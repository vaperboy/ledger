-- Gold economy on the server: wallet, boxes, pity, cabinet, cosmetics, pass ownership and claims,
-- purchases and money packs live here, tied to the account. The app only shows what this returns.

-- Catalogue (filled from the content files by supabase/tools/store_catalog.py).
create table private.store_box_kinds (kind text primary key, price int not null check (price >= 0), card_pack boolean not null default false);
create table private.store_box_rows (
  kind text not null, pos int not null, rarity text not null, prize text not null, amount int not null default 0, weight int not null check (weight > 0),
  primary key (kind, pos)
);
create table private.store_box_bundles (id text primary key, kind text not null, count int not null check (count > 0), price int not null check (price > 0));
create table private.store_items (
  id text primary key, kind text not null check (kind in ('artifact', 'profileCard', 'companyCard')), rarity text not null,
  collection text, theme text not null default 'classic', bound boolean not null default false
);
create table private.store_collections (id text primary key, reward_id text not null, theme text not null default 'classic');
create table private.store_cosmetics (
  id text primary key, kind text not null, rarity text not null, source text not null, price int, theme text not null default 'classic', bound boolean not null default false
);
create table private.store_seasons (season int primary key, theme text not null, founder boolean not null, starts date not null);
create table private.store_pass_rewards (
  season int not null, track text not null check (track in ('f', 'p')), tier int not null, reward_id text not null, kind text not null, amount int not null default 0,
  primary key (season, track, tier)
);
create table private.store_level_rewards (level int primary key, gold int not null check (gold >= 0));
create table private.store_level_cards (level int not null, card_id text not null, primary key (level, card_id));
create table private.store_retired (id text primary key, gold int not null check (gold >= 0));
create table private.store_gold_products (
  product_id text primary key, kind text not null check (kind in ('gold', 'pass', 'perk', 'plan')), gold int not null default 0, box_kind text, box_count int not null default 0
);
create table private.store_money_packs (id text primary key, gold int not null check (gold > 0), bonus_percent int not null default 0, free boolean not null default false);
create table private.store_services (id text primary key, price int not null check (price > 0));
create table private.store_config (key text primary key, at timestamptz not null);
-- Accounts made before this migration may bring their phone's wallet over in full; later accounts bring items only.
insert into private.store_config (key, at) values ('import_cutoff', now()) on conflict (key) do nothing;

-- Per account state.
alter table public.gold_wallets
  add column debt int not null default 0 check (debt >= 0),
  add column pity int not null default 0 check (pity between 0 and 100),
  add column boxes_opened int not null default 0,
  add column level_gold_paid int not null default 0,
  add column level_day int not null default 0,
  add column level_day_base int not null default 0,
  add column streak_count int not null default 0,
  add column streak_best int not null default 0,
  add column streak_day int not null default 0;

create table public.gold_box_stock (
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null,
  count int not null default 0 check (count >= 0),
  primary key (user_id, kind)
);

create table public.store_cabinet (
  user_id uuid not null references public.profiles (id) on delete cascade,
  def_id text not null,
  serial int not null check (serial >= 1),
  origin text not null default 'found' check (origin in ('found', 'acquired', 'bought')),
  source text not null default 'box',
  acquired_at timestamptz not null default now(),
  primary key (user_id, def_id, serial)
);

create table public.store_collections_done (
  user_id uuid not null references public.profiles (id) on delete cascade,
  collection_id text not null,
  done_at timestamptz not null default now(),
  primary key (user_id, collection_id)
);

create table public.store_transactions (
  original_transaction_id text primary key check (char_length(original_transaction_id) between 1 and 64),
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id text not null,
  transaction_id text not null,
  environment text not null default '',
  gold int not null default 0,
  box_kind text,
  box_count int not null default 0,
  season int,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  clawed int not null default 0,
  debt_added int not null default 0
);
create index store_transactions_user on public.store_transactions (user_id);

create table public.store_perks (
  user_id uuid not null references public.profiles (id) on delete cascade,
  perk text not null check (perk in ('pro', 'founder')),
  original_transaction_id text not null,
  gold int not null default 0,
  granted_at timestamptz not null default now(),
  primary key (user_id, perk)
);

create table public.store_plans (
  original_transaction_id text not null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id text not null,
  expires_at timestamptz,
  revoked_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (original_transaction_id, user_id)
);

create table public.pass_owners (
  user_id uuid not null references public.profiles (id) on delete cascade,
  season int not null,
  source text not null,
  bonus_tiers int not null default 0 check (bonus_tiers between 0 and 30),
  granted_at timestamptz not null default now(),
  primary key (user_id, season)
);

create table public.pass_claims (
  user_id uuid not null references public.profiles (id) on delete cascade,
  season int not null,
  track text not null check (track in ('f', 'p')),
  tier int not null check (tier between 1 and 30),
  reward_id text not null,
  claimed_at timestamptz not null default now(),
  primary key (user_id, season, track, tier)
);

create table public.store_requests (
  user_id uuid not null references public.profiles (id) on delete cascade,
  request_id text not null check (char_length(request_id) between 8 and 64),
  kind text not null,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (user_id, request_id)
);
create index store_requests_recent on public.store_requests (user_id, created_at desc);

-- Game money owed to the player's save: money packs, free packs and box cash prizes, paid by the app once.
create table public.money_claims (
  id text not null check (char_length(id) between 8 and 80),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('pack', 'free', 'prize')),
  pack_id text,
  gold int not null default 0,
  amount int not null default 0,
  day int not null,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  primary key (user_id, id)
);
create index money_claims_user on public.money_claims (user_id, created_at desc);

create table public.store_refunds (
  user_id uuid not null references public.profiles (id) on delete cascade,
  item_id text not null,
  gold int not null default 0,
  paid_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

create table public.level_card_grants (
  user_id uuid not null references public.profiles (id) on delete cascade,
  card_id text not null,
  primary key (user_id, card_id)
);

create table public.race_gold_claims (
  user_id uuid not null references public.profiles (id) on delete cascade,
  week int not null,
  gold int not null default 0,
  primary key (user_id, week)
);

create table public.store_imports (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  device_hash text not null unique,
  gold int not null default 0,
  items int not null default 0,
  cosmetics int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.gold_box_stock enable row level security;
alter table public.store_cabinet enable row level security;
alter table public.store_collections_done enable row level security;
alter table public.store_transactions enable row level security;
alter table public.store_perks enable row level security;
alter table public.store_plans enable row level security;
alter table public.pass_owners enable row level security;
alter table public.pass_claims enable row level security;
alter table public.store_requests enable row level security;
alter table public.money_claims enable row level security;
alter table public.store_refunds enable row level security;
alter table public.level_card_grants enable row level security;
alter table public.race_gold_claims enable row level security;
alter table public.store_imports enable row level security;
revoke all on public.gold_box_stock, public.store_cabinet, public.store_collections_done, public.store_transactions, public.store_perks, public.store_plans,
  public.pass_owners, public.pass_claims, public.store_requests, public.money_claims, public.store_refunds, public.level_card_grants,
  public.race_gold_claims, public.store_imports from anon, authenticated;
revoke all on private.store_box_kinds, private.store_box_rows, private.store_box_bundles, private.store_items, private.store_collections, private.store_cosmetics,
  private.store_seasons, private.store_pass_rewards, private.store_level_rewards, private.store_level_cards, private.store_retired, private.store_gold_products,
  private.store_money_packs, private.store_services, private.store_config from public, anon, authenticated;
-- The old wallet tables were readable by their owner; every read now goes through store_state().
revoke select on public.gold_wallets, public.gold_ledger, public.gold_purchases, public.cosmetic_grants from authenticated;
-- The unused gold-pack grant of 0007 knows only the old pack ids; purchases go through grant_purchase.
revoke execute on function public.grant_gold_purchase(uuid, text, text) from service_role;

-- store catalog begin (generated by supabase/tools/store_catalog.py; do not edit by hand)
truncate private.store_box_kinds, private.store_box_rows, private.store_box_bundles, private.store_items, private.store_collections,
  private.store_cosmetics, private.store_seasons, private.store_pass_rewards, private.store_level_rewards, private.store_level_cards, private.store_retired,
  private.store_gold_products, private.store_money_packs, private.store_services;
insert into private.store_box_kinds (kind, price, card_pack) values
  ('free', 0, false),
  ('cabinet', 25, false),
  ('grand', 75, false),
  ('cardBasic', 15, true),
  ('cardPremium', 50, true),
  ('cardElite', 150, true);

insert into private.store_box_rows (kind, pos, rarity, prize, amount, weight) values
  ('free', 1, 'common', 'cosmetic', 0, 1500),
  ('free', 2, 'common', 'artifact', 0, 3450),
  ('free', 3, 'common', 'gold', 1, 3000),
  ('free', 4, 'common', 'money', 1000, 50),
  ('free', 5, 'rare', 'cosmetic', 0, 370),
  ('free', 6, 'rare', 'artifact', 0, 800),
  ('free', 7, 'rare', 'gold', 2, 500),
  ('free', 8, 'rare', 'money', 5000, 30),
  ('free', 9, 'epic', 'cosmetic', 0, 100),
  ('free', 10, 'epic', 'artifact', 0, 150),
  ('free', 11, 'legendary', 'artifact', 0, 50),
  ('cabinet', 1, 'common', 'cosmetic', 0, 2800),
  ('cabinet', 2, 'common', 'artifact', 0, 2800),
  ('cabinet', 3, 'common', 'gold', 5, 1400),
  ('cabinet', 4, 'rare', 'cosmetic', 0, 800),
  ('cabinet', 5, 'rare', 'artifact', 0, 900),
  ('cabinet', 6, 'rare', 'gold', 8, 400),
  ('cabinet', 7, 'rare', 'money', 1000, 200),
  ('cabinet', 8, 'epic', 'cosmetic', 0, 250),
  ('cabinet', 9, 'epic', 'artifact', 0, 200),
  ('cabinet', 10, 'epic', 'gold', 12, 50),
  ('cabinet', 11, 'epic', 'money', 2000, 100),
  ('cabinet', 12, 'legendary', 'cosmetic', 0, 40),
  ('cabinet', 13, 'legendary', 'artifact', 0, 40),
  ('cabinet', 14, 'legendary', 'money', 5000, 20),
  ('grand', 1, 'common', 'cosmetic', 0, 1500),
  ('grand', 2, 'common', 'artifact', 0, 2500),
  ('grand', 3, 'common', 'gold', 6, 500),
  ('grand', 4, 'rare', 'cosmetic', 0, 1300),
  ('grand', 5, 'rare', 'artifact', 0, 1900),
  ('grand', 6, 'rare', 'gold', 12, 400),
  ('grand', 7, 'rare', 'money', 2000, 200),
  ('grand', 8, 'epic', 'cosmetic', 0, 450),
  ('grand', 9, 'epic', 'artifact', 0, 700),
  ('grand', 10, 'epic', 'gold', 25, 100),
  ('grand', 11, 'epic', 'money', 5000, 150),
  ('grand', 12, 'legendary', 'cosmetic', 0, 100),
  ('grand', 13, 'legendary', 'artifact', 0, 150),
  ('grand', 14, 'legendary', 'money', 5000, 50),
  ('cardBasic', 1, 'common', 'profileCard', 0, 3650),
  ('cardBasic', 2, 'common', 'companyCard', 0, 3650),
  ('cardBasic', 3, 'rare', 'profileCard', 0, 1100),
  ('cardBasic', 4, 'rare', 'companyCard', 0, 1100),
  ('cardBasic', 5, 'epic', 'profileCard', 0, 200),
  ('cardBasic', 6, 'epic', 'companyCard', 0, 200),
  ('cardBasic', 7, 'legendary', 'profileCard', 0, 50),
  ('cardBasic', 8, 'legendary', 'companyCard', 0, 50),
  ('cardPremium', 1, 'common', 'profileCard', 0, 1800),
  ('cardPremium', 2, 'common', 'companyCard', 0, 1800),
  ('cardPremium', 3, 'rare', 'profileCard', 0, 1800),
  ('cardPremium', 4, 'rare', 'companyCard', 0, 1800),
  ('cardPremium', 5, 'epic', 'profileCard', 0, 1000),
  ('cardPremium', 6, 'epic', 'companyCard', 0, 1000),
  ('cardPremium', 7, 'legendary', 'profileCard', 0, 400),
  ('cardPremium', 8, 'legendary', 'companyCard', 0, 400),
  ('cardElite', 1, 'common', 'profileCard', 0, 500),
  ('cardElite', 2, 'common', 'companyCard', 0, 500),
  ('cardElite', 3, 'rare', 'profileCard', 0, 1700),
  ('cardElite', 4, 'rare', 'companyCard', 0, 1700),
  ('cardElite', 5, 'epic', 'profileCard', 0, 1600),
  ('cardElite', 6, 'epic', 'companyCard', 0, 1600),
  ('cardElite', 7, 'legendary', 'profileCard', 0, 1200),
  ('cardElite', 8, 'legendary', 'companyCard', 0, 1200);

insert into private.store_box_bundles (id, kind, count, price) values
  ('cabinetx5', 'cabinet', 5, 110),
  ('cabinetx10', 'cabinet', 10, 200),
  ('grandx3', 'grand', 3, 200);

insert into private.store_items (id, kind, rarity, collection, theme, bound) values
  ('abacus', 'artifact', 'common', 'counting', 'classic', false),
  ('scales', 'artifact', 'rare', 'counting', 'classic', false),
  ('strongbox', 'artifact', 'epic', 'counting', 'classic', false),
  ('seal', 'artifact', 'legendary', 'counting', 'classic', false),
  ('rope', 'artifact', 'common', 'harbour', 'classic', false),
  ('lantern', 'artifact', 'rare', 'harbour', 'classic', false),
  ('chart', 'artifact', 'epic', 'harbour', 'classic', false),
  ('compass', 'artifact', 'legendary', 'harbour', 'classic', false),
  ('token', 'artifact', 'common', 'market', 'classic', false),
  ('banner', 'artifact', 'rare', 'market', 'classic', false),
  ('bell', 'artifact', 'epic', 'market', 'classic', false),
  ('weights', 'artifact', 'legendary', 'market', 'classic', false),
  ('stamp', 'artifact', 'common', 'archive', 'classic', false),
  ('map', 'artifact', 'rare', 'archive', 'classic', false),
  ('scroll', 'artifact', 'epic', 'archive', 'classic', false),
  ('charter', 'artifact', 'legendary', 'archive', 'classic', false),
  ('spring.egg', 'artifact', 'common', 'spring', 'spring', false),
  ('spring.blossom', 'artifact', 'rare', 'spring', 'spring', false),
  ('spring.hare', 'artifact', 'epic', 'spring', 'spring', false),
  ('spring.jewel', 'artifact', 'legendary', 'spring', 'spring', false),
  ('card.p.slate', 'profileCard', 'common', null, 'classic', false),
  ('card.p.olive', 'profileCard', 'common', null, 'classic', false),
  ('card.p.clay', 'profileCard', 'common', null, 'classic', false),
  ('card.p.ink', 'profileCard', 'common', null, 'classic', false),
  ('card.p.twilight', 'profileCard', 'rare', null, 'classic', false),
  ('card.p.harbour', 'profileCard', 'rare', null, 'classic', false),
  ('card.p.ember', 'profileCard', 'rare', null, 'founder', false),
  ('card.p.glass', 'profileCard', 'epic', null, 'classic', false),
  ('card.p.gilt', 'profileCard', 'epic', null, 'founder', false),
  ('card.p.aurora', 'profileCard', 'legendary', null, 'founder', false),
  ('card.p.flare', 'profileCard', 'legendary', null, 'classic', false),
  ('card.p.tide', 'profileCard', 'legendary', null, 'classic', false),
  ('card.c.navy', 'companyCard', 'common', null, 'classic', false),
  ('card.c.forest', 'companyCard', 'common', null, 'classic', false),
  ('card.c.burgundy', 'companyCard', 'common', null, 'founder', false),
  ('card.c.charcoal', 'companyCard', 'common', null, 'classic', false),
  ('card.c.brass', 'companyCard', 'rare', null, 'founder', false),
  ('card.c.teal', 'companyCard', 'rare', null, 'classic', false),
  ('card.c.copper', 'companyCard', 'rare', null, 'founder', false),
  ('card.c.silver', 'companyCard', 'epic', null, 'founder', false),
  ('card.c.violet', 'companyCard', 'epic', null, 'classic', false),
  ('card.c.standard', 'companyCard', 'legendary', null, 'classic', false),
  ('card.c.skyline', 'companyCard', 'legendary', null, 'classic', false),
  ('card.c.diamond', 'companyCard', 'legendary', null, 'classic', false),
  ('card.p.meadow', 'profileCard', 'common', null, 'spring', false),
  ('card.p.blossom', 'profileCard', 'rare', null, 'spring', false),
  ('card.p.pastel', 'profileCard', 'epic', null, 'spring', false),
  ('card.p.dawn', 'profileCard', 'legendary', null, 'spring', false),
  ('card.c.hare', 'companyCard', 'common', null, 'spring', false),
  ('card.c.regatta', 'companyCard', 'rare', null, 'spring', false),
  ('card.c.roadster', 'companyCard', 'epic', null, 'spring', false),
  ('card.c.yacht', 'companyCard', 'legendary', null, 'spring', false);

insert into private.store_level_cards (level, card_id) values
  (2, 'card.p.slate'),
  (4, 'card.c.navy'),
  (6, 'card.p.olive'),
  (9, 'card.c.forest'),
  (12, 'card.p.harbour'),
  (16, 'card.c.teal');

insert into private.store_collections (id, reward_id, theme) values
  ('counting', 'gold.coll.counting.backdrop', 'classic'),
  ('harbour', 'gold.coll.harbour', 'classic'),
  ('market', 'gold.coll.market', 'classic'),
  ('archive', 'gold.coll.archive', 'classic'),
  ('spring', 'gold.coll.spring', 'spring');

insert into private.store_cosmetics (id, kind, rarity, source, price, theme, bound) values
  ('outfit.shirt', 'outfit', 'common', 'free', null, 'classic', false),
  ('outfit.polo', 'outfit', 'common', 'free', null, 'classic', false),
  ('outfit.hoodie', 'outfit', 'common', 'free', null, 'classic', false),
  ('outfit.blazer', 'outfit', 'common', 'free', null, 'classic', false),
  ('outfit.intern', 'outfit', 'common', 'level', null, 'classic', true),
  ('outfit.clerk', 'outfit', 'common', 'level', null, 'classic', true),
  ('outfit.sales', 'outfit', 'common', 'level', null, 'classic', true),
  ('outfit.suit', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.courier', 'outfit', 'common', 'level', null, 'classic', true),
  ('outfit.manager', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.whites', 'outfit', 'common', 'level', null, 'classic', true),
  ('outfit.turtleneck', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.trench', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.vest', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.pinstripe', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.tux', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.camel', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.threepiece', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.bomber', 'outfit', 'rare', 'level', null, 'classic', true),
  ('outfit.velvet', 'outfit', 'epic', 'level', null, 'classic', true),
  ('outfit.mandarin', 'outfit', 'epic', 'level', null, 'classic', true),
  ('outfit.cashmere', 'outfit', 'epic', 'level', null, 'classic', true),
  ('outfit.opera', 'outfit', 'epic', 'level', null, 'classic', true),
  ('outfit.brocade', 'outfit', 'epic', 'level', null, 'classic', true),
  ('outfit.whitetux', 'outfit', 'epic', 'level', null, 'classic', true),
  ('outfit.goldthread', 'outfit', 'epic', 'level', null, 'classic', true),
  ('outfit.tailcoat', 'outfit', 'legendary', 'level', null, 'classic', true),
  ('outfit.rank.shopkeeper', 'outfit', 'common', 'rank', null, 'classic', true),
  ('outfit.rank.trader', 'outfit', 'common', 'rank', null, 'classic', true),
  ('outfit.rank.merchant', 'outfit', 'rare', 'rank', null, 'classic', true),
  ('outfit.rank.entrepreneur', 'outfit', 'rare', 'rank', null, 'classic', true),
  ('outfit.rank.executive', 'outfit', 'rare', 'rank', null, 'classic', true),
  ('outfit.rank.magnate', 'outfit', 'epic', 'rank', null, 'classic', true),
  ('outfit.rank.mogul', 'outfit', 'epic', 'rank', null, 'classic', true),
  ('outfit.rank.tycoon', 'outfit', 'legendary', 'rank', null, 'classic', true),
  ('outfit.goal.regulars', 'outfit', 'common', 'goal', null, 'classic', true),
  ('outfit.goal.coinvest', 'outfit', 'common', 'goal', null, 'classic', true),
  ('outfit.goal.laurelcoat', 'outfit', 'rare', 'goal', null, 'classic', true),
  ('outfit.goal.trophyblazer', 'outfit', 'rare', 'goal', null, 'classic', true),
  ('outfit.goal.bannercardigan', 'outfit', 'rare', 'goal', null, 'classic', true),
  ('outfit.goal.diamondjacket', 'outfit', 'epic', 'goal', null, 'classic', true),
  ('outfit.goal.crowncollar', 'outfit', 'epic', 'goal', null, 'classic', true),
  ('outfit.goal.skylinesuit', 'outfit', 'epic', 'goal', null, 'classic', true),
  ('outfit.goal.bellsleeve', 'outfit', 'common', 'goal', null, 'classic', true),
  ('outfit.goal.sealedlapel', 'outfit', 'rare', 'goal', null, 'classic', true),
  ('outfit.goal.crestblazer', 'outfit', 'epic', 'goal', null, 'classic', true),
  ('outfit.charcoal', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.greyflannel', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.linensuit', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.navypin', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.camelcoat', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.redpower', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.boardroom', 'outfit', 'epic', 'store', 80, 'classic', true),
  ('outfit.chalkstripe', 'outfit', 'epic', 'store', 80, 'classic', true),
  ('outfit.denim', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.bomberjk', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.cableknit', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.trackjk', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.flannel', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.leather', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.smoking', 'outfit', 'epic', 'store', 80, 'classic', true),
  ('outfit.kimono', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.evening', 'outfit', 'epic', 'store', 80, 'classic', true),
  ('outfit.minkcoat', 'outfit', 'legendary', 'box', null, 'classic', false),
  ('outfit.lame', 'outfit', 'legendary', 'box', null, 'classic', false),
  ('outfit.diamondtux', 'outfit', 'legendary', 'box', null, 'classic', false),
  ('outfit.captain', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.aviator', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.baker', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.safari', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.labcoat', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.pirate', 'outfit', 'epic', 'store', 80, 'classic', true),
  ('outfit.racing', 'outfit', 'epic', 'store', 80, 'classic', true),
  ('outfit.astronaut', 'outfit', 'legendary', 'box', null, 'classic', false),
  ('outfit.parka', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.tweed', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.sunlinen', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.rainmac', 'outfit', 'common', 'store', 15, 'classic', true),
  ('outfit.skijacket', 'outfit', 'rare', 'store', 35, 'classic', true),
  ('outfit.holiday', 'outfit', 'epic', 'store', 80, 'classic', true),
  ('face.0', 'face', 'common', 'free', null, 'classic', false),
  ('face.1', 'face', 'common', 'free', null, 'classic', false),
  ('face.2', 'face', 'common', 'free', null, 'classic', false),
  ('face.3', 'face', 'common', 'free', null, 'classic', false),
  ('face.4', 'face', 'common', 'free', null, 'classic', false),
  ('face.5', 'face', 'common', 'free', null, 'classic', false),
  ('face.6', 'face', 'common', 'free', null, 'classic', false),
  ('face.7', 'face', 'common', 'free', null, 'classic', false),
  ('face.8', 'face', 'common', 'store', 15, 'classic', true),
  ('face.9', 'face', 'common', 'store', 15, 'classic', true),
  ('face.10', 'face', 'common', 'store', 15, 'classic', true),
  ('face.11', 'face', 'rare', 'store', 35, 'classic', true),
  ('face.12', 'face', 'rare', 'store', 35, 'classic', true),
  ('face.13', 'face', 'rare', 'store', 35, 'classic', true),
  ('face.14', 'face', 'epic', 'store', 80, 'classic', true),
  ('face.15', 'face', 'epic', 'store', 80, 'classic', true),
  ('hair.short', 'hair', 'common', 'free', null, 'classic', false),
  ('hair.side', 'hair', 'common', 'free', null, 'classic', false),
  ('hair.buzz', 'hair', 'common', 'free', null, 'classic', false),
  ('hair.long', 'hair', 'common', 'free', null, 'classic', false),
  ('hair.bun', 'hair', 'common', 'free', null, 'classic', false),
  ('hair.curly', 'hair', 'common', 'free', null, 'classic', false),
  ('hair.tail', 'hair', 'common', 'free', null, 'classic', false),
  ('hair.bald', 'hair', 'common', 'free', null, 'classic', false),
  ('hair.pompadour', 'hair', 'common', 'store', 15, 'classic', true),
  ('hair.bob', 'hair', 'common', 'store', 15, 'classic', true),
  ('hair.braids', 'hair', 'common', 'store', 15, 'classic', true),
  ('hair.waves', 'hair', 'common', 'store', 15, 'classic', true),
  ('hair.afro', 'hair', 'rare', 'store', 35, 'classic', true),
  ('hair.undercut', 'hair', 'rare', 'store', 35, 'classic', true),
  ('hair.topknot', 'hair', 'rare', 'store', 35, 'classic', true),
  ('hair.pixie', 'hair', 'epic', 'store', 80, 'classic', true),
  ('hair.slicked', 'hair', 'epic', 'store', 80, 'classic', true),
  ('hair.mohawk', 'hair', 'legendary', 'box', null, 'classic', false),
  ('skin.porcelain', 'skin', 'common', 'free', null, 'classic', false),
  ('skin.fair', 'skin', 'common', 'free', null, 'classic', false),
  ('skin.light', 'skin', 'common', 'free', null, 'classic', false),
  ('skin.sand', 'skin', 'common', 'free', null, 'classic', false),
  ('skin.olive', 'skin', 'common', 'free', null, 'classic', false),
  ('skin.tan', 'skin', 'common', 'free', null, 'classic', false),
  ('skin.brown', 'skin', 'common', 'free', null, 'classic', false),
  ('skin.deep', 'skin', 'common', 'free', null, 'classic', false),
  ('gold.backdrop.fog', 'backdrop', 'common', 'store', 15, 'classic', true),
  ('gold.backdrop.slate', 'backdrop', 'common', 'store', 15, 'classic', true),
  ('gold.backdrop.sandstone', 'backdrop', 'common', 'store', 15, 'classic', true),
  ('gold.backdrop.pine', 'backdrop', 'common', 'store', 15, 'classic', true),
  ('gold.backdrop.harbourdusk', 'backdrop', 'common', 'store', 15, 'classic', true),
  ('gold.backdrop.brickloft', 'backdrop', 'common', 'store', 15, 'classic', true),
  ('gold.backdrop.paperwhite', 'backdrop', 'common', 'store', 15, 'classic', true),
  ('gold.backdrop.cafeterrace', 'backdrop', 'common', 'store', 15, 'classic', true),
  ('gold.backdrop.greenhouse', 'backdrop', 'common', 'store', 15, 'classic', true),
  ('gold.backdrop.plum', 'backdrop', 'rare', 'store', 35, 'classic', true),
  ('gold.backdrop.citynight', 'backdrop', 'rare', 'store', 35, 'classic', true),
  ('gold.backdrop.library', 'backdrop', 'rare', 'store', 35, 'classic', true),
  ('gold.backdrop.desert', 'backdrop', 'rare', 'store', 35, 'classic', true),
  ('gold.backdrop.rainwindow', 'backdrop', 'rare', 'store', 35, 'classic', true),
  ('gold.backdrop.snowpeaks', 'backdrop', 'rare', 'store', 35, 'classic', true),
  ('gold.backdrop.marketsquare', 'backdrop', 'rare', 'store', 35, 'classic', true),
  ('gold.backdrop.lighthouse', 'backdrop', 'rare', 'store', 35, 'classic', true),
  ('gold.backdrop.orchardrow', 'backdrop', 'rare', 'store', 35, 'classic', true),
  ('gold.backdrop.aurora', 'backdrop', 'epic', 'store', 80, 'classic', true),
  ('gold.backdrop.marbleatrium', 'backdrop', 'epic', 'store', 80, 'classic', true),
  ('gold.backdrop.skyline', 'backdrop', 'epic', 'store', 80, 'classic', true),
  ('gold.backdrop.rooftopdusk', 'backdrop', 'epic', 'store', 80, 'classic', true),
  ('gold.backdrop.vaultdoor', 'backdrop', 'epic', 'store', 80, 'classic', true),
  ('gold.backdrop.cherrygarden', 'backdrop', 'epic', 'store', 80, 'classic', true),
  ('gold.backdrop.goldhall', 'backdrop', 'legendary', 'box', null, 'classic', false),
  ('gold.backdrop.nebula', 'backdrop', 'legendary', 'box', null, 'classic', false),
  ('gold.backdrop.opera', 'backdrop', 'legendary', 'box', null, 'classic', false),
  ('gold.backdrop.crystalcave', 'backdrop', 'legendary', 'box', null, 'classic', false),
  ('gold.coll.harbour', 'backdrop', 'epic', 'collection', null, 'harbour', false),
  ('gold.coll.spring', 'backdrop', 'epic', 'collection', null, 'spring', false),
  ('gold.coll.counting.backdrop', 'backdrop', 'epic', 'collection', null, 'classic', false),
  ('gold.flair.laurel', 'richListFlair', 'rare', 'store', 35, 'classic', true),
  ('gold.flair.spark', 'richListFlair', 'rare', 'store', 35, 'classic', true),
  ('gold.flair.pennant', 'richListFlair', 'rare', 'store', 35, 'classic', true),
  ('gold.flair.ember', 'richListFlair', 'epic', 'store', 80, 'classic', true),
  ('gold.flair.crown', 'richListFlair', 'epic', 'store', 80, 'classic', true),
  ('gold.flair.laurelgold', 'richListFlair', 'epic', 'store', 80, 'classic', true),
  ('gold.flair.comet', 'richListFlair', 'epic', 'store', 80, 'classic', true),
  ('gold.flair.ink', 'richListFlair', 'epic', 'store', 80, 'classic', true),
  ('gold.flair.signet', 'richListFlair', 'epic', 'store', 80, 'classic', true),
  ('gold.flair.coinrain', 'richListFlair', 'epic', 'store', 80, 'classic', true),
  ('gold.flair.sun', 'richListFlair', 'legendary', 'box', null, 'classic', false),
  ('gold.flair.diamond', 'richListFlair', 'legendary', 'box', null, 'classic', false),
  ('gold.flair.phoenix', 'richListFlair', 'legendary', 'box', null, 'classic', false),
  ('gold.flair.dragon', 'richListFlair', 'legendary', 'box', null, 'classic', false),
  ('gold.flair.aurora', 'richListFlair', 'legendary', 'box', null, 'classic', false),
  ('gold.flair.galaxy', 'richListFlair', 'legendary', 'box', null, 'classic', false),
  ('gold.flair.vault', 'richListFlair', 'legendary', 'box', null, 'classic', false),
  ('gold.flair.hallofame', 'richListFlair', 'legendary', 'box', null, 'classic', false),
  ('gold.flair.plus', 'richListFlair', 'rare', 'plan', null, 'classic', true),
  ('gold.flair.founder', 'richListFlair', 'legendary', 'plan', null, 'classic', true),
  ('gold.coll.archive', 'richListFlair', 'epic', 'collection', null, 'archive', false),
  ('gold.trade.pewter', 'tradePlate', 'common', 'store', 15, 'classic', true),
  ('gold.trade.rose', 'tradePlate', 'epic', 'store', 80, 'classic', true),
  ('gold.coll.market', 'tradePlate', 'epic', 'collection', null, 'market', false),
  ('gold.slot.1', 'saveSlot', 'common', 'store', 75, 'classic', true),
  ('gold.slot.2', 'saveSlot', 'common', 'store', 120, 'classic', true),
  ('gold.slot.3', 'saveSlot', 'common', 'store', 175, 'classic', true),
  ('gold.plate.pewter', 'namePlate', 'common', 'retired', null, 'classic', true),
  ('gold.plate.ribbon', 'namePlate', 'common', 'retired', null, 'classic', true),
  ('gold.plate.chalk', 'namePlate', 'common', 'retired', null, 'classic', true),
  ('gold.plate.woodsign', 'namePlate', 'common', 'retired', null, 'classic', true),
  ('gold.plate.tape', 'namePlate', 'common', 'retired', null, 'classic', true),
  ('gold.plate.copper', 'namePlate', 'rare', 'retired', null, 'classic', true),
  ('gold.plate.brassplaque', 'namePlate', 'rare', 'retired', null, 'classic', true),
  ('gold.plate.enamel', 'namePlate', 'rare', 'retired', null, 'classic', true),
  ('gold.plate.slate', 'namePlate', 'rare', 'retired', null, 'classic', true),
  ('gold.plate.neonbar', 'namePlate', 'epic', 'retired', null, 'classic', true),
  ('gold.plate.marbleslab', 'namePlate', 'epic', 'retired', null, 'classic', true),
  ('gold.plate.carbon', 'namePlate', 'epic', 'retired', null, 'classic', true),
  ('gold.plate.onyx', 'namePlate', 'epic', 'retired', null, 'classic', true),
  ('gold.plate.leaf', 'namePlate', 'legendary', 'retired', null, 'classic', true),
  ('gold.plate.mosaic', 'namePlate', 'legendary', 'retired', null, 'classic', true),
  ('gold.coll.counting', 'namePlate', 'epic', 'retired', null, 'classic', true),
  ('plate.ledger', 'namePlate', 'common', 'retired', null, 'classic', true),
  ('plate.brass', 'namePlate', 'common', 'retired', null, 'classic', true),
  ('plate.walnut', 'namePlate', 'common', 'retired', null, 'classic', true),
  ('plate.marble', 'namePlate', 'common', 'retired', null, 'classic', true),
  ('plate.egg', 'namePlate', 'rare', 'retired', null, 'classic', true),
  ('plate.marble.s2', 'namePlate', 'epic', 'retired', null, 'classic', true),
  ('gold.theme.sage', 'theme', 'common', 'retired', null, 'classic', true),
  ('gold.theme.amber', 'theme', 'rare', 'retired', null, 'classic', true),
  ('gold.theme.indigo', 'theme', 'epic', 'retired', null, 'classic', true),
  ('gold.theme.crimson', 'theme', 'legendary', 'retired', null, 'classic', true),
  ('badge.s1.first', 'badge', 'common', 'retired', null, 'classic', true),
  ('badge.s1.cash', 'badge', 'common', 'retired', null, 'founder', true),
  ('theme.dusk', 'theme', 'common', 'retired', null, 'founder', true),
  ('badge.s1.complete', 'badge', 'common', 'retired', null, 'founder', true),
  ('theme.moss', 'theme', 'common', 'retired', null, 'founder', true),
  ('badge.s1.plus', 'badge', 'common', 'retired', null, 'founder', true),
  ('theme.rose', 'theme', 'common', 'retired', null, 'founder', true),
  ('theme.ocean', 'theme', 'common', 'retired', null, 'founder', true),
  ('badge.s1.crown', 'badge', 'common', 'retired', null, 'founder', true),
  ('badge.s2.sprout', 'badge', 'common', 'retired', null, 'spring', true),
  ('badge.s2.complete', 'badge', 'epic', 'retired', null, 'spring', true),
  ('theme.mint', 'theme', 'rare', 'retired', null, 'spring', true),
  ('badge.s2.plus', 'badge', 'rare', 'retired', null, 'spring', true),
  ('theme.lilac', 'theme', 'rare', 'retired', null, 'spring', true),
  ('badge.s2.crown', 'badge', 'legendary', 'retired', null, 'spring', true),
  ('av.briefcase', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.coffee', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.leaf', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.bolt', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.star', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.sun', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.moon', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.drop', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.hare', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.bird', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.flame', 'avatar', 'rare', 'avatar', null, 'classic', true),
  ('av.sparkle', 'avatar', 'rare', 'avatar', null, 'classic', true),
  ('av.infinity', 'avatar', 'epic', 'avatar', null, 'classic', true),
  ('av.plus.ink', 'avatar', 'common', 'avatar', null, 'classic', true),
  ('av.pro.gilded', 'avatar', 'epic', 'avatar', null, 'classic', true),
  ('av.founder.quill', 'avatar', 'epic', 'avatar', null, 'classic', true),
  ('av.founder.vault', 'avatar', 'epic', 'avatar', null, 'classic', true),
  ('av.founder.seal', 'avatar', 'legendary', 'avatar', null, 'classic', true),
  ('av.key', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.paw', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.tortoise', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.summit', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.sailboat', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.workshop', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.jet', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.toast', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.diamond', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.goldstar', 'avatar', 'common', 'retired', null, 'classic', true),
  ('av.sleight', 'avatar', 'common', 'retired', null, 'classic', true),
  ('outfit.s1.pennant', 'outfit', 'common', 'season', null, 'classic', true),
  ('backdrop.ledger', 'backdrop', 'common', 'season', null, 'founder', false),
  ('outfit.s1.cash', 'outfit', 'rare', 'season', null, 'founder', true),
  ('outfit.s1.brass', 'outfit', 'common', 'season', null, 'founder', true),
  ('outfit.s1.dusk', 'outfit', 'epic', 'season', null, 'founder', true),
  ('backdrop.sand', 'backdrop', 'common', 'season', null, 'founder', false),
  ('outfit.s1.finisher', 'outfit', 'epic', 'season', null, 'founder', true),
  ('outfit.s1.moss', 'outfit', 'rare', 'season', null, 'founder', true),
  ('outfit.s1.walnut', 'outfit', 'common', 'season', null, 'founder', true),
  ('advisor.patience', 'advisorLine', 'common', 'season', null, 'founder', false),
  ('backdrop.dawn', 'backdrop', 'common', 'season', null, 'founder', false),
  ('outfit.s1.plus', 'outfit', 'rare', 'season', null, 'founder', true),
  ('trade.engraved', 'tradePlate', 'common', 'season', null, 'founder', false),
  ('outfit.s1.rose', 'outfit', 'rare', 'season', null, 'founder', true),
  ('flair.crest', 'richListFlair', 'common', 'season', null, 'founder', false),
  ('advisor.horizon', 'advisorLine', 'common', 'season', null, 'founder', false),
  ('slot.extra', 'saveSlot', 'common', 'season', null, 'founder', false),
  ('backdrop.harbour', 'backdrop', 'common', 'season', null, 'founder', false),
  ('backdrop.marble', 'backdrop', 'common', 'season', null, 'founder', false),
  ('outfit.s1.ocean', 'outfit', 'epic', 'season', null, 'founder', true),
  ('trade.gilded', 'tradePlate', 'common', 'season', null, 'founder', false),
  ('outfit.s1.crown', 'outfit', 'legendary', 'season', null, 'founder', true),
  ('outfit.s2.sprout', 'outfit', 'common', 'season', null, 'spring', false),
  ('advisor.s2.spring', 'advisorLine', 'common', 'season', null, 'spring', false),
  ('backdrop.orchard', 'backdrop', 'rare', 'season', null, 'spring', false),
  ('outfit.s2.fairday', 'outfit', 'epic', 'season', null, 'spring', false),
  ('outfit.s2.mint', 'outfit', 'rare', 'season', null, 'spring', false),
  ('outfit.s2.egg', 'outfit', 'rare', 'season', null, 'spring', false),
  ('advisor.s2.market', 'advisorLine', 'common', 'season', null, 'spring', false),
  ('backdrop.pastel', 'backdrop', 'rare', 'season', null, 'spring', false),
  ('outfit.s2.plus', 'outfit', 'rare', 'season', null, 'spring', false),
  ('trade.market', 'tradePlate', 'rare', 'season', null, 'spring', false),
  ('outfit.s2.lilac', 'outfit', 'rare', 'season', null, 'spring', false),
  ('flair.egg', 'richListFlair', 'epic', 'season', null, 'spring', false),
  ('advisor.s2.patience', 'advisorLine', 'common', 'season', null, 'spring', false),
  ('backdrop.dawn.s2', 'backdrop', 'epic', 'season', null, 'spring', false),
  ('backdrop.marble.s2', 'backdrop', 'epic', 'season', null, 'spring', false),
  ('trade.gilded.s2', 'tradePlate', 'epic', 'season', null, 'spring', false),
  ('outfit.s2.crown', 'outfit', 'legendary', 'season', null, 'spring', false);

insert into private.store_seasons (season, theme, founder, starts) values
  (1, 'founder', true, '2026-09-28'),
  (2, 'spring', false, '2027-03-29');

insert into private.store_pass_rewards (season, track, tier, reward_id, kind, amount) values
  (1, 'f', 1, 'outfit.s1.pennant', 'outfit', 0),
  (1, 'f', 3, 'backdrop.ledger', 'backdrop', 0),
  (1, 'f', 6, 'card.p.slate', 'profileCard', 0),
  (1, 'f', 10, 'box.f10', 'box', 1),
  (1, 'p', 11, 'outfit.s1.cash', 'outfit', 0),
  (1, 'f', 13, 'outfit.s1.brass', 'outfit', 0),
  (1, 'f', 16, 'box.f16', 'box', 1),
  (1, 'p', 17, 'outfit.s1.dusk', 'outfit', 0),
  (1, 'f', 20, 'card.p.ember', 'profileCard', 0),
  (1, 'f', 23, 'backdrop.sand', 'backdrop', 0),
  (1, 'f', 26, 'box.f26', 'box', 1),
  (1, 'f', 30, 'outfit.s1.finisher', 'outfit', 0),
  (1, 'p', 1, 'outfit.s1.moss', 'outfit', 0),
  (1, 'p', 2, 'outfit.s1.walnut', 'outfit', 0),
  (1, 'p', 3, 'advisor.patience', 'advisorLine', 0),
  (1, 'p', 4, 'box.p4', 'box', 1),
  (1, 'p', 5, 'backdrop.dawn', 'backdrop', 0),
  (1, 'p', 6, 'outfit.s1.plus', 'outfit', 0),
  (1, 'p', 7, 'gold.p7', 'gold', 4),
  (1, 'p', 8, 'card.c.brass', 'companyCard', 0),
  (1, 'p', 9, 'trade.engraved', 'tradePlate', 0),
  (1, 'p', 10, 'box.p10', 'box', 2),
  (1, 'p', 12, 'outfit.s1.rose', 'outfit', 0),
  (1, 'p', 13, 'gold.p13', 'gold', 6),
  (1, 'p', 14, 'card.p.gilt', 'profileCard', 0),
  (1, 'p', 15, 'flair.crest', 'richListFlair', 0),
  (1, 'p', 16, 'box.p16', 'box', 2),
  (1, 'p', 18, 'advisor.horizon', 'advisorLine', 0),
  (1, 'p', 19, 'gold.p19', 'gold', 8),
  (1, 'p', 20, 'slot.extra', 'saveSlot', 0),
  (1, 'p', 21, 'backdrop.harbour', 'backdrop', 0),
  (1, 'p', 22, 'card.c.silver', 'companyCard', 0),
  (1, 'p', 24, 'backdrop.marble', 'backdrop', 0),
  (1, 'p', 25, 'box.p25', 'box', 2),
  (1, 'p', 26, 'card.p.aurora', 'profileCard', 0),
  (1, 'p', 27, 'outfit.s1.ocean', 'outfit', 0),
  (1, 'p', 28, 'trade.gilded', 'tradePlate', 0),
  (1, 'p', 29, 'gold.p29', 'gold', 10),
  (1, 'p', 30, 'outfit.s1.crown', 'outfit', 0),
  (2, 'f', 1, 'outfit.s2.sprout', 'outfit', 0),
  (2, 'f', 2, 'xp.s2.f2', 'xp', 60),
  (2, 'f', 7, 'spring.egg', 'artifact', 0),
  (2, 'f', 10, 'box.s2.f10', 'box', 1),
  (2, 'f', 13, 'advisor.s2.spring', 'advisorLine', 0),
  (2, 'f', 16, 'box.s2.f16', 'box', 1),
  (2, 'p', 18, 'spring.blossom', 'artifact', 0),
  (2, 'f', 20, 'card.p.blossom', 'profileCard', 0),
  (2, 'f', 23, 'backdrop.orchard', 'backdrop', 0),
  (2, 'f', 26, 'box.s2.f26', 'box', 1),
  (2, 'f', 30, 'outfit.s2.fairday', 'outfit', 0),
  (2, 'p', 1, 'outfit.s2.mint', 'outfit', 0),
  (2, 'p', 2, 'outfit.s2.egg', 'outfit', 0),
  (2, 'p', 3, 'advisor.s2.market', 'advisorLine', 0),
  (2, 'p', 4, 'box.s2.p4', 'box', 2),
  (2, 'p', 5, 'backdrop.pastel', 'backdrop', 0),
  (2, 'p', 6, 'outfit.s2.plus', 'outfit', 0),
  (2, 'p', 7, 'gold.s2.p7', 'gold', 24),
  (2, 'p', 8, 'card.c.roadster', 'companyCard', 0),
  (2, 'p', 9, 'trade.market', 'tradePlate', 0),
  (2, 'p', 10, 'box.s2.p10', 'box', 2),
  (2, 'p', 11, 'spring.hare', 'artifact', 0),
  (2, 'p', 12, 'outfit.s2.lilac', 'outfit', 0),
  (2, 'p', 13, 'xp.s2.p13', 'xp', 200),
  (2, 'p', 14, 'card.p.pastel', 'profileCard', 0),
  (2, 'p', 15, 'flair.egg', 'richListFlair', 0),
  (2, 'p', 16, 'box.s2.p16', 'box', 2),
  (2, 'p', 17, 'advisor.s2.patience', 'advisorLine', 0),
  (2, 'p', 19, 'gold.s2.p19', 'gold', 36),
  (2, 'p', 20, 'spring.jewel', 'artifact', 0),
  (2, 'p', 21, 'backdrop.dawn.s2', 'backdrop', 0),
  (2, 'p', 22, 'card.c.yacht', 'companyCard', 0),
  (2, 'p', 24, 'backdrop.marble.s2', 'backdrop', 0),
  (2, 'p', 25, 'box.s2.p25', 'box', 3),
  (2, 'p', 26, 'card.p.dawn', 'profileCard', 0),
  (2, 'p', 27, 'xp.s2.p27', 'xp', 250),
  (2, 'p', 28, 'trade.gilded.s2', 'tradePlate', 0),
  (2, 'p', 29, 'gold.s2.p29', 'gold', 50),
  (2, 'p', 30, 'outfit.s2.crown', 'outfit', 0);

insert into private.store_level_rewards (level, gold) values
  (2, 1),
  (3, 1),
  (4, 1),
  (5, 1),
  (6, 1),
  (7, 1),
  (8, 1),
  (9, 1),
  (10, 2),
  (11, 2),
  (12, 2),
  (13, 2),
  (14, 2),
  (15, 2),
  (16, 2),
  (17, 2),
  (18, 2),
  (19, 2),
  (20, 4),
  (21, 2),
  (22, 2),
  (23, 2),
  (24, 2),
  (25, 2),
  (26, 2),
  (27, 2),
  (28, 2),
  (29, 2),
  (30, 4),
  (31, 3),
  (32, 3),
  (33, 3),
  (34, 3),
  (35, 3),
  (36, 3),
  (37, 3),
  (38, 3),
  (39, 3),
  (40, 6),
  (41, 3),
  (42, 3),
  (43, 3),
  (44, 3),
  (45, 3),
  (46, 3),
  (47, 3),
  (48, 3),
  (49, 3),
  (50, 6),
  (51, 3),
  (52, 3),
  (53, 3),
  (54, 3),
  (55, 3),
  (56, 3),
  (57, 3),
  (58, 3),
  (59, 3),
  (60, 6),
  (61, 4),
  (62, 4),
  (63, 4),
  (64, 4),
  (65, 4),
  (66, 4),
  (67, 4),
  (68, 4),
  (69, 4),
  (70, 8),
  (71, 4),
  (72, 4),
  (73, 4),
  (74, 4),
  (75, 4),
  (76, 4),
  (77, 4),
  (78, 4),
  (79, 4),
  (80, 8),
  (81, 4),
  (82, 4),
  (83, 4),
  (84, 4),
  (85, 4),
  (86, 4),
  (87, 4),
  (88, 4),
  (89, 4),
  (90, 8),
  (91, 4),
  (92, 4),
  (93, 4),
  (94, 4),
  (95, 4),
  (96, 4),
  (97, 4),
  (98, 4),
  (99, 4),
  (100, 100);

insert into private.store_retired (id, gold) values
  ('gold.theme.sage', 15),
  ('gold.theme.amber', 35),
  ('gold.theme.indigo', 80),
  ('av.key', 15),
  ('av.paw', 15),
  ('av.tortoise', 15),
  ('av.summit', 15),
  ('av.sailboat', 35),
  ('av.workshop', 35),
  ('av.jet', 35),
  ('av.toast', 35),
  ('av.diamond', 80),
  ('av.goldstar', 80),
  ('av.sleight', 80),
  ('gold.plate.pewter', 15),
  ('gold.plate.ribbon', 15),
  ('gold.plate.chalk', 15),
  ('gold.plate.woodsign', 15),
  ('gold.plate.tape', 15),
  ('gold.plate.copper', 35),
  ('gold.plate.brassplaque', 35),
  ('gold.plate.enamel', 35),
  ('gold.plate.slate', 35),
  ('gold.plate.neonbar', 80),
  ('gold.plate.marbleslab', 80),
  ('gold.plate.carbon', 80),
  ('gold.plate.onyx', 80);

insert into private.store_gold_products (product_id, kind, gold, box_kind, box_count) values
  ('com.ledger.gold.pouch', 'gold', 20, null, 0),
  ('com.ledger.gold.purse', 'gold', 55, null, 0),
  ('com.ledger.gold.chest', 'gold', 120, null, 0),
  ('com.ledger.gold.vault', 'gold', 260, null, 0),
  ('com.ledger.gold.hoard', 'gold', 700, null, 0),
  ('com.ledger.season.bundle', 'pass', 10, 'cabinet', 1),
  ('com.ledger.season.levels', 'pass', 10, 'cabinet', 1),
  ('com.ledger.pro', 'perk', 250, null, 0),
  ('com.ledger.pro.yearly', 'perk', 250, null, 0),
  ('com.ledger.founder', 'perk', 600, null, 0),
  ('com.ledger.plus.monthly', 'plan', 0, null, 0),
  ('com.ledger.plus.yearly', 'plan', 0, null, 0);

insert into private.store_money_packs (id, gold, bonus_percent, free) values
  ('handful', 10, 0, false),
  ('bundle', 50, 5, false),
  ('case', 125, 10, false),
  ('safe', 250, 15, false),
  ('mountain', 530, 20, false),
  ('free', 2, 0, true);

insert into private.store_services (id, price) values
  ('companyNameSkip', 15),
  ('usernameChange', 20);

create or replace function private.store_setting(k text) returns int language sql immutable as $$
  select ('{"founderLastSeason": 1, "founderPassTiers": 10, "freeMoneyPerDay": 2, "levelsTiers": 10, "moneyPackWeeklyGold": 1060, "seasonDays": 182}'::jsonb ->> k)::int;
$$;
-- store catalog end

-- Server clock: the app reads these instead of the phone's date for pass days, daily and weekly limits and streaks.
create or replace function private.era_day(t timestamptz default now()) returns int language sql stable set search_path = '' as $$
  select (((t at time zone 'utc')::date) - date '0001-01-01') + 1;
$$;

create or replace function private.utc_today() returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'utc')::date;
$$;

create or replace function public.server_now() returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('now', extract(epoch from now()), 'day', private.era_day(), 'date', private.utc_today());
$$;

create or replace function public.my_day() returns int language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_user();
  return private.era_day();
end $$;

create or replace function private.rarity_rank(r text) returns int language sql immutable as $$
  select case r when 'rare' then 1 when 'epic' then 2 when 'legendary' then 3 else 0 end;
$$;

create or replace function private.rarity_edition(r text) returns int language sql immutable as $$
  select case r when 'rare' then 1500 when 'epic' then 500 when 'legendary' then 100 else 5000 end;
$$;

-- A whole number from a JSON value, clamped; anything that is not a number counts as lo.
create or replace function private.json_int(v jsonb, lo int, hi int) returns int language sql immutable as $$
  select case when jsonb_typeof(v) = 'number' then least(hi, greatest(lo, floor((v #>> '{}')::numeric)))::int else lo end;
$$;

create or replace function private.season_start(n int) returns date language sql stable set search_path = '' as $$
  select (select starts from private.store_seasons where season = 1) + (greatest(1, n) - 1) * private.store_setting('seasonDays');
$$;

create or replace function private.current_season() returns int language sql stable set search_path = '' as $$
  select greatest(1, (private.utc_today() - (select starts from private.store_seasons where season = 1)) / private.store_setting('seasonDays') + 1);
$$;

-- Seasons past the last file reuse the newest regular season's rewards, as the app does.
create or replace function private.pass_season_def(n int) returns int language sql stable set search_path = '' as $$
  select coalesce((select season from private.store_seasons where season = n),
                  (select max(season) from private.store_seasons where not founder),
                  (select max(season) from private.store_seasons));
$$;

-- Items of a season that has not started are hidden everywhere, boxes included.
create or replace function private.theme_live(th text) returns boolean language sql stable set search_path = '' as $$
  select th = 'classic'
      or not exists (select 1 from private.store_seasons s where s.theme = th)
      or exists (select 1 from private.store_seasons s where s.theme = th and s.starts <= private.utc_today());
$$;

-- Every credit goes through here: gold owed after a refund is paid back first.
create or replace function private.store_credit(uid uuid, amount int, kind text, ref text default '') returns void
language plpgsql security definer set search_path = '' as $$
declare w public.gold_wallets; pay int;
begin
  if amount is null or amount <= 0 then return; end if;
  w := private.wallet(uid);
  pay := least(w.debt, amount);
  update public.gold_wallets set balance = balance + amount - pay, debt = debt - pay where user_id = uid;
  insert into public.gold_ledger (user_id, delta, kind, ref) values (uid, amount, left(kind, 40), left(coalesce(ref, ''), 80));
  if pay > 0 then insert into public.gold_ledger (user_id, delta, kind, ref) values (uid, -pay, 'debt_paid', left(coalesce(ref, ''), 80)); end if;
end $$;

create or replace function private.store_spend(uid uuid, amount int, kind text, ref text) returns void
language plpgsql security definer set search_path = '' as $$
declare w public.gold_wallets := private.wallet(uid);
begin
  if w.debt > 0 then raise exception 'in_debt:%', w.debt using errcode = 'P0001'; end if;
  perform private.gold_spend(uid, amount, left(kind, 40), left(coalesce(ref, ''), 80));
end $$;

-- One lock per account for every store change; a request id that already ran returns its first answer.
create or replace function private.store_request(uid uuid, p_request text, p_kind text, per_minute int, per_day int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if p_request is null or char_length(p_request) not between 8 and 64 then raise exception 'invalid_request' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  select result into r from public.store_requests where user_id = uid and request_id = p_request;
  if found then return r; end if;
  if (select count(*) from public.store_requests where user_id = uid and created_at > now() - interval '1 minute') >= per_minute
     or (select count(*) from public.store_requests where user_id = uid and kind = p_kind and created_at > now() - interval '1 day') >= per_day then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  return null;
end $$;

create or replace function private.store_done(uid uuid, p_request text, p_kind text, p_result jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.store_requests (user_id, request_id, kind, result) values (uid, p_request, p_kind, coalesce(p_result, '{}'::jsonb));
  delete from public.store_requests where user_id = uid and created_at < now() - interval '30 days';
end $$;

create or replace function private.add_boxes(uid uuid, p_kind text, n int) returns void language sql security definer set search_path = '' as $$
  insert into public.gold_box_stock (user_id, kind, count) values (uid, p_kind, greatest(0, n))
  on conflict (user_id, kind) do update set count = public.gold_box_stock.count + excluded.count;
$$;

create or replace function private.pick_serial(uid uuid, p_def text, p_rarity text) returns int
language plpgsql volatile security definer set search_path = '' as $$
declare ed int := private.rarity_edition(p_rarity); s int; tries int := 0;
begin
  loop
    s := least(ed, greatest(1, 1 + floor(random() * ed)::int));
    exit when tries >= 8 or not exists (select 1 from public.store_cabinet where user_id = uid and def_id = p_def and serial = s);
    tries := tries + 1;
  end loop;
  return s;
end $$;

-- Adds a piece and pays any collection it completes (its reward cosmetic). Returns the collections completed.
create or replace function private.cabinet_add(uid uuid, p_def text, p_serial int, p_origin text, p_source text) returns text[]
language plpgsql security definer set search_path = '' as $$
declare got int; done text[] := '{}'; c record;
begin
  insert into public.store_cabinet (user_id, def_id, serial, origin, source) values (uid, p_def, p_serial, p_origin, p_source) on conflict do nothing;
  get diagnostics got = row_count;
  if got = 0 then return done; end if;
  for c in
    select col.id, col.reward_id from private.store_collections col
     where private.theme_live(col.theme)
       and not exists (select 1 from public.store_collections_done d where d.user_id = uid and d.collection_id = col.id)
       and exists (select 1 from private.store_items i where i.collection = col.id)
       and not exists (select 1 from private.store_items i where i.collection = col.id
                         and not exists (select 1 from public.store_cabinet k where k.user_id = uid and k.def_id = i.id))
     order by col.id
  loop
    insert into public.store_collections_done (user_id, collection_id) values (uid, c.id) on conflict do nothing;
    insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (uid, c.reward_id, 'collection') on conflict do nothing;
    done := done || c.id;
  end loop;
  return done;
end $$;

create or replace function private.has_premium(uid uuid, n int) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.pass_owners where user_id = uid and season = n)
      or exists (select 1 from public.store_plans where user_id = uid and revoked_at is null
                  and product_id in ('com.ledger.plus.monthly', 'com.ledger.plus.yearly') and expires_at > now() - interval '3 days')
      or (n = 1 and exists (select 1 from public.store_perks where user_id = uid and perk = 'founder'));
$$;

-- The highest tier a player can have reached by now: a generous day, week and month allowance of pass XP
-- (the app caps a day well below 200), plus tiers bought with the pass and XP rewards already claimed.
create or replace function private.pass_tier_ceiling(uid uuid, n int) returns int language plpgsql stable security definer set search_path = '' as $$
declare days int := greatest(1, (private.utc_today() - private.season_start(n)) + 1); xp int;
begin
  xp := days * 200 + ceil(days / 7.0)::int * 120 + ceil(days / 30.0)::int * 240
      + coalesce((select bonus_tiers from public.pass_owners where user_id = uid and season = n), 0) * 300
      + coalesce((select sum(r.amount) from public.pass_claims c
                    join private.store_pass_rewards r on r.season = private.pass_season_def(n) and r.track = c.track and r.tier = c.tier and r.kind = 'xp'
                   where c.user_id = uid and c.season = n), 0);
  return least(30, xp / 300);
end $$;

create or replace function private.store_state_for(uid uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare w public.gold_wallets := private.wallet(uid); v_season int := private.current_season(); v_today int := private.era_day(); used int; cutoff timestamptz;
begin
  used := coalesce((select sum(gold) from public.money_claims where user_id = uid and kind = 'pack' and created_at > now() - interval '7 days'), 0);
  select at into cutoff from private.store_config where key = 'import_cutoff';
  return jsonb_build_object(
    'account', uid,
    'serverTime', extract(epoch from now()),
    'serverDay', v_today,
    'season', v_season,
    'wallet', jsonb_build_object('balance', w.balance - w.held),
    'debt', w.debt,
    'boxes', coalesce((select jsonb_object_agg(kind, count) from public.gold_box_stock where user_id = uid and count > 0), '{}'::jsonb),
    'pity', jsonb_build_object('sinceRare', w.pity),
    'firstPurchaseDone', w.first_purchase_done,
    'boxesOpened', w.boxes_opened,
    'cabinet', jsonb_build_object(
      'items', coalesce((select jsonb_agg(jsonb_build_object('defID', def_id, 'serial', serial, 'origin', origin) order by acquired_at, def_id, serial)
                           from public.store_cabinet where user_id = uid), '[]'::jsonb),
      'rewarded', coalesce((select jsonb_agg(collection_id order by collection_id) from public.store_collections_done where user_id = uid), '[]'::jsonb)),
    'cosmetics', coalesce((select jsonb_agg(cosmetic_id order by cosmetic_id) from public.cosmetic_grants where user_id = uid), '[]'::jsonb),
    'premium', private.has_premium(uid, v_season),
    'passBonusTiers', coalesce((select bonus_tiers from public.pass_owners where user_id = uid and season = v_season), 0),
    'passClaims', coalesce((select jsonb_agg(track || tier::text order by track, tier) from public.pass_claims where user_id = uid and season = v_season), '[]'::jsonb),
    'levelGoldPaid', w.level_gold_paid,
    'streak', jsonb_build_object('count', w.streak_count, 'best', w.streak_best, 'openedToday', w.streak_day = v_today),
    'freeMoneyLeft', greatest(0, private.store_setting('freeMoneyPerDay')
                       - (select count(*) from public.money_claims where user_id = uid and kind = 'free' and day = v_today)::int),
    'moneyWeek', jsonb_build_object('used', used, 'cap', private.store_setting('moneyPackWeeklyGold')),
    'unpaidMoney', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'pack', pack_id, 'amount', amount) order by created_at)
                               from public.money_claims where user_id = uid and paid_at is null and created_at > now() - interval '14 days'), '[]'::jsonb),
    'imported', exists (select 1 from public.store_imports where user_id = uid),
    'importsGold', coalesce((select created_at from public.profiles where id = uid) <= cutoff, false));
end $$;

create or replace function public.store_state() returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return private.store_state_for(private.require_player());
end $$;

-- One box roll with the published odds. Paid boxes keep the pity count: the tenth paid box in a row without
-- a rare or better roll can only roll a rare or better item. Prizes are paid here.
create or replace function private.roll_box(uid uuid, p_kind text, p_paid boolean, p_pity int, p_claim text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare guaranteed boolean := p_paid and p_pity >= 9; total int; pick double precision; acc int := 0; r record; chosen record;
        item record; cos text; doubled boolean; done text[] := '{}'; s int; content jsonb; pool_kind text;
begin
  select coalesce(sum(weight), 0) into total from private.store_box_rows
   where kind = p_kind and (not guaranteed or (prize not in ('gold', 'money') and private.rarity_rank(rarity) >= 1));
  if total = 0 then raise exception 'unknown_item' using errcode = 'P0001'; end if;
  select * into chosen from private.store_box_rows
   where kind = p_kind and (not guaranteed or (prize not in ('gold', 'money') and private.rarity_rank(rarity) >= 1))
   order by pos desc limit 1;
  pick := random() * total;
  for r in select * from private.store_box_rows
            where kind = p_kind and (not guaranteed or (prize not in ('gold', 'money') and private.rarity_rank(rarity) >= 1)) order by pos loop
    acc := acc + r.weight;
    if pick < acc then chosen := r; exit; end if;
  end loop;

  if chosen.prize = 'gold' then
    doubled := not p_paid and random() < 0.01;
    content := jsonb_build_object('type', 'gold', 'amount', chosen.amount * case when doubled then 2 else 1 end, 'doubled', doubled);
    perform private.store_credit(uid, chosen.amount * case when doubled then 2 else 1 end, 'box_gold', p_claim);
  elsif chosen.prize = 'money' then
    insert into public.money_claims (id, user_id, kind, amount, day) values (p_claim, uid, 'prize', chosen.amount, private.era_day());
    content := jsonb_build_object('type', 'money', 'amount', chosen.amount, 'claimID', p_claim);
  else
    if chosen.prize = 'cosmetic' then
      select c.id into cos from private.store_cosmetics c
       where c.rarity = chosen.rarity and c.kind <> 'saveSlot' and c.source in ('box', 'store') and private.theme_live(c.theme)
         and not exists (select 1 from public.cosmetic_grants g where g.user_id = uid and g.cosmetic_id = c.id)
       order by random() limit 1;
      if cos is not null then
        insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (uid, cos, 'box') on conflict do nothing;
        content := jsonb_build_object('type', 'cosmetic', 'id', cos);
      end if;
    end if;
    if content is null then
      pool_kind := case chosen.prize when 'profileCard' then 'profileCard' when 'companyCard' then 'companyCard' else 'artifact' end;
      select i.id, i.rarity into item from private.store_items i
       where i.kind = pool_kind and i.rarity = chosen.rarity and private.theme_live(i.theme) order by random() limit 1;
      if item.id is null then
        select i.id, i.rarity into item from private.store_items i
         where i.kind = 'artifact' and i.rarity = chosen.rarity and private.theme_live(i.theme) order by random() limit 1;
      end if;
      if item.id is null then raise exception 'unknown_item' using errcode = 'P0001'; end if;
      s := private.pick_serial(uid, item.id, item.rarity);
      done := private.cabinet_add(uid, item.id, s, 'found', 'box');
      content := jsonb_build_object('type', 'artifact', 'defID', item.id, 'serial', s);
    end if;
  end if;
  return jsonb_build_object('rarity', chosen.rarity, 'guaranteed', guaranteed, 'content', content, 'completed', to_jsonb(done));
end $$;

create or replace function public.open_boxes(p_kind text, p_count int, p_request text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); prev jsonb; bk private.store_box_kinds; stock int; from_stock int; to_buy int;
        w public.gold_wallets; v_pity int; paid boolean; res jsonb := '[]'::jsonb; one jsonb; done text[] := '{}'; out jsonb;
begin
  perform private.require_free(uid, 'gold');
  prev := private.store_request(uid, p_request, 'open', 30, 500);
  if prev is not null then return prev || jsonb_build_object('state', private.store_state_for(uid)); end if;
  select * into bk from private.store_box_kinds where kind = p_kind;
  if not found then raise exception 'unknown_item' using errcode = 'P0001'; end if;
  if p_count is null or p_count < 1 or p_count > 10 then raise exception 'invalid_amount' using errcode = 'P0001'; end if;
  w := private.wallet(uid);
  paid := bk.price > 0;
  stock := coalesce((select count from public.gold_box_stock where user_id = uid and kind = p_kind), 0);
  from_stock := least(stock, p_count);
  to_buy := p_count - from_stock;
  if to_buy > 0 then
    if not paid then raise exception 'no_box' using errcode = 'P0001'; end if;
    perform private.store_spend(uid, to_buy * bk.price, 'box', p_kind || ':' || p_request);
  end if;
  if from_stock > 0 then update public.gold_box_stock set count = count - from_stock where user_id = uid and kind = p_kind; end if;
  v_pity := w.pity;
  for i in 1..p_count loop
    one := private.roll_box(uid, p_kind, paid, v_pity, p_request || ':' || i);
    if paid then v_pity := case when private.rarity_rank(one ->> 'rarity') >= 1 then 0 else least(100, v_pity + 1) end; end if;
    done := done || array(select jsonb_array_elements_text(one -> 'completed'));
    res := res || jsonb_build_array(one - 'completed');
  end loop;
  update public.gold_wallets set pity = v_pity, boxes_opened = boxes_opened + p_count where user_id = uid;
  out := jsonb_build_object('kind', p_kind, 'results', res, 'completed', to_jsonb(done));
  perform private.store_done(uid, p_request, 'open', out);
  return out || jsonb_build_object('state', private.store_state_for(uid));
end $$;

-- Gold spent on a box bundle, a store cosmetic, a profile icon, a service or a money pack.
-- Money packs pay the game through the app once the server has taken the gold; the weekly limit counts gold.
create or replace function public.store_buy(p_kind text, p_id text, p_request text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); prev jsonb; out jsonb; b private.store_box_bundles; c private.store_cosmetics; v_price int;
        mp private.store_money_packs; used int; cap int := private.store_setting('moneyPackWeeklyGold');
begin
  perform private.require_free(uid, 'gold');
  prev := private.store_request(uid, p_request, 'buy', 20, 300);
  if prev is not null then return prev || jsonb_build_object('state', private.store_state_for(uid)); end if;
  if p_kind = 'bundle' then
    select * into b from private.store_box_bundles where id = p_id;
    if not found then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    perform private.store_spend(uid, b.price, 'bundle', p_id);
    perform private.add_boxes(uid, b.kind, b.count);
    out := jsonb_build_object('kind', p_kind, 'id', p_id);
  elsif p_kind in ('cosmetic', 'avatar') then
    select * into c from private.store_cosmetics k where k.id = p_id and k.price is not null and private.theme_live(k.theme)
       and ((p_kind = 'cosmetic' and k.source = 'store') or (p_kind = 'avatar' and k.source = 'avatar'));
    if not found then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    if exists (select 1 from public.cosmetic_grants where user_id = uid and cosmetic_id = p_id) then raise exception 'already_owned' using errcode = 'P0001'; end if;
    perform private.store_spend(uid, c.price, p_kind, p_id);
    insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (uid, p_id, 'store');
    out := jsonb_build_object('kind', p_kind, 'id', p_id);
  elsif p_kind = 'service' then
    select s.price into v_price from private.store_services s where s.id = p_id;
    if v_price is null then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    perform private.store_spend(uid, v_price, 'service', p_id);
    out := jsonb_build_object('kind', p_kind, 'id', p_id);
  elsif p_kind = 'money' then
    select * into mp from private.store_money_packs where id = p_id and not free;
    if not found then raise exception 'unknown_item' using errcode = 'P0001'; end if;
    used := coalesce((select sum(gold) from public.money_claims where user_id = uid and kind = 'pack' and created_at > now() - interval '7 days'), 0);
    if used + mp.gold > cap then raise exception 'weekly_limit:%', greatest(0, cap - used) using errcode = 'P0001'; end if;
    perform private.store_spend(uid, mp.gold, 'money_pack', p_id);
    insert into public.money_claims (id, user_id, kind, pack_id, gold, day) values (p_request, uid, 'pack', p_id, mp.gold, private.era_day());
    out := jsonb_build_object('kind', p_kind, 'id', p_id, 'claimID', p_request);
  else
    raise exception 'unknown_item' using errcode = 'P0001';
  end if;
  perform private.store_done(uid, p_request, 'buy', out);
  return out || jsonb_build_object('state', private.store_state_for(uid));
end $$;

create or replace function public.claim_free_money(p_request text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); prev jsonb; out jsonb; v_today int := private.era_day();
begin
  prev := private.store_request(uid, p_request, 'free', 10, 20);
  if prev is not null then return prev || jsonb_build_object('state', private.store_state_for(uid)); end if;
  if (select count(*) from public.money_claims where user_id = uid and kind = 'free' and day = v_today) >= private.store_setting('freeMoneyPerDay') then
    raise exception 'daily_limit' using errcode = 'P0001';
  end if;
  insert into public.money_claims (id, user_id, kind, pack_id, day) values (p_request, uid, 'free', 'free', v_today);
  out := jsonb_build_object('kind', 'free', 'id', 'free', 'claimID', p_request);
  perform private.store_done(uid, p_request, 'free', out);
  return out || jsonb_build_object('state', private.store_state_for(uid));
end $$;

-- The app calls this once the game has booked the money, so a crash in between pays on the next start instead.
create or replace function public.confirm_money_claims(p_ids text[]) returns int language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); n int;
begin
  update public.money_claims set paid_at = now()
   where user_id = uid and paid_at is null and id = any ((coalesce(p_ids, '{}'::text[]))[1:50]);
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.claim_pass_tier(p_season int, p_track text, p_tier int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v_season int := private.current_season(); rw private.store_pass_rewards; got int;
        done text[] := '{}'; item jsonb; s int; rar text;
begin
  perform private.require_free(uid, 'gold');
  if p_season is distinct from v_season then raise exception 'season_over' using errcode = 'P0001'; end if;
  if p_track is null or p_track not in ('f', 'p') or p_tier is null or p_tier < 1 or p_tier > 30 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  select * into rw from private.store_pass_rewards where season = private.pass_season_def(v_season) and track = p_track and tier = p_tier;
  if not found then raise exception 'no_reward' using errcode = 'P0001'; end if;
  if p_track = 'p' and not private.has_premium(uid, v_season) then raise exception 'needs_premium' using errcode = 'P0001'; end if;
  if p_tier > private.pass_tier_ceiling(uid, v_season) then raise exception 'tier_not_reached' using errcode = 'P0001'; end if;
  insert into public.pass_claims (user_id, season, track, tier, reward_id) values (uid, v_season, p_track, p_tier, rw.reward_id) on conflict do nothing;
  get diagnostics got = row_count;
  if got = 0 then raise exception 'already_claimed' using errcode = 'P0001'; end if;
  if rw.kind = 'gold' then
    perform private.store_credit(uid, rw.amount, 'pass', v_season || p_track || p_tier);
  elsif rw.kind = 'box' then
    perform private.add_boxes(uid, 'free', rw.amount);
  elsif rw.kind in ('profileCard', 'companyCard', 'artifact') then
    select rarity into rar from private.store_items where id = rw.reward_id;
    s := private.pick_serial(uid, rw.reward_id, coalesce(rar, 'common'));
    done := private.cabinet_add(uid, rw.reward_id, s, 'found', 'pass');
    item := jsonb_build_object('defID', rw.reward_id, 'serial', s);
  elsif rw.kind <> 'xp' then
    insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (uid, rw.reward_id, 'pass') on conflict do nothing;
  end if;
  return jsonb_build_object('reward', jsonb_build_object('id', rw.reward_id, 'kind', rw.kind, 'amount', rw.amount, 'item', item),
                            'completed', to_jsonb(done), 'state', private.store_state_for(uid));
end $$;

-- Level gold and level cards, paid once per account. At most 30 levels a day count, so a forged level gains little.
create or replace function public.claim_level_gold(p_level int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); w public.gold_wallets; v_today int := private.era_day(); base int; target int; gold int := 0;
        c record; s int; cards jsonb := '[]'::jsonb; done text[] := '{}';
begin
  if p_level is null or p_level < 1 or p_level > 1000 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  w := private.wallet(uid);
  base := case when w.level_day = v_today then w.level_day_base else w.level_gold_paid end;
  target := least(p_level, base + 30);
  if target > w.level_gold_paid then
    gold := coalesce((select sum(r.gold) from private.store_level_rewards r where r.level > w.level_gold_paid and r.level <= target), 0);
    update public.gold_wallets set level_gold_paid = target, level_day = v_today, level_day_base = base where user_id = uid;
    perform private.store_credit(uid, gold, 'level', target::text);
  end if;
  for c in
    select lc.card_id, coalesce(i.rarity, 'common') as rarity from private.store_level_cards lc
      left join private.store_items i on i.id = lc.card_id
     where lc.level <= greatest(target, w.level_gold_paid)
       and not exists (select 1 from public.level_card_grants g where g.user_id = uid and g.card_id = lc.card_id)
     order by lc.level
  loop
    insert into public.level_card_grants (user_id, card_id) values (uid, c.card_id);
    s := private.pick_serial(uid, c.card_id, c.rarity);
    done := done || private.cabinet_add(uid, c.card_id, s, 'found', 'level');
    cards := cards || jsonb_build_array(jsonb_build_object('defID', c.card_id, 'serial', s));
  end loop;
  return jsonb_build_object('gold', gold, 'paidTo', greatest(target, w.level_gold_paid), 'cards', cards, 'completed', to_jsonb(done),
                            'state', private.store_state_for(uid));
end $$;

-- The login streak counts server days: a gap of up to 7 days keeps it, a longer one halves it.
create or replace function public.claim_login_day() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); w public.gold_wallets; v_today int := private.era_day(); n int; gold int; box int;
begin
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  w := private.wallet(uid);
  if w.streak_day >= v_today then
    return jsonb_build_object('opened', false, 'count', w.streak_count, 'best', w.streak_best, 'gold', 0, 'boxes', 0, 'state', private.store_state_for(uid));
  end if;
  n := case when w.streak_day = 0 then 1 when v_today - w.streak_day <= 7 then w.streak_count + 1 else greatest(1, w.streak_count / 2) + 1 end;
  gold := least(3, 1 + n / 10);
  box := case when n % 7 = 0 then 1 else 0 end;
  update public.gold_wallets set streak_count = n, streak_best = greatest(streak_best, n), streak_day = v_today where user_id = uid;
  perform private.store_credit(uid, gold, 'login', v_today::text);
  if box > 0 then perform private.add_boxes(uid, 'free', box); end if;
  return jsonb_build_object('opened', true, 'count', n, 'best', greatest(w.streak_best, n), 'gold', gold, 'boxes', box, 'state', private.store_state_for(uid));
end $$;

-- Friend race gold for a finished week: 3, 2 and 1 gold for the top three, when at least one racer is behind.
create or replace function public.claim_race_gold(p_week int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); wk int := private.friend_week(); mine numeric; my_name text; racers int; place int; gold int; got int;
begin
  if p_week is null or p_week >= wk or p_week < wk - 4 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  select growth into mine from public.friend_race_scores where user_id = uid and week = p_week;
  if mine is null then raise exception 'no_reward' using errcode = 'P0001'; end if;
  my_name := private.display_name(uid);
  with field as (
    select s.user_id, s.growth, private.display_name(s.user_id) as nm from public.friend_race_scores s
     where s.week = p_week and (s.user_id = uid or s.user_id in (select private.friend_ids(uid))))
  select count(*), 1 + count(*) filter (where user_id <> uid and (growth > mine or (growth = mine and nm < my_name)))
    into racers, place from field;
  gold := case when place < racers then (array[3, 2, 1])[place] else null end;
  if gold is null then raise exception 'no_reward' using errcode = 'P0001'; end if;
  insert into public.race_gold_claims (user_id, week, gold) values (uid, p_week, gold) on conflict do nothing;
  get diagnostics got = row_count;
  if got = 0 then raise exception 'already_claimed' using errcode = 'P0001'; end if;
  perform private.store_credit(uid, gold, 'race', p_week::text);
  return jsonb_build_object('gold', gold, 'place', place, 'state', private.store_state_for(uid));
end $$;

-- Retired items the account owns pay their gold back once each, at most 300 gold per account.
create or replace function public.claim_refund_retired() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); paid int; total int := 0; r record; g int;
begin
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  paid := coalesce((select sum(gold) from public.store_refunds where user_id = uid), 0);
  for r in
    select rt.id, rt.gold from private.store_retired rt
     where exists (select 1 from public.cosmetic_grants g where g.user_id = uid and g.cosmetic_id = rt.id)
       and not exists (select 1 from public.store_refunds f where f.user_id = uid and f.item_id = rt.id)
     order by rt.id
  loop
    g := least(r.gold, greatest(0, 300 - paid));
    insert into public.store_refunds (user_id, item_id, gold) values (uid, r.id, g);
    paid := paid + g;
    total := total + g;
  end loop;
  perform private.store_credit(uid, total, 'refund_retired', '');
  return jsonb_build_object('gold', total, 'state', private.store_state_for(uid));
end $$;

-- Quick sale: the pieces leave the cabinet here; the app pays their market price into the open game.
create or replace function public.quick_sell(p_items jsonb, p_request text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); prev jsonb; e jsonb; sold jsonb := '[]'::jsonb; d text; s int; rar text; got int; out jsonb;
begin
  perform private.require_free(uid, 'gold');
  prev := private.store_request(uid, p_request, 'sell', 20, 200);
  if prev is not null then return prev || jsonb_build_object('state', private.store_state_for(uid)); end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  for e in select value from jsonb_array_elements(p_items) loop
    d := e ->> 'defID';
    s := private.json_int(e -> 'serial', 0, 100000);
    continue when d is null or s < 1;
    delete from public.store_cabinet k
     where k.user_id = uid and k.def_id = d and k.serial = s and k.origin <> 'bought'
       and not coalesce((select i.bound from private.store_items i where i.id = d), true);
    get diagnostics got = row_count;
    if got > 0 then
      select i.rarity into rar from private.store_items i where i.id = d;
      sold := sold || jsonb_build_array(jsonb_build_object('defID', d, 'serial', s, 'rarity', rar));
    end if;
  end loop;
  if jsonb_array_length(sold) = 0 then raise exception 'not_yours' using errcode = 'P0001'; end if;
  out := jsonb_build_object('sold', sold);
  perform private.store_done(uid, p_request, 'sell', out);
  return out || jsonb_build_object('state', private.store_state_for(uid));
end $$;

-- A gift moves a piece the sender holds and may trade; it leaves the sender's cabinet when sent.
create or replace function public.send_friend_gift(p_to uuid, p_def_id text, p_serial int) returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); gid uuid; got int;
begin
  if p_to is null or p_to = uid then raise exception 'cannot_target_self' using errcode = 'P0001'; end if;
  if p_def_id is null or char_length(p_def_id) not between 1 and 80 or p_serial is null or p_serial < 1 then raise exception 'invalid_gift' using errcode = 'P0001'; end if;
  if not exists (select 1 from private.friend_ids(uid) f where f = p_to) then raise exception 'not_found' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  delete from public.store_cabinet k
   where k.user_id = uid and k.def_id = p_def_id and k.serial = p_serial and k.origin <> 'bought' and k.source <> 'import_late'
     and not coalesce((select i.bound from private.store_items i where i.id = p_def_id), true);
  get diagnostics got = row_count;
  if got = 0 then raise exception 'not_yours' using errcode = 'P0001'; end if;
  begin
    insert into public.friend_gifts (sender_id, recipient_id, sender_name, def_id, serial)
      values (uid, p_to, private.display_name(uid), p_def_id, p_serial) returning id into gid;
  exception when unique_violation then
    raise exception 'gift_limit' using errcode = 'P0001';
  end;
  return gid;
end $$;

create or replace function public.accept_friend_gifts(p_ids uuid[]) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); g record;
begin
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  for g in
    update public.friend_gifts set accepted_at = now()
     where recipient_id = uid and accepted_at is null and id = any (coalesce(p_ids, '{}'::uuid[]))
    returning def_id, serial
  loop
    if exists (select 1 from private.store_items i where i.id = g.def_id and g.serial between 1 and private.rarity_edition(i.rarity)) then
      perform private.cabinet_add(uid, g.def_id, g.serial, 'acquired', 'gift');
    end if;
  end loop;
end $$;

-- One-time move of the phone's old wallet to the account. Accounts made before this migration bring gold,
-- boxes and the premium pass (capped); later accounts bring at most 30 pieces, which cannot be gifted.
-- Lists of what was already claimed or paid always come over, so nothing is paid twice.
create or replace function public.import_local_store(p_device text, p_store jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); dh text; full_import boolean; v_gold int := 0; n int; k text; v jsonb; e jsonb; d text; s int;
        org text; items int := 0; cos int := 0; v_season int := private.current_season(); v_today int := private.era_day(); rw private.store_pass_rewards;
begin
  if p_device is null or char_length(p_device) not between 8 and 100 or p_store is null or jsonb_typeof(p_store) <> 'object' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  dh := encode(extensions.digest(p_device, 'sha256'), 'hex');
  if exists (select 1 from public.store_imports where user_id = uid) then
    return jsonb_build_object('imported', false, 'reason', 'already', 'state', private.store_state_for(uid));
  end if;
  if exists (select 1 from public.store_imports where device_hash = dh) then
    return jsonb_build_object('imported', false, 'reason', 'device', 'state', private.store_state_for(uid));
  end if;
  full_import := coalesce((select p.created_at <= c.at from public.profiles p, private.store_config c where p.id = uid and c.key = 'import_cutoff'), false);
  perform private.wallet(uid);

  if full_import then
    v_gold := private.json_int(p_store -> 'gold', 0, 2000);
    perform private.store_credit(uid, v_gold, 'import', '');
    for k, v in select key, value from jsonb_each(coalesce(p_store -> 'boxes', '{}'::jsonb)) loop
      continue when not exists (select 1 from private.store_box_kinds b where b.kind = k);
      n := private.json_int(v, 0, 20);
      if n > 0 then perform private.add_boxes(uid, k, n); end if;
    end loop;
    update public.gold_wallets set pity = private.json_int(p_store -> 'pity', 0, 9),
      first_purchase_done = first_purchase_done or coalesce((p_store ->> 'firstPurchaseDone')::boolean, false),
      streak_count = private.json_int(p_store -> 'streak', 0, 400),
      streak_best = greatest(private.json_int(p_store -> 'streak', 0, 400), private.json_int(p_store -> 'streakBest', 0, 400)),
      streak_day = case when private.json_int(p_store -> 'streak', 0, 400) > 0
                        then v_today - case when coalesce((p_store ->> 'streakOpenedToday')::boolean, false) then 0 else 1 end else 0 end
     where user_id = uid;
    if private.json_int(p_store -> 'premiumSeason', 0, 1000) = v_season then
      insert into public.pass_owners (user_id, season, source) values (uid, v_season, 'import') on conflict do nothing;
    end if;
    for d in select value from jsonb_array_elements_text(case when jsonb_typeof(p_store -> 'cosmetics') = 'array' then p_store -> 'cosmetics' else '[]'::jsonb end) limit 400 loop
      if exists (select 1 from private.store_cosmetics c where c.id = d and c.source in ('box', 'store', 'collection', 'season', 'retired', 'avatar')) then
        insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (uid, d, 'import') on conflict do nothing;
        cos := cos + 1;
      end if;
    end loop;
  end if;

  for e in select value from jsonb_array_elements(case when jsonb_typeof(p_store -> 'items') = 'array' then p_store -> 'items' else '[]'::jsonb end)
            limit case when full_import then 200 else 30 end loop
    d := e ->> 'defID';
    s := private.json_int(e -> 'serial', 0, 100000);
    org := coalesce(e ->> 'origin', 'found');
    continue when d is null or org not in ('found', 'acquired', 'bought')
      or not exists (select 1 from private.store_items i where i.id = d and s between 1 and private.rarity_edition(i.rarity));
    perform private.cabinet_add(uid, d, s, org, case when full_import then 'import' else 'import_late' end);
    items := items + 1;
  end loop;

  for k in select value from jsonb_array_elements_text(case when jsonb_typeof(p_store -> 'passClaims') = 'array' then p_store -> 'passClaims' else '[]'::jsonb end) limit 60 loop
    continue when k !~ '^[fp][0-9]{1,2}$';
    select * into rw from private.store_pass_rewards where season = private.pass_season_def(v_season) and track = left(k, 1) and tier = substr(k, 2)::int;
    if found then
      insert into public.pass_claims (user_id, season, track, tier, reward_id) values (uid, v_season, rw.track, rw.tier, rw.reward_id) on conflict do nothing;
    end if;
  end loop;
  update public.gold_wallets set level_gold_paid = greatest(level_gold_paid, private.json_int(p_store -> 'levelGoldPaid', 0, 1000)) where user_id = uid;
  insert into public.level_card_grants (user_id, card_id)
    select uid, c.card_id from private.store_level_cards c
     where c.card_id in (select value from jsonb_array_elements_text(case when jsonb_typeof(p_store -> 'levelCards') = 'array' then p_store -> 'levelCards' else '[]'::jsonb end))
    on conflict do nothing;
  insert into public.store_refunds (user_id, item_id, gold)
    select uid, r.id, 0 from private.store_retired r
     where r.id in (select value from jsonb_array_elements_text(case when jsonb_typeof(p_store -> 'refunded') = 'array' then p_store -> 'refunded' else '[]'::jsonb end))
    on conflict do nothing;

  insert into public.store_imports (user_id, device_hash, gold, items, cosmetics) values (uid, dh, v_gold, items, cos);
  return jsonb_build_object('imported', true, 'full', full_import, 'gold', v_gold, 'items', items, 'cosmetics', cos, 'state', private.store_state_for(uid));
end $$;

-- Refunds: unspent gold and boxes are taken back; what was already spent becomes a debt that blocks spending
-- until earned or bought gold has paid it.
create or replace function private.revoke_transaction(p_original text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t public.store_transactions; w public.gold_wallets; took int; owe int; have int; btook int := 0; plans int;
begin
  select * into t from public.store_transactions where original_transaction_id = p_original for update;
  if not found then
    update public.store_plans set revoked_at = now(), updated_at = now() where original_transaction_id = p_original and revoked_at is null;
    get diagnostics plans = row_count;
    return jsonb_build_object('revoked', plans > 0, 'clawed', 0, 'debt', 0);
  end if;
  if t.revoked_at is not null then return jsonb_build_object('revoked', false, 'reason', 'already', 'clawed', 0, 'debt', 0); end if;
  perform pg_advisory_xact_lock(hashtext('store:' || t.user_id::text));
  w := private.wallet(t.user_id);
  took := least(t.gold, w.balance - w.held);
  owe := t.gold - took;
  if t.box_kind is not null and t.box_count > 0 then
    have := coalesce((select count from public.gold_box_stock where user_id = t.user_id and kind = t.box_kind), 0);
    btook := least(have, t.box_count);
    update public.gold_box_stock set count = count - btook where user_id = t.user_id and kind = t.box_kind;
    owe := owe + (t.box_count - btook) * coalesce((select price from private.store_box_kinds where kind = t.box_kind), 0);
  end if;
  update public.gold_wallets set balance = balance - took, debt = debt + owe where user_id = t.user_id;
  insert into public.gold_ledger (user_id, delta, kind, ref) values (t.user_id, -took, 'refund', left(p_original, 80));
  if t.product_id in ('com.ledger.season.bundle', 'com.ledger.season.levels') then
    delete from public.pass_owners where user_id = t.user_id and season = t.season and source = t.product_id;
    if t.product_id = 'com.ledger.season.levels' then
      update public.pass_owners set bonus_tiers = case when source = 'founder' then private.store_setting('founderPassTiers') else 0 end
       where user_id = t.user_id and season = t.season;
    end if;
  end if;
  if exists (select 1 from public.store_perks where user_id = t.user_id and original_transaction_id = p_original and perk = 'founder') then
    delete from public.pass_owners where user_id = t.user_id and source = 'founder';
  end if;
  delete from public.store_perks where user_id = t.user_id and original_transaction_id = p_original;
  update public.store_plans set revoked_at = now(), updated_at = now() where original_transaction_id = p_original and revoked_at is null;
  update public.store_transactions set revoked_at = now(), clawed = took, debt_added = owe where original_transaction_id = p_original;
  return jsonb_build_object('revoked', true, 'clawed', took, 'boxes', btook, 'debt', owe);
end $$;

create or replace function private.check_transaction(p_original text, p_product text, p_tx jsonb) returns void
language plpgsql immutable as $$
begin
  if p_original is null or char_length(p_original) not between 1 and 64 or p_product is null or p_tx is null or jsonb_typeof(p_tx) <> 'object' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if p_tx ->> 'originalTransactionId' is distinct from p_original or p_tx ->> 'productId' is distinct from p_product then
    raise exception 'mismatch' using errcode = 'P0001';
  end if;
  if p_tx ->> 'bundleId' is distinct from 'com.matasdovyda.ledger' then raise exception 'wrong_app' using errcode = 'P0001'; end if;
end $$;

-- Called only by the store-purchase edge function after it has verified Apple's signature on the transaction.
-- Each original transaction pays once; Pro and Founder gold pays once per account and never again on restore.
create or replace function public.grant_purchase(p_user uuid, p_original_transaction_id text, p_product_id text, p_tx jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare pr private.store_gold_products; w public.gold_wallets; owner uuid; total int := 0; v_season int := private.current_season();
        v_perk text; tiers int := 0; got int; token text;
begin
  perform private.check_transaction(p_original_transaction_id, p_product_id, p_tx);
  if p_user is null or not exists (select 1 from public.profiles where id = p_user and deleted_at is null) then raise exception 'not_found' using errcode = 'P0001'; end if;
  token := nullif(lower(coalesce(p_tx ->> 'appAccountToken', '')), '');
  if token is not null and token <> p_user::text then raise exception 'wrong_account' using errcode = 'P0001'; end if;
  if nullif(p_tx ->> 'revocationDate', '') is not null then
    return private.revoke_transaction(p_original_transaction_id) || jsonb_build_object('granted', false, 'state', private.store_state_for(p_user));
  end if;
  select * into pr from private.store_gold_products where product_id = p_product_id;
  if not found then raise exception 'unknown_product' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtext('store:' || p_user::text));

  if pr.kind = 'plan' then
    insert into public.store_plans (original_transaction_id, user_id, product_id, expires_at)
      values (p_original_transaction_id, p_user, p_product_id, to_timestamp(nullif(p_tx ->> 'expiresDate', '')::numeric / 1000))
      on conflict (original_transaction_id, user_id) do update
        set expires_at = greatest(public.store_plans.expires_at, excluded.expires_at), product_id = excluded.product_id, updated_at = now();
    if (select count(*) from public.store_plans where original_transaction_id = p_original_transaction_id) > 3 then
      raise exception 'too_many_accounts' using errcode = 'P0001';
    end if;
    return jsonb_build_object('granted', true, 'kind', 'plan', 'gold', 0, 'state', private.store_state_for(p_user));
  end if;

  select user_id into owner from public.store_transactions where original_transaction_id = p_original_transaction_id;
  if owner is not null then
    return jsonb_build_object('granted', false, 'reason', case when owner = p_user then 'already' else 'other_account' end, 'gold', 0,
                              'state', private.store_state_for(p_user));
  end if;
  w := private.wallet(p_user);
  if pr.kind = 'gold' then
    total := pr.gold + case when w.first_purchase_done then 0 else pr.gold / 2 end;
    update public.gold_wallets set first_purchase_done = true where user_id = p_user;
  elsif pr.kind = 'pass' then
    total := pr.gold;
    if pr.box_kind is not null and pr.box_count > 0 then perform private.add_boxes(p_user, pr.box_kind, pr.box_count); end if;
    tiers := case when p_product_id = 'com.ledger.season.levels' then private.store_setting('levelsTiers') else 0 end;
    insert into public.pass_owners (user_id, season, source, bonus_tiers) values (p_user, v_season, p_product_id, tiers)
      on conflict (user_id, season) do update set bonus_tiers = greatest(public.pass_owners.bonus_tiers, excluded.bonus_tiers);
  elsif pr.kind = 'perk' then
    v_perk := case when p_product_id = 'com.ledger.founder' then 'founder' else 'pro' end;
    if not exists (select 1 from public.store_perks k where k.user_id = p_user and k.perk = v_perk) then
      total := pr.gold;
      insert into public.store_perks (user_id, perk, original_transaction_id, gold) values (p_user, v_perk, p_original_transaction_id, total);
    end if;
    if v_perk = 'founder' and v_season = 1 then
      insert into public.pass_owners (user_id, season, source, bonus_tiers) values (p_user, 1, 'founder', private.store_setting('founderPassTiers'))
        on conflict do nothing;
      get diagnostics got = row_count;
      if got > 0 then tiers := private.store_setting('founderPassTiers'); end if;
    end if;
  end if;
  insert into public.store_transactions (original_transaction_id, user_id, product_id, transaction_id, environment, gold, box_kind, box_count, season)
    values (p_original_transaction_id, p_user, p_product_id, left(coalesce(p_tx ->> 'transactionId', p_original_transaction_id), 64),
            left(coalesce(p_tx ->> 'environment', ''), 20), total, pr.box_kind, pr.box_count, v_season);
  perform private.store_credit(p_user, total, 'purchase', p_original_transaction_id);
  return jsonb_build_object('granted', true, 'kind', pr.kind, 'gold', total, 'boxKind', pr.box_kind, 'boxes', pr.box_count,
                            'passTiers', tiers, 'season', v_season, 'state', private.store_state_for(p_user));
end $$;

-- Called only by the store edge functions for a verified refund or revocation from Apple.
create or replace function public.revoke_purchase(p_original_transaction_id text, p_product_id text, p_tx jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform private.check_transaction(p_original_transaction_id, p_product_id, p_tx);
  return private.revoke_transaction(p_original_transaction_id);
end $$;

revoke execute on function public.server_now(), public.my_day(), public.store_state(), public.open_boxes(text, int, text), public.store_buy(text, text, text),
  public.claim_free_money(text), public.confirm_money_claims(text[]), public.claim_pass_tier(int, text, int), public.claim_level_gold(int),
  public.claim_login_day(), public.claim_race_gold(int), public.claim_refund_retired(), public.quick_sell(jsonb, text),
  public.import_local_store(text, jsonb), public.grant_purchase(uuid, text, text, jsonb), public.revoke_purchase(text, text, jsonb) from public, anon;
grant execute on function public.server_now(), public.my_day(), public.store_state(), public.open_boxes(text, int, text), public.store_buy(text, text, text),
  public.claim_free_money(text), public.confirm_money_claims(text[]), public.claim_pass_tier(int, text, int), public.claim_level_gold(int),
  public.claim_login_day(), public.claim_race_gold(int), public.claim_refund_retired(), public.quick_sell(jsonb, text),
  public.import_local_store(text, jsonb) to authenticated;
revoke execute on function public.grant_purchase(uuid, text, text, jsonb), public.revoke_purchase(text, text, jsonb) from authenticated;
grant execute on function public.grant_purchase(uuid, text, text, jsonb), public.revoke_purchase(text, text, jsonb) to service_role;
