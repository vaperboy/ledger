-- Deleting an account always works: whatever the player still has open with other players is settled first, then the account is removed.
-- The player's own side of a settlement can no longer be booked, so other players are made whole without anyone gaining from the deletion.

create or replace function private.acct_count(n bigint, one text, many text) returns text language sql immutable as $$
  select n::text || ' ' || case when n = 1 then one else many end;
$$;

-- What a partner put into a venture: the price of the stake plus capital calls, from the money the server moved.
create or replace function private.acct_paid_in(member uuid, vid uuid) returns numeric language sql stable security definer set search_path = '' as $$
  select greatest(0, -coalesce(sum(amount), 0)) from public.settlements
   where recipient_id = member and ref = vid::text and kind in ('venture_stake', 'venture_capital_call');
$$;

-- What a partner is paid when the venture's owner leaves: the value of the shares, but never more than the partner put in.
create or replace function private.acct_venture_payout(v public.ventures, member uuid, member_shares int) returns numeric
language sql stable security definer set search_path = '' as $$
  select least(floor(greatest(v.value, 0) * member_shares / nullif(private.jv_total_shares(v.id), 0) * 100) / 100,
               private.acct_paid_in(member, v.id));
$$;

-- The plain list of everything deleting this account settles, shown before the player confirms.
create or replace function private.acct_obligations(uid uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare items jsonb := '[]'::jsonb; r record; n bigint; g bigint;
begin
  for r in select v.name, count(p.member_id) filter (where p.member_id <> uid and not coalesce(q.is_bot, false)) as partners
             from public.ventures v left join public.venture_partners p on p.venture_id = v.id left join public.profiles q on q.id = p.member_id
            where v.chair_id = uid and v.dissolved_at is null group by v.id, v.name order by v.name loop
    items := items || to_jsonb(case when r.partners = 0 then 'Your shared company ' || r.name || ' is closed.'
      else r.name || ' is closed. ' || case when r.partners = 1 then 'Your partner gets' else 'Your ' || r.partners || ' partners get' end
           || ' back what they paid in, up to what their shares are worth.' end);
  end loop;
  for r in select v.name, round(100.0 * p.shares / nullif(private.jv_total_shares(v.id), 0), 1) as pct
             from public.venture_partners p join public.ventures v on v.id = p.venture_id
            where p.member_id = uid and v.chair_id <> uid and v.dissolved_at is null order by v.name loop
    items := items || to_jsonb('Your ' || r.pct || '% of ' || r.name || ' goes back to its owner without payment.');
  end loop;

  select count(*) into n from public.supply_contracts where ended_at is null and (supplier_id = uid or buyer_id = uid);
  if n > 0 then items := items || to_jsonb(private.acct_count(n, 'supply deal ends.', 'supply deals end.')); end if;
  select count(*) into n from public.supply_listings where owner_id = uid and not stopped;
  if n > 0 then items := items || to_jsonb(private.acct_count(n, 'supply offer is taken down.', 'supply offers are taken down.')); end if;

  for r in select name from public.startups where founder_id = uid and status in ('raising', 'live') order by name loop
    items := items || to_jsonb('Your startup ' || r.name || ' closes. Money held for its investors goes back to them.');
  end loop;
  select count(*) into n from public.startup_investments where investor_id = uid and not released and not refunded;
  if n > 0 then items := items || to_jsonb(private.acct_count(n, 'startup investment still held is given up.', 'startup investments still held are given up.')); end if;
  select count(*) into n from public.startup_holdings where owner_id = uid;
  if n > 0 then items := items || to_jsonb(private.acct_count(n, 'startup stake is given up.', 'startup stakes are given up.')); end if;

  for r in select name from public.exchange_listings where owner_id = uid and delisted_at is null order by name loop
    items := items || to_jsonb(r.name || ' leaves the exchange. Other shareholders get back what they paid, up to what their shares are worth.');
  end loop;
  select count(*) into n from public.exchange_holdings h join public.exchange_listings l on l.id = h.listing_id
   where h.owner_id = uid and l.owner_id <> uid and h.shares > 0 and l.delisted_at is null;
  if n > 0 then items := items || to_jsonb('Your shares in ' || private.acct_count(n, 'listed company go', 'listed companies go') || ' back to their owners without payment.'); end if;
  select count(*) into n from public.exchange_orders where trader_id = uid and status = 'open';
  if n > 0 then items := items || to_jsonb(private.acct_count(n, 'exchange order is cancelled.', 'exchange orders are cancelled.')); end if;

  select count(*) into n from public.auctions where seller_id = uid and status = 'live';
  if n > 0 then items := items || to_jsonb(private.acct_count(n, 'auction ends without a sale.', 'auctions end without a sale.')); end if;
  select count(distinct a.id) into n from public.auction_bids b join public.auctions a on a.id = b.auction_id where b.bidder_id = uid and a.status = 'live';
  if n > 0 then items := items || to_jsonb('Your bids in ' || private.acct_count(n, 'auction are', 'auctions are') || ' taken back.'); end if;

  select count(*) into n from public.market_listings where seller_id = uid and status = 'active';
  if n > 0 then items := items || to_jsonb(private.acct_count(n, 'marketplace listing is taken down. Buyers waiting on it get their money back.', 'marketplace listings are taken down. Buyers waiting on them get their money back.')); end if;
  select count(*) into n from public.market_offers where buyer_id = uid and status in ('pending', 'discussing');
  if n > 0 then items := items || to_jsonb(private.acct_count(n, 'open marketplace request is withdrawn.', 'open marketplace requests are withdrawn.')); end if;

  select coalesce(balance, 0) into g from public.gold_wallets where user_id = uid;
  if coalesce(g, 0) > 0 then items := items || to_jsonb(private.acct_count(g, 'gold on your account is removed.', 'gold on your account is removed.')); end if;
  select count(*) into n from public.artifact_pieces where owner_id = uid;
  if n > 0 then items := items || to_jsonb(private.acct_count(n, 'collection piece is removed.', 'collection pieces are removed.')); end if;
  return items;
end $$;

-- Pays the human shareholders of a listing whose owner leaves: what they paid, at most what their shares are worth.
create or replace function private.acct_exchange_buyout(lid uuid) returns void language plpgsql security definer set search_path = '' as $$
declare l public.exchange_listings; r record; pay numeric;
begin
  select * into l from public.exchange_listings where id = lid;
  for r in select h.owner_id, h.shares, h.cost from public.exchange_holdings h join public.profiles q on q.id = h.owner_id
            where h.listing_id = l.id and h.owner_id <> l.owner_id and h.shares > 0 and not q.is_bot loop
    pay := least(round(l.value * r.shares / l.total_shares, 2), r.cost);
    if pay > 0 then
      perform private.settle(r.owner_id, pay, l.currency, 'exchange_buyout', l.id::text, 'Shares in ' || l.name || ' paid out because its owner left the game',
        jsonb_build_object('listingID', l.id, 'shares', r.shares));
    end if;
  end loop;
end $$;

-- Settles everything open with other players. Runs inside the deletion, so it either all happens or none of it does.
create or replace function private.acct_settle(uid uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v public.ventures; r record; pay numeric; ml public.market_listings;
begin
  -- Ventures this player owns close. Each human partner is paid out and the company leaves their game.
  for v in select * from public.ventures where chair_id = uid and dissolved_at is null order by id for update loop
    for r in select p.member_id, p.shares from public.venture_partners p join public.profiles q on q.id = p.member_id
              where p.venture_id = v.id and p.member_id <> uid and not q.is_bot loop
      pay := coalesce(private.acct_venture_payout(v, r.member_id, r.shares), 0);
      perform private.settle(r.member_id, pay, v.currency, 'venture_dissolved', v.id::text, v.name || ' closed because its owner left the game',
        jsonb_build_object('ventureID', v.id, 'reason', 'accountDeleted'));
    end loop;
    update public.venture_meetings set closed_at = now() where venture_id = v.id and closed_at is null;
    update public.venture_invites set status = 'expired' where venture_id = v.id and status = 'pending';
    update public.venture_buybacks set status = 'withdrawn', answered_at = now() where venture_id = v.id and status = 'pending';
    update public.ventures set dissolved_at = now() where id = v.id;
  end loop;

  -- A stake in someone else's venture goes back to its owner, as when a partner leaves; the owner's game sees the partner gone at no price.
  for r in select p.venture_id, p.shares from public.venture_partners p join public.ventures x on x.id = p.venture_id
            where p.member_id = uid and x.chair_id <> uid and x.dissolved_at is null order by p.venture_id loop
    select * into v from public.ventures where id = r.venture_id for update;
    update public.venture_partners set shares = shares + r.shares where venture_id = v.id and member_id = v.chair_id;
    delete from public.venture_partners where venture_id = v.id and member_id = uid;
    delete from public.venture_votes x using public.venture_items i, public.venture_meetings m
     where x.item_id = i.id and i.meeting_id = m.id and m.venture_id = v.id and m.closed_at is null and x.member_id = uid;
    update public.venture_buybacks set status = 'withdrawn', answered_at = now() where venture_id = v.id and seller_id = uid and status = 'pending';
  end loop;

  update public.supply_contracts set ended_at = now(), end_reason = 'accountDeleted'
   where ended_at is null and (supplier_id = uid or buyer_id = uid);
  update public.supply_listings set stopped = true where owner_id = uid and not stopped;

  -- A startup this player founded fails, which hands held money back to its investors.
  for r in select id from public.startups where founder_id = uid and status in ('raising', 'live') order by id loop
    perform private.cs_fail(r.id, 'failed');
  end loop;
  update public.startup_investments set refunded = true where investor_id = uid and not released and not refunded;
  update public.startup_offers set status = 'cancelled' where seller_id = uid and status = 'open';

  -- A listed company leaves the exchange. Human shareholders get back what they paid, at most what the shares are worth.
  update public.exchange_orders set status = 'cancelled' where trader_id = uid and status = 'open';
  for r in select * from public.exchange_listings where owner_id = uid and delisted_at is null order by id for update loop
    perform private.acct_exchange_buyout(r.id);
    update public.exchange_orders set status = 'cancelled' where listing_id = r.id and status = 'open';
    update public.exchange_listings set delisted_at = now() where id = r.id;
  end loop;
  -- Shares in other players' listed companies go back to the company's owner.
  for r in select h.listing_id, h.shares, l.owner_id as lister from public.exchange_holdings h join public.exchange_listings l on l.id = h.listing_id
            where h.owner_id = uid and l.owner_id <> uid and h.shares > 0 order by h.listing_id loop
    insert into public.exchange_holdings (listing_id, owner_id, shares, cost) values (r.listing_id, r.lister, r.shares, 0)
      on conflict (listing_id, owner_id) do update set shares = public.exchange_holdings.shares + excluded.shares;
    delete from public.exchange_holdings where listing_id = r.listing_id and owner_id = uid;
  end loop;

  -- Auctions: this player's live auctions end unsold, and their bids are taken back so the next bid leads.
  update public.artifact_pieces set in_auction = null where in_auction in (select id from public.auctions where seller_id = uid and status = 'live');
  update public.auctions set status = 'cancelled' where seller_id = uid and status = 'live';
  delete from public.auction_bids b using public.auctions a where a.id = b.auction_id and a.status = 'live' and b.bidder_id = uid;
  -- Old auctions by other sellers point at pieces this player now owns; they would stop the pieces from being removed.
  delete from public.auctions a using public.artifact_pieces p where p.owner_id = uid and a.def_id = p.def_id and a.serial = p.serial and a.seller_id <> uid;

  -- Marketplace: listings come down and waiting buyers get their money back; this player's own requests are withdrawn.
  for ml in select * from public.market_listings where seller_id = uid and status = 'active' order by id for update loop
    update public.market_listings set status = 'cancelled', closed_at = now() where id = ml.id;
    perform private.market_close_open(ml, ml.title || ' is no longer for sale because the seller left the game. Your money is back.', 'gone');
  end loop;
  for r in select o.id, o.listing_id, o.seller_id, l.title, l.currency from public.market_offers o join public.market_listings l on l.id = o.listing_id
            where o.buyer_id = uid and o.status in ('pending', 'discussing') order by o.id loop
    update public.market_offers set status = 'withdrawn', closed_at = now() where id = r.id;
    perform private.market_notice(r.seller_id, r.id::text || ':gone', 'Request withdrawn: ' || r.title,
      'The buyer left the game, so the request for ' || r.title || ' is closed.', 'n', r.currency, jsonb_build_object('dealID', r.id, 'listingID', r.listing_id));
  end loop;

  delete from public.username_reservations where owner_id = uid;
end $$;

create or replace function public.account_deletion_preview() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  return jsonb_build_object('items', private.acct_obligations(uid));
end $$;

create or replace function public.delete_my_account() returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  perform private.acct_settle(uid);
  update public.profiles set deleted_at = now(), display_name = 'Deleted player' where id = uid;
  delete from auth.users where id = uid;
end $$;

-- Every row the server keeps about the player, from every table that names them.
create or replace function private.acct_rows(q text, uid uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare res jsonb;
begin
  execute 'select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (' || q || ') t' into res using uid;
  return res;
end $$;

create or replace function public.export_my_data() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_user();
begin
  return jsonb_build_object(
    'exportedAt', now(),
    'account', (select jsonb_build_object('id', u.id, 'email', u.email, 'createdAt', u.created_at,
                  'signIns', coalesce((select jsonb_agg(i.provider) from auth.identities i where i.user_id = u.id), '[]'::jsonb))
                  from auth.users u where u.id = uid),
    'profile', (select to_jsonb(p) from public.profiles p where id = uid),
    'username', private.acct_rows('select name_key, claimed_at from public.username_reservations where owner_id = $1', uid),
    'companies', private.acct_rows('select * from public.companies_public where owner_id = $1', uid),
    'friendships', private.acct_rows('select * from public.friendships where requester_id = $1 or addressee_id = $1', uid),
    'blocks', private.acct_rows('select * from public.blocks where blocker_id = $1', uid),
    'reportsMade', private.acct_rows('select reason, note, status, created_at from public.reports where reporter_id = $1', uid),
    'saves', private.acct_rows('select slot, version, updated_at, char_length(payload) as size from public.save_blobs where user_id = $1', uid),
    'settlements', private.acct_rows('select * from public.settlements where recipient_id = $1 order by created_at', uid),
    'supplyListings', private.acct_rows('select * from public.supply_listings where owner_id = $1', uid),
    'supplyContracts', private.acct_rows('select * from public.supply_contracts where buyer_id = $1 or supplier_id = $1', uid),
    'supplyOrders', private.acct_rows('select o.* from public.supply_orders o join public.supply_contracts c on c.id = o.contract_id where c.buyer_id = $1 or c.supplier_id = $1', uid)) || jsonb_build_object(
    'startups', private.acct_rows('select * from public.startups where founder_id = $1', uid),
    'startupInvestments', private.acct_rows('select * from public.startup_investments where investor_id = $1', uid),
    'startupHoldings', private.acct_rows('select * from public.startup_holdings where owner_id = $1', uid),
    'startupOffers', private.acct_rows('select * from public.startup_offers where seller_id = $1', uid),
    'ventures', private.acct_rows('select v.* from public.ventures v where v.chair_id = $1 or exists (select 1 from public.venture_partners p where p.venture_id = v.id and p.member_id = $1)', uid),
    'ventureStakes', private.acct_rows('select * from public.venture_partners where member_id = $1', uid),
    'ventureInvites', private.acct_rows('select i.* from public.venture_invites i join public.ventures v on v.id = i.venture_id where i.invitee_id = $1 or v.chair_id = $1', uid),
    'ventureVotes', private.acct_rows('select * from public.venture_votes where member_id = $1', uid),
    'ventureBuybacks', private.acct_rows('select * from public.venture_buybacks where buyer_id = $1 or seller_id = $1', uid),
    'exchangeListings', private.acct_rows('select * from public.exchange_listings where owner_id = $1', uid),
    'exchangeHoldings', private.acct_rows('select * from public.exchange_holdings where owner_id = $1', uid),
    'exchangeOrders', private.acct_rows('select * from public.exchange_orders where trader_id = $1', uid),
    'exchangeTrades', private.acct_rows('select * from public.exchange_trades where buyer_id = $1 or seller_id = $1', uid)) || jsonb_build_object(
    'goldWallet', private.acct_rows('select * from public.gold_wallets where user_id = $1', uid),
    'goldLedger', private.acct_rows('select * from public.gold_ledger where user_id = $1 order by created_at', uid),
    'goldPurchases', private.acct_rows('select * from public.gold_purchases where user_id = $1', uid),
    'collectionPieces', private.acct_rows('select * from public.artifact_pieces where owner_id = $1', uid),
    'cosmetics', private.acct_rows('select * from public.cosmetic_grants where user_id = $1', uid),
    'auctions', private.acct_rows('select * from public.auctions where seller_id = $1 or winner_id = $1', uid),
    'auctionBids', private.acct_rows('select * from public.auction_bids where bidder_id = $1', uid),
    'auctionNotices', private.acct_rows('select * from public.auction_notices where user_id = $1', uid),
    'marketListings', private.acct_rows('select * from public.market_listings where seller_id = $1 or buyer_id = $1', uid),
    'marketDeals', private.acct_rows('select * from public.market_offers where buyer_id = $1 or seller_id = $1', uid)) || jsonb_build_object(
    'associations', private.acct_rows('select * from public.association_members where owner_id = $1', uid),
    'associationBans', private.acct_rows('select * from public.association_bans where owner_id = $1', uid),
    'events', private.acct_rows('select * from public.player_events where player_id = $1', uid),
    'activity', private.acct_rows('select * from public.player_activity where player_id = $1', uid),
    'offices', private.acct_rows('select * from public.country_offices where holder_id = $1', uid),
    'electionsWon', private.acct_rows('select * from public.elections where winner_id = $1', uid),
    'candidacies', private.acct_rows('select * from public.election_candidates where candidate_id = $1', uid),
    'votedIn', private.acct_rows('select * from public.election_voters where voter_id = $1', uid),
    'convictions', private.acct_rows('select * from public.convictions where player_id = $1', uid),
    'linkReward', private.acct_rows('select provider, gold, claimed_at from public.link_reward_claims where user_id = $1', uid),
    'admin', private.acct_rows('select * from public.admins where user_id = $1', uid),
    'adminActions', private.acct_rows('select * from public.admin_audit where actor_id = $1', uid),
    'leaderboard', private.acct_rows('select * from public.leaderboard_entries where user_id = $1', uid),
    'accountantOffice', private.acct_rows('select * from public.accountant_offices where owner_id = $1', uid),
    'accountantHires', private.acct_rows('select h.* from public.accountant_hires h left join public.accountant_offices o on o.id = h.office_id where h.client_id = $1 or o.owner_id = $1', uid),
    'deviceAndNetwork', private.acct_rows('select kind, hash, first_seen, last_seen from public.account_signals where user_id = $1', uid),
    'pushDevices', private.acct_rows('select * from public.device_tokens where user_id = $1', uid),
    'pushMessages', private.acct_rows('select * from public.push_outbox where user_id = $1', uid),
    'friendRace', private.acct_rows('select * from public.friend_race_scores where user_id = $1', uid),
    'friendGoals', private.acct_rows('select * from public.friend_goal_units where user_id = $1', uid),
    'friendGoalClaims', private.acct_rows('select * from public.friend_goal_claims where user_id = $1', uid),
    'gifts', private.acct_rows('select * from public.friend_gifts where sender_id = $1 or recipient_id = $1', uid),
    'friendNotes', private.acct_rows('select * from public.friend_notices where sender_id = $1 or recipient_id = $1', uid));
end $$;

revoke execute on function private.acct_count(bigint, text, text), private.acct_paid_in(uuid, uuid), private.acct_venture_payout(public.ventures, uuid, int),
  private.acct_obligations(uuid), private.acct_exchange_buyout(uuid), private.acct_settle(uuid), private.acct_rows(text, uuid) from public, anon, authenticated;
revoke execute on function public.account_deletion_preview(), public.delete_my_account(), public.export_my_data() from public, anon;
grant execute on function public.account_deletion_preview(), public.delete_my_account(), public.export_my_data() to authenticated;
