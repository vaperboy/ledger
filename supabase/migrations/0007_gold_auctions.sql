-- Gold wallet, collectible artifacts and timed auctions. Mirrors the engine's GoldWallet, ArtifactCatalog and AuctionRules.
-- Gold is premium currency held on the server: it is only ever spent (or held while a bid leads), never turned into game money, and it
-- leaves a wallet only through a purchase, a sale fee or a won auction. Clients cannot write any of these tables; every change is one of
-- the functions below. Gold enters only through grant_gold_purchase, which the payment webhook (service role) calls after it has
-- verified the store receipt.

create type public.artifact_rarity as enum ('common', 'rare', 'epic', 'legendary');
create type public.auction_status as enum ('live', 'sold', 'unsold', 'cancelled');

create table public.gold_packs (
  id text primary key,
  name text not null,
  price_cents int not null check (price_cents > 0),
  gold int not null check (gold > 0)
);
insert into public.gold_packs (id, name, price_cents, gold) values
  ('gold.pouch', 'Pouch', 199, 200), ('gold.purse', 'Purse', 499, 550), ('gold.chest', 'Chest', 999, 1200),
  ('gold.vault', 'Vault', 1999, 2600), ('gold.hoard', 'Hoard', 4999, 7000);

create table public.gold_wallets (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  balance int not null default 0 check (balance >= 0),
  -- Part of the balance reserved for bids that currently lead.
  held int not null default 0 check (held >= 0),
  first_purchase_done boolean not null default false,
  constraint held_within_balance check (held <= balance)
);

create table public.gold_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  delta int not null,
  kind text not null check (char_length(kind) between 1 and 40),
  ref text not null default '' check (char_length(ref) <= 80),
  created_at timestamptz not null default now()
);
create index gold_ledger_user on public.gold_ledger (user_id, created_at desc);

-- One row per store transaction, so a receipt that is delivered twice credits once.
create table public.gold_purchases (
  store_transaction_id text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  pack_id text not null references public.gold_packs (id),
  gold int not null check (gold > 0),
  created_at timestamptz not null default now()
);

create table public.artifact_collections (
  id text primary key,
  name text not null,
  reward_id text not null
);
create table public.artifact_defs (
  id text primary key,
  name text not null,
  collection_id text not null references public.artifact_collections (id),
  rarity public.artifact_rarity not null,
  -- How many exist; the serial of a piece runs from 1 to this.
  edition int not null check (edition > 0)
);
insert into public.artifact_collections (id, name, reward_id) values
  ('counting', 'Counting House', 'gold.coll.counting'), ('harbour', 'Harbour Trade', 'gold.coll.harbour'),
  ('market', 'Market Square', 'gold.coll.market'), ('archive', 'Town Archive', 'gold.coll.archive');
insert into public.artifact_defs (id, name, collection_id, rarity, edition) values
  ('abacus', 'Boxwood abacus', 'counting', 'common', 5000), ('scales', 'Brass scales', 'counting', 'rare', 1500),
  ('strongbox', 'Iron strongbox', 'counting', 'epic', 500), ('seal', 'Gilt counting seal', 'counting', 'legendary', 100),
  ('rope', 'Tarred rope coil', 'harbour', 'common', 5000), ('lantern', 'Ship''s lantern', 'harbour', 'rare', 1500),
  ('chart', 'Sea chart', 'harbour', 'epic', 500), ('compass', 'Silver compass', 'harbour', 'legendary', 100),
  ('token', 'Clay market token', 'market', 'common', 5000), ('banner', 'Silk stall banner', 'market', 'rare', 1500),
  ('bell', 'Merchant''s bell', 'market', 'epic', 500), ('weights', 'Golden weights', 'market', 'legendary', 100),
  ('stamp', 'Ink stamp', 'archive', 'common', 5000), ('map', 'Old town map', 'archive', 'rare', 1500),
  ('scroll', 'Charter scroll', 'archive', 'epic', 500), ('charter', 'Royal charter', 'archive', 'legendary', 100);

-- Each numbered piece exists once. The piece has an owner; while it is on auction it stays with the seller and points at the auction.
create table public.artifact_pieces (
  def_id text not null references public.artifact_defs (id),
  serial int not null check (serial >= 1),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  in_auction uuid,
  acquired_at timestamptz not null default now(),
  primary key (def_id, serial)
);
create index artifact_pieces_owner on public.artifact_pieces (owner_id);

create function private.check_piece_serial() returns trigger language plpgsql as $$
begin
  if new.serial > (select edition from public.artifact_defs where id = new.def_id) then raise exception 'invalid_serial' using errcode = 'P0001'; end if;
  return new;
end $$;
create trigger artifact_pieces_serial before insert or update of serial, def_id on public.artifact_pieces for each row execute function private.check_piece_serial();

-- The cosmetic a finished collection pays, once ever.
create table public.cosmetic_grants (
  user_id uuid not null references public.profiles (id) on delete cascade,
  cosmetic_id text not null,
  source text not null,
  granted_at timestamptz not null default now(),
  primary key (user_id, cosmetic_id)
);

create table public.auctions (
  id uuid primary key default gen_random_uuid(),
  def_id text not null,
  serial int not null,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  start_price int not null check (start_price >= 10),
  -- Hidden minimum: below it the piece is not sold. Bidders only learn whether it has been met.
  reserve int,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  duration_hours int not null check (duration_hours in (1, 6, 24)),
  extensions int not null default 0 check (extensions between 0 and 12),
  status public.auction_status not null default 'live',
  sold_for int,
  winner_id uuid references public.profiles (id) on delete set null,
  fee int not null default 0,
  foreign key (def_id, serial) references public.artifact_pieces (def_id, serial),
  constraint reserve_rules check (reserve is null or (reserve >= start_price and reserve <= start_price * 50))
);
create index auctions_live on public.auctions (ends_at) where status = 'live';
create unique index auctions_piece_live on public.auctions (def_id, serial) where status = 'live';

create table public.auction_bids (
  id bigint generated always as identity primary key,
  auction_id uuid not null references public.auctions (id) on delete cascade,
  bidder_id uuid references public.profiles (id) on delete set null,
  amount int not null check (amount > 0),
  placed_at timestamptz not null default now()
);
create index auction_bids_auction on public.auction_bids (auction_id, id desc);

-- What a player is told about an auction that ended and touched them (shown once).
create table public.auction_notices (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  auction_id uuid not null references public.auctions (id) on delete cascade,
  role text not null check (role in ('seller', 'winner', 'bidder')),
  status public.auction_status not null,
  price int not null default 0,
  fee int not null default 0,
  completed text[] not null default '{}',
  seen boolean not null default false,
  created_at timestamptz not null default now()
);
create index auction_notices_unseen on public.auction_notices (user_id) where not seen;

alter table public.gold_packs enable row level security;
alter table public.gold_wallets enable row level security;
alter table public.gold_ledger enable row level security;
alter table public.gold_purchases enable row level security;
alter table public.artifact_collections enable row level security;
alter table public.artifact_defs enable row level security;
alter table public.artifact_pieces enable row level security;
alter table public.cosmetic_grants enable row level security;
alter table public.auctions enable row level security;
alter table public.auction_bids enable row level security;
alter table public.auction_notices enable row level security;
revoke all on public.gold_packs, public.gold_wallets, public.gold_ledger, public.gold_purchases, public.artifact_collections, public.artifact_defs,
  public.artifact_pieces, public.cosmetic_grants, public.auctions, public.auction_bids, public.auction_notices from anon, authenticated;
grant select on public.gold_packs, public.gold_wallets, public.gold_ledger, public.gold_purchases, public.artifact_collections, public.artifact_defs,
  public.artifact_pieces, public.cosmetic_grants, public.auction_notices to authenticated;

create policy gold_packs_read on public.gold_packs for select to authenticated using (true);
create policy artifact_collections_read on public.artifact_collections for select to authenticated using (true);
create policy artifact_defs_read on public.artifact_defs for select to authenticated using (true);
create policy gold_wallets_own on public.gold_wallets for select to authenticated using (user_id = auth.uid());
create policy gold_ledger_own on public.gold_ledger for select to authenticated using (user_id = auth.uid());
create policy gold_purchases_own on public.gold_purchases for select to authenticated using (user_id = auth.uid());
create policy artifact_pieces_own on public.artifact_pieces for select to authenticated using (owner_id = auth.uid());
create policy cosmetic_grants_own on public.cosmetic_grants for select to authenticated using (user_id = auth.uid());
create policy auction_notices_own on public.auction_notices for select to authenticated using (user_id = auth.uid());
-- Auctions and bids are read through auctions_snapshot() (it hides the reserve and blocked pairs).

create or replace function private.auctions_open(uid uuid) returns boolean language sql stable as $$
  select exists (select 1 from public.auctions where status = 'live' and seller_id = uid)
      or exists (select 1 from public.auction_bids b join public.auctions a on a.id = b.auction_id
                  where b.bidder_id = uid and a.status = 'live' and b.id = (select max(id) from public.auction_bids where auction_id = a.id));
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Wallet primitives (private: other functions call them, clients never do)
-- ---------------------------------------------------------------------------------------------------------------------
create function private.wallet(uid uuid) returns public.gold_wallets language plpgsql security definer set search_path = '' as $$
declare w public.gold_wallets;
begin
  insert into public.gold_wallets (user_id) values (uid) on conflict do nothing;
  select * into w from public.gold_wallets where user_id = uid for update;
  return w;
end $$;

-- Spends gold that is not held; a short wallet raises not_enough_gold:<missing>.
create function private.gold_spend(uid uuid, amount int, kind text, ref text default '') returns void language plpgsql security definer set search_path = '' as $$
declare w public.gold_wallets := private.wallet(uid);
begin
  if amount < 0 or amount > w.balance - w.held then raise exception 'not_enough_gold:%', greatest(0, amount - (w.balance - w.held)) using errcode = 'P0001'; end if;
  update public.gold_wallets set balance = balance - amount where user_id = uid;
  insert into public.gold_ledger (user_id, delta, kind, ref) values (uid, -amount, kind, coalesce(ref, ''));
end $$;

create function private.gold_credit(uid uuid, amount int, kind text, ref text default '') returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.wallet(uid);
  update public.gold_wallets set balance = balance + greatest(0, amount) where user_id = uid;
  insert into public.gold_ledger (user_id, delta, kind, ref) values (uid, greatest(0, amount), kind, coalesce(ref, ''));
end $$;

-- Called by the payment webhook with the service role, after the store receipt has been verified. Idempotent on the store transaction id.
-- The first pack ever bought carries a one-time bonus of half as much gold again.
create function public.grant_gold_purchase(p_user uuid, p_pack text, p_transaction text) returns int language plpgsql security definer set search_path = '' as $$
declare pk public.gold_packs; w public.gold_wallets; total int;
begin
  select * into pk from public.gold_packs where id = p_pack;
  if not found then raise exception 'unknown_pack' using errcode = 'P0001'; end if;
  if exists (select 1 from public.gold_purchases where store_transaction_id = p_transaction) then return 0; end if;
  w := private.wallet(p_user);
  total := pk.gold + case when w.first_purchase_done then 0 else pk.gold / 2 end;
  insert into public.gold_purchases (store_transaction_id, user_id, pack_id, gold) values (p_transaction, p_user, p_pack, total);
  update public.gold_wallets set first_purchase_done = true where user_id = p_user;
  perform private.gold_credit(p_user, total, 'purchase', p_transaction);
  return total;
end $$;

create function public.my_gold() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); w public.gold_wallets;
begin
  select * into w from public.gold_wallets where user_id = uid;
  return jsonb_build_object('balance', coalesce(w.balance, 0), 'held', coalesce(w.held, 0), 'available', coalesce(w.balance - w.held, 0),
    'firstPurchaseDone', coalesce(w.first_purchase_done, false),
    'cabinet', coalesce((select jsonb_agg(jsonb_build_object('defID', def_id, 'serial', serial, 'inAuction', in_auction) order by def_id, serial)
                           from public.artifact_pieces where owner_id = uid), '[]'::jsonb),
    'cosmetics', coalesce((select jsonb_agg(cosmetic_id) from public.cosmetic_grants where user_id = uid), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Auction rules
-- ---------------------------------------------------------------------------------------------------------------------
create function private.auction_increment(price int) returns int language sql immutable as $$
  select case when price < 100 then 5 when price < 500 then 10 when price < 2000 then 25 when price < 10000 then 100 else 500 end;
$$;
create function private.auction_fee(price int) returns int language sql immutable as $$ select case when price <= 0 then 0 else greatest(1, price * 10 / 100) end; $$;

create function private.auction_top(aid uuid) returns public.auction_bids language sql stable security definer set search_path = '' as $$
  select * from public.auction_bids where auction_id = aid order by id desc limit 1;
$$;

-- Gives the winner the piece, pays the seller less the fee (the fee is burned) and hands out a finished collection's cosmetic once.
create function private.auction_close(a public.auctions) returns void language plpgsql security definer set search_path = '' as $$
declare top public.auction_bids; v_fee int; done text[] := '{}'; col text; reward text;
begin
  top := private.auction_top(a.id);
  if top.id is not null and (a.reserve is null or top.amount >= a.reserve) then
    v_fee := private.auction_fee(top.amount);
    update public.auctions set status = 'sold', sold_for = top.amount, winner_id = top.bidder_id, fee = v_fee where id = a.id;
    update public.gold_wallets set held = held - top.amount, balance = balance - top.amount where user_id = top.bidder_id;
    insert into public.gold_ledger (user_id, delta, kind, ref) values (top.bidder_id, -top.amount, 'auction_win', a.id::text);
    perform private.gold_credit(a.seller_id, top.amount - v_fee, 'auction_sale', a.id::text);
    update public.artifact_pieces set owner_id = top.bidder_id, in_auction = null, acquired_at = now() where def_id = a.def_id and serial = a.serial;
    select collection_id into col from public.artifact_defs where id = a.def_id;
    select reward_id into reward from public.artifact_collections where id = col;
    if not exists (select 1 from public.artifact_defs d where d.collection_id = col
                    and not exists (select 1 from public.artifact_pieces p where p.def_id = d.id and p.owner_id = top.bidder_id)) then
      insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (top.bidder_id, reward, 'collection:' || col) on conflict do nothing;
      if found then done := array[col]; end if;
    end if;
    insert into public.auction_notices (user_id, auction_id, role, status, price, fee, completed) values
      (top.bidder_id, a.id, 'winner', 'sold', top.amount, v_fee, done), (a.seller_id, a.id, 'seller', 'sold', top.amount, v_fee, '{}');
  else
    update public.auctions set status = 'unsold' where id = a.id;
    if top.id is not null then
      update public.gold_wallets set held = held - top.amount where user_id = top.bidder_id;
      insert into public.auction_notices (user_id, auction_id, role, status, price) values (top.bidder_id, a.id, 'bidder', 'unsold', top.amount);
    end if;
    update public.artifact_pieces set in_auction = null where def_id = a.def_id and serial = a.serial;
    insert into public.auction_notices (user_id, auction_id, role, status, price) values (a.seller_id, a.id, 'seller', 'unsold', coalesce(top.amount, a.start_price));
  end if;
end $$;

-- Closes every auction whose time is up. Safe to run at any time (the platform also schedules it).
create function private.settle_due_auctions() returns int language plpgsql security definer set search_path = '' as $$
declare a public.auctions; n int := 0;
begin
  for a in select * from public.auctions where status = 'live' and ends_at <= now() order by ends_at for update skip locked loop
    perform private.auction_close(a);
    n := n + 1;
  end loop;
  return n;
end $$;

create function private.auction_json(a public.auctions, viewer uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare top public.auction_bids; price int; minimum int;
begin
  top := private.auction_top(a.id);
  price := coalesce(top.amount, a.start_price);
  minimum := case when top.id is null then a.start_price else top.amount + private.auction_increment(top.amount) end;
  return jsonb_build_object('id', a.id, 'item', jsonb_build_object('defID', a.def_id, 'serial', a.serial), 'seller', a.seller_id,
    'sellerName', private.display_name(a.seller_id), 'startPrice', a.start_price,
    'reserve', case when a.seller_id = viewer then to_jsonb(a.reserve) else 'null'::jsonb end,
    'reserveMet', a.reserve is null or (top.id is not null and top.amount >= a.reserve),
    'startsAt', extract(epoch from a.starts_at), 'endsAt', extract(epoch from a.ends_at), 'durationHours', a.duration_hours,
    'extensions', a.extensions, 'status', a.status, 'soldFor', a.sold_for, 'currentPrice', price, 'minimumBid', minimum,
    'leader', top.bidder_id, 'leaderName', case when top.id is null then null else private.display_name(top.bidder_id) end,
    'bids', coalesce((select jsonb_agg(jsonb_build_object('bidder', b.bidder_id, 'name', private.display_name(b.bidder_id), 'amount', b.amount, 'at', extract(epoch from b.placed_at)) order by b.id)
                        from public.auction_bids b where b.auction_id = a.id), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Auction functions
-- ---------------------------------------------------------------------------------------------------------------------
-- Everything the screen needs after settling what is due: live auctions (not of blocked players), the caller's wallet, and what ended for them.
create function public.auctions_snapshot() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); notices jsonb;
begin
  perform private.settle_due_auctions();
  with n as (update public.auction_notices set seen = true where user_id = uid and not seen returning *)
  select coalesce(jsonb_agg(jsonb_build_object('auctionID', auction_id, 'role', role, 'status', status, 'price', price, 'fee', fee, 'completed', completed) order by id), '[]'::jsonb)
    into notices from n;
  return jsonb_build_object('now', extract(epoch from now()),
    'auctions', coalesce((select jsonb_agg(private.auction_json(a, uid) order by a.ends_at) from public.auctions a
                           where a.status = 'live' and not private.is_blocked_between(uid, a.seller_id)), '[]'::jsonb),
    'wallet', public.my_gold(), 'settled', notices);
end $$;

create function public.list_artifact(p_def text, p_serial int, p_start_price int, p_reserve int, p_duration_hours int) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); a public.auctions; pc public.artifact_pieces;
begin
  perform private.require_free(uid, 'gold');
  if p_duration_hours not in (1, 6, 24) then raise exception 'invalid_listing' using errcode = 'P0001'; end if;
  if p_start_price < 10 then raise exception 'start_price_too_low' using errcode = 'P0001'; end if;
  if p_reserve is not null and (p_reserve < p_start_price or p_reserve > p_start_price * 50) then raise exception 'invalid_reserve' using errcode = 'P0001'; end if;
  select * into pc from public.artifact_pieces where def_id = p_def and serial = p_serial and owner_id = uid for update;
  if not found then raise exception 'not_yours' using errcode = 'P0001'; end if;
  if pc.in_auction is not null then raise exception 'already_listed' using errcode = 'P0001'; end if;
  insert into public.auctions (def_id, serial, seller_id, start_price, reserve, ends_at, duration_hours)
    values (p_def, p_serial, uid, p_start_price, p_reserve, now() + make_interval(hours => p_duration_hours), p_duration_hours) returning * into a;
  update public.artifact_pieces set in_auction = a.id where def_id = p_def and serial = p_serial;
  return private.auction_json(a, uid);
end $$;

-- A bid is held while it leads and returned when beaten. A bid in the last two minutes pushes the end out to two minutes after it
-- (at most twelve times), so an auction cannot be sniped and cannot run for ever.
create function public.place_bid(p_auction uuid, p_amount int) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); a public.auctions; top public.auction_bids; minimum int; w public.gold_wallets; new_end timestamptz;
begin
  perform private.require_free(uid, 'gold');
  select * into a from public.auctions where id = p_auction for update;
  if not found or private.is_blocked_between(uid, a.seller_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if a.status <> 'live' or a.ends_at <= now() then raise exception 'not_live' using errcode = 'P0001'; end if;
  if a.seller_id = uid or private.linked(uid, a.seller_id) then raise exception 'seller_cannot_bid' using errcode = 'P0001'; end if;
  top := private.auction_top(a.id);
  if top.bidder_id = uid then raise exception 'already_leading' using errcode = 'P0001'; end if;
  minimum := case when top.id is null then a.start_price else top.amount + private.auction_increment(top.amount) end;
  if p_amount < minimum then raise exception 'too_low:%', minimum using errcode = 'P0001'; end if;
  w := private.wallet(uid);
  if p_amount > w.balance - w.held then raise exception 'not_enough_gold:%', p_amount - (w.balance - w.held) using errcode = 'P0001'; end if;
  update public.gold_wallets set held = held + p_amount where user_id = uid;
  if top.id is not null and top.bidder_id is not null then update public.gold_wallets set held = held - top.amount where user_id = top.bidder_id; end if;
  insert into public.auction_bids (auction_id, bidder_id, amount) values (a.id, uid, p_amount);
  if a.extensions < 12 and a.ends_at - now() <= interval '120 seconds' then
    new_end := now() + interval '120 seconds';
    if new_end > a.ends_at then update public.auctions set ends_at = new_end, extensions = extensions + 1 where id = a.id; end if;
  end if;
  select * into a from public.auctions where id = a.id;
  return private.auction_json(a, uid);
end $$;

-- Takes a listing back while nobody has bid.
create function public.cancel_auction(p_auction uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); a public.auctions;
begin
  select * into a from public.auctions where id = p_auction and seller_id = uid and status = 'live' for update;
  if not found then raise exception 'not_live' using errcode = 'P0001'; end if;
  if exists (select 1 from public.auction_bids where auction_id = a.id) then raise exception 'has_bids' using errcode = 'P0001'; end if;
  update public.auctions set status = 'cancelled' where id = a.id;
  update public.artifact_pieces set in_auction = null where def_id = a.def_id and serial = a.serial;
end $$;

-- Staff / the box-opening function put a numbered piece into a cabinet (service role only).
create function public.grant_artifact(p_user uuid, p_def text, p_serial int) returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.artifact_pieces (def_id, serial, owner_id) values (p_def, p_serial, p_user);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.my_gold(), public.auctions_snapshot(), public.list_artifact(text, int, int, int, int),
  public.place_bid(uuid, int), public.cancel_auction(uuid) to authenticated;
revoke execute on function public.grant_gold_purchase(uuid, text, text), public.grant_artifact(uuid, text, int) from authenticated;
grant execute on function public.grant_gold_purchase(uuid, text, text), public.grant_artifact(uuid, text, int) to service_role;
