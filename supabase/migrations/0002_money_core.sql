alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

alter table public.profiles add column link_key text not null default gen_random_uuid()::text;
create index profiles_link_key on public.profiles (link_key);
comment on column public.profiles.link_key is 'Accounts of one owner (or otherwise linked) share a key. Set by staff only: no client grant covers it.';

create function private.link_key(uid uuid) returns text language sql stable security definer set search_path = '' as $$
  select link_key from public.profiles where id = uid;
$$;
create function private.linked(a uuid, b uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles x join public.profiles y on y.link_key = x.link_key where x.id = a and y.id = b);
$$;

create function private.account_weeks(uid uuid) returns int language sql stable security definer set search_path = '' as $$
  select coalesce((select game_week from public.profiles where id = uid), 0);
$$;

create function private.display_name(uid uuid) returns text language sql stable security definer set search_path = '' as $$
  select display_name from public.profiles where id = uid;
$$;

create function private.is_barred(uid uuid, scope text) returns boolean language sql stable as $$ select false; $$;

create function private.conviction_count(uid uuid) returns int language sql stable as $$ select 0; $$;

create function private.require_free(uid uuid, scope text) returns void language plpgsql stable as $$
begin
  if private.is_barred(uid, scope) then raise exception 'barred' using errcode = 'P0001'; end if;
end $$;

create function private.require_player() returns uuid language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  if not exists (select 1 from public.profiles where id = uid and deleted_at is null) then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  return uid;
end $$;

create table public.settlements (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  amount numeric(18, 2) not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  kind text not null check (char_length(kind) between 1 and 40),
  ref text not null default '' check (char_length(ref) <= 80),
  label text not null default '' check (char_length(label) <= 200),
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  claimed_at timestamptz
);
create index settlements_unclaimed on public.settlements (recipient_id, created_at) where claimed_at is null;

alter table public.settlements enable row level security;
revoke all on public.settlements from anon, authenticated;
grant select on public.settlements to authenticated;
create policy settlements_select_own on public.settlements for select to authenticated using (recipient_id = auth.uid());

create function private.settle(uid uuid, amount numeric, currency text, kind text, ref text, label text, meta jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.settlements (recipient_id, amount, currency, kind, ref, label, meta)
  values (uid, round(amount, 2), currency, kind, coalesce(ref, ''), coalesce(label, ''), coalesce(meta, '{}'::jsonb));
$$;

create function public.claim_settlements() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); res jsonb;
begin
  with c as (update public.settlements set claimed_at = now() where recipient_id = uid and claimed_at is null returning *)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'amount', amount, 'currency', currency, 'kind', kind, 'ref', ref,
           'label', label, 'meta', meta, 'createdAt', created_at) order by created_at), '[]'::jsonb) into res from c;
  return res;
end $$;

create table public.treasuries (
  country_code text primary key check (country_code ~ '^[A-Z]{2}$'),
  balance numeric(18, 2) not null default 0
);
create table public.treasury_entries (
  id bigint generated always as identity primary key,
  country_code text not null references public.treasuries (country_code),
  amount numeric(18, 2) not null check (amount <> 0),
  kind text not null check (char_length(kind) between 1 and 40),
  ref text not null default '' check (char_length(ref) <= 80),
  created_at timestamptz not null default now()
);
create index treasury_entries_country on public.treasury_entries (country_code, created_at desc);
alter table public.treasuries enable row level security;
alter table public.treasury_entries enable row level security;
revoke all on public.treasuries, public.treasury_entries from anon, authenticated;
grant select on public.treasuries, public.treasury_entries to authenticated;
create policy treasuries_read on public.treasuries for select to authenticated using (true);
create policy treasury_entries_read on public.treasury_entries for select to authenticated using (true);

create function private.treasury_post(cc text, amount numeric, kind text, ref text default '') returns void language plpgsql security definer set search_path = '' as $$
begin
  if amount = 0 then return; end if;
  insert into public.treasuries (country_code) values (cc) on conflict do nothing;
  update public.treasuries set balance = balance + round(amount, 2) where country_code = cc;
  insert into public.treasury_entries (country_code, amount, kind, ref) values (cc, round(amount, 2), kind, coalesce(ref, ''));
end $$;

create function private.transfer_tax_rate(cc text) returns numeric language sql stable as $$ select 0.02::numeric; $$;
create function private.gains_tax_rate(cc text) returns numeric language sql stable as $$ select 0.20::numeric; $$;

create function private.weeks(n int) returns interval language sql immutable as $$ select make_interval(days => n); $$;

create table public.currency_scales (
  currency text primary key check (currency ~ '^[A-Z]{3}$'),
  scale numeric not null check (scale > 0 and scale < 1000000)
);
alter table public.currency_scales enable row level security;
revoke all on public.currency_scales from anon, authenticated;
grant select on public.currency_scales to authenticated;
create policy currency_scales_read on public.currency_scales for select to authenticated using (true);
create function private.currency_scale(cur text) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select scale from public.currency_scales where currency = cur), 1);
$$;

create function private.supply_open(uid uuid) returns boolean language sql stable as $$ select false; $$;
create function private.startups_open(uid uuid) returns boolean language sql stable as $$ select false; $$;
create function private.ventures_open(uid uuid) returns boolean language sql stable as $$ select false; $$;
create function private.exchange_open(uid uuid) returns boolean language sql stable as $$ select false; $$;
create function private.auctions_open(uid uuid) returns boolean language sql stable as $$ select false; $$;

create or replace function private.has_open_obligations(uid uuid) returns boolean language sql stable as $$
  select private.supply_open(uid) or private.startups_open(uid) or private.ventures_open(uid) or private.exchange_open(uid) or private.auctions_open(uid);
$$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.claim_settlements() to authenticated;
