-- Purchase limits on store offers (0039): counters per account and period, enforced by the server.
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

create function pg_temp.expect_error(q text, code text) returns void language plpgsql as $$
begin
  execute q;
  raise exception 'expected % but the call worked: %', code, q;
exception when others then
  if sqlerrm not like code || '%' then raise; end if;
end $$;

create function pg_temp.lim(s jsonb, k text, i text) returns jsonb language sql as $$
  select e from jsonb_array_elements(s -> 'limits') e where e ->> 'kind' = k and e ->> 'id' = i
$$;

create temp table cast_ids (k text primary key, id uuid);
insert into cast_ids select 'admin', pg_temp.mk_player('Ada Ames');
insert into cast_ids select 'p', pg_temp.mk_player('Pia Player');
insert into cast_ids select 'q', pg_temp.mk_player('Quin Quick');
create function pg_temp.id(k text) returns uuid language sql as $$ select id from cast_ids where k = $1 $$;
insert into public.admins (user_id) values (pg_temp.id('admin'));

-- Every limit names a real bundle or paid money pack, and exactly one bundle is the featured offer.
do $$
begin
  if exists (select 1 from private.store_offer_limits l where l.kind = 'bundle' and not exists (select 1 from private.store_box_bundles b where b.id = l.id))
     or exists (select 1 from private.store_offer_limits l where l.kind = 'money'
                 and not exists (select 1 from private.store_money_packs m where m.id = l.id and not m.free)) then
    raise exception 'a limit names an offer that is not on sale';
  end if;
  if (select count(*) from private.store_offer_limits where featured and kind = 'bundle') <> 1 then raise exception 'not exactly one featured bundle'; end if;
  if private.offer_resets_at('day') <= extract(epoch from now()) or private.offer_resets_at('day') > extract(epoch from now()) + 86400 then
    raise exception 'the day does not reset within a day';
  end if;
  if private.offer_resets_at('week') <= extract(epoch from now()) or private.offer_resets_at('week') > extract(epoch from now()) + 7 * 86400 then
    raise exception 'the week does not reset within a week';
  end if;
  if private.offer_period_key('week', 700) <> 100 or private.offer_period_key('day', 700) <> 700 then raise exception 'period keys wrong'; end if;
end $$;

-- A player buys a limited bundle up to its cap; the next buy is refused and charges nothing; a repeated request
-- replays without counting; the state shows what is left; other players keep their own counters.
do $$
declare p uuid := pg_temp.id('p'); q uuid := pg_temp.id('q'); r jsonb; s jsonb; cap int; i int; before int; feat text;
begin
  perform private.store_credit(p, 5000, 'test', '');
  perform private.store_credit(q, 5000, 'test', '');
  perform pg_temp.as_user(p);
  s := public.store_state();
  if jsonb_array_length(s -> 'limits') <> (select count(*) from private.store_offer_limits) then raise exception 'limits missing from state: %', s -> 'limits'; end if;
  cap := (pg_temp.lim(s, 'bundle', 'cabinetx5') ->> 'cap')::int;
  if (pg_temp.lim(s, 'bundle', 'cabinetx5') ->> 'left')::int <> cap then raise exception 'a fresh account has used a limit'; end if;
  if (pg_temp.lim(s, 'bundle', 'cabinetx5') ->> 'resetsAt') is null then raise exception 'no reset time'; end if;
  for i in 1..cap loop
    r := public.store_buy('bundle', 'cabinetx5', 'lim-p-bundle-' || i);
    if (pg_temp.lim(r -> 'state', 'bundle', 'cabinetx5') ->> 'left')::int <> cap - i then
      raise exception 'left after % buys is %', i, pg_temp.lim(r -> 'state', 'bundle', 'cabinetx5');
    end if;
  end loop;
  r := public.store_buy('bundle', 'cabinetx5', 'lim-p-bundle-1');
  if (select count from public.store_offer_buys where user_id = p and id = 'cabinetx5') <> cap then raise exception 'a replayed request counted'; end if;
  before := pg_temp.gold(p);
  perform pg_temp.expect_error($q$select public.store_buy('bundle', 'cabinetx5', 'lim-p-bundle-over')$q$, 'offer_limit:week');
  if pg_temp.gold(p) <> before then raise exception 'a refused buy took gold'; end if;
  if (public.store_state() -> 'boxes' ->> 'cabinet')::int <> cap * 5 then raise exception 'boxes wrong: %', public.store_state() -> 'boxes'; end if;

  -- The featured bundle sells once a week.
  feat := (select id from private.store_offer_limits where featured);
  r := public.store_buy('bundle', feat, 'lim-p-feat-1');
  perform pg_temp.expect_error(format('select public.store_buy(%L, %L, %L)', 'bundle', feat, 'lim-p-feat-2'), 'offer_limit');

  -- Money packs count per server day.
  r := public.store_buy('money', 'safe', 'lim-p-money-1');
  r := public.store_buy('money', 'safe', 'lim-p-money-2');
  perform pg_temp.expect_error($q$select public.store_buy('money', 'safe', 'lim-p-money-3')$q$, 'offer_limit:day');
  if (pg_temp.lim(public.store_state(), 'money', 'safe') ->> 'left')::int <> 0 then raise exception 'money pack left wrong'; end if;
  -- Yesterday's buys do not count today.
  update public.store_offer_buys set period_key = period_key - 1 where user_id = p and kind = 'money';
  r := public.store_buy('money', 'case', 'lim-p-money-4');
  if (pg_temp.lim(r -> 'state', 'money', 'safe') ->> 'left')::int <> 2 then raise exception 'a new day did not reset the money limit'; end if;

  perform pg_temp.as_user(q);
  r := public.store_buy('bundle', 'cabinetx5', 'lim-q-bundle-1');
  if (pg_temp.lim(r -> 'state', 'bundle', 'cabinetx5') ->> 'left')::int <> cap - 1 then raise exception 'counters are shared between players'; end if;
  -- Unlimited goods are not affected.
  r := public.store_buy('service', 'usernameChange', 'lim-q-service-1');
  if r ? 'limits' then raise exception 'odd answer: %', r; end if;
  reset role;
end $$;

-- Administrators are not limited.
do $$
declare a uuid := pg_temp.id('admin'); r jsonb; i int;
begin
  perform pg_temp.as_user(a);
  for i in 1..3 loop r := public.store_buy('bundle', (select id from private.store_offer_limits where featured), 'lim-adm-' || i); end loop;
  if (pg_temp.lim(public.store_state(), 'bundle', (select id from private.store_offer_limits where featured)) ->> 'left')::int < 1 then
    raise exception 'an administrator was limited';
  end if;
  reset role;
end $$;

-- Players cannot read or change the counters directly, nor call the inner buy.
do $$
begin
  if has_table_privilege('authenticated', 'public.store_offer_buys', 'select') or has_table_privilege('authenticated', 'public.store_offer_buys', 'update') then
    raise exception 'players can touch the counters';
  end if;
  if has_function_privilege('authenticated', 'private.store_buy_unlimited(text, text, text)', 'execute') then raise exception 'the inner buy is open'; end if;
  if not has_function_privilege('authenticated', 'public.store_buy(text, text, text)', 'execute') then raise exception 'store_buy is closed'; end if;
end $$;
