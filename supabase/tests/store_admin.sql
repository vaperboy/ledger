-- Store extras (0035): codes kept as hashes and used once, administrators, beta keys, the daily shelf, ad gold and supporters.
create function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
$$;

create function pg_temp.mk_player(nm text) returns uuid language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role) values (u, 'authenticated', 'authenticated');
  insert into public.profiles (id, display_name, adult_confirmed, created_at) values (u, nm, true, now() - interval '40 days');
  return u;
end $$;

create function pg_temp.gold(u uuid) returns int language sql as $$ select coalesce((select balance from public.gold_wallets where user_id = u), 0) $$;

-- The 'salt:hash' entry make_codes.py prints for a code.
create function pg_temp.entry(code text) returns text language sql as $$
  with s as (select md5(random()::text || clock_timestamp()::text) as salt)
  select s.salt || ':' || encode(extensions.digest(s.salt || ':' || upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g')), 'sha256'), 'hex') from s;
$$;

create temp table cast_ids (k text primary key, id uuid);
insert into cast_ids select 'a', pg_temp.mk_player('Ada Ames');
insert into cast_ids select 'b', pg_temp.mk_player('Ben Beta');
insert into cast_ids select 'c', pg_temp.mk_player('Cid Codes');
insert into cast_ids select 'd', pg_temp.mk_player('Dot Dee');
create function pg_temp.id(k text) returns uuid language sql as $$ select id from cast_ids where k = $1 $$;

-- Codes: only a salted hash is stored, each works once, an administrator code binds the account for good.
do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); r jsonb; n int; floor_gold int := private.store_extra('adminFloor');
begin
  n := private.add_codes('admin', array[pg_temp.entry('LEDGER-ADMN-TEST-0001')]);
  if n <> 1 then raise exception 'admin code not added'; end if;
  begin
    perform private.add_codes('admin', array['LEDGER-ADMN-TEST-0001']);
    raise exception 'a plain code was accepted';
  exception when others then
    if sqlerrm <> 'invalid_hash' then raise; end if;
  end;
  if exists (select 1 from private.redeem_codes c where row_to_json(c)::text ilike '%ADMNTEST%' or row_to_json(c)::text ilike '%LEDGER-ADMN%') then
    raise exception 'a plain code is stored';
  end if;

  perform pg_temp.as_user(b);
  r := public.redeem_code('LEDGER-ADMN-TEST-9999');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'invalid' then raise exception 'a wrong code worked: %', r - 'state'; end if;

  perform pg_temp.as_user(a);
  r := public.redeem_code('ledger admn test 0001');
  if not (r ->> 'ok')::boolean or r ->> 'kind' <> 'admin' then raise exception 'admin code failed: %', r - 'state'; end if;
  if not private.is_admin(a) or not (r -> 'state' ->> 'isAdmin')::boolean then raise exception 'admin flag missing'; end if;
  if pg_temp.gold(a) < floor_gold then raise exception 'admin wallet not topped up: %', pg_temp.gold(a); end if;

  perform pg_temp.as_user(b);
  r := public.redeem_code('LEDGER-ADMN-TEST-0001');
  if (r ->> 'ok')::boolean or private.is_admin(b) then raise exception 'an admin code worked twice'; end if;
  reset role;
end $$;

-- Administrators: spending never takes the wallet below the floor, every cosmetic, premium pass, every tier claimable.
do $$
declare a uuid := pg_temp.id('a'); r jsonb; i int; floor_gold int := private.store_extra('adminFloor'); st jsonb;
begin
  perform pg_temp.as_user(a);
  for i in 1..5 loop
    r := public.store_buy('bundle', (select id from private.store_box_bundles order by price desc limit 1), 'adm-bundle-' || i);
    if pg_temp.gold(a) < floor_gold then raise exception 'admin gold fell below the floor: %', pg_temp.gold(a); end if;
  end loop;
  update public.gold_wallets set debt = 50 where user_id = a;
  r := public.store_buy('service', 'usernameChange', 'adm-service-1');
  if (select debt from public.gold_wallets where user_id = a) <> 0 then raise exception 'debt blocked an admin'; end if;
  st := public.store_state();
  if not (st ->> 'premium')::boolean then raise exception 'admin lacks the premium pass'; end if;
  if private.pass_tier_ceiling(a, private.current_season()) <> 30 then raise exception 'admin cannot claim every tier'; end if;
  if jsonb_array_length(st -> 'cosmetics') < (select count(*) from private.store_cosmetics where source <> 'retired') then
    raise exception 'admin lacks cosmetics';
  end if;
  reset role;
end $$;

-- Beta keys: 500 gold, one key per account, each key once.
do $$
declare b uuid := pg_temp.id('b'); c uuid := pg_temp.id('c'); r jsonb; before int;
begin
  perform private.add_codes('beta', array[pg_temp.entry('LEDGER-BETA-AAAA-0001'), pg_temp.entry('LEDGER-BETA-AAAA-0002')]);
  perform pg_temp.as_user(b);
  before := pg_temp.gold(b);
  r := public.redeem_code('LEDGER-BETA-AAAA-0001');
  if not (r ->> 'ok')::boolean or (r ->> 'gold')::int <> 500 or pg_temp.gold(b) <> before + 500 then raise exception 'beta key did not pay 500: %', r - 'state'; end if;
  if not (r -> 'state' ->> 'betaRedeemed')::boolean then raise exception 'beta flag missing'; end if;
  r := public.redeem_code('LEDGER-BETA-AAAA-0002');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'beta_used' or pg_temp.gold(b) <> before + 500 then raise exception 'a second beta key paid one account: %', r; end if;
  if private.is_admin(b) then raise exception 'a beta key made an admin'; end if;

  perform pg_temp.as_user(c);
  r := public.redeem_code('LEDGER-BETA-AAAA-0001');
  if (r ->> 'ok')::boolean then raise exception 'a used beta key paid again'; end if;
  r := public.redeem_code('LEDGER-BETA-AAAA-0002');
  if not (r ->> 'ok')::boolean then raise exception 'the unused beta key was burnt by a refused try: %', r; end if;
  reset role;
end $$;

-- Wrong codes lock the field for an hour after a few tries.
do $$
declare d uuid := pg_temp.id('d'); r jsonb; i int;
begin
  perform pg_temp.as_user(d);
  for i in 1..private.store_extra('codeTriesPerHour') loop r := public.redeem_code('LEDGER-NOPE-NOPE-' || lpad(i::text, 4, '0')); end loop;
  r := public.redeem_code('LEDGER-NOPE-NOPE-9999');
  if r ->> 'reason' <> 'locked' then raise exception 'tries were not limited: %', r; end if;
  reset role;
end $$;

-- The daily shelf: never pass items, the same all day, sold at the shelf price; pass items cannot be bought.
do $$
declare c uuid := pg_temp.id('c'); d int; r jsonb; pick record; before int; pass_id text;
begin
  for d in private.era_day() - 30 .. private.era_day() + 30 loop
    if exists (select 1 from private.store_shelf(d) s join private.store_pass_rewards p on p.reward_id = s.id) then raise exception 'a pass item is on the shelf of day %', d; end if;
    if (select count(*) from private.store_shelf(d)) <> private.store_extra('shelfSize') then raise exception 'shelf of day % has the wrong size', d; end if;
  end loop;
  if (select array_agg(id order by id) from private.store_shelf(private.era_day())) is distinct from (select array_agg(id order by id) from private.store_shelf(private.era_day())) then
    raise exception 'the shelf changed within a day';
  end if;
  if (select array_agg(id) from private.store_shelf(private.era_day())) = (select array_agg(id) from private.store_shelf(private.era_day() + 1))
     and (select array_agg(id) from private.store_shelf(private.era_day())) = (select array_agg(id) from private.store_shelf(private.era_day() + 2)) then
    raise exception 'the shelf never changes';
  end if;

  perform pg_temp.as_user(c);
  perform private.store_credit(c, 1000, 'test', '');
  select * into pick from private.store_shelf(private.era_day()) s
   where not exists (select 1 from public.cosmetic_grants g where g.user_id = c and g.cosmetic_id = s.id) order by s.id limit 1;
  before := pg_temp.gold(c);
  r := public.store_buy('cosmetic', pick.id, 'shelf-c-0001');
  if pg_temp.gold(c) <> before - pick.price then raise exception 'shelf price not charged: % -> %', before, pg_temp.gold(c); end if;

  select reward_id into pass_id from private.store_pass_rewards r join private.store_cosmetics k on k.id = r.reward_id limit 1;
  begin
    perform public.store_buy('cosmetic', pass_id, 'shelf-c-0002');
    raise exception 'a pass item was sold';
  exception when others then
    if sqlerrm <> 'unknown_item' then raise; end if;
  end;
  begin
    perform public.store_buy('cosmetic', (select id from private.store_cosmetics k where k.source = 'store' and k.kind <> 'saveSlot'
                                            and k.id not in (select id from private.store_shelf(private.era_day()))
                                            and k.id not in (select id from private.store_shelf(private.era_day() - 1)) limit 1), 'shelf-c-0003');
    raise exception 'an item off the shelf was sold';
  exception when others then
    if sqlerrm <> 'unknown_item' then raise; end if;
  end;
  reset role;

  begin
    set constraints all immediate;
    update private.store_cosmetics set source = 'store' where id = pass_id;
    raise exception 'the catalogue let a pass item be sold';
  exception when others then
    if sqlerrm <> 'pass_item_for_sale' then raise; end if;
  end;
end $$;
set constraints all deferred;

-- Ads: a daily cap on server days, a wait between ads, a repeated claim id pays once; supporters get more and wait less.
do $$
declare d uuid := pg_temp.id('d'); r jsonb; before int; i int; cap int := private.store_extra('adsPerDay');
begin
  perform pg_temp.as_user(d);
  before := pg_temp.gold(d);
  r := public.claim_ad_gold('ad-d-00001');
  if not (r ->> 'ok')::boolean or (r ->> 'gold')::int <> private.store_extra('adGold') then raise exception 'first ad did not pay: %', r - 'state'; end if;
  r := public.claim_ad_gold('ad-d-00001');
  if not (r ->> 'repeat')::boolean or pg_temp.gold(d) <> before + private.store_extra('adGold') then raise exception 'a repeated claim paid twice'; end if;
  r := public.claim_ad_gold('ad-d-00002');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'cooldown' or (r ->> 'wait')::int <= 0 then raise exception 'no wait between ads: %', r - 'state'; end if;
  for i in 2..cap loop
    update public.ad_claims set created_at = created_at - interval '1 hour' where user_id = d;
    r := public.claim_ad_gold('ad-d-' || lpad(i::text, 5, '0') || 'x');
    if not (r ->> 'ok')::boolean then raise exception 'ad % of % refused: %', i, cap, r - 'state'; end if;
  end loop;
  update public.ad_claims set created_at = created_at - interval '1 hour' where user_id = d;
  r := public.claim_ad_gold('ad-d-over-cap');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'daily_limit' then raise exception 'the daily cap did not hold: %', r - 'state'; end if;
  if pg_temp.gold(d) <> before + cap * private.store_extra('adGold') then raise exception 'ad gold wrong: %', pg_temp.gold(d) - before; end if;
  update public.ad_claims set day = day - 1, created_at = created_at - interval '1 day' where user_id = d;
  r := public.claim_ad_gold('ad-d-next-day');
  if not (r ->> 'ok')::boolean then raise exception 'the cap did not reset on a new server day'; end if;
  reset role;
end $$;

do $$
declare c uuid := pg_temp.id('c'); d uuid := pg_temp.id('d'); r jsonb; t jsonb;
begin
  update public.profiles set badges = array['Supporter', 'Trader'] where id = d;
  if exists (select 1 from public.profiles where id = d and 'Supporter' = any (badges)) then raise exception 'the app could set the supporter badge'; end if;
  if private.is_supporter(c) then raise exception 'c should not be a supporter yet'; end if;
  perform public.grant_purchase(c, 'sup-1', 'com.ledger.gold.pouch',
    jsonb_build_object('originalTransactionId', 'sup-1', 'transactionId', 'sup-1', 'productId', 'com.ledger.gold.pouch', 'bundleId', 'com.matasdovyda.ledger', 'environment', 'Sandbox'));
  if not private.is_supporter(c) or not (exists (select 1 from public.profiles where id = c and 'Supporter' = any (badges))) then raise exception 'a buyer got no supporter badge'; end if;
  t := private.ad_terms(c);
  if (t ->> 'gold')::int <> private.store_extra('supporterAdGold') or (t ->> 'cooldown')::int <> private.store_extra('supporterAdCooldown') then
    raise exception 'supporter ad terms wrong: %', t;
  end if;
  update public.gold_wallets set ads_watched = private.store_extra('supporterAds') - 1 where user_id = d;
  update public.ad_claims set created_at = created_at - interval '1 hour' where user_id = d;
  perform pg_temp.as_user(d);
  r := public.claim_ad_gold('ad-d-makes-sup');
  reset role;
  if not ((r -> 'state' ->> 'supporter')::boolean) or not (exists (select 1 from public.profiles where id = d and 'Supporter' = any (badges))) then
    raise exception 'watching enough ads did not make a supporter';
  end if;
end $$;

-- Mission gold: paid once per account, period and mission; capped per mission, per server day and per server week.
do $$
declare b uuid := pg_temp.id('b'); r jsonb; before int; i int; total int := 0;
begin
  perform pg_temp.as_user(b);
  before := pg_temp.gold(b);
  r := public.claim_mission_gold('m.sell.easy', 'day:100', 2);
  if (r ->> 'gold')::int <> 2 then raise exception 'mission gold not paid: %', r - 'state'; end if;
  r := public.claim_mission_gold('m.sell.easy', 'day:100', 2);
  if not (r ->> 'repeat')::boolean or pg_temp.gold(b) <> before + 2 then raise exception 'a mission paid twice'; end if;
  r := public.claim_mission_gold('m.big.hard', 'day:100', 99);
  if (r ->> 'gold')::int <> private.store_extra('missionGold') then raise exception 'mission cap did not hold: %', r - 'state'; end if;
  for i in 1..10 loop r := public.claim_mission_gold('m.more.' || i, 'day:100', 4); end loop;
  if pg_temp.gold(b) - before <> private.store_extra('missionGoldPerDay') then raise exception 'day cap did not hold: %', pg_temp.gold(b) - before; end if;
  for i in 1..10 loop
    update public.mission_gold set day = day - 1 where user_id = b;
    r := public.claim_mission_gold('m.week.' || i, 'day:' || (100 + i), 4);
  end loop;
  if pg_temp.gold(b) - before <> private.store_extra('missionGoldPerWeek') then raise exception 'week cap did not hold: %', pg_temp.gold(b) - before; end if;
  begin
    perform public.claim_mission_gold('m.neg', 'day:200', -5);
    raise exception 'negative mission gold accepted';
  exception when others then
    if sqlerrm <> 'invalid_request' then raise; end if;
  end;
  reset role;
end $$;
