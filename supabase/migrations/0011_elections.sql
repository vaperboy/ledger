create type public.election_status as enum ('nomination', 'voting', 'closed');

create table public.elections (
  id uuid primary key default gen_random_uuid(),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  office text not null default 'president' check (office in ('president')),
  status public.election_status not null default 'nomination',
  nominate_until timestamptz not null,
  voting_until timestamptz not null,
  winner_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint election_window check (voting_until > nominate_until)
);
create unique index elections_one_running on public.elections (country_code, office) where status <> 'closed';

create table public.election_candidates (
  election_id uuid not null references public.elections (id) on delete cascade,
  candidate_id uuid not null references public.profiles (id) on delete cascade,
  manifesto text not null default '' check (char_length(manifesto) <= 300),
  nominated_at timestamptz not null default now(),
  primary key (election_id, candidate_id)
);

create table public.election_voters (
  election_id uuid not null references public.elections (id) on delete cascade,
  voter_id uuid not null references public.profiles (id) on delete cascade,
  link_key text not null,
  primary key (election_id, voter_id),
  unique (election_id, link_key)
);

create table public.election_ballots (
  id uuid primary key default gen_random_uuid(),
  election_id uuid not null references public.elections (id) on delete cascade,
  candidate_id uuid not null,
  foreign key (election_id, candidate_id) references public.election_candidates (election_id, candidate_id) on delete cascade
);
create index election_ballots_election on public.election_ballots (election_id, candidate_id);

alter table public.elections enable row level security;
alter table public.election_candidates enable row level security;
alter table public.election_voters enable row level security;
alter table public.election_ballots enable row level security;
revoke all on public.elections, public.election_candidates, public.election_voters, public.election_ballots from anon, authenticated;
grant select on public.elections, public.election_candidates, public.election_voters to authenticated;
create policy elections_read on public.elections for select to authenticated using (true);
create policy election_candidates_read on public.election_candidates for select to authenticated using (true);
create policy election_voters_own on public.election_voters for select to authenticated using (voter_id = auth.uid());

create function private.may_vote(uid uuid, cc text) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = uid and deleted_at is null and not is_simulated and country_code = cc and created_at < now() - private.weeks(4))
     and not private.is_barred(uid, 'vote');
$$;
create function private.may_stand(uid uuid, cc text) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = uid and deleted_at is null and not is_simulated and country_code = cc and created_at < now() - private.weeks(8))
     and not private.is_barred(uid, 'stand');
$$;

create function private.run_election_cycle() returns int language plpgsql security definer set search_path = '' as $$
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
      update public.elections set status = 'closed', winner_id = win where id = e.id;
      if win is not null then
        insert into public.country_offices (country_code, office, holder_id, term_start, term_end) values (e.country_code, e.office, win, now(), now() + private.weeks(12))
          on conflict (country_code, office) do update set holder_id = excluded.holder_id, term_start = excluded.term_start, term_end = excluded.term_end;
      end if;
      n := n + 1;
    end if;
  end loop;
  for cc in select distinct p.country_code from public.profiles p where p.deleted_at is null and not p.is_simulated loop
    continue when exists (select 1 from public.elections where country_code = cc.country_code and status <> 'closed');
    continue when exists (select 1 from public.country_offices where country_code = cc.country_code and term_end > now() and holder_id is not null);
    continue when exists (select 1 from public.elections where country_code = cc.country_code and status = 'closed' and created_at > now() - private.weeks(2));
    insert into public.elections (country_code, nominate_until, voting_until) values (cc.country_code, now() + private.weeks(7), now() + private.weeks(14));
    n := n + 1;
  end loop;
  return n;
end $$;

create function public.election_state(p_country text default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); cc text := coalesce(p_country, (select country_code from public.profiles where id = uid)); e public.elections;
begin
  select * into e from public.elections where country_code = cc order by created_at desc limit 1;
  if not found then return jsonb_build_object('country', cc, 'election', null); end if;
  return jsonb_build_object('country', cc, 'election', jsonb_build_object('id', e.id, 'office', e.office, 'status', e.status, 'nominateUntil', e.nominate_until,
    'votingUntil', e.voting_until, 'winnerID', e.winner_id, 'winnerName', case when e.winner_id is null then null else private.display_name(e.winner_id) end,
    'turnout', case when e.status = 'closed' then (select count(*) from public.election_ballots where election_id = e.id) else null end,
    'iVoted', exists (select 1 from public.election_voters where election_id = e.id and voter_id = uid),
    'canVote', e.status = 'voting' and private.may_vote(uid, e.country_code),
    'canStand', e.status = 'nomination' and private.may_stand(uid, e.country_code),
    'candidates', coalesce((select jsonb_agg(jsonb_build_object('id', c.candidate_id, 'name', private.display_name(c.candidate_id), 'manifesto', c.manifesto,
        'level', (select level from public.profiles where id = c.candidate_id), 'convictions', private.conviction_count(c.candidate_id), 'votes', case when e.status = 'closed' then
            (select count(*) from public.election_ballots b where b.election_id = e.id and b.candidate_id = c.candidate_id) else null end) order by c.nominated_at)
       from public.election_candidates c where c.election_id = e.id and not private.is_blocked_between(uid, c.candidate_id)), '[]'::jsonb)));
end $$;

create function public.stand_for_election(p_election uuid, p_manifesto text default '') returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); e public.elections;
begin
  select * into e from public.elections where id = p_election for update;
  if not found or e.status <> 'nomination' or now() >= e.nominate_until then raise exception 'not_open' using errcode = 'P0001'; end if;
  if not private.may_stand(uid, e.country_code) then raise exception 'not_eligible' using errcode = 'P0001'; end if;
  insert into public.election_candidates (election_id, candidate_id, manifesto) values (e.id, uid, coalesce(p_manifesto, ''))
    on conflict (election_id, candidate_id) do update set manifesto = excluded.manifesto;
end $$;

create function public.withdraw_candidacy(p_election uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player();
begin
  if not exists (select 1 from public.elections where id = p_election and status = 'nomination') then raise exception 'not_open' using errcode = 'P0001'; end if;
  delete from public.election_candidates where election_id = p_election and candidate_id = uid;
end $$;

create function public.cast_ballot(p_election uuid, p_candidate uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); e public.elections;
begin
  select * into e from public.elections where id = p_election for update;
  if not found or e.status <> 'voting' or now() >= e.voting_until then raise exception 'not_open' using errcode = 'P0001'; end if;
  if not private.may_vote(uid, e.country_code) then raise exception 'not_eligible' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.election_candidates where election_id = e.id and candidate_id = p_candidate) then raise exception 'not_found' using errcode = 'P0001'; end if;
  begin
    insert into public.election_voters (election_id, voter_id, link_key) values (e.id, uid, private.link_key(uid));
  exception when unique_violation then
    raise exception 'already_voted' using errcode = 'P0001';
  end;
  insert into public.election_ballots (election_id, candidate_id) values (e.id, p_candidate);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.election_state(text), public.stand_for_election(uuid, text), public.withdraw_candidacy(uuid), public.cast_ballot(uuid, uuid) to authenticated;
