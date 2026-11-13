-- Server-side limits for co-owned companies, supply fees, the leaderboard, the marketplace and computer-run players,
-- and unused money calls closed until the app uses them. Safe to run more than once.

-- Replaces text inside an existing function. Text that is already in place is skipped, so a second run changes nothing.
create or replace function private.rewire34(fn regprocedure, pairs text[]) returns void language plpgsql as $$
declare d text := pg_get_functiondef(fn); n text; i int; changed boolean := false;
begin
  for i in 1..cardinality(pairs) by 2 loop
    continue when position(pairs[i + 1] in d) > 0;
    n := replace(d, pairs[i], pairs[i + 1]);
    if n = d then raise exception 'rewire34: text not found in %: %', fn, pairs[i]; end if;
    d := n;
    changed := true;
  end loop;
  if changed then execute d; end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Currencies: kroner per unit for every currency the game uses (the game's own fixed rates).

create or replace function private.market_fx(cur text) returns numeric language sql immutable as $$
  select case cur when 'NOK' then 1 when 'SEK' then 1.0190476 when 'DKK' then 1.562 when 'EUR' then 11.6304348 when 'GBP' then 13.5443038
    when 'USD' then 10.7 when 'CAD' then 7.6428571 when 'AUD' then 7.1333333 when 'JPY' then 0.0713333 when 'BRL' then 1.8448276
    when 'PLN' then 2.675 when 'INR' then 0.1289 when 'ZAR' then 0.5784 when 'KRW' then 0.0076429 when 'CHF' then 13.4 when 'MXN' then 0.578
    when 'AED' then 2.9135 when 'SGD' then 8.29 else 1 end::numeric;
$$;

create or replace function private.fx_known(cur text) returns boolean language sql immutable as $$
  select coalesce(cur in ('NOK','SEK','DKK','EUR','GBP','USD','CAD','AUD','JPY','BRL','PLN','INR','ZAR','KRW','CHF','MXN','AED','SGD'), false);
$$;

create or replace function private.country_currency(cc text) returns text language sql immutable as $$
  select case cc when 'NO' then 'NOK' when 'SE' then 'SEK' when 'PL' then 'PLN' when 'UK' then 'GBP' when 'US' then 'USD' when 'CA' then 'CAD'
    when 'AU' then 'AUD' when 'JP' then 'JPY' when 'KR' then 'KRW' when 'BR' then 'BRL' when 'CH' then 'CHF' when 'MX' then 'MXN'
    when 'AE' then 'AED' when 'DK' then 'DKK' when 'SG' then 'SGD' when 'IN' then 'INR' when 'ZA' then 'ZAR' else 'EUR' end;
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Co-owned companies: the value moves in small steps with a history every owner can read, payouts and capital calls are capped
-- against that value and spaced out, and computer-run co-owners never bring in more than a small fixed sum.

create table if not exists public.venture_value_log (
  venture_id uuid not null references public.ventures (id) on delete cascade,
  value numeric(18, 2) not null,
  asked numeric(18, 2),
  at timestamptz not null default now()
);
create index if not exists venture_value_log_venture on public.venture_value_log (venture_id, at desc);
alter table public.venture_value_log enable row level security;
revoke all on public.venture_value_log from anon, authenticated;
grant select on public.venture_value_log to authenticated;
drop policy if exists venture_value_log_partner on public.venture_value_log;
create policy venture_value_log_partner on public.venture_value_log for select to authenticated using (private.is_partner(venture_id, auth.uid()));

insert into public.venture_value_log (venture_id, value, at)
  select v.id, v.value, now() - interval '1 day' from public.ventures v
   where not exists (select 1 from public.venture_value_log x where x.venture_id = v.id);

create or replace function private.jv_log_value() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.venture_value_log (venture_id, value) values (new.id, new.value);
  return new;
end $$;
drop trigger if exists venture_value_logged on public.ventures;
create trigger venture_value_logged after insert on public.ventures for each row execute function private.jv_log_value();

create or replace function private.jv_const(k text) returns numeric language sql immutable as $$
  select case k when 'start_cap_nok' then 200000000 when 'value_step' then 0.10 when 'value_growth_week' then 1.5
                when 'payout_share' then 0.20 when 'payout_gap_days' then 7 when 'bot_stake_nok' then 2000000 end::numeric;
$$;

create or replace function private.jv_bot_stake_cap(cur text) returns numeric language sql immutable as $$
  select round(private.jv_const('bot_stake_nok') / private.market_fx(cur), 2);
$$;

-- The largest dividend or capital call one decision may move: a fifth of the value the server holds.
create or replace function private.jv_payout_cap(v public.ventures) returns numeric language sql stable as $$
  select round(greatest(v.value, 0) * private.jv_const('payout_share'), 2);
$$;

-- An open item of this kind, or one that passed in the last week, blocks another. A policy dividend paid in the last week blocks a voted one.
create or replace function private.jv_payout_recent(p_vid uuid, p_kind text, p_skip uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.venture_items i join public.venture_meetings m on m.id = i.meeting_id
                  where m.venture_id = p_vid and i.kind::text = p_kind and i.id is distinct from p_skip
                    and ((m.closed_at is null and i.outcome is null)
                         or (i.outcome = 'passed' and (m.closed_at is null or m.closed_at > now() - make_interval(days => private.jv_const('payout_gap_days')::int)))))
      or (p_kind = 'dividend' and exists (select 1 from public.venture_payouts x where x.venture_id = p_vid
                                            and x.created_at > now() - make_interval(days => private.jv_const('payout_gap_days')::int)));
$$;

create or replace function public.create_venture(p_company_key text, p_name text, p_value numeric, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures; val numeric;
begin
  perform private.require_free(uid, 'trade');
  if p_value is null or p_value < 0 or p_currency is null or not private.fx_known(p_currency) then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  val := round(least(p_value, private.jv_const('start_cap_nok') / private.market_fx(p_currency)), 2);
  insert into public.ventures (chair_id, company_key, name, currency, value) values (uid, p_company_key, p_name, p_currency, val) returning * into v;
  insert into public.venture_partners (venture_id, member_id, shares) values (v.id, uid, v.total_shares);
  return private.jv_json(v, uid);
end $$;

-- The owner's report moves the value at most a tenth per game day and half again in seven days, and not at all while a payout
-- or a closure waits for a vote. The value the server keeps is returned.
drop function if exists public.report_venture_value(uuid, numeric);
create function public.report_venture_value(p_venture uuid, p_value numeric) returns numeric language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures; lo numeric; hi numeric; base numeric; val numeric;
begin
  if p_value is null or p_value < 0 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  select * into v from public.ventures where id = p_venture and chair_id = uid and dissolved_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if exists (select 1 from public.venture_value_log where venture_id = v.id and at > now() - private.game_days(1)) then return v.value; end if;
  if exists (select 1 from public.venture_items i join public.venture_meetings m on m.id = i.meeting_id
              where m.venture_id = v.id and m.closed_at is null and i.outcome is null and i.kind::text in ('dividend', 'capital', 'dissolve')) then
    return v.value;
  end if;
  if v.value <= 0 then
    val := least(p_value, private.jv_const('start_cap_nok') / private.market_fx(v.currency));
  else
    lo := v.value * (1 - private.jv_const('value_step'));
    hi := v.value * (1 + private.jv_const('value_step'));
    select min(value) into base from public.venture_value_log where venture_id = v.id and at > now() - private.weeks(7) and value > 0;
    hi := least(hi, greatest(coalesce(base, v.value) * private.jv_const('value_growth_week'), v.value));
    val := least(greatest(p_value, lo), hi);
  end if;
  val := round(val, 2);
  update public.ventures set value = val where id = v.id;
  insert into public.venture_value_log (venture_id, value, asked) values (v.id, val, round(least(p_value, 1e15), 2));
  return val;
end $$;

-- Every owner can read how the value moved, newest first.
create or replace function public.venture_value_history(p_venture uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if not private.is_partner(p_venture, uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('value', x.value, 'at', x.at) order by x.at desc)
                     from (select value, at from public.venture_value_log where venture_id = p_venture order by at desc limit 60) x), '[]'::jsonb);
end $$;

create or replace function private.jv_check_item(v public.ventures, kind text, params jsonb) returns void language plpgsql stable security definer set search_path = '' as $$
declare amt numeric;
begin
  if kind is null or kind not in ('dividend', 'price', 'hire', 'sell', 'partner', 'capital', 'dissolve', 'policy', 'setting') then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
  if kind in ('dividend', 'capital') then
    begin
      amt := (params ->> 'amount')::numeric;
    exception when others then
      amt := null;
    end;
    if amt is null or amt <= 0 or amt > 1e12 then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
    if amt > private.jv_payout_cap(v) then raise exception 'invalid_amount' using errcode = 'P0001'; end if;
    if private.jv_payout_recent(v.id, kind, null) then raise exception 'too_soon' using errcode = 'P0001'; end if;
  elsif kind = 'partner' then
    if (params ->> 'invitee') is null or (params ->> 'pct') is null or (params ->> 'price') is null then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
  elsif kind = 'policy' then
    if coalesce(params ->> 'policy', '') not in ('none', 'low', 'mid', 'high') then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
    if params ->> 'policy' = v.dividend_policy then raise exception 'already_set' using errcode = 'P0001'; end if;
  elsif kind = 'setting' then
    if coalesce(params ->> 'key', '') !~ '^[a-z][a-z0-9_.:-]{0,39}$' or coalesce(jsonb_typeof(params -> 'value'), '') not in ('string', 'number', 'boolean')
       or char_length(params::text) > 600 then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
    if v.settings -> (params ->> 'key') = params -> 'value' then raise exception 'already_set' using errcode = 'P0001'; end if;
    if not v.settings ? (params ->> 'key') and (select count(*) from jsonb_object_keys(v.settings)) >= 60 then raise exception 'too_many_settings' using errcode = 'P0001'; end if;
  end if;
end $$;

-- Carries out a passed item. Amounts are capped again against today's value; a second payout of a kind inside a week moves nothing,
-- and computer-run co-owners' parts of a capital call are never credited to the company.
create or replace function private.jv_apply(v public.ventures, it public.venture_items) returns void language plpgsql security definer set search_path = '' as $$
declare k text := it.kind::text; amt numeric; part numeric; paid numeric := 0; r record; pid uuid; val numeric; tot numeric := private.jv_total_shares(v.id);
begin
  if k in ('dividend', 'capital') then
    if tot <= 0 or private.jv_payout_recent(v.id, k, it.id) then return; end if;
    amt := least(coalesce((it.params ->> 'amount')::numeric, 0), private.jv_payout_cap(v));
    if amt <= 0 then return; end if;
  end if;
  if k = 'dividend' then
    for r in select member_id, shares from public.venture_partners where venture_id = v.id and member_id <> v.chair_id loop
      part := round(amt * r.shares / tot, 2);
      continue when part <= 0;
      perform private.settle(r.member_id, part, v.currency, 'venture_dividend', v.id::text, 'Dividend: ' || v.name, jsonb_build_object('ventureID', v.id));
      paid := paid + part;
    end loop;
    if paid > 0 then
      perform private.settle(v.chair_id, -paid, v.currency, 'venture_company_payout', v.id::text, 'Dividend paid to partners', jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
    end if;
  elsif k = 'capital' then
    for r in select p.member_id, p.shares, coalesce(b.is_bot, false) as bot from public.venture_partners p left join public.profiles b on b.id = p.member_id
              where p.venture_id = v.id and p.member_id <> v.chair_id loop
      part := round(amt * r.shares / tot, 2);
      continue when part <= 0 or r.bot;
      perform private.settle(r.member_id, -part, v.currency, 'venture_capital_call', v.id::text, 'Capital call: ' || v.name, jsonb_build_object('ventureID', v.id));
      paid := paid + part;
    end loop;
    if paid > 0 then
      perform private.settle(v.chair_id, paid, v.currency, 'venture_capital', v.id::text, 'Capital called from partners', jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
    end if;
  elsif k = 'dissolve' then
    val := greatest(v.value, 0);
    for r in select member_id, shares from public.venture_partners where venture_id = v.id and member_id <> v.chair_id loop
      perform private.settle(r.member_id, floor(val * r.shares / tot * 100) / 100, v.currency, 'venture_dissolved', v.id::text, 'Joint venture closed: ' || v.name, jsonb_build_object('ventureID', v.id));
      paid := paid + floor(val * r.shares / tot * 100) / 100;
    end loop;
    perform private.settle(v.chair_id, -paid, v.currency, 'venture_company_payout', v.id::text, 'Closing payout to partners', jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
    update public.ventures set dissolved_at = now() where id = v.id;
  elsif k = 'partner' then
    pid := (it.params ->> 'invitee')::uuid;
    begin
      perform private.jv_invite_check(v, v.chair_id, pid, (it.params ->> 'pct')::numeric, (it.params ->> 'price')::numeric);
      insert into public.venture_invites (venture_id, invitee_id, pct, price, fair)
        values (v.id, pid, (it.params ->> 'pct')::numeric, round((it.params ->> 'price')::numeric, 2), round(private.jv_fair_price(v.value, (it.params ->> 'pct')::numeric), 2));
    exception when others then null;
    end;
  else
    perform private.jv_apply_change(v.id, k, it.params);
  end if;
end $$;

-- Every invitee answers to the same rules: only friends can be invited.
create or replace function private.jv_invite_check(v public.ventures, inviter uuid, invitee uuid, pct numeric, price numeric) returns numeric
language plpgsql stable security definer set search_path = '' as $$
declare fair numeric; partners int; chair_after numeric;
begin
  if not exists (select 1 from public.profiles where id = invitee and deleted_at is null) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if not private.are_friends(inviter, invitee) then raise exception 'not_friends' using errcode = 'P0001'; end if;
  if private.is_blocked_between(inviter, invitee) then raise exception 'blocked' using errcode = 'P0001'; end if;
  if private.linked(inviter, invitee) or exists (select 1 from public.venture_partners p join public.profiles q on q.id = p.member_id
       join public.profiles r on r.id = invitee where p.venture_id = v.id and q.link_key = r.link_key) then raise exception 'linked_account' using errcode = 'P0001'; end if;
  if private.is_partner(v.id, invitee) then raise exception 'already_partner' using errcode = 'P0001'; end if;
  select count(*) - 1 into partners from public.venture_partners where venture_id = v.id;
  chair_after := coalesce(private.jv_chair_pct(v.id), 0) * (100 - pct) / 100;
  if partners >= 5 then raise exception 'too_many_partners' using errcode = 'P0001'; end if;
  if pct < 2 or pct > 49 or chair_after < 1 then raise exception 'invalid_stake' using errcode = 'P0001'; end if;
  fair := private.jv_fair_price(v.value, pct);
  if fair <= 0 then raise exception 'worthless' using errcode = 'P0001'; end if;
  if price < fair * private.rule_num('band.venture_low') - 0.005 or price > fair * private.rule_num('band.venture_high') + 0.005 then
    raise exception 'outside_band' using errcode = 'P0001';
  end if;
  return fair;
end $$;

-- A computer-run co-owner pays at most the fair price of today's value, and never more than a small fixed sum.
create or replace function private.jv_join(v public.ventures, invitee uuid, pct numeric, price numeric) returns void language plpgsql security definer set search_path = '' as $$
declare total int := private.jv_total_shares(v.id); new_shares int := greatest(1, round(total * pct / (100 - pct))::int);
begin
  if private.jv_is_bot(invitee) and price > least(private.jv_fair_price(v.value, pct), private.jv_bot_stake_cap(v.currency)) + 0.005 then
    raise exception 'outside_band' using errcode = 'P0001';
  end if;
  insert into public.venture_partners (venture_id, member_id, shares, lock_until) values (v.id, invitee, new_shares, now() + private.weeks(26));
  perform private.settle(invitee, -price, v.currency, 'venture_stake', v.id::text, 'Joined ' || v.name, jsonb_build_object('ventureID', v.id, 'percent', pct));
  perform private.settle(v.chair_id, price, v.currency, 'venture_capital', v.id::text, 'New partner in ' || v.name,
    jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key, 'partner', private.display_name(invitee)));
end $$;

select private.rewire34('private.jv_bot_act()'::regprocedure, array[
  $a$if v.dissolved_at is null and abs(hashtext(i.id::text || 'a')) % 100 < least(95, greatest(25, 115 - 35 * ratio)) then$a$,
  $a$if v.dissolved_at is null and i.price <= least(private.jv_fair_price(v.value, i.pct), private.jv_bot_stake_cap(v.currency)) + 0.005
       and abs(hashtext(i.id::text || 'a')) % 100 < least(95, greatest(25, 115 - 35 * ratio)) then$a$]);

-- ---------------------------------------------------------------------------------------------------------------------
-- Supply: ending a deal early charges the buyer the fee the supplier receives.

create or replace function public.end_supply_contract(p_company_key text, p_line_id text) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); c public.supply_contracts; l public.supply_listings; fee numeric;
begin
  select * into c from public.supply_contracts where buyer_id = uid and buyer_company_key = p_company_key and line_id = p_line_id and ended_at is null for update;
  if not found then return; end if;
  update public.supply_contracts set ended_at = now(), end_reason = 'buyerEnded', acknowledged = true where id = c.id;
  select * into l from public.supply_listings where id = c.listing_id;
  fee := round(c.units_per_week * coalesce(c.unit_price, private.supply_unit_price(l)) * 2, 2);
  perform private.settle(uid, -fee, l.currency, 'supply_end_fee', c.id::text || ':end', 'Fee for ending a supply deal early.',
    jsonb_build_object('companyKey', c.buyer_company_key, 'lineID', c.line_id));
  perform private.settle(c.supplier_id, fee, l.currency, 'supply_end_fee', c.id::text || ':end', private.display_name(uid) || ' ended the supply and paid the fee of two weeks of the order.',
    jsonb_build_object('companyKey', l.company_key, 'listingID', l.id));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Leaderboard: the week can only move as fast as a person can play, and net worth must fit a fixed growth curve by week and
-- a growth limit since the last accepted figure. Refused and very high figures are kept for review.

alter table public.leaderboard_entries add column if not exists anchor_week int;
alter table public.leaderboard_entries add column if not exists anchor_worth numeric(20, 2);

create table if not exists public.leaderboard_flags (
  id bigserial primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  net_worth numeric(20, 2),
  trading_result numeric(20, 2),
  game_week int,
  reason text not null,
  accepted boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists leaderboard_flags_user on public.leaderboard_flags (user_id, created_at desc);
alter table public.leaderboard_flags enable row level security;
revoke all on public.leaderboard_flags from anon, authenticated;

create or replace function private.board_const(k text) returns numeric language sql immutable as $$
  select case k when 'weeks_per_day' then 80 when 'week_slack' then 10 when 'start_nok' then 5000000 when 'curve' then 1.05
                when 'max_nok' then 200000000000 when 'step' then 1.15 when 'step_nok' then 2000000 when 'review_nok' then 10000000000 end::numeric;
$$;

-- The highest net worth a game of this week can plausibly have, in the player's own currency.
create or replace function private.board_ceiling(cc text, wk int) returns numeric language sql immutable as $$
  select least(private.board_const('start_nok') * power(private.board_const('curve'), least(greatest(wk, 0), 2000)), private.board_const('max_nok'))
         / private.market_fx(private.country_currency(cc));
$$;

create or replace function public.publish_leaderboard(p_net_worth numeric, p_trading_result numeric, p_game_week int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); prior public.leaderboard_entries; me public.profiles; scale numeric; days numeric; max_week numeric;
        aw int; anw numeric; dw int; ceiling_nw numeric; why text;
begin
  perform private.require_free(uid, 'trade');
  if p_net_worth is null or p_trading_result is null or p_game_week is null
     or p_net_worth not between -1000000000000 and 10000000000000 or p_trading_result not between -1000000000000 and 1000000000000
     or p_game_week not between 0 and 100000 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  select * into me from public.profiles where id = uid;
  select * into prior from public.leaderboard_entries where user_id = uid;
  if found and now() - prior.updated_at < interval '30 seconds' then return jsonb_build_object('accepted', false, 'reason', 'too_soon'); end if;
  scale := 1 / private.market_fx(private.country_currency(me.country_code));

  days := extract(epoch from now() - coalesce(prior.updated_at, me.created_at, now())) / 86400;
  max_week := coalesce(prior.game_week, 0) + private.board_const('weeks_per_day') * greatest(days, 0) + private.board_const('week_slack');
  ceiling_nw := private.board_ceiling(me.country_code, p_game_week);
  if prior.user_id is not null then
    if p_game_week > prior.game_week then
      aw := prior.game_week; anw := prior.net_worth;
    else
      aw := coalesce(prior.anchor_week, prior.game_week); anw := coalesce(prior.anchor_worth, prior.net_worth);
    end if;
    dw := greatest(1, p_game_week - aw);
    ceiling_nw := least(ceiling_nw, greatest(anw, 0) * power(private.board_const('step'), least(dw, 500)) + scale * private.board_const('step_nok') * dw);
  end if;

  why := case when p_game_week > max_week then 'week_too_fast'
              when p_net_worth > ceiling_nw then 'net_worth'
              when abs(p_trading_result) > abs(p_net_worth) * 3 + 1000000 * scale then 'trading_result' end;
  if why is not null then
    insert into public.leaderboard_flags (user_id, net_worth, trading_result, game_week, reason, accepted) values (uid, p_net_worth, p_trading_result, p_game_week, why, false);
    return jsonb_build_object('accepted', false, 'reason', 'implausible');
  end if;
  if p_net_worth > private.board_const('review_nok') * scale then
    insert into public.leaderboard_flags (user_id, net_worth, trading_result, game_week, reason, accepted) values (uid, p_net_worth, p_trading_result, p_game_week, 'review', true);
  end if;
  insert into public.leaderboard_entries (user_id, net_worth, trading_result, game_week, anchor_week, anchor_worth)
    values (uid, round(p_net_worth, 2), round(p_trading_result, 2), p_game_week, null, null)
    on conflict (user_id) do update set net_worth = excluded.net_worth, trading_result = excluded.trading_result,
                                        game_week = greatest(public.leaderboard_entries.game_week, excluded.game_week),
                                        anchor_week = aw, anchor_worth = anw, updated_at = now();
  return jsonb_build_object('accepted', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Marketplace: a listed item must be a kind of thing the game has, with its value and price near the game's price for it,
-- and a seller cannot list the same item again after selling it or list without limit.

create table if not exists public.market_refs (
  kind text not null,
  ref text not null,
  base_nok numeric not null check (base_nok > 0),
  lux boolean not null default false,
  primary key (kind, ref)
);
alter table public.market_refs enable row level security;
revoke all on public.market_refs from anon, authenticated;

-- Vehicles, luxury pieces and company equipment of the game, at the game's price in kroner.
insert into public.market_refs (kind, ref, base_nok, lux) values
  ('boat','ferry',140000000,false),('boat','ship_l',180000000,false),('boat','ship_s',42000000,false),('boat','y1',5000000,true),
  ('boat','y2',38000000,true),('boat','y3',320000000,true),('car','c1',1800000,true),('car','c10',3000000,true),('car','c11',2700000,true),
  ('car','c12',9500000,true),('car','c13',8000000,true),('car','c14',7500000,true),('car','c15',1300000,true),('car','c2',4200000,true),
  ('car','c3',4800000,true),('car','c4',4500000,true),('car','c5',38000000,true),('car','c6',42000000,true),('car','c7',3300000,true),
  ('car','c8',3600000,true),('car','c9',4100000,true),('car','car_ev',460000,false),('car','car_lux',880000,false),('car','car_s',340000,false),
  ('car','taxi_cmf',640000,false),('car','taxi_ev',540000,false),('car','taxi_prm',990000,false),('equipment','3dp',45000,false),
  ('equipment','ac',240000,false),('equipment','ads',90000,false),('equipment','aisle',2500000,false),('equipment','arcade',650000,false),
  ('equipment','armory',350000,false),('equipment','atm',2200000,false),('equipment','audio',350000,false),('equipment','av',60000,false),
  ('equipment','bar',600000,false),('equipment','barn',3200000,false),('equipment','barrel',260000,false),('equipment','bays',4500000,false),
  ('equipment','bench',120000,false),('equipment','bev',140000,false),('equipment','bike',90000,false),('equipment','book',150000,false),
  ('equipment','bot',1800000,false),('equipment','bottle',950000,false),('equipment','br',160000,false),('equipment','brew',480000,false),
  ('equipment','cab',650000,false),('equipment','cad',180000,false),('equipment','cage',1200000,false),('equipment','cam',95000,false),
  ('equipment','cams',900000,false),('equipment','cap',80000,false),('equipment','car',8000000,false),('equipment','card',1100000,false),
  ('equipment','cash',35000,false),('equipment','chair',42000000,false),('equipment','chairs',220000,false),('equipment','chill',380000,false),
  ('equipment','cnc',2800000,false),('equipment','cold',400000,false),('equipment','comp',650000,false),('equipment','conv',380000,false),
  ('equipment','cool',140000000,false),('equipment','core',1800000,false),('equipment','crane',3800000,false),('equipment','crm',30000,false),
  ('equipment','ct',3800000,false),('equipment','cutter',220000,false),('equipment','cycle',90000,false),('equipment','dash',30000,false),
  ('equipment','data',2400000,false),('equipment','dc',95000,false),('equipment','decor',2200000,false),('equipment','desk',180000,false),
  ('equipment','desks',150000,false),('equipment','diag',180000,false),('equipment','disp',320000,false),('equipment','dock',260000,false),
  ('equipment','door',120000,false),('equipment','drill',300000,false),('equipment','drone',40000,false),('equipment','drum',320000,false),
  ('equipment','dryer',80000,false),('equipment','dryers',260000,false),('equipment','ed',40000,false),('equipment','edit',260000,false),
  ('equipment','elev',4800000,false),('equipment','espr',95000,false),('equipment','ev',900000,false),('equipment','ex',320000,false),
  ('equipment','excav',2400000,false),('equipment','fact',1800000,false),('equipment','feedb',14000000,false),('equipment','fence',2800000,false),
  ('equipment','ferm',520000,false),('equipment','fit',120000,false),('equipment','fork',650000,false),('equipment','forklift',380000,false),
  ('equipment','forms',450000,false),('equipment','fridge',90000,false),('equipment','fry',90000,false),('equipment','fx',220000,false),
  ('equipment','gaming',4800000,false),('equipment','gear',95000,false),('equipment','gen',120000,false),('equipment','grid',28000000,false),
  ('equipment','groom',2800000,false),('equipment','hall',620000000,false),('equipment','hangar',28000000,false),('equipment','hdc',240000,false),
  ('equipment','hood',120000,false),('equipment','htrade',280000,false),('equipment','hyd',900000,false),('equipment','ice',450000,false),
  ('equipment','ilift',38000000,false),('equipment','inv',120000,false),('equipment','iron',140000,false),('equipment','it',180000,false),
  ('equipment','kiln',260000,false),('equipment','kit',420000,false),('equipment','kitchen',280000,false),('equipment','lab',650000,false),
  ('equipment','lap',36000,false),('equipment','lath',1600000,false),('equipment','led',35000,false),('equipment','lens',60000,false),
  ('equipment','lift',2400000,false),('equipment','lifts',180000,false),('equipment','light',30000,false),('equipment','lights',650000,false),
  ('equipment','lms',120000,false),('equipment','lock',95000,false),('equipment','log',70000,false),('equipment','looms',1200000,false),
  ('equipment','mach',240000,false),('equipment','machine',380000,false),('equipment','mat',25000,false),('equipment','meas',120000,false),
  ('equipment','meter',160000,false),('equipment','mix',90000,false),('equipment','mon',120000,false),('equipment','motion',650000,false),
  ('equipment','nmr',9500000,false),('equipment','nozzle',250000,false),('equipment','oven',160000,false),('equipment','pack',180000,false),
  ('equipment','park',180000,false),('equipment','pens',22000000,false),('equipment','pipes',1200000,false),('equipment','plane',180000000,false),
  ('equipment','plat',800000000,false),('equipment','plow',180000,false),('equipment','pol',30000,false),('equipment','pos',30000,false),
  ('equipment','post',80000,false),('equipment','pots',85000,false),('equipment','power',3200000,false),('equipment','prep',95000,false),
  ('equipment','press',480000,false),('equipment','print',90000,false),('equipment','pump',90000,false),('equipment','racks',850000,false),
  ('equipment','radio',140000,false),('equipment','rec',30000,false),('equipment','rig',120000000,false),('equipment','safe',120000,false),
  ('equipment','sand',280000,false),('equipment','scaff',260000,false),('equipment','scan',90000,false),('equipment','screens',650000,false),
  ('equipment','seis',18000000,false),('equipment','serv',380000,false),('equipment','shelf',95000,false),('equipment','shelv',80000,false),
  ('equipment','shelving',140000,false),('equipment','ship',42000000,false),('equipment','show',350000,false),('equipment','sign',45000,false),
  ('equipment','sim',350000,false),('equipment','site',25000,false),('equipment','slots',1800000,false),('equipment','snow',6500000,false),
  ('equipment','snowm',14000000,false),('equipment','sort',1800000,false),('equipment','sound',260000,false),('equipment','spec',90000,false),
  ('equipment','sports',160000,false),('equipment','spray',350000,false),('equipment','stage',650000,false),('equipment','steam',45000,false),
  ('equipment','steril',180000,false),('equipment','store',380000,false),('equipment','studio',350000,false),('equipment','sw',22000,false),
  ('equipment','tab',30000,false),('equipment','tables',1800000,false),('equipment','tanks',520000,false),('equipment','tg',160000,false),
  ('equipment','tool',220000,false),('equipment','tools',140000,false),('equipment','torch',85000,false),('equipment','tract',3500000,false),
  ('equipment','trailer',380000,false),('equipment','truck',3000000,false),('equipment','turb',14000000,false),('equipment','tv',320000,false),
  ('equipment','van',600000,false),('equipment','vehicles',2400000,false),('equipment','vent',180000,false),('equipment','vines',2600000,false),
  ('equipment','wash',85000,false),('equipment','washers',380000,false),('equipment','web',25000,false),('equipment','weights',220000,false),
  ('equipment','weld',180000,false),('equipment','xray',220000,false),('luxury','a1',120000,true),('luxury','a2',250000,true),
  ('luxury','a3',600000,true),('luxury','a4',400000,true),('luxury','a5',18000000,true),('luxury','w1',380000,true),('luxury','w2',140000,true),
  ('luxury','w3',900000,true),('luxury','w4',1500000,true),('luxury','w5',650000,true),('luxury','w6',2600000,true),('luxury','w7',6500000,true),
  ('luxury','w8',9800000,true),('plane','j1',60000000,true),('plane','j2',160000000,true),('plane','j3',520000000,true),('plane','j4',380000000,true),
  ('plane','j5',900000000,true),('plane','plane_s',180000000,false),('van','bus',3200000,false),('van','ev_van',590000,false),
  ('van','foodtruck',520000,false),('van','minibus',1100000,false),('van','pickup',520000,false),('van','taxi_xl',720000,false),
  ('van','truck_ev',3300000,false),('van','truck_h',2150000,false),('van','truck_s',950000,false),('van','van_box',640000,false),
  ('van','van_l',560000,false),('van','van_s',330000,false)
  on conflict (kind, ref) do update set base_nok = excluded.base_nok, lux = excluded.lux;
insert into public.market_refs (kind, ref, base_nok, lux) select c.kind, c.ref, c.base_nok, c.lux from private.market_catalog() c on conflict (kind, ref) do nothing;

-- Brands, wear, appreciation and exchange-rate drift stay inside three times the game's price (four for luxury pieces).
create or replace function private.market_ref_cap(k text, r text, cur text) returns numeric language sql stable security definer set search_path = '' as $$
  select round(m.base_nok * case when m.lux then 4 else 3 end / private.market_fx(cur), 2) from public.market_refs m where m.kind = k and m.ref = r;
$$;

create or replace function public.market_list(p_item jsonb, p_price numeric, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); k text; t text; l public.market_listings; r_ref text; cap numeric; is_lux boolean; clean jsonb; n numeric; last_seller uuid;
begin
  perform private.require_free(uid, 'trade');
  if p_item is null or jsonb_typeof(p_item) <> 'object' then raise exception 'invalid_item' using errcode = 'P0001'; end if;
  k := p_item ->> 'kind';
  t := btrim(coalesce(p_item ->> 'title', ''));
  r_ref := p_item ->> 'ref';
  if k is null or k not in ('car', 'van', 'plane', 'boat', 'equipment', 'luxury') or char_length(t) not between 2 and 80 then raise exception 'invalid_item' using errcode = 'P0001'; end if;
  if p_price is null or p_price <= 0 or p_price > 1000000000000 or p_currency is null or not private.fx_known(p_currency) then raise exception 'invalid_price' using errcode = 'P0001'; end if;
  cap := private.market_ref_cap(k, r_ref, p_currency);
  if cap is null then raise exception 'invalid_item' using errcode = 'P0001'; end if;
  if p_price > cap then raise exception 'price_outside_market' using errcode = 'P0001'; end if;
  if (select count(*) from public.market_listings where seller_id = uid and status = 'active') >= 12 then raise exception 'too_many_listings' using errcode = 'P0001'; end if;
  if (select count(*) from public.market_listings where seller_id = uid and created_at > now() - interval '24 hours') >= 10 then raise exception 'rate_limited' using errcode = 'P0001'; end if;
  if exists (select 1 from public.market_listings where seller_id = uid and status = 'active' and item ->> 'id' = p_item ->> 'id') then raise exception 'already_listed' using errcode = 'P0001'; end if;
  -- An item this seller sold stays sold unless they bought it back later.
  select m.seller_id into last_seller from public.market_listings m
   where m.status = 'sold' and m.item ->> 'id' = p_item ->> 'id' and (m.seller_id = uid or m.buyer_id = uid) order by m.closed_at desc nulls last limit 1;
  if last_seller = uid then raise exception 'invalid_item' using errcode = 'P0001'; end if;

  select m.lux into is_lux from public.market_refs m where m.kind = k and m.ref = r_ref;
  clean := p_item || jsonb_build_object('lux', is_lux);
  begin n := (p_item ->> 'base')::numeric; exception when others then n := null; end;
  clean := clean || jsonb_build_object('base', round(least(greatest(coalesce(n, cap / 3), 1), cap), 2));
  begin n := (p_item ->> 'cond')::numeric; exception when others then n := null; end;
  if n is not null then clean := clean || jsonb_build_object('cond', least(greatest(n, 0.05), 1)); end if;
  begin n := (p_item ->> 'seen')::numeric; exception when others then n := null; end;
  if n is not null then clean := clean || jsonb_build_object('seen', least(greatest(n, 0.05), 1)); end if;
  begin n := (p_item ->> 'age')::numeric; exception when others then n := null; end;
  clean := clean || jsonb_build_object('age', least(greatest(coalesce(round(n), 0), 0), 100));
  begin n := (p_item ->> 'km')::numeric; exception when others then n := null; end;
  clean := clean || jsonb_build_object('km', least(greatest(coalesce(round(n), 0), 0), 3000000));

  insert into public.market_listings (seller_id, kind, title, item, price, currency) values (uid, k, t, clean, round(p_price, 2), p_currency) returning * into l;
  return private.market_listing_json(l, uid);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Computer-run players answer to the same calls as anyone: friend requests to them wait like any other, search and codes find them,
-- and their names and looks come in the same shapes as players' names and looks.

create or replace function private.bot_ascii(t text) returns text language sql immutable as $$
  select regexp_replace(translate(coalesce(t, ''),
    'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÝýÿÑñÇçŁłŚśŹźŻżĄąĘęĆćŃńĖėŪūŠšŽžČčĐđÆæŒœßŞşĞğİıŌōĀāĒēĪīŘřŤťĎďŇňĚěŮů',
    'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuYyyNnCcLlSsZzZzAaEeCcNnEeUuSsZzCcDdAaOosSsGgIiOoAaEeIiRrTtDdNnEeUu'), '[^A-Za-z0-9]', '', 'g');
$$;

-- A player name in one of the shapes players have: the starting "Player 1A2B", or a chosen user name.
create or replace function private.bot_handle(p_first text, p_last text, p_seed text) returns text language plpgsql immutable as $$
declare f text := private.bot_ascii(p_first); l text := private.bot_ascii(p_last); h int := abs(hashtext('h:' || coalesce(p_seed, ''))); d text; n text;
begin
  if char_length(f) < 2 then f := 'Sam'; end if;
  if char_length(l) < 2 then l := 'Lee'; end if;
  d := (10 + (h / 13) % 90)::text;
  n := case h % 10
    when 0 then 'Player ' || upper(substr(md5('p:' || coalesce(p_seed, '')), 1, 4))
    when 1 then 'Player ' || upper(substr(md5('q:' || coalesce(p_seed, '')), 1, 4))
    when 2 then 'Player ' || upper(substr(md5('r:' || coalesce(p_seed, '')), 1, 4))
    when 3 then initcap(f) || initcap(l)
    when 4 then lower(f) || '_' || lower(l)
    when 5 then initcap(f) || d
    when 6 then lower(left(f, 1)) || lower(l)
    when 7 then initcap(l) || upper(left(f, 1))
    when 8 then lower(f) || lower(left(l, 1)) || d
    else initcap(f) || '_' || initcap(l) end;
  if n not like 'Player %' then
    n := left(n, 16);
    if char_length(n) < 3 then n := n || d; end if;
  end if;
  return n;
end $$;

create or replace function private.bot_name_free(nm text) returns boolean language sql stable security definer set search_path = '' as $$
  select nm is not null and char_length(nm) between 3 and 20 and private.name_problem(nm) is null
     and not exists (select 1 from public.profiles where lower(display_name) = lower(nm) or lower(username) = lower(nm))
     and not exists (select 1 from public.username_reservations where name_key = lower(nm));
$$;

-- Holds the user name like a claimed one, and gives seven in ten a look of their own (the rest keep the default, as many players do).
create or replace function private.bot_dress(uid uuid, nm text) returns void language plpgsql security definer set search_path = '' as $$
declare h int := abs(hashtext('look:' || uid::text));
        outfits text[] := array['shirt','shirt','blazer','denim','flannel','bomber','cableknit','charcoal','camel','clerk','courier','aviator','chalkstripe','evening'];
begin
  if nm ~ '^[A-Za-z][A-Za-z0-9_]{2,15}$' then
    insert into public.username_reservations (name_key, owner_id) values (lower(nm), uid) on conflict (name_key) do nothing;
    update public.profiles set username = nm where id = uid and username is distinct from nm
      and not exists (select 1 from public.profiles q where lower(q.username) = lower(nm) and q.id <> uid);
  end if;
  update public.profiles set avatar_look = case when h % 10 < 3 then null else
      (h % 16)::text || ',' || ((h / 16) % 8)::text || ',' || ((h / 128) % 8)::text || ',' || outfits[1 + (h / 1024) % cardinality(outfits)] end
   where id = uid and avatar_look is null;
end $$;

select private.rewire34('private.bot_create(int)'::regprocedure, array[
  $a$nm := fname || ' ' || lname;$a$, $a$nm := private.bot_handle(fname, lname, 'b' || slot || ':' || k);$a$,
  $a$exit when not exists (select 1 from public.profiles where lower(display_name) = lower(nm)) and private.name_problem(nm) is null;$a$,
  $a$exit when private.bot_name_free(nm);$a$,
  $a$insert into public.bots (user_id, slot) values (uid, slot);$a$,
  $a$insert into public.bots (user_id, slot) values (uid, slot);
  perform private.bot_dress(uid, nm);$a$]);

-- Players the world already runs get names of the same shapes.
do $$
declare r record; nm text; k int; fst text; lst text;
begin
  for r in select p.id, p.display_name from public.profiles p
            where p.is_bot and p.deleted_at is null and position(' ' in p.display_name) > 0 and p.display_name !~ '^Player [0-9A-F]{4}$' order by p.created_at, p.id loop
    fst := split_part(r.display_name, ' ', 1);
    lst := substr(r.display_name, char_length(fst) + 2);
    k := 0;
    loop
      nm := private.bot_handle(fst, lst, r.id::text || ':' || k);
      exit when private.bot_name_free(nm) or k >= 40;
      k := k + 1;
    end loop;
    continue when not private.bot_name_free(nm);
    update public.profiles set display_name = nm where id = r.id;
    perform private.bot_dress(r.id, nm);
  end loop;
end $$;

create or replace function public.send_friend_request(p_target uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); f public.friendships;
begin
  if p_target = uid then raise exception 'cannot_target_self' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.profiles where id = p_target and deleted_at is null) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if private.is_blocked_between(uid, p_target) then raise exception 'blocked' using errcode = 'P0001'; end if;
  select * into f from public.friendships
   where (requester_id = uid and addressee_id = p_target) or (requester_id = p_target and addressee_id = uid);
  if found then
    if f.status = 'accepted' then raise exception 'already_friends' using errcode = 'P0001'; end if;
    if f.requester_id = uid then raise exception 'request_pending' using errcode = 'P0001'; end if;
    update public.friendships set status = 'accepted', responded_at = now() where id = f.id;
    return;
  end if;
  if (select count(*) from public.friendships where requester_id = uid and created_at > now() - interval '1 day') >= 50 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  insert into public.friendships (requester_id, addressee_id) values (uid, p_target);
end $$;

create or replace function public.search_players(p_query text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); q text := trim(coalesce(p_query, '')); pat text; res jsonb;
begin
  if char_length(q) < 2 then return '[]'::jsonb; end if;
  pat := '%' || replace(replace(replace(lower(q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  select coalesce(jsonb_agg(private.profile_json(uid, x.id) order by x.display_name), '[]'::jsonb) into res from (
    select p.id, p.display_name from public.profiles p
     where p.deleted_at is null and p.id <> uid and not private.is_blocked_between(uid, p.id)
       and (lower(p.display_name) like pat or (char_length(private.code_key(q)) = 7 and private.code_key(p.code) = private.code_key(q)))
     order by p.display_name limit 20) x;
  return res;
end $$;

create or replace function public.profile_by_code(p_code text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); target uuid;
begin
  select p.id into target from public.profiles p where private.code_key(p.code) = private.code_key(p_code) and p.deleted_at is null;
  if target is null or (target <> uid and private.is_blocked_between(uid, target)) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  return private.profile_json(uid, target);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Calls for features the app runs on this device for now (supply, startups, the exchange, auctions, clubs, offices, elections,
-- government) are closed to players until the app uses them.

do $$
declare fn record;
begin
  for fn in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = any (array[
               'auctions_snapshot', 'buy_startup_offer', 'call_venture_emergency', 'cancel_auction', 'cancel_exchange_order', 'cancel_startup_offer',
               'cast_ballot', 'club_members', 'clubs_for_company', 'complain_about_supplier', 'conviction_count_of', 'country_overview',
               'delist_from_exchange', 'election_state', 'end_accountant_hire', 'end_supply_as_supplier', 'end_supply_contract', 'exchange_market',
               'hire_accountant_office', 'invest_in_startup', 'join_club', 'leave_club', 'list_accountant_offices', 'list_artifact', 'list_on_exchange',
               'list_startup', 'list_startups', 'my_accountant_hires', 'my_club', 'my_convictions', 'my_exchange_positions', 'my_pending_changes',
               'my_startup_holdings', 'my_supply_contracts', 'my_supply_listings', 'offer_startup_shares', 'open_accountant_office', 'open_venture_meeting',
               'place_bid', 'place_exchange_order', 'rate_accountant_hire', 'record_player_event', 'report_association_standing', 'report_exchange_value',
               'report_startup_closed', 'report_startup_progress', 'report_supply_week', 'save_supply_listing', 'set_country_policy',
               'set_supply_listing_paused', 'set_supply_logo', 'sign_supply_contract', 'stand_for_election', 'startup_offers_for', 'stop_supply_listing',
               'supplier_company_closed', 'supplier_profile', 'supply_listing_orders', 'supply_listings_for_line', 'withdraw_candidacy']) loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn.sig);
  end loop;
end $$;

drop function private.rewire34(regprocedure, text[]);

revoke execute on all functions in schema public from public, anon;
grant execute on function public.create_venture(text, text, numeric, text), public.report_venture_value(uuid, numeric), public.venture_value_history(uuid),
  public.publish_leaderboard(numeric, numeric, int), public.market_list(jsonb, numeric, text), public.send_friend_request(uuid),
  public.search_players(text), public.profile_by_code(text) to authenticated;
