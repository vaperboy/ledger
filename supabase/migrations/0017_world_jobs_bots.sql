create table if not exists public.job_runs (
  name text primary key,
  every interval not null,
  last_run timestamptz
);
alter table public.job_runs enable row level security;
revoke all on public.job_runs from anon, authenticated;
insert into public.job_runs (name, every) values
  ('auctions', interval '1 minute'), ('bots', interval '1 hour'), ('orders', interval '1 hour'), ('supply', interval '1 day'),
  ('startups', interval '1 day'), ('ventures', interval '1 day'), ('news', interval '1 day'), ('elections', interval '1 day')
  on conflict (name) do nothing;

create table if not exists public.bots (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  slot int not null unique check (slot >= 0),
  active boolean not null default true
);
alter table public.bots enable row level security;
revoke all on public.bots from anon, authenticated;

create or replace function private.bot_awake(uid uuid) returns boolean language sql stable as $$
  select abs(hashtext(uid::text || ((extract(epoch from now()) / 600)::bigint)::text)) % 100 < 28;
$$;

create or replace function private.bot_target() returns int language sql stable security definer set search_path = '' as $$
  select least(40, greatest(8, 36 - (select count(*) / 2 from public.profiles
                                      where not is_bot and adult_confirmed and deleted_at is null and last_seen_at > now() - interval '14 days')::int));
$$;

create or replace function private.bot_pick(pool text[], salt int) returns text language sql immutable as $$
  select pool[1 + abs(hashtext(salt::text || 'p' || cardinality(pool)::text)) % cardinality(pool)];
$$;

create or replace function private.bot_create(slot int) returns void language plpgsql security definer set search_path = '' as $$
declare
  nordic_f text[] := array['Ingrid','Magnus','Sofie','Henrik','Kari','Mikkel','Freja','Eino','Aino','Astrid','Erik','Silje','Isak','Maja','Jakob','Nora'];
  nordic_l text[] := array['Solheim','Berg','Lund','Dahl','Nordby','Holm','Jensen','Virtanen','Korhonen','Haugen','Eriksen','Strand','Bakke','Moen','Hagen','Lindqvist'];
  brit_f text[] := array['Oliver','Priya','Callum','Eleanor','Harriet','Marcus','Tyler','Chloe','Aoife','Noah','Thandi','Daniel','Grace','Owen','Imogen','Rhys'];
  brit_l text[] := array['Whitfield','Shah','Reid','Hughes','Cole','Carter','Bell','Nguyen','Tremblay','Brennan','Dlamini','Mitchell','Fraser','Hale','Pearce','Doyle'];
  fr_f text[] := array['Camille','Julien','Manon','Hugo','Louise','Theo','Lea','Mathis','Chloe','Lucas','Jade','Nathan','Ines','Remi','Alix','Sacha'];
  fr_l text[] := array['Laurent','Moreau','Girard','Bernard','Petit','Roux','Fournier','Lambert','Mercier','Blanc','Garnier','Chevalier','Faure','Lemaire','Perrin','Colin'];
  de_f text[] := array['Lukas','Anna','Jonas','Sanne','Daan','Emma','Felix','Lena','Paul','Sophie','Max','Hanna','Jens','Lotte','Bas','Femke'];
  de_l text[] := array['Schneider','Fischer','Weber','de Vries','Bakker','Wagner','Becker','Hoffmann','Visser','Smit','Meijer','Koch','Richter','Bos','Klein','Wolf'];
  med_f text[] := array['Lucia','Marco','Matteo','Elena','Pablo','Carmen','Beatriz','Diego','Sofia','Luca','Marta','Andres','Giulia','Rafael','Paula','Enzo'];
  med_l text[] := array['Ferrari','Conti','Navarro','Ortega','Santos','Almeida','Rossi','Moretti','Castro','Vega','Serra','Costa','Ricci','Prieto','Lopes','Bianchi'];
  jp_f text[] := array['Haruto','Yuki','Aiko','Kenji','Hana','Ayaka','Ren','Sakura','Daichi','Mio','Takumi','Nanami','Sota','Riko','Yuto','Emi'];
  jp_l text[] := array['Sato','Tanaka','Suzuki','Watanabe','Kobayashi','Yamada','Ito','Nakamura','Kato','Yoshida','Matsuda','Hayashi','Mori','Saito','Ogawa','Fujita'];
  in_f text[] := array['Arjun','Mehul','Ravi','Sana','Anika','Rohan','Priya','Vikram','Neha','Kabir','Ishaan','Divya','Aditya','Meera','Rahul','Tara'];
  in_l text[] := array['Mehta','Kapoor','Iyer','Nair','Rao','Menon','Sharma','Gupta','Reddy','Joshi','Bose','Patel','Chopra','Desai','Banerjee','Malhotra'];
  pl_f text[] := array['Kasia','Tomasz','Piotr','Agnieszka','Marek','Ola','Jakub','Zofia','Pawel','Magda','Lukasz','Ewa','Michal','Natalia','Bartek','Julia'];
  pl_l text[] := array['Nowak','Wisniewski','Kowalczyk','Zielinski','Kaminski','Lewandowski','Wojcik','Szymanski','Dabrowski','Kozlowski','Jankowski','Mazur','Krawczyk','Piotrowski','Grabowski','Pawlak'];
  trades text[] := array['Bakery','Brewery','Farm','Vineyard','Grocery','Hardware store','Furniture maker','Cleaning firm','Web studio','Game studio','Garage','Electrician','Plumber','Courier','Salmon farm','Factory'];
  cities text[] := array['Oslo','Leeds','Lyon','Malmo','Aarhus','Turku','Hamburg','Utrecht','Austin','Toronto','Valencia','Turin','Gdansk','Cork','Osaka','Recife','Pune','Perth','Durban','Bergen','Bristol','Lille','Uppsala'];
  suffixes text[] := array['& Sons','Trading','Works','Provisions','Partners','Group','Direct','Supply'];
  region int := slot % 8; fnames text[]; lnames text[]; fname text; lname text; nm text; cc text; uid uuid := gen_random_uuid(); k int := 0;
  nw numeric := round(15000 * power(1.19, slot)); trade text; surname text; days int := 20 + (slot * 37) % 160;
begin
  fnames := case region when 0 then nordic_f when 1 then brit_f when 2 then fr_f when 3 then de_f when 4 then med_f when 5 then jp_f when 6 then in_f else pl_f end;
  lnames := case region when 0 then nordic_l when 1 then brit_l when 2 then fr_l when 3 then de_l when 4 then med_l when 5 then jp_l when 6 then in_l else pl_l end;
  cc := case region when 0 then (array['NO','SE','DK','FI'])[1 + slot % 4] when 1 then (array['UK','IE','US','CA','AU','ZA'])[1 + slot % 6]
             when 2 then 'FR' when 3 then (array['DE','NL'])[1 + slot % 2] when 4 then (array['ES','IT','BR'])[1 + slot % 3] when 5 then 'JP' when 6 then 'IN' else 'PL' end;
  loop
    fname := fnames[1 + abs(hashtext('f' || slot || ':' || k)) % cardinality(fnames)];
    lname := lnames[1 + abs(hashtext('l' || slot || ':' || k)) % cardinality(lnames)];
    nm := fname || ' ' || lname;
    exit when not exists (select 1 from public.profiles where lower(display_name) = lower(nm)) and private.name_problem(nm) is null;
    k := k + 1;
    exit when k > 40;
  end loop;
  insert into auth.users (id, aud, role, banned_until, created_at, updated_at)
    values (uid, 'authenticated', 'authenticated', 'infinity', now(), now());
  insert into public.profiles (id, display_name, avatar_colour, country_code, level, privacy, game_week, trades_completed, created_at,
                               adult_confirmed, is_bot, last_seen_at)
    values (uid, nm, slot % 8, cc, 1 + days * 3 / 14, 'public', days * 3, days * 2 + slot, now() - make_interval(days => days), true, true, now());
  insert into public.bots (user_id, slot) values (uid, slot);
  trade := trades[1 + (slot * 5 + region) % cardinality(trades)];
  surname := lname;
  insert into public.companies_public (owner_id, company_key, name, trade, city, country, health)
    values (uid, 'bot-' || slot || '-a', surname || ' ' || suffixes[1 + slot % cardinality(suffixes)], trade, cities[1 + (slot * 3) % cardinality(cities)], cc,
            (array['steady','growing','thriving','steady','new'])[1 + slot % 5]::public.company_health);
  if slot % 3 = 0 then
    insert into public.companies_public (owner_id, company_key, name, trade, city, country, health)
      values (uid, 'bot-' || slot || '-b', fname || '''s ' || trades[1 + (slot * 7) % cardinality(trades)], trades[1 + (slot * 7) % cardinality(trades)],
              cities[1 + (slot * 5 + 2) % cardinality(cities)], cc, 'growing');
  end if;
  insert into public.leaderboard_entries (user_id, net_worth, trading_result, game_week)
    values (uid, nw, round(nw * 0.02), days * 3);
end $$;

create or replace function private.bot_ensure(target int) returns void language plpgsql security definer set search_path = '' as $$
declare s int;
begin
  for s in 0..target - 1 loop
    if not exists (select 1 from public.bots where slot = s) then perform private.bot_create(s); end if;
  end loop;
end $$;

create or replace function private.bot_events(b public.bots, p public.profiles, hour_key bigint) returns void language plpgsql security definer set search_path = '' as $$
declare c public.companies_public; kind int; n int; other text; club text; m bigint;
begin
  if abs(hashtext(p.id::text || ':' || hour_key)) % 1000 >= 45 then return; end if;
  select * into c from public.companies_public where owner_id = p.id order by company_key limit 1;
  kind := abs(hashtext(p.id::text || 'k' || hour_key)) % 6;
  if kind = 0 then
    n := 2 + (p.game_week / 40) % 10;
    perform private.post_event(p.id, 'branchMilestone', c.trade, c.city, c.name, n, null, null, 'bot:branch:' || n);
  elsif kind = 1 then
    perform private.post_event(p.id, 'wentViral', c.trade, c.city, c.name, null, null, null, 'bot:viral:' || (p.game_week / 120));
  elsif kind = 2 then
    m := (array[100, 500, 1000, 5000, 10000, 20000])[1 + least(5, p.game_week / 90)];
    perform private.post_event(p.id, 'supplierMilestone', c.trade, c.city, c.name, m::int, null, null, 'bot:supply:' || m);
  elsif kind = 3 then
    select cp.name into other from public.companies_public cp join public.bots ob on ob.user_id = cp.owner_id and ob.active
     where cp.owner_id <> p.id order by hashtext(cp.owner_id::text || hour_key::text) limit 1;
    if other is not null then perform private.post_event(p.id, 'acquisition', c.trade, c.city, c.name, null, other, null, 'bot:acq:' || other); end if;
  elsif kind = 4 then
    select name into club from public.association_clubs order by hashtext(id || p.id::text) limit 1;
    if club is not null then perform private.post_event(p.id, 'newAssociation', null, null, null, null, null, club, 'bot:club:' || club); end if;
  else
    n := 1 + p.game_week / 52;
    perform private.post_event(p.id, 'seasonMilestone', null, null, null, n, null, null, 'bot:season:' || n);
  end if;
end $$;

create or replace function private.bot_quote(l public.exchange_listings, hour_key bigint) returns void language plpgsql security definer set search_path = '' as $$
declare cb numeric[]; ref numeric; bot uuid; held bigint; px numeric; qty bigint; budget numeric; min_ask numeric; max_bid numeric; reserved bigint;
begin
  update public.exchange_orders o set status = 'cancelled'
   where o.listing_id = l.id and o.status = 'open' and exists (select 1 from public.profiles p where p.id = o.trader_id and p.is_bot);
  cb := private.exchange_close_bounds(l);
  ref := least(greatest(coalesce(private.exchange_last_price(l.id), private.exchange_nav(l)), cb[1]), cb[2]);
  select min(price) into min_ask from public.exchange_orders where listing_id = l.id and status = 'open' and side = 'sell';
  select max(price) into max_bid from public.exchange_orders where listing_id = l.id and status = 'open' and side = 'buy';
  select b.user_id into bot from public.bots b where b.active
   order by hashtext(b.user_id::text || l.id::text || hour_key::text) limit 1;
  if bot is null then return; end if;
  px := round(least(greatest(ref * 0.97, cb[1]), cb[2]), 4);
  budget := l.value * 0.01 - coalesce((select sum(t.shares * t.price) from public.exchange_trades t join public.profiles p on p.id = t.buyer_id and p.is_bot
                                        where t.listing_id = l.id and t.traded_at > now() - interval '24 hours'), 0);
  qty := least(floor(l.total_shares * 0.002)::bigint, floor(greatest(0, budget) / px)::bigint,
               floor(l.total_shares * 0.15)::bigint - coalesce((select shares from public.exchange_holdings where listing_id = l.id and owner_id = bot), 0),
               private.exchange_buyable(l, bot));
  if qty >= 1 and (min_ask is null or px < min_ask) then
    insert into public.exchange_orders (listing_id, trader_id, side, shares, remaining, price) values (l.id, bot, 'buy', qty, qty, px);
  end if;
  select h.owner_id, h.shares into bot, held from public.exchange_holdings h join public.profiles p on p.id = h.owner_id and p.is_bot
   where h.listing_id = l.id and h.shares > 0 order by h.shares desc limit 1;
  if bot is not null then
    px := round(least(greatest(ref * 1.03, cb[1]), cb[2]), 4);
    reserved := held;
    if reserved >= 1 and (max_bid is null or px > max_bid) then
      insert into public.exchange_orders (listing_id, trader_id, side, shares, remaining, price) values (l.id, bot, 'sell', reserved, reserved, px);
    end if;
  end if;
end $$;

create or replace function private.bot_tick() returns int language plpgsql security definer set search_path = '' as $$
declare target int := private.bot_target(); b public.bots; p public.profiles; hour_key bigint := floor(extract(epoch from now()) / 3600)::bigint;
        l public.exchange_listings; n int := 0; wk int; nw numeric; share numeric;
begin
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

create or replace function private.settle(uid uuid, amount numeric, currency text, kind text, ref text, label text, meta jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.settlements (recipient_id, amount, currency, kind, ref, label, meta)
  select uid, round(amount, 2), currency, kind, coalesce(ref, ''), coalesce(label, ''), coalesce(meta, '{}'::jsonb)
   where not exists (select 1 from public.profiles where id = uid and is_bot);
$$;

create or replace function private.expire_orders() returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.exchange_orders o set status = 'cancelled'
   where o.status = 'open' and not exists (select 1 from public.profiles p where p.id = o.trader_id and p.is_bot)
     and (o.created_at < now() - interval '7 days'
          or coalesce((select p.last_seen_at from public.profiles p where p.id = o.trader_id), o.created_at) < now() - interval '2 days');
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function private.run_news_cleanup() returns int language plpgsql security definer set search_path = '' as $$
declare n int; m int;
begin
  delete from public.player_events where created_at < now() - interval '30 days';
  get diagnostics n = row_count;
  delete from public.player_activity where created_at < now() - interval '30 days';
  get diagnostics m = row_count;
  delete from public.account_signals where last_seen < now() - interval '90 days';
  return n + m;
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
      end if;
      n := n + 1;
    exception when others then
      raise warning 'job % failed: %', j.name, sqlerrm;
    end;
  end loop;
  return n;
end $$;

create or replace function public.heartbeat() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); online int; total int;
begin
  update public.profiles set last_seen_at = now() where id = uid and (last_seen_at is null or last_seen_at < now() - interval '45 seconds');
  perform private.run_due_jobs();
  select count(*) filter (where (not is_bot and last_seen_at > now() - interval '10 minutes') or (is_bot and private.bot_awake(id))),
         count(*)
    into online, total
    from public.profiles p where p.deleted_at is null and p.adult_confirmed and (not p.is_bot or exists (select 1 from public.bots b where b.user_id = p.id and b.active));
  return jsonb_build_object('online', online, 'players', total, 'now', extract(epoch from now()));
end $$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
      perform cron.schedule('ledger-jobs', '* * * * *', 'select private.run_due_jobs()');
    exception when others then
      raise notice 'pg_cron could not be scheduled: %', sqlerrm;
    end;
  end if;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.heartbeat() to authenticated;
