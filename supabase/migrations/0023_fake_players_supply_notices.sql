create table if not exists public.world_flags (
  key text primary key check (char_length(key) between 1 and 40),
  value jsonb not null default 'true'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.world_flags enable row level security;
revoke all on public.world_flags from anon, authenticated;

alter table public.supply_listings add column if not exists logo_id text not null default '' check (char_length(logo_id) <= 40);

create or replace function private.fakes_removed() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select (value)::text = 'true' from public.world_flags where key = 'fakes_removed'), false);
$$;

create or replace function private.bot_target() returns int language sql stable security definer set search_path = '' as $$
  select case when private.fakes_removed() then 0
              else least(40, greatest(8, 36 - (select count(*) / 2 from public.profiles
                                                where not is_bot and adult_confirmed and deleted_at is null and last_seen_at > now() - interval '14 days')::int)) end;
$$;

create or replace function private.bot_ensure(target int) returns void language plpgsql security definer set search_path = '' as $$
declare s int;
begin
  if private.fakes_removed() then return; end if;
  for s in 0..target - 1 loop
    if not exists (select 1 from public.bots where slot = s) then perform private.bot_create(s); end if;
  end loop;
end $$;

create or replace function private.bot_tick() returns int language plpgsql security definer set search_path = '' as $$
declare target int := private.bot_target(); b public.bots; p public.profiles; hour_key bigint := floor(extract(epoch from now()) / 3600)::bigint;
        l public.exchange_listings; n int := 0; wk int; nw numeric; share numeric;
begin
  if private.fakes_removed() then return 0; end if;
  perform private.bot_ensure(target);
  update public.bots set active = slot < target;
  for b in select * from public.bots where active order by slot loop
    select * into p from public.profiles where id = b.user_id;
    wk := floor(extract(epoch from now() - p.created_at) / 86400 * 3)::int;
    update public.profiles set game_week = wk, level = 1 + wk / 14, trades_completed = greatest(trades_completed, wk * 2 / 3),
           last_seen_at = case when private.bot_awake(p.id) then now() else last_seen_at end
     where id = p.id;
    nw := round(15000 * power(1.19, b.slot) * (1 + 0.012 * wk) * (0.97 + (abs(hashtext(p.id::text || hour_key::text)) % 60) / 1000.0));
    share := ((abs(hashtext(p.id::text || 'tr')) % 220) / 1000.0) - 0.06;
    update public.leaderboard_entries set net_worth = nw, trading_result = round(nw * share), game_week = wk, updated_at = now() where user_id = p.id;
    perform private.bot_events(b, p, hour_key);
    n := n + 1;
  end loop;
  for l in select * from public.exchange_listings where delisted_at is null and not exists (select 1 from public.profiles o where o.id = owner_id and o.is_bot) loop
    perform private.bot_quote(l, hour_key);
  end loop;
  return n;
end $$;

create or replace function public.admin_remove_fake_players(p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin(); why text := trim(coalesce(p_reason, '')); n int;
begin
  if char_length(why) < 3 then raise exception 'reason_required' using errcode = 'P0001'; end if;
  insert into public.world_flags (key, value, updated_by) values ('fakes_removed', 'true'::jsonb, uid)
    on conflict (key) do update set value = 'true'::jsonb, updated_at = now(), updated_by = uid;
  update public.supply_contracts set ended_at = now(), end_reason = 'stopped'
   where ended_at is null and (supplier_id in (select id from public.profiles where is_bot) or buyer_id in (select id from public.profiles where is_bot));
  update public.supply_listings set stopped = true where not stopped and owner_id in (select id from public.profiles where is_bot);
  update public.exchange_orders set status = 'cancelled' where status = 'open' and trader_id in (select id from public.profiles where is_bot);
  update public.exchange_listings set delisted_at = now() where delisted_at is null and owner_id in (select id from public.profiles where is_bot);
  delete from public.leaderboard_entries where user_id in (select id from public.profiles where is_bot);
  delete from public.companies_public where owner_id in (select id from public.profiles where is_bot);
  update public.bots set active = false;
  update public.profiles set deleted_at = now() where is_bot and deleted_at is null;
  get diagnostics n = row_count;
  perform private.audit(uid, 'remove_fake_players', 'world', null, to_jsonb(n), why);
  return jsonb_build_object('removed', n);
end $$;

create or replace function public.account_status() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); p public.profiles; had boolean;
begin
  select * into p from public.profiles where id = uid and deleted_at is null;
  had := found;
  return jsonb_build_object(
    'hasProfile', had,
    'adultConfirmed', had and p.adult_confirmed,
    'isAdmin', had and p.adult_confirmed and private.is_admin(uid),
    'linkRewardGold', private.link_reward_gold(),
    'linkRewardClaimed', exists (select 1 from public.link_reward_claims where user_id = uid),
    'fakePlayersRemoved', private.fakes_removed());
end $$;

create or replace function public.sign_supply_contract(p_company_key text, p_line_id text, p_listing uuid, p_units int, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.supply_listings; why text; c public.supply_contracts;
begin
  perform private.require_free(uid, 'trade');
  if p_units is null or p_units < 1 then raise exception 'invalid_units' using errcode = 'P0001'; end if;
  select * into l from public.supply_listings where id = p_listing for update;
  if not found or l.line_id <> p_line_id or private.is_blocked_between(uid, l.owner_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if l.currency <> p_currency then raise exception 'currency_mismatch' using errcode = 'P0001'; end if;
  update public.supply_contracts set ended_at = now(), end_reason = 'replaced' where buyer_id = uid and buyer_company_key = p_company_key and line_id = p_line_id and ended_at is null;
  why := private.supply_availability(l, uid, p_units);
  if why <> 'available' then raise exception 'listing_%', why using errcode = 'P0001'; end if;
  if private.supply_committed(l.id) + p_units > private.supply_effective_capacity(l) then raise exception 'listing_full' using errcode = 'P0001'; end if;
  insert into public.supply_contracts (buyer_id, buyer_company_key, line_id, listing_id, supplier_id, supplier_name, units_per_week, unit_price)
    values (uid, p_company_key, p_line_id, l.id, l.owner_id, private.display_name(l.owner_id), p_units, private.supply_unit_price(l)) returning * into c;
  perform private.settle(l.owner_id, 0, l.currency, 'supply_notice', c.id::text || ':start',
    private.display_name(uid) || ' started buying ' || ceil(p_units * 52.0 / 12)::int || ' units a month from you.',
    jsonb_build_object('companyKey', l.company_key, 'listingID', l.id, 'units', p_units));
  return private.supply_contract_json(c);
end $$;

create or replace function public.end_supply_contract(p_company_key text, p_line_id text) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); c public.supply_contracts; l public.supply_listings; fee numeric;
begin
  select * into c from public.supply_contracts where buyer_id = uid and buyer_company_key = p_company_key and line_id = p_line_id and ended_at is null for update;
  if not found then return; end if;
  update public.supply_contracts set ended_at = now(), end_reason = 'buyerEnded', acknowledged = true where id = c.id;
  select * into l from public.supply_listings where id = c.listing_id;
  fee := round(c.units_per_week * coalesce(c.unit_price, private.supply_unit_price(l)) * 2, 2);
  perform private.settle(c.supplier_id, fee, l.currency, 'supply_end_fee', c.id::text || ':end', private.display_name(uid) || ' ended the supply and paid the fee of two weeks of the order.',
    jsonb_build_object('companyKey', l.company_key, 'listingID', l.id));
end $$;

create or replace function public.end_supply_as_supplier(p_contract uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); c public.supply_contracts; l public.supply_listings; fee numeric;
begin
  select * into c from public.supply_contracts where id = p_contract and supplier_id = uid and ended_at is null for update;
  if not found then return; end if;
  update public.supply_contracts set ended_at = now(), end_reason = 'stopped' where id = c.id;
  select * into l from public.supply_listings where id = c.listing_id;
  fee := round(c.units_per_week * coalesce(c.unit_price, private.supply_unit_price(l)) * 2, 2);
  perform private.settle(uid, -fee, l.currency, 'supply_end_fee', c.id::text || ':end', 'Fee for ending a supply deal early.',
    jsonb_build_object('companyKey', l.company_key, 'listingID', l.id));
  perform private.settle(c.buyer_id, fee, l.currency, 'supply_end_fee', c.id::text || ':end', private.display_name(uid) || ' ended the supply and paid you the fee of two weeks of the order.',
    jsonb_build_object('companyKey', c.buyer_company_key, 'lineID', c.line_id));
end $$;

create or replace function public.set_supply_logo(p_company_key text, p_logo_id text) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if p_logo_id is null or char_length(p_logo_id) > 40 then raise exception 'invalid_logo' using errcode = 'P0001'; end if;
  update public.supply_listings set logo_id = p_logo_id where owner_id = uid and company_key = p_company_key;
end $$;

create or replace function private.supply_listing_json(l public.supply_listings, viewer uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = l.owner_id;
  return jsonb_build_object(
    'id', l.id, 'ownerID', l.owner_id, 'ownerName', p.display_name, 'profileCode', p.code, 'companyName', l.company_name,
    'companyKey', l.company_key, 'tradeID', l.trade_id, 'city', l.city, 'region', l.region, 'lineID', l.line_id,
    'priceTier', l.price_tier, 'qualityTier', l.quality_tier, 'capacityPerWeek', l.capacity_per_week, 'leadDays', l.lead_days,
    'minOrder', l.min_order, 'termsDays', l.terms_days, 'unitValue', l.unit_value, 'unitPrice', private.supply_unit_price(l),
    'currency', l.currency, 'logoID', l.logo_id,
    'linkKey', md5(p.link_key),
    'isFriend', private.are_friends(viewer, l.owner_id), 'paused', l.paused, 'stopped', l.stopped, 'expiresAt', l.expires_at,
    'committedUnits', private.supply_committed(l.id), 'effectiveCapacity', private.supply_effective_capacity(l),
    'availability', private.supply_availability(l, viewer, null), 'word', private.supply_word(l),
    'record', jsonb_build_object(
      'weeksTrading', l.weeks_trading, 'ordersTotal', l.orders_total, 'ordersOnTime', l.orders_on_time, 'unitsPromised', l.units_promised,
      'unitsDelivered', l.units_delivered, 'complaints', l.complaints, 'disputes', l.disputes, 'priceChanges', l.price_changes,
      'cleanWeeks', l.clean_weeks, 'deliveredTrend', l.delivered_trend, 'onTimeTrend', l.on_time_trend, 'lifetimeUnits', l.lifetime_units));
end $$;

grant execute on function public.admin_remove_fake_players(text), public.account_status(), public.end_supply_contract(text, text),
  public.end_supply_as_supplier(uuid), public.set_supply_logo(text, text), public.sign_supply_contract(text, text, uuid, int, text) to authenticated;
