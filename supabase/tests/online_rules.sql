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
  perform pg_temp.expect_error('select public.send_friend_request(''' || (select user_id from public.bots limit 1) || '''::uuid)', 'not_found');
  if exists (select 1 from public.search_players('') s where (s ->> 'playerID')::uuid in (select user_id from public.bots)) then raise exception 'bots are searchable'; end if;
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
begin
  perform pg_temp.as_user(c);
  lid := (public.save_supply_listing(null, 'own.8', 'Cole Bakes', 'bakery', 'Leeds', 'GB', 'goods', 1, 1, 100, 3, 1, 14, 7, 10, 'USD') ->> 'id')::uuid;
  perform pg_temp.as_user(a);
  cid := (public.sign_supply_contract('own.1', 'goods', lid, 15, 'USD') ->> 'id')::uuid;
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
