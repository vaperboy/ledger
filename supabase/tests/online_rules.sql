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

create function pg_temp.mk_player(nm text, age_days int default 40) returns uuid language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role) values (u, 'authenticated', 'authenticated');
  insert into public.profiles (id, display_name, adult_confirmed, created_at) values (u, nm, true, now() - make_interval(days => age_days));
  return u;
end $$;

create temp table cast_ids (k text primary key, id uuid);
insert into cast_ids select 'a', pg_temp.mk_player('Alice Ames');
insert into cast_ids select 'b', pg_temp.mk_player('Bob Berg');
insert into cast_ids select 'c', pg_temp.mk_player('Cora Cole');
insert into cast_ids select 'n', pg_temp.mk_player('Newt Young', 1);
create function pg_temp.id(k text) returns uuid language sql as $$ select id from cast_ids where k = $1 $$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); r jsonb;
begin
  perform private.settle(a, 100, 'USD', 'test', 'r1', 'one');
  perform private.settle(b, 200, 'USD', 'test', 'r2', 'two');
  perform pg_temp.as_user(a);
  r := public.pending_settlements();
  if jsonb_array_length(r) <> 1 or r -> 0 ->> 'ref' <> 'r1' then raise exception 'pending_settlements shows %', r; end if;
  perform public.ack_settlements(array[(r -> 0 ->> 'id')::uuid]);
  if jsonb_array_length(public.pending_settlements()) <> 0 then raise exception 'ack did not clear'; end if;
  perform public.ack_settlements(array[(select id from public.settlements where recipient_id = b)]);
  if exists (select 1 from public.settlements where recipient_id = b and claimed_at is not null) then raise exception 'acked another players settlement'; end if;
end $$;

create temp table rls_cast (a uuid);
grant all on rls_cast to authenticated;
insert into rls_cast select pg_temp.id('a');
grant select on cast_ids to authenticated;

do $$
declare a uuid := (select a from rls_cast); n int;
begin
  perform pg_temp.as_user(a);
  set local role authenticated;
  select count(*) into n from public.settlements;
  if n <> 1 then raise exception 'settlements visible: %', n; end if;
  perform pg_temp.expect_error('select buyer_id from public.exchange_trades', 'permission denied');
  perform pg_temp.expect_error('select * from public.account_signals', 'permission denied');
  perform pg_temp.expect_error('select * from public.leaderboard_entries', 'permission denied');
  perform pg_temp.expect_error('select * from public.auction_bids', 'permission denied');
  perform pg_temp.expect_error('update public.profiles set level = 99', 'permission denied');
  perform pg_temp.expect_error('insert into public.settlements (recipient_id, amount, currency, kind) values (''' || a || ''', 1, ''USD'', ''x'')', 'permission denied');
  reset role;
end $$;

do $$
declare a uuid := pg_temp.id('a'); p record;
begin
  perform pg_temp.as_user(a);
  perform public.share_progress(5, array['First Profit', 'Ten Hires'], 50, 40, '[{"id":"own.1","name":"Ames Bakery","trade":"Bakery","city":"Leeds","countryCode":"GB","health":"steady"}]'::jsonb);
  perform public.share_progress(2, array['Debt Free'], 10, 5, '[]'::jsonb);
  select * into p from public.profiles where id = a;
  if p.level <> 5 or p.game_week <> 50 or p.trades_completed <> 40 then raise exception 'progress regressed: % % %', p.level, p.game_week, p.trades_completed; end if;
  if not (p.badges @> array['First Profit', 'Ten Hires', 'Debt Free']) then raise exception 'badges lost: %', p.badges; end if;
  if (select count(*) from public.companies_public where owner_id = a) <> 1 then raise exception 'companies replaced by a stale save'; end if;
  perform public.share_progress(6, array[]::text[], 60, 50, '[]'::jsonb);
  if (select count(*) from public.companies_public where owner_id = a) <> 0 then raise exception 'companies not updated by a newer save'; end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); r jsonb;
begin
  perform pg_temp.as_user(a);
  r := public.publish_leaderboard(50000, 1000, 60);
  if not (r ->> 'accepted')::boolean then raise exception 'plausible publish refused: %', r; end if;
  update public.leaderboard_entries set updated_at = now() - interval '1 hour' where user_id = a;
  r := public.publish_leaderboard(900000000000, 1000, 61);
  if (r ->> 'accepted')::boolean or r ->> 'reason' <> 'implausible' then raise exception 'forged net worth accepted: %', r; end if;
  update public.leaderboard_entries set updated_at = now() - interval '1 hour' where user_id = a;
  r := public.publish_leaderboard(70000, 1000, 40);
  if (select game_week from public.leaderboard_entries where user_id = a) < 60 then raise exception 'week moved backwards'; end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); c uuid := pg_temp.id('c'); r jsonb;
begin
  perform pg_temp.as_user(a);
  perform public.heartbeat();
  if (select count(*) from public.profiles where is_bot) < 8 then raise exception 'bots were not created'; end if;
  perform pg_temp.as_user(b);
  perform public.send_friend_request(a);
  perform pg_temp.as_user(a);
  perform public.accept_friend_request(b);
  perform public.share_progress(7, array[]::text[], 70, 60, '[]'::jsonb);
  perform pg_temp.as_user(b);
  perform public.heartbeat();
  r := public.friend_activity(20);
  if jsonb_array_length(r -> 'presence') < 1 then raise exception 'no presence for a friend: %', r; end if;
  if not exists (select 1 from jsonb_array_elements(r -> 'activity') e where e ->> 'kind' = 'levelUp' and e ->> 'playerID' = a::text) then raise exception 'friend level up missing: %', r; end if;
  perform pg_temp.as_user(c);
  r := public.friend_activity(20);
  if jsonb_array_length(r -> 'activity') <> 0 then raise exception 'a stranger sees friend activity: %', r; end if;
  perform public.send_friend_request((select user_id from public.bots order by slot limit 1));
  if (select status from public.friendships where requester_id = c and addressee_id = (select user_id from public.bots order by slot limit 1)) <> 'pending' then
    raise exception 'a request to a player the world runs did not wait like any other';
  end if;
  if jsonb_array_length(public.search_players((select display_name from public.profiles where id = (select user_id from public.bots order by slot limit 1)))) < 1 then
    raise exception 'a player the world runs cannot be found by name';
  end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); c uuid := pg_temp.id('c');
begin
  perform pg_temp.as_user(a);
  perform public.register_device('device-one');
  perform pg_temp.as_user(c);
  perform public.register_device('device-two');
  if private.linked(a, c) then raise exception 'different devices linked'; end if;
  perform pg_temp.as_user(b);
  perform public.register_device('device-one');
  if not private.linked(a, b) then raise exception 'same device did not link accounts'; end if;
end $$;

do $$
declare b uuid := pg_temp.id('b'); c uuid := pg_temp.id('c'); nw uuid := pg_temp.id('n'); d uuid; aid uuid; r jsonb; cc text;
begin
  d := pg_temp.mk_player('Dana Dyer');
  insert into public.leaderboard_entries (user_id, net_worth, trading_result, game_week) values (d, 500000, 0, 40), (b, 400000, 0, 40);
  perform public.grant_artifact(c, 'abacus', 1);
  perform pg_temp.as_user(nw);
  perform pg_temp.expect_error('select public.place_bid(gen_random_uuid(), 100)', 'not_found');
  perform pg_temp.as_user(c);
  perform pg_temp.expect_error('select public.list_artifact(''abacus'', 1, 1, null, 6, ''USD'')', 'start_price_too_low');
  perform pg_temp.expect_error('select public.list_artifact(''abacus'', 1, 1000000000, null, 6, ''USD'')', 'price_outside_market');
  perform pg_temp.expect_error('select public.list_artifact(''abacus'', 1, 100, null, 6, ''usd'')', 'invalid_listing');
  r := public.list_artifact('abacus', 1, 100, null, 6, 'USD');
  aid := (r ->> 'id')::uuid;
  if r ->> 'currency' <> 'USD' then raise exception 'currency missing: %', r; end if;
  perform pg_temp.as_user(nw);
  perform pg_temp.expect_error('select public.place_bid(''' || aid || ''', 100)', 'new_account');
  perform pg_temp.as_user(c);
  perform pg_temp.expect_error('select public.place_bid(''' || aid || ''', 100)', 'seller_cannot_bid');
  perform pg_temp.as_user(b);
  perform pg_temp.expect_error('select public.place_bid(''' || aid || ''', 99)', 'too_low');
  perform pg_temp.expect_error('select public.place_bid(''' || aid || ''', 5000000)', 'price_outside_market');
  r := public.place_bid(aid, 100);
  if r ->> 'leader' <> b::text then raise exception 'bid did not lead: %', r; end if;
  perform pg_temp.as_user(d);
  perform pg_temp.expect_error('select public.place_bid(''' || aid || ''', 104)', 'too_low');
  r := public.place_bid(aid, 105);
  update public.auctions set ends_at = now() - interval '1 second' where id = aid;
  perform public.auctions_snapshot();
  if (select status::text from public.auctions where id = aid) <> 'sold' then raise exception 'auction did not sell'; end if;
  if (select owner_id from public.artifact_pieces where def_id = 'abacus' and serial = 1) <> d then raise exception 'piece did not change hands'; end if;
  if (select amount from public.settlements where recipient_id = d and kind = 'auction_win') <> -105 then raise exception 'winner not charged in cash'; end if;
  if (select amount from public.settlements where recipient_id = c and kind = 'auction_sale') <> 95 then raise exception 'seller not paid price less fee'; end if;
  if (select currency from public.settlements where recipient_id = c and kind = 'auction_sale') <> 'USD' then raise exception 'settlement currency'; end if;
  if exists (select 1 from public.settlements where recipient_id = b and kind like 'auction%') then raise exception 'outbid player was charged'; end if;
  select country_code into cc from public.profiles where id = c;
  if (select balance from public.treasuries where country_code = cc) <> 10 then raise exception 'fee not posted to treasury'; end if;
  if not exists (select 1 from public.player_activity where player_id = c and kind = 'auctionSold') then raise exception 'auction sale not logged'; end if;
  if (select held from public.gold_wallets where user_id = d) is not null and (select held from public.gold_wallets where user_id = d) <> 0 then raise exception 'gold was held'; end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); c uuid := pg_temp.id('c'); aid uuid; r jsonb; cap numeric;
begin
  perform public.grant_artifact(a, 'rope', 1);
  perform pg_temp.as_user(a);
  aid := (public.list_artifact('rope', 1, 100, null, 6, 'USD') ->> 'id')::uuid;
  perform pg_temp.as_user(c);
  update public.leaderboard_entries set net_worth = 0 where user_id = c;
  insert into public.leaderboard_entries (user_id, net_worth, trading_result, game_week) values (c, 0, 0, 1) on conflict do nothing;
  perform pg_temp.expect_error('select public.place_bid(''' || aid || ''', 10001)', 'not_enough_cash');
  r := public.place_bid(aid, 9999);
  if r ->> 'leader' <> c::text then raise exception 'bid within headroom refused: %', r; end if;
  perform pg_temp.as_user(a);
  perform public.cancel_auction(aid);
exception when others then
  if sqlerrm <> 'has_bids' then raise; end if;
end $$;

do $$
declare cnt int;
begin
  select count(*) into cnt from pg_policies where schemaname = 'public' and cmd in ('UPDATE', 'DELETE', 'INSERT', 'ALL') and coalesce(qual, with_check) = 'true';
  if cnt <> 0 then raise exception 'open write policies: %', cnt; end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); c uuid := pg_temp.id('c'); lid uuid; r jsonb; i int; bought bigint;
begin
  perform pg_temp.as_user(c);
  lid := (public.list_on_exchange('own.7', 'Cole Foods', 40000000, 'USD') ->> 'id')::uuid;
  update public.exchange_listings set listed_at = now() - interval '60 days' where id = lid;
  for i in 1..4 loop
    perform pg_temp.as_user(c);
    perform public.place_exchange_order(lid, 'sell', 1000, 40, 'USD');
    perform pg_temp.as_user(b);
    r := public.place_exchange_order(lid, 'buy', 1000, 40, 'USD');
    if i <= 3 and (r ->> 'filled')::bigint <> 1000 then raise exception 'trade % did not fill: %', i, r; end if;
    if i = 4 and (r ->> 'filled')::bigint <> 0 then raise exception 'pair limit not enforced: %', r; end if;
  end loop;
  select shares into bought from public.exchange_holdings where listing_id = lid and owner_id = b;
  if bought <> 3000 then raise exception 'unexpected holding %', bought; end if;
  perform pg_temp.as_user(b);
  perform public.place_exchange_order(lid, 'sell', 500, 40, 'USD');
  perform pg_temp.as_user(c);
  r := public.place_exchange_order(lid, 'buy', 500, 40, 'USD');
  if (r ->> 'filled')::bigint <> 0 then raise exception 'cooling period not enforced: %', r; end if;
  if (select count(*) from public.settlements where recipient_id = c and kind = 'exchange_sale') <> 3 then raise exception 'sale settlements'; end if;
  perform pg_temp.as_user(a);
  r := public.place_exchange_order(lid, 'buy', 500, 40, 'USD');
  perform pg_temp.as_user(b);
  r := public.place_exchange_order(lid, 'sell', 500, 40, 'USD');
  if exists (select 1 from public.exchange_trades where listing_id = lid and buyer_id = a and seller_id = b) then raise exception 'linked accounts traded with each other'; end if;
end $$;

do $$
declare c uuid := pg_temp.id('c'); lid uuid := (select id from public.exchange_listings limit 1); i int; res text;
begin
  perform pg_temp.as_user(c);
  for i in 1..25 loop
    begin
      perform public.place_exchange_order(lid, 'sell', 1, 40 + i * 0.001, 'USD');
    exception when others then
      res := sqlerrm;
      exit;
    end;
  end loop;
  if res is distinct from 'too_many_orders' then raise exception 'open order cap not enforced: %', res; end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); c uuid := pg_temp.id('c'); lid uuid; cid uuid; wk date := date_trunc('week', now())::date - 7; price numeric; n int; q int;
        ln text := (select line_id from public.supply_trade_lines where trade_id = 'bakery' order by line_id limit 1);
begin
  perform pg_temp.as_user(c);
  lid := (public.save_supply_listing(null, 'own.8', 'Cole Bakes', 'bakery', 'Leeds', 'GB', ln, 1, 1, 100, 3, 1, 14, 7, 10, 'USD') ->> 'id')::uuid;
  perform pg_temp.as_user(a);
  cid := (public.sign_supply_contract('own.1', ln, lid, 15, 'USD') ->> 'id')::uuid;
  select unit_price into price from public.supply_contracts where id = cid;
  update public.supply_contracts set signed_at = wk::timestamp at time zone 'UTC' + interval '2 days' where id = cid;
  update public.profiles set last_seen_at = now() where id in (a, c);
  perform private.run_supply_week(wk);
  perform private.run_supply_week(wk);
  select count(*) into n from public.settlements where kind = 'supply_sale' and recipient_id = c;
  if n <> 1 then raise exception 'supply sale settled % times', n; end if;
  select units_asked into q from public.supply_orders where contract_id = cid and week = wk;
  if q <> 11 then raise exception 'billing not prorated to days under contract: %', q; end if;
  if (select amount from public.settlements where kind = 'supply_sale' and recipient_id = c) <> 11 * price then raise exception 'sale amount'; end if;
  if (select amount from public.settlements where kind = 'supply_purchase' and recipient_id = a) <> -11 * price then raise exception 'purchase amount'; end if;
  update public.profiles set last_seen_at = now() - interval '30 days' where id = a;
  perform private.run_supply_week(date_trunc('week', now())::date);
  if (select end_reason from public.supply_contracts where id = cid) <> 'expired' then raise exception 'contract of an absent buyer kept running'; end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); c uuid := pg_temp.id('c'); code text; r jsonb;
begin
  select p.code into code from public.profiles p where p.id = a;
  perform pg_temp.as_user(c);
  r := public.profile_by_code(lower(replace(code, '-', '')));
  if r ->> 'id' <> a::text then raise exception 'code without dash not found: %', r; end if;
  if jsonb_array_length(public.search_players(lower(replace(code, '-', '')))) <> 1 then raise exception 'search by loose code'; end if;
  perform pg_temp.expect_error('select public.profile_by_code(''ZZZ-ZZZZ'')', 'not_found');
end $$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); c uuid := pg_temp.id('c'); n int;
begin
  perform pg_temp.as_user(c);
  set local role authenticated;
  delete from public.friendships where status = 'accepted';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'a stranger deleted % friendships', n; end if;
  perform pg_temp.expect_error('insert into public.reports (reporter_id, target_id, reason) values (''' || a || ''', ''' || b || ''', ''spam'')', 'new row violates row-level security');
  perform pg_temp.expect_error('insert into public.blocks (blocker_id, blocked_id) values (''' || a || ''', ''' || b || ''')', 'new row violates row-level security');
  reset role;
  perform pg_temp.as_user(a);
  set local role authenticated;
  delete from public.friendships where status = 'accepted';
  get diagnostics n = row_count;
  reset role;
  if n < 1 then raise exception 'a party could not end their own friendship'; end if;
end $$;

do $$
declare u uuid := gen_random_uuid(); r jsonb; code text := 'ANON-ADMIN-CODE-2026';
begin
  insert into auth.users (id, aud, role, is_anonymous) values (u, 'authenticated', 'authenticated', true);
  perform pg_temp.as_user(u);
  r := public.account_status();
  if (r ->> 'hasProfile')::boolean or (r ->> 'adultConfirmed')::boolean then raise exception 'anonymous status before profile: %', r; end if;
  perform pg_temp.expect_error('select public.ensure_profile(false)', 'adult_required');
  perform pg_temp.expect_error('select public.redeem_admin_code(''' || code || ''')', 'not_signed_in');
  r := public.ensure_profile(true);
  if r ->> 'id' <> u::text then raise exception 'anonymous profile not created: %', r; end if;
  r := public.account_status();
  if not (r ->> 'adultConfirmed')::boolean or (r ->> 'isAdmin')::boolean then raise exception 'anonymous status after profile: %', r; end if;
  insert into public.admin_codes (code_hash) values (encode(extensions.digest(code, 'sha256'), 'hex'));
  r := public.redeem_admin_code(code);
  if r ->> 'reason' <> 'granted' then raise exception 'anonymous admin code: %', r; end if;
  if not (public.account_status() ->> 'isAdmin')::boolean then raise exception 'anonymous admin not recognised'; end if;
end $$;

do $$
declare x uuid := pg_temp.mk_player('Xena Fox'); y uuid := pg_temp.mk_player('Yan Yu'); z uuid := pg_temp.mk_player('Zed Zim');
        wk int := private.friend_week(); r jsonb; gid uuid; ok boolean;
begin
  insert into public.friendships (requester_id, addressee_id, status) values (x, y, 'accepted');

  perform pg_temp.as_user(x);
  gid := public.send_friend_gift(y, 'artifact.test', 7);
  perform pg_temp.expect_error('select public.send_friend_gift(''' || y || ''', ''artifact.test'', 8)', 'gift_limit');
  perform pg_temp.expect_error('select public.send_friend_gift(''' || z || ''', ''artifact.test'', 9)', 'not_found');
  if (select count(*) from public.friend_gifts where sender_id = x) <> 1 then raise exception 'daily gift limit not enforced'; end if;

  perform pg_temp.as_user(z);
  if jsonb_array_length(public.received_friend_gifts()) <> 0 then raise exception 'stranger sees a gift'; end if;
  perform public.accept_friend_gifts(array[gid]);
  if exists (select 1 from public.friend_gifts where id = gid and accepted_at is not null) then raise exception 'stranger accepted a gift'; end if;

  perform pg_temp.as_user(y);
  r := public.received_friend_gifts();
  if jsonb_array_length(r) <> 1 or r -> 0 ->> 'fromName' <> 'Xena Fox' or r -> 0 ->> 'defID' <> 'artifact.test' then raise exception 'gift inbox shows %', r; end if;
  perform public.accept_friend_gifts(array[gid]);
  if jsonb_array_length(public.received_friend_gifts()) <> 0 then raise exception 'accepted gift still in the inbox'; end if;

  perform pg_temp.as_user(x);
  perform public.submit_race_score(wk, 0.25);
  perform pg_temp.as_user(z);
  perform public.submit_race_score(wk, 0.5);
  perform pg_temp.as_user(y);
  r := public.read_race(wk);
  if jsonb_array_length(r) <> 1 or r -> 0 ->> 'id' <> x::text then raise exception 'friend race shows %', r; end if;
  perform pg_temp.as_user(z);
  if jsonb_array_length(public.read_race(wk)) <> 0 then raise exception 'stranger reads a friend race'; end if;
  perform pg_temp.expect_error('select public.submit_race_score(1, 0.1)', 'invalid_value');

  insert into public.blocks (blocker_id, blocked_id) values (y, x);
  perform pg_temp.as_user(y);
  if jsonb_array_length(public.read_race(wk)) <> 0 then raise exception 'blocked player in the race'; end if;
  delete from public.blocks where blocker_id = y;
  insert into public.friendships (requester_id, addressee_id, status) values (x, y, 'accepted') on conflict do nothing;

  perform pg_temp.as_user(x);
  perform public.submit_goal_units(wk, 400);
  perform pg_temp.as_user(y);
  perform public.submit_goal_units(wk, 100);
  perform pg_temp.as_user(x);
  if public.claim_friend_goal(wk) then raise exception 'goal claimed below target'; end if;
  perform pg_temp.as_user(y);
  perform public.submit_goal_units(wk, 300);
  perform pg_temp.as_user(x);
  ok := public.claim_friend_goal(wk);
  if not ok then raise exception 'goal not claimable at target'; end if;
  if public.claim_friend_goal(wk) then raise exception 'goal reward claimed twice'; end if;
  perform pg_temp.as_user(z);
  if public.claim_friend_goal(wk) then raise exception 'stranger claimed a goal'; end if;
end $$;

do $$ declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); tok text := repeat('cd', 32);
begin
  perform pg_temp.as_user(a);
  perform public.register_push_token(tok, 'sandbox', '{gift,auction}');
  perform public.register_push_token(tok, 'sandbox', '{gift}');
  if (select count(*) from public.device_tokens where token = tok) <> 1 then raise exception 'push token not upserted'; end if;
  perform pg_temp.expect_error($q$select public.register_push_token('short', 'sandbox', '{}')$q$, 'invalid_value');
  perform private.queue_push(a, 'auction', 'x', 'y');
  if exists (select 1 from public.push_outbox where user_id = a and category = 'auction') then raise exception 'push queued for a disabled category'; end if;
  perform private.queue_push(a, 'gift', 'x', 'y');
  if not exists (select 1 from public.push_outbox where user_id = a and category = 'gift') then raise exception 'push not queued'; end if;
  perform pg_temp.as_user(b);
  perform public.register_push_token(tok, 'production', '{gift}');
  if (select user_id from public.device_tokens where token = tok) <> b then raise exception 'push token did not move to the new owner'; end if;
end $$;

do $$ declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); c uuid := pg_temp.id('c');
begin
  perform pg_temp.as_user(a);
  if public.username_available('ab') <> 'invalid' then raise exception 'two letters accepted'; end if;
  if public.username_available('abcdefghijklmnopq') <> 'invalid' then raise exception '17 characters accepted'; end if;
  if public.username_available('bad name') <> 'invalid' then raise exception 'space accepted'; end if;
  if public.username_available('9lives') <> 'invalid' then raise exception 'leading digit accepted'; end if;
  if public.username_available('Admin_one') <> 'invalid' then raise exception 'reserved word accepted'; end if;
  if public.claim_username('Tiger_7') <> 'ok' then raise exception 'claim failed'; end if;
  if (select username from public.profiles where id = a) <> 'Tiger_7' or (select display_name from public.profiles where id = a) <> 'Tiger_7' then raise exception 'claim not stored'; end if;
  perform pg_temp.as_user(b);
  if public.username_available('tiger_7') <> 'taken' then raise exception 'case-insensitive duplicate offered'; end if;
  if public.claim_username('TIGER_7') <> 'taken' then raise exception 'duplicate claimed'; end if;
  if public.claim_username('Cora') <> 'ok' then raise exception 'free name refused'; end if;
  perform pg_temp.as_user(c);
  if public.claim_username('Cora') <> 'taken' then raise exception 'name of another player claimed'; end if;
  perform pg_temp.as_user(a);
  if public.claim_username('Tiger_8') <> 'ok' then raise exception 'change failed'; end if;
  perform pg_temp.as_user(b);
  if public.claim_username('Tiger_7') <> 'taken' then raise exception 'released name was reused'; end if;
  perform pg_temp.as_user(a);
  if public.claim_username('tiger_7') <> 'ok' then raise exception 'owner cannot return to own name'; end if;
  perform public.update_my_profile(p_display_name => 'Sneaky Name');
  if (select display_name from public.profiles where id = a) <> 'tiger_7' then raise exception 'display name changed outside the claim'; end if;
end $$;

create function pg_temp.mk_item(k text, nm text, ttl text) returns jsonb language sql as $$
  select jsonb_build_object('id', nm, 'kind', k, 'title', ttl, 'family', r, 'ref', r, 'age', 4, 'km', 60000, 'seen', 0.7, 'cond', 0.5, 'base', 400000)
    from (select case k when 'van' then 'van_s' when 'boat' then 'y1' when 'equipment' then 'oven' when 'plane' then 'j1' when 'luxury' then 'w1' else 'car_s' end as r) x;
$$;

create function pg_temp.notes(uid uuid, kind text) returns int language sql as $$
  select count(*)::int from public.settlements s where s.recipient_id = $1 and s.kind = $2;
$$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('c'); c uuid := pg_temp.id('n'); l jsonb; d jsonb; r jsonb; lid uuid; did uuid;
begin
  perform pg_temp.as_user(a);
  l := public.market_list(pg_temp.mk_item('car', 'it-1', 'Old estate car'), 50000, 'NOK');
  lid := (l ->> 'id')::uuid;
  perform pg_temp.expect_error('select public.market_list(pg_temp.mk_item(''car'', ''it-1'', ''Old estate car''), 50000, ''NOK'')', 'already_listed');
  perform pg_temp.expect_error('select public.market_list(pg_temp.mk_item(''spaceship'', ''it-2'', ''Rocket''), 50000, ''NOK'')', 'invalid_item');
  perform pg_temp.expect_error('select public.market_list(pg_temp.mk_item(''car'', ''it-3'', ''Cheap car''), 0, ''NOK'')', 'invalid_price');
  if exists (select 1 from jsonb_array_elements(public.market_browse('car', 60)) e where e ->> 'id' = lid::text) then raise exception 'seller sees own listing in browse'; end if;

  perform pg_temp.as_user(b);
  update public.profiles set last_seen_at = now() where id = a;
  r := public.market_browse('car', 60);
  if not exists (select 1 from jsonb_array_elements(r) e where e ->> 'id' = lid::text and (e ->> 'sellerOnline')::boolean and e ->> 'sellerName' = (select display_name from public.profiles where id = a)) then raise exception 'listing or seller presence missing: %', r; end if;
  update public.profiles set last_seen_at = now() - interval '1 hour' where id = a;
  if (select (e ->> 'sellerOnline')::boolean from jsonb_array_elements(public.market_browse('car', 60)) e where e ->> 'id' = lid::text) then raise exception 'seller shown online after an hour'; end if;

  d := public.market_buy(lid);
  did := (d ->> 'id')::uuid;
  if d ->> 'status' <> 'pending' or (d ->> 'price')::numeric <> 50000 then raise exception 'buy request wrong: %', d; end if;
  perform pg_temp.expect_error('select public.market_buy(''' || lid || '''::uuid)', 'deal_open');
  perform pg_temp.expect_error('select public.market_offer(''' || lid || '''::uuid, 40000)', 'deal_open');
  if pg_temp.notes(a, 'market_notice') <> 1 then raise exception 'seller was not notified of the request'; end if;
  perform pg_temp.as_user(c);
  perform pg_temp.expect_error('select public.market_respond(''' || did || '''::uuid, ''accept'', null)', 'not_found');
  perform pg_temp.as_user(a);
  r := public.market_mine();
  if jsonb_array_length(r -> 'incoming') <> 1 or r -> 'incoming' -> 0 ->> 'otherName' <> (select display_name from public.profiles where id = b) then raise exception 'incoming deal missing: %', r; end if;
  r := public.market_respond(did, 'accept', null);
  if r ->> 'status' <> 'accepted' then raise exception 'accept failed: %', r; end if;
  if (select amount from public.settlements where recipient_id = a and kind = 'market_sale') <> 50000 then raise exception 'seller was not paid'; end if;
  if not exists (select 1 from public.settlements where recipient_id = b and kind = 'market_purchase' and amount = 0 and meta -> 'item' ->> 'id' = 'it-1' and (meta ->> 'price')::numeric = 50000) then raise exception 'buyer item settlement missing'; end if;
  if (select status from public.market_listings where id = lid) <> 'sold' then raise exception 'listing not sold'; end if;
  perform pg_temp.as_user(c);
  perform pg_temp.expect_error('select public.market_buy(''' || lid || '''::uuid)', 'not_found');
  perform pg_temp.expect_error('select public.market_respond(''' || did || '''::uuid, ''accept'', null)', 'not_found');
end $$;

do $$
declare a uuid := pg_temp.id('a'); l jsonb;
begin
  perform pg_temp.as_user(a);
  l := public.market_list(pg_temp.mk_item('boat', 'it-5', 'Small boat'), 9000, 'NOK');
  perform pg_temp.as_user((select id from cast_ids where k = 'b'));
  perform pg_temp.expect_error('select public.market_buy(''' || (l ->> 'id') || '''::uuid)', 'own_listing');
  perform pg_temp.as_user(a);
  perform public.market_cancel((l ->> 'id')::uuid);
end $$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('c'); c uuid := pg_temp.id('n'); l jsonb; d jsonb; r jsonb; lid uuid; did uuid; did2 uuid;
begin
  perform pg_temp.as_user(a);
  l := public.market_list(pg_temp.mk_item('van', 'it-10', 'Work van'), 1000, 'NOK');
  lid := (l ->> 'id')::uuid;
  perform pg_temp.as_user(b);
  perform pg_temp.expect_error('select public.market_offer(''' || lid || '''::uuid, 1000)', 'offer_not_lower');
  perform pg_temp.expect_error('select public.market_offer(''' || lid || '''::uuid, 100)', 'offer_too_low');
  d := public.market_offer(lid, 800);
  did := (d ->> 'id')::uuid;
  perform pg_temp.expect_error('select public.market_offer(''' || lid || '''::uuid, 850)', 'offer_used');
  perform pg_temp.expect_error('select public.market_buy(''' || lid || '''::uuid)', 'deal_open');
  r := (select e from jsonb_array_elements(public.market_browse(null, 60)) e where e ->> 'id' = lid::text);
  if not (r ->> 'offerUsed')::boolean or r -> 'myDeal' ->> 'status' <> 'pending' then raise exception 'listing does not show my offer: %', r; end if;

  perform pg_temp.as_user(c);
  d := public.market_offer(lid, 700);
  did2 := (d ->> 'id')::uuid;

  perform pg_temp.as_user(a);
  perform pg_temp.expect_error('select public.market_respond(''' || did || '''::uuid, ''discuss'', 1000)', 'price_not_lower');
  perform pg_temp.expect_error('select public.market_respond(''' || did || '''::uuid, ''bogus'', null)', 'invalid_action');
  r := public.market_respond(did, 'discuss', 900);
  if r ->> 'status' <> 'discussing' then raise exception 'discuss failed: %', r; end if;
  perform pg_temp.expect_error('select public.market_respond(''' || did || '''::uuid, ''discuss'', 850)', 'already_discussing');
  r := public.market_respond(did2, 'decline', null);
  if r ->> 'status' <> 'declined' then raise exception 'decline failed: %', r; end if;

  perform pg_temp.as_user(c);
  perform pg_temp.expect_error('select public.market_offer(''' || lid || '''::uuid, 750)', 'offer_used');
  if pg_temp.notes(c, 'market_refund') <> 1 then raise exception 'declined buyer got no refund notice'; end if;
  perform pg_temp.as_user(b);
  perform pg_temp.expect_error('select public.market_answer(''' || did2 || '''::uuid, true)', 'not_found');
  if (select status from public.market_offers where id = did) <> 'discussing' then raise exception 'offer lost its discussion'; end if;
  r := public.market_answer(did, true);
  if r ->> 'status' <> 'accepted' or (r ->> 'price')::numeric <> 900 then raise exception 'special price not honoured: %', r; end if;
  if not exists (select 1 from public.settlements where recipient_id = a and kind = 'market_sale' and amount = 900) then raise exception 'seller not paid the special price'; end if;
  if not exists (select 1 from public.settlements where recipient_id = b and kind = 'market_purchase' and (meta ->> 'price')::numeric = 900) then raise exception 'buyer settlement missing special price'; end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('c'); c uuid := pg_temp.id('n'); l jsonb; d jsonb; lid uuid; did uuid; did2 uuid; before_b int; before_c int;
begin
  perform pg_temp.as_user(a);
  l := public.market_list(pg_temp.mk_item('equipment', 'it-20', 'Pizza oven'), 5000, 'NOK');
  lid := (l ->> 'id')::uuid;
  perform pg_temp.as_user(b);
  did := (public.market_buy(lid) ->> 'id')::uuid;
  perform pg_temp.as_user(c);
  did2 := (public.market_offer(lid, 4000) ->> 'id')::uuid;
  before_b := pg_temp.notes(b, 'market_refund');
  before_c := pg_temp.notes(c, 'market_refund');
  perform pg_temp.as_user(b);
  d := public.market_withdraw(did);
  if d ->> 'status' <> 'withdrawn' or pg_temp.notes(b, 'market_refund') <> before_b + 1 then raise exception 'withdraw did not refund'; end if;
  perform pg_temp.expect_error('select public.market_withdraw(''' || did || '''::uuid)', 'not_found');
  perform pg_temp.as_user(a);
  perform pg_temp.expect_error('select public.market_cancel(''' || pg_temp.id('c') || '''::uuid)', 'not_found');
  perform public.market_cancel(lid);
  if (select status from public.market_listings where id = lid) <> 'cancelled' then raise exception 'listing not cancelled'; end if;
  if pg_temp.notes(c, 'market_refund') <> before_c + 1 then raise exception 'cancel did not refund the open offer'; end if;
  if not exists (select 1 from public.settlements where recipient_id = a and kind = 'market_unlist' and meta ->> 'itemID' = 'it-20') then raise exception 'seller not told to unlock the item'; end if;
  perform public.market_cancel(lid);

  l := public.market_list(pg_temp.mk_item('equipment', 'it-21', 'Mixer'), 3000, 'NOK');
  lid := (l ->> 'id')::uuid;
  perform pg_temp.as_user(b);
  did := (public.market_buy(lid) ->> 'id')::uuid;
  update public.market_listings set expires_at = now() - interval '1 minute' where id = lid;
  perform private.market_expire();
  if (select status from public.market_listings where id = lid) <> 'expired' or (select status from public.market_offers where id = did) <> 'closed' then raise exception 'expiry did not close the listing and its deal'; end if;
  if not exists (select 1 from public.settlements where recipient_id = a and kind = 'market_unlist' and meta ->> 'itemID' = 'it-21') then raise exception 'expiry did not unlock for the seller'; end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('c'); bot uuid; i int; lid uuid; did uuid; r jsonb; ok int := 0; kinds text[] := array['car', 'van', 'plane', 'boat', 'equipment', 'luxury']; k text;
begin
  foreach k in array kinds loop
    for i in 1..3 loop
      select user_id into bot from public.bots where active order by abs(hashtext(k || i::text || user_id::text)) limit 1;
      perform private.market_bot_list(bot, 'test:' || k || ':' || i, k);
    end loop;
  end loop;
  perform pg_temp.as_user(b);
  r := public.market_browse(null, 100);
  foreach k in array kinds loop
    if not exists (select 1 from jsonb_array_elements(r) e where e ->> 'kind' = k) then raise exception 'no listing of kind % from the world', k; end if;
  end loop;
  if exists (select 1 from jsonb_array_elements(r) e where (e -> 'item' ->> 'base')::numeric <= 0 or (e ->> 'price')::numeric <= 0) then raise exception 'bad generated prices'; end if;
  if exists (select 1 from jsonb_array_elements(r) e where e::text ilike '%is_bot%' or e::text ilike '%fake%' or e::text ilike '%simulated%') then raise exception 'generated listings are labelled'; end if;

  for lid in select m.id from public.market_listings m join public.profiles p on p.id = m.seller_id where p.is_bot and m.status = 'active' and m.kind in ('car', 'van') order by m.created_at, m.id limit 6 loop
    did := (public.market_buy(lid) ->> 'id')::uuid;
    if (select status from public.market_offers where id = did) <> 'pending' then raise exception 'bot answered at once'; end if;
  end loop;
  perform private.market_bot_respond();
  if (select count(*) from public.market_offers where status = 'pending' and seller_id in (select user_id from public.bots)) <> 6 then raise exception 'bots answered before any human delay'; end if;
  update public.market_offers set created_at = now() - interval '5 hours' where status = 'pending' and seller_id in (select user_id from public.bots);
  perform private.market_bot_respond();
  if exists (select 1 from public.market_offers where status = 'pending' and seller_id in (select user_id from public.bots)) then raise exception 'bots never answered'; end if;
  select count(*) into ok from public.market_offers where buyer_id = b and status = 'accepted' and seller_id in (select user_id from public.bots);
  if ok < 1 then raise exception 'no bot ever accepted a request'; end if;
  if pg_temp.notes(b, 'market_purchase') <> ok + 2 then raise exception 'purchase settlements do not match accepted deals'; end if;
  if exists (select 1 from public.settlements where kind in ('market_sale', 'market_notice', 'market_unlist') and recipient_id in (select user_id from public.bots)) then raise exception 'a generated seller was paid or notified'; end if;

  select m.id into lid from public.market_listings m join public.profiles p on p.id = m.seller_id where p.is_bot and m.status = 'active' order by m.created_at, m.id limit 1;
  did := (public.market_offer(lid, round((select price from public.market_listings where id = lid) * 0.8, 2)) ->> 'id')::uuid;
  update public.market_offers set created_at = now() - interval '5 hours' where id = did;
  perform private.market_bot_respond();
  r := (select to_jsonb(o) from public.market_offers o where id = did);
  if r ->> 'status' <> 'discussing' or (r ->> 'special_price')::numeric <= (r ->> 'price')::numeric then raise exception 'a middling offer did not get a counter price: %', r; end if;
end $$;

do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('c'); r jsonb; lid uuid; did uuid;
begin
  insert into public.admins (user_id) values (a);
  select m.id into lid from public.market_listings m join public.profiles p on p.id = m.seller_id
   where p.is_bot and m.status = 'active' and not exists (select 1 from public.market_offers o where o.listing_id = m.id and o.buyer_id = b) order by m.created_at, m.id limit 1;
  perform pg_temp.as_user(b);
  did := (public.market_buy(lid) ->> 'id')::uuid;
  perform pg_temp.as_user(a);
  r := public.admin_remove_fake_players('Marketplace test');
  if exists (select 1 from public.market_listings m join public.profiles p on p.id = m.seller_id where p.is_bot and m.status = 'active') then raise exception 'generated listings survived the removal'; end if;
  if exists (select 1 from public.market_offers where status in ('pending', 'discussing') and seller_id in (select id from public.profiles where is_bot)) then raise exception 'generated deals survived the removal'; end if;
  if not exists (select 1 from public.settlements where kind = 'market_refund' and recipient_id = b and meta ->> 'dealID' = did::text) then raise exception 'open deal with a removed seller was not refunded'; end if;
  perform pg_temp.as_user(b);
  if exists (select 1 from jsonb_array_elements(public.market_browse(null, 100)) e where e ->> 'sellerID' in (select id::text from public.profiles where is_bot)) then raise exception 'removed sellers still browseable'; end if;
  if private.market_bot_stock() <> 0 then raise exception 'listings restocked after the removal'; end if;
end $$;

create temp table board_cast (k text primary key, id uuid);
grant select on board_cast to authenticated;
insert into board_cast select 'd', pg_temp.mk_player('Dana Dale');
insert into board_cast select 'e', pg_temp.mk_player('Eli Eden');
insert into board_cast select 'f', pg_temp.mk_player('Fay Ford');
insert into board_cast select 'o', pg_temp.mk_player('Otto Outsider');
create function pg_temp.bid(k text) returns uuid language sql as $$ select id from board_cast where k = $1 $$;
create function pg_temp.pushes(uid uuid) returns int language sql as $$ select count(*)::int from public.push_outbox where user_id = uid and category = 'board' $$;
create function pg_temp.mk_bot(nm text) returns uuid language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role) values (u, 'authenticated', 'authenticated');
  insert into public.profiles (id, display_name, adult_confirmed, is_bot, created_at) values (u, nm, true, true, now() - interval '90 days');
  return u;
end $$;

do $$
declare d uuid := pg_temp.bid('d'); e uuid := pg_temp.bid('e'); f uuid := pg_temp.bid('f'); o uuid := pg_temp.bid('o'); k text; vid uuid; r jsonb; inv uuid;
begin
  insert into public.friendships (requester_id, addressee_id, status, responded_at) values (d, e, 'accepted', now()), (d, f, 'accepted', now());
  foreach k in array array['d', 'e', 'f'] loop
    perform pg_temp.as_user(pg_temp.bid(k));
    perform public.register_push_token(repeat(k, 64), 'sandbox', array['board']);
  end loop;

  perform pg_temp.as_user(d);
  vid := (public.create_venture('own.9', 'Dale Works', 900000, 'USD') ->> 'id')::uuid;
  r := public.propose_venture_change(vid, 'policy', '{"policy":"low"}'::jsonb, true);
  if not (r ->> 'applied')::boolean or (select dividend_policy from public.ventures where id = vid) <> 'low' then raise exception 'a sole owner did not set the policy directly: %', r; end if;
  if exists (select 1 from public.venture_meetings where venture_id = vid) then raise exception 'a sole owner got a meeting'; end if;
  perform pg_temp.expect_error(format('select public.propose_venture_change(%L, ''policy'', ''{"policy":"low"}''::jsonb, true)', vid), 'already_set');
  perform pg_temp.expect_error(format('select public.propose_venture_change(%L, ''policy'', ''{"policy":"all"}''::jsonb, true)', vid), 'invalid_agenda');

  inv := (public.invite_venture_partner(vid, e, 10, 100000) ->> 'id')::uuid;
  if pg_temp.pushes(e) <> 1 then raise exception 'the invitee got no push'; end if;
  perform pg_temp.as_user(e);
  r := public.my_venture_offers();
  if jsonb_array_length(r) <> 1 or (r -> 0 ->> 'pct')::numeric <> 10 or (r -> 0 ->> 'price')::numeric <> 100000 then raise exception 'the invitee does not see share and price: %', r; end if;
  perform public.reply_to_venture_offer(inv, false, 'USD');
  if private.is_partner(vid, e) or exists (select 1 from public.settlements where recipient_id in (d, e) and kind in ('venture_stake', 'venture_capital')) then
    raise exception 'a declined invitation moved shares or money';
  end if;

  perform pg_temp.as_user(d);
  inv := (public.invite_venture_partner(vid, e, 10, 100000) ->> 'id')::uuid;
  perform pg_temp.as_user(e);
  perform public.reply_to_venture_offer(inv, true, 'USD');
  if not private.is_partner(vid, e) or pg_temp.notes(e, 'venture_stake') <> 1 or pg_temp.notes(d, 'venture_capital') <> 1 then raise exception 'an accepted invitation did not settle'; end if;
  if (select amount from public.settlements where recipient_id = e and kind = 'venture_stake') <> -100000 then raise exception 'the invitee paid another price'; end if;

  update public.ventures set value = 1000000 where id = vid;
  perform pg_temp.as_user(d);
  inv := (public.invite_venture_partner(vid, f, 49, round(private.jv_fair_price(1000000, 49), 2)) ->> 'id')::uuid;
  perform pg_temp.as_user(f);
  perform public.reply_to_venture_offer(inv, true, 'USD');
  if (select 100.0 * shares / private.jv_total_shares(vid) from public.venture_partners where venture_id = vid and member_id = d) >= 50 then raise exception 'the chair still holds a majority'; end if;
  perform pg_temp.as_user(o);
  perform pg_temp.expect_error(format('select public.propose_venture_change(%L, ''policy'', ''{"policy":"mid"}''::jsonb, true)', vid), 'not_found');
end $$;

do $$
declare d uuid := pg_temp.bid('d'); e uuid := pg_temp.bid('e'); f uuid := pg_temp.bid('f'); o uuid := pg_temp.bid('o'); vid uuid; r jsonb; mid uuid; iid uuid;
        pe int := pg_temp.pushes(pg_temp.bid('e')); pf int := pg_temp.pushes(pg_temp.bid('f')); pd int := pg_temp.pushes(pg_temp.bid('d'));
begin
  select id into vid from public.ventures where chair_id = d and company_key = 'own.9';
  perform pg_temp.as_user(d);
  r := public.propose_venture_change(vid, 'policy', '{"policy":"mid"}'::jsonb, true);
  mid := (r ->> 'meetingID')::uuid;
  if (r ->> 'applied')::boolean or not (r ->> 'emergency')::boolean then raise exception 'a minority owner decided alone: %', r; end if;
  if (select dividend_policy from public.ventures where id = vid) <> 'low' then raise exception 'the policy changed before the vote'; end if;
  if abs(extract(epoch from (select deadline - opened_at from public.venture_meetings where id = mid)) - 86400) > 5 then raise exception 'an emergency meeting is not 24 hours'; end if;
  if pg_temp.pushes(e) <> pe + 1 or pg_temp.pushes(f) <> pf + 1 or pg_temp.pushes(d) <> pd then raise exception 'emergency push went to the wrong owners'; end if;
  if not exists (select 1 from public.push_outbox where user_id = e and category = 'board' and title = 'Emergency board meeting' and body like 'Dana Dale called a vote at Dale Works%24 hours%') then
    raise exception 'the emergency push does not say who, where and how long';
  end if;
  perform pg_temp.expect_error(format('select public.propose_venture_change(%L, ''setting'', ''{"key":"chain.pay","value":0.05}''::jsonb, true)', vid), 'meeting_open');
  select id into iid from public.venture_items where meeting_id = mid;
  if (select choice from public.venture_votes where item_id = iid and member_id = d) <> 'yes' then raise exception 'the proposer is not counted for their own proposal'; end if;
  perform pg_temp.as_user(o);
  perform pg_temp.expect_error(format('select public.cast_venture_vote(%L, ''yes'')', iid), 'not_found');
  perform pg_temp.as_user(e);
  perform public.cast_venture_vote(iid, 'yes');
  if (select closed_at from public.venture_meetings where id = mid) is null or (select outcome from public.venture_items where id = iid) <> 'passed' then raise exception 'over half of all shares in favour did not pass at once'; end if;
  if (select dividend_policy from public.ventures where id = vid) <> 'mid' then raise exception 'a passed policy was not applied'; end if;
  if not exists (select 1 from public.settlements where recipient_id = d and kind = 'venture_decision' and (meta ->> 'apply')::boolean and meta ->> 'companyKey' = 'own.9' and meta -> 'params' ->> 'policy' = 'mid') then
    raise exception 'the chair was not told to carry out the decision';
  end if;
  if not exists (select 1 from public.settlements where recipient_id = f and kind = 'venture_decision' and not (meta ->> 'apply')::boolean and meta ->> 'companyKey' is null) then
    raise exception 'the other owners were not told the result';
  end if;

  perform pg_temp.as_user(d);
  r := public.propose_venture_change(vid, 'policy', '{"policy":"high"}'::jsonb, true);
  mid := (r ->> 'meetingID')::uuid;
  select id into iid from public.venture_items where meeting_id = mid;
  perform pg_temp.as_user(e);
  perform public.cast_venture_vote(iid, 'no');
  perform pg_temp.expect_error(format('select public.close_venture_meeting(%L)', mid), 'voting_open');
  update public.venture_meetings set deadline = now() - interval '1 minute' where id = mid;
  perform pg_temp.expect_error(format('select public.cast_venture_vote(%L, ''yes'')', iid), 'vote_closed');
  perform private.run_venture_housekeeping();
  if (select outcome from public.venture_items where id = iid) <> 'failed' or (select dividend_policy from public.ventures where id = vid) <> 'mid' then
    raise exception 'a proposal without half of all shares did not fail at the deadline';
  end if;
end $$;

do $$
declare d uuid := pg_temp.bid('d'); e uuid := pg_temp.bid('e'); f uuid := pg_temp.bid('f'); vid uuid; r jsonb; mid uuid; iid uuid; iid2 uuid; pf int := pg_temp.pushes(pg_temp.bid('f')); slot timestamptz;
begin
  select id into vid from public.ventures where chair_id = d and company_key = 'own.9';
  perform pg_temp.as_user(e);
  r := public.propose_venture_change(vid, 'setting', '{"key":"chain.price","value":1,"label":"Chain price rule: premium"}'::jsonb, false);
  mid := (r ->> 'meetingID')::uuid;
  select deadline into slot from public.venture_meetings where id = mid;
  if (r ->> 'emergency')::boolean or (r ->> 'applied')::boolean then raise exception 'the weekly meeting was treated as an emergency: %', r; end if;
  if extract(isodow from slot at time zone 'utc') <> 1 or (slot at time zone 'utc')::time <> '00:00' or slot < now() + interval '24 hours' or slot > now() + interval '8 days' then
    raise exception 'the weekly meeting is not the next Monday with a day of notice: %', slot;
  end if;
  if pg_temp.pushes(f) <> pf then raise exception 'a weekly agenda item sent an emergency push'; end if;
  perform pg_temp.as_user(d);
  r := public.propose_venture_change(vid, 'setting', '{"key":"chain.pay","value":0.05,"label":"Chain pay rule: 5% above market"}'::jsonb, false);
  if (r ->> 'meetingID')::uuid <> mid then raise exception 'a second item opened a second weekly meeting'; end if;
  select id into iid from public.venture_items where meeting_id = mid and params ->> 'key' = 'chain.price';
  select id into iid2 from public.venture_items where meeting_id = mid and params ->> 'key' = 'chain.pay';
  perform public.cast_venture_vote(iid, 'yes');
  if (select closed_at from public.venture_meetings where id = mid) is not null then raise exception 'the weekly meeting closed before its day'; end if;
  r := public.venture_meeting(mid);
  if (r -> 'items' -> 0 ->> 'title') <> 'Chain price rule: premium' or (r -> 'items' -> 0 ->> 'yesShares')::numeric * 2 <= (r ->> 'totalShares')::numeric then raise exception 'meeting view lacks title or tally: %', r; end if;
  perform pg_temp.expect_error(format('select public.close_venture_meeting(%L)', mid), 'voting_open');
  update public.venture_meetings set deadline = now() - interval '1 minute' where id = mid;
  perform private.run_venture_housekeeping();
  if (select outcome from public.venture_items where id = iid) <> 'passed' or (select settings ->> 'chain.price' from public.ventures where id = vid) <> '1' then
    raise exception 'the weekly meeting did not pass the item with over half of all shares';
  end if;
  if (select outcome from public.venture_items where id = iid2) <> 'failed' or (select settings ? 'chain.pay' from public.ventures where id = vid) then
    raise exception 'owners who stayed silent were not counted as abstaining';
  end if;
end $$;

do $$
declare d uuid := pg_temp.bid('d'); e uuid := pg_temp.bid('e'); f uuid := pg_temp.bid('f'); vid uuid; r jsonb; oid uuid; fair numeric; held int; chair int; pe int; pd int; n int;
begin
  select id into vid from public.ventures where chair_id = d and company_key = 'own.9';
  select shares into held from public.venture_partners where venture_id = vid and member_id = e;
  select shares into chair from public.venture_partners where venture_id = vid and member_id = d;
  fair := round(1000000.0 * held / private.jv_total_shares(vid), 2);
  perform pg_temp.as_user(d);
  perform pg_temp.expect_error(format('select public.offer_venture_buyback(%L, %L, %s)', vid, e, fair), 'locked');
  update public.venture_partners set lock_until = now() - interval '1 day' where venture_id = vid;
  perform pg_temp.expect_error(format('select public.offer_venture_buyback(%L, %L, %s)', vid, e, fair * 3), 'outside_band');
  perform pg_temp.as_user(f);
  perform pg_temp.expect_error(format('select public.offer_venture_buyback(%L, %L, %s)', vid, e, fair), 'not_found');
  perform pg_temp.as_user(d);
  pe := pg_temp.pushes(e);
  oid := (public.offer_venture_buyback(vid, e, fair) ->> 'id')::uuid;
  if pg_temp.pushes(e) <> pe + 1 then raise exception 'the holder got no push about the offer'; end if;
  if (select shares from public.venture_partners where venture_id = vid and member_id = e) <> held or exists (select 1 from public.settlements where kind in ('venture_buyback', 'venture_exit') and recipient_id in (d, e)) then
    raise exception 'a buyback offer moved shares or money before it was accepted';
  end if;
  perform pg_temp.expect_error(format('select public.offer_venture_buyback(%L, %L, %s)', vid, e, fair), 'offer_open');
  perform pg_temp.expect_error(format('select public.reply_to_venture_buyback(%L, true)', oid), 'not_found');

  perform pg_temp.as_user(e);
  r := public.my_venture_buybacks();
  if jsonb_array_length(r -> 'incoming') <> 1 or (r -> 'incoming' -> 0 ->> 'price')::numeric <> fair or (r -> 'incoming' -> 0 ->> 'shares')::int <> held then raise exception 'the holder does not see the offer: %', r; end if;
  perform public.reply_to_venture_buyback(oid, false);
  if not private.is_partner(vid, e) or pg_temp.notes(d, 'venture_buyback_reply') <> 1 or pg_temp.notes(d, 'venture_buyback') <> 0 then raise exception 'a declined buyback changed something'; end if;

  pd := pg_temp.pushes(d);
  oid := (public.request_venture_exit(vid, fair) ->> 'id')::uuid;
  if pg_temp.pushes(d) <> pd + 1 or not private.is_partner(vid, e) then raise exception 'asking to sell forced the chair to buy'; end if;
  perform pg_temp.expect_error(format('select public.reply_to_venture_buyback(%L, true)', oid), 'not_found');
  perform public.withdraw_venture_buyback(oid);

  perform pg_temp.as_user(d);
  oid := (public.offer_venture_buyback(vid, e, fair) ->> 'id')::uuid;
  perform pg_temp.as_user(e);
  perform public.reply_to_venture_buyback(oid, true);
  if private.is_partner(vid, e) or (select shares from public.venture_partners where venture_id = vid and member_id = d) <> chair + held then raise exception 'an accepted buyback did not move the shares'; end if;
  if (select amount from public.settlements where recipient_id = e and kind = 'venture_exit') <> fair or (select amount from public.settlements where recipient_id = d and kind = 'venture_buyback') <> -fair then
    raise exception 'an accepted buyback did not pay the agreed price';
  end if;

  perform pg_temp.as_user(f);
  set local role authenticated;
  select count(*) into n from public.venture_buybacks;
  if n <> 0 then raise exception 'buyback offers of other owners are visible: %', n; end if;
  perform pg_temp.expect_error(format('insert into public.venture_buybacks (venture_id, buyer_id, seller_id, shares, price, fair, proposed_by) values (%L, %L, %L, 1, 1, 1, %L)', vid, d, f, d), 'permission denied');
  perform pg_temp.expect_error(format('update public.ventures set dividend_policy = ''high'' where id = %L', vid), 'permission denied');
  perform pg_temp.expect_error(format('select public.leave_venture(%L)', vid), 'permission denied');
  reset role;
end $$;

do $$
declare d uuid := pg_temp.bid('d'); f uuid := pg_temp.bid('f'); bot uuid := pg_temp.mk_bot('Greta Gale'); vid uuid; r jsonb; inv uuid; mid uuid; oid uuid; i int; n int; fair numeric; voted int;
begin
  select id into vid from public.ventures where chair_id = d and company_key = 'own.9';
  fair := round(private.jv_fair_price(1000000, 5), 2);
  perform pg_temp.as_user(d);
  perform pg_temp.expect_error(format('select public.invite_venture_partner(%L, %L, 5, %s)', vid, bot, fair), 'not_friends');
  insert into public.friendships (requester_id, addressee_id, status, responded_at) values (d, bot, 'accepted', now());
  inv := (public.invite_venture_partner(vid, bot, 5, round(fair * 1.2, 2)) ->> 'id')::uuid;
  update public.venture_invites set sent_at = now() - interval '12 hours' where id = inv;
  perform private.run_venture_housekeeping();
  if (select status from public.venture_invites where id = inv) <> 'declined' or private.is_partner(vid, bot) then raise exception 'a player the world runs paid more than the fair price'; end if;
  for i in 1..12 loop
    inv := (public.invite_venture_partner(vid, bot, 5, fair) ->> 'id')::uuid;
    perform private.run_venture_housekeeping();
    if (select status from public.venture_invites where id = inv) <> 'pending' then raise exception 'a generated player answered at once'; end if;
    update public.venture_invites set sent_at = now() - interval '12 hours' where id = inv;
    perform private.run_venture_housekeeping();
    if (select status from public.venture_invites where id = inv) = 'pending' then raise exception 'a generated player never answered the invitation'; end if;
    exit when private.is_partner(vid, bot);
  end loop;
  if not private.is_partner(vid, bot) then raise exception 'no generated player ever accepted a fair invitation'; end if;
  if exists (select 1 from public.settlements where recipient_id = bot) then raise exception 'a generated player was paid or billed'; end if;

  for i in 1..6 loop
    r := public.propose_venture_change(vid, 'setting', jsonb_build_object('key', 'rule.' || i, 'value', i, 'label', 'Rule ' || i), false);
  end loop;
  mid := (r ->> 'meetingID')::uuid;
  perform private.run_venture_housekeeping();
  if exists (select 1 from public.venture_votes x join public.venture_items it on it.id = x.item_id where it.meeting_id = mid and x.member_id = bot) then raise exception 'a generated co-owner voted at once'; end if;
  update public.venture_items set created_at = now() - interval '15 hours' where meeting_id = mid;
  perform private.run_venture_housekeeping();
  select count(*) into voted from public.venture_votes x join public.venture_items it on it.id = x.item_id where it.meeting_id = mid and x.member_id = bot;
  if voted < 1 then raise exception 'a generated co-owner never voted'; end if;
  r := public.venture_meeting(mid) || jsonb_build_object('venture', public.my_ventures());
  if r::text ilike '%is_bot%' or r::text ilike '%fake%' or r::text ilike '%generated%' or r::text ilike '%simulated%' then raise exception 'generated co-owners are labelled: %', r; end if;
  if (select count(distinct (select array_agg(k order by k) from jsonb_object_keys(p) k)) from jsonb_array_elements(public.my_ventures() -> 0 -> 'partners') p) <> 1 then
    raise exception 'generated co-owners look different in the partner list';
  end if;

  update public.venture_partners set lock_until = now() - interval '1 day' where venture_id = vid and member_id = bot;
  select round(1000000.0 * shares / private.jv_total_shares(vid), 2) into fair from public.venture_partners where venture_id = vid and member_id = bot;
  oid := (public.offer_venture_buyback(vid, bot, fair) ->> 'id')::uuid;
  perform private.run_venture_housekeeping();
  if (select status from public.venture_buybacks where id = oid) <> 'pending' then raise exception 'a generated co-owner answered a buyback at once'; end if;
  update public.venture_buybacks set created_at = now() - interval '12 hours' where id = oid;
  perform private.run_venture_housekeeping();
  if (select status from public.venture_buybacks where id = oid) not in ('accepted', 'declined') then raise exception 'a generated co-owner never answered the buyback'; end if;
  if (select status from public.venture_buybacks where id = oid) = 'accepted' and private.is_partner(vid, bot) then raise exception 'an accepted buyback left the seller in'; end if;

  if not private.is_partner(vid, bot) then
    for i in 1..12 loop
      inv := (public.invite_venture_partner(vid, bot, 5, round(private.jv_fair_price(1000000, 5), 2)) ->> 'id')::uuid;
      update public.venture_invites set sent_at = now() - interval '12 hours' where id = inv;
      perform private.run_venture_housekeeping();
      exit when private.is_partner(vid, bot);
    end loop;
  end if;
  select sum(shares) into n from public.venture_partners where venture_id = vid;
  update public.profiles set deleted_at = now() where id = bot;
  perform private.run_venture_housekeeping();
  if private.is_partner(vid, bot) or (select sum(shares) from public.venture_partners where venture_id = vid) <> n then raise exception 'a removed generated co-owner still holds shares, or shares were lost'; end if;
  if (select every from public.job_runs where name = 'ventures') > interval '10 minutes' then raise exception 'board deadlines are checked too rarely'; end if;
end $$;
