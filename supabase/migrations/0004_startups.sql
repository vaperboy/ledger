create type public.startup_status as enum ('raising', 'live', 'failed', 'closed');
create type public.startup_offer_status as enum ('open', 'sold', 'cancelled');

create table public.startups (
  id uuid primary key default gen_random_uuid(),
  founder_id uuid not null references public.profiles (id) on delete cascade,
  company_key text not null check (char_length(company_key) between 1 and 64),
  name text not null check (char_length(name) between 1 and 40),
  trade text not null check (char_length(trade) <= 40),
  pitch text not null default '' check (char_length(pitch) <= 300),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  plan_cost numeric(18, 2) not null check (plan_cost > 0),
  founder_put_in numeric(18, 2) not null,
  milestones int not null default 0 check (milestones between 0 and 3),
  stage_opened_at timestamptz not null default now(),
  status public.startup_status not null default 'raising',
  exited boolean not null default false,
  assets numeric(18, 2) not null default 0 check (assets >= 0),
  weekly_profit numeric(18, 2)[] not null default '{}' check (cardinality(weekly_profit) <= 13),
  created_at timestamptz not null default now(),
  constraint startup_plan_valid check (founder_put_in >= plan_cost / 3 - 0.005 and founder_put_in <= plan_cost)
);
create unique index startups_one_open_per_company on public.startups (founder_id, company_key) where status in ('raising', 'live');
create index startups_open on public.startups (status, created_at desc) where status in ('raising', 'live');

create table public.startup_investments (
  id uuid primary key default gen_random_uuid(),
  startup_id uuid not null references public.startups (id) on delete cascade,
  investor_id uuid not null references public.profiles (id) on delete cascade,
  link_key text not null,
  stage int not null check (stage between 0 and 2),
  amount numeric(18, 2) not null check (amount > 0),
  percent numeric(12, 6) not null check (percent > 0),
  created_at timestamptz not null default now(),
  released boolean not null default false,
  refunded boolean not null default false
);
create index startup_investments_startup on public.startup_investments (startup_id, stage);
create index startup_investments_investor on public.startup_investments (investor_id);

create table public.startup_holdings (
  startup_id uuid not null references public.startups (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  link_key text not null,
  percent numeric(12, 6) not null check (percent > 0),
  paid numeric(18, 2) not null check (paid >= 0),
  bought_at timestamptz not null default now(),
  primary key (startup_id, owner_id)
);

create table public.startup_offers (
  id uuid primary key default gen_random_uuid(),
  startup_id uuid not null references public.startups (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  percent numeric(12, 6) not null check (percent > 0),
  price numeric(18, 2) not null check (price > 0),
  status public.startup_offer_status not null default 'open',
  created_at timestamptz not null default now()
);
create index startup_offers_open on public.startup_offers (startup_id) where status = 'open';

alter table public.startups enable row level security;
alter table public.startup_investments enable row level security;
alter table public.startup_holdings enable row level security;
alter table public.startup_offers enable row level security;
revoke all on public.startups, public.startup_investments, public.startup_holdings, public.startup_offers from anon, authenticated;
grant select on public.startups, public.startup_investments, public.startup_holdings, public.startup_offers to authenticated;

create policy startups_own on public.startups for select to authenticated using (founder_id = auth.uid());
create policy startup_investments_own on public.startup_investments for select to authenticated using (investor_id = auth.uid());
create policy startup_holdings_own on public.startup_holdings for select to authenticated using (owner_id = auth.uid());
create policy startup_offers_own on public.startup_offers for select to authenticated using (seller_id = auth.uid());

create function private.cs_multiple(stage int) returns numeric language sql immutable as $$ select (array[2.5, 3.5, 5.0])[least(2, greatest(0, stage)) + 1]::numeric; $$;
create function private.cs_share(stage int) returns numeric language sql immutable as $$ select (array[0.40, 0.35, 0.25])[least(2, greatest(0, stage)) + 1]::numeric; $$;
create function private.cs_investor_target(s public.startups) returns numeric language sql immutable as $$ select greatest(0, s.plan_cost - s.founder_put_in); $$;
create function private.cs_valuation(s public.startups, stage int) returns numeric language sql immutable as $$ select s.plan_cost * private.cs_multiple(stage); $$;
create function private.cs_stage_target(s public.startups, stage int) returns numeric language sql immutable as $$ select private.cs_investor_target(s) * private.cs_share(stage); $$;
create function private.cs_price_per_percent(s public.startups, stage int) returns numeric language sql immutable as $$ select private.cs_valuation(s, stage) / 100; $$;

create function private.cs_raised(sid uuid, stage int) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(amount), 0) from public.startup_investments where startup_id = sid and public.startup_investments.stage = cs_raised.stage and not refunded;
$$;
create function private.cs_invested_by(sid uuid, uid uuid) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(amount), 0) from public.startup_investments where startup_id = sid and investor_id = uid and not refunded;
$$;
create function private.cs_sold_percent(sid uuid) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(percent), 0) from public.startup_investments where startup_id = sid and not refunded;
$$;

create function private.cs_real_value(s public.startups) returns numeric language sql immutable as $$
  select case when s.status in ('raising', 'live') then
    greatest(0, s.assets) + greatest(0, coalesce((select sum(x) from unnest(s.weekly_profit) x), 0)) else 0 end;
$$;

create function private.cs_founder_record(uid uuid) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'exits', (select count(*) from public.startups where founder_id = uid and exited),
    'fails', (select count(*) from public.startups where founder_id = uid and status in ('failed', 'closed') and not exited));
$$;

create function private.cs_json(s public.startups, viewer uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare open_stage int := case when s.status in ('raising', 'live') and s.milestones < 3 then s.milestones else null end; rec jsonb := private.cs_founder_record(s.founder_id);
        viral boolean;
begin
  select count(distinct investor_id) >= 5 into viral from public.startup_investments
   where startup_id = s.id and not refunded and created_at > now() - interval '7 days' and link_key <> private.link_key(s.founder_id) and investor_id <> s.founder_id;
  return jsonb_build_object(
    'id', s.id, 'name', s.name, 'trade', s.trade, 'pitch', s.pitch, 'founderID', s.founder_id, 'founderName', private.display_name(s.founder_id),
    'founderLinkKey', md5(private.link_key(s.founder_id)), 'founderExits', (rec->>'exits')::int, 'founderFails', (rec->>'fails')::int,
    'currency', s.currency, 'planCost', s.plan_cost, 'founderPutIn', s.founder_put_in, 'milestones', s.milestones, 'status', s.status,
    'openStage', open_stage, 'stageOpenedAt', s.stage_opened_at, 'createdAt', s.created_at, 'assets', s.assets, 'weeklyProfit', s.weekly_profit,
    'realValue', private.cs_real_value(s), 'soldPercent', private.cs_sold_percent(s.id), 'escrowHeld',
      (select coalesce(sum(amount), 0) from public.startup_investments where startup_id = s.id and not released and not refunded),
    'raisedByStage', jsonb_build_array(private.cs_raised(s.id, 0), private.cs_raised(s.id, 1), private.cs_raised(s.id, 2)),
    'stageTarget', case when open_stage is null then null else private.cs_stage_target(s, open_stage) end,
    'pricePerPercent', case when open_stage is null then null else private.cs_price_per_percent(s, open_stage) end,
    'perInvestorCap', private.cs_investor_target(s) * 0.20, 'myInvested', private.cs_invested_by(s.id, viewer), 'viral', coalesce(viral, false));
end $$;

create or replace function private.startups_open(uid uuid) returns boolean language sql stable as $$
  select exists (select 1 from public.startups st where st.founder_id = uid and st.status in ('raising', 'live')
                   and exists (select 1 from public.startup_investments i where i.startup_id = st.id and not i.refunded))
      or exists (select 1 from public.startup_investments i where i.investor_id = uid and not i.released and not i.refunded);
$$;

create function private.cs_fail(sid uuid, final public.startup_status) returns numeric language plpgsql security definer set search_path = '' as $$
declare s public.startups; i public.startup_investments; back numeric := 0;
begin
  select * into s from public.startups where id = sid for update;
  if s.status not in ('raising', 'live') then return 0; end if;
  for i in select * from public.startup_investments where startup_id = sid and not released and not refunded loop
    update public.startup_investments set refunded = true where id = i.id;
    perform private.settle(i.investor_id, i.amount, s.currency, 'startup_refund', sid::text, 'Escrow returned: ' || s.name, jsonb_build_object('startupID', sid));
    back := back + i.amount;
  end loop;
  update public.startups set status = final, assets = 0 where id = sid;
  update public.startup_offers set status = 'cancelled' where startup_id = sid and status = 'open';
  return back;
end $$;

create function public.list_startup(p_company_key text, p_name text, p_trade text, p_pitch text, p_plan_cost numeric, p_founder_put_in numeric, p_currency text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); s public.startups; fee numeric; cc text;
begin
  perform private.require_free(uid, 'trade');
  if now() - (select created_at from public.profiles where id = uid) < private.weeks(4) then raise exception 'new_account' using errcode = 'P0001'; end if;
  if p_plan_cost is null or p_plan_cost <= 0 or p_founder_put_in < p_plan_cost / 3 - 0.005 or p_founder_put_in > p_plan_cost then raise exception 'invalid_plan' using errcode = 'P0001'; end if;
  if exists (select 1 from public.startups where founder_id = uid and company_key = p_company_key and status in ('raising', 'live')) then raise exception 'already_listed' using errcode = 'P0001'; end if;
  insert into public.startups (founder_id, company_key, name, trade, pitch, currency, plan_cost, founder_put_in, assets)
    values (uid, p_company_key, p_name, p_trade, coalesce(p_pitch, ''), p_currency, round(p_plan_cost, 2), round(p_founder_put_in, 2), round(p_founder_put_in, 2)) returning * into s;
  fee := round(150000 * private.currency_scale(p_currency), 2);
  perform private.settle(uid, -fee, p_currency, 'startup_entry_fee', s.id::text, 'Startup entry cost: ' || s.name, jsonb_build_object('startupID', s.id));
  select country_code into cc from public.profiles where id = uid;
  perform private.treasury_post(cc, fee, 'startup_entry_fee', s.id::text);
  return private.cs_json(s, uid);
end $$;

create function public.report_startup_progress(p_startup uuid, p_milestones int, p_assets numeric, p_weekly_profit numeric default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); s public.startups; rel numeric := 0;
begin
  select * into s from public.startups where id = p_startup and founder_id = uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if s.status not in ('raising', 'live') then raise exception 'not_open' using errcode = 'P0001'; end if;
  if p_milestones < s.milestones or p_milestones > s.milestones + 1 or p_milestones > 3 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
  if p_assets is null or p_assets < 0 then raise exception 'invalid_progress' using errcode = 'P0001'; end if;
  if p_milestones > s.milestones then
    if now() - s.stage_opened_at < private.weeks(2) then raise exception 'too_soon' using errcode = 'P0001'; end if;
    select coalesce(sum(amount), 0) into rel from public.startup_investments where startup_id = s.id and stage = s.milestones and not released and not refunded;
    update public.startup_investments set released = true where startup_id = s.id and stage = s.milestones and not released and not refunded;
    if rel > 0 then
      perform private.settle(uid, rel, s.currency, 'startup_release', s.id::text, 'Investors'' money released: ' || s.name, jsonb_build_object('startupID', s.id, 'stage', s.milestones));
    end if;
    update public.startups set milestones = p_milestones, stage_opened_at = now(), status = 'live' where id = s.id;
  end if;
  update public.startups set assets = least(p_assets, plan_cost * 3),
      weekly_profit = case when p_weekly_profit is null then weekly_profit
                           else (weekly_profit || greatest(-plan_cost, least(plan_cost, p_weekly_profit)))[greatest(1, cardinality(weekly_profit) + 1 - 12):] end
    where id = s.id returning * into s;
  return private.cs_json(s, uid);
end $$;

create function public.report_startup_closed(p_startup uuid) returns numeric language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if not exists (select 1 from public.startups where id = p_startup and founder_id = uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  return private.cs_fail(p_startup, 'failed');
end $$;

create function public.list_startups() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(private.cs_json(s, uid) order by s.created_at desc) from public.startups s
                    where s.status in ('raising', 'live') and not private.is_blocked_between(uid, s.founder_id)), '[]'::jsonb);
end $$;

create function public.invest_in_startup(p_startup uuid, p_amount numeric, p_currency text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); s public.startups; stage int; room numeric; mine numeric; minimum numeric; pct numeric; inv public.startup_investments;
begin
  perform private.require_free(uid, 'trade');
  select * into s from public.startups where id = p_startup for update;
  if not found or private.is_blocked_between(uid, s.founder_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount' using errcode = 'P0001'; end if;
  if p_currency <> s.currency then raise exception 'currency_mismatch' using errcode = 'P0001'; end if;
  if now() - (select created_at from public.profiles where id = uid) < private.weeks(4) then raise exception 'new_account' using errcode = 'P0001'; end if;
  if uid = s.founder_id or private.linked(uid, s.founder_id) then raise exception 'linked_to_founder' using errcode = 'P0001'; end if;
  if s.status not in ('raising', 'live') or s.milestones >= 3 then raise exception 'not_open' using errcode = 'P0001'; end if;
  stage := s.milestones;
  room := private.cs_stage_target(s, stage) - private.cs_raised(s.id, stage);
  if p_amount > room + 0.005 then raise exception 'stage_full' using errcode = 'P0001'; end if;
  mine := private.cs_investor_target(s) * 0.20 - private.cs_invested_by(s.id, uid);
  if p_amount > mine + 0.005 then raise exception 'investor_cap' using errcode = 'P0001'; end if;
  minimum := least(private.cs_stage_target(s, stage) * 0.02, greatest(room, 0));
  if p_amount < minimum - 0.005 then raise exception 'too_small' using errcode = 'P0001'; end if;
  pct := p_amount / private.cs_price_per_percent(s, stage);
  insert into public.startup_investments (startup_id, investor_id, link_key, stage, amount, percent) values (s.id, uid, private.link_key(uid), stage, round(p_amount, 2), pct) returning * into inv;
  insert into public.startup_holdings (startup_id, owner_id, link_key, percent, paid) values (s.id, uid, private.link_key(uid), pct, round(p_amount, 2))
    on conflict (startup_id, owner_id) do update set percent = public.startup_holdings.percent + excluded.percent, paid = public.startup_holdings.paid + excluded.paid, bought_at = now();
  perform private.settle(uid, -round(p_amount, 2), s.currency, 'startup_investment', s.id::text, 'Invested in ' || s.name, jsonb_build_object('startupID', s.id, 'stage', stage, 'percent', pct));
  return jsonb_build_object('stage', stage, 'amount', inv.amount, 'percent', pct, 'pricePerPercent', private.cs_price_per_percent(s, stage),
    'lockedUntil', now() + private.weeks(12), 'releasedAtMilestone', (array['The startup opens', 'It makes its first sales', 'It makes its first profit'])[stage + 1]);
end $$;

create function public.my_startup_holdings() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('startupID', h.startup_id, 'percent', h.percent, 'paid', h.paid, 'boughtAt', h.bought_at,
           'lockedUntil', h.bought_at + private.weeks(12), 'name', s.name, 'status', s.status,
           'value', private.cs_real_value(s) * h.percent / 100)) from public.startup_holdings h join public.startups s on s.id = h.startup_id where h.owner_id = uid), '[]'::jsonb);
end $$;

create function public.offer_startup_shares(p_startup uuid, p_percent numeric, p_price numeric) returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); s public.startups; h public.startup_holdings; fair numeric; already numeric; oid uuid;
begin
  perform private.require_free(uid, 'trade');
  select * into s from public.startups where id = p_startup;
  select * into h from public.startup_holdings where startup_id = p_startup and owner_id = uid;
  if s.id is null or h.owner_id is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  if s.status not in ('raising', 'live') then raise exception 'not_live' using errcode = 'P0001'; end if;
  select coalesce(sum(percent), 0) into already from public.startup_offers where startup_id = p_startup and seller_id = uid and status = 'open';
  if p_percent is null or p_percent <= 0 or p_percent + already > h.percent + 1e-9 then raise exception 'too_many' using errcode = 'P0001'; end if;
  if now() < h.bought_at + private.weeks(12) then raise exception 'locked' using errcode = 'P0001'; end if;
  fair := private.cs_real_value(s) * p_percent / 100;
  if p_price is null or p_price < fair * 0.8 - 0.005 or p_price > fair * 1.25 + 0.005 then raise exception 'outside_band' using errcode = 'P0001'; end if;
  insert into public.startup_offers (startup_id, seller_id, percent, price) values (p_startup, uid, p_percent, round(p_price, 2)) returning id into oid;
  return oid;
end $$;

create function public.cancel_startup_offer(p_offer uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  update public.startup_offers set status = 'cancelled' where id = p_offer and seller_id = uid and status = 'open';
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
end $$;

create function public.startup_offers_for(p_startup uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'startupID', o.startup_id, 'sellerID', o.seller_id, 'sellerName', private.display_name(o.seller_id),
            'sellerLinkKey', md5(private.link_key(o.seller_id)), 'percent', o.percent, 'price', o.price, 'createdAt', o.created_at) order by o.price / o.percent)
     from public.startup_offers o where o.startup_id = p_startup and o.status = 'open' and not private.is_blocked_between(uid, o.seller_id)), '[]'::jsonb);
end $$;

create function public.buy_startup_offer(p_offer uuid, p_currency text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); o public.startup_offers; s public.startups; h public.startup_holdings; fair numeric; basis numeric; gain numeric;
        tax numeric; gtax numeric; bcc text; scc text;
begin
  perform private.require_free(uid, 'trade');
  select * into o from public.startup_offers where id = p_offer and status = 'open' for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  select * into s from public.startups where id = o.startup_id for update;
  select * into h from public.startup_holdings where startup_id = o.startup_id and owner_id = o.seller_id for update;
  if s.status not in ('raising', 'live') then raise exception 'not_live' using errcode = 'P0001'; end if;
  if p_currency <> s.currency then raise exception 'currency_mismatch' using errcode = 'P0001'; end if;
  if h.owner_id is null or h.percent + 1e-9 < o.percent then raise exception 'too_many' using errcode = 'P0001'; end if;
  if uid = o.seller_id or private.linked(uid, o.seller_id) then raise exception 'linked_parties' using errcode = 'P0001'; end if;
  if private.is_blocked_between(uid, o.seller_id) then raise exception 'blocked' using errcode = 'P0001'; end if;
  if now() - (select created_at from public.profiles where id = uid) < private.weeks(4) then raise exception 'new_account' using errcode = 'P0001'; end if;
  if uid = s.founder_id or private.linked(uid, s.founder_id) then raise exception 'linked_to_founder' using errcode = 'P0001'; end if;
  if now() < h.bought_at + private.weeks(12) then raise exception 'locked' using errcode = 'P0001'; end if;
  fair := private.cs_real_value(s) * o.percent / 100;
  if o.price < fair * 0.8 - 0.005 or o.price > fair * 1.25 + 0.005 then raise exception 'outside_band' using errcode = 'P0001'; end if;
  select country_code into bcc from public.profiles where id = uid;
  select country_code into scc from public.profiles where id = o.seller_id;
  basis := h.paid * o.percent / h.percent;
  gain := o.price - basis;
  tax := round(o.price * private.transfer_tax_rate(bcc), 2);
  gtax := round(greatest(0, gain) * private.gains_tax_rate(scc), 2);
  if h.percent - o.percent <= 1e-9 then delete from public.startup_holdings where startup_id = s.id and owner_id = o.seller_id;
  else update public.startup_holdings set percent = percent - o.percent, paid = paid - basis where startup_id = s.id and owner_id = o.seller_id; end if;
  insert into public.startup_holdings (startup_id, owner_id, link_key, percent, paid) values (s.id, uid, private.link_key(uid), o.percent, o.price)
    on conflict (startup_id, owner_id) do update set percent = public.startup_holdings.percent + excluded.percent, paid = public.startup_holdings.paid + excluded.paid, bought_at = now();
  update public.startup_offers set status = 'sold' where id = o.id;
  perform private.settle(uid, -(o.price + tax), s.currency, 'startup_share_purchase', s.id::text, 'Bought shares in ' || s.name,
    jsonb_build_object('startupID', s.id, 'percent', o.percent, 'price', o.price, 'transferTax', tax));
  perform private.settle(o.seller_id, o.price - gtax, s.currency, 'startup_share_sale', s.id::text, 'Sold shares in ' || s.name,
    jsonb_build_object('startupID', s.id, 'percent', o.percent, 'price', o.price, 'gainsTax', gtax, 'gain', gain));
  perform private.treasury_post(bcc, tax, 'startup_transfer_tax', s.id::text);
  perform private.treasury_post(scc, gtax, 'startup_gains_tax', s.id::text);
  return jsonb_build_object('startupID', s.id, 'percent', o.percent, 'price', o.price, 'transferTax', tax, 'gainsTax', gtax);
end $$;

create function private.run_startup_expiry() returns int language plpgsql security definer set search_path = '' as $$
declare s record; n int := 0;
begin
  for s in select id from public.startups where status in ('raising', 'live') and milestones < 3 and stage_opened_at < now() - private.weeks(30) loop
    perform private.cs_fail(s.id, 'closed');
    n := n + 1;
  end loop;
  return n;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.list_startup(text, text, text, text, numeric, numeric, text), public.report_startup_progress(uuid, int, numeric, numeric),
  public.report_startup_closed(uuid), public.list_startups(), public.invest_in_startup(uuid, numeric, text), public.my_startup_holdings(),
  public.offer_startup_shares(uuid, numeric, numeric), public.cancel_startup_offer(uuid), public.startup_offers_for(uuid),
  public.buy_startup_offer(uuid, text) to authenticated;
