-- Limits from 0034 (and 0031 when it is applied): ventures, supply fees, leaderboard, marketplace, computer-run players, closed calls.

create function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
$$;

create function pg_temp.expect_error(stmt text, code text) returns void language plpgsql as $$
declare msg text;
begin
  begin
    execute stmt;
  exception when others then
    msg := sqlerrm;
  end;
  if msg is null then raise exception 'expected % but nothing failed: %', code, stmt; end if;
  if msg <> code and msg not like code || ':%' and msg not like code || '%' then raise exception 'expected % but got "%": %', code, msg, stmt; end if;
end $$;

create function pg_temp.mk_player(nm text, age_days int default 40, cc text default 'US') returns uuid language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role) values (u, 'authenticated', 'authenticated');
  insert into public.profiles (id, display_name, adult_confirmed, created_at, country_code) values (u, nm, true, now() - make_interval(days => age_days), cc);
  return u;
end $$;

create function pg_temp.friends(a uuid, b uuid) returns void language sql as $$
  insert into public.friendships (requester_id, addressee_id, status, responded_at) values (a, b, 'accepted', now());
$$;

create function pg_temp.sum_kind(uid uuid, k text) returns numeric language sql as $$
  select coalesce(sum(amount), 0) from public.settlements where recipient_id = uid and kind = k;
$$;

create temp table sx (k text primary key, id uuid);
grant select on sx to authenticated;
insert into sx select 'chair', pg_temp.mk_player('Sec Chair');
insert into sx select 'mate', pg_temp.mk_player('Sec Mate');
insert into sx select 'out', pg_temp.mk_player('Sec Outsider');
create function pg_temp.sid(k text) returns uuid language sql as $$ select id from sx where k = $1 $$;

-- A new venture's value is capped, reports move it in small steps, and every owner sees the history.
do $$
declare ch uuid := pg_temp.sid('chair'); m uuid := pg_temp.sid('mate'); vid uuid; v numeric; r numeric; inv uuid; h jsonb;
begin
  perform pg_temp.friends(ch, m);
  perform pg_temp.as_user(ch);
  perform pg_temp.expect_error('select public.create_venture(''own.70'', ''Bad Cur'', 1000, ''XYZ'')', 'invalid_value');
  vid := (public.create_venture('own.71', 'Sec Works', 9e15, 'USD') ->> 'id')::uuid;
  select value into v from public.ventures where id = vid;
  if v > round(200000000 / 10.7, 2) then raise exception 'a new venture kept a forged value: %', v; end if;
  update public.ventures set value = 1000000 where id = vid;
  r := public.report_venture_value(vid, 9e15);
  if r <> 1000000 then raise exception 'a report right after the last one moved the value: %', r; end if;
  update public.venture_value_log set at = now() - interval '2 days' where venture_id = vid;
  insert into public.venture_value_log (venture_id, value, at) values (vid, 1000000, now() - interval '1 day');
  r := public.report_venture_value(vid, 9e15);
  if r <> 1100000 then raise exception 'a report moved the value more than a tenth: %', r; end if;
  update public.venture_value_log set at = at - interval '1 day' where venture_id = vid;
  r := public.report_venture_value(vid, 1);
  if r <> 990000 then raise exception 'a report dropped the value more than a tenth: %', r; end if;
  update public.venture_value_log set at = at - interval '1 day' where venture_id = vid;
  update public.ventures set value = 1450000 where id = vid;
  r := public.report_venture_value(vid, 9e15);
  if r > 1500000 then raise exception 'the value grew more than half in seven days: %', r; end if;

  update public.ventures set value = 1000000 where id = vid;
  inv := (public.invite_venture_partner(vid, m, 20, round(private.jv_fair_price(1000000, 20), 2)) ->> 'id')::uuid;
  perform pg_temp.as_user(m);
  perform public.reply_to_venture_offer(inv, true, 'USD');
  h := public.venture_value_history(vid);
  if jsonb_array_length(h) < 4 then raise exception 'a partner does not see the value history: %', h; end if;
  perform pg_temp.as_user(pg_temp.sid('out'));
  perform pg_temp.expect_error(format('select public.venture_value_history(%L)', vid), 'not_found');
end $$;

do $$
declare n int;
begin
  perform pg_temp.as_user(pg_temp.sid('mate'));
  set local role authenticated;
  select count(*) into n from public.venture_value_log;
  if n < 4 then raise exception 'a partner cannot read the value log: %', n; end if;
  reset role;
  perform pg_temp.as_user(pg_temp.sid('out'));
  set local role authenticated;
  select count(*) into n from public.venture_value_log;
  if n <> 0 then raise exception 'an outsider reads the value log: %', n; end if;
  reset role;
end $$;

-- Capital calls and dividends: a fifth of the value at most, one a week, capped again when carried out, and the value is frozen meanwhile.
do $$
declare ch uuid := pg_temp.sid('chair'); m uuid := pg_temp.sid('mate'); vid uuid; r jsonb; part numeric; mid uuid; before numeric;
begin
  select id into vid from public.ventures where chair_id = ch and company_key = 'own.71';
  update public.ventures set value = 1000000 where id = vid;
  perform pg_temp.as_user(ch);
  perform pg_temp.expect_error(format('select public.propose_venture_change(%L, ''capital'', ''{"amount": 1000000000000}''::jsonb, true)', vid), 'invalid_amount');
  perform pg_temp.expect_error(format('select public.propose_venture_change(%L, ''capital'', ''{"amount": 200001}''::jsonb, true)', vid), 'invalid_amount');
  perform pg_temp.expect_error(format('select public.propose_venture_change(%L, ''dividend'', ''{"amount": 500000}''::jsonb, true)', vid), 'invalid_amount');
  r := public.propose_venture_change(vid, 'capital', '{"amount": 200000}'::jsonb, true);
  if not (r ->> 'applied')::boolean then raise exception 'a majority owner''s capped call did not pass: %', r; end if;
  part := -pg_temp.sum_kind(m, 'venture_capital_call');
  if part <= 0 or part > 200000 * 0.2 + 0.01 then raise exception 'the partner paid outside their part of a capped call: %', part; end if;
  if pg_temp.sum_kind(ch, 'venture_capital') - round(private.jv_fair_price(1000000, 20), 2) <> part then raise exception 'the chair got more than the partners paid'; end if;
  perform pg_temp.expect_error(format('select public.propose_venture_change(%L, ''capital'', ''{"amount": 1000}''::jsonb, true)', vid), 'too_soon');

  -- Moved back past the gap, a second call waits for the weekly meeting; the value stays put and the amount is capped again.
  update public.venture_meetings set closed_at = now() - interval '8 days' where venture_id = vid and closed_at is not null;
  r := public.propose_venture_change(vid, 'capital', '{"amount": 150000}'::jsonb, false);
  mid := (r ->> 'meetingID')::uuid;
  perform pg_temp.expect_error(format('select public.propose_venture_change(%L, ''capital'', ''{"amount": 1000}''::jsonb, false)', vid), 'too_soon');
  update public.venture_value_log set at = at - interval '3 days' where venture_id = vid;
  if public.report_venture_value(vid, 100) <> 1000000 then raise exception 'the value moved while a capital call waited for the vote'; end if;
  update public.ventures set value = 100000 where id = vid;
  before := pg_temp.sum_kind(m, 'venture_capital_call');
  update public.venture_meetings set deadline = now() - interval '1 minute' where id = mid;
  perform private.run_venture_housekeeping();
  if before - pg_temp.sum_kind(m, 'venture_capital_call') > 100000 * 0.2 * 0.2 + 0.01 then raise exception 'a call was not capped to today''s value'; end if;
end $$;

-- Computer-run co-owners: invited like anyone (friends only), never pay above fair or the fixed sum, and are never credited in a call.
do $$
declare ch uuid := pg_temp.mk_player('Bot Chair'); bot uuid := gen_random_uuid(); vid uuid; v public.ventures; credited numeric;
begin
  insert into auth.users (id, aud, role) values (bot, 'authenticated', 'authenticated');
  insert into public.profiles (id, display_name, adult_confirmed, is_bot, created_at) values (bot, 'Gretabot', true, true, now() - interval '90 days');
  perform pg_temp.as_user(ch);
  vid := (public.create_venture('own.72', 'Bot Works', 100000000, 'USD') ->> 'id')::uuid;
  perform pg_temp.expect_error(format('select public.invite_venture_partner(%L, %L, 10, %s)', vid, bot, round(private.jv_fair_price(100000000, 10), 2)), 'not_friends');
  select * into v from public.ventures where id = vid;
  perform pg_temp.expect_error(format('select private.jv_join(v, %L, 10, %s) from public.ventures v where v.id = %L', bot, round(private.jv_fair_price(v.value, 10), 2), vid), 'outside_band');
  perform private.jv_join(v, bot, 10, private.jv_bot_stake_cap('USD'));
  credited := pg_temp.sum_kind(ch, 'venture_capital');
  update public.ventures set value = 10000000 where id = vid;
  select * into v from public.ventures where id = vid;
  perform private.jv_apply(v, row(gen_random_uuid(), null, 'capital', '{"amount": 1000000}'::jsonb, null, null, now())::public.venture_items);
  if pg_temp.sum_kind(ch, 'venture_capital') <> credited then raise exception 'a capital call credited a computer-run co-owner''s part'; end if;
end $$;

-- Supply: the buyer pays the fee the supplier gets for ending early.
do $$
declare a uuid := pg_temp.mk_player('Supply Buyer'); c uuid := pg_temp.mk_player('Supply Seller'); lid uuid; cid uuid;
        ln text := (select line_id from public.supply_trade_lines where trade_id = 'bakery' order by line_id limit 1);
begin
  insert into public.supply_listings (owner_id, company_key, company_name, trade_id, city, region, line_id, price_tier, quality_tier, capacity_per_week,
                                      lead_days, min_order, terms_days, unit_value, currency)
    values (c, 'own.80', 'Sec Bakes', 'bakery', 'Leeds', 'GB', ln, 1, 1, 100, 3, 1, 14, 10, 'USD') returning id into lid;
  perform pg_temp.as_user(a);
  cid := (public.sign_supply_contract('own.81', ln, lid, 15, 'USD') ->> 'id')::uuid;
  perform public.end_supply_contract('own.81', ln);
  if pg_temp.sum_kind(c, 'supply_end_fee') <= 0 or pg_temp.sum_kind(a, 'supply_end_fee') <> -pg_temp.sum_kind(c, 'supply_end_fee') then
    raise exception 'ending a supply deal did not charge the buyer what the supplier got';
  end if;
  if to_regprocedure('private.supply_fill()') is not null then
    perform pg_temp.expect_error(format('select public.sign_supply_contract(''own.82'', %L, %L, 2000000000, ''USD'')', ln, lid), 'invalid_units');
  end if;
end $$;

-- 0031 when applied: a huge need cannot stop the hourly job.
do $$
declare a uuid := pg_temp.mk_player('Huge Buyer'); c uuid := pg_temp.mk_player('Huge Seller'); lid uuid; ln text;
begin
  if to_regprocedure('private.supply_fill()') is null then return; end if;
  ln := (select line_id from public.supply_trade_lines where trade_id = 'bakery' order by line_id limit 1);
  insert into public.supply_listings (owner_id, company_key, company_name, trade_id, city, region, line_id, price_tier, quality_tier, capacity_per_week,
                                      lead_days, min_order, terms_days, unit_value, currency)
    values (c, 'own.90', 'Huge Bakes', 'bakery', 'Leeds', 'US', ln, 1, 1, 1000000, 3, 1, 14, 10, 'USD') returning id into lid;
  insert into public.supply_contracts (buyer_id, buyer_company_key, line_id, listing_id, supplier_id, supplier_name, units_per_week, unit_price, need)
    values (a, 'own.91', ln, lid, c, 'Huge Seller', 1000000, 10, 1000000);
  update public.profiles set last_seen_at = now() where id in (a, c);
  delete from public.world_flags where key = 'fakes_removed';
  perform private.supply_fill();
  perform private.bot_tick();
end $$;

-- Leaderboard: a new account cannot jump to the top, weeks move at a playable pace, and repeats in one week do not compound.
do $$
declare n uuid := pg_temp.mk_player('Board New', 1, 'NO'); r jsonb; i int;
begin
  perform pg_temp.as_user(n);
  r := public.publish_leaderboard(100000000000, 0, 0);
  if (r ->> 'accepted')::boolean then raise exception 'a forged first entry was accepted'; end if;
  r := public.publish_leaderboard(1000000, 0, 5000);
  if (r ->> 'accepted')::boolean then raise exception 'a week far ahead of play was accepted'; end if;
  if not exists (select 1 from public.leaderboard_flags where user_id = n and reason = 'week_too_fast') then raise exception 'a refused entry was not kept for review'; end if;
  r := public.publish_leaderboard(400000, 0, 20);
  if not (r ->> 'accepted')::boolean then raise exception 'a plausible first entry was refused: %', r; end if;
  for i in 1..20 loop
    update public.leaderboard_entries set updated_at = now() - interval '1 minute' where user_id = n;
    r := public.publish_leaderboard((select net_worth from public.leaderboard_entries where user_id = n) * 1.14 + 1900000, 0, 21);
  end loop;
  if (select net_worth from public.leaderboard_entries where user_id = n) > 400000 * 1.15 + 2000000 + 1 then raise exception 'repeats in one week compounded'; end if;
end $$;

-- Marketplace: items must be things the game has, near the game's price, and a sold item cannot be sold again.
do $$
declare a uuid := pg_temp.mk_player('Market Seller', 40, 'NO'); b uuid := pg_temp.mk_player('Market Buyer', 40, 'NO'); l jsonb; did uuid; i int;
begin
  perform pg_temp.as_user(a);
  perform pg_temp.expect_error($q$select public.market_list('{"id":"x1","kind":"car","title":"Rocket car","ref":"nope","base":1}'::jsonb, 1000, 'NOK')$q$, 'invalid_item');
  perform pg_temp.expect_error($q$select public.market_list('{"id":"x1","kind":"plane","title":"Small car","ref":"car_s","base":1}'::jsonb, 1000, 'NOK')$q$, 'invalid_item');
  perform pg_temp.expect_error($q$select public.market_list('{"id":"x1","kind":"car","title":"Small car","ref":"car_s","base":1}'::jsonb, 1000, 'XYZ')$q$, 'invalid_price');
  perform pg_temp.expect_error($q$select public.market_list('{"id":"x1","kind":"car","title":"Small car","ref":"car_s","base":1}'::jsonb, 5000000, 'NOK')$q$, 'price_outside_market');
  l := public.market_list('{"id":"x1","kind":"car","title":"Small car","ref":"car_s","base":900000000,"cond":7,"lux":true}'::jsonb, 300000, 'NOK');
  if (l -> 'item' ->> 'base')::numeric > 340000 * 3 or (l -> 'item' ->> 'cond')::numeric > 1 or (l -> 'item' ->> 'lux')::boolean then raise exception 'item figures were not clamped: %', l; end if;
  perform pg_temp.as_user(b);
  did := (public.market_buy((l ->> 'id')::uuid) ->> 'id')::uuid;
  perform pg_temp.as_user(a);
  perform public.market_respond(did, 'accept', null);
  perform pg_temp.expect_error($q$select public.market_list('{"id":"x1","kind":"car","title":"Small car","ref":"car_s","base":1}'::jsonb, 1000, 'NOK')$q$, 'invalid_item');
  for i in 2..10 loop
    perform public.market_list(jsonb_build_object('id', 'x' || i, 'kind', 'equipment', 'title', 'Oven ' || i, 'ref', 'oven', 'base', 1000), 1000, 'NOK');
    perform public.market_cancel((select id from public.market_listings where seller_id = a and item ->> 'id' = 'x' || i));
  end loop;
  perform pg_temp.expect_error($q$select public.market_list('{"id":"x11","kind":"equipment","title":"Oven","ref":"oven","base":1}'::jsonb, 1000, 'NOK')$q$, 'rate_limited');
end $$;

-- Computer-run players look and answer like players.
do $$
declare s int; me uuid := pg_temp.mk_player('Bot Finder'); bot uuid; shapes int; r jsonb;
begin
  delete from public.bots where slot between 60 and 99;
  for s in 60..99 loop perform private.bot_create(s); end loop;
  if exists (select 1 from public.profiles p join public.bots b on b.user_id = p.id where b.slot between 60 and 99
              and p.display_name !~ '^Player [0-9A-F]{4}$' and p.display_name !~ '^[A-Za-z][A-Za-z0-9_]{2,15}$') then
    raise exception 'a computer-run player has a name no player could have';
  end if;
  select count(distinct case when p.display_name ~ '^Player ' then 'p' when p.display_name ~ '_' then 'u' when p.display_name ~ '[0-9]' then 'd' else 'n' end) into shapes
    from public.profiles p join public.bots b on b.user_id = p.id where b.slot between 60 and 99;
  if shapes < 4 then raise exception 'computer-run names come in too few shapes: %', shapes; end if;
  if (select count(*) from public.profiles p join public.bots b on b.user_id = p.id where b.slot between 60 and 99 and p.avatar_look is not null) < 15 then
    raise exception 'too few computer-run players have a look';
  end if;
  if exists (select 1 from public.profiles p join public.bots b on b.user_id = p.id where b.slot between 60 and 99
              and p.display_name !~ '^Player ' and (p.username is null or not exists (select 1 from public.username_reservations u where u.name_key = lower(p.display_name)))) then
    raise exception 'a computer-run user name is not held like a claimed one';
  end if;
  select b.user_id into bot from public.bots b where b.slot = 60;
  perform pg_temp.as_user(me);
  r := public.profile_by_code((select code from public.profiles where id = bot));
  if r ->> 'id' <> bot::text then raise exception 'a computer-run player cannot be opened by code'; end if;
  if not exists (select 1 from jsonb_array_elements(public.search_players((select display_name from public.profiles where id = bot))) e where e ->> 'id' = bot::text) then
    raise exception 'a computer-run player cannot be found';
  end if;
  perform public.send_friend_request(bot);
  perform pg_temp.expect_error(format('select public.send_friend_request(%L)', bot), 'request_pending');
end $$;

-- Calls the app does not use are closed to players; the ones it uses stay open.
do $$
declare f text;
begin
  foreach f in array array['public.sign_supply_contract(text,text,uuid,integer,text)', 'public.end_supply_contract(text,text)',
                           'public.place_exchange_order(uuid,public.exchange_side,bigint,numeric,text)', 'public.record_player_event(text,text,text,text,integer,text,text,text)',
                           'public.call_venture_emergency(uuid,public.venture_kind,jsonb)', 'public.open_venture_meeting(uuid,jsonb,boolean,boolean)'] loop
    continue when to_regprocedure(f) is null;
    if has_function_privilege('authenticated', to_regprocedure(f), 'execute') then raise exception 'still open to players: %', f; end if;
  end loop;
  foreach f in array array['report_supply_week', 'place_bid', 'invest_in_startup', 'list_on_exchange', 'cast_ballot', 'join_club', 'set_country_policy', 'list_artifact'] loop
    if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = f
                and has_function_privilege('authenticated', p.oid, 'execute')) then raise exception 'still open to players: %', f; end if;
  end loop;
  foreach f in array array['heartbeat', 'my_ventures', 'propose_venture_change', 'report_venture_value', 'publish_leaderboard', 'market_list', 'market_buy',
                           'send_friend_request', 'search_players', 'profile_by_code', 'pay_venture_dividend', 'venture_value_history', 'reply_to_venture_offer'] loop
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = f
                    and has_function_privilege('authenticated', p.oid, 'execute')) then raise exception 'closed by mistake: %', f; end if;
  end loop;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) then
    raise exception 'a public call is open without sign-in';
  end if;
end $$;
