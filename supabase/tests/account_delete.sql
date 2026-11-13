-- Account deletion: run after bootstrap.sql and every migration. A deletes; B and C keep playing.
create function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
$$;

create function pg_temp.mk(nm text) returns uuid language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role) values (u, 'authenticated', 'authenticated');
  insert into public.profiles (id, display_name, adult_confirmed, created_at) values (u, nm, true, now() - interval '60 days');
  return u;
end $$;

do $$
declare a uuid := pg_temp.mk('Alice Ames'); b uuid := pg_temp.mk('Bob Berg'); c uuid := pg_temp.mk('Cora Cole');
        v1 uuid; v2 uuid; l1 uuid; l2 uuid; live uuid; e1 uuid; e2 uuid; s1 uuid; items jsonb; ex jsonb;
begin
  -- A owns a venture where B holds 20% and paid 2500; A holds 10% of C's venture.
  insert into public.ventures (chair_id, company_key, name, currency, value) values (a, 'own.1', 'Alpha Bakery', 'USD', 10000) returning id into v1;
  insert into public.venture_partners (venture_id, member_id, shares) values (v1, a, 8000), (v1, b, 2000);
  perform private.settle(b, -2500, 'USD', 'venture_stake', v1::text, 'Joined Alpha Bakery');
  insert into public.ventures (chair_id, company_key, name, currency, value) values (c, 'own.4', 'Cora Cars', 'USD', 50000) returning id into v2;
  insert into public.venture_partners (venture_id, member_id, shares) values (v2, c, 9000), (v2, a, 1000);

  -- Marketplace requests both ways.
  insert into public.market_listings (seller_id, kind, title, item, price, currency) values (a, 'car', 'Red van', '{"id":"car1"}', 900, 'USD') returning id into l1;
  insert into public.market_listings (seller_id, kind, title, item, price, currency) values (b, 'boat', 'Blue boat', '{"id":"boat1"}', 700, 'USD') returning id into l2;
  insert into public.market_offers (listing_id, buyer_id, seller_id, kind, price) values (l1, b, a, 'buy', 900), (l2, a, b, 'buy', 700);

  -- A owns a piece C once sold at auction, and leads C's live auction over B.
  insert into public.artifact_pieces (def_id, serial, owner_id) values ('abacus', 1, a), ('abacus', 2, c);
  insert into public.auctions (def_id, serial, seller_id, start_price, ends_at, duration_hours, status, sold_for, winner_id, currency)
    values ('abacus', 1, c, 10, now() - interval '1 day', 1, 'sold', 50, a, 'USD');
  insert into public.auctions (def_id, serial, seller_id, start_price, ends_at, duration_hours, currency)
    values ('abacus', 2, c, 10, now() + interval '1 day', 24, 'USD') returning id into live;
  insert into public.auction_bids (auction_id, bidder_id, amount) values (live, b, 100), (live, a, 200);

  -- Exchange: B holds shares of A's listing that cost 500; A holds shares of C's listing and has an open order.
  insert into public.exchange_listings (owner_id, company_key, name, currency, value) values (a, 'own.1', 'Alpha Bakery', 'USD', 1000000) returning id into e1;
  insert into public.exchange_listings (owner_id, company_key, name, currency, value) values (c, 'own.4', 'Cora Cars', 'USD', 1000000) returning id into e2;
  insert into public.exchange_holdings (listing_id, owner_id, shares, cost) values (e1, a, 999000, 0), (e1, b, 1000, 500), (e2, c, 999700, 0), (e2, a, 300, 300);
  insert into public.exchange_orders (listing_id, trader_id, side, shares, remaining, price) values (e2, a, 'buy', 10, 10, 1);

  -- A raises money for a startup; B's 1000 is still held.
  insert into public.startups (founder_id, company_key, name, trade, currency, plan_cost, founder_put_in) values (a, 'own.1', 'Alpha Labs', 'tech', 'USD', 3000, 1000) returning id into s1;
  insert into public.startup_investments (startup_id, investor_id, link_key, stage, amount, percent) values (s1, b, 'k', 0, 1000, 5);

  perform pg_temp.as_user(a);
  items := public.account_deletion_preview() -> 'items';
  if jsonb_array_length(items) < 8 or not items::text like '%Alpha Bakery is closed%' or not items::text like '%Cora Cars goes back to its owner%' then
    raise exception 'preview misses something: %', items;
  end if;
  ex := public.export_my_data();
  if jsonb_array_length(ex -> 'ventureStakes') <> 2 or jsonb_array_length(ex -> 'marketDeals') <> 2 or jsonb_array_length(ex -> 'auctionBids') <> 1
     or jsonb_array_length(ex -> 'exchangeHoldings') <> 2 or ex -> 'profile' ->> 'display_name' <> 'Alice Ames' then
    raise exception 'export misses tables: %', ex;
  end if;

  perform public.delete_my_account();

  if exists (select 1 from auth.users where id = a) then raise exception 'the account is still there'; end if;
  if (select amount from public.settlements where recipient_id = b and kind = 'venture_dissolved') <> 2000 then raise exception 'partner not paid the value of the shares'; end if;
  if (select amount from public.settlements where recipient_id = b and kind = 'exchange_buyout') <> 500 then raise exception 'shareholder not paid what the shares cost'; end if;
  if (select amount from public.settlements where recipient_id = b and kind = 'startup_refund') <> 1000 then raise exception 'held startup money not returned'; end if;
  if not exists (select 1 from public.settlements where recipient_id = b and kind = 'market_refund') then raise exception 'waiting buyer not refunded'; end if;
  if not exists (select 1 from public.settlements where recipient_id = b and kind = 'market_notice' and label like '%buyer left%') then raise exception 'seller not told'; end if;
  if (select shares from public.venture_partners where venture_id = v2 and member_id = c) <> 10000 then raise exception 'stake did not go back to the owner'; end if;
  if (select bidder_id from private.auction_top(live)) <> b then raise exception 'the next bid does not lead'; end if;
  if (select shares from public.exchange_holdings where listing_id = e2 and owner_id = c) <> 1000000 then raise exception 'listed shares did not go back to the owner'; end if;
  if (select status from public.market_listings where id = l2) <> 'active' then raise exception 'another players listing was closed'; end if;
end $$;

-- A guest account with no profile is deleted too.
do $$
declare g uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role) values (g, 'authenticated', 'authenticated');
  perform pg_temp.as_user(g);
  if jsonb_array_length(public.account_deletion_preview() -> 'items') <> 0 then raise exception 'a guest has things to settle'; end if;
  perform public.delete_my_account();
  if exists (select 1 from auth.users where id = g) then raise exception 'the guest account is still there'; end if;
end $$;
