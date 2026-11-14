-- A company pays its quarterly policy dividend in the owner's own game. This passes the partners' part on to them.
create table public.venture_payouts (
  venture_id uuid not null references public.ventures (id) on delete cascade,
  ref text not null check (char_length(ref) between 1 and 40),
  amount numeric(18, 2) not null check (amount > 0),
  paid numeric(18, 2) not null default 0,
  created_at timestamptz not null default now(),
  primary key (venture_id, ref)
);
alter table public.venture_payouts enable row level security;
revoke all on public.venture_payouts from anon, authenticated;

-- Only under a dividend policy the owners voted for, at most once in twelve days, and never more than a fifth of the company's value,
-- so it cannot be used to hand money to a friend. The same ref is paid once.
create function public.pay_venture_dividend(p_venture uuid, p_amount numeric, p_ref text) returns numeric language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); v public.ventures; r record; tot numeric; part numeric; paid numeric := 0;
begin
  perform private.require_free(uid, 'trade');
  select * into v from public.ventures where id = p_venture and chair_id = uid and dissolved_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_ref is null or char_length(p_ref) not between 1 and 40 then raise exception 'invalid_amount' using errcode = 'P0001'; end if;
  if exists (select 1 from public.venture_payouts where venture_id = v.id and ref = p_ref) then return 0; end if;
  if v.dividend_policy = 'none' or p_amount is null or p_amount <= 0 or p_amount > v.value * 0.2 then raise exception 'invalid_amount' using errcode = 'P0001'; end if;
  if exists (select 1 from public.venture_payouts where venture_id = v.id and created_at > now() - interval '12 days') then
    raise exception 'too_soon' using errcode = 'P0001';
  end if;
  tot := private.jv_total_shares(v.id);
  if tot <= 0 then raise exception 'not_found' using errcode = 'P0001'; end if;
  for r in select member_id, shares from public.venture_partners where venture_id = v.id and member_id <> v.chair_id loop
    part := round(p_amount * r.shares / tot, 2);
    continue when part <= 0;
    perform private.settle(r.member_id, part, v.currency, 'venture_dividend', v.id::text, 'Dividend: ' || v.name, jsonb_build_object('ventureID', v.id));
    paid := paid + part;
  end loop;
  insert into public.venture_payouts (venture_id, ref, amount, paid) values (v.id, p_ref, round(p_amount, 2), paid);
  if paid > 0 then
    perform private.settle(v.chair_id, -paid, v.currency, 'venture_company_payout', v.id::text, 'Dividend paid to partners',
      jsonb_build_object('ventureID', v.id, 'companyKey', v.company_key));
  end if;
  return paid;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.pay_venture_dividend(uuid, numeric, text) to authenticated;
