update public.artifact_pieces set in_auction = null where in_auction in (select id from public.auctions where status = 'live');
update public.auctions set status = 'cancelled' where status = 'live';
update public.gold_wallets set held = 0 where held <> 0;

drop function if exists public.place_bid(uuid, int);
drop function if exists public.list_artifact(text, int, int, int, int);
drop function if exists private.auction_json(public.auctions, uuid);
drop function if exists private.auction_close(public.auctions);
drop function if exists private.auction_increment(int);
drop function if exists private.auction_fee(int);

alter table public.auctions add column if not exists currency text;
update public.auctions set currency = 'USD' where currency is null;
alter table public.auctions alter column currency set not null;
alter table public.auctions drop constraint if exists auctions_currency_shape;
alter table public.auctions add constraint auctions_currency_shape check (currency ~ '^[A-Z]{3}$');
alter table public.auctions drop constraint if exists auctions_start_price_check;
alter table public.auctions add constraint auctions_start_price_check check (start_price >= 1);
alter table public.auctions drop constraint if exists reserve_rules;
alter table public.auctions alter column start_price type bigint, alter column reserve type bigint, alter column sold_for type bigint, alter column fee type bigint;
alter table public.auctions add constraint reserve_rules check (reserve is null or (reserve >= start_price and reserve <= start_price * 50));
alter table public.auction_bids alter column amount type bigint;
alter table public.auction_notices alter column price type bigint, alter column fee type bigint;
alter table public.auction_notices add column if not exists currency text;

create or replace function private.auction_increment(price bigint) returns bigint language sql immutable as $$
  select greatest(1, ceil(price * 0.05)::bigint);
$$;

create or replace function private.auction_fee(price bigint) returns bigint language sql immutable as $$
  select case when price <= 0 then 0 else greatest(1, price / 10) end;
$$;

create or replace function private.auction_min_start(cur text) returns bigint language sql stable security definer set search_path = '' as $$
  select greatest(1, round(10 * private.currency_scale(cur))::bigint);
$$;

create or replace function private.auction_ceiling(def text, cur text) returns bigint language plpgsql stable security definer set search_path = '' as $$
declare sc numeric := private.currency_scale(cur); med numeric; n int; r public.artifact_rarity;
begin
  select percentile_cont(0.5) within group (order by x.sold_for / private.currency_scale(x.currency)), count(*) into med, n from (
    select a.sold_for, a.currency from public.auctions a where a.def_id = def and a.status = 'sold' order by a.ends_at desc limit 10) x;
  if n >= 3 then return ceil(med * 20 * sc)::bigint; end if;
  select rarity into r from public.artifact_defs where id = def;
  return ceil(sc * case r when 'common' then 100000 when 'rare' then 1000000 when 'epic' then 10000000 else 100000000 end)::bigint;
end $$;

create or replace function private.bid_headroom(uid uuid, cur text) returns numeric language sql stable security definer set search_path = '' as $$
  select (greatest(10000, coalesce((select e.net_worth from public.leaderboard_entries e where e.user_id = uid), 0))
          - coalesce((select sum(t.amount / private.currency_scale(a.currency))
                        from public.auctions a cross join lateral private.auction_top(a.id) t
                       where a.status = 'live' and t.bidder_id = uid), 0)) * private.currency_scale(cur);
$$;

create or replace function private.auction_close(a public.auctions) returns void language plpgsql security definer set search_path = '' as $$
declare top public.auction_bids; v_fee bigint; done text[] := '{}'; col text; reward text; nm text; cc text;
begin
  top := private.auction_top(a.id);
  if top.id is not null and top.bidder_id is not null and (a.reserve is null or top.amount >= a.reserve) then
    v_fee := private.auction_fee(top.amount);
    update public.auctions set status = 'sold', sold_for = top.amount, winner_id = top.bidder_id, fee = v_fee where id = a.id;
    select name into nm from public.artifact_defs where id = a.def_id;
    perform private.settle(top.bidder_id, -top.amount, a.currency, 'auction_win', a.id::text, 'Won at auction: ' || nm,
      jsonb_build_object('auctionID', a.id, 'defID', a.def_id, 'serial', a.serial));
    perform private.settle(a.seller_id, top.amount - v_fee, a.currency, 'auction_sale', a.id::text, 'Sold at auction: ' || nm,
      jsonb_build_object('auctionID', a.id, 'defID', a.def_id, 'serial', a.serial, 'fee', v_fee));
    select country_code into cc from public.profiles where id = a.seller_id;
    perform private.treasury_post(cc, v_fee, 'auction_fee', a.id::text);
    update public.artifact_pieces set owner_id = top.bidder_id, in_auction = null, acquired_at = now() where def_id = a.def_id and serial = a.serial;
    select collection_id into col from public.artifact_defs where id = a.def_id;
    select reward_id into reward from public.artifact_collections where id = col;
    if not exists (select 1 from public.artifact_defs d where d.collection_id = col
                    and not exists (select 1 from public.artifact_pieces p where p.def_id = d.id and p.owner_id = top.bidder_id)) then
      insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (top.bidder_id, reward, 'collection:' || col) on conflict do nothing;
      if found then done := array[col]; end if;
    end if;
    insert into public.auction_notices (user_id, auction_id, role, status, price, fee, currency, completed) values
      (top.bidder_id, a.id, 'winner', 'sold', top.amount, v_fee, a.currency, done), (a.seller_id, a.id, 'seller', 'sold', top.amount, v_fee, a.currency, '{}');
  else
    update public.auctions set status = 'unsold' where id = a.id;
    if top.id is not null and top.bidder_id is not null then
      insert into public.auction_notices (user_id, auction_id, role, status, price, currency) values (top.bidder_id, a.id, 'bidder', 'unsold', top.amount, a.currency);
    end if;
    update public.artifact_pieces set in_auction = null where def_id = a.def_id and serial = a.serial;
    insert into public.auction_notices (user_id, auction_id, role, status, price, currency)
      values (a.seller_id, a.id, 'seller', 'unsold', coalesce(top.amount, a.start_price), a.currency);
  end if;
end $$;

create or replace function private.auction_json(a public.auctions, viewer uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare top public.auction_bids; price bigint; minimum bigint;
begin
  top := private.auction_top(a.id);
  price := coalesce(top.amount, a.start_price);
  minimum := case when top.id is null then a.start_price else top.amount + private.auction_increment(top.amount) end;
  return jsonb_build_object('id', a.id, 'item', jsonb_build_object('defID', a.def_id, 'serial', a.serial), 'seller', a.seller_id,
    'sellerName', private.display_name(a.seller_id), 'currency', a.currency, 'startPrice', a.start_price,
    'reserve', case when a.seller_id = viewer then to_jsonb(a.reserve) else 'null'::jsonb end,
    'reserveMet', a.reserve is null or (top.id is not null and top.amount >= a.reserve),
    'startsAt', extract(epoch from a.starts_at), 'endsAt', extract(epoch from a.ends_at), 'durationHours', a.duration_hours,
    'extensions', a.extensions, 'status', a.status, 'soldFor', a.sold_for, 'currentPrice', price, 'minimumBid', minimum,
    'leader', top.bidder_id, 'leaderName', case when top.id is null then null else private.display_name(top.bidder_id) end,
    'bids', coalesce((select jsonb_agg(jsonb_build_object('bidder', b.bidder_id, 'name', private.display_name(b.bidder_id), 'amount', b.amount, 'at', extract(epoch from b.placed_at)) order by b.id)
                        from public.auction_bids b where b.auction_id = a.id), '[]'::jsonb));
end $$;

create or replace function public.auctions_snapshot() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); notices jsonb;
begin
  perform private.settle_due_auctions();
  with n as (update public.auction_notices set seen = true where user_id = uid and not seen returning *)
  select coalesce(jsonb_agg(jsonb_build_object('auctionID', auction_id, 'role', role, 'status', status, 'price', price, 'fee', fee, 'currency', currency, 'completed', completed) order by id), '[]'::jsonb)
    into notices from n;
  return jsonb_build_object('now', extract(epoch from now()),
    'auctions', coalesce((select jsonb_agg(private.auction_json(a, uid) order by a.ends_at) from public.auctions a
                           where a.status = 'live' and not private.is_blocked_between(uid, a.seller_id)), '[]'::jsonb),
    'wallet', public.my_gold(), 'settled', notices);
end $$;

create or replace function public.list_artifact(p_def text, p_serial int, p_start_price bigint, p_reserve bigint, p_duration_hours int, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); a public.auctions; pc public.artifact_pieces;
begin
  perform private.require_free(uid, 'gold');
  if p_duration_hours not in (1, 6, 24) or p_currency is null or p_currency !~ '^[A-Z]{3}$' or p_start_price is null then raise exception 'invalid_listing' using errcode = 'P0001'; end if;
  if now() - (select created_at from public.profiles where id = uid) < private.weeks(4) then raise exception 'new_account' using errcode = 'P0001'; end if;
  if p_start_price < private.auction_min_start(p_currency) then raise exception 'start_price_too_low' using errcode = 'P0001'; end if;
  if p_start_price > private.auction_ceiling(p_def, p_currency) then raise exception 'price_outside_market' using errcode = 'P0001'; end if;
  if p_reserve is not null and (p_reserve < p_start_price or p_reserve > p_start_price * 50) then raise exception 'invalid_reserve' using errcode = 'P0001'; end if;
  select * into pc from public.artifact_pieces where def_id = p_def and serial = p_serial and owner_id = uid for update;
  if not found then raise exception 'not_yours' using errcode = 'P0001'; end if;
  if pc.in_auction is not null then raise exception 'already_listed' using errcode = 'P0001'; end if;
  insert into public.auctions (def_id, serial, seller_id, start_price, reserve, ends_at, duration_hours, currency)
    values (p_def, p_serial, uid, p_start_price, p_reserve, now() + make_interval(hours => p_duration_hours), p_duration_hours, p_currency) returning * into a;
  update public.artifact_pieces set in_auction = a.id where def_id = p_def and serial = p_serial;
  return private.auction_json(a, uid);
end $$;

create or replace function public.place_bid(p_auction uuid, p_amount bigint) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); a public.auctions; top public.auction_bids; minimum bigint; new_end timestamptz; room numeric;
begin
  perform private.require_free(uid, 'gold');
  select * into a from public.auctions where id = p_auction for update;
  if not found or private.is_blocked_between(uid, a.seller_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if a.status <> 'live' or a.ends_at <= now() then raise exception 'not_live' using errcode = 'P0001'; end if;
  if a.seller_id = uid or private.linked(uid, a.seller_id) then raise exception 'seller_cannot_bid' using errcode = 'P0001'; end if;
  if now() - (select created_at from public.profiles where id = uid) < private.weeks(4) then raise exception 'new_account' using errcode = 'P0001'; end if;
  top := private.auction_top(a.id);
  if top.bidder_id = uid then raise exception 'already_leading' using errcode = 'P0001'; end if;
  minimum := case when top.id is null then a.start_price else top.amount + private.auction_increment(top.amount) end;
  if p_amount is null or p_amount < minimum then raise exception 'too_low:%', minimum using errcode = 'P0001'; end if;
  if p_amount > private.auction_ceiling(a.def_id, a.currency) then raise exception 'price_outside_market' using errcode = 'P0001'; end if;
  room := private.bid_headroom(uid, a.currency);
  if p_amount > room then raise exception 'not_enough_cash:%', ceil(p_amount - room) using errcode = 'P0001'; end if;
  insert into public.auction_bids (auction_id, bidder_id, amount) values (a.id, uid, p_amount);
  if a.extensions < 12 and a.ends_at - now() <= interval '120 seconds' then
    new_end := now() + interval '120 seconds';
    if new_end > a.ends_at then update public.auctions set ends_at = new_end, extensions = extensions + 1 where id = a.id; end if;
  end if;
  select * into a from public.auctions where id = a.id;
  return private.auction_json(a, uid);
end $$;

create or replace function private.activity_auction() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'sold' and old.status = 'live' then
    perform private.log_activity(new.seller_id, 'auctionSold', null, (select name from public.artifact_defs where id = new.def_id), 'auction:' || new.id);
  end if;
  return new;
end $$;
drop trigger if exists auction_sold_activity on public.auctions;
create trigger auction_sold_activity after update of status on public.auctions for each row execute function private.activity_auction();

revoke execute on all functions in schema public from public, anon;
grant execute on function public.list_artifact(text, int, bigint, bigint, int, text), public.place_bid(uuid, bigint) to authenticated;
