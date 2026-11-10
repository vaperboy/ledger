create type public.venture_kind as enum ('dividend', 'price', 'hire', 'sell', 'partner', 'capital', 'dissolve');
create type public.venture_choice as enum ('yes', 'no', 'abstain');
create type public.venture_outcome as enum ('passed', 'failed', 'noQuorum', 'chairPassed', 'chairFailed', 'statusQuo');
create type public.venture_invite_status as enum ('pending', 'accepted', 'declined', 'expired');

create table public.ventures (
  id uuid primary key default gen_random_uuid(),
  chair_id uuid not null references public.profiles (id) on delete cascade,
  company_key text not null check (char_length(company_key) between 1 and 64),
  name text not null check (char_length(name) between 1 and 40),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  value numeric(18, 2) not null default 0 check (value >= 0),
  total_shares int not null default 10000 check (total_shares > 0),
  created_at timestamptz not null default now(),
  dissolved_at timestamptz
);
create unique index ventures_one_per_company on public.ventures (chair_id, company_key) where dissolved_at is null;

create table public.venture_partners (
  venture_id uuid not null references public.ventures (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  shares int not null check (shares > 0),
  joined_at timestamptz not null default now(),
  lock_until timestamptz not null default now(),
  primary key (venture_id, member_id)
);
create index venture_partners_member on public.venture_partners (member_id);

create table public.venture_invites (
  id uuid primary key default gen_random_uuid(),
  venture_id uuid not null references public.ventures (id) on delete cascade,
  invitee_id uuid not null references public.profiles (id) on delete cascade,
  pct numeric(6, 3) not null check (pct >= 2 and pct <= 49),
  price numeric(18, 2) not null check (price > 0),
  fair numeric(18, 2) not null,
  status public.venture_invite_status not null default 'pending',
  sent_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '28 days'
);
create unique index venture_invite_pending on public.venture_invites (venture_id, invitee_id) where status = 'pending';

create table public.venture_meetings (
  id uuid primary key default gen_random_uuid(),
  venture_id uuid not null references public.ventures (id) on delete cascade,
  planned boolean not null,
  called_by uuid references public.profiles (id) on delete set null,
  opened_at timestamptz not null default now(),
  deadline timestamptz not null,
  closed_at timestamptz,
  profitable boolean not null default true,
  cash_tight boolean not null default false
);
create index venture_meetings_venture on public.venture_meetings (venture_id, opened_at desc);

create table public.venture_meeting_shares (
  meeting_id uuid not null references public.venture_meetings (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  shares int not null check (shares > 0),
  primary key (meeting_id, member_id)
);

create table public.venture_items (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.venture_meetings (id) on delete cascade,
  kind public.venture_kind not null,
  params jsonb not null default '{}'::jsonb,
  outcome public.venture_outcome
);
create index venture_items_meeting on public.venture_items (meeting_id);

create table public.venture_votes (
  item_id uuid not null references public.venture_items (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  choice public.venture_choice not null,
  cast_at timestamptz not null default now(),
  primary key (item_id, member_id)
);

alter table public.ventures enable row level security;
alter table public.venture_partners enable row level security;
alter table public.venture_invites enable row level security;
alter table public.venture_meetings enable row level security;
alter table public.venture_meeting_shares enable row level security;
alter table public.venture_items enable row level security;
alter table public.venture_votes enable row level security;
revoke all on public.ventures, public.venture_partners, public.venture_invites, public.venture_meetings, public.venture_meeting_shares,
  public.venture_items, public.venture_votes from anon, authenticated;
grant select on public.ventures, public.venture_partners, public.venture_invites, public.venture_meetings, public.venture_meeting_shares,
  public.venture_items, public.venture_votes to authenticated;

create function private.is_partner(vid uuid, uid uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.venture_partners where venture_id = vid and member_id = uid);
$$;

create policy ventures_partner on public.ventures for select to authenticated using (private.is_partner(id, auth.uid()));
create policy venture_partners_partner on public.venture_partners for select to authenticated using (private.is_partner(venture_id, auth.uid()));
create policy venture_invites_party on public.venture_invites for select to authenticated
  using (invitee_id = auth.uid() or exists (select 1 from public.ventures v where v.id = venture_id and v.chair_id = auth.uid()));
create policy venture_meetings_partner on public.venture_meetings for select to authenticated using (private.is_partner(venture_id, auth.uid()));
create policy venture_meeting_shares_partner on public.venture_meeting_shares for select to authenticated
  using (exists (select 1 from public.venture_meetings m where m.id = meeting_id and private.is_partner(m.venture_id, auth.uid())));
create policy venture_items_partner on public.venture_items for select to authenticated
  using (exists (select 1 from public.venture_meetings m where m.id = meeting_id and private.is_partner(m.venture_id, auth.uid())));
create policy venture_votes_own on public.venture_votes for select to authenticated using (member_id = auth.uid());

create or replace function private.ventures_open(uid uuid) returns boolean language sql stable as $$
  select exists (select 1 from public.venture_partners p join public.ventures v on v.id = p.venture_id where p.member_id = uid and v.dissolved_at is null);
$$;

create function private.jv_fair_price(value numeric, pct numeric) returns numeric language sql immutable as $$
  select case when pct > 0 and pct < 100 then greatest(0, value) * pct / (100 - pct) else 0 end;
$$;

create function private.jv_chair_pct(vid uuid) returns numeric language sql stable security definer set search_path = '' as $$
  select 100.0 * p.shares / v.total_shares from public.ventures v join public.venture_partners p on p.venture_id = v.id and p.member_id = v.chair_id where v.id = vid;
$$;

create function private.jv_total_shares(vid uuid) returns int language sql stable security definer set search_path = '' as $$
  select coalesce(sum(shares), 0)::int from public.venture_partners where venture_id = vid;
$$;

create function private.jv_json(v public.ventures, viewer uuid) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'chairID', v.chair_id, 'chairName', private.display_name(v.chair_id), 'companyKey', v.company_key, 'name', v.name,
    'currency', v.currency, 'value', v.value, 'totalShares', private.jv_total_shares(v.id), 'dissolved', v.dissolved_at is not null,
    'isChair', v.chair_id = viewer,
    'partners', coalesce((select jsonb_agg(jsonb_build_object('memberID', p.member_id, 'name', private.display_name(p.member_id), 'shares', p.shares,
         'percent', round(100.0 * p.shares / nullif(private.jv_total_shares(v.id), 0), 3), 'joinedAt', p.joined_at, 'lockUntil', p.lock_until) order by p.joined_at)
       from public.venture_partners p where p.venture_id = v.id), '[]'::jsonb));
$$;

create function public.create_venture(p_company_key text, p_name text, p_value numeric, p_currency text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures;
begin
  perform private.require_free(uid, 'trade');
  if p_value is null or p_value < 0 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  insert into public.ventures (chair_id, company_key, name, currency, value) values (uid, p_company_key, p_name, p_currency, round(p_value, 2)) returning * into v;
  insert into public.venture_partners (venture_id, member_id, shares) values (v.id, uid, v.total_shares);
  return private.jv_json(v, uid);
end $$;

create function public.report_venture_value(p_venture uuid, p_value numeric) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if p_value is null or p_value < 0 then raise exception 'invalid_value' using errcode = 'P0001'; end if;
  update public.ventures set value = round(p_value, 2) where id = p_venture and chair_id = uid and dissolved_at is null;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
end $$;

create function private.jv_invite_check(v public.ventures, inviter uuid, invitee uuid, pct numeric, price numeric) returns numeric language plpgsql stable security definer set search_path = '' as $$
declare fair numeric; partners int; chair_after numeric;
begin
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
  if price < fair * 0.7 or price > fair * 1.5 then raise exception 'outside_band' using errcode = 'P0001'; end if;
  return fair;
end $$;

create function public.invite_venture_partner(p_venture uuid, p_friend uuid, p_pct numeric, p_price numeric) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures; fair numeric; inv public.venture_invites;
begin
  perform private.require_free(uid, 'trade');
  select * into v from public.ventures where id = p_venture and chair_id = uid and dissolved_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  update public.venture_invites set status = 'expired' where venture_id = v.id and status = 'pending' and expires_at < now();
  fair := private.jv_invite_check(v, uid, p_friend, p_pct, p_price);
  insert into public.venture_invites (venture_id, invitee_id, pct, price, fair) values (v.id, p_friend, p_pct, round(p_price, 2), round(fair, 2)) returning * into inv;
  return jsonb_build_object('id', inv.id, 'fair', inv.fair, 'expiresAt', inv.expires_at);
end $$;

create function public.my_venture_offers() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'ventureID', v.id, 'companyName', v.name, 'chairID', v.chair_id, 'chairName', private.display_name(v.chair_id),
      'pct', i.pct, 'price', i.price, 'fair', i.fair, 'currency', v.currency, 'sentAt', i.sent_at, 'expiresAt', i.expires_at, 'lockWeeks', 26) order by i.sent_at)
    from public.venture_invites i join public.ventures v on v.id = i.venture_id
   where i.invitee_id = uid and i.status = 'pending' and i.expires_at >= now() and v.dissolved_at is null), '[]'::jsonb);
end $$;

create function private.jv_join(v public.ventures, invitee uuid, pct numeric, price numeric) returns void language plpgsql security definer set search_path = '' as $$
declare total int := private.jv_total_shares(v.id); new_shares int := greatest(1, round(total * pct / (100 - pct))::int);
begin
  insert into public.venture_partners (venture_id, member_id, shares, lock_until) values (v.id, invitee, new_shares, now() + private.weeks(26));
  perform private.settle(invitee, -price, v.currency, 'venture_stake', v.id::text, 'Joined ' || v.name, jsonb_build_object('ventureID', v.id, 'percent', pct));
  perform private.settle(v.chair_id, price, v.currency, 'venture_capital', v.id::text, 'New partner in ' || v.name,
    jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key, 'partner', private.display_name(invitee)));
end $$;

create function public.reply_to_venture_offer(p_invite uuid, p_accept boolean, p_currency text) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); i public.venture_invites; v public.ventures;
begin
  select * into i from public.venture_invites where id = p_invite and invitee_id = uid and status = 'pending' for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  select * into v from public.ventures where id = i.venture_id for update;
  if v.dissolved_at is not null or i.expires_at < now() then
    update public.venture_invites set status = 'expired' where id = i.id;
    raise exception 'offer_expired' using errcode = 'P0001';
  end if;
  if not p_accept then update public.venture_invites set status = 'declined' where id = i.id; return; end if;
  perform private.require_free(uid, 'trade');
  if p_currency <> v.currency then raise exception 'currency_mismatch' using errcode = 'P0001'; end if;
  perform private.jv_invite_check(v, v.chair_id, uid, i.pct, i.price) where not private.is_partner(v.id, uid);
  perform private.jv_join(v, uid, i.pct, i.price);
  update public.venture_invites set status = 'accepted' where id = i.id;
end $$;

create function private.jv_open_meeting(v public.ventures, caller uuid, planned boolean, items jsonb, profitable boolean, cash_tight boolean) returns uuid
language plpgsql security definer set search_path = '' as $$
declare mid uuid; it jsonb; k public.venture_kind; amt numeric;
begin
  if exists (select 1 from public.venture_meetings where venture_id = v.id and closed_at is null) then raise exception 'meeting_open' using errcode = 'P0001'; end if;
  if jsonb_typeof(items) <> 'array' or jsonb_array_length(items) not between 1 and 5 then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
  insert into public.venture_meetings (venture_id, planned, called_by, deadline, profitable, cash_tight)
    values (v.id, planned, caller, now() + case when planned then private.weeks(2) else private.weeks(1) end,
            profitable, cash_tight) returning id into mid;
  insert into public.venture_meeting_shares (meeting_id, member_id, shares) select mid, member_id, shares from public.venture_partners where venture_id = v.id;
  for it in select * from jsonb_array_elements(items) loop
    k := (it->>'kind')::public.venture_kind;
    if k in ('dividend', 'capital') then
      amt := (it->'params'->>'amount')::numeric;
      if amt is null or amt <= 0 or amt > 1e12 then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
    elsif k = 'partner' then
      if (it->'params'->>'invitee') is null or (it->'params'->>'pct') is null or (it->'params'->>'price') is null then raise exception 'invalid_agenda' using errcode = 'P0001'; end if;
    end if;
    insert into public.venture_items (meeting_id, kind, params) values (mid, k, coalesce(it->'params', '{}'::jsonb));
  end loop;
  return mid;
end $$;

create function public.open_venture_meeting(p_venture uuid, p_items jsonb, p_profitable boolean default true, p_cash_tight boolean default false) returns uuid
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures; last_planned timestamptz;
begin
  select * into v from public.ventures where id = p_venture and chair_id = uid and dissolved_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  select max(opened_at) into last_planned from public.venture_meetings where venture_id = v.id and planned;
  if last_planned is not null and now() < last_planned + private.weeks(13) then raise exception 'too_soon' using errcode = 'P0001'; end if;
  return private.jv_open_meeting(v, uid, true, p_items, p_profitable, p_cash_tight);
end $$;

create function public.call_venture_emergency(p_venture uuid, p_kind public.venture_kind, p_params jsonb default '{}'::jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures;
begin
  select * into v from public.ventures where id = p_venture and dissolved_at is null for update;
  if not found or not private.is_partner(v.id, uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  return private.jv_open_meeting(v, uid, false, jsonb_build_array(jsonb_build_object('kind', p_kind, 'params', p_params)), true, false);
end $$;

create function public.cast_venture_vote(p_item uuid, p_choice public.venture_choice) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); m public.venture_meetings;
begin
  select m2.* into m from public.venture_items i join public.venture_meetings m2 on m2.id = i.meeting_id where i.id = p_item;
  if not found or m.closed_at is not null or not exists (select 1 from public.venture_meeting_shares where meeting_id = m.id and member_id = uid) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if now() > m.deadline then raise exception 'vote_closed' using errcode = 'P0001'; end if;
  insert into public.venture_votes (item_id, member_id, choice) values (p_item, uid, p_choice)
    on conflict (item_id, member_id) do update set choice = excluded.choice, cast_at = now();
end $$;

create function public.venture_meeting(p_meeting uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); m public.venture_meetings;
begin
  select * into m from public.venture_meetings where id = p_meeting;
  if not found or not private.is_partner(m.venture_id, uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  return jsonb_build_object('id', m.id, 'ventureID', m.venture_id, 'planned', m.planned, 'openedAt', m.opened_at, 'deadline', m.deadline, 'closedAt', m.closed_at,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'kind', i.kind, 'params', i.params, 'outcome', i.outcome,
       'myVote', (select choice from public.venture_votes x where x.item_id = i.id and x.member_id = uid),
       'votes', case when m.closed_at is null then null else
          (select coalesce(jsonb_agg(jsonb_build_object('memberID', x.member_id, 'name', private.display_name(x.member_id), 'choice', x.choice)), '[]'::jsonb)
             from public.venture_votes x where x.item_id = i.id) end) order by i.kind) from public.venture_items i where i.meeting_id = m.id), '[]'::jsonb));
end $$;

create function public.my_ventures() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(private.jv_json(v, uid) || jsonb_build_object('openMeeting',
      (select m.id from public.venture_meetings m where m.venture_id = v.id and m.closed_at is null limit 1)) order by v.created_at)
    from public.ventures v where private.is_partner(v.id, uid) and v.dissolved_at is null), '[]'::jsonb);
end $$;

create function public.close_venture_meeting(p_meeting uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid); m public.venture_meetings; v public.ventures; it public.venture_items;
        yes_s numeric; no_s numeric; tot numeric; cast_share numeric; chair_choice public.venture_choice; res public.venture_outcome; outs jsonb := '[]'::jsonb;
        amt numeric; r record; pid uuid; paid numeric; val numeric;
begin
  select * into m from public.venture_meetings where id = p_meeting for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  select * into v from public.ventures where id = m.venture_id for update;
  if auth.uid() is not null and not private.is_partner(v.id, uid) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if m.closed_at is not null then raise exception 'already_closed' using errcode = 'P0001'; end if;
  if now() <= m.deadline then raise exception 'voting_open' using errcode = 'P0001'; end if;
  select coalesce(sum(shares), 0) into tot from public.venture_meeting_shares where meeting_id = m.id;
  for it in select * from public.venture_items where meeting_id = m.id order by id loop
    select coalesce(sum(s.shares) filter (where x.choice = 'yes'), 0), coalesce(sum(s.shares) filter (where x.choice = 'no'), 0)
      into yes_s, no_s from public.venture_meeting_shares s join public.venture_votes x on x.member_id = s.member_id and x.item_id = it.id
     where s.meeting_id = m.id and x.cast_at <= m.deadline;
    cast_share := case when tot > 0 then (yes_s + no_s) / tot else 0 end;
    select choice into chair_choice from public.venture_votes where item_id = it.id and member_id = v.chair_id;
    res := case when tot = 0 or cast_share < 0.5 then 'noQuorum'
                when yes_s > no_s then 'passed' when no_s > yes_s then 'failed'
                when chair_choice = 'yes' then 'chairPassed' when chair_choice = 'no' then 'chairFailed' else 'statusQuo' end;
    update public.venture_items set outcome = res where id = it.id;
    outs := outs || jsonb_build_array(jsonb_build_object('itemID', it.id, 'kind', it.kind, 'outcome', res));
    continue when res not in ('passed', 'chairPassed');

    if it.kind = 'dividend' then
      amt := (it.params->>'amount')::numeric; paid := 0;
      for r in select member_id, shares from public.venture_partners where venture_id = v.id and member_id <> v.chair_id loop
        perform private.settle(r.member_id, round(amt * r.shares / private.jv_total_shares(v.id), 2), v.currency, 'venture_dividend', v.id::text, 'Dividend: ' || v.name, jsonb_build_object('ventureID', v.id));
        paid := paid + round(amt * r.shares / private.jv_total_shares(v.id), 2);
      end loop;
      perform private.settle(v.chair_id, -paid, v.currency, 'venture_company_payout', v.id::text, 'Dividend paid to partners', jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
    elsif it.kind = 'capital' then
      amt := (it.params->>'amount')::numeric; paid := 0;
      for r in select member_id, shares from public.venture_partners where venture_id = v.id and member_id <> v.chair_id loop
        perform private.settle(r.member_id, -round(amt * r.shares / private.jv_total_shares(v.id), 2), v.currency, 'venture_capital_call', v.id::text, 'Capital call: ' || v.name, jsonb_build_object('ventureID', v.id));
        paid := paid + round(amt * r.shares / private.jv_total_shares(v.id), 2);
      end loop;
      perform private.settle(v.chair_id, paid, v.currency, 'venture_capital', v.id::text, 'Capital called from partners', jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
    elsif it.kind = 'dissolve' then
      val := v.value; paid := 0;
      for r in select member_id, shares from public.venture_partners where venture_id = v.id and member_id <> v.chair_id loop
        perform private.settle(r.member_id, floor(val * r.shares / private.jv_total_shares(v.id) * 100) / 100, v.currency, 'venture_dissolved', v.id::text, 'Joint venture closed: ' || v.name, jsonb_build_object('ventureID', v.id));
        paid := paid + floor(val * r.shares / private.jv_total_shares(v.id) * 100) / 100;
      end loop;
      perform private.settle(v.chair_id, -paid, v.currency, 'venture_company_payout', v.id::text, 'Closing payout to partners', jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
      update public.ventures set dissolved_at = now() where id = v.id;
    elsif it.kind = 'partner' then
      pid := (it.params->>'invitee')::uuid;
      begin
        perform private.jv_invite_check(v, v.chair_id, pid, (it.params->>'pct')::numeric, (it.params->>'price')::numeric);
        insert into public.venture_invites (venture_id, invitee_id, pct, price, fair)
          values (v.id, pid, (it.params->>'pct')::numeric, round((it.params->>'price')::numeric, 2), round(private.jv_fair_price(v.value, (it.params->>'pct')::numeric), 2));
      exception when others then null;
      end;
    end if;
  end loop;
  update public.venture_meetings set closed_at = now() where id = m.id;
  return outs;
end $$;

create function public.leave_venture(p_venture uuid) returns numeric language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures; p public.venture_partners; pay numeric;
begin
  select * into v from public.ventures where id = p_venture and dissolved_at is null for update;
  select * into p from public.venture_partners where venture_id = p_venture and member_id = uid for update;
  if v.id is null or p.member_id is null or v.chair_id = uid then raise exception 'not_found' using errcode = 'P0001'; end if;
  if now() < p.lock_until then raise exception 'locked' using errcode = 'P0001'; end if;
  if exists (select 1 from public.venture_meetings where venture_id = v.id and closed_at is null) then raise exception 'meeting_open' using errcode = 'P0001'; end if;
  pay := round(v.value * p.shares / private.jv_total_shares(v.id), 2);
  update public.venture_partners set shares = shares + p.shares where venture_id = v.id and member_id = v.chair_id;
  delete from public.venture_partners where venture_id = v.id and member_id = uid;
  perform private.settle(uid, pay, v.currency, 'venture_exit', v.id::text, 'Left ' || v.name, jsonb_build_object('ventureID', v.id));
  perform private.settle(v.chair_id, -pay, v.currency, 'venture_company_payout', v.id::text, 'Bought out a partner', jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
  return pay;
end $$;

create function private.run_venture_housekeeping() returns int language plpgsql security definer set search_path = '' as $$
declare m record; n int := 0;
begin
  update public.venture_invites set status = 'expired' where status = 'pending' and expires_at < now();
  for m in select id from public.venture_meetings where closed_at is null and deadline < now() loop
    perform public.close_venture_meeting(m.id);
    n := n + 1;
  end loop;
  return n;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.create_venture(text, text, numeric, text), public.report_venture_value(uuid, numeric),
  public.invite_venture_partner(uuid, uuid, numeric, numeric), public.my_venture_offers(), public.reply_to_venture_offer(uuid, boolean, text),
  public.open_venture_meeting(uuid, jsonb, boolean, boolean), public.call_venture_emergency(uuid, public.venture_kind, jsonb),
  public.cast_venture_vote(uuid, public.venture_choice), public.venture_meeting(uuid), public.my_ventures(), public.close_venture_meeting(uuid),
  public.leave_venture(uuid) to authenticated;
