-- Store price ladder, Elite box, event boxes on a two-week rotation, live administrator prices and mission loot (0038).
create function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
$$;

create function pg_temp.mk_player(nm text) returns uuid language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role) values (u, 'authenticated', 'authenticated');
  insert into public.profiles (id, display_name, adult_confirmed, created_at) values (u, nm, true, now() - interval '40 days');
  return u;
end $$;

create function pg_temp.gold(u uuid) returns int language sql as $$ select coalesce((select balance from public.gold_wallets where user_id = u), 0) $$;
create function pg_temp.fund(u uuid, n int) returns void language sql as $$
  insert into public.gold_wallets (user_id, balance) values (u, n) on conflict (user_id) do update set balance = excluded.balance;
$$;

create temp table cast_ids (k text primary key, id uuid);
insert into cast_ids select 'admin', pg_temp.mk_player('Ada Ames');
insert into cast_ids select 'p', pg_temp.mk_player('Pia Player');
insert into cast_ids select 'q', pg_temp.mk_player('Quin Quick');
create function pg_temp.id(k text) returns uuid language sql as $$ select id from cast_ids where k = $1 $$;
insert into public.admins (user_id) values (pg_temp.id('admin'));

-- The ladder: a guaranteed item costs clearly more than the box that may drop it; Elite is the dearest box and bundle.
do $$
declare premium int := private.box_price('grand'); epic int := private.rarity_price('epic'); legendary int := private.rarity_price('legendary');
        elite int := private.box_price('elite'); elite_bundle record;
begin
  if elite is null or elite <= (select max(private.box_price(kind)) from private.store_box_kinds where kind <> 'elite') then
    raise exception 'elite is not the dearest box: %', elite;
  end if;
  if epic <= 3 * premium then raise exception 'a guaranteed epic (%) must cost more than three premium boxes (%)', epic, premium; end if;
  if legendary <= epic then raise exception 'legendary (%) must cost more than epic (%)', legendary, epic; end if;
  if private.rarity_price('rare') <= private.box_price('cabinet') then raise exception 'a guaranteed rare must cost more than a basic box'; end if;
  select * into elite_bundle from private.store_box_bundles where kind = 'elite';
  if not found then raise exception 'no elite bundle'; end if;
  if private.bundle_price(elite_bundle.id) >= elite_bundle.count * elite then raise exception 'the elite bundle saves nothing'; end if;
  if private.bundle_price(elite_bundle.id) <= (select max(private.bundle_price(id)) from private.store_box_bundles where kind <> 'elite') then
    raise exception 'the elite bundle is not the dearest bundle';
  end if;
  -- Every shelf price follows the ladder, and the shelf never sells a legendary.
  if exists (select 1 from private.store_shelf(private.era_day()) s join private.store_cosmetics c on c.id = s.id
              where s.price <> private.rarity_price(c.rarity) or c.rarity = 'legendary') then
    raise exception 'shelf price off the ladder';
  end if;
  if exists (select 1 from private.store_box_rows r where private.rarity_rank(r.rarity) >= 2 and r.prize in ('gold', 'money')) then
    raise exception 'cash or gold sits in an epic or legendary row';
  end if;
  if exists (select 1 from private.store_box_kinds k where not k.card_pack
              and (select prize from private.store_box_rows r where r.kind = k.kind order by pos desc limit 1) <> 'cosmetic') then
    raise exception 'the rarest row of a box is not a cosmetic';
  end if;
  if (select sum(weight) filter (where rarity = 'legendary') from private.store_box_rows where kind = 'elite')
     <= (select max(s) from (select sum(weight) filter (where rarity = 'legendary') s from private.store_box_rows
                                 where kind <> 'elite' and kind in (select kind from private.store_box_kinds where not card_pack) group by kind) x) then
    raise exception 'elite does not have the best legendary odds of the boxes';
  end if;
end $$;

-- Event loot: epic and legendary event items belong to exactly one event box and appear nowhere else.
do $$
declare d int; p uuid := pg_temp.id('p'); r jsonb; got text; i int; ev text;
begin
  if (select count(*) from private.store_event_sets) < 12 then raise exception 'fewer than 12 event sets'; end if;
  if exists (select 1 from private.store_event_sets s where (select count(*) from private.store_event_boxes b where b.set_id = s.id) <> 6) then
    raise exception 'a set without six boxes';
  end if;
  if exists (select 1 from private.store_event_boxes b
              where (select count(*) from private.store_event_items i where i.box_id = b.id and i.rarity = 'epic') < 2
                 or (select count(*) from private.store_event_items i where i.box_id = b.id and i.rarity = 'legendary') < 1) then
    raise exception 'an event box lacks its exclusive epics and legendary';
  end if;
  if exists (select 1 from private.store_event_items i join private.store_cosmetics c on c.id = i.item_id where c.source <> 'event')
     or exists (select 1 from private.store_event_items i where not exists (select 1 from private.store_cosmetics c where c.id = i.item_id)) then
    raise exception 'an event item is not an event-only cosmetic';
  end if;
  if exists (select 1 from private.store_event_items i join private.store_pass_rewards r on r.reward_id = i.item_id) then
    raise exception 'an event item is a pass reward';
  end if;
  for d in private.era_day() .. private.era_day() + 400 loop
    if exists (select 1 from private.store_shelf(d) s join private.store_event_items i on i.item_id = s.id) then raise exception 'event item on the shelf on day %', d; end if;
  end loop;
  begin
    perform private.gift_check(array[(select item_id from private.store_event_items limit 1)], '{}'::jsonb);
    raise exception 'an event item fits in a gift code';
  exception when others then
    if sqlerrm not like 'invalid_gift_item%' then raise; end if;
  end;

  -- Regular boxes never roll an event item; an event box's epic and legendary cosmetics are its own.
  perform pg_temp.fund(p, 0);
  for i in 1..300 loop
    perform private.roll_box(p, case i % 3 when 0 then 'grand' when 1 then 'elite' else 'cabinet' end, true, 0, 'regular-roll-' || i);
  end loop;
  if exists (select 1 from public.cosmetic_grants g join private.store_event_items e on e.item_id = g.cosmetic_id where g.user_id = p) then
    raise exception 'a regular box rolled an event item';
  end if;
  ev := private.event_box(2);
  for i in 1..200 loop
    r := private.roll_box(p, 'event2', true, 0, 'event-roll-' || i);
    got := r -> 'content' ->> 'id';
    if private.rarity_rank(r ->> 'rarity') >= 2 and r -> 'content' ->> 'type' = 'cosmetic'
       and not exists (select 1 from private.store_event_items e where e.item_id = got and e.box_id = ev) then
      raise exception 'event box % gave % at %', ev, got, r ->> 'rarity';
    end if;
  end loop;
  if not exists (select 1 from public.cosmetic_grants g join private.store_event_items e on e.item_id = g.cosmetic_id where g.user_id = p and e.box_id = ev) then
    raise exception 'two hundred event boxes gave none of their exclusives';
  end if;
  if exists (select 1 from public.cosmetic_grants g join private.store_event_items e on e.item_id = g.cosmetic_id where g.user_id = p and e.box_id <> ev) then
    raise exception 'an event box gave another box''s exclusive';
  end if;
end $$;

-- Rotation: the same six boxes for 14 days, a new set every 14 days, 12 rotations before a set comes back.
do $$
declare e int := private.store_setting('eventEpochDay'); n int := private.store_setting('eventRotationDays'); k int; sets text[] := '{}'; st jsonb;
begin
  if n <> 14 then raise exception 'rotation is % days', n; end if;
  for k in 0..11 loop
    if private.event_set(e + k * n) <> private.event_set(e + k * n + n - 1) then raise exception 'set changed inside rotation %', k; end if;
    if private.event_set(e + k * n) = private.event_set(e + (k + 1) * n) then raise exception 'set did not change after rotation %', k; end if;
    if private.event_box(1, e + k * n) = private.event_box(1, e + (k + 1) * n) then raise exception 'slot 1 kept its box'; end if;
    sets := sets || private.event_set(e + k * n);
  end loop;
  if (select count(distinct x) from unnest(sets) x) <> 12 then raise exception 'twelve rotations repeat a set: %', sets; end if;
  if private.event_set(e - 1) is null or private.event_box(6, e - 20) is null then raise exception 'no set before the epoch'; end if;
  perform pg_temp.as_user(pg_temp.id('q'));
  st := public.store_state();
  if jsonb_array_length(st -> 'events' -> 'boxes') <> 6 or (st -> 'events' ->> 'set') <> private.event_set() then raise exception 'state lacks the event boxes'; end if;
  if (st -> 'prices' -> 'boxes' ->> 'elite')::int <> private.box_price('elite') then raise exception 'state lacks the prices'; end if;
  reset role;
end $$;

-- Prices an administrator sets apply to everyone at once; anyone else is refused.
do $$
declare a uuid := pg_temp.id('admin'); q uuid := pg_temp.id('q'); r jsonb; before int; st jsonb; b text := (select id from private.store_box_bundles order by price limit 1);
begin
  perform pg_temp.as_user(q);
  begin
    perform public.admin_set_price('box', 'grand', 1);
    raise exception 'a player changed a price';
  exception when others then
    if sqlerrm <> 'not_admin' then raise; end if;
  end;
  if private.box_price('grand') <> 75 then raise exception 'the refused change took effect'; end if;

  perform pg_temp.as_user(a);
  r := public.admin_set_price('box', 'grand', 90);
  if (r -> 'state' -> 'prices' -> 'boxes' ->> 'grand')::int <> 90 then raise exception 'admin answer lacks the new price'; end if;
  r := public.admin_set_price('bundle', b, 77);
  r := public.admin_set_price('rarity', 'epic', 300);
  begin
    perform public.admin_set_price('box', 'free', 5);
    raise exception 'the season box got a price';
  exception when others then
    if sqlerrm <> 'unknown_item' then raise; end if;
  end;
  begin
    perform public.admin_set_price('item', (select reward_id from private.store_pass_rewards where kind = 'outfit' limit 1), 5);
    raise exception 'a pass item got a price';
  exception when others then
    if sqlerrm <> 'unknown_item' then raise; end if;
  end;
  if not exists (select 1 from public.admin_audit where actor_id = a and action = 'store_price') then raise exception 'price change not audited'; end if;

  perform pg_temp.as_user(q);
  st := public.store_state();
  if (st -> 'prices' -> 'boxes' ->> 'grand')::int <> 90 or (st -> 'prices' -> 'bundles' ->> b)::int <> 77 or (st -> 'prices' -> 'rarity' ->> 'epic')::int <> 300 then
    raise exception 'another player does not see the new prices: %', st -> 'prices';
  end if;
  perform pg_temp.fund(q, 1000);
  before := pg_temp.gold(q);
  r := public.open_boxes('grand', 1, 'price-open-1');
  if before - pg_temp.gold(q) <> 90 + coalesce((select sum(delta) from public.gold_ledger where user_id = q and kind = 'box_gold'), 0) then
    raise exception 'a box was not charged the new price: %', before - pg_temp.gold(q);
  end if;
  before := pg_temp.gold(q);
  r := public.store_buy('bundle', b, 'price-bundle-1');
  if before - pg_temp.gold(q) <> 77 then raise exception 'a bundle was not charged the new price'; end if;

  perform pg_temp.as_user(a);
  r := public.admin_set_price('box', 'grand', null);
  if private.box_price('grand') <> 75 then raise exception 'clearing the price did not restore the catalogue'; end if;
  reset role;
end $$;

-- Starter clothes: a few stay free, the rest are mission loot that old accounts keep and missions now and then give.
do $$
declare p uuid := pg_temp.id('p'); q uuid := pg_temp.id('q'); i int; r jsonb; n int;
begin
  if (select count(*) from private.store_cosmetics where source = 'mission') < 8 then raise exception 'too few mission items'; end if;
  if (select count(*) from private.store_cosmetics where source = 'free' and kind in ('outfit', 'face', 'hair')) > 10 then raise exception 'too many free clothes'; end if;
  delete from public.cosmetic_grants where user_id = p and source = 'legacy_free';
  perform private.grant_legacy_free();
  if (select count(*) from public.cosmetic_grants where user_id = p and source = 'legacy_free') <> (select count(*) from private.store_cosmetics where source = 'mission') then
    raise exception 'existing accounts did not keep their clothes';
  end if;
  delete from public.cosmetic_grants where user_id = q and source = 'legacy_free';
  perform pg_temp.as_user(q);
  for i in 1..40 loop r := public.claim_mission_gold('m' || i, 'daily:1', 1); end loop;
  n := (select count(*) from public.mission_drops where user_id = q);
  if n <> 1 then raise exception 'mission loot on one day: % items', n; end if;
  if not exists (select 1 from public.cosmetic_grants g join private.store_cosmetics c on c.id = g.cosmetic_id
                  where g.user_id = q and g.source = 'mission' and c.source = 'mission' and c.rarity = 'common') then
    raise exception 'mission loot is not a common clothing item';
  end if;
  reset role;
end $$;
