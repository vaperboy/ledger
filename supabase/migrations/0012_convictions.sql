-- Convictions: what staff record against a player after a report (see reports in 0001). A conviction can carry a fine (paid to the
-- player's country treasury) and bans from trading, standing for office, voting and gold use. Only staff (the service role) create or
-- quash one; a player reads their own, and other players see only how many unquashed convictions a candidate has. The ban check
-- replaces the stub every money and vote function already calls.

create type public.conviction_kind as enum ('cheating', 'harassment', 'fraud', 'impersonation', 'spam', 'other');

create table public.convictions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles (id) on delete cascade,
  kind public.conviction_kind not null,
  summary text not null check (char_length(summary) between 1 and 500),
  fine numeric(18, 2) not null default 0 check (fine >= 0),
  currency text check (currency ~ '^[A-Z]{3}$'),
  trade_ban_until timestamptz,
  office_ban_until timestamptz,
  vote_ban_until timestamptz,
  gold_ban_until timestamptz,
  report_id uuid references public.reports (id) on delete set null,
  created_at timestamptz not null default now(),
  quashed_at timestamptz,
  constraint fine_has_currency check (fine = 0 or currency is not null)
);
create index convictions_player on public.convictions (player_id) where quashed_at is null;

alter table public.convictions enable row level security;
revoke all on public.convictions from anon, authenticated;
grant select on public.convictions to authenticated;
create policy convictions_own on public.convictions for select to authenticated using (player_id = auth.uid());

-- Replaces the stub from 0002. A ban holds while its end lies in the future and the conviction has not been quashed.
create or replace function private.is_barred(uid uuid, scope text) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.convictions c where c.player_id = uid and c.quashed_at is null and
    case scope when 'trade' then c.trade_ban_until when 'stand' then c.office_ban_until when 'vote' then c.vote_ban_until when 'gold' then c.gold_ban_until end > now());
$$;

-- Unquashed convictions, as a count other players may see (a candidate's record on the ballot).
create or replace function private.conviction_count(uid uuid) returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.convictions where player_id = uid and quashed_at is null;
$$;

-- A president convicted of anything that bars them from office loses the seat at once.
create function private.convicted_loses_office() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.quashed_at is null and new.office_ban_until > now() then
    update public.country_offices set holder_id = null where holder_id = new.player_id;
  end if;
  return new;
end $$;
create trigger convictions_office after insert on public.convictions for each row execute function private.convicted_loses_office();

-- Staff record a conviction (service role only). The fine becomes a settlement and goes to the player's country treasury; the report, if
-- given, is marked reviewed. Ban lengths are in days; zero or null means no ban of that kind.
create function public.record_conviction(p_player uuid, p_kind public.conviction_kind, p_summary text, p_fine numeric default 0, p_currency text default null,
  p_trade_ban_days int default null, p_office_ban_days int default null, p_vote_ban_days int default null, p_gold_ban_days int default null, p_report uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare cid uuid; cc text;
begin
  if not exists (select 1 from public.profiles where id = p_player) then raise exception 'not_found' using errcode = 'P0001'; end if;
  insert into public.convictions (player_id, kind, summary, fine, currency, trade_ban_until, office_ban_until, vote_ban_until, gold_ban_until, report_id)
    values (p_player, p_kind, p_summary, coalesce(p_fine, 0), p_currency,
            case when coalesce(p_trade_ban_days, 0) > 0 then now() + make_interval(days => p_trade_ban_days) end,
            case when coalesce(p_office_ban_days, 0) > 0 then now() + make_interval(days => p_office_ban_days) end,
            case when coalesce(p_vote_ban_days, 0) > 0 then now() + make_interval(days => p_vote_ban_days) end,
            case when coalesce(p_gold_ban_days, 0) > 0 then now() + make_interval(days => p_gold_ban_days) end, p_report) returning id into cid;
  if coalesce(p_fine, 0) > 0 then
    perform private.settle(p_player, -p_fine, p_currency, 'conviction_fine', cid::text, 'Fine: ' || p_summary, jsonb_build_object('convictionID', cid));
    select country_code into cc from public.profiles where id = p_player;
    perform private.treasury_post(cc, p_fine, 'conviction_fine', cid::text);
  end if;
  if p_report is not null then update public.reports set status = 'reviewed' where id = p_report; end if;
  -- Orders the player left standing on the exchange come off the book.
  if coalesce(p_trade_ban_days, 0) > 0 then update public.exchange_orders set status = 'cancelled' where trader_id = p_player and status = 'open'; end if;
  return cid;
end $$;

-- A conviction overturned on appeal: its bans lapse at once. The fine is returned as a settlement.
create function public.quash_conviction(p_conviction uuid) returns void language plpgsql security definer set search_path = '' as $$
declare c public.convictions; cc text;
begin
  select * into c from public.convictions where id = p_conviction and quashed_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  update public.convictions set quashed_at = now() where id = c.id;
  if c.fine > 0 then
    perform private.settle(c.player_id, c.fine, c.currency, 'conviction_refund', c.id::text, 'Fine returned: conviction quashed', jsonb_build_object('convictionID', c.id));
    select country_code into cc from public.profiles where id = c.player_id;
    perform private.treasury_post(cc, -c.fine, 'conviction_refund', c.id::text);
  end if;
end $$;

create function public.my_convictions() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'summary', summary, 'fine', fine, 'currency', currency,
      'tradeBanUntil', trade_ban_until, 'officeBanUntil', office_ban_until, 'voteBanUntil', vote_ban_until, 'goldBanUntil', gold_ban_until,
      'quashed', quashed_at is not null, 'createdAt', created_at) order by created_at desc) from public.convictions where player_id = uid), '[]'::jsonb);
end $$;

-- What other players may know of someone: only how many standing convictions they have.
create function public.conviction_count_of(p_player uuid) returns int language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if private.is_blocked_between(uid, p_player) then raise exception 'not_found' using errcode = 'P0001'; end if;
  return private.conviction_count(p_player);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.my_convictions(), public.conviction_count_of(uuid) to authenticated;
revoke execute on function public.record_conviction(uuid, public.conviction_kind, text, numeric, text, int, int, int, int, uuid), public.quash_conviction(uuid) from authenticated;
grant execute on function public.record_conviction(uuid, public.conviction_kind, text, numeric, text, int, int, int, int, uuid), public.quash_conviction(uuid) to service_role;
