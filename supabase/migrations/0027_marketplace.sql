create table public.market_listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('car', 'van', 'plane', 'boat', 'equipment', 'luxury')),
  title text not null check (char_length(title) between 2 and 80),
  item jsonb not null check (jsonb_typeof(item) = 'object' and pg_column_size(item) <= 4000 and char_length(coalesce(item ->> 'id', '')) between 1 and 64),
  price numeric(18, 2) not null check (price > 0 and price <= 1000000000000),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'active' check (status in ('active', 'sold', 'cancelled', 'expired')),
  buyer_id uuid references public.profiles (id) on delete set null,
  sold_price numeric(18, 2),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  expires_at timestamptz not null default now() + interval '21 days'
);
create index market_listings_active on public.market_listings (kind, created_at desc) where status = 'active';
create index market_listings_seller on public.market_listings (seller_id, status);
create unique index market_listings_one_item on public.market_listings (seller_id, (item ->> 'id')) where status = 'active';

create table public.market_offers (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.market_listings (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('buy', 'offer')),
  price numeric(18, 2) not null check (price > 0),
  special_price numeric(18, 2) check (special_price is null or special_price > 0),
  final_price numeric(18, 2),
  status text not null default 'pending' check (status in ('pending', 'discussing', 'accepted', 'declined', 'withdrawn', 'expired', 'closed')),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  closed_at timestamptz
);
create unique index market_offers_one_open on public.market_offers (listing_id, buyer_id) where status in ('pending', 'discussing');
create unique index market_offers_one_counter on public.market_offers (listing_id, buyer_id) where kind = 'offer';
create index market_offers_seller on public.market_offers (seller_id, status);
create index market_offers_buyer on public.market_offers (buyer_id, status);
create index market_offers_open on public.market_offers (created_at) where status in ('pending', 'discussing');

alter table public.market_listings enable row level security;
alter table public.market_offers enable row level security;
revoke all on public.market_listings, public.market_offers from anon, authenticated;
grant select on public.market_listings, public.market_offers to authenticated;
create policy market_listings_visible on public.market_listings for select to authenticated
  using (seller_id = auth.uid() or buyer_id = auth.uid() or status = 'active');
create policy market_offers_parties on public.market_offers for select to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid());

insert into public.job_runs (name, every) values ('market', interval '5 minutes') on conflict (name) do nothing;

create function private.market_fx(cur text) returns numeric language sql immutable as $$
  select case cur when 'NOK' then 1 when 'SEK' then 1.0190476 when 'DKK' then 1.562 when 'EUR' then 11.6304348 when 'GBP' then 13.5443038
    when 'USD' then 10.7 when 'CAD' then 7.6428571 when 'AUD' then 7.1333333 when 'JPY' then 0.0713333 when 'BRL' then 1.8448276
    when 'PLN' then 2.675 when 'INR' then 0.1289 when 'ZAR' then 0.5784 else 1 end::numeric;
$$;

create function private.market_currency(cc text) returns text language sql immutable as $$
  select case cc when 'NO' then 'NOK' when 'SE' then 'SEK' when 'DK' then 'DKK' when 'UK' then 'GBP' when 'US' then 'USD' when 'CA' then 'CAD'
    when 'AU' then 'AUD' when 'JP' then 'JPY' when 'BR' then 'BRL' when 'PL' then 'PLN' when 'IN' then 'INR' when 'ZA' then 'ZAR' else 'EUR' end;
$$;

create function private.market_money(v numeric, cur text) returns text language sql immutable as $$
  select trim(to_char(round(v), 'FM999G999G999G999G990')) || ' ' || cur;
$$;

create function private.market_notice(uid uuid, ref text, title text, label text, tone text, cur text, meta jsonb default '{}'::jsonb) returns void
language sql security definer set search_path = '' as $$
  select private.settle(uid, 0, cur, 'market_notice', ref, label, coalesce(meta, '{}'::jsonb) || jsonb_build_object('title', title, 'tone', tone));
$$;

create function private.market_refund(o public.market_offers, why text, ref_tag text) returns void
language plpgsql security definer set search_path = '' as $$
declare l public.market_listings;
begin
  select * into l from public.market_listings where id = o.listing_id;
  perform private.settle(o.buyer_id, 0, l.currency, 'market_refund', o.id::text || ':' || ref_tag, why,
    jsonb_build_object('dealID', o.id, 'listingID', l.id, 'title', 'Deal closed', 'tone', 'n'));
end $$;

create function private.market_unlist_note(l public.market_listings, why text, ref_tag text) returns void
language sql security definer set search_path = '' as $$
  select private.settle(l.seller_id, 0, l.currency, 'market_unlist', l.id::text || ':' || ref_tag, why,
    jsonb_build_object('listingID', l.id, 'itemID', l.item ->> 'id', 'title', 'Listing closed', 'tone', 'n'));
$$;

create function private.market_close_open(l public.market_listings, why text, ref_tag text) returns void
language plpgsql security definer set search_path = '' as $$
declare o public.market_offers;
begin
  for o in select * from public.market_offers where listing_id = l.id and status in ('pending', 'discussing') for update loop
    update public.market_offers set status = 'closed', closed_at = now() where id = o.id;
    perform private.market_refund(o, why, ref_tag);
  end loop;
end $$;

create function private.market_deal_json(o public.market_offers, viewer uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare l public.market_listings; other uuid; p public.profiles;
begin
  select * into l from public.market_listings where id = o.listing_id;
  other := case when viewer = o.buyer_id then o.seller_id else o.buyer_id end;
  select * into p from public.profiles where id = other;
  return jsonb_build_object(
    'id', o.id, 'listingID', o.listing_id, 'role', case when viewer = o.buyer_id then 'buyer' else 'seller' end,
    'kind', o.kind, 'price', o.price, 'specialPrice', o.special_price, 'finalPrice', o.final_price, 'status', o.status,
    'title', l.title, 'itemKind', l.kind, 'family', l.item ->> 'family', 'currency', l.currency, 'listingPrice', l.price, 'listingStatus', l.status,
    'otherID', other, 'otherName', coalesce(p.display_name, 'Player'), 'otherCode', p.code,
    'otherOnline', coalesce(p.last_seen_at > now() - interval '5 minutes', false),
    'createdAt', extract(epoch from o.created_at),
    'answeredAt', case when o.answered_at is null then null else to_jsonb(extract(epoch from o.answered_at)) end);
end $$;

create function private.market_listing_json(l public.market_listings, viewer uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare p public.profiles; mine public.market_offers;
begin
  select * into p from public.profiles where id = l.seller_id;
  select * into mine from public.market_offers where listing_id = l.id and buyer_id = viewer order by created_at desc limit 1;
  return jsonb_build_object(
    'id', l.id, 'sellerID', l.seller_id, 'sellerName', coalesce(p.display_name, 'Player'), 'sellerCode', p.code,
    'avatarColour', p.avatar_colour, 'avatarIcon', p.avatar_icon, 'sellerCountry', p.country_code, 'sellerLevel', p.level,
    'sellerOnline', coalesce(p.last_seen_at > now() - interval '5 minutes', false),
    'sellerLastSeen', case when p.last_seen_at is null then null else to_jsonb(extract(epoch from p.last_seen_at)) end,
    'kind', l.kind, 'title', l.title, 'item', l.item, 'price', l.price, 'currency', l.currency, 'status', l.status,
    'postedAt', extract(epoch from l.created_at), 'mine', l.seller_id = viewer,
    'offerUsed', exists (select 1 from public.market_offers where listing_id = l.id and buyer_id = viewer and kind = 'offer'),
    'myDeal', case when mine.id is null then null else private.market_deal_json(mine, viewer) end);
end $$;

create function private.market_settle(o public.market_offers, final numeric) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare l public.market_listings; seller_name text; buyer_name text; other public.market_offers;
begin
  select * into l from public.market_listings where id = o.listing_id for update;
  if l.status <> 'active' then raise exception 'listing_closed' using errcode = 'P0001'; end if;
  seller_name := private.display_name(l.seller_id);
  buyer_name := private.display_name(o.buyer_id);
  update public.market_listings set status = 'sold', buyer_id = o.buyer_id, sold_price = final, closed_at = now() where id = l.id;
  update public.market_offers set status = 'accepted', final_price = final, answered_at = coalesce(answered_at, now()), closed_at = now() where id = o.id;
  perform private.settle(l.seller_id, final, l.currency, 'market_sale', o.id::text || ':sale',
    buyer_name || ' bought ' || l.title || ' for ' || private.market_money(final, l.currency) || '.',
    jsonb_build_object('dealID', o.id, 'listingID', l.id, 'itemID', l.item ->> 'id', 'title', 'Sold: ' || l.title, 'tone', 'good'));
  perform private.settle(o.buyer_id, 0, l.currency, 'market_purchase', o.id::text || ':buy',
    'You bought ' || l.title || ' from ' || seller_name || ' for ' || private.market_money(final, l.currency) || '. It is in your inventory.',
    jsonb_build_object('dealID', o.id, 'listingID', l.id, 'price', final, 'item', l.item || jsonb_build_object('title', l.title, 'kind', l.kind),
                       'title', 'Bought: ' || l.title, 'tone', 'good', 'seller', seller_name));
  for other in select * from public.market_offers where listing_id = l.id and status in ('pending', 'discussing') and id <> o.id for update loop
    update public.market_offers set status = 'closed', closed_at = now() where id = other.id;
    perform private.market_refund(other, l.title || ' was sold to someone else. Your money is back.', 'sold');
  end loop;
  return jsonb_build_object('status', 'accepted', 'dealID', o.id, 'price', final);
end $$;

create function public.market_list(p_item jsonb, p_price numeric, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); k text; t text; l public.market_listings;
begin
  perform private.require_free(uid, 'trade');
  if p_item is null or jsonb_typeof(p_item) <> 'object' then raise exception 'invalid_item' using errcode = 'P0001'; end if;
  k := p_item ->> 'kind';
  t := btrim(coalesce(p_item ->> 'title', ''));
  if k is null or k not in ('car', 'van', 'plane', 'boat', 'equipment', 'luxury') or char_length(t) not between 2 and 80 then raise exception 'invalid_item' using errcode = 'P0001'; end if;
  if p_price is null or p_price <= 0 or p_price > 1000000000000 or p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid_price' using errcode = 'P0001'; end if;
  if (select count(*) from public.market_listings where seller_id = uid and status = 'active') >= 12 then raise exception 'too_many_listings' using errcode = 'P0001'; end if;
  if exists (select 1 from public.market_listings where seller_id = uid and status = 'active' and item ->> 'id' = p_item ->> 'id') then raise exception 'already_listed' using errcode = 'P0001'; end if;
  insert into public.market_listings (seller_id, kind, title, item, price, currency) values (uid, k, t, p_item, round(p_price, 2), p_currency) returning * into l;
  return private.market_listing_json(l, uid);
end $$;

create function public.market_cancel(p_listing uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.market_listings;
begin
  select * into l from public.market_listings where id = p_listing and seller_id = uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if l.status <> 'active' then return; end if;
  update public.market_listings set status = 'cancelled', closed_at = now() where id = l.id;
  perform private.market_close_open(l, 'The seller took ' || l.title || ' off the market. Your money is back.', 'cancel');
  perform private.market_unlist_note(l, l.title || ' is back in your inventory.', 'cancel');
end $$;

create function public.market_browse(p_kind text default null, p_limit int default 60) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_player(); res jsonb;
begin
  select coalesce(jsonb_agg(private.market_listing_json(l, uid) order by l.created_at desc), '[]'::jsonb) into res
    from (select * from public.market_listings m
           where m.status = 'active' and m.seller_id <> uid and (p_kind is null or m.kind = p_kind)
             and not private.is_blocked_between(uid, m.seller_id)
             and exists (select 1 from public.profiles s where s.id = m.seller_id and s.deleted_at is null)
           order by m.created_at desc limit greatest(1, least(coalesce(p_limit, 60), 100))) l;
  return res;
end $$;

create function public.market_mine() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return jsonb_build_object(
    'listings', coalesce((select jsonb_agg(private.market_listing_json(l, uid) order by l.created_at desc)
                            from (select * from public.market_listings where seller_id = uid and (status = 'active' or closed_at > now() - interval '7 days') order by created_at desc limit 40) l), '[]'::jsonb),
    'incoming', coalesce((select jsonb_agg(private.market_deal_json(o, uid) order by o.created_at)
                            from public.market_offers o where o.seller_id = uid and o.status in ('pending', 'discussing')), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(private.market_deal_json(o, uid) order by o.created_at desc)
                            from (select * from public.market_offers where buyer_id = uid and (status in ('pending', 'discussing') or coalesce(closed_at, created_at) > now() - interval '7 days') order by created_at desc limit 40) o), '[]'::jsonb));
end $$;

create function public.market_buy(p_listing uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.market_listings; o public.market_offers; me text;
begin
  perform private.require_free(uid, 'trade');
  select * into l from public.market_listings where id = p_listing for update;
  if not found or l.status <> 'active' or private.is_blocked_between(uid, l.seller_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if l.seller_id = uid or private.linked(uid, l.seller_id) then raise exception 'own_listing' using errcode = 'P0001'; end if;
  if exists (select 1 from public.market_offers where listing_id = l.id and buyer_id = uid and status in ('pending', 'discussing')) then raise exception 'deal_open' using errcode = 'P0001'; end if;
  insert into public.market_offers (listing_id, buyer_id, seller_id, kind, price) values (l.id, uid, l.seller_id, 'buy', l.price) returning * into o;
  me := private.display_name(uid);
  perform private.market_notice(l.seller_id, o.id::text || ':req', 'Deal request: ' || l.title,
    me || ' wants to buy ' || l.title || ' for ' || private.market_money(l.price, l.currency) || '. Open Marketplace to accept or decline.', 'n', l.currency,
    jsonb_build_object('dealID', o.id, 'listingID', l.id));
  return private.market_deal_json(o, uid);
end $$;

create function public.market_offer(p_listing uuid, p_price numeric) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.market_listings; o public.market_offers; me text;
begin
  perform private.require_free(uid, 'trade');
  select * into l from public.market_listings where id = p_listing for update;
  if not found or l.status <> 'active' or private.is_blocked_between(uid, l.seller_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if l.seller_id = uid or private.linked(uid, l.seller_id) then raise exception 'own_listing' using errcode = 'P0001'; end if;
  if p_price is null or p_price <= 0 or p_price >= l.price then raise exception 'offer_not_lower' using errcode = 'P0001'; end if;
  if p_price < l.price * 0.3 then raise exception 'offer_too_low' using errcode = 'P0001'; end if;
  if exists (select 1 from public.market_offers where listing_id = l.id and buyer_id = uid and kind = 'offer') then raise exception 'offer_used' using errcode = 'P0001'; end if;
  if exists (select 1 from public.market_offers where listing_id = l.id and buyer_id = uid and status in ('pending', 'discussing')) then raise exception 'deal_open' using errcode = 'P0001'; end if;
  insert into public.market_offers (listing_id, buyer_id, seller_id, kind, price) values (l.id, uid, l.seller_id, 'offer', round(p_price, 2)) returning * into o;
  me := private.display_name(uid);
  perform private.market_notice(l.seller_id, o.id::text || ':req', 'Offer: ' || l.title,
    me || ' offers ' || private.market_money(o.price, l.currency) || ' for ' || l.title || ' (asking ' || private.market_money(l.price, l.currency) || '). Open Marketplace to answer.', 'n', l.currency,
    jsonb_build_object('dealID', o.id, 'listingID', l.id));
  return private.market_deal_json(o, uid);
end $$;

create function public.market_respond(p_deal uuid, p_action text, p_price numeric default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); o public.market_offers; l public.market_listings; me text;
begin
  select * into o from public.market_offers where id = p_deal and seller_id = uid for update;
  if not found or o.status not in ('pending', 'discussing') then raise exception 'not_found' using errcode = 'P0001'; end if;
  select * into l from public.market_listings where id = o.listing_id;
  me := private.display_name(uid);
  if p_action = 'accept' then
    return private.market_settle(o, o.price);
  elsif p_action = 'decline' then
    update public.market_offers set status = 'declined', answered_at = now(), closed_at = now() where id = o.id;
    perform private.market_refund(o, me || ' declined. Your money is back.', 'declined');
    return jsonb_build_object('status', 'declined', 'dealID', o.id);
  elsif p_action = 'discuss' then
    if o.status <> 'pending' then raise exception 'already_discussing' using errcode = 'P0001'; end if;
    if p_price is null or p_price <= 0 or p_price >= l.price then raise exception 'price_not_lower' using errcode = 'P0001'; end if;
    update public.market_offers set status = 'discussing', special_price = round(p_price, 2), answered_at = now() where id = o.id;
    perform private.market_notice(o.buyer_id, o.id::text || ':disc', 'New price: ' || l.title,
      me || ' will sell ' || l.title || ' to you for ' || private.market_money(p_price, l.currency) || '. Open Marketplace to take it or leave it.', 'n', l.currency,
      jsonb_build_object('dealID', o.id, 'listingID', l.id));
    return jsonb_build_object('status', 'discussing', 'dealID', o.id, 'specialPrice', round(p_price, 2));
  end if;
  raise exception 'invalid_action' using errcode = 'P0001';
end $$;

create function public.market_answer(p_deal uuid, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); o public.market_offers; l public.market_listings;
begin
  select * into o from public.market_offers where id = p_deal and buyer_id = uid for update;
  if not found or o.status <> 'discussing' or o.special_price is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_accept then return private.market_settle(o, o.special_price); end if;
  select * into l from public.market_listings where id = o.listing_id;
  update public.market_offers set status = 'withdrawn', closed_at = now() where id = o.id;
  perform private.market_refund(o, 'You turned down the new price. Your money is back.', 'turned');
  perform private.market_notice(o.seller_id, o.id::text || ':turned', 'No deal: ' || l.title,
    private.display_name(uid) || ' turned down your price for ' || l.title || '.', 'n', l.currency, jsonb_build_object('dealID', o.id, 'listingID', l.id));
  return jsonb_build_object('status', 'withdrawn', 'dealID', o.id);
end $$;

create function public.market_withdraw(p_deal uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); o public.market_offers; l public.market_listings;
begin
  select * into o from public.market_offers where id = p_deal and buyer_id = uid for update;
  if not found or o.status not in ('pending', 'discussing') then raise exception 'not_found' using errcode = 'P0001'; end if;
  select * into l from public.market_listings where id = o.listing_id;
  update public.market_offers set status = 'withdrawn', closed_at = now() where id = o.id;
  perform private.market_refund(o, 'You withdrew your request. Your money is back.', 'withdrawn');
  perform private.market_notice(o.seller_id, o.id::text || ':wd', 'Request withdrawn: ' || l.title,
    private.display_name(uid) || ' withdrew the request for ' || l.title || '.', 'n', l.currency, jsonb_build_object('dealID', o.id, 'listingID', l.id));
  return jsonb_build_object('status', 'withdrawn', 'dealID', o.id);
end $$;

create function private.market_catalog() returns table (kind text, ref text, title text, family text, base_nok numeric, lux boolean)
language sql immutable as $$
  select t.kind::text, t.ref::text, t.title::text, t.family::text, t.base_nok::numeric, t.lux::boolean from (values
    ('car', 'car_s', 'Hexa Compact 1.2', 'car_s', 340000, false),
    ('car', 'car_ev', 'Solen EV Hatch', 'car_ev', 460000, false),
    ('car', 'taxi_cmf', 'Karo Comfort Hybrid', 'taxi_cmf', 640000, false),
    ('car', 'car_lux', 'Aurelia Executive Sedan', 'car_lux', 880000, false),
    ('car', 'c15', 'Hyperion Zenith Tourer', 'car_lux', 1300000, true),
    ('car', 'c10', 'Apex V10 GT', 'car_lux', 3000000, true),
    ('van', 'van_s', 'Transa Small Van', 'van_s', 330000, false),
    ('van', 'van_l', 'Haulmark Large Van', 'van_l', 560000, false),
    ('van', 'pickup', 'Ridge Pickup 4x4', 'pickup', 520000, false),
    ('van', 'ev_van', 'Voltvan Electric', 'ev_van', 590000, false),
    ('van', 'van_box', 'Movers Box Van 20 m3', 'van_box', 640000, false),
    ('van', 'truck_s', 'Distribution Truck 12 t', 'truck_s', 950000, false),
    ('plane', 'j1', 'Corvane Light 4 jet', 'j1', 60000000, true),
    ('plane', 'j2', 'Stratos Noir midsize jet', 'j2', 160000000, true),
    ('plane', 'j4', 'Aerion Long Range 650', 'j4', 380000000, true),
    ('boat', 'y1', 'Sundqvist 40 day cruiser', 'y1', 5000000, true),
    ('boat', 'y2', 'Marenco 80 motor yacht', 'y2', 38000000, true),
    ('boat', 'ship_s', 'Small coaster', 'ship_s', 42000000, false),
    ('equipment', 'oven', 'Deck oven, two chambers', 'oven', 90000, false),
    ('equipment', 'lift', 'Two-post car lift', 'lift', 85000, false),
    ('equipment', 'esp', 'Espresso machine, two group', 'esp', 45000, false),
    ('equipment', 'mix', 'Spiral dough mixer', 'mix', 40000, false),
    ('equipment', 'tyre', 'Tyre changer and balancer', 'tyre', 65000, false),
    ('equipment', 'xray', 'Digital dental x-ray', 'xray', 120000, false),
    ('luxury', 'w1', 'Aethelred Vanguard Regulateur Grand Feu', 'w1', 380000, true),
    ('luxury', 'w5', 'Aethelred Monarch Solstice Celestial', 'w5', 650000, true),
    ('luxury', 'w3', 'Vescovi Riviere diamond necklace', 'w3', 900000, true),
    ('luxury', 'a1', 'Oil painting by Mira Halden', 'a1', 120000, true),
    ('luxury', 'a4', 'Jules Arnaud print set', 'a4', 400000, true),
    ('luxury', 'a3', 'Chateau Ormel cellar, 120 bottles', 'a3', 600000, true)
  ) as t (kind, ref, title, family, base_nok, lux);
$$;

create function private.market_bot_list(b uuid, seed text, want text) returns void language plpgsql security definer set search_path = '' as $$
declare c record; cc text; cur text; fx numeric; age int; km int; cond numeric; seen numeric; base numeric; price numeric; item jsonb;
begin
  select p.country_code into cc from public.profiles p where p.id = b;
  cur := private.market_currency(cc);
  fx := private.market_fx(cur);
  select * into c from private.market_catalog() m where m.kind = want order by abs(hashtext(seed || m.ref)) limit 1;
  if not found then return; end if;
  age := case when c.lux then 1 + abs(hashtext(seed || 'a')) % 6 else 1 + abs(hashtext(seed || 'a')) % 11 end;
  km := case when want in ('car', 'van') then (age * (9000 + abs(hashtext(seed || 'k')) % 12000)) / 1000 * 1000 else 0 end;
  seen := least(0.97, greatest(0.25, 0.92 - age * 0.04 - (abs(hashtext(seed || 's')) % 100) / 500.0));
  cond := case when abs(hashtext(seed || 'l')) % 100 < 14 then greatest(0.2, seen - 0.2 - (abs(hashtext(seed || 'q')) % 100) / 400.0)
               when abs(hashtext(seed || 'l')) % 100 > 92 then least(1, seen + 0.08)
               else least(1, greatest(0.15, seen + ((abs(hashtext(seed || 'q')) % 100) - 50) / 800.0)) end;
  base := round(c.base_nok / fx * (0.97 + (abs(hashtext(seed || 'b')) % 60) / 1000.0), 2);
  price := round(base * (0.5 + 0.5 * seen) * (0.9 + (abs(hashtext(seed || 'p')) % 200) / 1000.0), 2);
  item := jsonb_build_object('id', 'm' || substr(md5(seed), 1, 14), 'kind', want, 'title', c.title, 'family', c.family, 'ref', c.ref, 'lux', c.lux,
                             'age', age, 'km', km, 'seen', round(seen, 2), 'cond', round(cond, 2), 'base', base);
  insert into public.market_listings (seller_id, kind, title, item, price, currency, created_at, expires_at)
    values (b, want, c.title, item, price, cur, now() - make_interval(mins => abs(hashtext(seed || 't')) % 90), now() + make_interval(days => 4 + abs(hashtext(seed || 'e')) % 9));
exception when unique_violation then null;
end $$;

create function private.market_bot_stock() returns int language plpgsql security definer set search_path = '' as $$
declare k text; real_n int; fake_n int; target int; made int := 0; b uuid; bucket bigint := floor(extract(epoch from now()) / 600)::bigint; seed text;
begin
  if private.fakes_removed() then return 0; end if;
  foreach k in array array['car', 'van', 'plane', 'boat', 'equipment', 'luxury'] loop
    select count(*) filter (where not p.is_bot), count(*) filter (where p.is_bot) into real_n, fake_n
      from public.market_listings m join public.profiles p on p.id = m.seller_id where m.status = 'active' and m.kind = k;
    target := greatest(0, (case when k in ('car', 'van', 'equipment') then 6 else 4 end) - real_n);
    if fake_n < target and abs(hashtext(k || bucket::text)) % 3 = 0 then
      seed := k || ':' || bucket::text || ':' || fake_n::text;
      b := null;
      select bt.user_id into b from public.bots bt join public.profiles p on p.id = bt.user_id
       where bt.active and p.deleted_at is null
         and (select count(*) from public.market_listings m where m.seller_id = bt.user_id and m.status = 'active') < 3
       order by abs(hashtext(seed || bt.user_id::text)) limit 1;
      if b is not null then
        perform private.market_bot_list(b, seed, k);
        made := made + 1;
      end if;
    elsif fake_n > target then
      update public.market_listings m set status = 'cancelled', closed_at = now()
       where m.id = (select m2.id from public.market_listings m2 join public.profiles p on p.id = m2.seller_id
                      where m2.status = 'active' and m2.kind = k and p.is_bot and m2.created_at < now() - interval '1 day'
                        and not exists (select 1 from public.market_offers o where o.listing_id = m2.id and o.status in ('pending', 'discussing'))
                      order by m2.created_at limit 1);
    end if;
  end loop;
  return made;
end $$;

create function private.market_bot_respond() returns int language plpgsql security definer set search_path = '' as $$
declare o public.market_offers; l public.market_listings; n int := 0; delay int; special numeric;
begin
  for o in select o2.* from public.market_offers o2 join public.profiles p on p.id = o2.seller_id
            where o2.status = 'pending' and p.is_bot order by o2.created_at for update of o2 skip locked loop
    delay := 2 + abs(hashtext(o.id::text)) % 38;
    continue when o.created_at > now() - make_interval(mins => delay);
    continue when not private.bot_awake(o.seller_id) and o.created_at > now() - interval '3 hours';
    select * into l from public.market_listings where id = o.listing_id;
    if o.kind = 'buy' then
      if abs(hashtext(o.id::text || 'r')) % 100 < 90 then perform private.market_settle(o, o.price);
      else
        update public.market_offers set status = 'declined', answered_at = now(), closed_at = now() where id = o.id;
        perform private.market_refund(o, private.display_name(o.seller_id) || ' declined. Your money is back.', 'declined');
      end if;
    else
      if o.price >= l.price * 0.9 then perform private.market_settle(o, o.price);
      elsif o.price >= l.price * 0.75 then
        special := round((o.price + l.price) / 2, 2);
        update public.market_offers set status = 'discussing', special_price = special, answered_at = now() where id = o.id;
        perform private.market_notice(o.buyer_id, o.id::text || ':disc', 'New price: ' || l.title,
          private.display_name(o.seller_id) || ' will sell ' || l.title || ' to you for ' || private.market_money(special, l.currency) || '. Open Marketplace to take it or leave it.', 'n', l.currency,
          jsonb_build_object('dealID', o.id, 'listingID', l.id));
      else
        update public.market_offers set status = 'declined', answered_at = now(), closed_at = now() where id = o.id;
        perform private.market_refund(o, private.display_name(o.seller_id) || ' declined your offer. Your money is back.', 'declined');
      end if;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

create function private.market_expire() returns int language plpgsql security definer set search_path = '' as $$
declare l public.market_listings; o public.market_offers; n int := 0;
begin
  for l in select * from public.market_listings where status = 'active' and expires_at < now() for update skip locked loop
    update public.market_listings set status = 'expired', closed_at = now() where id = l.id;
    perform private.market_close_open(l, l.title || ' is no longer for sale. Your money is back.', 'expired');
    perform private.market_unlist_note(l, 'Your listing of ' || l.title || ' ran out. It is back in your inventory.', 'expired');
    n := n + 1;
  end loop;
  for o in select * from public.market_offers where status in ('pending', 'discussing') and created_at < now() - interval '3 days' for update skip locked loop
    update public.market_offers set status = 'expired', closed_at = now() where id = o.id;
    perform private.market_refund(o, 'The seller did not answer in time. Your money is back.', 'timeout');
    n := n + 1;
  end loop;
  return n;
end $$;

create function private.market_tick() returns int language plpgsql security definer set search_path = '' as $$
begin
  return private.market_expire() + private.market_bot_respond() + private.market_bot_stock();
end $$;

create or replace function private.run_due_jobs() returns int language plpgsql security definer set search_path = '' as $$
declare j public.job_runs; n int := 0;
begin
  for j in select * from public.job_runs where last_run is null or last_run + every <= now() order by name for update skip locked loop
    update public.job_runs set last_run = now() where name = j.name;
    begin
      if j.name = 'auctions' then perform private.settle_due_auctions();
      elsif j.name = 'bots' then perform private.bot_tick();
      elsif j.name = 'orders' then perform private.expire_orders();
      elsif j.name = 'supply' then perform private.run_supply_week(date_trunc('week', now())::date - 7);
      elsif j.name = 'startups' then perform private.run_startup_expiry();
      elsif j.name = 'ventures' then perform private.run_venture_housekeeping();
      elsif j.name = 'news' then perform private.run_news_cleanup();
      elsif j.name = 'elections' then perform private.run_election_cycle();
      elsif j.name = 'market' then perform private.market_tick();
      end if;
      n := n + 1;
    exception when others then
      raise warning 'job % failed: %', j.name, sqlerrm;
    end;
  end loop;
  return n;
end $$;

create or replace function public.admin_remove_fake_players(p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin(); why text := trim(coalesce(p_reason, '')); n int; l public.market_listings;
begin
  if char_length(why) < 3 then raise exception 'reason_required' using errcode = 'P0001'; end if;
  insert into public.world_flags (key, value, updated_by) values ('fakes_removed', 'true'::jsonb, uid)
    on conflict (key) do update set value = 'true'::jsonb, updated_at = now(), updated_by = uid;
  update public.supply_contracts set ended_at = now(), end_reason = 'stopped'
   where ended_at is null and (supplier_id in (select id from public.profiles where is_bot) or buyer_id in (select id from public.profiles where is_bot));
  update public.supply_listings set stopped = true where not stopped and owner_id in (select id from public.profiles where is_bot);
  update public.exchange_orders set status = 'cancelled' where status = 'open' and trader_id in (select id from public.profiles where is_bot);
  update public.exchange_listings set delisted_at = now() where delisted_at is null and owner_id in (select id from public.profiles where is_bot);
  for l in select * from public.market_listings where status = 'active' and seller_id in (select id from public.profiles where is_bot) for update loop
    update public.market_listings set status = 'cancelled', closed_at = now() where id = l.id;
    perform private.market_close_open(l, l.title || ' is no longer for sale. Your money is back.', 'cancel');
  end loop;
  delete from public.leaderboard_entries where user_id in (select id from public.profiles where is_bot);
  delete from public.companies_public where owner_id in (select id from public.profiles where is_bot);
  update public.bots set active = false;
  update public.profiles set deleted_at = now() where is_bot and deleted_at is null;
  get diagnostics n = row_count;
  perform private.audit(uid, 'remove_fake_players', 'world', null, to_jsonb(n), why);
  return jsonb_build_object('removed', n);
end $$;

grant execute on function public.market_list(jsonb, numeric, text), public.market_cancel(uuid), public.market_browse(text, int), public.market_mine(),
  public.market_buy(uuid), public.market_offer(uuid, numeric), public.market_respond(uuid, text, numeric), public.market_answer(uuid, boolean),
  public.market_withdraw(uuid), public.admin_remove_fake_players(text) to authenticated;
