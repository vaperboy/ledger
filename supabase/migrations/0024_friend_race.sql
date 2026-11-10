create table if not exists public.friend_race_scores (
  user_id uuid not null references public.profiles (id) on delete cascade,
  week int not null check (week between 1 and 10000000),
  growth numeric(9, 4) not null check (growth between -1 and 100),
  updated_at timestamptz not null default now(),
  primary key (user_id, week)
);

create table if not exists public.friend_goal_units (
  user_id uuid not null references public.profiles (id) on delete cascade,
  week int not null check (week between 1 and 10000000),
  units numeric(12, 0) not null check (units >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, week)
);

create table if not exists public.friend_goal_claims (
  user_id uuid not null references public.profiles (id) on delete cascade,
  week int not null check (week between 1 and 10000000),
  claimed_at timestamptz not null default now(),
  primary key (user_id, week)
);

create table if not exists public.friend_gifts (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  sender_name text not null,
  def_id text not null check (char_length(def_id) between 1 and 80),
  serial int not null check (serial >= 0),
  sent_day date not null default ((now() at time zone 'utc')::date),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  constraint friend_gift_not_self check (sender_id <> recipient_id)
);
create unique index if not exists friend_gifts_one_a_day on public.friend_gifts (sender_id, sent_day);
create index if not exists friend_gifts_inbox on public.friend_gifts (recipient_id) where accepted_at is null;

create table if not exists public.friend_notices (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  text text not null check (char_length(text) between 1 and 200),
  sent_day date not null default ((now() at time zone 'utc')::date),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create unique index if not exists friend_notices_once_a_day on public.friend_notices (sender_id, recipient_id, sent_day);
create index if not exists friend_notices_inbox on public.friend_notices (recipient_id) where read_at is null;

alter table public.friend_race_scores enable row level security;
alter table public.friend_goal_units enable row level security;
alter table public.friend_goal_claims enable row level security;
alter table public.friend_gifts enable row level security;
alter table public.friend_notices enable row level security;
revoke all on public.friend_race_scores, public.friend_goal_units, public.friend_goal_claims, public.friend_gifts, public.friend_notices from anon, authenticated;

create or replace function private.friend_week() returns int language sql stable security definer set search_path = '' as $$
  select ((((now() at time zone 'utc')::date) - date '0001-01-01') + 1) / 7;
$$;

create or replace function private.friend_ids(uid uuid) returns setof uuid language sql stable security definer set search_path = '' as $$
  select o.id
    from public.friendships f
    join public.profiles o on o.id = case when f.requester_id = uid then f.addressee_id else f.requester_id end
   where f.status = 'accepted' and (f.requester_id = uid or f.addressee_id = uid)
     and o.deleted_at is null and not o.is_bot and not private.is_blocked_between(uid, o.id);
$$;

create or replace function public.submit_race_score(p_week int, p_growth numeric) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); wk int := private.friend_week();
begin
  if p_week is null or p_growth is null or p_growth <> p_growth or p_week < wk - 3 or p_week > wk + 3 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  insert into public.friend_race_scores (user_id, week, growth) values (uid, p_week, round(least(100, greatest(-1, p_growth)), 4))
    on conflict (user_id, week) do update set growth = excluded.growth, updated_at = now();
end $$;

create or replace function public.read_race(p_week int) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.user_id, 'name', p.display_name, 'growth', s.growth) order by s.growth desc, p.display_name)
      from public.friend_race_scores s
      join public.profiles p on p.id = s.user_id
     where s.week = p_week and s.user_id in (select private.friend_ids(uid)) and p.privacy <> 'private'), '[]'::jsonb);
end $$;

create or replace function public.submit_goal_units(p_week int, p_units numeric) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); wk int := private.friend_week();
begin
  if p_week is null or p_units is null or p_units <> p_units or p_week < wk - 3 or p_week > wk + 3 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  insert into public.friend_goal_units (user_id, week, units) values (uid, p_week, round(least(1000000, greatest(0, p_units))))
    on conflict (user_id, week) do update set units = greatest(public.friend_goal_units.units, excluded.units), updated_at = now();
end $$;

create or replace function public.read_goal_units(p_week int) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((
    select jsonb_agg(coalesce(u.units, 0) order by f.id)
      from (select private.friend_ids(uid) as id) f
      left join public.friend_goal_units u on u.user_id = f.id and u.week = p_week), '[]'::jsonb);
end $$;

create or replace function public.claim_friend_goal(p_week int) returns boolean language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); mine numeric; mates numeric; members int; got int;
begin
  perform pg_advisory_xact_lock(hashtext('goal:' || uid::text));
  select coalesce(units, 0) into mine from public.friend_goal_units where user_id = uid and week = p_week;
  select coalesce(sum(u.units), 0), count(*) into mates, members
    from (select private.friend_ids(uid) as id) f
    left join public.friend_goal_units u on u.user_id = f.id and u.week = p_week;
  if coalesce(mine, 0) + mates < 300 * greatest(2, members + 1) then return false; end if;
  insert into public.friend_goal_claims (user_id, week) values (uid, p_week) on conflict do nothing;
  get diagnostics got = row_count;
  return got = 1;
end $$;

create or replace function public.send_friend_gift(p_to uuid, p_def_id text, p_serial int) returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); gid uuid;
begin
  if p_to is null or p_to = uid then raise exception 'cannot_target_self' using errcode = 'P0001'; end if;
  if p_def_id is null or char_length(p_def_id) not between 1 and 80 or p_serial is null or p_serial < 0 then raise exception 'invalid_gift' using errcode = 'P0001'; end if;
  if not exists (select 1 from private.friend_ids(uid) f where f = p_to) then raise exception 'not_found' using errcode = 'P0001'; end if;
  begin
    insert into public.friend_gifts (sender_id, recipient_id, sender_name, def_id, serial)
      values (uid, p_to, private.display_name(uid), p_def_id, p_serial) returning id into gid;
  exception when unique_violation then
    raise exception 'gift_limit' using errcode = 'P0001';
  end;
  return gid;
end $$;

create or replace function public.received_friend_gifts() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', g.id, 'fromName', g.sender_name, 'defID', g.def_id, 'serial', g.serial) order by g.created_at)
      from public.friend_gifts g where g.recipient_id = uid and g.accepted_at is null), '[]'::jsonb);
end $$;

create or replace function public.accept_friend_gifts(p_ids uuid[]) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  update public.friend_gifts set accepted_at = now() where recipient_id = uid and accepted_at is null and id = any (coalesce(p_ids, '{}'::uuid[]));
end $$;

create or replace function public.send_pass_notices(p_to uuid[]) returns int language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); me public.profiles; r uuid; n int := 0; got int;
begin
  select * into me from public.profiles where id = uid;
  foreach r in array (coalesce(p_to, '{}'::uuid[]))[1:50] loop
    continue when r = uid or private.is_blocked_between(uid, r);
    continue when not exists (select 1 from public.profiles o where o.id = r and o.deleted_at is null and not o.is_bot and o.adult_confirmed);
    continue when not (exists (select 1 from private.friend_ids(uid) f where f = r)
                       or exists (select 1 from public.leaderboard_entries e join public.profiles o on o.id = e.user_id where e.user_id = r and o.privacy = 'public'));
    insert into public.friend_notices (recipient_id, sender_id, text)
      values (r, uid, case when me.privacy = 'public' then me.display_name else 'A player' end || ' passed you in net worth.')
      on conflict do nothing;
    get diagnostics got = row_count;
    n := n + got;
  end loop;
  return n;
end $$;

create or replace function public.take_pass_notices() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); res jsonb;
begin
  with c as (
    update public.friend_notices set read_at = now()
     where recipient_id = uid and read_at is null and not private.is_blocked_between(uid, sender_id)
    returning text, created_at)
  select coalesce(jsonb_agg(text order by created_at), '[]'::jsonb) into res from c;
  return res;
end $$;

revoke execute on function public.submit_race_score(int, numeric), public.read_race(int), public.submit_goal_units(int, numeric), public.read_goal_units(int),
  public.claim_friend_goal(int), public.send_friend_gift(uuid, text, int), public.received_friend_gifts(), public.accept_friend_gifts(uuid[]),
  public.send_pass_notices(uuid[]), public.take_pass_notices() from public, anon;
grant execute on function public.submit_race_score(int, numeric), public.read_race(int), public.submit_goal_units(int, numeric), public.read_goal_units(int),
  public.claim_friend_goal(int), public.send_friend_gift(uuid, text, int), public.received_friend_gifts(), public.accept_friend_gifts(uuid[]),
  public.send_pass_notices(uuid[]), public.take_pass_notices() to authenticated;
