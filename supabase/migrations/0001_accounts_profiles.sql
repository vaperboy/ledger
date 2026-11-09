-- Accounts, profiles, friends, blocks, reports and cloud saves.
-- Privacy is enforced here: clients read other players only through the SECURITY DEFINER functions below, which return exactly
-- the fields the viewer may see (hidden fields come back null). Clients never write level, week or companies directly.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create type public.privacy_level as enum ('public', 'friends', 'private');
create type public.company_health as enum ('new', 'struggling', 'steady', 'growing', 'thriving');
create type public.friendship_status as enum ('pending', 'accepted');
create type public.report_status as enum ('open', 'reviewed', 'dismissed');

-- Shareable code like K7M-4PQ2 (no 0/O/1/I/L).
create function private.new_code() returns text language plpgsql volatile as $$
declare chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; s text := ''; i int;
begin
  for i in 1..7 loop s := s || substr(chars, 1 + floor(random() * length(chars))::int, 1); end loop;
  return substr(s, 1, 3) || '-' || substr(s, 4, 4);
end $$;

-- Display-name rules, mirroring the app's ProfileRules (blocklist and reserved words after undoing look-alike characters).
create function private.name_problem(n text) returns text language plpgsql immutable as $$
declare flat text; w text;
begin
  flat := translate(lower(n), '0134578@$', 'oieatsass');
  flat := regexp_replace(flat, '[^a-z0-9]', '', 'g');
  foreach w in array array['fuck','shit','cunt','nazi','bitch','whore','rape','nigg','fagg'] loop
    if position(w in flat) > 0 then return 'That name is not allowed.'; end if;
  end loop;
  foreach w in array array['admin','moderator','ledger','support','staff','official'] loop
    if position(w in flat) > 0 then return 'That name is reserved.'; end if;
  end loop;
  if position('http' in flat) > 0 or position('www' in flat) > 0 then return 'A name cannot be a web address.'; end if;
  return null;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  code text not null unique default private.new_code(),
  display_name text not null
    constraint display_name_length check (char_length(display_name) between 2 and 20)
    constraint display_name_chars check (display_name ~ '^[[:alpha:][:digit:] ._''-]+$' and display_name ~ '[[:alpha:]]'),
  avatar_colour int not null default 0 check (avatar_colour between 0 and 7),
  country_code text not null default 'US' check (country_code ~ '^[A-Z]{2}$'),
  level int not null default 1 check (level between 0 and 1000),
  badges text[] not null default '{}' check (cardinality(badges) <= 64),
  privacy public.privacy_level not null default 'public',
  game_week int not null default 0 check (game_week >= 0),
  trades_completed int not null default 0 check (trades_completed >= 0),
  is_simulated boolean not null default false,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.companies_public (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  company_key text not null check (char_length(company_key) between 1 and 64),
  name text not null check (char_length(name) between 1 and 40),
  trade text not null check (char_length(trade) <= 40),
  city text not null check (char_length(city) <= 60),
  country text not null check (country ~ '^[A-Z]{2}$'),
  health public.company_health not null default 'new',
  updated_at timestamptz not null default now(),
  primary key (owner_id, company_key)
);

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status public.friendship_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint friendship_not_self check (requester_id <> addressee_id)
);
-- One row per unordered pair, whichever direction asked first.
create unique index friendships_pair_key on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint block_not_self check (blocker_id <> blocked_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles (id) on delete set null,
  target_id uuid references public.profiles (id) on delete set null,
  reason text not null check (reason in ('offensiveName','impersonation','harassment','cheating','spam','other')),
  note text not null default '' check (char_length(note) <= 500),
  status public.report_status not null default 'open',
  created_at timestamptz not null default now()
);

-- Cloud saves: the app encrypts the save on the device and uploads base64 text; the platform also encrypts the disk at rest.
create table public.save_blobs (
  user_id uuid not null references public.profiles (id) on delete cascade,
  slot int not null check (slot between 0 and 9),
  payload text not null check (char_length(payload) <= 8000000),
  version int not null default 1,
  updated_at timestamptz not null default now(),
  primary key (user_id, slot)
);

-- Index plan: profiles(code) is unique-indexed; name search uses a trigram index; friendship lookups by either side; blocks by blocked side.
create extension if not exists pg_trgm with schema extensions;
create index profiles_name_trgm on public.profiles using gin (lower(display_name) extensions.gin_trgm_ops) where deleted_at is null;
create index friendships_requester on public.friendships (requester_id, status);
create index friendships_addressee on public.friendships (addressee_id, status);
create index blocks_blocked on public.blocks (blocked_id);
create index reports_open on public.reports (status, created_at) where status = 'open';

-- Name rules on every write of display_name (simulated seed players are exempt).
create function private.check_name() returns trigger language plpgsql as $$
declare why text;
begin
  if new.is_simulated or new.display_name = 'Deleted player' then return new; end if;
  why := private.name_problem(new.display_name);
  if why is not null then raise exception 'name_rejected: %', why using errcode = 'P0001'; end if;
  return new;
end $$;
create trigger profiles_check_name before insert or update of display_name on public.profiles
  for each row execute function private.check_name();

-- Blocking someone ends any friendship or request between the pair.
create function private.drop_friendship_on_block() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.friendships
   where (requester_id = new.blocker_id and addressee_id = new.blocked_id) or (requester_id = new.blocked_id and addressee_id = new.blocker_id);
  return new;
end $$;
create trigger blocks_drop_friendship after insert on public.blocks for each row execute function private.drop_friendship_on_block();

-- ---------------------------------------------------------------------------------------------------------------------
-- Row Level Security: the direct table surface. Cross-player reads go through the functions further down.
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.companies_public enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.save_blobs enable row level security;

-- Column grants: a client can change only these profile columns; level, week, trades, badges and is_simulated are server-set.
revoke all on public.profiles, public.companies_public, public.friendships, public.blocks, public.reports, public.save_blobs from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, avatar_colour, country_code, privacy) on public.profiles to authenticated;
grant select on public.companies_public to authenticated;
grant select, delete on public.friendships to authenticated;
grant select, insert, delete on public.blocks to authenticated;
grant insert on public.reports to authenticated;
grant select, insert, update, delete on public.save_blobs to authenticated;

-- profiles: you read only your own row directly (others' fields are filtered by view_profile and the search functions).
create policy profiles_select_own on public.profiles for select to authenticated using (id = auth.uid() and deleted_at is null);
-- profiles: you edit only your own row, and only the granted columns.
create policy profiles_update_own on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- companies_public: the owner reads their own rows; writes happen only inside share_progress; others see them through profile_json.
create policy companies_select_own on public.companies_public for select to authenticated using (owner_id = auth.uid());

-- friendships: either side sees the row; creation and acceptance go through RPCs so nobody can forge a pair.
create policy friendships_select_party on public.friendships for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());
-- friendships: either side may delete (cancel, decline or unfriend).
create policy friendships_delete_party on public.friendships for delete to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- blocks: you see, add and remove only your own blocks (the blocked player cannot see that they are blocked).
create policy blocks_select_own on public.blocks for select to authenticated using (blocker_id = auth.uid());
create policy blocks_insert_own on public.blocks for insert to authenticated with check (blocker_id = auth.uid());
create policy blocks_delete_own on public.blocks for delete to authenticated using (blocker_id = auth.uid());

-- reports: insert-only as yourself; no policy lets a client read them back (staff use the dashboard).
create policy reports_insert_own on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'open');

-- save_blobs: full control of your own saves only.
create policy saves_own on public.save_blobs for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------------------------------------------------
-- Helpers (private schema: not callable by clients)
-- ---------------------------------------------------------------------------------------------------------------------
create function private.is_blocked_between(a uuid, b uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.blocks where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;
create function private.are_friends(a uuid, b uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.friendships where status = 'accepted'
                  and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a)));
$$;
create function private.relation(viewer uuid, target uuid) returns text language sql stable security definer set search_path = '' as $$
  select case
    when viewer = target then 'you'
    when exists (select 1 from public.blocks where blocker_id = viewer and blocked_id = target) then 'blocked'
    when private.are_friends(viewer, target) then 'friend'
    when exists (select 1 from public.friendships where status = 'pending' and requester_id = viewer and addressee_id = target) then 'requestSent'
    when exists (select 1 from public.friendships where status = 'pending' and requester_id = target and addressee_id = viewer) then 'requestReceived'
    else 'none' end;
$$;

-- The one place that decides what a viewer sees. Output keys match the app's PlayerProfile; hidden fields are JSON null.
-- Public: name, level, badges, company count, week, trades (companies for friends). Friends: name, level, badges (rest for friends). Private: name only.
create function private.profile_json(viewer uuid, target uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare p public.profiles; rel text; is_self boolean; is_friend boolean; see_level boolean; see_detail boolean; see_companies boolean;
        n int; comps jsonb;
begin
  select * into p from public.profiles where id = target and deleted_at is null;
  if not found then return null; end if;
  rel := private.relation(viewer, target);
  is_self := rel = 'you'; is_friend := rel = 'friend';
  see_level := is_self or p.privacy in ('public', 'friends');
  see_detail := is_self or p.privacy = 'public' or (p.privacy = 'friends' and is_friend);
  see_companies := is_self or (is_friend and p.privacy <> 'private');
  select count(*) into n from public.companies_public where owner_id = target;
  select coalesce(jsonb_agg(jsonb_build_object('id', company_key, 'name', name, 'trade', trade, 'city', city,
           'countryCode', country, 'health', health) order by name), '[]'::jsonb) into comps
    from public.companies_public where owner_id = target;
  return jsonb_build_object(
    'id', p.id, 'code', p.code, 'displayName', p.display_name, 'avatarColour', p.avatar_colour, 'countryCode', p.country_code,
    'level', case when see_level then to_jsonb(p.level) else 'null'::jsonb end,
    'badges', case when see_level then to_jsonb(p.badges) else '[]'::jsonb end,
    'privacy', case p.privacy when 'public' then 'everyone' when 'friends' then 'friends' else 'onlyMe' end,
    'companyCount', case when see_detail then to_jsonb(n) else 'null'::jsonb end,
    'companies', case when see_companies then comps else 'null'::jsonb end,
    'isSimulated', p.is_simulated,
    'gameWeek', case when see_detail then to_jsonb(p.game_week) else 'null'::jsonb end,
    'tradesCompleted', case when see_detail then to_jsonb(p.trades_completed) else 'null'::jsonb end,
    'relation', rel);
end $$;

create function private.require_user() returns uuid language plpgsql stable as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  return uid;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- RPC functions (the client surface). Errors are raised as short codes the app maps to OnlineError.
-- ---------------------------------------------------------------------------------------------------------------------
-- Creates the caller's profile on first sign-in (idempotent). Anonymous guests have no profile.
create function public.ensure_profile() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); anon boolean;
begin
  select coalesce(is_anonymous, false) into anon from auth.users where id = uid;
  if anon then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  insert into public.profiles (id, display_name) values (uid, 'Player ' || upper(substr(md5(uid::text), 1, 4)))
    on conflict (id) do nothing;
  return private.profile_json(uid, uid);
end $$;

-- A profile as the caller may see it; null id means the caller. Someone who blocked the caller looks like "not found".
create function public.view_profile(p_id uuid default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); target uuid := coalesce(p_id, uid); j jsonb;
begin
  if target <> uid and exists (select 1 from public.blocks where blocker_id = target and blocked_id = uid) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  j := private.profile_json(uid, target);
  if j is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  return j;
end $$;

create function public.profile_by_code(p_code text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); target uuid;
begin
  select id into target from public.profiles where code = upper(trim(p_code)) and deleted_at is null;
  if target is null or (target <> uid and private.is_blocked_between(uid, target)) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  return private.profile_json(uid, target);
end $$;

-- Name substring or exact code; never the caller or anyone blocked in either direction; at most 20 rows.
create function public.search_players(p_query text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); q text := trim(coalesce(p_query, '')); pat text; res jsonb;
begin
  if char_length(q) < 2 then return '[]'::jsonb; end if;
  pat := '%' || replace(replace(replace(lower(q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  select coalesce(jsonb_agg(private.profile_json(uid, x.id) order by x.display_name), '[]'::jsonb) into res from (
    select p.id, p.display_name from public.profiles p
     where p.deleted_at is null and p.id <> uid and not private.is_blocked_between(uid, p.id)
       and (lower(p.display_name) like pat or p.code = upper(q))
     order by p.display_name limit 20) x;
  return res;
end $$;

create function public.send_friend_request(p_target uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); f public.friendships;
begin
  if p_target = uid then raise exception 'cannot_target_self' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.profiles where id = p_target and deleted_at is null) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if private.is_blocked_between(uid, p_target) then raise exception 'blocked' using errcode = 'P0001'; end if;
  select * into f from public.friendships
   where (requester_id = uid and addressee_id = p_target) or (requester_id = p_target and addressee_id = uid);
  if found then
    if f.status = 'accepted' then raise exception 'already_friends' using errcode = 'P0001'; end if;
    if f.requester_id = uid then raise exception 'request_pending' using errcode = 'P0001'; end if;
    update public.friendships set status = 'accepted', responded_at = now() where id = f.id;   -- they had asked us first
    return;
  end if;
  insert into public.friendships (requester_id, addressee_id) values (uid, p_target);
end $$;

create function public.accept_friend_request(p_from uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); n int;
begin
  update public.friendships set status = 'accepted', responded_at = now()
   where requester_id = p_from and addressee_id = uid and status = 'pending';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_found' using errcode = 'P0001'; end if;
end $$;

-- Friends plus incoming and outgoing requests, shaped as the app's FriendsOverview.
create function public.my_friends() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  return jsonb_build_object(
    'friends', coalesce((select jsonb_agg(private.profile_json(uid, case when requester_id = uid then addressee_id else requester_id end))
        from public.friendships where status = 'accepted' and (requester_id = uid or addressee_id = uid)), '[]'::jsonb),
    'incoming', coalesce((select jsonb_agg(jsonb_build_object('player', private.profile_json(uid, requester_id), 'sentAt', created_at))
        from public.friendships where status = 'pending' and addressee_id = uid), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(jsonb_build_object('player', private.profile_json(uid, addressee_id), 'sentAt', created_at))
        from public.friendships where status = 'pending' and requester_id = uid), '[]'::jsonb));
end $$;

create function public.blocked_players() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  return coalesce((select jsonb_agg(private.profile_json(uid, blocked_id)) from public.blocks where blocker_id = uid), '[]'::jsonb);
end $$;

-- The only way level, week, trades, badges and companies change: validated here, never trusted from a client column write.
-- Null arguments leave a field as it is; p_companies replaces the whole list.
create function public.share_progress(p_level int default null, p_badges text[] default null, p_game_week int default null,
                                      p_trades_completed int default null, p_companies jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); c jsonb; b text;
begin
  if not exists (select 1 from public.profiles where id = uid and deleted_at is null) then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if p_level is not null and p_level not between 0 and 1000 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
  if p_game_week is not null and p_game_week < 0 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
  if p_trades_completed is not null and p_trades_completed < 0 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
  if p_badges is not null then
    if cardinality(p_badges) > 64 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
    foreach b in array p_badges loop
      if b is null or char_length(b) not between 1 and 40 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
    end loop;
  end if;
  if p_companies is not null then
    if jsonb_typeof(p_companies) <> 'array' or jsonb_array_length(p_companies) > 50 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
    for c in select * from jsonb_array_elements(p_companies) loop
      if coalesce(c->>'id', '') = '' or coalesce(c->>'name', '') = ''
         or not ((c->>'health') = any (enum_range(null::public.company_health)::text[])) then
        raise exception 'invalid_progress' using errcode = 'P0001';
      end if;
    end loop;
  end if;
  update public.profiles set
      level = coalesce(p_level, level), badges = coalesce(p_badges, badges), game_week = coalesce(p_game_week, game_week),
      trades_completed = coalesce(p_trades_completed, trades_completed)
   where id = uid;
  if p_companies is not null then
    delete from public.companies_public where owner_id = uid;
    insert into public.companies_public (owner_id, company_key, name, trade, city, country, health)
      select uid, e->>'id', e->>'name', coalesce(e->>'trade', ''), coalesce(e->>'city', ''), coalesce(e->>'countryCode', 'US'),
             (e->>'health')::public.company_health
        from jsonb_array_elements(p_companies) e;
  end if;
  return private.profile_json(uid, uid);
end $$;

-- Everything held about the caller, for the "export my data" screen.
create function public.export_my_data() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  return jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where id = uid),
    'companies', coalesce((select jsonb_agg(to_jsonb(c)) from public.companies_public c where owner_id = uid), '[]'::jsonb),
    'friendships', coalesce((select jsonb_agg(to_jsonb(f)) from public.friendships f where requester_id = uid or addressee_id = uid), '[]'::jsonb),
    'blocks', coalesce((select jsonb_agg(to_jsonb(b)) from public.blocks b where blocker_id = uid), '[]'::jsonb),
    'saves', coalesce((select jsonb_agg(jsonb_build_object('slot', slot, 'version', version, 'updatedAt', updated_at))
                         from public.save_blobs where user_id = uid), '[]'::jsonb));
end $$;

-- HOOK: the supply-contract migration replaces this body with a real check; deletion is refused while it returns true.
create function private.has_open_obligations(uid uuid) returns boolean language sql stable as $$ select false; $$;

-- Soft delete (marks the row for the rest of the transaction), then hard delete of the auth user, which cascades to every table above.
create function public.delete_my_account() returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  if private.has_open_obligations(uid) then raise exception 'open_contracts' using errcode = 'P0001'; end if;
  update public.profiles set deleted_at = now(), display_name = 'Deleted player' where id = uid;
  delete from auth.users where id = uid;
end $$;

-- Execute rights: only signed-in users call the client functions; everything in `private` stays closed.
revoke execute on all functions in schema public from public, anon;
grant execute on function public.ensure_profile(), public.view_profile(uuid), public.profile_by_code(text), public.search_players(text),
  public.send_friend_request(uuid), public.accept_friend_request(uuid), public.my_friends(), public.blocked_players(),
  public.share_progress(int, text[], int, int, jsonb), public.export_my_data(), public.delete_my_account() to authenticated;
