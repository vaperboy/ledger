create table if not exists public.device_tokens (
  token text primary key check (char_length(token) between 32 and 400),
  user_id uuid not null references public.profiles (id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  categories text[] not null default '{auction,supplier,gift,race,daily}',
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user on public.device_tokens (user_id);

create table if not exists public.push_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  category text not null check (category in ('auction', 'supplier', 'gift', 'race', 'daily')),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 240),
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index if not exists push_outbox_pending on public.push_outbox (id) where sent_at is null;

alter table public.device_tokens enable row level security;
alter table public.push_outbox enable row level security;
revoke all on public.device_tokens, public.push_outbox from anon, authenticated;
grant select, delete on public.device_tokens to authenticated;
drop policy if exists device_tokens_owner_select on public.device_tokens;
drop policy if exists device_tokens_owner_delete on public.device_tokens;
create policy device_tokens_owner_select on public.device_tokens for select to authenticated using (user_id = auth.uid());
create policy device_tokens_owner_delete on public.device_tokens for delete to authenticated using (user_id = auth.uid());

create or replace function public.register_push_token(p_token text, p_environment text, p_categories text[]) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if p_token is null or char_length(p_token) not between 32 and 400 or p_environment not in ('sandbox', 'production') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  insert into public.device_tokens (token, user_id, environment, categories)
    values (p_token, uid, p_environment, coalesce(p_categories, '{}'::text[]))
    on conflict (token) do update set user_id = uid, environment = excluded.environment, categories = excluded.categories, updated_at = now();
end;
$$;
revoke all on function public.register_push_token(text, text, text[]) from public, anon;
grant execute on function public.register_push_token(text, text, text[]) to authenticated;

create or replace function private.queue_push(p_user uuid, p_category text, p_title text, p_body text) returns void language sql security definer set search_path = '' as $$
  insert into public.push_outbox (user_id, category, title, body)
  select p_user, p_category, p_title, p_body
   where exists (select 1 from public.device_tokens d where d.user_id = p_user and p_category = any (d.categories));
$$;

create or replace function private.push_on_bid() returns trigger language plpgsql security definer set search_path = '' as $$
declare prev uuid;
begin
  select b.bidder_id into prev from public.auction_bids b
   where b.auction_id = new.auction_id and b.id < new.id and b.bidder_id is distinct from new.bidder_id
   order by b.id desc limit 1;
  if prev is not null then perform private.queue_push(prev, 'auction', 'You were outbid', 'Someone raised the bid on an auction you are in.'); end if;
  return new;
end;
$$;

create or replace function private.push_on_auction_notice() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'winner' and new.status = 'sold' then
    perform private.queue_push(new.user_id, 'auction', 'You won the auction', 'Collect your piece in the market.');
  end if;
  return new;
end;
$$;

create or replace function private.push_on_contract() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.queue_push(new.supplier_id, 'supplier', 'New supply request', 'A buyer signed up for your supply line.');
  return new;
end;
$$;

create or replace function private.push_on_gift() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.queue_push(new.recipient_id, 'gift', 'A gift from ' || new.sender_name, 'Open Ledger to accept it.');
  return new;
end;
$$;

drop trigger if exists push_on_bid on public.auction_bids;
create trigger push_on_bid after insert on public.auction_bids for each row execute function private.push_on_bid();
drop trigger if exists push_on_auction_notice on public.auction_notices;
create trigger push_on_auction_notice after insert on public.auction_notices for each row execute function private.push_on_auction_notice();
drop trigger if exists push_on_contract on public.supply_contracts;
create trigger push_on_contract after insert on public.supply_contracts for each row execute function private.push_on_contract();
drop trigger if exists push_on_gift on public.friend_gifts;
create trigger push_on_gift after insert on public.friend_gifts for each row execute function private.push_on_gift();
