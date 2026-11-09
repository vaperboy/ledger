-- Government: each country has a policy (the transfer tax and the capital gains tax that shared deals pay), a sitting president and
-- a public treasury (created in 0002, fed by those taxes, listing fees and fines). The office is filled by the election migration; until
-- someone holds it the defaults stand. The sitting president may nudge the two rates within fixed limits, and nothing else.

create table public.country_policy (
  country_code text primary key check (country_code ~ '^[A-Z]{2}$'),
  transfer_tax numeric(5, 4) not null default 0.02 check (transfer_tax between 0 and 0.05),
  gains_tax numeric(5, 4) not null default 0.20 check (gains_tax between 0.05 and 0.40),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);

-- One row per country and office: who holds it and until when. An empty holder means the office is vacant.
create table public.country_offices (
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  office text not null default 'president' check (office in ('president')),
  holder_id uuid references public.profiles (id) on delete set null,
  term_start timestamptz,
  term_end timestamptz,
  primary key (country_code, office)
);

alter table public.country_policy enable row level security;
alter table public.country_offices enable row level security;
revoke all on public.country_policy, public.country_offices from anon, authenticated;
grant select on public.country_policy, public.country_offices to authenticated;
-- Policy and office holders are public by nature: every player lives under them.
create policy country_policy_read on public.country_policy for select to authenticated using (true);
create policy country_offices_read on public.country_offices for select to authenticated using (true);

-- The rates the money functions of earlier migrations call.
create or replace function private.transfer_tax_rate(cc text) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select transfer_tax from public.country_policy where country_code = cc), 0.02);
$$;
create or replace function private.gains_tax_rate(cc text) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select gains_tax from public.country_policy where country_code = cc), 0.20);
$$;

-- Whether the user sits in the office right now.
create function private.holds_office(uid uuid, cc text) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.country_offices where country_code = cc and office = 'president' and holder_id = uid and term_end > now());
$$;

-- A country at a glance: balance, latest entries, rates, who governs.
create function public.country_overview(p_country text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); o public.country_offices;
begin
  if p_country !~ '^[A-Z]{2}$' then raise exception 'invalid_country' using errcode = 'P0001'; end if;
  select * into o from public.country_offices where country_code = p_country and office = 'president' and term_end > now();
  return jsonb_build_object('country', p_country,
    'treasury', coalesce((select balance from public.treasuries where country_code = p_country), 0),
    'transferTax', private.transfer_tax_rate(p_country), 'gainsTax', private.gains_tax_rate(p_country),
    'president', case when o.holder_id is null then null else jsonb_build_object('id', o.holder_id, 'name', private.display_name(o.holder_id), 'termEnd', o.term_end) end,
    'isPresident', o.holder_id = uid,
    'entries', coalesce((select jsonb_agg(jsonb_build_object('amount', amount, 'kind', kind, 'at', created_at) order by id desc)
                           from (select * from public.treasury_entries where country_code = p_country order by id desc limit 30) e), '[]'::jsonb));
end $$;

-- Only the sitting president, only for their own country, at most once a week, and by at most one point of the rate each time.
create function public.set_country_policy(p_country text, p_transfer_tax numeric, p_gains_tax numeric) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); cur public.country_policy; t0 numeric := private.transfer_tax_rate(p_country); g0 numeric := private.gains_tax_rate(p_country);
begin
  if not private.holds_office(uid, p_country) or (select country_code from public.profiles where id = uid) <> p_country then raise exception 'not_in_office' using errcode = 'P0001'; end if;
  select * into cur from public.country_policy where country_code = p_country;
  if cur.updated_at is not null and now() - cur.updated_at < private.weeks(7) then raise exception 'too_soon' using errcode = 'P0001'; end if;
  if p_transfer_tax not between 0 and 0.05 or p_gains_tax not between 0.05 and 0.40 then raise exception 'outside_limits' using errcode = 'P0001'; end if;
  if abs(p_transfer_tax - t0) > 0.01 or abs(p_gains_tax - g0) > 0.01 then raise exception 'change_too_large' using errcode = 'P0001'; end if;
  insert into public.country_policy (country_code, transfer_tax, gains_tax, updated_by) values (p_country, p_transfer_tax, p_gains_tax, uid)
    on conflict (country_code) do update set transfer_tax = excluded.transfer_tax, gains_tax = excluded.gains_tax, updated_at = now(), updated_by = uid;
  return jsonb_build_object('transferTax', p_transfer_tax, 'gainsTax', p_gains_tax);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.country_overview(text), public.set_country_policy(text, numeric, numeric) to authenticated;
