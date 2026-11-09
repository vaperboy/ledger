-- Public exchange: a player's holding company can go public, and other players trade its shares in an order book. Mirrors the engine's
-- Funding listing rules (a minimum value and a listing fee, scaled to the currency). The owner reports the company's value, but every
-- price must stay inside a band around it, the owner keeps control (at least 51% of the shares), linked accounts cannot trade with each
-- other, and the trade tax and gains tax go to the country treasuries.

create type public.exchange_side as enum ('buy', 'sell');
create type public.exchange_order_status as enum ('open', 'filled', 'cancelled');

create table public.exchange_listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  company_key text not null check (char_length(company_key) between 1 and 64),
  name text not null check (char_length(name) between 1 and 40),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  total_shares bigint not null default 1000000 check (total_shares > 0),
  -- The company's value as its owner last reported it; the price band hangs on it.
  value numeric(18, 2) not null check (value > 0),
  value_reported_at timestamptz not null default now(),
  listed_at timestamptz not null default now(),
  delisted_at timestamptz
);
create unique index exchange_one_listing on public.exchange_listings (owner_id, company_key) where delisted_at is null;

create table public.exchange_holdings (
  listing_id uuid not null references public.exchange_listings (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  shares bigint not null check (shares >= 0),
  -- What the shares cost in all (the basis for the gains tax).
  cost numeric(18, 2) not null default 0 check (cost >= 0),
  primary key (listing_id, owner_id)
);
create index exchange_holdings_owner on public.exchange_holdings (owner_id);

create table public.exchange_orders (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.exchange_listings (id) on delete cascade,
  trader_id uuid not null references public.profiles (id) on delete cascade,
  side public.exchange_side not null,
  shares bigint not null check (shares > 0),
  remaining bigint not null check (remaining >= 0),
  price numeric(18, 4) not null check (price > 0),
  status public.exchange_order_status not null default 'open',
  created_at timestamptz not null default now()
);
create index exchange_orders_book on public.exchange_orders (listing_id, side, price, created_at) where status = 'open';
create index exchange_orders_trader on public.exchange_orders (trader_id) where status = 'open';

create table public.exchange_trades (
  id bigint generated always as identity primary key,
  listing_id uuid not null references public.exchange_listings (id) on delete cascade,
  buyer_id uuid references public.profiles (id) on delete set null,
  seller_id uuid references public.profiles (id) on delete set null,
  shares bigint not null check (shares > 0),
  price numeric(18, 4) not null,
  traded_at timestamptz not null default now()
);
create index exchange_trades_listing on public.exchange_trades (listing_id, traded_at desc);

alter table public.exchange_listings enable row level security;
alter table public.exchange_holdings enable row level security;
alter table public.exchange_orders enable row level security;
alter table public.exchange_trades enable row level security;
revoke all on public.exchange_listings, public.exchange_holdings, public.exchange_orders, public.exchange_trades from anon, authenticated;
grant select on public.exchange_listings, public.exchange_holdings, public.exchange_orders, public.exchange_trades to authenticated;

-- A listing and its trade tape are public (that is what an exchange is); holdings and orders are private to their owner, the book is
-- shown only as price levels by exchange_market().
create policy exchange_listings_read on public.exchange_listings for select to authenticated using (delisted_at is null or owner_id = auth.uid());
create policy exchange_trades_read on public.exchange_trades for select to authenticated using (true);
create policy exchange_holdings_own on public.exchange_holdings for select to authenticated using (owner_id = auth.uid());
create policy exchange_orders_own on public.exchange_orders for select to authenticated using (trader_id = auth.uid());

create or replace function private.exchange_open(uid uuid) returns boolean language sql stable as $$
  select exists (select 1 from public.exchange_holdings h join public.exchange_listings l on l.id = h.listing_id
                  where h.owner_id = uid and h.shares > 0 and l.owner_id <> uid and l.delisted_at is null)
      or exists (select 1 from public.exchange_listings l where l.owner_id = uid and l.delisted_at is null
                  and exists (select 1 from public.exchange_holdings h where h.listing_id = l.id and h.owner_id <> uid and h.shares > 0))
      or exists (select 1 from public.exchange_orders where trader_id = uid and status = 'open');
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------------------------------------------------
create function private.exchange_nav(l public.exchange_listings) returns numeric language sql immutable as $$ select l.value / l.total_shares; $$;

create function private.exchange_last_price(lid uuid) returns numeric language sql stable security definer set search_path = '' as $$
  select price from public.exchange_trades where listing_id = lid order by id desc limit 1;
$$;

-- The owner lists the holding. Needs 30,000,000 of value and pays 1,500,000 (reference economy, scaled to the currency); the owner starts with all shares.
create function public.list_on_exchange(p_company_key text, p_name text, p_value numeric, p_currency text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.exchange_listings; sc numeric := private.currency_scale(p_currency); fee numeric; cc text;
begin
  perform private.require_free(uid, 'trade');
  if p_value is null or p_value < 30000000 * sc then raise exception 'too_small' using errcode = 'P0001'; end if;
  if exists (select 1 from public.exchange_listings where owner_id = uid and company_key = p_company_key and delisted_at is null) then raise exception 'already_listed' using errcode = 'P0001'; end if;
  insert into public.exchange_listings (owner_id, company_key, name, currency, value) values (uid, p_company_key, p_name, p_currency, round(p_value, 2)) returning * into l;
  insert into public.exchange_holdings (listing_id, owner_id, shares, cost) values (l.id, uid, l.total_shares, 0);
  fee := round(1500000 * sc, 2);
  perform private.settle(uid, -fee, p_currency, 'exchange_listing_fee', l.id::text, 'Stock exchange listing: ' || p_name, jsonb_build_object('listingID', l.id, 'companyKey', p_company_key));
  select country_code into cc from public.profiles where id = uid;
  perform private.treasury_post(cc, fee, 'exchange_listing_fee', l.id::text);
  return jsonb_build_object('id', l.id, 'totalShares', l.total_shares, 'navPerShare', private.exchange_nav(l));
end $$;

-- The owner keeps the value current. A single report may move it by at most a quarter, and no more than once an hour.
create function public.report_exchange_value(p_listing uuid, p_value numeric) returns numeric language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.exchange_listings;
begin
  select * into l from public.exchange_listings where id = p_listing and owner_id = uid and delisted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_value is null or p_value <= 0 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  if now() - l.value_reported_at < interval '1 hour' then raise exception 'too_soon' using errcode = 'P0001'; end if;
  if p_value > l.value * 1.25 or p_value < l.value * 0.75 then raise exception 'value_jump' using errcode = 'P0001'; end if;
  update public.exchange_listings set value = round(p_value, 2), value_reported_at = now() where id = l.id;
  return private.exchange_nav(l) * p_value / l.value;
end $$;

-- Listings with their price levels (best bid and ask, last trade) for the market screen. Blocked owners' listings are left out.
create function public.exchange_market() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'ownerID', l.owner_id, 'ownerName', private.display_name(l.owner_id),
      'currency', l.currency, 'totalShares', l.total_shares, 'value', l.value, 'navPerShare', private.exchange_nav(l), 'lastPrice', private.exchange_last_price(l.id),
      'bestBid', (select max(price) from public.exchange_orders o where o.listing_id = l.id and o.side = 'buy' and o.status = 'open'),
      'bestAsk', (select min(price) from public.exchange_orders o where o.listing_id = l.id and o.side = 'sell' and o.status = 'open'),
      'priceLow', round(private.exchange_nav(l) * 0.75, 4), 'priceHigh', round(private.exchange_nav(l) * 1.25, 4),
      'myShares', coalesce((select shares from public.exchange_holdings h where h.listing_id = l.id and h.owner_id = uid), 0)) order by l.listed_at)
    from public.exchange_listings l where l.delisted_at is null and not private.is_blocked_between(uid, l.owner_id)), '[]'::jsonb);
end $$;

create function public.my_exchange_positions() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return jsonb_build_object(
    'holdings', coalesce((select jsonb_agg(jsonb_build_object('listingID', h.listing_id, 'name', l.name, 'shares', h.shares, 'cost', h.cost,
        'navValue', round(h.shares * private.exchange_nav(l), 2))) from public.exchange_holdings h join public.exchange_listings l on l.id = h.listing_id
        where h.owner_id = uid and h.shares > 0), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'listingID', o.listing_id, 'side', o.side, 'shares', o.shares, 'remaining', o.remaining,
        'price', o.price, 'createdAt', o.created_at) order by o.created_at desc) from public.exchange_orders o where o.trader_id = uid and o.status = 'open'), '[]'::jsonb));
end $$;

-- Shares a trader could still put up for sale: holdings less what open sell orders already promise; the owner keeps 51%.
create function private.exchange_sellable(l public.exchange_listings, uid uuid) returns bigint language sql stable security definer set search_path = '' as $$
  select greatest(0, coalesce((select shares from public.exchange_holdings where listing_id = l.id and owner_id = uid), 0)
       - coalesce((select sum(remaining) from public.exchange_orders where listing_id = l.id and trader_id = uid and side = 'sell' and status = 'open'), 0)
       - case when uid = l.owner_id then ceil(l.total_shares * 0.51)::bigint else 0 end);
$$;

-- Places a limit order and matches it at once against the book (the resting order's price is the trade price). Returns the filled shares.
create function public.place_exchange_order(p_listing uuid, p_side public.exchange_side, p_shares bigint, p_price numeric, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.exchange_listings; nav numeric; o public.exchange_orders; mine public.exchange_orders; fill bigint; filled bigint := 0;
        buyer uuid; seller uuid; bh public.exchange_holdings; sh public.exchange_holdings; basis numeric; gross numeric; tax numeric; gtax numeric; bcc text; scc text; oid uuid;
begin
  perform private.require_free(uid, 'trade');
  select * into l from public.exchange_listings where id = p_listing and delisted_at is null for update;
  if not found or private.is_blocked_between(uid, l.owner_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_currency <> l.currency then raise exception 'currency_mismatch' using errcode = 'P0001'; end if;
  if p_shares is null or p_shares <= 0 or p_price is null or p_price <= 0 then raise exception 'invalid_order' using errcode = 'P0001'; end if;
  nav := private.exchange_nav(l);
  if p_price < nav * 0.75 or p_price > nav * 1.25 then raise exception 'outside_band' using errcode = 'P0001'; end if;
  if now() - (select created_at from public.profiles where id = uid) < private.weeks(4) then raise exception 'new_account' using errcode = 'P0001'; end if;
  if p_side = 'sell' and p_shares > private.exchange_sellable(l, uid) then raise exception 'too_many' using errcode = 'P0001'; end if;
  insert into public.exchange_orders (listing_id, trader_id, side, shares, remaining, price) values (l.id, uid, p_side, p_shares, p_shares, round(p_price, 4)) returning * into mine;
  oid := mine.id;
  for o in select * from public.exchange_orders x where x.listing_id = l.id and x.status = 'open' and x.side <> p_side and x.id <> mine.id
            and ((p_side = 'buy' and x.price <= mine.price) or (p_side = 'sell' and x.price >= mine.price))
            and x.trader_id <> uid and not private.linked(x.trader_id, uid) and not private.is_blocked_between(x.trader_id, uid)
          order by case when p_side = 'buy' then x.price end asc, case when p_side = 'sell' then x.price end desc, x.created_at for update loop
    exit when mine.remaining = 0;
    fill := least(mine.remaining, o.remaining);
    buyer := case when p_side = 'buy' then uid else o.trader_id end;
    seller := case when p_side = 'sell' then uid else o.trader_id end;
    gross := round(fill * o.price, 2);
    select * into sh from public.exchange_holdings where listing_id = l.id and owner_id = seller for update;
    basis := case when sh.shares > 0 then sh.cost * fill / sh.shares else 0 end;
    select country_code into bcc from public.profiles where id = buyer;
    select country_code into scc from public.profiles where id = seller;
    tax := round(gross * private.transfer_tax_rate(bcc), 2);
    gtax := round(greatest(0, gross - basis) * private.gains_tax_rate(scc), 2);
    update public.exchange_holdings set shares = shares - fill, cost = cost - basis where listing_id = l.id and owner_id = seller;
    insert into public.exchange_holdings (listing_id, owner_id, shares, cost) values (l.id, buyer, fill, gross)
      on conflict (listing_id, owner_id) do update set shares = public.exchange_holdings.shares + fill, cost = public.exchange_holdings.cost + gross;
    update public.exchange_orders set remaining = remaining - fill, status = (case when remaining - fill = 0 then 'filled' else 'open' end)::public.exchange_order_status where id = o.id;
    mine.remaining := mine.remaining - fill; filled := filled + fill;
    insert into public.exchange_trades (listing_id, buyer_id, seller_id, shares, price) values (l.id, buyer, seller, fill, o.price);
    perform private.settle(buyer, -(gross + tax), l.currency, 'exchange_purchase', l.id::text, 'Bought ' || fill || ' shares of ' || l.name,
      jsonb_build_object('listingID', l.id, 'shares', fill, 'price', o.price, 'transferTax', tax));
    perform private.settle(seller, gross - gtax, l.currency, 'exchange_sale', l.id::text, 'Sold ' || fill || ' shares of ' || l.name,
      jsonb_build_object('listingID', l.id, 'shares', fill, 'price', o.price, 'gainsTax', gtax));
    perform private.treasury_post(bcc, tax, 'exchange_transfer_tax', l.id::text);
    perform private.treasury_post(scc, gtax, 'exchange_gains_tax', l.id::text);
  end loop;
  update public.exchange_orders set remaining = mine.remaining, status = (case when mine.remaining = 0 then 'filled' else 'open' end)::public.exchange_order_status where id = oid;
  return jsonb_build_object('orderID', oid, 'filled', filled, 'remaining', mine.remaining);
end $$;

create function public.cancel_exchange_order(p_order uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  update public.exchange_orders set status = 'cancelled' where id = p_order and trader_id = uid and status = 'open';
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
end $$;

-- The owner takes the company off the exchange once nobody else holds shares (they must be bought or sold first).
create function public.delist_from_exchange(p_listing uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if exists (select 1 from public.exchange_holdings where listing_id = p_listing and owner_id <> uid and shares > 0) then raise exception 'outside_holders' using errcode = 'P0001'; end if;
  update public.exchange_listings set delisted_at = now() where id = p_listing and owner_id = uid and delisted_at is null;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  update public.exchange_orders set status = 'cancelled' where listing_id = p_listing and status = 'open';
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.list_on_exchange(text, text, numeric, text), public.report_exchange_value(uuid, numeric), public.exchange_market(),
  public.my_exchange_positions(), public.place_exchange_order(uuid, public.exchange_side, bigint, numeric, text), public.cancel_exchange_order(uuid),
  public.delist_from_exchange(uuid) to authenticated;
