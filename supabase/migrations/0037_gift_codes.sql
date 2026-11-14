-- Gift codes in the one redeem field. A gift code carries gold, cosmetics and/or boxes, an optional expiry and a number of
-- uses (one for a personal gift, many for a promo code). Every account can use a given code once. Codes are stored hashed
-- exactly like administrator and beta codes; supabase/tools/make_codes.py gift makes them.

alter table private.redeem_codes drop constraint redeem_codes_kind_check;
alter table private.redeem_codes add constraint redeem_codes_kind_check check (kind in ('admin', 'beta', 'gift'));

-- What a gift code gives and how far it goes. used_count only grows, inside the same transaction as the redemption.
create table private.gift_codes (
  code_id uuid primary key references private.redeem_codes (id) on delete cascade,
  gold int not null default 0 check (gold >= 0 and gold <= 1000000),
  items text[] not null default '{}',
  boxes jsonb not null default '{}'::jsonb,
  max_uses int not null default 1 check (max_uses between 1 and 1000000),
  used_count int not null default 0 check (used_count >= 0),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  check (gold > 0 or cardinality(items) > 0 or boxes <> '{}'::jsonb)
);

-- One row per account and code: the primary key is what makes a code work once per account.
create table private.gift_redemptions (
  code_id uuid not null references private.gift_codes (code_id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  at timestamptz not null default now(),
  primary key (code_id, user_id)
);
create index gift_redemptions_user on private.gift_redemptions (user_id);

revoke all on private.gift_codes, private.gift_redemptions from public, anon, authenticated;

-- Checks a gift's contents against the server catalogue: boxes must be known box kinds; cosmetics must be sold or won in
-- boxes, the store or the avatar shop, and never a Battle Pass reward (the pass is the only way to get those).
create or replace function private.gift_check(p_items text[], p_boxes jsonb) returns void
language plpgsql stable security definer set search_path = '' as $$
declare i text; b record;
begin
  foreach i in array coalesce(p_items, '{}'::text[]) loop
    if not exists (select 1 from private.store_cosmetics c where c.id = i and c.source in ('box', 'store', 'avatar'))
       or exists (select 1 from private.store_pass_rewards r where r.reward_id = i) then
      raise exception 'invalid_gift_item:%', i using errcode = 'P0001';
    end if;
  end loop;
  if (select count(*) from unnest(coalesce(p_items, '{}'::text[])) x) <> (select count(distinct x) from unnest(coalesce(p_items, '{}'::text[])) x) then
    raise exception 'duplicate_gift_item' using errcode = 'P0001';
  end if;
  if p_boxes is null or jsonb_typeof(p_boxes) <> 'object' then raise exception 'invalid_gift_boxes' using errcode = 'P0001'; end if;
  for b in select key, value from jsonb_each(p_boxes) loop
    if not exists (select 1 from private.store_box_kinds k where k.kind = b.key)
       or jsonb_typeof(b.value) <> 'number' or b.value::text !~ '^[0-9]+$' or (b.value::text)::int not between 1 and 100 then
      raise exception 'invalid_gift_box:%', b.key using errcode = 'P0001';
    end if;
  end loop;
end $$;
revoke execute on function private.gift_check(text[], jsonb) from public, anon, authenticated;

-- Adds gift codes from make_codes.py: each entry is 'salt:hash' in lower-case hex and every code gets the same reward.
-- p_expiry is the last day the code works (UTC), or null for no expiry. Returns how many were new.
create or replace function private.add_gift_codes(p_hashes text[], p_gold int, p_items text[], p_boxes jsonb, p_uses int, p_expiry date)
returns int language plpgsql security definer set search_path = '' as $$
declare h text; n int := 0; v_id uuid;
begin
  if coalesce(p_gold, 0) < 0 or coalesce(p_gold, 0) > 1000000 then raise exception 'invalid_gift_gold' using errcode = 'P0001'; end if;
  if p_uses is null or p_uses not between 1 and 1000000 then raise exception 'invalid_gift_uses' using errcode = 'P0001'; end if;
  if coalesce(p_gold, 0) = 0 and cardinality(coalesce(p_items, '{}'::text[])) = 0 and coalesce(p_boxes, '{}'::jsonb) = '{}'::jsonb then
    raise exception 'empty_gift' using errcode = 'P0001';
  end if;
  perform private.gift_check(coalesce(p_items, '{}'::text[]), coalesce(p_boxes, '{}'::jsonb));
  foreach h in array coalesce(p_hashes, '{}'::text[]) loop
    if h !~ '^[0-9a-f]{32}:[0-9a-f]{64}$' then raise exception 'invalid_hash' using errcode = 'P0001'; end if;
    insert into private.redeem_codes (kind, salt, code_hash) values ('gift', split_part(h, ':', 1), split_part(h, ':', 2))
      on conflict do nothing returning id into v_id;
    if v_id is not null then
      insert into private.gift_codes (code_id, gold, items, boxes, max_uses, expires_at)
        values (v_id, coalesce(p_gold, 0), coalesce(p_items, '{}'::text[]), coalesce(p_boxes, '{}'::jsonb), p_uses,
                case when p_expiry is null then null else (p_expiry + 1)::timestamp at time zone 'UTC' end);
      n := n + 1;
    end if;
    v_id := null;
  end loop;
  return n;
end $$;
revoke execute on function private.add_gift_codes(text[], int, text[], jsonb, int, date) from public, anon, authenticated;

-- One field for every code. An administrator code makes the account an administrator for good; a beta key pays gold
-- once per account; a gift code pays its reward once per account until it expires or its uses run out. Admin and beta
-- codes work once. At most store_extra('codeTriesPerHour') tries per account an hour.
-- A gift reply tells the app what was received: 'reward' = {gold, items (new ones only), boxes {kind: count}}.
create or replace function public.redeem_code(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); norm text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
        c private.redeem_codes; g private.gift_codes; v_gold int := 0; i text; b record; got int; v_new text[] := '{}'; v_reward jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('store:' || uid::text));
  delete from private.redeem_attempts where user_id = uid and at < now() - interval '1 day';
  if (select count(*) from private.redeem_attempts where user_id = uid and at > now() - interval '1 hour') >= private.store_extra('codeTriesPerHour') then
    return jsonb_build_object('ok', false, 'reason', 'locked');
  end if;
  insert into private.redeem_attempts (user_id) values (uid);
  if char_length(norm) not between 12 and 64 then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  select * into c from private.redeem_codes r
   where r.kind <> 'gift' and r.redeemed_at is null and r.code_hash = encode(extensions.digest(r.salt || ':' || norm, 'sha256'), 'hex')
   limit 1 for update skip locked;
  if not found then
    -- A gift code stays findable after use so a second try on the same account gets its own answer.
    select * into c from private.redeem_codes r
     where r.kind = 'gift' and r.code_hash = encode(extensions.digest(r.salt || ':' || norm, 'sha256'), 'hex')
     limit 1;
    if not found then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  end if;
  if c.kind = 'admin' then
    if private.is_admin(uid) then return jsonb_build_object('ok', true, 'kind', 'admin', 'reason', 'already_admin', 'state', private.store_state_for(uid)); end if;
    update private.redeem_codes set redeemed_by = uid, redeemed_at = now() where id = c.id;
    insert into public.admins (user_id) values (uid) on conflict do nothing;
    perform private.admin_grant_all(uid);
    perform private.audit(uid, 'admin_granted', uid::text, null, jsonb_build_object('code', c.id), 'one-time code redeemed');
    perform private.refresh_supporter(uid);
  elsif c.kind = 'beta' then
    if exists (select 1 from private.redeem_codes where kind = 'beta' and redeemed_by = uid) then
      return jsonb_build_object('ok', false, 'kind', 'beta', 'reason', 'beta_used');
    end if;
    update private.redeem_codes set redeemed_by = uid, redeemed_at = now() where id = c.id;
    v_gold := private.store_extra('betaGold');
    perform private.store_credit(uid, v_gold, 'beta_key', c.id::text);
    perform private.refresh_supporter(uid);
  else
    -- The lock on the gift row makes the use count exact when many players redeem a promo code at once.
    select * into g from private.gift_codes x where x.code_id = c.id for update;
    if not found then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
    if exists (select 1 from private.gift_redemptions d where d.code_id = c.id and d.user_id = uid) then
      return jsonb_build_object('ok', false, 'kind', 'gift', 'reason', 'gift_used');
    end if;
    if g.expires_at is not null and g.expires_at <= now() then return jsonb_build_object('ok', false, 'kind', 'gift', 'reason', 'expired'); end if;
    if g.used_count >= g.max_uses then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
    -- Cosmetics are re-checked now in case the catalogue changed since the code was made.
    perform private.gift_check(g.items, g.boxes);
    if g.gold = 0 and g.boxes = '{}'::jsonb and not exists (
         select 1 from unnest(g.items) x where not exists (select 1 from public.cosmetic_grants k where k.user_id = uid and k.cosmetic_id = x)) then
      return jsonb_build_object('ok', false, 'kind', 'gift', 'reason', 'owned');
    end if;
    insert into private.gift_redemptions (code_id, user_id) values (c.id, uid);
    update private.gift_codes set used_count = used_count + 1 where code_id = c.id;
    v_gold := g.gold;
    perform private.store_credit(uid, v_gold, 'gift_code', c.id::text);
    foreach i in array g.items loop
      insert into public.cosmetic_grants (user_id, cosmetic_id, source) values (uid, i, 'gift') on conflict do nothing;
      get diagnostics got = row_count;
      if got > 0 then v_new := v_new || i; end if;
    end loop;
    for b in select key, (value::text)::int as n from jsonb_each(g.boxes) loop
      perform private.add_boxes(uid, b.key, b.n);
    end loop;
    v_reward := jsonb_build_object('gold', v_gold, 'items', to_jsonb(v_new), 'boxes', g.boxes);
    perform private.refresh_supporter(uid);
    return jsonb_build_object('ok', true, 'kind', 'gift', 'reason', 'granted', 'gold', v_gold, 'reward', v_reward, 'state', private.store_state_for(uid));
  end if;
  return jsonb_build_object('ok', true, 'kind', c.kind, 'reason', 'granted', 'gold', v_gold, 'state', private.store_state_for(uid));
end $$;

revoke execute on function public.redeem_code(text) from public, anon;
grant execute on function public.redeem_code(text) to authenticated;
