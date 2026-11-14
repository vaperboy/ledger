-- Gift codes (0037): rewards, once per account, a maximum number of uses, expiry, and no Battle Pass items.
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
create function pg_temp.boxes(u uuid, k text) returns int language sql as $$ select coalesce((select count from public.gold_box_stock where user_id = u and kind = k), 0) $$;
create function pg_temp.owns(u uuid, c text) returns boolean language sql as $$ select exists (select 1 from public.cosmetic_grants where user_id = u and cosmetic_id = c) $$;

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
insert into cast_ids select 'e', pg_temp.mk_player('Eve Early');
create function pg_temp.id(k text) returns uuid language sql as $$ select id from cast_ids where k = $1 $$;

-- Only catalogue items that are sold or won in boxes can be gifts: never pass rewards, unknown ids, or unknown boxes.
do $$
declare store_item text; pass_item text; n int;
begin
  select id into store_item from private.store_cosmetics where source = 'store' order by id limit 1;
  select reward_id into pass_item from private.store_pass_rewards r join private.store_cosmetics c on c.id = r.reward_id order by r.season, r.tier limit 1;
  if store_item is null or pass_item is null then raise exception 'catalogue is empty'; end if;

  n := private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-TEST-0001')], 100, array[store_item], '{"cabinet": 1}'::jsonb, 1, null);
  if n <> 1 then raise exception 'gift code not added'; end if;

  begin
    perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-PASS-0001')], 0, array[pass_item], '{}'::jsonb, 1, null);
    raise exception 'a pass item was accepted';
  exception when others then if sqlerrm not like 'invalid_gift_item:%' then raise; end if; end;
  begin
    perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-PASS-0002')], 0, array['no.such.item'], '{}'::jsonb, 1, null);
    raise exception 'an unknown item was accepted';
  exception when others then if sqlerrm not like 'invalid_gift_item:%' then raise; end if; end;
  begin
    perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-BOXX-0001')], 10, '{}', '{"nosuchbox": 1}'::jsonb, 1, null);
    raise exception 'an unknown box was accepted';
  exception when others then if sqlerrm not like 'invalid_gift_box:%' then raise; end if; end;
  begin
    perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-NONE-0001')], 0, '{}', '{}'::jsonb, 1, null);
    raise exception 'an empty gift was accepted';
  exception when others then if sqlerrm <> 'empty_gift' then raise; end if; end;
  begin
    perform private.add_gift_codes(array['LEDGER-GIFT-TEST-0001'], 10, '{}', '{}'::jsonb, 1, null);
    raise exception 'a plain code was accepted';
  exception when others then if sqlerrm <> 'invalid_hash' then raise; end if; end;
  begin
    perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-USES-0001')], 10, '{}', '{}'::jsonb, 0, null);
    raise exception 'zero uses were accepted';
  exception when others then if sqlerrm <> 'invalid_gift_uses' then raise; end if; end;
  if exists (select 1 from private.redeem_codes c where row_to_json(c)::text ilike '%GIFTTEST%' or row_to_json(c)::text ilike '%LEDGER-GIFT%') then
    raise exception 'a plain code is stored';
  end if;
end $$;

-- A single-use gift pays gold, the cosmetic and the boxes, says exactly what arrived, and works once per account.
do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); r jsonb; store_item text; g0 int;
begin
  select id into store_item from private.store_cosmetics where source = 'store' order by id limit 1;
  perform pg_temp.as_user(a);
  g0 := pg_temp.gold(a);
  r := public.redeem_code('ledger gift test 0001');
  if not (r ->> 'ok')::boolean or r ->> 'kind' <> 'gift' or r ->> 'reason' <> 'granted' then raise exception 'gift failed: %', r - 'state'; end if;
  if (r -> 'reward' ->> 'gold')::int <> 100 or r -> 'reward' -> 'items' ->> 0 <> store_item or (r -> 'reward' -> 'boxes' ->> 'cabinet')::int <> 1 then
    raise exception 'reward not described: %', r -> 'reward';
  end if;
  if pg_temp.gold(a) <> g0 + 100 or not pg_temp.owns(a, store_item) or pg_temp.boxes(a, 'cabinet') <> 1 then raise exception 'gift not paid'; end if;
  if (r -> 'state' -> 'boxes' ->> 'cabinet')::int <> 1 then raise exception 'state lacks the box'; end if;

  r := public.redeem_code('LEDGER-GIFT-TEST-0001');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'gift_used' then raise exception 'same account twice: %', r - 'state'; end if;
  if pg_temp.gold(a) <> g0 + 100 or pg_temp.boxes(a, 'cabinet') <> 1 then raise exception 'paid twice'; end if;

  perform pg_temp.as_user(b);
  r := public.redeem_code('LEDGER-GIFT-TEST-0001');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'invalid' then raise exception 'single-use gift worked for a second account: %', r - 'state'; end if;
  if pg_temp.gold(b) <> 0 then raise exception 'second account was paid'; end if;
end $$;

-- A promo code with three uses: three accounts get it, the fourth does not, nobody gets it twice.
do $$
declare a uuid := pg_temp.id('a'); b uuid := pg_temp.id('b'); c uuid := pg_temp.id('c'); d uuid := pg_temp.id('d'); r jsonb;
begin
  perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-PROM-0001')], 50, '{}', '{}'::jsonb, 3, null);
  perform pg_temp.as_user(a); r := public.redeem_code('LEDGER-GIFT-PROM-0001');
  if not (r ->> 'ok')::boolean or (r -> 'reward' ->> 'gold')::int <> 50 or jsonb_array_length(r -> 'reward' -> 'items') <> 0 then raise exception 'promo a: %', r - 'state'; end if;
  perform pg_temp.as_user(b); r := public.redeem_code('LEDGER-GIFT-PROM-0001');
  if not (r ->> 'ok')::boolean then raise exception 'promo b: %', r - 'state'; end if;
  perform pg_temp.as_user(a); r := public.redeem_code('LEDGER-GIFT-PROM-0001');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'gift_used' then raise exception 'promo a twice: %', r - 'state'; end if;
  perform pg_temp.as_user(c); r := public.redeem_code('LEDGER-GIFT-PROM-0001');
  if not (r ->> 'ok')::boolean then raise exception 'promo c: %', r - 'state'; end if;
  perform pg_temp.as_user(d); r := public.redeem_code('LEDGER-GIFT-PROM-0001');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'invalid' then raise exception 'promo over its uses: %', r - 'state'; end if;
  if pg_temp.gold(d) <> 0 then raise exception 'promo paid past its uses'; end if;
  if (select g.used_count from private.gift_codes g join private.redeem_codes k on k.id = g.code_id
       where k.code_hash = encode(extensions.digest(k.salt || ':LEDGERGIFTPROM0001', 'sha256'), 'hex')) <> 3 then
    raise exception 'use count is off';
  end if;
end $$;

-- Expiry: the last day still works, the day after does not; a code that expired after it was made is refused too.
do $$
declare a uuid := pg_temp.id('a'); r jsonb; n int;
begin
  perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-LATE-0001')], 10, '{}', '{}'::jsonb, 5, current_date - 1);
  perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-TODAY-001')], 10, '{}', '{}'::jsonb, 5, (now() at time zone 'UTC')::date);
  perform pg_temp.as_user(a);
  r := public.redeem_code('LEDGER-GIFT-LATE-0001');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'expired' then raise exception 'expired code worked: %', r - 'state'; end if;
  r := public.redeem_code('LEDGER-GIFT-TODAY-001');
  if not (r ->> 'ok')::boolean then raise exception 'code on its last day failed: %', r - 'state'; end if;
  perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-SOON-0001')], 10, '{}', '{}'::jsonb, 5, current_date + 30);
  update private.gift_codes set expires_at = now() - interval '1 minute'
   where code_id in (select id from private.redeem_codes k where k.code_hash = encode(extensions.digest(k.salt || ':LEDGERGIFTSOON0001', 'sha256'), 'hex'));
  r := public.redeem_code('LEDGER-GIFT-SOON-0001');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'expired' then raise exception 'code expired later worked: %', r - 'state'; end if;
end $$;

-- A gift of items the account already has is refused without using the code up; a mixed gift pays what is new.
do $$
declare a uuid := pg_temp.id('a'); e uuid := pg_temp.id('e'); r jsonb; store_item text; g0 int;
begin
  select id into store_item from private.store_cosmetics where source = 'store' order by id limit 1;
  perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-ITEM-0001')], 0, array[store_item], '{}'::jsonb, 2, null);
  perform private.add_gift_codes(array[pg_temp.entry('LEDGER-GIFT-MIXD-0001')], 25, array[store_item], '{}'::jsonb, 2, null);
  perform pg_temp.as_user(a);
  r := public.redeem_code('LEDGER-GIFT-ITEM-0001');
  if (r ->> 'ok')::boolean or r ->> 'reason' <> 'owned' then raise exception 'owned gift: %', r - 'state'; end if;
  g0 := pg_temp.gold(a);
  r := public.redeem_code('LEDGER-GIFT-MIXD-0001');
  if not (r ->> 'ok')::boolean or (r -> 'reward' ->> 'gold')::int <> 25 or jsonb_array_length(r -> 'reward' -> 'items') <> 0 then raise exception 'mixed gift: %', r - 'state'; end if;
  if pg_temp.gold(a) <> g0 + 25 then raise exception 'mixed gift gold'; end if;
  perform pg_temp.as_user(e);
  r := public.redeem_code('LEDGER-GIFT-ITEM-0001');
  if not (r ->> 'ok')::boolean or r -> 'reward' -> 'items' ->> 0 <> store_item then raise exception 'item gift not paid: %', r - 'state'; end if;
  -- Beta and administrator keys still work beside gifts.
  perform private.add_codes('beta', array[pg_temp.entry('LEDGER-BETA-TEST-0001')]);
  r := public.redeem_code('LEDGER-BETA-TEST-0001');
  if not (r ->> 'ok')::boolean or r ->> 'kind' <> 'beta' or r ? 'reward' then raise exception 'beta key broke: %', r - 'state'; end if;
end $$;

-- Wrong tries share the one hourly limit with every other kind of code.
do $$
declare d uuid := pg_temp.id('d'); r jsonb; i int;
begin
  perform pg_temp.as_user(d);
  delete from private.redeem_attempts where user_id = d;
  for i in 1..private.store_extra('codeTriesPerHour') loop
    r := public.redeem_code('LEDGER-NOPE-NOPE-' || lpad(i::text, 4, '0'));
    if (r ->> 'ok')::boolean or r ->> 'reason' <> 'invalid' then raise exception 'wrong code: %', r - 'state'; end if;
  end loop;
  r := public.redeem_code('LEDGER-GIFT-PROM-0001');
  if r ->> 'reason' <> 'locked' then raise exception 'no rate limit: %', r - 'state'; end if;
end $$;
