-- Store extras on the server wallet: a daily cosmetics shelf, gold for rewarded ads and missions, open supporter perks,
-- administrator and beta codes. Every number lives in private.store_extra().

create or replace function private.store_extra(k text) returns int language sql immutable as $$
  select ('{"shelfSize": 6, "adsPerDay": 10, "adGold": 1, "supporterAdGold": 2, "adCooldown": 300, "supporterAdCooldown": 180,
            "supporterAds": 50, "betaGold": 500, "adminFloor": 1000000, "codeTriesPerHour": 10,
            "missionGold": 4, "missionGoldPerDay": 12, "missionGoldPerWeek": 40}'::jsonb ->> k)::int;
$$;

-- Codes are kept only as SHA-256 of salt, a colon and the code (upper case, letters and digits only); the plain codes
-- never reach the repo, the app or the database. supabase/tools/make_codes.py makes them.
create table private.redeem_codes (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('admin', 'beta')),
  salt text not null check (salt ~ '^[0-9a-f]{32}$'),
  code_hash text not null check (code_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  redeemed_by uuid references auth.users (id) on delete set null,
  redeemed_at timestamptz,
  unique (salt, code_hash)
);
-- One beta key per account.
create unique index redeem_codes_one_beta on private.redeem_codes (redeemed_by) where kind = 'beta';

create table private.redeem_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  at timestamptz not null default now()
);
create index redeem_attempts_user on private.redeem_attempts (user_id, at desc);

create table public.ad_claims (
  user_id uuid not null references public.profiles (id) on delete cascade,
  claim_id text not null check (char_length(claim_id) between 8 and 64),
  day int not null,
  gold int not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, claim_id)
);
create index ad_claims_day on public.ad_claims (user_id, day);
create index ad_claims_recent on public.ad_claims (user_id, created_at desc);

alter table public.gold_wallets add column ads_watched int not null default 0 check (ads_watched >= 0);
create index if not exists store_plans_user on public.store_plans (user_id);

alter table public.ad_claims enable row level security;
revoke all on public.ad_claims from anon, authenticated;
revoke all on private.redeem_codes, private.redeem_attempts from public, anon, authenticated;

-- Adds codes from make_codes.py: each entry is 'salt:hash' in lower-case hex. Returns how many were new.
create or replace function private.add_codes(p_kind text, p_hashes text[]) returns int
language plpgsql security definer set search_path = '' as $$
declare h text; n int := 0; got int;
begin
  if p_kind is null or p_kind not in ('admin', 'beta') then raise exception 'invalid_kind' using errcode = 'P0001'; end if;
  foreach h in array coalesce(p_hashes, '{}'::text[]) loop
    if h !~ '^[0-9a-f]{32}:[0-9a-f]{64}$' then raise exception 'invalid_hash' using errcode = 'P0001'; end if;
    insert into private.redeem_codes (kind, salt, code_hash) values (p_kind, split_part(h, ':', 1), split_part(h, ':', 2)) on conflict do nothing;
    get diagnostics got = row_count;
    n := n + got;
  end loop;
  return n;
end $$;
revoke execute on function private.add_codes(text, text[]) from public, anon, authenticated;

-- The Battle Pass is the only way to get pass items: no pass reward may be a box or store item.
create or replace function private.check_pass_items_not_sold() returns trigger language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from private.store_cosmetics c join private.store_pass_rewards r on r.reward_id = c.id where c.source in ('box', 'store')) then
    raise exception 'pass_item_for_sale' using errcode = 'P0001';
  end if;
  return null;
end $$;
create constraint trigger store_cosmetics_pass_only after insert or update on private.store_cosmetics
  deferrable initially deferred for each row execute function private.check_pass_items_not_sold();
create constraint trigger store_pass_rewards_pass_only after insert or update on private.store_pass_rewards
  deferrable initially deferred for each row execute function private.check_pass_items_not_sold();
do $$ begin
  if exists (select 1 from private.store_cosmetics c join private.store_pass_rewards r on r.reward_id = c.id where c.source in ('box', 'store')) then
    raise exception 'pass_item_for_sale';
  end if;
end $$;

-- The shelf of a day (an era day, as private.era_day): box and store items, never pass items, slots or plates,
-- each at its own price or the store price of its rarity. The same for every player; legendary items stay box-only.
create or replace function private.store_shelf(p_day int) returns table (id text, price int)
language sql stable security definer set search_path = '' as $$
  with priced as (
    select c.id,
           coalesce(case when c.source = 'store' then c.price end,
                    (select min(s.price) from private.store_cosmetics s
                      where s.source = 'store' and s.kind <> 'saveSlot' and s.rarity = c.rarity and s.price is not null)) as price
      from private.store_cosmetics c
     where c.source in ('box', 'store') and c.kind not in ('saveSlot', 'tradePlate') and private.theme_live(c.theme)
       and not exists (select 1 from private.store_pass_rewards r where r.reward_id = c.id)
  )
  select p.id, p.price from priced p where p.price > 0
   order by md5(p.id || ':' || p_day::text), p.id
   limit private.store_extra('shelfSize');
$$;

-- Supporters: anyone who bought something with real money or watched enough ads. Open and visible, no gameplay edge.
create or replace function private.is_supporter(uid uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.store_transactions where user_id = uid and revoked_at is null)
      or exists (select 1 from public.store_plans where user_id = uid and revoked_at is null)
      or coalesce((select ads_watched from public.gold_wallets where user_id = uid), 0) >= private.store_extra('supporterAds');
$$;

-- The rewarded-ad terms of an account right now.
create or replace function private.ad_terms(uid uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare sup boolean := private.is_supporter(uid); v_today int := private.era_day(); used int; last timestamptz; cool int;
begin
  used := (select count(*) from public.ad_claims where user_id = uid and day = v_today)::int;
  last := (select max(created_at) from public.ad_claims where user_id = uid);
  cool := case when sup then private.store_extra('supporterAdCooldown') else private.store_extra('adCooldown') end;
  return jsonb_build_object(
    'perDay', private.store_extra('adsPerDay'),
    'used', used,
    'gold', case when sup then private.store_extra('supporterAdGold') else private.store_extra('adGold') end,
    'cooldown', cool,
    'nextAt', case when last is null or last + make_interval(secs => cool) <= now() then null
                   else extract(epoch from last + make_interval(secs => cool)) end,
    'baseGold', private.store_extra('adGold'),
    'supporterGold', private.store_extra('supporterAdGold'),
    'baseCooldown', private.store_extra('adCooldown'),
    'supporterCooldown', private.store_extra('supporterAdCooldown'),
    'supporterAds', private.store_extra('supporterAds'),
    'watched', coalesce((select ads_watched from public.gold_wallets where user_id = uid), 0));
end $$;

-- The "Supporter" badge on the player card is set here only: a badge of that name sent by the app is dropped.
create or replace function private.profile_supporter_badge() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.badges := array_remove(coalesce(new.badges, '{}'::text[]), 'Supporter');
  if private.is_supporter(new.id) then new.badges := (array['Supporter'] || new.badges)[1:64]; end if;
  return new;
end $$;
create trigger profiles_supporter_badge before insert or update of badges on public.profiles
  for each row execute function private.profile_supporter_badge();

create or replace function private.refresh_supporter(uid uuid) returns void language sql security definer set search_path = '' as $$
  update public.profiles set badges = badges where id = uid;
$$;

create or replace function private.purchase_refreshes_supporter() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.refresh_supporter(new.user_id);
  return null;
end $$;
create trigger store_transactions_supporter after insert or update of revoked_at on public.store_transactions
  for each row execute function private.purchase_refreshes_supporter();
create trigger store_plans_supporter after insert or update of revoked_at on public.store_plans
  for each row execute function private.purchase_refreshes_supporter();

-- Administrators: gold never runs out (a spend tops the wallet up to the floor first), every cosmetic, the premium
-- pass with every tier claimable. App Store purchases still cost money; an administrator never needs them.
create or replace function private.gold_spend(uid uuid, amount int, kind text, ref text default '') returns void
language plpgsql security definer set search_path = '' as $$
declare w public.gold_wallets := private.wallet(uid); top int;
begin
  if amount >= 0 and private.is_admin(uid) then
    top := greatest(0, private.store_extra('adminFloor') + amount - (w.balance - w.held));
    if top > 0 then
      update public.gold_wallets set balance = balance + top where user_id = uid;
      insert into public.gold_ledger (user_id, delta, kind, ref) values (uid, top, 'admin_topup', '');
      w := private.wallet(uid);
    end if;
  end if;
  if amount < 0 or amount > w.balance - w.held then raise exception 'not_enough_gold:%', greatest(0, amount - (w.balance - w.held)) using errcode = 'P0001'; end if;
  update public.gold_wallets set balance = balance - amount where user_id = uid;
  insert into public.gold_ledger (user_id, delta, kind, ref) values (uid, -amount, kind, coalesce(ref, ''));
end $$;

create or replace function private.store_spend(uid uuid, amount int, kind text, ref text) returns void
language plpgsql security definer set search_path = '' as $$
declare w public.gold_wallets := private.wallet(uid);
begin
  if w.debt > 0 and private.is_admin(uid) then
    update public.gold_wallets set debt = 0 where user_id = uid;
    w.debt := 0;
  end if;
  if w.debt > 0 then raise exception 'in_debt:%', w.debt using errcode = 'P0001'; end if;
  perform private.gold_spend(uid, amount, left(kind, 40), left(coalesce(ref, ''), 80));
end $$;

create or replace function private.has_premium(uid uuid, n int) returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_admin(uid)
      or exists (select 1 from public.pass_owners where user_id = uid and season = n)
      or exists (select 1 from public.store_plans where user_id = uid and revoked_at is null
                  and product_id in ('com.ledger.plus.monthly', 'com.ledger.plus.yearly') and expires_at > now() - interval '3 days')
      or (n = 1 and exists (select 1 from public.store_perks where user_id = uid and perk = 'founder'));
$$;

create or replace function private.pass_tier_ceiling(uid uuid, n int) returns int language plpgsql stable security definer set search_path = '' as $$
declare days int := greatest(1, (private.utc_today() - private.season_start(n)) + 1); xp int;
begin
  if private.is_admin(uid) then return 30; end if;
  xp := days * 200 + ceil(days / 7.0)::int * 120 + ceil(days / 30.0)::int * 240
      + coalesce((select bonus_tiers from public.pass_owners where user_id = uid and season = n), 0) * 300
      + coalesce((select sum(r.amount) from public.pass_claims c
                    join private.store_pass_rewards r on r.season = private.pass_season_def(n) and r.track = c.track and r.tier = c.tier and r.kind = 'xp'
                   where c.user_id = uid and c.season = n), 0);
  return least(30, xp / 300);
end $$;

-- Tops the wallet up to the floor and grants every current cosmetic (retired items are left out).
create or replace function private.admin_grant_all(uid uuid) returns void language plpgsql security definer set search_path = '' as $$
declare w public.gold_wallets := private.wallet(uid); top int;
begin
  top := greatest(0, private.store_extra('adminFloor') - (w.balance - w.held));
  if top > 0 then
    update public.gold_wallets set balance = balance + top, debt = 0 where user_id = uid;
    insert into public.gold_ledger (user_id, delta, kind, ref) values (uid, top, 'admin_topup', '');
  end if;
  insert into public.cosmetic_grants (user_id, cosmetic_id, source)
    select uid, c.id, 'admin' from private.store_cosmetics c where c.source <> 'retired'
    on conflict do nothing;
end $$;

-- One field for every code. An administrator code makes the account an administrator for good; a beta key pays gold
-- once per account. Each code works once. At most store_extra('codeTriesPerHour') tries per account an hour.
create or replace function public.redeem_code(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); norm text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
        c private.redeem_codes; v_gold int := 0;
begin
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  delete from private.redeem_attempts where user_id = uid and at < now() - interval '1 day';
  if (select count(*) from private.redeem_attempts where user_id = uid and at > now() - interval '1 hour') >= private.store_extra('codeTriesPerHour') then
    return jsonb_build_object('ok', false, 'reason', 'locked');
  end if;
  insert into private.redeem_attempts (user_id) values (uid);
  if char_length(norm) not between 12 and 64 then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  select * into c from private.redeem_codes r
   where r.redeemed_at is null and r.code_hash = encode(extensions.digest(r.salt || ':' || norm, 'sha256'), 'hex')
   limit 1 for update skip locked;
  if not found then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  if c.kind = 'admin' then
    if private.is_admin(uid) then return jsonb_build_object('ok', true, 'kind', 'admin', 'reason', 'already_admin', 'state', private.store_state_for(uid)); end if;
    update private.redeem_codes set redeemed_by = uid, redeemed_at = now() where id = c.id;
    insert into public.admins (user_id) values (uid) on conflict do nothing;
    perform private.admin_grant_all(uid);
    perform private.audit(uid, 'admin_granted', uid::text, null, jsonb_build_object('code', c.id), 'one-time code redeemed');
  else
    if exists (select 1 from private.redeem_codes where kind = 'beta' and redeemed_by = uid) then
      return jsonb_build_object('ok', false, 'kind', 'beta', 'reason', 'beta_used');
    end if;
    update private.redeem_codes set redeemed_by = uid, redeemed_at = now() where id = c.id;
    v_gold := private.store_extra('betaGold');
    perform private.store_credit(uid, v_gold, 'beta_key', c.id::text);
  end if;
  return jsonb_build_object('ok', true, 'kind', c.kind, 'reason', 'granted', 'gold', v_gold, 'state', private.store_state_for(uid));
end $$;

-- Gold for one rewarded ad. The claim id makes a retry safe: a claim already paid answers with its first payment.
-- The daily count follows the server day; the wait between ads is shorter for supporters.
create or replace function public.claim_ad_gold(p_claim text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); prev public.ad_claims; t jsonb; v_today int := private.era_day(); v_gold int; sup boolean;
begin
  perform private.require_free(uid, 'gold');
  if p_claim is null or char_length(p_claim) not between 8 and 64 then raise exception 'invalid_request' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  perform private.wallet(uid);
  select * into prev from public.ad_claims where user_id = uid and claim_id = p_claim;
  if found then return jsonb_build_object('ok', true, 'gold', prev.gold, 'repeat', true, 'state', private.store_state_for(uid)); end if;
  t := private.ad_terms(uid);
  if (t ->> 'used')::int >= (t ->> 'perDay')::int then
    return jsonb_build_object('ok', false, 'reason', 'daily_limit', 'state', private.store_state_for(uid));
  end if;
  if t ->> 'nextAt' is not null then
    return jsonb_build_object('ok', false, 'reason', 'cooldown', 'wait', ceil((t ->> 'nextAt')::numeric - extract(epoch from now()))::int,
                              'state', private.store_state_for(uid));
  end if;
  sup := private.is_supporter(uid);
  v_gold := (t ->> 'gold')::int;
  insert into public.ad_claims (user_id, claim_id, day, gold) values (uid, p_claim, v_today, v_gold);
  update public.gold_wallets set ads_watched = ads_watched + 1 where user_id = uid;
  perform private.store_credit(uid, v_gold, 'ad', p_claim);
  if not sup and private.is_supporter(uid) then perform private.refresh_supporter(uid); end if;
  return jsonb_build_object('ok', true, 'gold', v_gold, 'state', private.store_state_for(uid));
end $$;

-- Gold from daily, weekly and monthly missions. A claim is paid once per account, period and mission; the amount is
-- capped per mission, per server day and per server week (era day / 7), so a forged claim gains little.
create table public.mission_gold (
  user_id uuid not null references public.profiles (id) on delete cascade,
  period_key text not null check (char_length(period_key) between 1 and 40),
  mission_id text not null check (char_length(mission_id) between 1 and 80),
  day int not null,
  week int not null,
  gold int not null default 0 check (gold >= 0),
  created_at timestamptz not null default now(),
  primary key (user_id, period_key, mission_id)
);
create index mission_gold_day on public.mission_gold (user_id, day);
create index mission_gold_week on public.mission_gold (user_id, week);
alter table public.mission_gold enable row level security;
revoke all on public.mission_gold from anon, authenticated;

create or replace function public.claim_mission_gold(mission_id text, period_key text, gold int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v_today int := private.era_day(); v_week int := private.era_day() / 7; prev public.mission_gold;
        day_used int; week_used int; pay int;
begin
  perform private.require_free(uid, 'gold');
  if mission_id is null or char_length(mission_id) not between 1 and 80 or period_key is null or char_length(period_key) not between 1 and 40
     or gold is null or gold < 0 then
    raise exception 'invalid_request' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  select * into prev from public.mission_gold m where m.user_id = uid and m.period_key = claim_mission_gold.period_key and m.mission_id = claim_mission_gold.mission_id;
  if found then return jsonb_build_object('ok', true, 'gold', prev.gold, 'repeat', true, 'state', private.store_state_for(uid)); end if;
  day_used := coalesce((select sum(m.gold) from public.mission_gold m where m.user_id = uid and m.day = v_today), 0);
  week_used := coalesce((select sum(m.gold) from public.mission_gold m where m.user_id = uid and m.week = v_week), 0);
  pay := greatest(0, least(gold, private.store_extra('missionGold'), private.store_extra('missionGoldPerDay') - day_used,
                           private.store_extra('missionGoldPerWeek') - week_used));
  insert into public.mission_gold (user_id, period_key, mission_id, day, week, gold)
    values (uid, claim_mission_gold.period_key, claim_mission_gold.mission_id, v_today, v_week, pay);
  perform private.store_credit(uid, pay, 'mission', left(claim_mission_gold.period_key || ':' || claim_mission_gold.mission_id, 80));
  return jsonb_build_object('ok', true, 'gold', pay, 'state', private.store_state_for(uid));
end $$;

-- The account's store state, now with the shelf, ad terms, supporter and administrator flags.
create or replace function private.store_state_for(uid uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare w public.gold_wallets := private.wallet(uid); v_season int := private.current_season(); v_today int := private.era_day(); used int;
        adm boolean := private.is_admin(uid);
begin
  used := coalesce((select sum(gold) from public.money_claims where user_id = uid and kind = 'pack' and created_at > now() - interval '7 days'), 0);
  return jsonb_build_object(
    'account', uid,
    'serverTime', extract(epoch from now()),
    'serverDay', v_today,
    'season', v_season,
    'wallet', jsonb_build_object('balance', w.balance - w.held),
    'debt', case when adm then 0 else w.debt end,
    'boxes', coalesce((select jsonb_object_agg(kind, count) from public.gold_box_stock where user_id = uid and count > 0), '{}'::jsonb),
    'pity', jsonb_build_object('sinceRare', w.pity),
    'firstPurchaseDone', w.first_purchase_done,
    'boxesOpened', w.boxes_opened,
    'cabinet', jsonb_build_object(
      'items', coalesce((select jsonb_agg(jsonb_build_object('defID', def_id, 'serial', serial, 'origin', origin) order by acquired_at, def_id, serial)
                           from public.store_cabinet where user_id = uid), '[]'::jsonb),
      'rewarded', coalesce((select jsonb_agg(collection_id order by collection_id) from public.store_collections_done where user_id = uid), '[]'::jsonb)),
    'cosmetics', coalesce((select jsonb_agg(x.id order by x.id) from (
                             select cosmetic_id as id from public.cosmetic_grants where user_id = uid
                             union
                             select c.id from private.store_cosmetics c where adm and c.source <> 'retired') x), '[]'::jsonb),
    'premium', private.has_premium(uid, v_season),
    'passBonusTiers', coalesce((select bonus_tiers from public.pass_owners where user_id = uid and season = v_season), 0),
    'passClaims', coalesce((select jsonb_agg(track || tier::text order by track, tier) from public.pass_claims where user_id = uid and season = v_season), '[]'::jsonb),
    'levelGoldPaid', w.level_gold_paid,
    'streak', jsonb_build_object('count', w.streak_count, 'best', w.streak_best, 'openedToday', w.streak_day = v_today),
    'freeMoneyLeft', greatest(0, private.store_setting('freeMoneyPerDay')
                       - (select count(*) from public.money_claims where user_id = uid and kind = 'free' and day = v_today)::int),
    'moneyWeek', jsonb_build_object('used', used, 'cap', case when adm then 1000000000 else private.store_setting('moneyPackWeeklyGold') end),
    'unpaidMoney', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'pack', pack_id, 'amount', amount) order by created_at)
                               from public.money_claims where user_id = uid and paid_at is null and created_at > now() - interval '14 days'), '[]'::jsonb),
    'imported', exists (select 1 from public.store_imports where user_id = uid),
    'importsGold', private.made_before_cutoff(uid),
    'isAdmin', adm,
    'supporter', private.is_supporter(uid),
    'ads', private.ad_terms(uid),
    'shelf', jsonb_build_object('day', v_today,
                                'items', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'price', s.price)) from private.store_shelf(v_today) s), '[]'::jsonb)),
    'betaRedeemed', exists (select 1 from private.redeem_codes where kind = 'beta' and redeemed_by = uid));
end $$;

-- Store cosmetics are sold from the day's shelf (yesterday's too, for a shelf opened just before midnight);
-- save slots are always on sale. Pass items never are. Administrators have no weekly money limit.
create or replace function public.store_buy(p_kind text, p_id text, p_request text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); prev jsonb; out jsonb; b private.store_box_bundles; c private.store_cosmetics; v_price int;
        mp private.store_money_packs; used int; cap int := private.store_setting('moneyPackWeeklyGold'); v_today int := private.era_day();
begin
  perform private.require_free(uid, 'gold');
  prev := private.store_request(uid, p_request, 'buy', 20, 300);
  if prev is not null then return prev || jsonb_build_object('state', private.store_state_for(uid)); end if;
  if p_kind = 'bundle' then
    select * into b from private.store_box_bundles where id = p_id;
    if not found then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    perform private.store_spend(uid, b.price, 'bundle', p_id);
    perform private.add_boxes(uid, b.kind, b.count);
    out := jsonb_build_object('kind', p_kind, 'id', p_id);
  elsif p_kind = 'cosmetic' then
    if exists (select 1 from private.store_pass_rewards r where r.reward_id = p_id) then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    select k.price into v_price from private.store_cosmetics k
     where k.id = p_id and k.source = 'store' and k.kind = 'saveSlot' and k.price is not null and private.theme_live(k.theme);
    if v_price is null then select s.price into v_price from private.store_shelf(v_today) s where s.id = p_id; end if;
    if v_price is null then select s.price into v_price from private.store_shelf(v_today - 1) s where s.id = p_id; end if;
    if v_price is null then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    if exists (select 1 from public.cosmetic_grants where user_id = uid and cosmetic_id = p_id) then raise exception 'already_owned' using errcode = 'P0001'; end if;
    perform private.store_spend(uid, v_price, p_kind, p_id);
    insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (uid, p_id, 'store');
    out := jsonb_build_object('kind', p_kind, 'id', p_id);
  elsif p_kind = 'avatar' then
    select * into c from private.store_cosmetics k where k.id = p_id and k.price is not null and private.theme_live(k.theme) and k.source = 'avatar';
    if not found then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    if exists (select 1 from public.cosmetic_grants where user_id = uid and cosmetic_id = p_id) then raise exception 'already_owned' using errcode = 'P0001'; end if;
    perform private.store_spend(uid, c.price, p_kind, p_id);
    insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (uid, p_id, 'store');
    out := jsonb_build_object('kind', p_kind, 'id', p_id);
  elsif p_kind = 'service' then
    select s.price into v_price from private.store_services s where s.id = p_id;
    if v_price is null then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    perform private.store_spend(uid, v_price, 'service', p_id);
    out := jsonb_build_object('kind', p_kind, 'id', p_id);
  elsif p_kind = 'money' then
    select * into mp from private.store_money_packs where id = p_id and not free;
    if not found then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    if private.is_admin(uid) then cap := 1000000000; end if;
    used := coalesce((select sum(gold) from public.money_claims where user_id = uid and kind = 'pack' and created_at > now() - interval '7 days'), 0);
    if used + mp.gold > cap then raise exception 'weekly_limit:%', greatest(0, cap - used) using errcode = 'P0001'; end if;
    perform private.store_spend(uid, mp.gold, 'money_pack', p_id);
    insert into public.money_claims (id, user_id, kind, pack_id, gold, day) values (p_request, uid, 'pack', p_id, mp.gold, private.era_day());
    out := jsonb_build_object('kind', p_kind, 'id', p_id, 'claimID', p_request);
  else
    raise exception 'unknown_item' using errcode = 'P0001';
  end if;
  perform private.store_done(uid, p_request, 'buy', out);
  return out || jsonb_build_object('state', private.store_state_for(uid));
end $$;

-- The old administrator-only entry is replaced by redeem_code; its code hash was public in the repo.
revoke execute on function public.redeem_admin_code(text) from public, anon, authenticated;
update public.admin_codes set expires_at = least(expires_at, now()) where redeemed_at is null;

-- Players who already bought something show the badge from now on.
update public.profiles set badges = badges
 where id in (select user_id from public.store_transactions where revoked_at is null
              union select user_id from public.store_plans where revoked_at is null);

revoke execute on function public.redeem_code(text), public.claim_ad_gold(text), public.claim_mission_gold(text, text, int) from public, anon;
grant execute on function public.redeem_code(text), public.claim_ad_gold(text), public.claim_mission_gold(text, text, int) to authenticated;
