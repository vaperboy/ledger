create type public.player_event_kind as enum ('branchMilestone', 'wentViral', 'supplierMilestone', 'acquisition', 'newAssociation', 'seasonMilestone');

create table public.player_events (
  id uuid primary key default gen_random_uuid(),
  kind public.player_event_kind not null,
  player_id uuid not null references public.profiles (id) on delete cascade,
  trade text check (char_length(trade) <= 40),
  city text check (char_length(city) <= 60),
  company text check (char_length(company) <= 40),
  count int check (count between 1 and 100000000),
  other_name text check (char_length(other_name) <= 40),
  club text check (char_length(club) <= 80),
  dedupe_key text,
  created_at timestamptz not null default now()
);
create unique index player_events_dedupe on public.player_events (player_id, dedupe_key) where dedupe_key is not null;
create index player_events_recent on public.player_events (created_at desc);
create index player_events_player on public.player_events (player_id, created_at desc);

alter table public.player_events enable row level security;
revoke all on public.player_events from anon, authenticated;
grant select on public.player_events to authenticated;
create policy player_events_own on public.player_events for select to authenticated using (player_id = auth.uid());

create function private.publishes(uid uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = uid and deleted_at is null and privacy <> 'private');
$$;

create function private.post_event(uid uuid, k public.player_event_kind, p_trade text, p_city text, p_company text, p_count int, p_other text, p_club text, p_key text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.publishes(uid) then return; end if;
  insert into public.player_events (player_id, kind, trade, city, company, count, other_name, club, dedupe_key) values (uid, k, p_trade, p_city, p_company, p_count, p_other, p_club, p_key)
    on conflict do nothing;
end $$;

create function private.event_supply_milestone() returns trigger language plpgsql security definer set search_path = '' as $$
declare m bigint;
begin
  foreach m in array array[100, 500, 1000, 5000, 10000, 20000, 50000, 100000] loop
    if old.lifetime_units < m and new.lifetime_units >= m then
      perform private.post_event(new.owner_id, 'supplierMilestone', new.trade_id, new.city, new.company_name, m::int, null, null, 'supply:' || new.id || ':' || m);
    end if;
  end loop;
  return new;
end $$;
create trigger supply_listing_milestone after update of lifetime_units on public.supply_listings for each row execute function private.event_supply_milestone();

create function private.event_startup_viral() returns trigger language plpgsql security definer set search_path = '' as $$
declare s public.startups;
begin
  select * into s from public.startups where id = new.startup_id;
  if (select count(distinct investor_id) from public.startup_investments
       where startup_id = s.id and not refunded and created_at > now() - interval '7 days'
         and link_key <> private.link_key(s.founder_id) and investor_id <> s.founder_id) >= 5 then
    perform private.post_event(s.founder_id, 'wentViral', s.trade, null, s.name, null, null, null, 'viral:' || s.id);
  end if;
  return new;
end $$;
create trigger startup_investment_viral after insert on public.startup_investments for each row execute function private.event_startup_viral();

create function private.event_club_joined() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.post_event(new.owner_id, 'newAssociation', null, null, null, null, null, (select name from public.association_clubs where id = new.club_id), 'club:' || new.club_id || ':' || new.company_key);
  return new;
end $$;
create trigger association_member_joined after insert on public.association_members for each row execute function private.event_club_joined();

create function public.record_player_event(p_kind public.player_event_kind, p_trade text default null, p_city text default null, p_company text default null,
  p_count int default null, p_other text default null) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if p_kind not in ('branchMilestone', 'acquisition', 'seasonMilestone') then raise exception 'not_reportable' using errcode = 'P0001'; end if;
  if p_kind = 'branchMilestone' and (p_count is null or p_count < 2 or p_count > 1000 or (p_company is null and p_trade is null)) then raise exception 'invalid_event' using errcode = 'P0001'; end if;
  if p_kind = 'acquisition' and (p_other is null or (p_company is null and p_trade is null)) then raise exception 'invalid_event' using errcode = 'P0001'; end if;
  if p_kind = 'seasonMilestone' and (p_count is null or p_count < 1 or p_count > 1000) then raise exception 'invalid_event' using errcode = 'P0001'; end if;
  if (select count(*) from public.player_events where player_id = uid and created_at > now() - interval '1 day') >= 20 then raise exception 'rate_limited' using errcode = 'P0001'; end if;
  perform private.post_event(uid, p_kind, p_trade, p_city, p_company, p_count, p_other, null, p_kind || ':' || coalesce(p_company, p_trade, '') || ':' || coalesce(p_other, '') || ':' || coalesce(p_count::text, ''));
end $$;

create function public.news_feed(p_filter text default 'everyone', p_limit int default 50) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); my_country text; my_trades text[];
begin
  if p_filter not in ('everyone', 'friends', 'myTrade', 'myCountry') then raise exception 'invalid_filter' using errcode = 'P0001'; end if;
  select country_code into my_country from public.profiles where id = uid;
  select coalesce(array_agg(lower(trade)), '{}') into my_trades from public.companies_public where owner_id = uid;
  return coalesce((select jsonb_agg(r.j order by r.at desc) from (
    select e.created_at as at, jsonb_build_object('id', e.id, 'kind', e.kind, 'playerID', p.id, 'playerName', p.display_name, 'countryCode', p.country_code,
        'audience', case p.privacy when 'public' then 'everyone' else 'friends' end, 'day', (e.created_at at time zone 'utc')::date, 'trade', e.trade, 'city', e.city,
        'company', e.company, 'count', e.count, 'otherName', e.other_name, 'club', e.club, 'isFriend', private.are_friends(uid, p.id),
        'namesVisible', p.id = uid or private.are_friends(uid, p.id)) as j
      from (select * from public.player_events order by created_at desc limit 500) e
      join public.profiles p on p.id = e.player_id and p.deleted_at is null
     where (p.id = uid
            or (not private.is_blocked_between(uid, p.id)
                and (p.privacy = 'public' or (p.privacy = 'friends' and private.are_friends(uid, p.id)))))
       and (p_filter = 'everyone'
            or (p_filter = 'friends' and (p.id = uid or private.are_friends(uid, p.id)))
            or (p_filter = 'myTrade' and lower(e.trade) = any (my_trades))
            or (p_filter = 'myCountry' and p.country_code = my_country))
     order by e.created_at desc
     limit greatest(1, least(coalesce(p_limit, 50), 100))) r), '[]'::jsonb);
end $$;

create function private.run_news_cleanup() returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.player_events where created_at < now() - interval '30 days';
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.record_player_event(public.player_event_kind, text, text, text, int, text), public.news_feed(text, int) to authenticated;
