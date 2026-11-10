create type public.association_standard as enum ('goodName', 'staffPaid', 'outOfTheRed', 'taxCurrent');

create table public.association_clubs (
  id text primary key check (char_length(id) between 1 and 80),
  name text not null,
  trade_name text,
  region text check (region ~ '^[A-Z]{2}$'),
  monthly_fee numeric(12, 2) not null check (monthly_fee >= 0),
  discount_cap numeric(5, 4) not null check (discount_cap between 0 and 0.08),
  standards public.association_standard[] not null
);
insert into public.association_clubs (id, name, trade_name, region, monthly_fee, discount_cap, standards) values
  ('x.circle', 'Independent Business Circle', null, null, 25, 0.03, '{staffPaid,taxCurrent}'),
  ('x.employers', 'Good Employers Alliance', null, null, 30, 0.04, '{goodName,staffPaid}'),
  ('x.steady', 'Steady Traders Club', null, null, 28, 0.03, '{outOfTheRed,taxCurrent}');

create table public.association_members (
  club_id text not null references public.association_clubs (id),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  company_key text not null check (char_length(company_key) between 1 and 64),
  trade_name text not null check (char_length(trade_name) between 1 and 40),
  city text not null default '' check (char_length(city) <= 60),
  joined_at timestamptz not null default now(),
  primary key (owner_id, company_key)
);
create index association_members_club on public.association_members (club_id);

create table public.association_bans (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  company_key text not null,
  club_id text not null references public.association_clubs (id),
  until timestamptz not null,
  breaches public.association_standard[] not null default '{}',
  primary key (owner_id, company_key, club_id)
);

alter table public.association_clubs enable row level security;
alter table public.association_members enable row level security;
alter table public.association_bans enable row level security;
revoke all on public.association_clubs, public.association_members, public.association_bans from anon, authenticated;
grant select on public.association_clubs, public.association_members, public.association_bans to authenticated;
create policy association_clubs_read on public.association_clubs for select to authenticated using (true);
create policy association_members_own on public.association_members for select to authenticated using (owner_id = auth.uid());
create policy association_bans_own on public.association_bans for select to authenticated using (owner_id = auth.uid());

create function private.assoc_slug(s text) returns text language sql immutable as $$ select regexp_replace(lower(s), '[^a-z0-9]', '', 'g'); $$;

create function private.assoc_trade_club(p_trade text, p_region text) returns text language plpgsql security definer set search_path = '' as $$
declare cid text := 'tr.' || private.assoc_slug(p_trade) || '.' || lower(p_region);
begin
  insert into public.association_clubs (id, name, trade_name, region, monthly_fee, discount_cap, standards)
    values (cid, p_region || ' ' || p_trade || ' Association', p_trade, p_region, 40, 0.06, '{goodName,staffPaid,outOfTheRed,taxCurrent}') on conflict do nothing;
  return cid;
end $$;

create function private.assoc_rate(members int, cap numeric) returns numeric language sql immutable as $$
  select case when members <= 0 then 0 else least(cap, 0.08, 0.01 + 0.001 * members) end;
$$;

create function private.assoc_members(cid text) returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.association_members where club_id = cid;
$$;

create function private.assoc_breaches(standards public.association_standard[], reputation numeric, weeks_negative int, wage_shortfall numeric, tax_due boolean)
returns public.association_standard[] language sql immutable as $$
  select coalesce(array_agg(s), '{}') from unnest(standards) s
   where (s = 'goodName' and reputation < 45) or (s = 'staffPaid' and wage_shortfall > 0)
      or (s = 'outOfTheRed' and weeks_negative > 3) or (s = 'taxCurrent' and tax_due);
$$;

create function private.assoc_club_json(c public.association_clubs) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'name', c.name, 'tradeName', c.trade_name, 'region', c.region, 'monthlyFee', c.monthly_fee, 'discountCap', c.discount_cap,
    'standards', to_jsonb(c.standards), 'members', private.assoc_members(c.id), 'rate', private.assoc_rate(private.assoc_members(c.id), c.discount_cap));
$$;

create function public.clubs_for_company(p_trade text, p_region text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); cid text;
begin
  if p_region !~ '^[A-Z]{2}$' or char_length(coalesce(p_trade, '')) not between 1 and 40 then raise exception 'invalid_company' using errcode = 'P0001'; end if;
  cid := private.assoc_trade_club(p_trade, p_region);
  return coalesce((select jsonb_agg(private.assoc_club_json(c) order by (c.id <> cid), c.name) from public.association_clubs c where c.id = cid or c.trade_name is null), '[]'::jsonb);
end $$;

create function public.join_club(p_club text, p_company_key text, p_trade text, p_city text, p_region text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); c public.association_clubs; ban timestamptz;
begin
  perform private.require_free(uid, 'trade');
  if p_region !~ '^[A-Z]{2}$' or char_length(coalesce(p_trade, '')) not between 1 and 40 then raise exception 'invalid_company' using errcode = 'P0001'; end if;
  select * into c from public.association_clubs where id = p_club;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if c.trade_name is not null and (private.assoc_slug(c.trade_name) <> private.assoc_slug(p_trade) or c.region <> p_region) then raise exception 'not_eligible' using errcode = 'P0001'; end if;
  select until into ban from public.association_bans where owner_id = uid and company_key = p_company_key and club_id = c.id;
  if ban is not null and ban > now() then raise exception 'removed_until:%', ban using errcode = 'P0001'; end if;
  if exists (select 1 from public.association_members where owner_id = uid and company_key = p_company_key) then raise exception 'already_member' using errcode = 'P0001'; end if;
  insert into public.association_members (club_id, owner_id, company_key, trade_name, city) values (c.id, uid, p_company_key, p_trade, coalesce(p_city, ''));
  return private.assoc_club_json(c);
end $$;

create function public.leave_club(p_company_key text) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  delete from public.association_members where owner_id = uid and company_key = p_company_key;
end $$;

create function public.report_association_standing(p_company_key text, p_reputation numeric, p_weeks_negative int, p_wage_shortfall numeric, p_tax_due boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); m public.association_members; c public.association_clubs; b public.association_standard[];
begin
  select * into m from public.association_members where owner_id = uid and company_key = p_company_key;
  if not found then return jsonb_build_object('member', false, 'breaches', '[]'::jsonb); end if;
  select * into c from public.association_clubs where id = m.club_id;
  b := private.assoc_breaches(c.standards, p_reputation, p_weeks_negative, p_wage_shortfall, p_tax_due);
  if cardinality(b) > 0 then
    delete from public.association_members where owner_id = uid and company_key = p_company_key;
    insert into public.association_bans (owner_id, company_key, club_id, until, breaches) values (uid, p_company_key, c.id, now() + private.weeks(8), b)
      on conflict (owner_id, company_key, club_id) do update set until = excluded.until, breaches = excluded.breaches;
    return jsonb_build_object('member', false, 'removed', true, 'breaches', to_jsonb(b), 'until', now() + private.weeks(8));
  end if;
  return jsonb_build_object('member', true, 'breaches', '[]'::jsonb, 'club', private.assoc_club_json(c));
end $$;

create function public.my_club(p_company_key text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); c public.association_clubs;
begin
  select ac.* into c from public.association_members m join public.association_clubs ac on ac.id = m.club_id where m.owner_id = uid and m.company_key = p_company_key;
  if not found then return null; end if;
  return private.assoc_club_json(c);
end $$;

create function public.club_members(p_club text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.owner_id, 'profile', private.profile_json(uid, x.owner_id),
        'line', case when x.privacy = 'public' or private.are_friends(uid, x.owner_id) or x.owner_id = uid then x.trade_name || case when x.city <> '' then ' in ' || x.city else '' end end) order by x.display_name)
    from (select m.owner_id, m.trade_name, m.city, p.privacy, p.display_name from public.association_members m join public.profiles p on p.id = m.owner_id
           where m.club_id = p_club and p.deleted_at is null and (p.privacy <> 'private' or p.id = uid) and not private.is_blocked_between(uid, p.id)) x), '[]'::jsonb);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.clubs_for_company(text, text), public.join_club(text, text, text, text, text), public.leave_club(text),
  public.report_association_standing(text, numeric, int, numeric, boolean), public.my_club(text), public.club_members(text) to authenticated;
