revoke select on public.exchange_trades from authenticated;
grant select (id, listing_id, shares, price, traded_at) on public.exchange_trades to authenticated;
create index if not exists exchange_trades_pair on public.exchange_trades (listing_id, buyer_id, seller_id, traded_at desc);

create table if not exists public.exchange_value_log (
  listing_id uuid not null references public.exchange_listings (id) on delete cascade,
  value numeric(18, 2) not null,
  at timestamptz not null default now()
);
create index if not exists exchange_value_log_listing on public.exchange_value_log (listing_id, at desc);
alter table public.exchange_value_log enable row level security;
revoke all on public.exchange_value_log from anon, authenticated;

insert into public.exchange_value_log (listing_id, value, at)
  select l.id, l.value, l.value_reported_at from public.exchange_listings l
   where not exists (select 1 from public.exchange_value_log v where v.listing_id = l.id);

create or replace function private.exchange_log_listing() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.exchange_value_log (listing_id, value) values (new.id, new.value);
  return new;
end $$;
drop trigger if exists exchange_listing_value_log on public.exchange_listings;
create trigger exchange_listing_value_log after insert on public.exchange_listings for each row execute function private.exchange_log_listing();

create or replace function private.exchange_const(k text) returns numeric language sql immutable as $$
  select case k when 'day_move' then 0.10 when 'value_step' then 0.10 when 'holder_cap' then 0.20 when 'owner_floor' then 0.51
                when 'lockup_days' then 28 when 'quarter_days' then 91 when 'blackout_before' then 7 when 'blackout_after' then 1
                when 'pair_trades' then 3 when 'pair_trades_shared' then 1 when 'pair_share' then 0.10 when 'pair_share_shared' then 0.04
                when 'cooling_weeks' then 2 when 'value_growth_week' then 1.5 when 'open_orders' then 20 end;
$$;

create or replace function private.pair_allowance(lid uuid, buyer uuid, seller uuid, total bigint) returns bigint language plpgsql stable security definer set search_path = '' as $$
declare shared boolean; n int; vol bigint; max_n int; max_share numeric;
begin
  if exists (select 1 from public.profiles where id in (buyer, seller) and is_bot) then return total; end if;
  if exists (select 1 from public.exchange_trades t where t.listing_id = lid and t.buyer_id = seller and t.seller_id = buyer
                and t.traded_at > now() - private.weeks(private.exchange_const('cooling_weeks')::int)) then return 0; end if;
  shared := private.shares_network(buyer, seller);
  max_n := (case when shared then private.exchange_const('pair_trades_shared') else private.exchange_const('pair_trades') end)::int;
  max_share := case when shared then private.exchange_const('pair_share_shared') else private.exchange_const('pair_share') end;
  select count(*), coalesce(sum(t.shares), 0) into n, vol from public.exchange_trades t
   where t.listing_id = lid and ((t.buyer_id = buyer and t.seller_id = seller) or (t.buyer_id = seller and t.seller_id = buyer))
     and t.traded_at > now() - private.weeks(1);
  if n >= max_n then return 0; end if;
  return greatest(0, floor(total * max_share)::bigint - vol);
end $$;

create or replace function private.exchange_open(uid uuid) returns boolean language sql stable as $$
  select exists (select 1 from public.exchange_holdings h join public.exchange_listings l on l.id = h.listing_id
                  where h.owner_id = uid and h.shares > 0 and l.owner_id <> uid and l.delisted_at is null)
      or exists (select 1 from public.exchange_listings l where l.owner_id = uid and l.delisted_at is null
                  and exists (select 1 from public.exchange_holdings h join public.profiles hp on hp.id = h.owner_id
                               where h.listing_id = l.id and h.owner_id <> uid and h.shares > 0 and not hp.is_bot))
      or exists (select 1 from public.exchange_orders where trader_id = uid and status = 'open');
$$;

create or replace function public.delist_from_exchange(p_listing uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.exchange_listings; back bigint;
begin
  select * into l from public.exchange_listings where id = p_listing and owner_id = uid and delisted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if exists (select 1 from public.exchange_holdings h join public.profiles p on p.id = h.owner_id
              where h.listing_id = p_listing and h.owner_id <> uid and h.shares > 0 and not p.is_bot) then raise exception 'outside_holders' using errcode = 'P0001'; end if;
  select coalesce(sum(h.shares), 0) into back from public.exchange_holdings h join public.profiles p on p.id = h.owner_id and p.is_bot where h.listing_id = p_listing;
  delete from public.exchange_holdings h using public.profiles p where h.listing_id = p_listing and p.id = h.owner_id and p.is_bot;
  update public.exchange_holdings set shares = shares + back where listing_id = p_listing and owner_id = uid;
  update public.exchange_listings set delisted_at = now() where id = p_listing;
  update public.exchange_orders set status = 'cancelled' where listing_id = p_listing and status = 'open';
end $$;

create or replace function public.report_exchange_value(p_listing uuid, p_value numeric) returns numeric language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.exchange_listings; floor_value numeric;
begin
  select * into l from public.exchange_listings where id = p_listing and owner_id = uid and delisted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_value is null or p_value <= 0 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  if now() - l.value_reported_at < private.game_days(1) then raise exception 'too_soon' using errcode = 'P0001'; end if;
  if p_value > l.value * (1 + private.exchange_const('value_step')) or p_value < l.value * (1 - private.exchange_const('value_step')) then raise exception 'value_jump' using errcode = 'P0001'; end if;
  select min(value) into floor_value from public.exchange_value_log where listing_id = l.id and at > now() - private.weeks(7);
  if p_value > coalesce(floor_value, l.value) * private.exchange_const('value_growth_week') then raise exception 'value_jump' using errcode = 'P0001'; end if;
  update public.exchange_listings set value = round(p_value, 2), value_reported_at = now() where id = l.id;
  insert into public.exchange_value_log (listing_id, value) values (l.id, round(p_value, 2));
  return private.exchange_nav(l) * p_value / l.value;
end $$;

create or replace function public.place_exchange_order(p_listing uuid, p_side public.exchange_side, p_shares bigint, p_price numeric, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.exchange_listings; cb numeric[]; ib text; nav numeric; o public.exchange_orders; mine public.exchange_orders;
        fill bigint; filled bigint := 0; allow bigint; buyer uuid; seller uuid; sh public.exchange_holdings; basis numeric; gross numeric; tax numeric; gtax numeric;
        bcc text; scc text; oid uuid; buyer_bot boolean; seller_bot boolean;
begin
  perform private.require_free(uid, 'trade');
  select * into l from public.exchange_listings where id = p_listing and delisted_at is null for update;
  if not found or private.is_blocked_between(uid, l.owner_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_currency <> l.currency then raise exception 'currency_mismatch' using errcode = 'P0001'; end if;
  if p_shares is null or p_shares <= 0 or p_price is null or p_price <= 0 then raise exception 'invalid_order' using errcode = 'P0001'; end if;
  nav := private.exchange_nav(l);
  if p_price < nav * private.rule_num('band.exchange_low') or p_price > nav * private.rule_num('band.exchange_high') then raise exception 'outside_band' using errcode = 'P0001'; end if;
  cb := private.exchange_close_bounds(l);
  if p_price < cb[1] or p_price > cb[2] then raise exception 'outside_day_limit' using errcode = 'P0001'; end if;
  if p_side = 'buy' and uid <> l.owner_id and p_shares > private.exchange_buyable(l, uid) then raise exception 'holder_cap' using errcode = 'P0001'; end if;
  if p_side = 'sell' and uid = l.owner_id then
    ib := private.exchange_insider_block(l);
    if ib is not null then raise exception using message = ib, errcode = 'P0001'; end if;
  end if;
  if now() - (select created_at from public.profiles where id = uid) < private.weeks(4) then raise exception 'new_account' using errcode = 'P0001'; end if;
  if p_side = 'sell' and p_shares > private.exchange_sellable(l, uid) then raise exception 'too_many' using errcode = 'P0001'; end if;
  if (select count(*) from public.exchange_orders where trader_id = uid and status = 'open') >= private.exchange_const('open_orders')::int then raise exception 'too_many_orders' using errcode = 'P0001'; end if;
  insert into public.exchange_orders (listing_id, trader_id, side, shares, remaining, price) values (l.id, uid, p_side, p_shares, p_shares, round(p_price, 4)) returning * into mine;
  oid := mine.id;
  for o in select * from public.exchange_orders x where x.listing_id = l.id and x.status = 'open' and x.side <> p_side and x.id <> mine.id
            and x.price between cb[1] and cb[2]
            and ((p_side = 'buy' and x.price <= mine.price) or (p_side = 'sell' and x.price >= mine.price))
            and not (x.side = 'sell' and x.trader_id = l.owner_id and private.exchange_insider_block(l) is not null)
            and x.trader_id <> uid and not private.linked(x.trader_id, uid) and not private.is_blocked_between(x.trader_id, uid)
          order by case when p_side = 'buy' then x.price end asc, case when p_side = 'sell' then x.price end desc, x.created_at for update loop
    exit when mine.remaining = 0;
    buyer := case when p_side = 'buy' then uid else o.trader_id end;
    seller := case when p_side = 'sell' then uid else o.trader_id end;
    select * into sh from public.exchange_holdings where listing_id = l.id and owner_id = seller for update;
    continue when coalesce(sh.shares, 0) <= 0;
    allow := private.pair_allowance(l.id, buyer, seller, l.total_shares);
    fill := least(mine.remaining, o.remaining, sh.shares, allow);
    continue when fill <= 0;
    select is_bot into buyer_bot from public.profiles where id = buyer;
    select is_bot into seller_bot from public.profiles where id = seller;
    gross := round(fill * o.price, 2);
    basis := case when sh.shares > 0 then sh.cost * fill / sh.shares else 0 end;
    select country_code into bcc from public.profiles where id = buyer;
    select country_code into scc from public.profiles where id = seller;
    tax := case when buyer_bot then 0 else round(gross * private.transfer_tax_rate(bcc), 2) end;
    gtax := case when seller_bot then 0 else round(greatest(0, gross - basis) * private.gains_tax_rate(scc), 2) end;
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

revoke execute on all functions in schema public from public, anon;
