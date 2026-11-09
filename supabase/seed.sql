-- Development seed: invented simulated players only, no real user data. profiles.id references auth.users, so each gets a
-- placeholder auth row that cannot sign in (no email, no password, banned).
do $$
declare r record; uid uuid;
begin
  for r in select * from (values
    ('Mara Voss',    'GB', 4, 'public',  array['First Profit']),
    ('Tomas Reyes',  'ES', 7, 'friends', array['Ten Hires','Debt Free']),
    ('Aiko Tanaka',  'JP', 2, 'private', array[]::text[]),
    ('Ines Okafor',  'NG', 9, 'public',  array['Export Pioneer']),
    ('Lukas Brandt', 'DE', 5, 'public',  array['First Profit','Ten Hires'])
  ) as t(n, c, lvl, pr, bd) loop
    uid := gen_random_uuid();
    insert into auth.users (id, aud, role, banned_until, created_at, updated_at)
      values (uid, 'authenticated', 'authenticated', 'infinity', now(), now());
    insert into public.profiles (id, display_name, country_code, level, privacy, badges, game_week, trades_completed, is_simulated)
      values (uid, r.n, r.c, r.lvl, r.pr::public.privacy_level, r.bd, r.lvl * 12, r.lvl * 3, true);
    insert into public.companies_public (owner_id, company_key, name, trade, city, country, health)
      values (uid, 'seed-1', r.n || ' & Co', 'Bakery', 'Springfield', r.c, 'steady');
  end loop;
end $$;
