-- Supply market between players: listings, contracts, weekly orders and the delivery record buyers read.
-- Rules mirror the engine's SupplyMarketRules / SupplyGuards / SupplyRecordRules. A supplier names what it offers, never what a sale is
-- worth: the unit price is always base value x the tier factor, and money moves only in the weekly run as settlements (see 0002).
-- The market clock is real time: a market week starts on Monday (UTC).

-- What each trade may supply (the engine's fixed catalogue). A trade not listed supplies nothing to other players.
create table public.supply_trade_lines (
  trade_id text not null,
  line_id text not null,
  primary key (trade_id, line_id)
);
insert into public.supply_trade_lines (trade_id, line_id) values
  ('bakery','goods'),('bakery','pack'),('brewery','goods'),('brewery','pack'),('farm','goods'),('vineyard','goods'),('salmon','goods'),
  ('factory','goods'),('factory','mat'),('factory','pack'),('factory','parts'),('furniture','goods'),('furniture','mat'),('grocery','goods'),
  ('hardware','supplies'),('hardware','parts'),('hardware','pack'),('cleaning','clean'),('cleaning','laundry'),('carclean','clean'),
  ('webdev','software'),('gamestudio','software'),('startup','software'),('carrepair','parts'),('carrepair','repair'),
  ('handy','repair'),('handy','parts'),('electrician','repair'),('electrician','parts'),('plumber','repair'),('plumber','parts'),
  ('power','power'),('oilgas','fuel'),('oilgas','power'),('courier','fuel');

create type public.supply_end as enum ('bankrupt', 'accountDeleted', 'stopped', 'expired', 'replaced', 'buyerEnded');

create table public.supply_listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  company_key text not null check (char_length(company_key) between 1 and 64),
  company_name text not null check (char_length(company_name) between 1 and 40),
  trade_id text not null,
  city text not null default '' check (char_length(city) <= 60),
  region text not null default '' check (char_length(region) <= 60),
  line_id text not null,
  price_tier int not null default 1 check (price_tier between 0 and 2),
  quality_tier int not null default 1 check (quality_tier between 0 and 2),
  capacity_per_week int not null check (capacity_per_week between 1 and 1000000),
  lead_days int not null default 3 check (lead_days between 0 and 30),
  min_order int not null default 1 check (min_order >= 1),
  terms_days int not null default 14 check (terms_days in (0, 14, 30)),
  -- What one unit is worth at the company's own prices; the price tier moves it. Currency of the supplier's game.
  unit_value numeric(14, 2) not null check (unit_value between 0.01 and 10000000),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  paused boolean not null default false,
  stopped boolean not null default false,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  -- The delivery record (SupplyRecordRules.applying keeps these current; only the weekly run writes them).
  weeks_trading int not null default 0,
  orders_total int not null default 0,
  orders_on_time int not null default 0,
  units_promised bigint not null default 0,
  units_delivered bigint not null default 0,
  complaints int not null default 0,
  disputes int not null default 0,
  price_changes int not null default 0,
  clean_weeks int not null default 0,
  delivered_trend numeric,
  on_time_trend numeric,
  lifetime_units bigint not null default 0,
  constraint listing_min_within_capacity check (min_order <= capacity_per_week),
  constraint listing_line_supplied foreign key (trade_id, line_id) references public.supply_trade_lines (trade_id, line_id)
);
create unique index supply_listing_live on public.supply_listings (owner_id, company_key, line_id) where not stopped;
create index supply_listing_line on public.supply_listings (line_id) where not stopped;

create table public.supply_contracts (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  buyer_company_key text not null check (char_length(buyer_company_key) between 1 and 64),
  line_id text not null,
  listing_id uuid not null references public.supply_listings (id) on delete cascade,
  supplier_id uuid not null references public.profiles (id) on delete cascade,
  supplier_name text not null,
  units_per_week int not null check (units_per_week between 1 and 1000000),
  signed_at timestamptz not null default now(),
  ended_at timestamptz,
  end_reason public.supply_end,
  -- The buyer has been told about an end it did not choose (the fall back to the House supplier).
  acknowledged boolean not null default false,
  constraint contract_end_pair check ((ended_at is null) = (end_reason is null))
);
create unique index supply_contract_active on public.supply_contracts (buyer_id, buyer_company_key, line_id) where ended_at is null;
create index supply_contract_listing on public.supply_contracts (listing_id) where ended_at is null;
create index supply_contract_supplier on public.supply_contracts (supplier_id) where ended_at is null;

-- What the supplier reports about a week (share of the promised units it really delivered, orders it sent late).
create table public.supply_reports (
  listing_id uuid not null references public.supply_listings (id) on delete cascade,
  week date not null,
  delivered_pct int not null check (delivered_pct between 0 and 100),
  late_orders int not null default 0 check (late_orders >= 0),
  primary key (listing_id, week)
);

-- A buyer's complaint or dispute about a week's delivery; one per contract and week.
create table public.supply_complaints (
  contract_id uuid not null references public.supply_contracts (id) on delete cascade,
  week date not null,
  is_dispute boolean not null default false,
  primary key (contract_id, week)
);

create table public.supply_orders (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.supply_contracts (id) on delete cascade,
  listing_id uuid not null references public.supply_listings (id) on delete cascade,
  week date not null,
  units_asked int not null,
  units_delivered int not null check (units_delivered between 0 and units_asked),
  late boolean not null default false,
  unit_price numeric(14, 2) not null,
  revenue numeric(18, 2) not null,
  created_at timestamptz not null default now(),
  unique (contract_id, week)
);
create index supply_orders_listing on public.supply_orders (listing_id, week desc);

alter table public.supply_trade_lines enable row level security;
alter table public.supply_listings enable row level security;
alter table public.supply_contracts enable row level security;
alter table public.supply_reports enable row level security;
alter table public.supply_complaints enable row level security;
alter table public.supply_orders enable row level security;

revoke all on public.supply_trade_lines, public.supply_listings, public.supply_contracts, public.supply_reports, public.supply_complaints, public.supply_orders from anon, authenticated;
grant select on public.supply_trade_lines, public.supply_listings, public.supply_contracts, public.supply_orders, public.supply_reports, public.supply_complaints to authenticated;

create policy supply_lines_read on public.supply_trade_lines for select to authenticated using (true);
-- Everyone else reads listings through the functions below, which hide linked, blocked and stopped rows as needed.
create policy supply_listings_own on public.supply_listings for select to authenticated using (owner_id = auth.uid());
create policy supply_contracts_party on public.supply_contracts for select to authenticated using (buyer_id = auth.uid() or supplier_id = auth.uid());
create policy supply_orders_party on public.supply_orders for select to authenticated
  using (exists (select 1 from public.supply_contracts c where c.id = contract_id and (c.buyer_id = auth.uid() or c.supplier_id = auth.uid())));
create policy supply_reports_own on public.supply_reports for select to authenticated
  using (exists (select 1 from public.supply_listings l where l.id = listing_id and l.owner_id = auth.uid()));
create policy supply_complaints_buyer on public.supply_complaints for select to authenticated
  using (exists (select 1 from public.supply_contracts c where c.id = contract_id and c.buyer_id = auth.uid()));

-- ---------------------------------------------------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------------------------------------------------
create function private.supply_tier_factor(tier int) returns numeric language sql immutable as $$
  select (array[0.90, 1.00, 1.14])[least(2, greatest(0, tier)) + 1]::numeric;
$$;
create function private.supply_unit_price(l public.supply_listings) returns numeric language sql immutable as $$
  select round(l.unit_value * private.supply_tier_factor(l.price_tier), 2);
$$;

-- The weekly units a new supplier may take; null once its record is clean enough to lift the limit.
create function private.supply_new_cap(clean_weeks int, disputes int) returns int language sql immutable as $$
  select case when clean_weeks >= 10 and disputes = 0 then null else 20 + 12 * clean_weeks end;
$$;
create function private.supply_effective_capacity(l public.supply_listings) returns int language sql immutable as $$
  select least(l.capacity_per_week, coalesce(private.supply_new_cap(l.clean_weeks, l.disputes), l.capacity_per_week));
$$;
create function private.supply_committed(listing uuid) returns int language sql stable security definer set search_path = '' as $$
  select coalesce(sum(units_per_week), 0)::int from public.supply_contracts where listing_id = listing and ended_at is null;
$$;

-- Under four weeks or five orders there is too little to judge; otherwise 0.5 delivered + 0.3 on time + 0.2 clean sheet.
create function private.supply_unproven(l public.supply_listings) returns boolean language sql immutable as $$
  select l.weeks_trading < 4 or l.orders_total < 5;
$$;
create function private.supply_score(l public.supply_listings) returns numeric language sql immutable as $$
  select 0.5 * (case when l.units_promised > 0 then l.units_delivered::numeric / l.units_promised else 1 end)
       + 0.3 * (case when l.orders_total > 0 then l.orders_on_time::numeric / l.orders_total else 1 end)
       + 0.2 * (1 - least(1, (l.complaints + 3 * l.disputes + 2 * l.price_changes)::numeric / greatest(10, l.orders_total)));
$$;
create function private.supply_word(l public.supply_listings) returns text language sql immutable as $$
  select case when private.supply_unproven(l) then 'Unproven'
              when private.supply_score(l) >= 0.93 then 'Reliable'
              when private.supply_score(l) >= 0.82 then 'Mostly reliable'
              else 'Struggling' end;
$$;

-- Why the buyer cannot use a listing; 'available' when it can. Same order of checks as SupplyGuards.availability.
create function private.supply_availability(l public.supply_listings, buyer uuid, units int) returns text language plpgsql stable security definer set search_path = '' as $$
begin
  if private.linked(buyer, l.owner_id) then return 'linkedAccount'; end if;
  if l.stopped then return 'stopped'; end if;
  if l.paused then return 'paused'; end if;
  if l.expires_at is not null and now() > l.expires_at then return 'offerEnded'; end if;
  if private.supply_effective_capacity(l) - private.supply_committed(l.id) < greatest(1, l.min_order) then return 'full'; end if;
  if units is not null and units < l.min_order then return 'belowMinimum'; end if;
  return 'available';
end $$;

create function private.supply_listing_json(l public.supply_listings, viewer uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = l.owner_id;
  return jsonb_build_object(
    'id', l.id, 'ownerID', l.owner_id, 'ownerName', p.display_name, 'profileCode', p.code, 'companyName', l.company_name,
    'companyKey', l.company_key, 'tradeID', l.trade_id, 'city', l.city, 'region', l.region, 'lineID', l.line_id,
    'priceTier', l.price_tier, 'qualityTier', l.quality_tier, 'capacityPerWeek', l.capacity_per_week, 'leadDays', l.lead_days,
    'minOrder', l.min_order, 'termsDays', l.terms_days, 'unitValue', l.unit_value, 'unitPrice', private.supply_unit_price(l),
    'currency', l.currency,
    -- Opaque, but equal for linked accounts, so the app can grey out its own accounts without learning the key.
    'linkKey', md5(p.link_key),
    'isFriend', private.are_friends(viewer, l.owner_id), 'paused', l.paused, 'stopped', l.stopped, 'expiresAt', l.expires_at,
    'committedUnits', private.supply_committed(l.id), 'effectiveCapacity', private.supply_effective_capacity(l),
    'availability', private.supply_availability(l, viewer, null), 'word', private.supply_word(l),
    'record', jsonb_build_object(
      'weeksTrading', l.weeks_trading, 'ordersTotal', l.orders_total, 'ordersOnTime', l.orders_on_time, 'unitsPromised', l.units_promised,
      'unitsDelivered', l.units_delivered, 'complaints', l.complaints, 'disputes', l.disputes, 'priceChanges', l.price_changes,
      'cleanWeeks', l.clean_weeks, 'deliveredTrend', l.delivered_trend, 'onTimeTrend', l.on_time_trend, 'lifetimeUnits', l.lifetime_units));
end $$;

-- Ends contracts on a listing (or all of a supplier's listings) at once; the buyers fall back to the House supplier.
create function private.supply_end_contracts(p_listing uuid, p_supplier uuid, p_reason public.supply_end) returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.supply_contracts set ended_at = now(), end_reason = p_reason
   where ended_at is null and ((p_listing is not null and listing_id = p_listing) or (p_supplier is not null and supplier_id = p_supplier));
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function private.supply_open(uid uuid) returns boolean language sql stable as $$
  select exists (select 1 from public.supply_contracts where supplier_id = uid and ended_at is null);
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Supplier functions
-- ---------------------------------------------------------------------------------------------------------------------
create function public.save_supply_listing(p_listing_id uuid, p_company_key text, p_company_name text, p_trade_id text, p_city text, p_region text,
  p_line_id text, p_price_tier int, p_quality_tier int, p_capacity int, p_lead_days int, p_min_order int, p_terms_days int, p_duration_days int,
  p_unit_value numeric, p_currency text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.supply_listings; committed int; expires timestamptz; active int;
begin
  perform private.require_free(uid, 'trade');
  if not exists (select 1 from public.supply_trade_lines where trade_id = p_trade_id and line_id = p_line_id) then raise exception 'not_supplied' using errcode = 'P0001'; end if;
  if p_duration_days is not null and p_duration_days not in (1, 3, 7, 14) then raise exception 'invalid_listing' using errcode = 'P0001'; end if;
  if p_min_order > p_capacity or p_unit_value is null or p_unit_value <= 0 then raise exception 'invalid_listing' using errcode = 'P0001'; end if;
  expires := case when p_duration_days is null then null else now() + make_interval(days => p_duration_days) end;
  if p_listing_id is null then
    insert into public.supply_listings (owner_id, company_key, company_name, trade_id, city, region, line_id, price_tier, quality_tier, capacity_per_week,
        lead_days, min_order, terms_days, unit_value, currency, expires_at)
      values (uid, p_company_key, p_company_name, p_trade_id, coalesce(p_city, ''), coalesce(p_region, ''), p_line_id, p_price_tier, p_quality_tier, p_capacity,
        p_lead_days, p_min_order, p_terms_days, p_unit_value, p_currency, expires)
      returning * into l;
  else
    select * into l from public.supply_listings where id = p_listing_id and owner_id = uid and not stopped for update;
    if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
    committed := private.supply_committed(l.id);
    if p_capacity < committed then raise exception 'capacity_below_commitments' using errcode = 'P0001'; end if;
    if p_line_id <> l.line_id or p_trade_id <> l.trade_id or p_company_key <> l.company_key then raise exception 'invalid_listing' using errcode = 'P0001'; end if;
    -- A price change after signing counts against the record once per buyer under contract.
    select count(*) into active from public.supply_contracts where listing_id = l.id and ended_at is null;
    update public.supply_listings set company_name = p_company_name, city = coalesce(p_city, ''), region = coalesce(p_region, ''),
        price_tier = p_price_tier, quality_tier = p_quality_tier, capacity_per_week = p_capacity, lead_days = p_lead_days, min_order = p_min_order,
        terms_days = p_terms_days, unit_value = p_unit_value, currency = p_currency, expires_at = expires,
        price_changes = price_changes + case when active > 0 and (p_price_tier <> price_tier or p_unit_value <> unit_value) then active else 0 end
      where id = l.id returning * into l;
  end if;
  return private.supply_listing_json(l, uid);
end $$;

create function public.set_supply_listing_paused(p_listing uuid, p_paused boolean) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  update public.supply_listings set paused = p_paused where id = p_listing and owner_id = uid and not stopped;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
end $$;

-- Stops a listing for good: its contracts end at once.
create function public.stop_supply_listing(p_listing uuid) returns int language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  update public.supply_listings set stopped = true where id = p_listing and owner_id = uid and not stopped;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  return private.supply_end_contracts(p_listing, null, 'stopped');
end $$;

-- A company went bankrupt (or was closed): every listing of it stops and its contracts end as bankrupt.
create function public.supplier_company_closed(p_company_key text) returns int language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); n int := 0; l uuid;
begin
  for l in select id from public.supply_listings where owner_id = uid and company_key = p_company_key and not stopped loop
    update public.supply_listings set stopped = true where id = l;
    n := n + private.supply_end_contracts(l, null, 'bankrupt');
  end loop;
  return n;
end $$;

create function public.my_supply_listings(p_company_key text default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(private.supply_listing_json(l, uid) order by l.created_at)
                     from public.supply_listings l where l.owner_id = uid and not l.stopped and (p_company_key is null or l.company_key = p_company_key)), '[]'::jsonb);
end $$;

create function public.supply_listing_orders(p_listing uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if not exists (select 1 from public.supply_listings where id = p_listing and owner_id = uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'listingID', o.listing_id, 'buyerName', private.display_name(c.buyer_id), 'units', o.units_asked,
            'delivered', o.units_delivered, 'late', o.late, 'week', o.week, 'revenue', o.revenue) order by o.week desc)
     from public.supply_orders o join public.supply_contracts c on c.id = o.contract_id where o.listing_id = p_listing), '[]'::jsonb);
end $$;

-- The supplier says how a week went. Only values the rules allow are stored; the weekly run reads them.
create function public.report_supply_week(p_listing uuid, p_delivered_pct int, p_late_orders int default 0) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); wk date := date_trunc('week', now())::date;
begin
  if not exists (select 1 from public.supply_listings where id = p_listing and owner_id = uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_delivered_pct not between 0 and 100 or p_late_orders < 0 then raise exception 'invalid_report' using errcode = 'P0001'; end if;
  insert into public.supply_reports (listing_id, week, delivered_pct, late_orders) values (p_listing, wk, p_delivered_pct, p_late_orders)
    on conflict (listing_id, week) do update set delivered_pct = excluded.delivered_pct, late_orders = excluded.late_orders;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Buyer functions
-- ---------------------------------------------------------------------------------------------------------------------
-- Listings for a line the caller may see: never blocked either way, never stopped. Unusable ones stay listed with their reason.
create function public.supply_listings_for_line(p_line_id text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(private.supply_listing_json(l, uid) order by l.lifetime_units desc, l.id)
     from public.supply_listings l
    where l.line_id = p_line_id and not l.stopped and not private.is_blocked_between(uid, l.owner_id)), '[]'::jsonb);
end $$;

create function public.supplier_profile(p_owner uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); p public.profiles;
begin
  if private.is_blocked_between(uid, p_owner) then raise exception 'not_found' using errcode = 'P0001'; end if;
  select * into p from public.profiles where id = p_owner and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  return jsonb_build_object('ownerID', p.id, 'ownerName', p.display_name, 'profileCode', p.code, 'isFriend', private.are_friends(uid, p.id),
    'listings', coalesce((select jsonb_agg(private.supply_listing_json(l, uid) order by l.created_at) from public.supply_listings l where l.owner_id = p.id and not l.stopped), '[]'::jsonb));
end $$;

create function private.supply_contract_json(c public.supply_contracts) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'buyerCompanyKey', c.buyer_company_key, 'lineID', c.line_id, 'listingID', c.listing_id,
    'supplierOwnerID', c.supplier_id, 'supplierName', c.supplier_name, 'unitsPerWeek', c.units_per_week, 'signedAt', c.signed_at,
    'endedAt', c.ended_at, 'endReason', c.end_reason);
$$;

-- Signs (or replaces) the caller's contract for one line of one company. Every guard is checked here, whatever the app showed.
create function public.sign_supply_contract(p_company_key text, p_line_id text, p_listing uuid, p_units int, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.supply_listings; why text; c public.supply_contracts;
begin
  perform private.require_free(uid, 'trade');
  if p_units is null or p_units < 1 then raise exception 'invalid_units' using errcode = 'P0001'; end if;
  select * into l from public.supply_listings where id = p_listing for update;
  if not found or l.line_id <> p_line_id or private.is_blocked_between(uid, l.owner_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if l.currency <> p_currency then raise exception 'currency_mismatch' using errcode = 'P0001'; end if;
  -- An existing contract for this line does not count against the new one's room.
  update public.supply_contracts set ended_at = now(), end_reason = 'replaced' where buyer_id = uid and buyer_company_key = p_company_key and line_id = p_line_id and ended_at is null;
  why := private.supply_availability(l, uid, p_units);
  if why <> 'available' then raise exception 'listing_%', why using errcode = 'P0001'; end if;
  if private.supply_committed(l.id) + p_units > private.supply_effective_capacity(l) then raise exception 'listing_full' using errcode = 'P0001'; end if;
  insert into public.supply_contracts (buyer_id, buyer_company_key, line_id, listing_id, supplier_id, supplier_name, units_per_week)
    values (uid, p_company_key, p_line_id, l.id, l.owner_id, private.display_name(l.owner_id), p_units) returning * into c;
  return private.supply_contract_json(c);
end $$;

create function public.end_supply_contract(p_company_key text, p_line_id text) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  update public.supply_contracts set ended_at = now(), end_reason = 'buyerEnded', acknowledged = true
   where buyer_id = uid and buyer_company_key = p_company_key and line_id = p_line_id and ended_at is null;
end $$;

-- Active contracts, plus those the supplier ended that the buyer has not been told about (shown once, then acknowledged).
create function public.my_supply_contracts() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); res jsonb;
begin
  res := jsonb_build_object(
    'active', coalesce((select jsonb_agg(private.supply_contract_json(c)) from public.supply_contracts c where c.buyer_id = uid and c.ended_at is null), '[]'::jsonb),
    'fallbacks', coalesce((select jsonb_agg(private.supply_contract_json(c)) from public.supply_contracts c
                            where c.buyer_id = uid and c.ended_at is not null and not c.acknowledged), '[]'::jsonb),
    'asSupplier', (select count(*) from public.supply_contracts c where c.supplier_id = uid and c.ended_at is null));
  update public.supply_contracts set acknowledged = true where buyer_id = uid and ended_at is not null and not acknowledged;
  return res;
end $$;

create function public.complain_about_supplier(p_company_key text, p_line_id text, p_dispute boolean default false) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); cid uuid;
begin
  select id into cid from public.supply_contracts where buyer_id = uid and buyer_company_key = p_company_key and line_id = p_line_id and ended_at is null;
  if cid is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  insert into public.supply_complaints (contract_id, week, is_dispute) values (cid, date_trunc('week', now())::date, coalesce(p_dispute, false))
    on conflict (contract_id, week) do update set is_dispute = public.supply_complaints.is_dispute or excluded.is_dispute;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- The weekly run (scheduled by the platform with the service role; not callable by clients).
-- ---------------------------------------------------------------------------------------------------------------------
create function private.run_supply_week(p_week date default date_trunc('week', now())::date) returns int language plpgsql security definer set search_path = '' as $$
declare l public.supply_listings; r public.supply_reports; c public.supply_contracts; delivered int; asked int; late int; n_orders int; n_late int; n_prom int; n_del int;
        v_compl int; v_disp int; price numeric; revenue numeric; processed int := 0; pct int; late_left int; d_now numeric; o_now numeric;
begin
  -- Offers that ran out end their contracts first.
  for l in select * from public.supply_listings where not stopped and expires_at is not null and expires_at < now() loop
    perform private.supply_end_contracts(l.id, null, 'expired');
    update public.supply_listings set stopped = true where id = l.id;
  end loop;
  for l in select * from public.supply_listings sl where not sl.stopped and exists (select 1 from public.supply_contracts k where k.listing_id = sl.id and k.ended_at is null) loop
    select * into r from public.supply_reports where listing_id = l.id and week = p_week;
    pct := coalesce(r.delivered_pct, 100);
    late_left := coalesce(r.late_orders, 0);
    price := private.supply_unit_price(l);
    n_orders := 0; n_late := 0; n_prom := 0; n_del := 0; v_compl := 0; v_disp := 0;
    for c in select * from public.supply_contracts k where k.listing_id = l.id and k.ended_at is null order by k.signed_at loop
      continue when exists (select 1 from public.supply_orders o where o.contract_id = c.id and o.week = p_week);
      asked := c.units_per_week;
      delivered := (asked * pct) / 100;
      late := case when late_left > 0 then 1 else 0 end;
      late_left := greatest(0, late_left - 1);
      revenue := delivered * price;
      insert into public.supply_orders (contract_id, listing_id, week, units_asked, units_delivered, late, unit_price, revenue)
        values (c.id, l.id, p_week, asked, delivered, late = 1, price, revenue);
      if revenue > 0 then
        perform private.settle(l.owner_id, revenue, l.currency, 'supply_sale', c.id::text, 'Sold to other players',
          jsonb_build_object('companyKey', l.company_key, 'listingID', l.id, 'units', delivered, 'unitPrice', price));
        perform private.settle(c.buyer_id, -revenue, l.currency, 'supply_purchase', c.id::text, 'Bought from ' || c.supplier_name,
          jsonb_build_object('companyKey', c.buyer_company_key, 'lineID', c.line_id, 'units', delivered, 'unitPrice', price));
      end if;
      n_orders := n_orders + 1; n_late := n_late + late; n_prom := n_prom + asked; n_del := n_del + delivered;
      v_compl := v_compl + coalesce((select count(*) from public.supply_complaints q where q.contract_id = c.id and q.week = p_week and not q.is_dispute), 0);
      v_disp := v_disp + coalesce((select count(*) from public.supply_complaints q where q.contract_id = c.id and q.week = p_week and q.is_dispute), 0);
    end loop;
    continue when n_orders = 0;
    d_now := case when n_prom > 0 then n_del::numeric / n_prom else 1 end;
    o_now := (n_orders - n_late)::numeric / n_orders;
    update public.supply_listings set
        weeks_trading = weeks_trading + 1, orders_total = orders_total + n_orders, orders_on_time = orders_on_time + (n_orders - n_late),
        units_promised = units_promised + n_prom, units_delivered = units_delivered + n_del, lifetime_units = lifetime_units + n_del,
        complaints = complaints + v_compl, disputes = disputes + v_disp,
        clean_weeks = case when n_late = 0 and v_compl = 0 and v_disp = 0 and n_del >= n_prom then clean_weeks + 1 else 0 end,
        delivered_trend = (d_now - case when units_promised > 0 then units_delivered::numeric / units_promised else 1 end) * 100,
        on_time_trend = (o_now - case when orders_total > 0 then orders_on_time::numeric / orders_total else 1 end) * 100
      where id = l.id;
    processed := processed + 1;
  end loop;
  return processed;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.save_supply_listing(uuid, text, text, text, text, text, text, int, int, int, int, int, int, int, numeric, text),
  public.set_supply_listing_paused(uuid, boolean), public.stop_supply_listing(uuid), public.supplier_company_closed(text),
  public.my_supply_listings(text), public.supply_listing_orders(uuid), public.report_supply_week(uuid, int, int),
  public.supply_listings_for_line(text), public.supplier_profile(uuid), public.sign_supply_contract(text, text, uuid, int, text),
  public.end_supply_contract(text, text), public.my_supply_contracts(), public.complain_about_supplier(text, text, boolean) to authenticated;
