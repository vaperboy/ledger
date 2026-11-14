-- Purchase limits on store offers: each box bundle and money pack sells a set number of times per server day or week,
-- counted per account. The featured bundle is the Offers card. Administrators are not limited.

create table private.store_offer_limits (
  kind text not null check (kind in ('bundle', 'money')),
  id text not null,
  cap int not null check (cap between 1 and 1000),
  period text not null check (period in ('day', 'week')),
  featured boolean not null default false,
  primary key (kind, id)
);
create unique index store_offer_limits_one_featured on private.store_offer_limits (featured) where featured;

-- Purchases of a limited offer in one period (a server day, or a server week of seven days).
create table public.store_offer_buys (
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  id text not null,
  period_key int not null,
  count int not null default 0 check (count >= 0),
  primary key (user_id, kind, id, period_key)
);
alter table public.store_offer_buys enable row level security;
revoke all on public.store_offer_buys from anon, authenticated;
revoke all on private.store_offer_limits from public, anon, authenticated;

insert into private.store_offer_limits (kind, id, cap, period, featured) values
  ('bundle', 'cabinetx10', 1, 'week', true),
  ('bundle', 'cabinetx5', 3, 'week', false),
  ('bundle', 'grandx3', 3, 'week', false),
  ('bundle', 'elitex3', 3, 'week', false),
  ('money', 'handful', 5, 'day', false),
  ('money', 'bundle', 3, 'day', false),
  ('money', 'case', 3, 'day', false),
  ('money', 'safe', 2, 'day', false),
  ('money', 'mountain', 2, 'day', false);

-- The current period of a limit: the server day, or the server week (day / 7).
create or replace function private.offer_period_key(p_period text, p_day int default private.era_day()) returns int
language sql immutable set search_path = '' as $$
  select case p_period when 'week' then p_day / 7 else p_day end;
$$;

-- When the current period ends, in seconds since 1970 (midnight UTC).
create or replace function private.offer_resets_at(p_period text, p_day int default private.era_day()) returns double precision
language sql immutable set search_path = '' as $$
  select extract(epoch from ((date '0001-01-01' + (case p_period when 'week' then (p_day / 7 + 1) * 7 else p_day + 1 end) - 1)::timestamp
                             at time zone 'utc'))::double precision;
$$;

-- How many of a limited offer the account has bought in the current period.
create or replace function private.offer_bought(uid uuid, p_kind text, p_id text, p_period text) returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((select b.count from public.store_offer_buys b
                    where b.user_id = uid and b.kind = p_kind and b.id = p_id and b.period_key = private.offer_period_key(p_period)), 0);
$$;

-- The limited offers as the app shows them: cap, how many are left, the period and when it resets.
create or replace function private.store_limits_for(uid uuid) returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', l.kind, 'id', l.id, 'cap', l.cap, 'period', l.period, 'featured', l.featured,
           'left', case when private.is_admin(uid) then l.cap else greatest(0, l.cap - private.offer_bought(uid, l.kind, l.id, l.period)) end,
           'resetsAt', private.offer_resets_at(l.period)) order by l.kind, l.id), '[]'::jsonb)
    from private.store_offer_limits l;
$$;

-- The state from 0038 plus the limited offers.
alter function private.store_state_for(uuid) rename to store_state_unlimited;
create or replace function private.store_state_for(uid uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return private.store_state_unlimited(uid) || jsonb_build_object('limits', private.store_limits_for(uid));
end $$;

-- Buying from 0038 moves behind a check of the offer's limit; the purchase and its count land in one transaction.
alter function public.store_buy(text, text, text) rename to store_buy_unlimited;
alter function public.store_buy_unlimited(text, text, text) set schema private;

create or replace function public.store_buy(p_kind text, p_id text, p_request text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); lim private.store_offer_limits; out jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  -- A repeated request replays its first answer and counts nothing.
  if exists (select 1 from public.store_requests r where r.user_id = uid and r.request_id = p_request) then
    return private.store_buy_unlimited(p_kind, p_id, p_request);
  end if;
  select * into lim from private.store_offer_limits l where l.kind = p_kind and l.id = p_id;
  if found and not private.is_admin(uid) and private.offer_bought(uid, p_kind, p_id, lim.period) >= lim.cap then
    raise exception 'offer_limit:%', lim.period using errcode = 'P0001';
  end if;
  out := private.store_buy_unlimited(p_kind, p_id, p_request);
  if lim.kind is not null then
    insert into public.store_offer_buys (user_id, kind, id, period_key, count)
      values (uid, p_kind, p_id, private.offer_period_key(lim.period), 1)
      on conflict (user_id, kind, id, period_key) do update set count = public.store_offer_buys.count + 1;
    out := out || jsonb_build_object('state', private.store_state_for(uid));
  end if;
  return out;
end $$;

revoke execute on function private.store_buy_unlimited(text, text, text), private.store_state_unlimited(uuid), private.store_limits_for(uuid),
  private.offer_bought(uuid, text, text, text), private.offer_period_key(text, int), private.offer_resets_at(text, int)
  from public, anon, authenticated;
revoke execute on function public.store_buy(text, text, text) from public, anon;
grant execute on function public.store_buy(text, text, text) to authenticated;
