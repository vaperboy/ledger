create or replace function public.publish_leaderboard(p_net_worth numeric, p_trading_result numeric, p_game_week int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); prior public.leaderboard_entries; ceiling_nw numeric; days numeric;
begin
  perform private.require_free(uid, 'trade');
  if p_net_worth is null or p_trading_result is null or p_game_week is null
     or p_net_worth not between -1000000000000 and 10000000000000 or p_trading_result not between -1000000000000 and 1000000000000
     or p_game_week not between 0 and 100000 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  select * into prior from public.leaderboard_entries where user_id = uid;
  if found and now() - prior.updated_at < interval '30 seconds' then return jsonb_build_object('accepted', false, 'reason', 'too_soon'); end if;
  if found then
    days := least(20, greatest(1, extract(epoch from now() - prior.updated_at) / 86400));
    ceiling_nw := greatest(prior.net_worth, 0) * power(2, days) + 1000000;
  else
    ceiling_nw := 1000000 * (1 + p_game_week);
  end if;
  if p_net_worth > ceiling_nw or abs(p_trading_result) > abs(p_net_worth) * 3 + 1000000 then
    return jsonb_build_object('accepted', false, 'reason', 'implausible');
  end if;
  insert into public.leaderboard_entries (user_id, net_worth, trading_result, game_week)
    values (uid, round(p_net_worth, 2), round(p_trading_result, 2), p_game_week)
    on conflict (user_id) do update set net_worth = excluded.net_worth, trading_result = excluded.trading_result,
                                        game_week = greatest(public.leaderboard_entries.game_week, excluded.game_week), updated_at = now();
  return jsonb_build_object('accepted', true);
end $$;

create or replace function public.read_leaderboards(p_limit int default 300) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); n int := least(greatest(coalesce(p_limit, 300), 10), 500);
begin
  return coalesce((
    with visible as (
      select e.user_id, p.display_name, e.game_week, e.net_worth, e.trading_result
        from public.leaderboard_entries e join public.profiles p on p.id = e.user_id
       where p.deleted_at is null and p.adult_confirmed and p.privacy = 'public' and e.user_id <> uid
         and (not p.is_bot or exists (select 1 from public.bots b where b.user_id = p.id and b.active))
         and not private.is_blocked_between(uid, e.user_id)),
    a as (select * from visible order by net_worth desc, display_name limit n),
    b as (select * from visible order by trading_result desc, display_name limit n)
    select jsonb_agg(jsonb_build_object('playerID', x.user_id, 'name', x.display_name, 'week', x.game_week,
                                        'netWorth', x.net_worth, 'tradingResult', x.trading_result))
      from (select * from a union select * from b) x), '[]'::jsonb);
end $$;

create or replace function public.news_feed(p_filter text default 'everyone', p_limit int default 50) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); my_country text; my_trades text[];
begin
  if p_filter not in ('everyone', 'friends', 'myTrade', 'myCountry') then raise exception 'invalid_filter' using errcode = 'P0001'; end if;
  select country_code into my_country from public.profiles where id = uid;
  select coalesce(array_agg(lower(trade)), '{}') into my_trades from public.companies_public where owner_id = uid;
  return coalesce((select jsonb_agg(r.j order by r.at desc) from (
    select e.created_at as at, jsonb_build_object('id', e.id, 'kind', e.kind, 'playerID', p.id, 'playerName', p.display_name, 'countryCode', p.country_code,
        'audience', case p.privacy when 'public' then 'everyone' else 'friends' end, 'day', floor(extract(epoch from e.created_at) / 86400)::int,
        'trade', e.trade, 'city', e.city, 'company', e.company, 'count', e.count, 'otherName', e.other_name, 'club', e.club,
        'isFriend', private.are_friends(uid, p.id), 'namesVisible', p.id = uid or private.are_friends(uid, p.id)) as j
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

revoke execute on all functions in schema public from public, anon;
grant execute on function public.publish_leaderboard(numeric, numeric, int), public.read_leaderboards(int), public.news_feed(text, int) to authenticated;
