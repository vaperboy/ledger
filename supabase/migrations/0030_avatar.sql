-- Half-body avatar and card look shared with other players.
-- avatar_look is a short text: "face,hair,colour,outfit|bd=<backdrop>|np=<plate>|fl=<flair>|fr=<frame>|pc=<card>|bg=<badge>,<badge>".

alter table public.profiles add column avatar_look text
  constraint avatar_look_shape check (avatar_look is null or avatar_look ~ '^[a-z0-9,._=|-]{1,240}$');

create function private.rewire30(fn regprocedure, pairs text[]) returns void language plpgsql as $$
declare d text := pg_get_functiondef(fn); n text; i int;
begin
  for i in 1..cardinality(pairs) by 2 loop
    n := replace(d, pairs[i], pairs[i + 1]);
    if n = d then raise exception 'rewire30: text not found in %: %', fn, pairs[i]; end if;
    d := n;
  end loop;
  execute d;
end $$;

select private.rewire30('private.profile_json(uuid, uuid)'::regprocedure, array[
  $a$'avatarIcon', p.avatar_icon,$a$, $a$'avatarIcon', p.avatar_icon, 'avatarLook', p.avatar_look,$a$]);

drop function private.rewire30(regprocedure, text[]);

drop function public.update_my_profile(text, int, text, public.privacy_level, text);

create function public.update_my_profile(p_display_name text default null, p_avatar_colour int default null, p_country_code text default null,
                                         p_privacy public.privacy_level default null, p_avatar_icon text default null, p_avatar_look text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  if not exists (select 1 from public.profiles where id = uid and deleted_at is null) then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  update public.profiles set
      avatar_colour = coalesce(p_avatar_colour, avatar_colour),
      country_code = coalesce(upper(p_country_code), country_code),
      privacy = coalesce(p_privacy, privacy),
      avatar_icon = case when p_avatar_icon is null then avatar_icon when p_avatar_icon = '' then null else p_avatar_icon end,
      avatar_look = case when p_avatar_look is null then avatar_look when p_avatar_look = '' then null else p_avatar_look end
   where id = uid and deleted_at is null;
  return private.profile_json(uid, uid);
end $$;

revoke execute on function public.update_my_profile(text, int, text, public.privacy_level, text, text) from public, anon;
grant execute on function public.update_my_profile(text, int, text, public.privacy_level, text, text) to authenticated;
