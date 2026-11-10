create or replace function public.ensure_profile(p_adult_confirmed boolean default false) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); p public.profiles; had boolean;
begin
  select * into p from public.profiles where id = uid and deleted_at is null;
  had := found;
  if had and p.adult_confirmed then return private.profile_json(uid, uid); end if;
  if p_adult_confirmed is distinct from true then raise exception 'adult_required' using errcode = 'P0001'; end if;
  if not had then
    insert into public.profiles (id, display_name, adult_confirmed) values (uid, 'Player ' || upper(substr(md5(uid::text), 1, 4)), true)
      on conflict (id) do nothing;
  end if;
  update public.profiles set adult_confirmed = true where id = uid and deleted_at is null;
  return private.profile_json(uid, uid);
end $$;

create or replace function public.account_status() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); p public.profiles; had boolean;
begin
  select * into p from public.profiles where id = uid and deleted_at is null;
  had := found;
  return jsonb_build_object(
    'hasProfile', had,
    'adultConfirmed', had and p.adult_confirmed,
    'isAdmin', had and p.adult_confirmed and private.is_admin(uid),
    'linkRewardGold', private.link_reward_gold(),
    'linkRewardClaimed', exists (select 1 from public.link_reward_claims where user_id = uid));
end $$;

grant execute on function public.ensure_profile(boolean), public.account_status() to authenticated;
