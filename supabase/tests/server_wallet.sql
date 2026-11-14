-- Server wallet rules (0032): purchases grant once, claims cannot repeat, pity, weekly and daily limits, refunds, gifts, import.
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

create function pg_temp.tx(orig text, product text, extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('originalTransactionId', orig, 'transactionId', orig, 'productId', product, 'bundleId', 'com.matasdovyda.ledger',
                            'environment', 'Sandbox') || extra;
$$;

create function pg_temp.gold(u uuid) returns int language sql as $$ select balance from public.gold_wallets where user_id = u $$;

create temp table cast_ids (k text primary key, id uuid);
insert into cast_ids select 'a', pg_temp.mk_player('Alice Ames');
insert into cast_ids select 'b', pg_temp.mk_player('Bob Berg');
insert into cast_ids select 'c', pg_temp.mk_player('Cora Cole');
insert into cast_ids select 'late', pg_temp.mk_player('Lena Late', 0);
create function pg_temp.id(k text) returns uuid language sql as $$ select id from cast_ids where k = $1 $$;

-- Purchases: one grant per original transaction, first-purchase bonus once, Pro and Founder gold once per account.
do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); r jsonb;
begin
  r := public.grant_purchase(a, 'g-1', 'com.ledger.gold.pouch', pg_temp.tx('g-1', 'com.ledger.gold.pouch'));
  if (r ->> 'gold')::int <> 30 or pg_temp.gold(a) <> 30 then raise exception 'first pouch should pay 20 + 10 bonus: %', r - 'state'; end if;
  r := public.grant_purchase(a, 'g-1', 'com.ledger.gold.pouch', pg_temp.tx('g-1', 'com.ledger.gold.pouch'));
  if (r ->> 'granted')::boolean or pg_temp.gold(a) <> 30 or r ->> 'reason' <> 'already' then raise exception 'second grant of one transaction paid: %', r - 'state'; end if;
  r := public.grant_purchase(b, 'g-1', 'com.ledger.gold.pouch', pg_temp.tx('g-1', 'com.ledger.gold.pouch'));
  if (r ->> 'granted')::boolean or r ->> 'reason' <> 'other_account' or coalesce(pg_temp.gold(b), 0) <> 0 then raise exception 'one transaction paid two accounts: %', r - 'state'; end if;
  r := public.grant_purchase(a, 'g-2', 'com.ledger.gold.pouch', pg_temp.tx('g-2', 'com.ledger.gold.pouch'));
  if (r ->> 'gold')::int <> 20 then raise exception 'first-purchase bonus paid twice: %', r - 'state'; end if;

  r := public.grant_purchase(a, 'pro-1', 'com.ledger.pro', pg_temp.tx('pro-1', 'com.ledger.pro'));
  if (r ->> 'gold')::int <> 250 then raise exception 'pro gold missing: %', r - 'state'; end if;
  r := public.grant_purchase(a, 'pro-2', 'com.ledger.pro.yearly', pg_temp.tx('pro-2', 'com.ledger.pro.yearly'));
  if (r ->> 'gold')::int <> 0 then raise exception 'pro gold paid twice on one account: %', r - 'state'; end if;
  r := public.grant_purchase(b, 'pro-1', 'com.ledger.pro', pg_temp.tx('pro-1', 'com.ledger.pro'));
  if (r ->> 'granted')::boolean then raise exception 'restore on another account paid pro gold again'; end if;

  r := public.grant_purchase(b, 'f-1', 'com.ledger.founder', pg_temp.tx('f-1', 'com.ledger.founder'));
  if (r ->> 'gold')::int <> 600 or (r ->> 'passTiers')::int <> 10 or not private.has_premium(b, 1) then raise exception 'founder grant wrong: %', r - 'state'; end if;

  perform pg_temp.expect_error($q$select public.grant_purchase(pg_temp.id('a'), 'x-1', 'com.ledger.gold.pouch', pg_temp.tx('x-1', 'com.ledger.gold.pouch', '{"bundleId":"com.other"}'))$q$, 'wrong_app');
  perform pg_temp.expect_error($q$select public.grant_purchase(pg_temp.id('a'), 'x-2', 'com.ledger.gold.pouch', pg_temp.tx('x-1', 'com.ledger.gold.pouch'))$q$, 'mismatch');
  perform pg_temp.expect_error($q$select public.grant_purchase(pg_temp.id('a'), 'x-3', 'com.ledger.gold.pouch', pg_temp.tx('x-3', 'com.ledger.gold.pouch', jsonb_build_object('appAccountToken', pg_temp.id('b'))))$q$, 'wrong_account');
  perform pg_temp.expect_error($q$select public.grant_purchase(pg_temp.id('a'), 'x-4', 'com.ledger.gold.lots', pg_temp.tx('x-4', 'com.ledger.gold.lots'))$q$, 'unknown_product');
end $$;

-- The grant can only come from the verifying edge function (service role).
create temp table rls_cast (a uuid);
grant all on rls_cast to authenticated;
insert into rls_cast select pg_temp.id('a');
do $$
declare a uuid := (select a from rls_cast);
begin
  perform pg_temp.as_user(a);
  set local role authenticated;
  perform pg_temp.expect_error($q$select public.grant_purchase('$q$ || a || $q$', 'z-1', 'com.ledger.gold.hoard', '{}'::jsonb)$q$, 'permission denied');
  perform pg_temp.expect_error('select * from public.gold_wallets', 'permission denied');
  perform pg_temp.expect_error('select * from public.store_cabinet', 'permission denied');
  perform pg_temp.expect_error('update public.gold_wallets set balance = 99999', 'permission denied');
  reset role;
end $$;

-- Spending: not enough gold, already owned, same request id spends once.
do $$
declare a uuid := pg_temp.id('a'); c uuid := pg_temp.id('c'); before int; r jsonb; cos text;
begin
  -- Store cosmetics are sold from the day's shelf.
  select id into cos from private.store_shelf(private.era_day()) order by price, id limit 1;
  perform pg_temp.as_user(c);
  perform pg_temp.expect_error(format('select public.store_buy(%L, %L, %L)', 'cosmetic', cos, 'req-c-0001'), 'not_enough_gold');
  perform pg_temp.as_user(a);
  before := pg_temp.gold(a);
  r := public.store_buy('cosmetic', cos, 'req-a-0001');
  r := public.store_buy('cosmetic', cos, 'req-a-0001');
  if pg_temp.gold(a) <> before - (select price from private.store_shelf(private.era_day()) where id = cos) then raise exception 'repeated request spent twice: % -> %', before, pg_temp.gold(a); end if;
  perform pg_temp.expect_error(format('select public.store_buy(%L, %L, %L)', 'cosmetic', cos, 'req-a-0002'), 'already_owned');
  perform pg_temp.expect_error(format('select public.store_buy(%L, %L, %L)', 'cosmetic', 'no.such.thing', 'req-a-0003'), 'unknown_item');
  perform pg_temp.expect_error(format('select public.store_buy(%L, %L, %L)', 'cosmetic', cos, 'short'), 'invalid_request');
end $$;

-- Boxes: a free box needs stock, paid boxes cost their price, the tenth paid box after nine plain ones holds a rare or better item.
do $$
declare a uuid := pg_temp.id('a'); r jsonb; before int; price int := (select price from private.store_box_kinds where kind = 'cabinet'); res jsonb; i int;
begin
  perform pg_temp.as_user(a);
  perform pg_temp.expect_error($q$select public.open_boxes('free', 1, 'box-a-0001')$q$, 'no_box');
  perform private.add_boxes(a, 'free', 2);
  r := public.open_boxes('free', 2, 'box-a-0002');
  if jsonb_array_length(r -> 'results') <> 2 or coalesce((r -> 'state' -> 'boxes' ->> 'free')::int, 0) <> 0 then raise exception 'free boxes not used: %', r - 'state'; end if;

  perform private.store_credit(a, 1000, 'test', '');
  update public.gold_wallets set pity = 9 where user_id = a;
  before := pg_temp.gold(a);
  r := public.open_boxes('cabinet', 1, 'box-a-0003');
  res := r -> 'results' -> 0;
  if not (res ->> 'guaranteed')::boolean or private.rarity_rank(res ->> 'rarity') < 1 or res -> 'content' ->> 'type' not in ('artifact', 'cosmetic') then
    raise exception 'pity box was not a rare item: %', res;
  end if;
  if (select pity from public.gold_wallets where user_id = a) <> 0 then raise exception 'pity not reset'; end if;
  if pg_temp.gold(a) <> before - price then raise exception 'paid box cost wrong: % -> %', before, pg_temp.gold(a); end if;

  r := public.open_boxes('cabinet', 10, 'box-a-0004');
  for i in 0..9 loop
    res := r -> 'results' -> i;
    if res -> 'content' ->> 'type' = 'artifact' and not exists (select 1 from public.store_cabinet where user_id = a and def_id = res -> 'content' ->> 'defID'
                                                                   and serial = (res -> 'content' ->> 'serial')::int) then
      raise exception 'box piece not in cabinet: %', res;
    end if;
  end loop;
  if (select boxes_opened from public.gold_wallets where user_id = a) <> 13 then raise exception 'boxes opened count wrong'; end if;
end $$;

-- Pity across many paid boxes: never more than nine plain rolls in a row.
do $$
declare b uuid := pg_temp.id('b'); r jsonb; run int := 0; worst int := 0; res jsonb;
begin
  perform pg_temp.as_user(b);
  perform private.store_credit(b, 5000, 'test', '');
  for n in 1..15 loop
    r := public.open_boxes('cabinet', 10, 'pity-b-' || lpad(n::text, 4, '0'));
    for res in select value from jsonb_array_elements(r -> 'results') loop
      if private.rarity_rank(res ->> 'rarity') >= 1 then run := 0; else run := run + 1; end if;
      worst := greatest(worst, run);
    end loop;
  end loop;
  if worst > 9 then raise exception 'pity broken: % plain boxes in a row', worst; end if;
end $$;

-- Money packs: the weekly limit counts gold, the free pack twice a server day, unpaid money stays listed until confirmed.
do $$
declare a uuid := pg_temp.id('a'); r jsonb; s jsonb;
begin
  perform pg_temp.as_user(a);
  perform private.store_credit(a, 3000, 'test', '');
  r := public.store_buy('money', 'mountain', 'money-a-0001');
  r := public.store_buy('money', 'mountain', 'money-a-0002');
  perform pg_temp.expect_error($q$select public.store_buy('money', 'handful', 'money-a-0003')$q$, 'weekly_limit:0');
  s := public.store_state();
  if (s -> 'moneyWeek' ->> 'used')::int <> 1060 then raise exception 'weekly use wrong: %', s -> 'moneyWeek'; end if;
  if jsonb_array_length(s -> 'unpaidMoney') < 2 then raise exception 'unpaid money not listed: %', s -> 'unpaidMoney'; end if;
  if public.confirm_money_claims(array['money-a-0001', 'money-a-0002']) <> 2 then raise exception 'confirm did not mark the claims'; end if;
  if exists (select 1 from jsonb_array_elements(public.store_state() -> 'unpaidMoney') e where e ->> 'kind' = 'pack') then raise exception 'confirmed packs still unpaid'; end if;
  perform pg_temp.expect_error($q$select public.store_buy('money', 'free', 'money-a-0004')$q$, 'unknown_item');

  r := public.claim_free_money('free-a-0001');
  r := public.claim_free_money('free-a-0002');
  perform pg_temp.expect_error($q$select public.claim_free_money('free-a-0003')$q$, 'daily_limit');
  if (public.store_state() ->> 'freeMoneyLeft')::int <> 0 then raise exception 'free money left wrong'; end if;
  update public.money_claims set day = day - 1 where user_id = a and kind = 'free';
  r := public.claim_free_money('free-a-0004');
end $$;

-- Pass: double claim refused, premium needs the pass, a tier past what the season's days allow is refused.
do $$
declare a uuid := pg_temp.id('a'); c uuid := pg_temp.id('c'); s int := private.current_season(); r jsonb; t int; orig date;
begin
  perform pg_temp.as_user(c);
  select tier into t from private.store_pass_rewards where season = private.pass_season_def(s) and track = 'f' order by tier limit 1;
  r := public.claim_pass_tier(s, 'f', t);
  if r -> 'reward' ->> 'id' is null then raise exception 'claim returned no reward: %', r - 'state'; end if;
  perform pg_temp.expect_error(format('select public.claim_pass_tier(%s, %L, %s)', s, 'f', t), 'already_claimed');
  perform pg_temp.expect_error(format('select public.claim_pass_tier(%s, %L, %s)', s + 1, 'f', t), 'season_over');
  select tier into t from private.store_pass_rewards where season = private.pass_season_def(s) and track = 'p' order by tier limit 1;
  perform pg_temp.expect_error(format('select public.claim_pass_tier(%s, %L, %s)', s, 'p', t), 'needs_premium');

  r := public.grant_purchase(c, 'bp-1', 'com.ledger.season.bundle', pg_temp.tx('bp-1', 'com.ledger.season.bundle'));
  if not (public.store_state() ->> 'premium')::boolean then raise exception 'battle pass did not open premium'; end if;
  r := public.claim_pass_tier(s, 'p', t);

  select starts into orig from private.store_seasons where season = 1;
  update private.store_seasons set starts = private.utc_today() - (s - 1) * private.store_setting('seasonDays') where season = 1;
  select max(tier) into t from private.store_pass_rewards where season = private.pass_season_def(s) and track = 'f';
  perform pg_temp.expect_error(format('select public.claim_pass_tier(%s, %L, %s)', s, 'f', t), 'tier_not_reached');
  update private.store_seasons set starts = orig where season = 1;
end $$;

-- Server-day limits: the login streak pays once a day; level gold pays once and at most 30 levels a day.
do $$
declare c uuid := pg_temp.id('c'); r jsonb; g int;
begin
  perform pg_temp.as_user(c);
  r := public.claim_login_day();
  if not (r ->> 'opened')::boolean or (r ->> 'count')::int <> 1 then raise exception 'first login wrong: %', r - 'state'; end if;
  r := public.claim_login_day();
  if (r ->> 'opened')::boolean then raise exception 'login paid twice in a day'; end if;
  update public.gold_wallets set streak_day = streak_day - 1 where user_id = c;
  r := public.claim_login_day();
  if (r ->> 'count')::int <> 2 then raise exception 'streak did not grow: %', r - 'state'; end if;

  r := public.claim_level_gold(80);
  if (r ->> 'paidTo')::int <> 30 then raise exception 'level gold went past 30 levels a day: %', r - 'state'; end if;
  g := (select sum(gold) from private.store_level_rewards where level <= 30);
  if (r ->> 'gold')::int <> g then raise exception 'level gold % expected %', r ->> 'gold', g; end if;
  r := public.claim_level_gold(80);
  if (r ->> 'gold')::int <> 0 then raise exception 'level gold paid twice'; end if;
  if (select count(*) from public.level_card_grants where user_id = c) <> (select count(*) from private.store_level_cards where level <= 30) then
    raise exception 'level cards not granted';
  end if;
end $$;

-- Refunds: unspent gold is taken back, the spent part is a debt that blocks spending until gold pays it.
do $$
declare b uuid := pg_temp.id('b'); r jsonb; before int; granted int;
begin
  update public.gold_wallets set balance = 0 where user_id = b;
  r := public.grant_purchase(b, 'h-1', 'com.ledger.gold.hoard', pg_temp.tx('h-1', 'com.ledger.gold.hoard'));
  granted := (r ->> 'gold')::int;
  perform pg_temp.as_user(b);
  r := public.open_boxes('grand', 4, 'refund-b-0001');
  before := pg_temp.gold(b);
  r := public.revoke_purchase('h-1', 'com.ledger.gold.hoard', pg_temp.tx('h-1', 'com.ledger.gold.hoard', '{"revocationDate": 1}'));
  if pg_temp.gold(b) <> 0 or (select debt from public.gold_wallets where user_id = b) <> granted - before then raise exception 'refund wrong: %', r; end if;
  perform pg_temp.expect_error($q$select public.store_buy('service', 'usernameChange', 'debt-b-0001')$q$, 'in_debt');
  r := public.revoke_purchase('h-1', 'com.ledger.gold.hoard', pg_temp.tx('h-1', 'com.ledger.gold.hoard', '{"revocationDate": 1}'));
  if (r ->> 'revoked')::boolean then raise exception 'refund ran twice'; end if;
  perform private.store_credit(b, 1000, 'test', '');
  if (select debt from public.gold_wallets where user_id = b) <> 0 or pg_temp.gold(b) <> 1000 - (granted - before) then raise exception 'debt not paid from new gold'; end if;
end $$;

-- Gifts and quick sale: only pieces the sender holds and may trade.
do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); k record; gid uuid; r jsonb;
begin
  insert into public.friendships (requester_id, addressee_id, status) values (a, b, 'accepted');
  perform pg_temp.as_user(a);
  perform pg_temp.expect_error(format('select public.send_friend_gift(%L, %L, %s)', b, 'abacus', 4999), 'not_yours');
  select c.def_id, c.serial into k from public.store_cabinet c join private.store_items i on i.id = c.def_id
   where c.user_id = a and c.origin <> 'bought' and not i.bound limit 1;
  gid := public.send_friend_gift(b, k.def_id, k.serial);
  if exists (select 1 from public.store_cabinet where user_id = a and def_id = k.def_id and serial = k.serial) then raise exception 'gift stayed with sender'; end if;
  perform pg_temp.as_user(b);
  perform public.accept_friend_gifts(array[gid]);
  if not exists (select 1 from public.store_cabinet where user_id = b and def_id = k.def_id and serial = k.serial and origin = 'acquired') then raise exception 'gift did not arrive'; end if;

  r := public.quick_sell(jsonb_build_array(jsonb_build_object('defID', k.def_id, 'serial', k.serial)), 'sell-b-0001');
  if jsonb_array_length(r -> 'sold') <> 1 then raise exception 'quick sale did not sell: %', r - 'state'; end if;
  perform pg_temp.expect_error(format('select public.quick_sell(%L::jsonb, %L)', jsonb_build_array(jsonb_build_object('defID', k.def_id, 'serial', k.serial)), 'sell-b-0002'), 'not_yours');
end $$;

-- Retired items pay back once.
do $$
declare c uuid := pg_temp.id('c'); r jsonb; rid text := (select id from private.store_retired order by id limit 1);
begin
  insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (c, rid, 'test');
  perform pg_temp.as_user(c);
  r := public.claim_refund_retired();
  if (r ->> 'gold')::int <> (select gold from private.store_retired where id = rid) then raise exception 'refund gold wrong: %', r - 'state'; end if;
  r := public.claim_refund_retired();
  if (r ->> 'gold')::int <> 0 then raise exception 'retired refund paid twice'; end if;
end $$;

-- Import: once per account and device, capped; accounts made after the cutoff bring no gold.
do $$
declare c uuid := pg_temp.id('c'); l uuid := pg_temp.id('late'); r jsonb; before int; store jsonb;
begin
  store := jsonb_build_object('gold', 999999, 'boxes', jsonb_build_object('grand', 500, 'nonsense', 3), 'pity', 50,
    'items', jsonb_build_array(jsonb_build_object('defID', 'abacus', 'serial', 7), jsonb_build_object('defID', 'nope', 'serial', 1),
                               jsonb_build_object('defID', 'abacus', 'serial', 999999)),
    'cosmetics', jsonb_build_array('no.such.cosmetic'), 'passClaims', jsonb_build_array('f1', 'p30', 'x9'), 'levelGoldPaid', 60);
  perform pg_temp.as_user(c);
  before := pg_temp.gold(c);
  r := public.import_local_store('device-0001', store);
  if not (r ->> 'imported')::boolean or (r ->> 'gold')::int <> 2000 or (r ->> 'items')::int <> 1 then raise exception 'import caps wrong: %', r - 'state'; end if;
  if pg_temp.gold(c) <> before + 2000 or (select count from public.gold_box_stock where user_id = c and kind = 'grand') <> 20 then raise exception 'import credit wrong'; end if;
  if (select pity from public.gold_wallets where user_id = c) <> 9 or (select level_gold_paid from public.gold_wallets where user_id = c) <> 60 then raise exception 'import state wrong'; end if;
  r := public.import_local_store('device-0002', store);
  if (r ->> 'imported')::boolean or r ->> 'reason' <> 'already' then raise exception 'second import ran: %', r - 'state'; end if;

  perform pg_temp.as_user(l);
  r := public.import_local_store('device-0001', store);
  if (r ->> 'imported')::boolean or r ->> 'reason' <> 'device' then raise exception 'device imported twice: %', r - 'state'; end if;
  r := public.import_local_store('device-0003', store);
  if not (r ->> 'imported')::boolean or (r ->> 'gold')::int <> 0 or coalesce(pg_temp.gold(l), 0) <> 0 then raise exception 'late account imported gold: %', r - 'state'; end if;
  insert into public.friendships (requester_id, addressee_id, status) values (l, c, 'accepted');
  perform pg_temp.expect_error(format('select public.send_friend_gift(%L, %L, %s)', c, 'abacus', 7), 'not_yours');
end $$;

-- Friend race gold: paid once for a finished week, only to the top three with someone behind.
do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); wk int := private.friend_week() - 1; r jsonb;
begin
  insert into public.friend_race_scores (user_id, week, growth) values (a, wk, 0.5), (b, wk, 0.2);
  perform pg_temp.as_user(a);
  r := public.claim_race_gold(wk);
  if (r ->> 'gold')::int <> 3 then raise exception 'race winner gold wrong: %', r - 'state'; end if;
  perform pg_temp.expect_error(format('select public.claim_race_gold(%s)', wk), 'already_claimed');
  perform pg_temp.expect_error(format('select public.claim_race_gold(%s)', wk + 1), 'invalid_value');
  perform pg_temp.as_user(b);
  perform pg_temp.expect_error(format('select public.claim_race_gold(%s)', wk), 'no_reward');
end $$;

-- The state the app reads holds every key StoreState decodes.
do $$
declare a uuid := pg_temp.id('a'); s jsonb;
begin
  perform pg_temp.as_user(a);
  s := public.store_state();
  if not (s ? 'wallet' and s ? 'boxes' and s ? 'pity' and s ? 'firstPurchaseDone' and s ? 'cabinet' and s ? 'boxesOpened'
          and s -> 'cabinet' ? 'items' and s -> 'cabinet' ? 'rewarded' and s -> 'wallet' ? 'balance' and s -> 'pity' ? 'sinceRare') then
    raise exception 'store state misses keys: %', s;
  end if;
  if (public.server_now() ->> 'day')::int <> public.my_day() then raise exception 'server day mismatch'; end if;
end $$;
