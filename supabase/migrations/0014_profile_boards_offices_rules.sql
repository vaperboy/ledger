-- Profile icon, leaderboards, accountant offices run by players, and the exchange rules brought closer to the engine's.
--
--  1. profiles.avatar_icon (the icon a player wears) is added and carried by the profile read and by a new update function.
--     profiles.is_simulated is dropped: the seed no longer marks its stand-ins, so every use of the column is rewritten below
--     (name check, profile_json, voting, standing for office, the election cycle). The election cycle now counts only profiles with the
--     18+ confirmation, which the seed's placeholder players never have, so they still never trigger an election.
--  2. Leaderboards: one row per account (net worth and trading result, self-reported, bounded), written only by publish_leaderboard and
--     read only by read_leaderboards. Players whose privacy is not public are left off the boards other players read.
--  3. Accountant offices: a player opens an office, other players hire it for a company and pay a one-time hiring fee that moves
--     through settlements (client pays, owner receives). The rating is the average of the stars real clients gave after at least one game
--     week of hire (seven game days); with fewer than three ratings it is null, never invented.
--  4. Exchange rules of 0006 re-issued from their own definitions (nothing else in them changes) to match ExchangeRules.swift:
--       - closing price: an order stays within 10% of the previous close (last trade before the current game day), inside the value band
--       - holder cap: an outsider holds, with open buy orders, at most 20% of the shares
--       - the owner cannot sell during the 28-day lock-up after listing, nor in the 7 game days before a quarter's results (every 91 days)
--         nor the first game day after them; resting owner sell orders do not trade inside those windows either
--       - the owner's value report moves at most 10% and at most once a game day (it was 25% an hour)
--     A game day is private.weeks(1) / 7, so these windows follow the one definition of a game week in 0002.
--     STILL DIFFERENT from the engine (the server is looser, the engine stays the stricter side): no dividend blackout (the server has no
--     dividends), no minimum company age of 26 weeks to list, no cap of 20 open orders per trader, no minimum order size, no 200,000,000
--     position cap, no broker fee, and the server matches continuously against the book while the engine clears one closing auction.
--     The "previous close" is the last trade before the current game day, or the value per share when nothing has traded yet.
--  5. world_rules_read(): every rule plus the exchange constants above, for the clients (the existing world_rules_snapshot() stays).
--
-- Applied migrations 0001-0013 are not edited; everything here is ALTER, create or replace, or new.

create extension if not exists pgcrypto with schema extensions;

-- A function re-issued from its own definition with text swapped; it stops the migration when a piece of text is not found.
create function private.rewire14(fn regprocedure, pairs text[]) returns void language plpgsql as $$
declare d text := pg_get_functiondef(fn); n text; i int;
begin
  for i in 1..cardinality(pairs) by 2 loop
    n := replace(d, pairs[i], pairs[i + 1]);
    if n = d then raise exception 'rewire14: text not found in %: %', fn, pairs[i]; end if;
    d := n;
  end loop;
  execute d;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Profile icon; no more is_simulated
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.profiles add column avatar_icon text
  constraint avatar_icon_shape check (avatar_icon is null or avatar_icon ~ '^[a-z][a-z0-9._-]{0,39}$');
-- Not in the client column grants: the only write path is update_my_profile below.

select private.rewire14('private.check_name()'::regprocedure, array[
  $a$new.is_simulated or new.display_name = 'Deleted player'$a$, $a$new.display_name = 'Deleted player'$a$]);
select private.rewire14('private.profile_json(uuid, uuid)'::regprocedure, array[
  $a$'id', p.id, 'code', p.code,$a$, $a$'id', p.id, 'code', p.code, 'avatarIcon', p.avatar_icon,$a$,
  $a$'isSimulated', p.is_simulated,$a$, $a$$a$]);
select private.rewire14('private.may_vote(uuid, text)'::regprocedure, array[$a$ and not is_simulated$a$, $a$$a$]);
select private.rewire14('private.may_stand(uuid, text)'::regprocedure, array[$a$ and not is_simulated$a$, $a$$a$]);
select private.rewire14('private.run_election_cycle()'::regprocedure, array[$a$and not p.is_simulated$a$, $a$and p.adult_confirmed$a$]);

alter table public.profiles drop column is_simulated;

-- Every editable profile field in one validated call; null leaves a field as it is, an empty icon takes the icon off.
create function public.update_my_profile(p_display_name text default null, p_avatar_colour int default null, p_country_code text default null,
                                         p_privacy public.privacy_level default null, p_avatar_icon text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  if not exists (select 1 from public.profiles where id = uid and deleted_at is null) then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  update public.profiles set
      display_name = coalesce(p_display_name, display_name),
      avatar_colour = coalesce(p_avatar_colour, avatar_colour),
      country_code = coalesce(upper(p_country_code), country_code),
      privacy = coalesce(p_privacy, privacy),
      avatar_icon = case when p_avatar_icon is null then avatar_icon when p_avatar_icon = '' then null else p_avatar_icon end
   where id = uid and deleted_at is null;
  return private.profile_json(uid, uid);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Leaderboards
-- ---------------------------------------------------------------------------------------------------------------------
-- Amounts are in accounting units (the same in every country). The bounds keep a forged figure from topping a board by orders of magnitude.
create table public.leaderboard_entries (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  net_worth numeric(20, 2) not null check (net_worth between -1000000000000 and 10000000000000),
  trading_result numeric(20, 2) not null check (trading_result between -1000000000000 and 1000000000000),
  game_week int not null check (game_week between 0 and 100000),
  updated_at timestamptz not null default now()
);
create index leaderboard_net_worth on public.leaderboard_entries (net_worth desc);
create index leaderboard_trading on public.leaderboard_entries (trading_result desc);
alter table public.leaderboard_entries enable row level security;
revoke all on public.leaderboard_entries from anon, authenticated;   -- no policy, no grant: clients neither read nor write the table

-- Stores the caller's own figures (name and country come from the profile, never from the call). Faster than every 30 seconds is ignored.
create function public.publish_leaderboard(p_net_worth numeric, p_trading_result numeric, p_game_week int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); last timestamptz;
begin
  perform private.require_free(uid, 'trade');
  if p_net_worth is null or p_trading_result is null or p_game_week is null
     or p_net_worth not between -1000000000000 and 10000000000000 or p_trading_result not between -1000000000000 and 1000000000000
     or p_game_week not between 0 and 100000 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  select updated_at into last from public.leaderboard_entries where user_id = uid;
  if last is not null and now() - last < interval '30 seconds' then return jsonb_build_object('accepted', false); end if;
  insert into public.leaderboard_entries (user_id, net_worth, trading_result, game_week)
    values (uid, round(p_net_worth, 2), round(p_trading_result, 2), p_game_week)
    on conflict (user_id) do update set net_worth = excluded.net_worth, trading_result = excluded.trading_result,
                                        game_week = excluded.game_week, updated_at = now();
  return jsonb_build_object('accepted', true);
end $$;

-- The other players on the boards: the best p_limit by net worth together with the best p_limit by trading result (at most 500 each),
-- never the caller, nobody blocked in either direction, and only players whose profile is public.
create function public.read_leaderboards(p_limit int default 300) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); n int := least(greatest(coalesce(p_limit, 300), 10), 500);
begin
  return coalesce((
    with visible as (
      select e.user_id, p.display_name, e.game_week, e.net_worth, e.trading_result
        from public.leaderboard_entries e join public.profiles p on p.id = e.user_id
       where p.deleted_at is null and p.adult_confirmed and p.privacy = 'public' and e.user_id <> uid
         and not private.is_blocked_between(uid, e.user_id)),
    a as (select * from visible order by net_worth desc, display_name limit n),
    b as (select * from visible order by trading_result desc, display_name limit n)
    select jsonb_agg(jsonb_build_object('playerID', x.user_id, 'name', x.display_name, 'week', x.game_week,
                                        'netWorth', x.net_worth, 'tradingResult', x.trading_result))
      from (select * from a union select * from b) x), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Accountant offices run by players
-- ---------------------------------------------------------------------------------------------------------------------
create table public.accountant_offices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references public.profiles (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 40),
  city text not null default '' check (char_length(city) <= 60),
  country text not null check (country ~ '^[A-Z]{2}$'),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  -- One-time fee for each hire, in the office's currency (reference economy 0 to 5,000, scaled to the currency).
  hire_fee numeric(18, 2) not null check (hire_fee >= 0),
  active boolean not null default true,
  opened_at timestamptz not null default now()
);
create index accountant_offices_listing on public.accountant_offices (country) where active;

-- One row per hire. `stars` is the client's own rating of that hire and the only source of an office's rating.
create table public.accountant_hires (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references public.accountant_offices (id) on delete cascade,
  client_id uuid not null references public.profiles (id) on delete cascade,
  company_key text not null check (char_length(company_key) between 1 and 64),
  fee numeric(18, 2) not null check (fee >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  hired_at timestamptz not null default now(),
  ended_at timestamptz,
  stars int check (stars between 1 and 5),
  rated_at timestamptz
);
create unique index accountant_hires_one_active on public.accountant_hires (client_id, company_key) where ended_at is null;
create index accountant_hires_office on public.accountant_hires (office_id);
create index accountant_hires_client on public.accountant_hires (client_id);

alter table public.accountant_offices enable row level security;
alter table public.accountant_hires enable row level security;
revoke all on public.accountant_offices, public.accountant_hires from anon, authenticated;   -- reached only through the functions below

-- The office and its record as everyone may see it. rating is null until three clients have rated.
create function private.office_json(o public.accountant_offices, uid uuid) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', o.id, 'officeName', o.name, 'ownerID', o.owner_id, 'ownerName', private.display_name(o.owner_id), 'city', o.city,
      'countryCode', o.country, 'currency', o.currency, 'hireFee', o.hire_fee, 'isMine', o.owner_id = uid,
      'rating', case when s.n >= 3 then round(s.avg_stars, 1) end, 'ratingCount', s.n, 'hires', s.hires, 'activeClients', s.active_clients)
    from (select count(h.stars) as n, avg(h.stars) as avg_stars, count(*) as hires, count(*) filter (where h.ended_at is null) as active_clients
            from public.accountant_hires h where h.office_id = o.id) s;
$$;

-- Opens (or reopens) the caller's one office. The name follows the display-name word rules; the fee is bounded to 5,000 reference units.
create function public.open_accountant_office(p_name text, p_city text, p_currency text, p_hire_fee numeric) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); o public.accountant_offices; why text; cc text; nm text := trim(coalesce(p_name, ''));
begin
  perform private.require_free(uid, 'trade');
  if now() - (select created_at from public.profiles where id = uid) < private.weeks(4) then raise exception 'new_account' using errcode = 'P0001'; end if;
  if char_length(nm) not between 2 and 40 or p_currency is null or p_currency !~ '^[A-Z]{3}$' or char_length(coalesce(p_city, '')) > 60
     or p_hire_fee is null or p_hire_fee < 0 or p_hire_fee > 5000 * private.currency_scale(p_currency) then raise exception 'invalid_office' using errcode = 'P0001'; end if;
  why := private.name_problem(nm);
  if why is not null then raise exception 'name_rejected: %', why using errcode = 'P0001'; end if;
  select country_code into cc from public.profiles where id = uid;
  insert into public.accountant_offices (owner_id, name, city, country, currency, hire_fee)
    values (uid, nm, trim(coalesce(p_city, '')), cc, p_currency, round(p_hire_fee, 2))
    on conflict (owner_id) do update set name = excluded.name, city = excluded.city, country = excluded.country, currency = excluded.currency,
                                         hire_fee = excluded.hire_fee, active = true
    returning * into o;
  return private.office_json(o, uid);
end $$;

-- Takes the office off the list. Clients already hired keep their hire until they end it.
create function public.close_accountant_office() returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  update public.accountant_offices set active = false where owner_id = uid and active;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
end $$;

-- Open offices (best rated first, then most hired), optionally of one country; nobody blocked in either direction. At most 50 rows.
create function public.list_accountant_offices(p_country text default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(j order by (j ->> 'rating')::numeric desc nulls last, (j ->> 'hires')::int desc, j ->> 'officeName') from (
      select private.office_json(o, uid) as j from public.accountant_offices o
       where o.active and (p_country is null or o.country = upper(p_country)) and not private.is_blocked_between(uid, o.owner_id)
       order by o.opened_at limit 200) x), '[]'::jsonb);
end $$;

-- The caller hires an office for one of their companies. The hiring fee moves through settlements: the client's ledger books the cost,
-- the owner's books the income. Hiring another office for the same company ends the earlier hire. Not your own or a linked account's office.
create function public.hire_accountant_office(p_office uuid, p_company_key text, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); o public.accountant_offices; h public.accountant_hires; cur public.accountant_hires;
begin
  perform private.require_free(uid, 'trade');
  select * into o from public.accountant_offices where id = p_office and active;
  if not found or private.is_blocked_between(uid, o.owner_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if o.owner_id = uid or private.linked(o.owner_id, uid) then raise exception 'own_office' using errcode = 'P0001'; end if;
  if p_currency is distinct from o.currency then raise exception 'currency_mismatch' using errcode = 'P0001'; end if;
  if p_company_key is null or char_length(p_company_key) not between 1 and 64 then raise exception 'invalid_office' using errcode = 'P0001'; end if;
  if now() - (select created_at from public.profiles where id = uid) < private.weeks(4) then raise exception 'new_account' using errcode = 'P0001'; end if;
  select * into cur from public.accountant_hires where client_id = uid and company_key = p_company_key and ended_at is null for update;
  if found then
    if cur.office_id = o.id then raise exception 'already_hired' using errcode = 'P0001'; end if;
    update public.accountant_hires set ended_at = now() where id = cur.id;
  end if;
  insert into public.accountant_hires (office_id, client_id, company_key, fee, currency) values (o.id, uid, p_company_key, o.hire_fee, o.currency) returning * into h;
  if o.hire_fee > 0 then
    perform private.settle(uid, -o.hire_fee, o.currency, 'accountant_hire_fee', h.id::text, 'Accountant office: ' || o.name,
      jsonb_build_object('officeID', o.id, 'companyKey', p_company_key, 'hireID', h.id));
    perform private.settle(o.owner_id, o.hire_fee, o.currency, 'accountant_fee_income', h.id::text, 'New client for ' || o.name,
      jsonb_build_object('officeID', o.id, 'hireID', h.id));
  end if;
  return jsonb_build_object('hireID', h.id, 'officeID', o.id, 'fee', o.hire_fee, 'currency', o.currency);
end $$;

create function public.end_accountant_hire(p_company_key text) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  update public.accountant_hires set ended_at = now() where client_id = uid and company_key = p_company_key and ended_at is null;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
end $$;

-- A client rates one of their own hires once, after the hire has run for a game week. That is the only way an office gets a rating.
create function public.rate_accountant_hire(p_hire uuid, p_stars int) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); h public.accountant_hires;
begin
  if p_stars is null or p_stars not between 1 and 5 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  select * into h from public.accountant_hires where id = p_hire and client_id = uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if h.stars is not null then raise exception 'already_rated' using errcode = 'P0001'; end if;
  if now() - h.hired_at < private.weeks(1) then raise exception 'too_early' using errcode = 'P0001'; end if;
  update public.accountant_hires set stars = p_stars, rated_at = now() where id = h.id;
end $$;

-- The caller's own hires (newest first) so the app can end or rate them, and their own office if they run one.
create function public.my_accountant_hires() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); o public.accountant_offices;
begin
  select * into o from public.accountant_offices where owner_id = uid;
  return jsonb_build_object(
    'hires', coalesce((select jsonb_agg(jsonb_build_object('hireID', h.id, 'officeID', h.office_id, 'officeName', f.name, 'companyKey', h.company_key,
          'fee', h.fee, 'currency', h.currency, 'hiredAt', h.hired_at, 'active', h.ended_at is null, 'stars', h.stars) order by h.hired_at desc)
        from public.accountant_hires h join public.accountant_offices f on f.id = h.office_id where h.client_id = uid), '[]'::jsonb),
    'office', case when o.id is null then null else private.office_json(o, uid) end);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Exchange rules aligned with the engine
-- ---------------------------------------------------------------------------------------------------------------------
-- A game day in real time (a game week is private.weeks(1), seven game days).
create function private.game_days(n int) returns interval language sql immutable as $$ select private.weeks(1) * n / 7; $$;

-- The exchange constants the engine (ExchangeRules.swift) also holds. Fixed here: moving them is a migration, not an admin change.
create function private.exchange_const(k text) returns numeric language sql immutable as $$
  select case k when 'day_move' then 0.10 when 'value_step' then 0.10 when 'holder_cap' then 0.20 when 'owner_floor' then 0.51
                when 'lockup_days' then 28 when 'quarter_days' then 91 when 'blackout_before' then 7 when 'blackout_after' then 1 end;
$$;

-- The previous close: the last trade before the current game day; null when nothing has traded before it.
create function private.exchange_close_ref(lid uuid) returns numeric language sql stable security definer set search_path = '' as $$
  select price from public.exchange_trades
   where listing_id = lid
     and traded_at < to_timestamp(floor(extract(epoch from now()) / extract(epoch from private.game_days(1))) * extract(epoch from private.game_days(1)))
   order by id desc limit 1;
$$;

-- Where a price may sit now: within a tenth of the previous close (the value per share when there is none) and inside the value band.
create function private.exchange_close_bounds(l public.exchange_listings) returns numeric[] language plpgsql stable security definer set search_path = '' as $$
declare nav numeric := private.exchange_nav(l); blo numeric := round(nav * private.rule_num('band.exchange_low'), 4); bhi numeric := round(nav * private.rule_num('band.exchange_high'), 4);
        pc numeric := coalesce(private.exchange_close_ref(l.id), nav); dm numeric := private.exchange_const('day_move'); lo numeric; hi numeric;
begin
  lo := greatest(round(pc * (1 - dm), 4), blo); hi := least(round(pc * (1 + dm), 4), bhi);
  if lo > hi then lo := round(least(greatest(pc, blo), bhi), 4); hi := lo; end if;
  return array[lo, hi];
end $$;

-- Shares an outsider may still buy before the holder cap (holdings and open buy orders count). The owner has no cap.
create function private.exchange_buyable(l public.exchange_listings, uid uuid) returns bigint language sql stable security definer set search_path = '' as $$
  select greatest(0, floor(l.total_shares * private.exchange_const('holder_cap'))::bigint
       - coalesce((select shares from public.exchange_holdings where listing_id = l.id and owner_id = uid), 0)
       - coalesce((select sum(remaining) from public.exchange_orders where listing_id = l.id and trader_id = uid and side = 'buy' and status = 'open'), 0));
$$;

-- Why the owner may not sell now: 'lock_up', 'blackout', or null when the window is open (same days as ExchangeRules.insiderBlock, without dividends).
create function private.exchange_insider_block(l public.exchange_listings) returns text language plpgsql stable security definer set search_path = '' as $$
declare n int := floor(extract(epoch from now() - l.listed_at) / extract(epoch from private.game_days(1)))::int;
        q int := private.exchange_const('quarter_days')::int; r int;
begin
  if n < private.exchange_const('lockup_days')::int then return 'lock_up'; end if;
  r := n % q;
  if r >= q - private.exchange_const('blackout_before')::int then return 'blackout'; end if;
  if n >= q and r <= private.exchange_const('blackout_after')::int then return 'blackout'; end if;
  return null;
end $$;

select private.rewire14('public.place_exchange_order(uuid, public.exchange_side, bigint, numeric, text)'::regprocedure, array[
  $a$l public.exchange_listings; nav numeric;$a$, $a$l public.exchange_listings; cb numeric[]; ib text; nav numeric;$a$,
  $a$raise exception 'outside_band' using errcode = 'P0001'; end if;$a$,
  $a$raise exception 'outside_band' using errcode = 'P0001'; end if;
  cb := private.exchange_close_bounds(l);
  if p_price < cb[1] or p_price > cb[2] then raise exception 'outside_day_limit' using errcode = 'P0001'; end if;
  if p_side = 'buy' and uid <> l.owner_id and p_shares > private.exchange_buyable(l, uid) then raise exception 'holder_cap' using errcode = 'P0001'; end if;
  if p_side = 'sell' and uid = l.owner_id then
    ib := private.exchange_insider_block(l);
    if ib is not null then raise exception using message = ib, errcode = 'P0001'; end if;
  end if;$a$,
  $a$and x.trader_id <> uid and not private.linked(x.trader_id, uid)$a$,
  $a$and not (x.side = 'sell' and x.trader_id = l.owner_id and private.exchange_insider_block(l) is not null)
            and x.trader_id <> uid and not private.linked(x.trader_id, uid)$a$]);

select private.rewire14('public.report_exchange_value(uuid, numeric)'::regprocedure, array[
  $a$now() - l.value_reported_at < interval '1 hour'$a$, $a$now() - l.value_reported_at < private.game_days(1)$a$,
  $a$p_value > l.value * 1.25 or p_value < l.value * 0.75$a$,
  $a$p_value > l.value * (1 + private.exchange_const('value_step')) or p_value < l.value * (1 - private.exchange_const('value_step'))$a$]);

select private.rewire14('public.exchange_market()'::regprocedure, array[
  $a$'priceLow', round(private.exchange_nav(l) * private.rule_num('band.exchange_low'), 4), 'priceHigh', round(private.exchange_nav(l) * private.rule_num('band.exchange_high'), 4),$a$,
  $a$'priceLow', (private.exchange_close_bounds(l))[1], 'priceHigh', (private.exchange_close_bounds(l))[2],$a$]);

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. World rules for the clients
-- ---------------------------------------------------------------------------------------------------------------------
-- The admin-set rules and the fixed exchange constants in one object, with the time of the last change, so a client can rebuild the
-- engine's rules from it and know when it is stale.
create function public.world_rules_read() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  return jsonb_build_object(
    'rules', coalesce((select jsonb_object_agg(key, value) from public.world_rules), '{}'::jsonb),
    'exchange', jsonb_build_object(
      'bandLow', private.rule_num('band.exchange_low'), 'bandHigh', private.rule_num('band.exchange_high'),
      'dayMoveShare', private.exchange_const('day_move'), 'valueStepShare', private.exchange_const('value_step'),
      'holderCapShare', private.exchange_const('holder_cap'), 'ownerFloorShare', private.exchange_const('owner_floor'),
      'lockUpDays', private.exchange_const('lockup_days'), 'quarterDays', private.exchange_const('quarter_days'),
      'blackoutBefore', private.exchange_const('blackout_before'), 'blackoutAfter', private.exchange_const('blackout_after')),
    'updatedAt', (select max(updated_at) from public.world_rules));
end $$;

drop function private.rewire14(regprocedure, text[]);

-- ---------------------------------------------------------------------------------------------------------------------
-- Execute rights
-- ---------------------------------------------------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on function public.update_my_profile(text, int, text, public.privacy_level, text), public.publish_leaderboard(numeric, numeric, int),
  public.read_leaderboards(int), public.open_accountant_office(text, text, text, numeric), public.close_accountant_office(),
  public.list_accountant_offices(text), public.hire_accountant_office(uuid, text, text), public.end_accountant_hire(text),
  public.rate_accountant_hire(uuid, int), public.my_accountant_hires(), public.world_rules_read() to authenticated;
