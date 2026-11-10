alter table public.supply_contracts add column if not exists unit_price numeric(14, 2);

create or replace function private.supply_contract_json(c public.supply_contracts) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'buyerCompanyKey', c.buyer_company_key, 'lineID', c.line_id, 'listingID', c.listing_id,
    'supplierOwnerID', c.supplier_id, 'supplierName', c.supplier_name, 'unitsPerWeek', c.units_per_week, 'unitPrice', c.unit_price,
    'signedAt', c.signed_at, 'endedAt', c.ended_at, 'endReason', c.end_reason);
$$;

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
  return private.supply_contract_json(c);
end $$;

create or replace function public.save_supply_listing(p_listing_id uuid, p_company_key text, p_company_name text, p_trade_id text, p_city text, p_region text,
  p_line_id text, p_price_tier int, p_quality_tier int, p_capacity int, p_lead_days int, p_min_order int, p_terms_days int, p_duration_days int,
  p_unit_value numeric, p_currency text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.supply_listings; committed int; expires timestamptz; active int; med numeric; n int;
begin
  perform private.require_free(uid, 'trade');
  if not exists (select 1 from public.supply_trade_lines where trade_id = p_trade_id and line_id = p_line_id) then raise exception 'not_supplied' using errcode = 'P0001'; end if;
  if p_duration_days is not null and p_duration_days not in (1, 3, 7, 14) then raise exception 'invalid_listing' using errcode = 'P0001'; end if;
  if p_min_order > p_capacity or p_unit_value is null or p_unit_value <= 0 or p_currency is null then raise exception 'invalid_listing' using errcode = 'P0001'; end if;
  if p_unit_value > 100000 * private.currency_scale(p_currency) then raise exception 'price_outside_market' using errcode = 'P0001'; end if;
  select percentile_cont(0.5) within group (order by x.unit_value), count(*) into med, n from (
    select distinct on (s.owner_id) s.unit_value from public.supply_listings s
     where s.line_id = p_line_id and s.currency = p_currency and not s.stopped and s.owner_id <> uid and not private.linked(s.owner_id, uid)
     order by s.owner_id, s.created_at desc) x;
  if n >= 3 and (p_unit_value > med * 4 or p_unit_value < med / 4) then raise exception 'price_outside_market' using errcode = 'P0001'; end if;
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
    select count(*) into active from public.supply_contracts where listing_id = l.id and ended_at is null;
    update public.supply_listings set company_name = p_company_name, city = coalesce(p_city, ''), region = coalesce(p_region, ''),
        price_tier = p_price_tier, quality_tier = p_quality_tier, capacity_per_week = p_capacity, lead_days = p_lead_days, min_order = p_min_order,
        terms_days = p_terms_days, unit_value = p_unit_value, currency = p_currency, expires_at = expires,
        price_changes = price_changes + case when active > 0 and (p_price_tier <> price_tier or p_unit_value <> unit_value) then active else 0 end
      where id = l.id returning * into l;
  end if;
  return private.supply_listing_json(l, uid);
end $$;

create or replace function private.run_supply_week(p_week date default date_trunc('week', now())::date) returns int language plpgsql security definer set search_path = '' as $$
declare l public.supply_listings; r public.supply_reports; c public.supply_contracts; delivered int; asked int; late int; n_orders int; n_late int; n_prom int; n_del int;
        v_compl int; v_disp int; price numeric; revenue numeric; processed int := 0; pct int; late_left int; d_now numeric; o_now numeric;
        w_start timestamptz := p_week::timestamp at time zone 'UTC'; w_end timestamptz := (p_week + 7)::timestamp at time zone 'UTC';
        days numeric; supplier_seen timestamptz; cap numeric; unseen interval := interval '14 days';
begin
  for l in select * from public.supply_listings where not stopped and expires_at is not null and expires_at < now() loop
    perform private.supply_end_contracts(l.id, null, 'expired');
    update public.supply_listings set stopped = true where id = l.id;
  end loop;
  update public.supply_contracts k set ended_at = now(), end_reason = 'expired'
   where k.ended_at is null and exists (
     select 1 from public.profiles p where not p.is_bot and p.id in (k.buyer_id, k.supplier_id) and coalesce(p.last_seen_at, p.created_at) < now() - unseen);
  for l in select * from public.supply_listings sl where exists (
             select 1 from public.supply_contracts k where k.listing_id = sl.id and k.signed_at < w_end and (k.ended_at is null or k.ended_at > w_start)) loop
    select * into r from public.supply_reports where listing_id = l.id and week = p_week;
    select coalesce(last_seen_at, created_at) into supplier_seen from public.profiles where id = l.owner_id;
    pct := coalesce(r.delivered_pct, case when supplier_seen >= w_start then 100 else 70 end);
    late_left := coalesce(r.late_orders, 0);
    cap := 2000000 * private.currency_scale(l.currency);
    n_orders := 0; n_late := 0; n_prom := 0; n_del := 0; v_compl := 0; v_disp := 0;
    for c in select * from public.supply_contracts k where k.listing_id = l.id and k.signed_at < w_end and (k.ended_at is null or k.ended_at > w_start) order by k.signed_at loop
      continue when exists (select 1 from public.supply_orders o where o.contract_id = c.id and o.week = p_week);
      days := least(7, ceil(extract(epoch from least(coalesce(c.ended_at, w_end), w_end) - greatest(c.signed_at, w_start)) / 86400));
      continue when days <= 0;
      asked := ceil(c.units_per_week * days / 7)::int;
      price := coalesce(c.unit_price, private.supply_unit_price(l));
      delivered := least((asked * pct) / 100, floor(cap / price)::int);
      late := case when late_left > 0 then 1 else 0 end;
      late_left := greatest(0, late_left - 1);
      revenue := delivered * price;
      insert into public.supply_orders (contract_id, listing_id, week, units_asked, units_delivered, late, unit_price, revenue)
        values (c.id, l.id, p_week, asked, delivered, late = 1, price, revenue);
      if revenue > 0 then
        perform private.settle(l.owner_id, revenue, l.currency, 'supply_sale', c.id::text || ':' || p_week, 'Sold to other players',
          jsonb_build_object('companyKey', l.company_key, 'listingID', l.id, 'units', delivered, 'unitPrice', price, 'week', p_week));
        perform private.settle(c.buyer_id, -revenue, l.currency, 'supply_purchase', c.id::text || ':' || p_week, 'Bought from ' || c.supplier_name,
          jsonb_build_object('companyKey', c.buyer_company_key, 'lineID', c.line_id, 'units', delivered, 'unitPrice', price, 'week', p_week));
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

create or replace function public.pending_settlements() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'amount', s.amount, 'currency', s.currency, 'kind', s.kind, 'ref', s.ref,
           'label', s.label, 'meta', s.meta, 'createdAt', s.created_at) order by s.created_at, s.id)
      from (select * from public.settlements where recipient_id = uid and claimed_at is null order by created_at, id limit 200) s), '[]'::jsonb);
end $$;

create or replace function public.ack_settlements(p_ids uuid[]) returns int language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); n int;
begin
  update public.settlements set claimed_at = now() where recipient_id = uid and claimed_at is null and id = any (coalesce(p_ids, '{}'));
  get diagnostics n = row_count;
  return n;
end $$;

drop function if exists public.claim_settlements();

create or replace function public.share_progress(p_level int default null, p_badges text[] default null, p_game_week int default null,
                                                 p_trades_completed int default null, p_companies jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); c jsonb; b text; cur public.profiles; behind boolean;
begin
  select * into cur from public.profiles where id = uid and deleted_at is null for update;
  if not found then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if p_level is not null and p_level not between 0 and 1000 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
  if p_game_week is not null and p_game_week < 0 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
  if p_trades_completed is not null and p_trades_completed < 0 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
  if p_badges is not null then
    if cardinality(p_badges) > 64 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
    foreach b in array p_badges loop
      if b is null or char_length(b) not between 1 and 40 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
    end loop;
  end if;
  if p_companies is not null then
    if jsonb_typeof(p_companies) <> 'array' or jsonb_array_length(p_companies) > 50 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
    for c in select * from jsonb_array_elements(p_companies) loop
      if coalesce(c->>'id', '') = '' or coalesce(c->>'name', '') = ''
         or not ((c->>'health') = any (enum_range(null::public.company_health)::text[])) then
        raise exception 'invalid_progress' using errcode = 'P0001';
      end if;
    end loop;
  end if;
  behind := p_game_week is not null and p_game_week < cur.game_week;
  update public.profiles set
      level = greatest(level, coalesce(p_level, level)),
      badges = case when p_badges is null then badges else array(select distinct x from unnest(badges || p_badges) x order by x limit 64) end,
      game_week = greatest(game_week, coalesce(p_game_week, game_week)),
      trades_completed = greatest(trades_completed, coalesce(p_trades_completed, trades_completed))
   where id = uid;
  if p_companies is not null and not behind then
    delete from public.companies_public where owner_id = uid;
    insert into public.companies_public (owner_id, company_key, name, trade, city, country, health)
      select uid, e->>'id', e->>'name', coalesce(e->>'trade', ''), coalesce(e->>'city', ''), coalesce(e->>'countryCode', 'US'),
             (e->>'health')::public.company_health
        from jsonb_array_elements(p_companies) e;
  end if;
  return private.profile_json(uid, uid);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.pending_settlements(), public.ack_settlements(uuid[]) to authenticated;
