-- Account rules, the administrator role and the world rules.
--
--  1. 18+ confirmation: a profile can only be created with a confirmation. Only a boolean is stored, never an age or a birth date.
--  2. Linking Apple or Google is for profile memory only (progress follows the account; it is not how friends are found) and pays a
--     one-time gold reward per person, granted here and never by a client write. A guest holds no server rows (every shared feature needs
--     a profile), so merging a guest into an account moves nothing on the server; the app decides what its progress sends.
--  3. Administrator: the `admins` table is bound to the account id. A one-time code is redeemed by `redeem_admin_code`, which compares a
--     hash held in `admin_codes`. No code lives in the repository or in the app.
--  4. World rules (`world_rules`) with hard limits only a migration can move, changed through admin RPCs that write one audit row each,
--     and the confirmations queue that the government engine's "president proposes, administrator confirms" rule needs.
--
-- OWNER STEP (SQL editor of the Supabase dashboard, once per code; the code never goes into the repository or the app). Use a long random
-- code (24 or more characters); it is spent by the first account that redeems it and expires after seven days:
--
--   insert into public.admin_codes (code_hash) values (encode(extensions.digest(upper(trim('YOUR-LONG-RANDOM-CODE')), 'sha256'), 'hex'));
--
-- The table has no client access at all; only the dashboard and the redeem function read it.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Adult confirmation
-- ---------------------------------------------------------------------------------------------------------------------
-- Not in the client column grants of 0001: only the functions below set it. Profiles made before this migration start unconfirmed and
-- cannot use shared features until the owner of the profile confirms.
alter table public.profiles add column adult_confirmed boolean not null default false;

create or replace function private.require_player() returns uuid language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  if not exists (select 1 from public.profiles where id = uid and deleted_at is null and adult_confirmed) then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  return uid;
end $$;

-- Replaces ensure_profile(). Creates the caller's profile, or confirms an older one. Without the confirmation nothing is created.
drop function public.ensure_profile();
create function public.ensure_profile(p_adult_confirmed boolean default false) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); anon boolean; p public.profiles; had boolean;
begin
  select coalesce(is_anonymous, false) into anon from auth.users where id = uid;
  if anon then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  select * into p from public.profiles where id = uid and deleted_at is null;
  had := found;
  if had and p.adult_confirmed then return private.profile_json(uid, uid); end if;
  if p_adult_confirmed is distinct from true then raise exception 'adult_required' using errcode = 'P0001'; end if;
  if not had then
    insert into public.profiles (id, display_name, adult_confirmed) values (uid, 'Player ' || upper(substr(md5(uid::text), 1, 4)), true)
      on conflict (id) do nothing;
  end if;
  update public.profiles set adult_confirmed = true where id = uid and deleted_at is null;
  return private.profile_json(uid, uid);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Link reward
-- ---------------------------------------------------------------------------------------------------------------------
-- One row per Apple or Google identity. The key is a hash of the provider's own user id and it survives deleting the account, so
-- deleting and re-creating an account with the same Apple or Google id cannot pay the reward twice. user_id is unique while it exists.
create table public.link_reward_claims (
  identity_hash text primary key,
  user_id uuid unique references auth.users (id) on delete set null,
  provider text not null check (provider in ('apple', 'google')),
  gold int not null check (gold > 0),
  claimed_at timestamptz not null default now()
);
alter table public.link_reward_claims enable row level security;
revoke all on public.link_reward_claims from anon, authenticated;

create function private.link_reward_gold() returns int language sql immutable as $$ select 100; $$;

-- Pays the reward once. Needs a real profile (so the 18+ confirmation is done) and a linked Apple or Google identity.
create function public.claim_link_reward() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); idn record; h text; g int := private.link_reward_gold();
begin
  select i.provider, coalesce(i.provider_id, i.identity_data ->> 'sub') as subject into idn
    from auth.identities i where i.user_id = uid and i.provider in ('apple', 'google') order by i.created_at limit 1;
  if not found then raise exception 'no_linked_account' using errcode = 'P0001'; end if;
  if idn.subject is null then raise exception 'no_linked_account' using errcode = 'P0001'; end if;
  h := encode(extensions.digest(idn.provider || ':' || idn.subject, 'sha256'), 'hex');
  begin
    insert into public.link_reward_claims (identity_hash, user_id, provider, gold) values (h, uid, idn.provider, g);
  exception when unique_violation then
    return jsonb_build_object('granted', false, 'gold', 0, 'reason', 'already_claimed');
  end;
  perform private.gold_credit(uid, g, 'link_reward', idn.provider);
  return jsonb_build_object('granted', true, 'gold', g, 'reason', 'granted');
end $$;

-- What the app needs to know about the signed-in account, in one call.
create function public.account_status() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); anon boolean; p public.profiles; had boolean;
begin
  select coalesce(is_anonymous, false) into anon from auth.users where id = uid;
  if anon then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  select * into p from public.profiles where id = uid and deleted_at is null;
  had := found;
  return jsonb_build_object(
    'hasProfile', had,
    'adultConfirmed', had and p.adult_confirmed,
    'isAdmin', had and p.adult_confirmed and private.is_admin(uid),
    'linkRewardGold', private.link_reward_gold(),
    'linkRewardClaimed', exists (select 1 from public.link_reward_claims where user_id = uid));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Administrators
-- ---------------------------------------------------------------------------------------------------------------------
create table public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  granted_at timestamptz not null default now()
);

-- One row per code. The hash is the only thing kept; a code works once and for seven days.
create table public.admin_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  redeemed_by uuid references auth.users (id) on delete set null,
  redeemed_at timestamptz
);

-- Every redeem attempt, so guessing is slowed down: five tries an hour per account and thirty an hour in all.
create table public.admin_code_attempts (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users (id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index admin_code_attempts_recent on public.admin_code_attempts (attempted_at);

-- The audit log of everything an administrator does. Append only: no update, no delete, not even by a function.
create table public.admin_audit (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id uuid references auth.users (id) on delete set null,
  action text not null check (char_length(action) between 1 and 40),
  target text not null default '' check (char_length(target) <= 80),
  before_value jsonb,
  after_value jsonb,
  reason text not null default '' check (char_length(reason) <= 300)
);
create function private.audit_is_append_only() returns trigger language plpgsql as $$
begin raise exception 'audit_is_append_only' using errcode = 'P0001'; end $$;
create trigger admin_audit_no_change before update or delete on public.admin_audit for each row execute function private.audit_is_append_only();
create trigger admin_audit_no_truncate before truncate on public.admin_audit for each statement execute function private.audit_is_append_only();

alter table public.admins enable row level security;
alter table public.admin_codes enable row level security;
alter table public.admin_code_attempts enable row level security;
alter table public.admin_audit enable row level security;
revoke all on public.admins, public.admin_codes, public.admin_code_attempts, public.admin_audit from anon, authenticated;

create function private.is_admin(uid uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = uid);
$$;

create function private.require_admin() returns uuid language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if not private.is_admin(uid) then raise exception 'not_admin' using errcode = 'P0001'; end if;
  return uid;
end $$;

create function private.audit(actor uuid, act text, target text, before_v jsonb, after_v jsonb, why text) returns void language sql security definer set search_path = '' as $$
  insert into public.admin_audit (actor_id, action, target, before_value, after_value, reason) values (actor, act, coalesce(target, ''), before_v, after_v, coalesce(why, ''));
$$;

-- A wrong code is an answer, not an error, so the attempt row is kept. Returns {ok, reason} with reason in
-- granted, already_admin, invalid, locked.
create function public.redeem_admin_code(p_code text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); code text := upper(trim(coalesce(p_code, ''))); h text; c public.admin_codes;
begin
  if private.is_admin(uid) then return jsonb_build_object('ok', true, 'reason', 'already_admin'); end if;
  if (select count(*) from public.admin_code_attempts where user_id = uid and attempted_at > now() - interval '1 hour') >= 5
     or (select count(*) from public.admin_code_attempts where attempted_at > now() - interval '1 hour') >= 30 then
    return jsonb_build_object('ok', false, 'reason', 'locked');
  end if;
  insert into public.admin_code_attempts (user_id) values (uid);
  if char_length(code) < 12 or char_length(code) > 128 then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  h := encode(extensions.digest(code, 'sha256'), 'hex');
  select * into c from public.admin_codes where code_hash = h and redeemed_at is null and expires_at > now() for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  update public.admin_codes set redeemed_by = uid, redeemed_at = now() where id = c.id;
  insert into public.admins (user_id) values (uid);
  perform private.audit(uid, 'admin_granted', uid::text, null, jsonb_build_object('code', c.id), 'one-time code redeemed');
  return jsonb_build_object('ok', true, 'reason', 'granted');
end $$;

-- An administrator does not stand for president (the engine keeps the two roles apart as well).
create or replace function private.may_stand(uid uuid, cc text) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = uid and deleted_at is null and not is_simulated and country_code = cc and created_at < now() - private.weeks(8))
     and not private.is_barred(uid, 'stand') and not private.is_admin(uid);
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. World rules
-- ---------------------------------------------------------------------------------------------------------------------
-- `value` moves only inside [min_value, max_value] and only through admin_set_rule. The hard limits are fixed here: no administrator
-- can raise printing past 10% of the supply in one go, take a band to nothing, or lift a tax beyond its ceiling.
create table public.world_rules (
  key text primary key,
  grp text not null check (grp in ('printing', 'taxes', 'bands', 'electricity', 'funding')),
  label text not null,
  unit text not null check (unit in ('share', 'weeks', 'count', 'factor')),
  value numeric not null,
  default_value numeric not null,
  min_value numeric not null,
  max_value numeric not null,
  sort int not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  constraint rule_inside_limits check (min_value <= max_value and value between min_value and max_value and default_value between min_value and max_value)
);
alter table public.world_rules enable row level security;
revoke all on public.world_rules from anon, authenticated;

insert into public.world_rules (key, grp, label, unit, value, default_value, min_value, max_value, sort) values
  ('print.single_limit',    'printing',    'Largest single printing',           'share',  0.05, 0.05, 0.01,  0.10, 10),
  ('print.window_limit',    'printing',    'Printing allowed in one window',    'share',  0.15, 0.15, 0.03,  0.30, 20),
  ('print.window_weeks',    'printing',    'Weeks in the printing window',      'weeks',  12,   12,   4,     26,   30),
  ('tax.transfer_max',      'taxes',       'Highest transfer tax',              'share',  0.05, 0.05, 0.01,  0.10, 10),
  ('tax.gains_min',         'taxes',       'Lowest gains tax',                  'share',  0.05, 0.05, 0,     0.15, 20),
  ('tax.gains_max',         'taxes',       'Highest gains tax',                 'share',  0.40, 0.40, 0.20,  0.60, 30),
  ('tax.step',              'taxes',       'Largest move of a rate at a time',  'share',  0.01, 0.01, 0.005, 0.03, 40),
  ('tax.gap_weeks',         'taxes',       'Weeks between rate changes',        'weeks',  7,    7,    1,     26,   50),
  ('band.exchange_low',     'bands',       'Exchange price, lowest vs value',   'factor', 0.75, 0.75, 0.50,  0.95, 10),
  ('band.exchange_high',    'bands',       'Exchange price, highest vs value',  'factor', 1.25, 1.25, 1.05,  2.00, 20),
  ('band.startup_low',      'bands',       'Startup resale, lowest vs value',   'factor', 0.80, 0.80, 0.50,  0.95, 30),
  ('band.startup_high',     'bands',       'Startup resale, highest vs value',  'factor', 1.25, 1.25, 1.05,  2.00, 40),
  ('band.venture_low',      'bands',       'Venture stake, lowest vs fair',     'factor', 0.70, 0.70, 0.40,  0.95, 50),
  ('band.venture_high',     'bands',       'Venture stake, highest vs fair',    'factor', 1.50, 1.50, 1.05,  2.50, 60),
  ('power.band_low',        'electricity', 'Electricity price index, floor',    'factor', 0.60, 0.60, 0.30,  0.90, 10),
  ('power.band_high',       'electricity', 'Electricity price index, ceiling',  'factor', 1.80, 1.80, 1.20,  3.00, 20),
  ('support.percent_max',   'funding',     'Largest support share of sales',    'share',  0.10, 0.10, 0.02,  0.20, 10),
  ('support.weeks_max',     'funding',     'Longest support run',               'weeks',  8,    8,    1,     16,   20),
  ('support.budget_share',  'funding',     'Weekly budget, share of treasury',  'share',  0.05, 0.05, 0.01,  0.10, 30),
  ('support.max_open',      'funding',     'Supports open at once',             'count',  2,    2,    1,     5,    40),
  ('support.account_share', 'funding',     'One account, share of a budget',    'share',  0.25, 0.25, 0.05,  0.50, 50);

create function private.rule_num(k text) returns numeric language plpgsql stable security definer set search_path = '' as $$
declare v numeric;
begin
  select value into v from public.world_rules where key = k;
  if v is null then raise exception 'unknown_rule' using errcode = 'P0001'; end if;
  return v;
end $$;

-- Rules that must hold together after any change.
create function private.rules_consistent() returns boolean language sql stable security definer set search_path = '' as $$
  select private.rule_num('print.single_limit') <= private.rule_num('print.window_limit')
     and private.rule_num('tax.gains_min') < private.rule_num('tax.gains_max')
     and private.rule_num('band.exchange_low') < 1 and private.rule_num('band.exchange_high') > 1
     and private.rule_num('band.startup_low') < 1 and private.rule_num('band.startup_high') > 1
     and private.rule_num('band.venture_low') < 1 and private.rule_num('band.venture_high') > 1
     and private.rule_num('power.band_low') < 1 and private.rule_num('power.band_high') > 1;
$$;

-- What a player's game may read: every rule as one object.
create function public.world_rules_snapshot() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  return coalesce((select jsonb_object_agg(key, value) from public.world_rules), '{}'::jsonb);
end $$;

-- Bands and tax limits now read the rules. The earlier functions are re-issued from their own definitions with the constants swapped,
-- so nothing else in them changes. Each replacement must find its text or the migration stops.
create function private.rewire(fn regprocedure, pairs text[]) returns void language plpgsql as $$
declare d text := pg_get_functiondef(fn); n text; i int;
begin
  for i in 1..cardinality(pairs) by 2 loop
    n := replace(d, pairs[i], pairs[i + 1]);
    if n = d then raise exception 'rewire: text not found in %: %', fn, pairs[i]; end if;
    d := n;
  end loop;
  execute d;
end $$;

select private.rewire('public.offer_startup_shares(uuid, numeric, numeric)'::regprocedure, array[
  $a$fair * 0.8 - 0.005$a$, $a$fair * private.rule_num('band.startup_low') - 0.005$a$,
  $a$fair * 1.25 + 0.005$a$, $a$fair * private.rule_num('band.startup_high') + 0.005$a$]);
select private.rewire('public.buy_startup_offer(uuid, text)'::regprocedure, array[
  $a$fair * 0.8 - 0.005$a$, $a$fair * private.rule_num('band.startup_low') - 0.005$a$,
  $a$fair * 1.25 + 0.005$a$, $a$fair * private.rule_num('band.startup_high') + 0.005$a$]);
select private.rewire('public.place_exchange_order(uuid, public.exchange_side, bigint, numeric, text)'::regprocedure, array[
  $a$p_price < nav * 0.75 or p_price > nav * 1.25$a$,
  $a$p_price < nav * private.rule_num('band.exchange_low') or p_price > nav * private.rule_num('band.exchange_high')$a$]);
select private.rewire('public.exchange_market()'::regprocedure, array[
  $a$private.exchange_nav(l) * 0.75$a$, $a$private.exchange_nav(l) * private.rule_num('band.exchange_low')$a$,
  $a$private.exchange_nav(l) * 1.25$a$, $a$private.exchange_nav(l) * private.rule_num('band.exchange_high')$a$]);
select private.rewire('private.jv_invite_check(public.ventures, uuid, uuid, numeric, numeric)'::regprocedure, array[
  $a$price < fair * 0.7 or price > fair * 1.5$a$,
  $a$price < fair * private.rule_num('band.venture_low') or price > fair * private.rule_num('band.venture_high')$a$]);

drop function private.rewire(regprocedure, text[]);

-- ---------------------------------------------------------------------------------------------------------------------
-- Confirmations queue (the engine's `GovPending`): a president's change and an election result wait here for an administrator.
-- The price-support and promises kinds are queued by the government features that propose them; deciding one records the decision.
-- ---------------------------------------------------------------------------------------------------------------------
create type public.confirmation_kind as enum ('policy', 'price_support', 'promises', 'election_result');
create type public.confirmation_status as enum ('open', 'confirmed', 'rejected');

create table public.gov_confirmations (
  id uuid primary key default gen_random_uuid(),
  kind public.confirmation_kind not null,
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  proposer_id uuid references public.profiles (id) on delete set null,
  summary text not null check (char_length(summary) between 1 and 300),
  payload jsonb not null default '{}'::jsonb,
  status public.confirmation_status not null default 'open',
  created_at timestamptz not null default now(),
  decided_by uuid references auth.users (id) on delete set null,
  decided_at timestamptz,
  decision_note text not null default '' check (char_length(decision_note) <= 300)
);
create unique index gov_confirmations_one_policy on public.gov_confirmations (country_code) where kind = 'policy' and status = 'open';
create unique index gov_confirmations_one_result on public.gov_confirmations (country_code) where kind = 'election_result' and status = 'open';
create index gov_confirmations_open on public.gov_confirmations (created_at) where status = 'open';
alter table public.gov_confirmations enable row level security;
revoke all on public.gov_confirmations from anon, authenticated;

-- The president's change now waits for an administrator (it used to apply at once). Same checks as 0010, with the limits from the rules.
create or replace function public.set_country_policy(p_country text, p_transfer_tax numeric, p_gains_tax numeric) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); cur public.country_policy; t0 numeric := private.transfer_tax_rate(p_country); g0 numeric := private.gains_tax_rate(p_country);
        cid uuid;
begin
  if not private.holds_office(uid, p_country) or (select country_code from public.profiles where id = uid) <> p_country then raise exception 'not_in_office' using errcode = 'P0001'; end if;
  select * into cur from public.country_policy where country_code = p_country;
  if cur.updated_at is not null and now() - cur.updated_at < private.weeks(private.rule_num('tax.gap_weeks')::int) then raise exception 'too_soon' using errcode = 'P0001'; end if;
  if p_transfer_tax not between 0 and private.rule_num('tax.transfer_max')
     or p_gains_tax not between private.rule_num('tax.gains_min') and private.rule_num('tax.gains_max') then raise exception 'outside_limits' using errcode = 'P0001'; end if;
  if abs(p_transfer_tax - t0) > private.rule_num('tax.step') + 1e-9 or abs(p_gains_tax - g0) > private.rule_num('tax.step') + 1e-9 then raise exception 'change_too_large' using errcode = 'P0001'; end if;
  if exists (select 1 from public.gov_confirmations where country_code = p_country and kind = 'policy' and status = 'open') then raise exception 'already_pending' using errcode = 'P0001'; end if;
  insert into public.gov_confirmations (kind, country_code, proposer_id, summary, payload)
    values ('policy', p_country, uid, 'Transfer tax ' || round(p_transfer_tax * 100, 1) || '%, gains tax ' || round(p_gains_tax * 100, 1) || '%',
            jsonb_build_object('transferTax', p_transfer_tax, 'gainsTax', p_gains_tax)) returning id into cid;
  return jsonb_build_object('status', 'pending', 'id', cid, 'transferTax', p_transfer_tax, 'gainsTax', p_gains_tax);
end $$;

-- A president's own recent proposals, so the app can say "waiting for an administrator".
create function public.my_pending_changes() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'summary', summary, 'status', status, 'at', created_at, 'note', decision_note) order by created_at desc)
    from (select * from public.gov_confirmations where proposer_id = uid and kind <> 'election_result' order by created_at desc limit 10) x), '[]'::jsonb);
end $$;

-- 0011's cycle runner with one change: a winner is queued for confirmation instead of taking the office at once. The office and the
-- winner column are set when an administrator confirms.
create or replace function private.run_election_cycle() returns int language plpgsql security definer set search_path = '' as $$
declare e public.elections; cc record; n int := 0; win uuid;
begin
  for e in select * from public.elections where status <> 'closed' for update loop
    if e.status = 'nomination' and now() >= e.nominate_until then
      if (select count(*) from public.election_candidates where election_id = e.id) = 0 then
        update public.elections set status = 'closed' where id = e.id;
      else
        update public.elections set status = 'voting' where id = e.id;
      end if;
      n := n + 1;
    elsif e.status = 'voting' and now() >= e.voting_until then
      select c.candidate_id into win from public.election_candidates c
       where c.election_id = e.id and private.may_stand(c.candidate_id, e.country_code)
       order by (select count(*) from public.election_ballots b where b.election_id = e.id and b.candidate_id = c.candidate_id) desc, c.nominated_at limit 1;
      if win is not null and (select count(*) from public.election_ballots where election_id = e.id) = 0 then win := null; end if;
      update public.elections set status = 'closed' where id = e.id;
      if win is not null then
        insert into public.gov_confirmations (kind, country_code, proposer_id, summary, payload)
          values ('election_result', e.country_code, win, 'Election result: ' || private.display_name(win) || ' wins the presidency of ' || e.country_code,
                  jsonb_build_object('election', e.id, 'winner', win));
      end if;
      n := n + 1;
    end if;
  end loop;
  for cc in select distinct p.country_code from public.profiles p where p.deleted_at is null and not p.is_simulated loop
    continue when exists (select 1 from public.elections where country_code = cc.country_code and status <> 'closed');
    continue when exists (select 1 from public.country_offices where country_code = cc.country_code and term_end > now() and holder_id is not null);
    continue when exists (select 1 from public.elections where country_code = cc.country_code and status = 'closed' and created_at > now() - private.weeks(2));
    continue when exists (select 1 from public.gov_confirmations where country_code = cc.country_code and kind = 'election_result' and status = 'open');
    insert into public.elections (country_code, nominate_until, voting_until) values (cc.country_code, now() + private.weeks(7), now() + private.weeks(14));
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Admin functions (each one checks the caller against the admins table itself; there is no client flag)
-- ---------------------------------------------------------------------------------------------------------------------
create function private.audit_json(p_before bigint, p_limit int) returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'at', at, 'actor', coalesce(private.display_name(actor_id), 'system'), 'action', action,
         'target', target, 'before', before_value #>> '{}', 'after', after_value #>> '{}', 'reason', reason) order by id desc), '[]'::jsonb)
    from (select * from public.admin_audit where p_before is null or id < p_before order by id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) a;
$$;

create function private.confirmations_json(p_status public.confirmation_status) returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'country', country_code, 'proposer', coalesce(private.display_name(proposer_id), 'Unknown'),
         'summary', summary, 'at', created_at, 'status', status, 'note', decision_note) order by created_at desc), '[]'::jsonb)
    from (select * from public.gov_confirmations where status = p_status order by created_at desc limit 50) c;
$$;

-- Everything the Admin screen shows.
create function public.admin_overview() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin();
begin
  return jsonb_build_object(
    'rules', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'group', grp, 'label', label, 'unit', unit, 'value', value, 'default', default_value,
                'min', min_value, 'max', max_value) order by grp, sort) from public.world_rules), '[]'::jsonb),
    'confirmations', private.confirmations_json('open'),
    'audit', private.audit_json(null, 50));
end $$;

create function public.admin_audit_page(p_before bigint default null, p_limit int default 50) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin();
begin
  return private.audit_json(p_before, p_limit);
end $$;

-- Changes one rule inside its hard limits, with a reason, and writes the audit row in the same transaction.
create function public.admin_set_rule(p_key text, p_value numeric, p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin(); r public.world_rules; why text := trim(coalesce(p_reason, ''));
begin
  if char_length(why) < 3 then raise exception 'reason_required' using errcode = 'P0001'; end if;
  select * into r from public.world_rules where key = p_key for update;
  if not found then raise exception 'unknown_rule' using errcode = 'P0001'; end if;
  if p_value is null or p_value < r.min_value or p_value > r.max_value then raise exception 'outside_hard_limits' using errcode = 'P0001'; end if;
  if p_value = r.value then return jsonb_build_object('key', r.key, 'value', r.value); end if;
  update public.world_rules set value = p_value, updated_at = now(), updated_by = uid where key = p_key;
  if not private.rules_consistent() then raise exception 'rules_conflict' using errcode = 'P0001'; end if;
  perform private.audit(uid, 'rule_change', p_key, to_jsonb(r.value), to_jsonb(p_value), why);
  return jsonb_build_object('key', p_key, 'value', p_value);
end $$;

-- Confirms or rejects one waiting change. The administrator cannot decide a change they proposed themselves. A confirmed policy change
-- is checked again against the office and the limits as they stand now; an election result installs the winner for a twelve-week term.
create function public.admin_decide(p_id uuid, p_approve boolean, p_reason text default '') returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin(); c public.gov_confirmations; t numeric; g numeric; t0 numeric; g0 numeric; cur public.country_policy; w uuid;
        why text := trim(coalesce(p_reason, '')); verdict text := case when p_approve then 'confirmed' else 'rejected' end;
begin
  select * into c from public.gov_confirmations where id = p_id and status = 'open' for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if c.proposer_id = uid then raise exception 'own_proposal' using errcode = 'P0001'; end if;
  if not p_approve and char_length(why) < 3 then raise exception 'reason_required' using errcode = 'P0001'; end if;
  if p_approve then
    if c.kind = 'policy' then
      t := (c.payload ->> 'transferTax')::numeric; g := (c.payload ->> 'gainsTax')::numeric;
      t0 := private.transfer_tax_rate(c.country_code); g0 := private.gains_tax_rate(c.country_code);
      if not private.holds_office(c.proposer_id, c.country_code) then raise exception 'not_in_office' using errcode = 'P0001'; end if;
      if t not between 0 and private.rule_num('tax.transfer_max') or g not between private.rule_num('tax.gains_min') and private.rule_num('tax.gains_max') then raise exception 'outside_limits' using errcode = 'P0001'; end if;
      if abs(t - t0) > private.rule_num('tax.step') + 1e-9 or abs(g - g0) > private.rule_num('tax.step') + 1e-9 then raise exception 'change_too_large' using errcode = 'P0001'; end if;
      select * into cur from public.country_policy where country_code = c.country_code;
      if cur.updated_at is not null and now() - cur.updated_at < private.weeks(private.rule_num('tax.gap_weeks')::int) then raise exception 'too_soon' using errcode = 'P0001'; end if;
      insert into public.country_policy (country_code, transfer_tax, gains_tax, updated_by) values (c.country_code, t, g, c.proposer_id)
        on conflict (country_code) do update set transfer_tax = excluded.transfer_tax, gains_tax = excluded.gains_tax, updated_at = now(), updated_by = excluded.updated_by;
    elsif c.kind = 'election_result' then
      w := (c.payload ->> 'winner')::uuid;
      if not private.may_stand(w, c.country_code) then raise exception 'not_eligible' using errcode = 'P0001'; end if;
      update public.elections set winner_id = w where id = (c.payload ->> 'election')::uuid;
      insert into public.country_offices (country_code, office, holder_id, term_start, term_end) values (c.country_code, 'president', w, now(), now() + private.weeks(12))
        on conflict (country_code, office) do update set holder_id = excluded.holder_id, term_start = excluded.term_start, term_end = excluded.term_end;
    end if;
  end if;
  update public.gov_confirmations set status = verdict::public.confirmation_status, decided_by = uid, decided_at = now(), decision_note = left(why, 300) where id = c.id;
  perform private.audit(uid, case when p_approve then 'confirm' else 'reject' end, c.kind::text || ':' || c.country_code,
                        jsonb_build_object('summary', c.summary), jsonb_build_object('status', verdict), why);
  return jsonb_build_object('id', c.id, 'status', verdict);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Execute rights
-- ---------------------------------------------------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on function public.ensure_profile(boolean), public.claim_link_reward(), public.account_status(), public.redeem_admin_code(text),
  public.world_rules_snapshot(), public.my_pending_changes(), public.admin_overview(), public.admin_audit_page(bigint, int),
  public.admin_set_rule(text, numeric, text), public.admin_decide(uuid, boolean, text) to authenticated;
