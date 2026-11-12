alter table public.push_outbox drop constraint if exists push_outbox_category_check;
alter table public.push_outbox add constraint push_outbox_category_check check (category in ('auction', 'supplier', 'gift', 'race', 'daily', 'board'));
alter table public.device_tokens alter column categories set default '{auction,supplier,gift,race,daily,board}';
update public.device_tokens set categories = array_append(categories, 'board') where not ('board' = any (categories));

alter type public.venture_kind add value if not exists 'policy';
alter type public.venture_kind add value if not exists 'setting';

alter table public.ventures add column if not exists dividend_policy text not null default 'none' check (dividend_policy in ('none', 'low', 'mid', 'high'));
alter table public.ventures add column if not exists settings jsonb not null default '{}'::jsonb;
alter table public.venture_items add column if not exists proposed_by uuid references public.profiles (id) on delete set null;
alter table public.venture_items add column if not exists created_at timestamptz not null default clock_timestamp();

create type public.venture_buyback_status as enum ('pending', 'accepted', 'declined', 'withdrawn', 'expired');

create table public.venture_buybacks (
  id uuid primary key default gen_random_uuid(),
  venture_id uuid not null references public.ventures (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  shares int not null check (shares > 0),
  price numeric(18, 2) not null check (price > 0),
  fair numeric(18, 2) not null,
  status public.venture_buyback_status not null default 'pending',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  answered_at timestamptz,
  proposed_by uuid not null references public.profiles (id) on delete cascade,
  constraint venture_buyback_two_parties check (buyer_id <> seller_id and proposed_by in (buyer_id, seller_id))
);
create unique index venture_buyback_pending on public.venture_buybacks (venture_id, seller_id) where status = 'pending';
create index venture_buybacks_seller on public.venture_buybacks (seller_id) where status = 'pending';

alter table public.venture_buybacks enable row level security;
revoke all on public.venture_buybacks from anon, authenticated;
grant select on public.venture_buybacks to authenticated;
create policy venture_buybacks_party on public.venture_buybacks for select to authenticated using (buyer_id = auth.uid() or seller_id = auth.uid());

create function private.jv_is_bot(uid uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select is_bot from public.profiles where id = uid), false);
$$;

-- The regular board meeting is Monday 00:00 UTC; an item needs a day's notice, so a late one waits a week more.
create function private.jv_next_meeting(at timestamptz) returns timestamptz language sql stable as $$
  select (date_trunc('week', (at + interval '1 day') at time zone 'utc') + interval '7 days') at time zone 'utc';
$$;

create or replace function private.jv_invite_check(v public.ventures, inviter uuid, invitee uuid, pct numeric, price numeric) returns numeric language plpgsql stable security definer set search_path = '' as $$
declare fair numeric; partners int; chair_after numeric; bot boolean := private.jv_is_bot(invitee); top numeric := private.rule_num('band.venture_high');
begin
  if not exists (select 1 from public.profiles where id = invitee and deleted_at is null) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if not bot and not private.are_friends(inviter, invitee) then raise exception 'not_friends' using errcode = 'P0001'; end if;
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
  if bot then top := least(1, top); end if;
  if price < fair * private.rule_num('band.venture_low') - 0.005 or price > fair * top + 0.005 then raise exception 'outside_band' using errcode = 'P0001'; end if;
  return fair;
end $$;

create or replace function private.jv_json(v public.ventures, viewer uuid) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'chairID', v.chair_id, 'chairName', private.display_name(v.chair_id), 'companyKey', v.company_key, 'name', v.name,
    'currency', v.currency, 'value', v.value, 'totalShares', private.jv_total_shares(v.id), 'dissolved', v.dissolved_at is not null,
    'isChair', v.chair_id = viewer, 'dividendPolicy', v.dividend_policy, 'settings', v.settings, 'nextMeetingAt', private.jv_next_meeting(now()),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('memberID', p.member_id, 'name', private.display_name(p.member_id), 'shares', p.shares,
         'percent', round(100.0 * p.shares / nullif(private.jv_total_shares(v.id), 0), 3), 'joinedAt', p.joined_at, 'lockUntil', p.lock_until) order by p.joined_at)
       from public.venture_partners p where p.venture_id = v.id), '[]'::jsonb));
$$;

create function private.jv_item_title(kind text, params jsonb) returns text language sql immutable as $$
  select case kind
    when 'policy' then 'Dividend policy: ' || (case params ->> 'policy' when 'none' then 'reinvest everything' when 'low' then '25% of profit'
                                                 when 'mid' then '50% of profit' else '80% of profit' end)
    when 'setting' then coalesce(nullif(left(params ->> 'label', 120), ''), 'Change a group setting')
    when 'dividend' then 'Pay a dividend'
    when 'capital' then 'Call capital from the owners'
    when 'price' then 'Change prices'
    when 'hire' then 'Hire a manager'
    when 'sell' then 'Sell the company'
    when 'partner' then 'Bring in a new partner'
    else 'Dissolve the joint venture' end;
$$;

create function private.jv_check_item(v public.ventures, kind text, params jsonb) returns void language plpgsql stable security definer set search_path = '' as $$
declare amt numeric;
begin
  if kind is null or kind not in ('dividend', 'price', 'hire', 'sell', 'partner', 'capital', 'dissolve', 'policy', 'setting') then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
  if kind in ('dividend', 'capital') then
    amt := (params ->> 'amount')::numeric;
    if amt is null or amt <= 0 or amt > 1e12 then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
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

create function private.jv_apply_change(vid uuid, kind text, params jsonb) returns void language plpgsql security definer set search_path = '' as $$
begin
  if kind = 'policy' then
    update public.ventures set dividend_policy = params ->> 'policy' where id = vid;
  elsif kind = 'setting' then
    update public.ventures set settings = settings || jsonb_build_object(params ->> 'key', params -> 'value') where id = vid;
  end if;
end $$;

create or replace function private.jv_open_meeting(v public.ventures, caller uuid, planned boolean, items jsonb, profitable boolean, cash_tight boolean) returns uuid
language plpgsql security definer set search_path = '' as $$
declare mid uuid; it jsonb; k text; iid uuid;
begin
  if jsonb_typeof(items) <> 'array' or jsonb_array_length(items) not between 1 and 5 then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
  if (select count(*) from public.venture_partners where venture_id = v.id) < 2 then raise exception 'no_partners' using errcode = 'P0001'; end if;
  for it in select * from jsonb_array_elements(items) loop
    perform private.jv_check_item(v, it ->> 'kind', coalesce(it -> 'params', '{}'::jsonb));
  end loop;
  if planned then
    select id into mid from public.venture_meetings where venture_id = v.id and venture_meetings.planned and closed_at is null and deadline > now() order by deadline limit 1;
    if mid is null then
      insert into public.venture_meetings (venture_id, planned, called_by, deadline, profitable, cash_tight)
        values (v.id, true, caller, private.jv_next_meeting(now()), profitable, cash_tight) returning id into mid;
    end if;
    if (select count(*) from public.venture_items where meeting_id = mid) + jsonb_array_length(items) > 8 then raise exception 'agenda_full' using errcode = 'P0001'; end if;
  else
    if exists (select 1 from public.venture_meetings where venture_id = v.id and not venture_meetings.planned and closed_at is null) then
      raise exception 'meeting_open' using errcode = 'P0001';
    end if;
    insert into public.venture_meetings (venture_id, planned, called_by, deadline, profitable, cash_tight)
      values (v.id, false, caller, now() + interval '24 hours', profitable, cash_tight) returning id into mid;
  end if;
  for it in select * from jsonb_array_elements(items) loop
    k := it ->> 'kind';
    insert into public.venture_items (meeting_id, kind, params, proposed_by) values (mid, k::public.venture_kind, coalesce(it -> 'params', '{}'::jsonb), caller) returning id into iid;
    insert into public.venture_votes (item_id, member_id, choice) values (iid, caller, 'yes');
  end loop;
  return mid;
end $$;

create function private.jv_apply(v public.ventures, it public.venture_items) returns void language plpgsql security definer set search_path = '' as $$
declare k text := it.kind::text; amt numeric; paid numeric := 0; r record; pid uuid; val numeric;
begin
  if k = 'dividend' then
    amt := (it.params ->> 'amount')::numeric;
    for r in select member_id, shares from public.venture_partners where venture_id = v.id and member_id <> v.chair_id loop
      perform private.settle(r.member_id, round(amt * r.shares / private.jv_total_shares(v.id), 2), v.currency, 'venture_dividend', v.id::text, 'Dividend: ' || v.name, jsonb_build_object('ventureID', v.id));
      paid := paid + round(amt * r.shares / private.jv_total_shares(v.id), 2);
    end loop;
    perform private.settle(v.chair_id, -paid, v.currency, 'venture_company_payout', v.id::text, 'Dividend paid to partners', jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
  elsif k = 'capital' then
    amt := (it.params ->> 'amount')::numeric;
    for r in select member_id, shares from public.venture_partners where venture_id = v.id and member_id <> v.chair_id loop
      perform private.settle(r.member_id, -round(amt * r.shares / private.jv_total_shares(v.id), 2), v.currency, 'venture_capital_call', v.id::text, 'Capital call: ' || v.name, jsonb_build_object('ventureID', v.id));
      paid := paid + round(amt * r.shares / private.jv_total_shares(v.id), 2);
    end loop;
    perform private.settle(v.chair_id, paid, v.currency, 'venture_capital', v.id::text, 'Capital called from partners', jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
  elsif k = 'dissolve' then
    val := v.value;
    for r in select member_id, shares from public.venture_partners where venture_id = v.id and member_id <> v.chair_id loop
      perform private.settle(r.member_id, floor(val * r.shares / private.jv_total_shares(v.id) * 100) / 100, v.currency, 'venture_dissolved', v.id::text, 'Joint venture closed: ' || v.name, jsonb_build_object('ventureID', v.id));
      paid := paid + floor(val * r.shares / private.jv_total_shares(v.id) * 100) / 100;
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

-- One rule for every vote: an item passes when more than half of all shares voted yes. Silence counts as abstaining.
create function private.jv_settle_meeting(p_meeting uuid, at_deadline boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare m public.venture_meetings; v public.ventures; it public.venture_items; tot numeric; yes_s numeric; res public.venture_outcome; outs jsonb := '[]'::jsonb; r record;
begin
  select * into m from public.venture_meetings where id = p_meeting for update;
  if not found or m.closed_at is not null then return null; end if;
  select * into v from public.ventures where id = m.venture_id for update;
  tot := private.jv_total_shares(v.id);
  if not at_deadline then
    if m.planned then return null; end if;
    for it in select * from public.venture_items where meeting_id = m.id loop
      select coalesce(sum(p.shares), 0) into yes_s from public.venture_partners p
        join public.venture_votes x on x.member_id = p.member_id and x.item_id = it.id and x.choice = 'yes' where p.venture_id = v.id;
      if yes_s * 2 <= tot then return null; end if;
    end loop;
  end if;
  for it in select * from public.venture_items where meeting_id = m.id order by created_at, id loop
    select coalesce(sum(p.shares), 0) into yes_s from public.venture_partners p
      join public.venture_votes x on x.member_id = p.member_id and x.item_id = it.id and x.choice = 'yes' where p.venture_id = v.id;
    res := case when tot > 0 and yes_s * 2 > tot then 'passed' else 'failed' end;
    update public.venture_items set outcome = res where id = it.id;
    outs := outs || jsonb_build_array(jsonb_build_object('itemID', it.id, 'kind', it.kind, 'outcome', res));
    if res = 'passed' then
      perform private.jv_apply(v, it);
      select * into v from public.ventures where id = v.id;
    end if;
    for r in select member_id from public.venture_partners where venture_id = v.id loop
      perform private.settle(r.member_id, 0, v.currency, 'venture_decision', it.id::text,
        left((case when res = 'passed' then 'Passed: ' else 'Not passed: ' end) || private.jv_item_title(it.kind::text, it.params) || ' (' || v.name || ')', 200),
        jsonb_build_object('ventureID', v.id, 'companyKey', case when r.member_id = v.chair_id then v.company_key end, 'itemID', it.id, 'kind', it.kind,
          'params', it.params, 'passed', res = 'passed', 'apply', res = 'passed' and r.member_id = v.chair_id));
    end loop;
  end loop;
  update public.venture_meetings set closed_at = now() where id = m.id;
  return outs;
end $$;

create or replace function public.close_venture_meeting(p_meeting uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare m public.venture_meetings;
begin
  select * into m from public.venture_meetings where id = p_meeting;
  if not found or (auth.uid() is not null and not private.is_partner(m.venture_id, auth.uid())) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if m.closed_at is not null then raise exception 'already_closed' using errcode = 'P0001'; end if;
  if now() <= m.deadline then raise exception 'voting_open' using errcode = 'P0001'; end if;
  return private.jv_settle_meeting(m.id, true);
end $$;

create or replace function public.cast_venture_vote(p_item uuid, p_choice public.venture_choice) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); m public.venture_meetings;
begin
  select m2.* into m from public.venture_items i join public.venture_meetings m2 on m2.id = i.meeting_id where i.id = p_item;
  if not found or m.closed_at is not null or not private.is_partner(m.venture_id, uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if now() > m.deadline then raise exception 'vote_closed' using errcode = 'P0001'; end if;
  insert into public.venture_votes (item_id, member_id, choice) values (p_item, uid, p_choice)
    on conflict (item_id, member_id) do update set choice = excluded.choice, cast_at = now();
  perform private.jv_settle_meeting(m.id, false);
end $$;

create or replace function public.open_venture_meeting(p_venture uuid, p_items jsonb, p_profitable boolean default true, p_cash_tight boolean default false) returns uuid
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures;
begin
  select * into v from public.ventures where id = p_venture and dissolved_at is null for update;
  if not found or not private.is_partner(v.id, uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  return private.jv_open_meeting(v, uid, true, p_items, coalesce(p_profitable, true), coalesce(p_cash_tight, false));
end $$;

-- p_now false adds the change to the weekly meeting; true calls a 24-hour emergency meeting. A sole owner's change applies at once.
create function public.propose_venture_change(p_venture uuid, p_kind text, p_params jsonb, p_now boolean default false, p_profitable boolean default true,
                                              p_cash_tight boolean default false) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures; m public.venture_meetings; mid uuid; params jsonb := coalesce(p_params, '{}'::jsonb);
begin
  select * into v from public.ventures where id = p_venture and dissolved_at is null for update;
  if not found or not private.is_partner(v.id, uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if (select count(*) from public.venture_partners where venture_id = v.id) < 2 then
    if p_kind is null or p_kind not in ('policy', 'setting') then raise exception 'no_partners' using errcode = 'P0001'; end if;
    perform private.jv_check_item(v, p_kind, params);
    perform private.jv_apply_change(v.id, p_kind, params);
    return jsonb_build_object('applied', true);
  end if;
  mid := private.jv_open_meeting(v, uid, not coalesce(p_now, false), jsonb_build_array(jsonb_build_object('kind', p_kind, 'params', params)),
                                 coalesce(p_profitable, true), coalesce(p_cash_tight, false));
  perform private.jv_settle_meeting(mid, false);
  select * into m from public.venture_meetings where id = mid;
  return jsonb_build_object('applied', m.closed_at is not null, 'meetingID', mid, 'emergency', not m.planned, 'deadline', m.deadline);
end $$;

create or replace function public.venture_meeting(p_meeting uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); m public.venture_meetings; tot numeric;
begin
  select * into m from public.venture_meetings where id = p_meeting;
  if not found or not private.is_partner(m.venture_id, uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  tot := private.jv_total_shares(m.venture_id);
  return jsonb_build_object('id', m.id, 'ventureID', m.venture_id, 'planned', m.planned, 'calledBy', private.display_name(m.called_by), 'openedAt', m.opened_at,
    'deadline', m.deadline, 'closedAt', m.closed_at, 'totalShares', tot,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'kind', i.kind, 'title', private.jv_item_title(i.kind::text, i.params), 'params', i.params,
       'proposedBy', private.display_name(i.proposed_by), 'outcome', i.outcome,
       'myVote', (select choice from public.venture_votes x where x.item_id = i.id and x.member_id = uid),
       'yesShares', (select coalesce(sum(p.shares), 0) from public.venture_partners p join public.venture_votes x on x.member_id = p.member_id and x.item_id = i.id and x.choice = 'yes'
                      where p.venture_id = m.venture_id),
       'noShares', (select coalesce(sum(p.shares), 0) from public.venture_partners p join public.venture_votes x on x.member_id = p.member_id and x.item_id = i.id and x.choice = 'no'
                     where p.venture_id = m.venture_id),
       'votes', case when m.closed_at is null then null else
          (select coalesce(jsonb_agg(jsonb_build_object('memberID', x.member_id, 'name', private.display_name(x.member_id), 'choice', x.choice)), '[]'::jsonb)
             from public.venture_votes x where x.item_id = i.id) end) order by i.created_at, i.id) from public.venture_items i where i.meeting_id = m.id), '[]'::jsonb));
end $$;

create or replace function public.my_ventures() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(private.jv_json(v, uid) || jsonb_build_object(
      'openMeeting', (select m.id from public.venture_meetings m where m.venture_id = v.id and m.closed_at is null order by m.deadline limit 1),
      'openMeetings', coalesce((select jsonb_agg(m.id order by m.deadline) from public.venture_meetings m where m.venture_id = v.id and m.closed_at is null), '[]'::jsonb)) order by v.created_at)
    from public.ventures v where private.is_partner(v.id, uid) and v.dissolved_at is null), '[]'::jsonb);
end $$;

create function private.jv_buyback_json(o public.venture_buybacks) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', o.id, 'ventureID', v.id, 'companyName', v.name, 'buyerID', o.buyer_id, 'buyerName', private.display_name(o.buyer_id),
    'sellerID', o.seller_id, 'sellerName', private.display_name(o.seller_id), 'shares', o.shares,
    'percent', round(100.0 * o.shares / nullif(private.jv_total_shares(v.id), 0), 3), 'price', o.price, 'fair', o.fair, 'currency', v.currency,
    'status', o.status, 'proposedBy', o.proposed_by, 'sentAt', o.created_at, 'expiresAt', o.expires_at)
  from public.ventures v where v.id = o.venture_id;
$$;

create function private.jv_buyback_offer(v public.ventures, seller uuid, proposer uuid, price numeric) returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.venture_partners; fair numeric; o public.venture_buybacks;
begin
  select * into p from public.venture_partners where venture_id = v.id and member_id = seller and member_id <> v.chair_id;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if now() < p.lock_until then raise exception 'locked' using errcode = 'P0001'; end if;
  update public.venture_buybacks set status = 'expired', answered_at = now() where venture_id = v.id and status = 'pending' and expires_at < now();
  if exists (select 1 from public.venture_buybacks where venture_id = v.id and seller_id = seller and status = 'pending') then
    raise exception 'offer_open' using errcode = 'P0001';
  end if;
  fair := round(v.value * p.shares / nullif(private.jv_total_shares(v.id), 0), 2);
  if fair is null or fair <= 0 then raise exception 'worthless' using errcode = 'P0001'; end if;
  if price is null or price < fair * private.rule_num('band.venture_low') or price > fair * private.rule_num('band.venture_high') then
    raise exception 'outside_band' using errcode = 'P0001';
  end if;
  insert into public.venture_buybacks (venture_id, buyer_id, seller_id, shares, price, fair, proposed_by)
    values (v.id, v.chair_id, seller, p.shares, round(price, 2), fair, proposer) returning * into o;
  return jsonb_build_object('id', o.id, 'fair', o.fair, 'expiresAt', o.expires_at);
end $$;

-- The chair offers to buy a partner's whole stake. Nothing moves until the partner accepts.
create function public.offer_venture_buyback(p_venture uuid, p_partner uuid, p_price numeric) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures;
begin
  perform private.require_free(uid, 'trade');
  select * into v from public.ventures where id = p_venture and chair_id = uid and dissolved_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  return private.jv_buyback_offer(v, p_partner, uid, p_price);
end $$;

-- A partner asks the chair to buy their stake. Nothing moves until the chair accepts.
create function public.request_venture_exit(p_venture uuid, p_price numeric) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures;
begin
  perform private.require_free(uid, 'trade');
  select * into v from public.ventures where id = p_venture and dissolved_at is null for update;
  if not found or not private.is_partner(v.id, uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  return private.jv_buyback_offer(v, uid, uid, p_price);
end $$;
revoke execute on function public.leave_venture(uuid) from authenticated;

create function private.jv_buyback_settle(o public.venture_buybacks) returns void language plpgsql security definer set search_path = '' as $$
declare v public.ventures; p public.venture_partners; m record;
begin
  select * into v from public.ventures where id = o.venture_id for update;
  select * into p from public.venture_partners where venture_id = o.venture_id and member_id = o.seller_id for update;
  if v.dissolved_at is not null or p.member_id is null or p.shares <> o.shares or not private.is_partner(v.id, o.buyer_id) then
    raise exception 'offer_expired' using errcode = 'P0001';
  end if;
  update public.venture_partners set shares = shares + p.shares where venture_id = v.id and member_id = o.buyer_id;
  delete from public.venture_partners where venture_id = v.id and member_id = o.seller_id;
  delete from public.venture_votes x using public.venture_items i, public.venture_meetings mt
   where x.item_id = i.id and i.meeting_id = mt.id and mt.venture_id = v.id and mt.closed_at is null and x.member_id = o.seller_id;
  update public.venture_buybacks set status = 'accepted', answered_at = now() where id = o.id;
  perform private.settle(o.seller_id, o.price, v.currency, 'venture_exit', v.id::text, 'Sold your shares in ' || v.name, jsonb_build_object('ventureID', v.id));
  perform private.settle(o.buyer_id, -o.price, v.currency, 'venture_buyback', v.id::text, 'Bought back shares from ' || private.display_name(o.seller_id),
    jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key, 'partner', private.display_name(o.seller_id), 'shares', o.shares));
  for m in select id from public.venture_meetings where venture_id = v.id and closed_at is null and not planned loop
    perform private.jv_settle_meeting(m.id, false);
  end loop;
end $$;

create function private.jv_buyback_decline(o public.venture_buybacks) returns void language plpgsql security definer set search_path = '' as $$
declare v public.ventures;
begin
  select * into v from public.ventures where id = o.venture_id;
  update public.venture_buybacks set status = 'declined', answered_at = now() where id = o.id;
  perform private.settle(o.proposed_by, 0, v.currency, 'venture_buyback_reply', o.id::text,
    private.display_name(case when o.proposed_by = o.buyer_id then o.seller_id else o.buyer_id end) || ' turned down the offer for the shares in ' || v.name || '.',
    jsonb_build_object('ventureID', v.id, 'companyKey', case when o.proposed_by = v.chair_id then v.company_key end, 'accepted', false));
end $$;

create function public.reply_to_venture_buyback(p_offer uuid, p_accept boolean) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); o public.venture_buybacks;
begin
  select * into o from public.venture_buybacks where id = p_offer and status = 'pending' and uid in (buyer_id, seller_id) and proposed_by <> uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if o.expires_at < now() then raise exception 'offer_expired' using errcode = 'P0001'; end if;
  if not coalesce(p_accept, false) then perform private.jv_buyback_decline(o); return; end if;
  perform private.require_free(uid, 'trade');
  perform private.jv_buyback_settle(o);
end $$;

create function public.withdraw_venture_buyback(p_offer uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  update public.venture_buybacks set status = 'withdrawn', answered_at = now() where id = p_offer and proposed_by = uid and status = 'pending';
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
end $$;

create function public.my_venture_buybacks() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return jsonb_build_object(
    'incoming', coalesce((select jsonb_agg(private.jv_buyback_json(o) order by o.created_at) from public.venture_buybacks o
                           where uid in (o.buyer_id, o.seller_id) and o.proposed_by <> uid and o.status = 'pending' and o.expires_at >= now()), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(private.jv_buyback_json(o) order by o.created_at desc)
                            from (select * from public.venture_buybacks where proposed_by = uid order by created_at desc limit 20) o), '[]'::jsonb));
end $$;

-- Generated co-owners answer after a human delay, and only while awake unless the wait has grown long.
create function private.jv_bot_due(seed text, at timestamptz, uid uuid, lo int, span int) returns boolean language sql stable as $$
  select now() >= at + make_interval(mins => lo + abs(hashtext(seed)) % span)
     and (private.bot_awake(uid) or now() >= at + make_interval(mins => lo + span + 180));
$$;

create function private.jv_bot_choice(kind text, params jsonb, v public.ventures, profitable boolean, cash_tight boolean, seed text) returns public.venture_choice
language plpgsql stable as $$
declare roll int := abs(hashtext(seed || 'c')) % 100; yes boolean; ranks text[] := array['none', 'low', 'mid', 'high'];
begin
  if kind = 'dividend' then yes := profitable and not cash_tight;
  elsif kind = 'capital' then yes := cash_tight;
  elsif kind in ('price', 'hire', 'partner') then yes := profitable;
  elsif kind = 'sell' then yes := not profitable;
  elsif kind = 'dissolve' then yes := not profitable and cash_tight;
  elsif kind = 'policy' then
    yes := case when array_position(ranks, params ->> 'policy') > array_position(ranks, v.dividend_policy) then profitable and not cash_tight
                else cash_tight or not profitable or roll % 2 = 0 end;
  else yes := roll >= 30;
  end if;
  if roll < 10 then return 'abstain'; end if;
  if roll < 18 and kind <> 'setting' then yes := not yes; end if;
  return case when yes then 'yes' else 'no' end;
end $$;

create function private.jv_bot_act() returns int language plpgsql security definer set search_path = '' as $$
declare i public.venture_invites; o public.venture_buybacks; v public.ventures; r record; n int := 0; ratio numeric;
begin
  for i in select i2.* from public.venture_invites i2 join public.profiles b on b.id = i2.invitee_id
            where i2.status = 'pending' and i2.expires_at >= now() and b.is_bot and b.deleted_at is null order by i2.sent_at for update of i2 skip locked loop
    continue when not private.jv_bot_due(i.id::text, i.sent_at, i.invitee_id, 10, 300);
    select * into v from public.ventures where id = i.venture_id for update;
    ratio := case when i.fair > 0 then i.price / i.fair else 1 end;
    if v.dissolved_at is null and abs(hashtext(i.id::text || 'a')) % 100 < least(95, greatest(25, 115 - 35 * ratio)) then
      begin
        perform private.jv_invite_check(v, v.chair_id, i.invitee_id, i.pct, i.price);
        perform private.jv_join(v, i.invitee_id, i.pct, i.price);
        update public.venture_invites set status = 'accepted' where id = i.id;
      exception when others then
        update public.venture_invites set status = 'declined' where id = i.id;
      end;
    else
      update public.venture_invites set status = 'declined' where id = i.id;
    end if;
    n := n + 1;
  end loop;

  for r in select it.id as item_id, it.kind::text as kind, it.params, it.created_at, m.id as meeting_id, m.planned, m.profitable, m.cash_tight, m.venture_id, p.member_id
             from public.venture_meetings m join public.venture_items it on it.meeting_id = m.id
             join public.venture_partners p on p.venture_id = m.venture_id
             join public.profiles b on b.id = p.member_id and b.is_bot and b.deleted_at is null
            where m.closed_at is null and m.deadline > now()
              and not exists (select 1 from public.venture_votes x where x.item_id = it.id and x.member_id = p.member_id)
            order by it.created_at, it.id, p.member_id loop
    continue when abs(hashtext(r.item_id::text || r.member_id::text || 's')) % 100 < 7;
    continue when not private.jv_bot_due(r.item_id::text || r.member_id::text, r.created_at, r.member_id, 10, 600);
    continue when exists (select 1 from public.venture_meetings where id = r.meeting_id and closed_at is not null);
    select * into v from public.ventures where id = r.venture_id;
    insert into public.venture_votes (item_id, member_id, choice)
      values (r.item_id, r.member_id, private.jv_bot_choice(r.kind, r.params, v, r.profitable, r.cash_tight, r.item_id::text || r.member_id::text))
      on conflict (item_id, member_id) do nothing;
    if not r.planned then perform private.jv_settle_meeting(r.meeting_id, false); end if;
    n := n + 1;
  end loop;

  for o in select o2.* from public.venture_buybacks o2 join public.profiles b on b.id = o2.seller_id
            where o2.status = 'pending' and o2.expires_at >= now() and o2.proposed_by = o2.buyer_id and b.is_bot and b.deleted_at is null
            order by o2.created_at for update of o2 skip locked loop
    continue when not private.jv_bot_due(o.id::text, o.created_at, o.seller_id, 10, 300);
    ratio := case when o.fair > 0 then o.price / o.fair else 1 end;
    if abs(hashtext(o.id::text || 'a')) % 100 < least(92, greatest(5, 140 * ratio - 75)) then
      begin
        perform private.jv_buyback_settle(o);
      exception when others then
        update public.venture_buybacks set status = 'expired', answered_at = now() where id = o.id;
      end;
    else
      perform private.jv_buyback_decline(o);
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

-- A generated co-owner that was removed from the world hands its shares back to the chair, so no vote waits on it.
create function private.jv_drop_removed_bots() returns int language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in select p.venture_id, p.member_id, p.shares, v.chair_id from public.venture_partners p
             join public.profiles b on b.id = p.member_id and b.is_bot and b.deleted_at is not null
             join public.ventures v on v.id = p.venture_id where p.member_id <> v.chair_id for update of p loop
    update public.venture_partners set shares = shares + r.shares where venture_id = r.venture_id and member_id = r.chair_id;
    delete from public.venture_partners where venture_id = r.venture_id and member_id = r.member_id;
    n := n + 1;
  end loop;
  update public.venture_invites i set status = 'expired' from public.profiles b where b.id = i.invitee_id and b.is_bot and b.deleted_at is not null and i.status = 'pending';
  update public.venture_buybacks o set status = 'expired', answered_at = now() from public.profiles b
   where b.id = o.seller_id and b.is_bot and b.deleted_at is not null and o.status = 'pending';
  return n;
end $$;

create or replace function private.run_venture_housekeeping() returns int language plpgsql security definer set search_path = '' as $$
declare m record; n int := 0;
begin
  update public.venture_invites set status = 'expired' where status = 'pending' and expires_at < now();
  update public.venture_buybacks set status = 'expired', answered_at = now() where status = 'pending' and expires_at < now();
  perform private.jv_drop_removed_bots();
  n := private.jv_bot_act();
  for m in select id from public.venture_meetings where closed_at is null and deadline < now() loop
    perform private.jv_settle_meeting(m.id, true);
    n := n + 1;
  end loop;
  return n;
end $$;

update public.job_runs set every = interval '5 minutes' where name = 'ventures';

create function private.push_on_venture_meeting() returns trigger language plpgsql security definer set search_path = '' as $$
declare r record; nm text;
begin
  if new.planned then return new; end if;
  select name into nm from public.ventures where id = new.venture_id;
  for r in select member_id from public.venture_partners where venture_id = new.venture_id and member_id is distinct from new.called_by loop
    perform private.queue_push(r.member_id, 'board', 'Emergency board meeting',
      left(coalesce(private.display_name(new.called_by), 'A co-owner') || ' called a vote at ' || nm || '. You have 24 hours to vote.', 240));
  end loop;
  return new;
end $$;

create function private.push_on_venture_invite() returns trigger language plpgsql security definer set search_path = '' as $$
declare v public.ventures;
begin
  select * into v from public.ventures where id = new.venture_id;
  perform private.queue_push(new.invitee_id, 'board', 'Partner offer from ' || private.display_name(v.chair_id),
    left(trim(to_char(new.pct, 'FM990.0')) || '% of ' || v.name || ' is offered to you. Open Ledger to see the price and answer.', 240));
  return new;
end $$;

create function private.push_on_venture_buyback() returns trigger language plpgsql security definer set search_path = '' as $$
declare v public.ventures;
begin
  select * into v from public.ventures where id = new.venture_id;
  if new.proposed_by = new.buyer_id then
    perform private.queue_push(new.seller_id, 'board', 'Offer for your shares',
      left(private.display_name(new.buyer_id) || ' offers to buy your shares in ' || v.name || '. Open Ledger to accept or decline.', 240));
  else
    perform private.queue_push(new.buyer_id, 'board', 'A partner wants to sell',
      left(private.display_name(new.seller_id) || ' asks you to buy their shares in ' || v.name || '. Open Ledger to accept or decline.', 240));
  end if;
  return new;
end $$;

create trigger push_on_venture_meeting after insert on public.venture_meetings for each row execute function private.push_on_venture_meeting();
create trigger push_on_venture_invite after insert on public.venture_invites for each row execute function private.push_on_venture_invite();
create trigger push_on_venture_buyback after insert on public.venture_buybacks for each row execute function private.push_on_venture_buyback();

revoke execute on all functions in schema public from public, anon;
grant execute on function public.propose_venture_change(uuid, text, jsonb, boolean, boolean, boolean), public.offer_venture_buyback(uuid, uuid, numeric),
  public.request_venture_exit(uuid, numeric), public.reply_to_venture_buyback(uuid, boolean), public.withdraw_venture_buyback(uuid), public.my_venture_buybacks() to authenticated;
