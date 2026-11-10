alter table public.profiles add column username text
  constraint username_shape check (username is null or username ~ '^[A-Za-z][A-Za-z0-9_]{2,15}$');
create unique index profiles_username_unique on public.profiles (lower(username)) where username is not null;

create table public.username_reservations (
  name_key text primary key check (name_key = lower(name_key)),
  owner_id uuid not null,
  claimed_at timestamptz not null default now()
);
alter table public.username_reservations enable row level security;
revoke all on public.username_reservations from anon, authenticated;

insert into public.username_reservations (name_key, owner_id)
  select lower(username), id from public.profiles where username is not null on conflict do nothing;

create function private.username_ok(n text) returns boolean language sql immutable as $$
  select n is not null and n ~ '^[A-Za-z][A-Za-z0-9_]{2,15}$' and private.name_problem(n) is null;
$$;

create function private.username_state(uid uuid, n text) returns text language plpgsql stable security definer set search_path = '' as $$
declare k text := lower(coalesce(n, '')); held uuid;
begin
  if not private.username_ok(n) then return 'invalid'; end if;
  select owner_id into held from public.username_reservations where name_key = k;
  if found and held <> uid then return 'taken'; end if;
  if exists (select 1 from public.profiles where lower(display_name) = k and id <> uid and deleted_at is null) then return 'taken'; end if;
  return 'ok';
end $$;

create function public.username_available(p_username text) returns text language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  return private.username_state(uid, btrim(p_username));
end $$;

create function public.claim_username(p_username text) returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); n text := btrim(p_username); st text;
begin
  st := private.username_state(uid, n);
  if st <> 'ok' then return st; end if;
  begin
    insert into public.username_reservations (name_key, owner_id) values (lower(n), uid) on conflict (name_key) do nothing;
    update public.profiles set username = n, display_name = n where id = uid and deleted_at is null;
  exception when unique_violation then
    return 'taken';
  end;
  return 'ok';
end $$;

create or replace function public.update_my_profile(p_display_name text default null, p_avatar_colour int default null, p_country_code text default null,
                                                    p_privacy public.privacy_level default null, p_avatar_icon text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  if not exists (select 1 from public.profiles where id = uid and deleted_at is null) then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  update public.profiles set
      avatar_colour = coalesce(p_avatar_colour, avatar_colour),
      country_code = coalesce(upper(p_country_code), country_code),
      privacy = coalesce(p_privacy, privacy),
      avatar_icon = case when p_avatar_icon is null then avatar_icon when p_avatar_icon = '' then null else p_avatar_icon end
   where id = uid and deleted_at is null;
  return private.profile_json(uid, uid);
end $$;

revoke update (display_name) on public.profiles from authenticated;

create or replace function private.link_reward_gold() returns int language sql immutable as $$ select 20; $$;

revoke execute on function public.username_available(text), public.claim_username(text) from public, anon;
grant execute on function public.username_available(text), public.claim_username(text) to authenticated;
