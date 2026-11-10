alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.profiles add column if not exists is_bot boolean not null default false;
create index if not exists profiles_last_seen on public.profiles (last_seen_at desc) where deleted_at is null;

create table if not exists public.account_signals (
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('device', 'ip')),
  hash text not null check (hash ~ '^[0-9a-f]{64}$'),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (user_id, kind, hash)
);
create index if not exists account_signals_hash on public.account_signals (kind, hash);
alter table public.account_signals enable row level security;
revoke all on public.account_signals from anon, authenticated;

create or replace function private.link_accounts(a uuid, b uuid) returns void language plpgsql security definer set search_path = '' as $$
declare ka text; kb text;
begin
  select link_key into ka from public.profiles where id = a;
  select link_key into kb from public.profiles where id = b;
  if ka is null or kb is null or ka = kb then return; end if;
  update public.profiles set link_key = ka where link_key = kb;
  update public.startup_investments i set link_key = ka where i.link_key = kb;
  update public.startup_holdings h set link_key = ka where h.link_key = kb;
  update public.supply_contracts c set ended_at = now(), end_reason = 'stopped', acknowledged = false
   where c.ended_at is null and private.linked(c.buyer_id, c.supplier_id);
  update public.exchange_orders o set status = 'cancelled'
   where o.status = 'open' and exists (select 1 from public.exchange_listings l where l.id = o.listing_id and private.linked(l.owner_id, o.trader_id));
end $$;

create or replace function private.shares_network(a uuid, b uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.account_signals x join public.account_signals y on y.kind = x.kind and y.hash = x.hash
     where x.user_id = a and y.user_id = b and x.kind = 'ip'
       and x.last_seen > now() - interval '7 days' and y.last_seen > now() - interval '7 days');
$$;

create or replace function public.register_device(p_device text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); h text; ip text; other uuid; linked_now int := 0;
begin
  if p_device is null or char_length(p_device) not between 8 and 200 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  h := encode(extensions.digest('ledger.device:' || p_device, 'sha256'), 'hex');
  insert into public.account_signals (user_id, kind, hash) values (uid, 'device', h)
    on conflict (user_id, kind, hash) do update set last_seen = now();
  ip := split_part(coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for', ''), ',', 1);
  if ip <> '' then
    insert into public.account_signals (user_id, kind, hash) values (uid, 'ip', encode(extensions.digest('ledger.ip:' || trim(ip), 'sha256'), 'hex'))
      on conflict (user_id, kind, hash) do update set last_seen = now();
  end if;
  for other in select distinct s.user_id from public.account_signals s join public.profiles p on p.id = s.user_id and p.deleted_at is null
                where s.kind = 'device' and s.hash = h and s.user_id <> uid loop
    if not private.linked(uid, other) then
      perform private.link_accounts(uid, other);
      linked_now := linked_now + 1;
    end if;
  end loop;
  return jsonb_build_object('linked', linked_now);
end $$;

create table if not exists public.player_activity (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('joined', 'levelUp', 'exchangeListed', 'auctionSold', 'officeOpened', 'tradeMilestone')),
  count int check (count between 1 and 100000000),
  label text check (char_length(label) <= 60),
  dedupe_key text,
  created_at timestamptz not null default now()
);
create unique index if not exists player_activity_dedupe on public.player_activity (player_id, dedupe_key) where dedupe_key is not null;
create index if not exists player_activity_recent on public.player_activity (created_at desc);
create index if not exists player_activity_player on public.player_activity (player_id, created_at desc);
alter table public.player_activity enable row level security;
revoke all on public.player_activity from anon, authenticated;
grant select on public.player_activity to authenticated;
drop policy if exists player_activity_own on public.player_activity;
create policy player_activity_own on public.player_activity for select to authenticated using (player_id = auth.uid());

create or replace function private.log_activity(uid uuid, k text, n int, lbl text, dkey text) returns void language sql security definer set search_path = '' as $$
  insert into public.player_activity (player_id, kind, count, label, dedupe_key) values (uid, k, n, left(lbl, 60), dkey) on conflict do nothing;
$$;

create or replace function private.activity_profile() returns trigger language plpgsql security definer set search_path = '' as $$
declare m int;
begin
  if new.adult_confirmed and (tg_op = 'INSERT' or not old.adult_confirmed) then
    perform private.log_activity(new.id, 'joined', null, null, 'joined');
  end if;
  if tg_op = 'UPDATE' and new.adult_confirmed then
    if new.level > old.level then perform private.log_activity(new.id, 'levelUp', new.level, null, 'level:' || new.level); end if;
    foreach m in array array[10, 50, 100, 500, 1000, 5000] loop
      if old.trades_completed < m and new.trades_completed >= m then perform private.log_activity(new.id, 'tradeMilestone', m, null, 'trades:' || m); end if;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists profiles_activity on public.profiles;
create trigger profiles_activity after insert or update of level, trades_completed, adult_confirmed on public.profiles
  for each row execute function private.activity_profile();

create or replace function private.activity_listing() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.log_activity(new.owner_id, 'exchangeListed', null, new.name, 'listed:' || new.id);
  return new;
end $$;
drop trigger if exists exchange_listing_activity on public.exchange_listings;
create trigger exchange_listing_activity after insert on public.exchange_listings for each row execute function private.activity_listing();

create or replace function private.activity_office() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.log_activity(new.owner_id, 'officeOpened', null, new.name, 'office:' || new.id);
  return new;
end $$;
drop trigger if exists accountant_office_activity on public.accountant_offices;
create trigger accountant_office_activity after insert on public.accountant_offices for each row execute function private.activity_office();

create or replace function public.friend_activity(p_limit int default 40) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); n int := least(greatest(coalesce(p_limit, 40), 1), 100);
begin
  return jsonb_build_object(
    'activity', coalesce((select jsonb_agg(x.j order by x.at desc) from (
        select a.created_at as at, jsonb_build_object('id', a.id, 'playerID', p.id, 'playerName', p.display_name, 'kind', a.kind, 'count', a.count,
               'label', a.label, 'at', extract(epoch from a.created_at)) as j
          from public.player_activity a join public.profiles p on p.id = a.player_id and p.deleted_at is null
         where private.are_friends(uid, p.id) and p.privacy <> 'private' and not private.is_blocked_between(uid, p.id)
         order by a.created_at desc limit n) x), '[]'::jsonb),
    'presence', coalesce((select jsonb_agg(jsonb_build_object('playerID', p.id, 'lastSeen', extract(epoch from p.last_seen_at),
               'online', coalesce(p.last_seen_at > now() - interval '5 minutes', false)))
          from public.profiles p where p.deleted_at is null and private.are_friends(uid, p.id) and p.privacy <> 'private'
           and not private.is_blocked_between(uid, p.id)), '[]'::jsonb));
end $$;

create or replace function private.profile_json(viewer uuid, target uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare p public.profiles; rel text; is_self boolean; is_friend boolean; see_level boolean; see_detail boolean; see_companies boolean; see_presence boolean;
        n int; comps jsonb;
begin
  select * into p from public.profiles where id = target and deleted_at is null;
  if not found then return null; end if;
  rel := private.relation(viewer, target);
  is_self := rel = 'you'; is_friend := rel = 'friend';
  see_level := is_self or p.privacy in ('public', 'friends');
  see_detail := is_self or p.privacy = 'public' or (p.privacy = 'friends' and is_friend);
  see_companies := is_self or (is_friend and p.privacy <> 'private');
  see_presence := is_self or (is_friend and p.privacy <> 'private');
  select count(*) into n from public.companies_public where owner_id = target;
  select coalesce(jsonb_agg(jsonb_build_object('id', company_key, 'name', name, 'trade', trade, 'city', city,
           'countryCode', country, 'health', health) order by name), '[]'::jsonb) into comps
    from public.companies_public where owner_id = target;
  return jsonb_build_object(
    'id', p.id, 'code', p.code, 'avatarIcon', p.avatar_icon, 'displayName', p.display_name, 'avatarColour', p.avatar_colour, 'countryCode', p.country_code,
    'level', case when see_level then to_jsonb(p.level) else 'null'::jsonb end,
    'badges', case when see_level then to_jsonb(p.badges) else '[]'::jsonb end,
    'privacy', case p.privacy when 'public' then 'everyone' when 'friends' then 'friends' else 'onlyMe' end,
    'companyCount', case when see_detail then to_jsonb(n) else 'null'::jsonb end,
    'companies', case when see_companies then comps else 'null'::jsonb end,
    'gameWeek', case when see_detail then to_jsonb(p.game_week) else 'null'::jsonb end,
    'tradesCompleted', case when see_detail then to_jsonb(p.trades_completed) else 'null'::jsonb end,
    'lastSeen', case when see_presence and p.last_seen_at is not null then to_jsonb(extract(epoch from p.last_seen_at)) else 'null'::jsonb end,
    'relation', rel);
end $$;

create or replace function public.send_friend_request(p_target uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); f public.friendships;
begin
  if p_target = uid then raise exception 'cannot_target_self' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.profiles where id = p_target and deleted_at is null and not is_bot) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if private.is_blocked_between(uid, p_target) then raise exception 'blocked' using errcode = 'P0001'; end if;
  select * into f from public.friendships
   where (requester_id = uid and addressee_id = p_target) or (requester_id = p_target and addressee_id = uid);
  if found then
    if f.status = 'accepted' then raise exception 'already_friends' using errcode = 'P0001'; end if;
    if f.requester_id = uid then raise exception 'request_pending' using errcode = 'P0001'; end if;
    update public.friendships set status = 'accepted', responded_at = now() where id = f.id;
    return;
  end if;
  insert into public.friendships (requester_id, addressee_id) values (uid, p_target);
end $$;

create or replace function public.search_players(p_query text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); q text := trim(coalesce(p_query, '')); pat text; res jsonb;
begin
  if char_length(q) < 2 then return '[]'::jsonb; end if;
  pat := '%' || replace(replace(replace(lower(q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  select coalesce(jsonb_agg(private.profile_json(uid, x.id) order by x.display_name), '[]'::jsonb) into res from (
    select p.id, p.display_name from public.profiles p
     where p.deleted_at is null and not p.is_bot and p.id <> uid and not private.is_blocked_between(uid, p.id)
       and (lower(p.display_name) like pat or p.code = upper(q))
     order by p.display_name limit 20) x;
  return res;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.register_device(text), public.friend_activity(int) to authenticated;
