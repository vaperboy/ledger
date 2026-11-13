-- Every supplier is a player company. The lines come from the one supply map (native/Engine/Sources/Businesses/Resources/supply_map.json);
-- where too few players supply a line, computer-run players open supplier companies with listings, and step back when real players cover it.
-- Contracts carry the buyer's need, worked out by the game; the buyer never picks a quantity.

alter table public.supply_contracts add column if not exists need int check (need is null or need >= 1);
alter table public.bots add column if not exists supplier boolean not null default false;

-- Lines: old line ids move to the new ones, dropped lines run out over a week.
alter table public.supply_listings drop constraint if exists listing_line_supplied;
create temporary table supply_line_moves (trade_id text, old_line text, new_line text);
insert into supply_line_moves (trade_id, old_line, new_line) values
  ('bakery','goods','bread'),
  ('bakery','pack',null),
  ('brewery','goods','beer'),
  ('brewery','pack',null),
  ('farm','goods','produce'),
  ('vineyard','goods','wine'),
  ('salmon','goods','fish'),
  ('factory','goods','parts'),
  ('factory','mat','parts'),
  ('factory','pack',null),
  ('furniture','goods','furn'),
  ('furniture','mat','furn'),
  ('grocery','goods',null),
  ('hardware','supplies','build'),
  ('hardware','parts','build'),
  ('hardware','pack',null),
  ('cleaning','laundry',null),
  ('carclean','clean','valet'),
  ('webdev','software',null),
  ('gamestudio','software',null),
  ('startup','software',null),
  ('carrepair','parts',null),
  ('carrepair','repair','carserv'),
  ('handy','repair','upkeep'),
  ('handy','parts',null),
  ('electrician','repair','upkeep'),
  ('electrician','parts',null),
  ('plumber','repair','upkeep'),
  ('plumber','parts',null),
  ('power','power',null),
  ('oilgas','power',null),
  ('courier','fuel',null);

-- Live listings that move: one per owner, company and new line (an owner keeps one live listing per company and line).
create temporary table supply_listing_moves as
  select distinct on (l.owner_id, l.company_key, mv.new_line) l.id, mv.new_line
    from public.supply_listings l join supply_line_moves mv on mv.trade_id = l.trade_id and mv.old_line = l.line_id
   where not l.stopped and mv.new_line is not null
     and not exists (select 1 from public.supply_listings o where o.owner_id = l.owner_id and o.company_key = l.company_key
                                                         and o.line_id = mv.new_line and not o.stopped)
   order by l.owner_id, l.company_key, mv.new_line, l.created_at desc;
-- The rest of the old lines run out over a week; their deals end then as expired.
update public.supply_listings l set expires_at = least(coalesce(l.expires_at, now() + interval '7 days'), now() + interval '7 days')
  from supply_line_moves mv
 where mv.trade_id = l.trade_id and mv.old_line = l.line_id and not l.stopped and l.id not in (select id from supply_listing_moves);
-- A buyer keeps one deal per company and line: the newest stays.
with cand as (
  select c.id, c.buyer_id, c.buyer_company_key, m.new_line as line, c.signed_at
    from public.supply_contracts c join supply_listing_moves m on m.id = c.listing_id where c.ended_at is null
  union all
  select c.id, c.buyer_id, c.buyer_company_key, c.line_id, c.signed_at from public.supply_contracts c
   where c.ended_at is null and c.line_id in (select new_line from supply_listing_moves) and c.listing_id not in (select id from supply_listing_moves)
), ranked as (select id, row_number() over (partition by buyer_id, buyer_company_key, line order by signed_at desc) as n from cand)
update public.supply_contracts set ended_at = now(), end_reason = 'replaced' where id in (select id from ranked where n > 1);
update public.supply_contracts c set line_id = m.new_line from supply_listing_moves m where c.listing_id = m.id and c.ended_at is null;
update public.supply_listings l set line_id = m.new_line from supply_listing_moves m where l.id = m.id;
drop table supply_listing_moves, supply_line_moves;

delete from public.supply_trade_lines;
insert into public.supply_trade_lines (trade_id, line_id) values
  ('bakery','bread'),('brewery','beer'),('carclean','valet'),('carrepair','carserv'),('cleaning','clean'),('courier','deliv'),('courier','parcel'),('electrician','upkeep'),
  ('factory','machines'),('factory','parts'),('farm','produce'),('fuelstation','fuel'),('furniture','furn'),('handy','upkeep'),('hardware','build'),('laundry','laundry'),
  ('mktg','ads'),('oilgas','fuel'),('plumber','upkeep'),('salmon','fish'),('security','guards'),('staffing','temp'),('trucking','freight'),('vineyard','wine'),
  ('wh3pl','whouse'),('wholesale','care'),('wholesale','food'),('wholesale','wares');
alter table public.supply_listings add constraint listing_line_supplied foreign key (trade_id, line_id)
  references public.supply_trade_lines (trade_id, line_id) not valid;

-- Where a supplier company of each country is, and what its owners are called.
create or replace function private.supply_places() returns table (country text, currency text, cities text[], first_names text[], last_names text[])
language sql immutable as $$
  values
    ('NO','NOK',array['Oslo','Bergen','Trondheim','Stavanger','Kristiansand','Tromsø'],array['Anders','Kari','Ola','Ingrid','Lars','Silje','Erik','Nora','Jonas','Emma','Henrik','Sofie','Magnus','Ida','Tobias','Maja'],array['Hansen','Johansen','Olsen','Larsen','Andersen','Pedersen','Nilsen','Jensen','Karlsen','Johnsen','Pettersen','Eriksen','Berg','Haugen','Hagen','Andreassen']),
    ('SE','SEK',array['Stockholm','Gothenburg','Malmö','Uppsala','Sundsvall'],array['Erik','Anna','Lars','Maria','Karl','Emma','Johan','Sara','Oskar','Elin','Nils','Ida','Axel','Maja','Gustav','Linnea'],array['Andersson','Johansson','Karlsson','Nilsson','Eriksson','Larsson','Olsson','Persson','Svensson','Gustafsson','Lindberg','Bergström','Lindgren','Berg','Holm','Nyström']),
    ('PL','PLN',array['Warsaw','Kraków','Wrocław','Gdańsk','Poznań'],array['Piotr','Anna','Jakub','Katarzyna','Michał','Agnieszka','Tomasz','Magdalena','Paweł','Ewa','Marek','Zofia','Łukasz','Julia','Krzysztof','Andrzej'],array['Nowak','Kowalski','Wiśniewski','Wójcik','Kowalczyk','Kamiński','Zieliński','Szymański','Woźniak','Dąbrowski','Kozłowski','Mazur','Krawczyk','Piotrowski','Grabowski','Pawłowski']),
    ('LT','EUR',array['Vilnius','Kaunas','Klaipėda','Šiauliai'],array['Jonas','Ona','Tomas','Rūta','Mantas','Gintarė','Andrius','Laura','Darius','Eglė','Lukas','Austėja','Paulius','Monika','Marius','Ieva'],array['Kazlauskas','Petrauskas','Jankauskas','Butkus','Paulauskas','Urbonas','Navickas','Žukauskas','Mockus','Šimkus','Rimkus','Pocius','Bagdonas','Adomaitis','Grigaitis','Vaitkus']),
    ('DE','EUR',array['Berlin','Hamburg','Munich','Cologne','Frankfurt'],array['Lukas','Anna','Jonas','Laura','Felix','Lea','Max','Marie','Paul','Sophie','Tim','Hannah','Jan','Lena','Tobias','Katharina'],array['Müller','Schmidt','Schneider','Fischer','Weber','Meyer','Wagner','Becker','Schulz','Hoffmann','Koch','Richter','Klein','Wolf']),
    ('UK','GBP',array['London','Manchester','Birmingham','Edinburgh','Bristol'],array['Oliver','Amelia','George','Olivia','Harry','Isla','Jack','Emily','Noah','Ava','Charlie','Mia','Thomas','Grace','Charlotte','Poppy'],array['Smith','Jones','Taylor','Brown','Williams','Wilson','Davies','Evans','Thomas','Johnson','Roberts','Walker','Wright','Hughes','Patel','Campbell']),
    ('FR','EUR',array['Paris','Lyon','Marseille','Toulouse','Nantes'],array['Lucas','Emma','Hugo','Léa','Louis','Chloé','Jules','Camille','Gabriel','Manon','Théo','Inès','Arthur','Sarah','Antoine','Julien'],array['Martin','Bernard','Dubois','Thomas','Robert','Richard','Petit','Durand','Leroy','Moreau','Simon','Laurent','Lefebvre','Fontaine']),
    ('ES','EUR',array['Madrid','Barcelona','Valencia','Seville','Bilbao'],array['Hugo','Lucía','Martín','Sofía','Pablo','Paula','Daniel','Valeria','Álvaro','Julia','Adrián','Carmen','Javier','Marta','Alejandro','Carlos'],array['García','Rodríguez','González','Fernández','López','Martínez','Sánchez','Pérez','Gómez','Ruiz','Hernández','Díaz','Moreno','Navarro']),
    ('NL','EUR',array['Amsterdam','Rotterdam','The Hague','Utrecht','Eindhoven'],array['Daan','Emma','Sem','Julia','Lucas','Sophie','Levi','Tess','Finn','Anna','Bram','Lotte','Jesse','Noor','Sanne','Thijs'],array['de Jong','Jansen','de Vries','van Dijk','Bakker','Janssen','Visser','Smit','Meijer','de Boer','Mulder','de Groot','Bos','Vos','Peters']),
    ('US','USD',array['New York','Los Angeles','Chicago','Houston','Denver'],array['James','Mary','Michael','Jennifer','Robert','Linda','David','Emily','Daniel','Ashley','Matthew','Jessica','Chris','Sarah','Megan','Lauren'],array['Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Martinez','Wilson','Anderson','Taylor','Thomas','Moore','Jackson','Martin']),
    ('CA','CAD',array['Toronto','Vancouver','Montréal','Calgary','Ottawa'],array['Liam','Olivia','Noah','Emma','Jackson','Charlotte','Lucas','Chloe','Ethan','Sophie','Logan','Ava','Mason','Zoe','Jacob','Mia'],array['Smith','Brown','Tremblay','Martin','Roy','Wilson','MacDonald','Gagnon','Johnson','Taylor','Campbell','Anderson','Singh','Chen','Bouchard','Morin']),
    ('AU','AUD',array['Sydney','Melbourne','Brisbane','Perth','Adelaide'],array['Oliver','Charlotte','William','Olivia','Jack','Amelia','Noah','Isla','Thomas','Mia','Lachlan','Matilda','Henry','Ruby','Cooper','Hunter'],array['Smith','Jones','Williams','Brown','Wilson','Taylor','Nguyen','Johnson','Martin','White','Thompson','Kelly','Anderson','Walker','Ryan','Campbell']),
    ('JP','JPY',array['Tokyo','Osaka','Nagoya','Fukuoka','Sapporo'],array['Haruto','Yui','Sota','Hina','Ren','Aoi','Yuto','Mei','Kaito','Sakura','Takumi','Rin','Daiki','Nana','Kenji','Emi'],array['Sato','Suzuki','Takahashi','Tanaka','Watanabe','Ito','Yamamoto','Nakamura','Kobayashi','Kato','Yoshida','Yamada','Sasaki','Matsumoto']),
    ('KR','KRW',array['Seoul','Busan','Incheon','Daegu','Daejeon'],array['Minjun','Seo-yeon','Jiho','Ha-eun','Joon','Ji-woo','Hyun','Soo-ah','Dong-hyun','Yuna','Tae-yang','Min-seo','Seung','Eun-ji','Seoyeon','Jiwoo'],array['Kim','Lee','Park','Choi','Jung','Kang','Cho','Yoon','Jang','Lim','Han','Oh','Seo','Shin']),
    ('BR','BRL',array['São Paulo','Rio de Janeiro','Brasília','Salvador','Curitiba'],array['Miguel','Helena','Arthur','Alice','Heitor','Laura','Gabriel','Manuela','Davi','Júlia','Pedro','Sophia','Lucas','Isabella','Ana','Beatriz'],array['Silva','Santos','Oliveira','Souza','Rodrigues','Ferreira','Alves','Pereira','Lima','Gomes','Costa','Ribeiro','Martins','Carvalho']),
    ('CH','CHF',array['Zurich','Geneva','Basel','Bern','Lausanne','Zug'],array['Noah','Mia','Liam','Emma','Luca','Sofia','Leon','Lina','Matteo','Elena','Lukas','Laura','Jonas','Anna','Nico','Lea'],array['Müller','Meier','Schmid','Keller','Weber','Huber','Schneider','Meyer','Steiner','Fischer','Gerber','Brunner','Baumann','Frei','Zimmermann','Favre']),
    ('MX','MXN',array['Mexico City','Guadalajara','Monterrey','Puebla','Tijuana','Cancún'],array['Santiago','Sofía','Mateo','Valentina','Sebastián','Regina','Leonardo','Camila','Emiliano','Ximena','Diego','Miguel','Fernanda','Alejandro','Daniela','José'],array['Hernández','García','Martínez','López','González','Pérez','Rodríguez','Sánchez','Ramírez','Cruz','Flores','Gómez','Morales','Vázquez','Reyes','Jiménez']),
    ('AE','AED',array['Dubai','Abu Dhabi','Sharjah','Al Ain','Ras Al Khaimah'],array['Mohammed','Fatima','Ahmed','Mariam','Omar','Aisha','Khalid','Noura','Rashid','Hessa','Rahul','Priya','Arjun','Anjali','Jose','Maria'],array['Al Nuaimi','Al Hashimi','Al Ketbi','Al Shamsi','Al Falasi','Al Suwaidi','Nair','Menon','Sharma','Pillai','Santos','Reyes','Khan','Hussain','Smith','Haddad']),
    ('IT','EUR',array['Rome','Milan','Naples','Turin','Palermo','Bologna'],array['Leonardo','Sofia','Francesco','Giulia','Aurora','Lorenzo','Ginevra','Mattia','Alice','Andrea','Beatrice','Gabriele','Martina','Matteo','Chiara','Tommaso'],array['Rossi','Russo','Ferrari','Esposito','Bianchi','Romano','Colombo','Ricci','Marino','Greco','Bruno','Gallo','Conti','De Luca','Mancini','Costa']),
    ('DK','DKK',array['Copenhagen','Aarhus','Odense','Aalborg','Esbjerg'],array['William','Ida','Noah','Emma','Oscar','Alma','Lucas','Ella','Carl','Freja','Victor','Karla','Malthe','Sofie','Frederik','Clara'],array['Nielsen','Jensen','Hansen','Pedersen','Andersen','Larsen','Sørensen','Rasmussen','Jørgensen','Petersen','Madsen','Kristensen','Olsen','Thomsen','Poulsen','Johansen']),
    ('FI','EUR',array['Helsinki','Espoo','Tampere','Oulu','Turku','Rovaniemi'],array['Leo','Aino','Eino','Olivia','Oliver','Helmi','Väinö','Isla','Elias','Eevi','Onni','Venla','Mikko','Sanna','Juha','Laura'],array['Korhonen','Virtanen','Mäkinen','Nieminen','Mäkelä','Hämäläinen','Laine','Heikkinen','Koskinen','Järvinen','Lehtonen','Lehtinen','Saarinen','Salminen','Heinonen','Niemi']),
    ('IE','EUR',array['Dublin','Cork','Limerick','Galway','Waterford'],array['Jack','Grace','Noah','Emily','James','Fiadh','Conor','Sophie','Oisín','Lucy','Seán','Ava','Cian','Ellie','Darragh','Aoife'],array['Murphy','Kelly','Walsh','Smith','Byrne','Ryan','Doyle','McCarthy','Gallagher','Kennedy','Lynch','Murray','Quinn','Moore']),
    ('SG','SGD',array['Central (CBD and Orchard)','Jurong','Tampines','Woodlands','Punggol','Sentosa'],array['Ethan','Chloe','Ryan','Sophia','Jayden','Emma','Lucas','Isabelle','Wei Jie','Hui Min','Jun Hao','Xin Yi','Muhammad','Arjun','Priya','Marcus'],array['Tan','Lim','Lee','Ng','Ong','Wong','Goh','Chua','Chan','Koh','Teo','Ang','Yeo','Tay','Ho','Low']);
$$;

-- How a supplier company of a trade is named, and what the trade is called.
create or replace function private.supply_trade_word(p_trade text, salt int) returns text language sql immutable as $$
  select coalesce((select ws[1 + abs(salt) % cardinality(ws)] from (values
    ('bakery',array['Bakery','Bakehouse','Bakers','Bread Co']),
    ('brewery',array['Brewing','Brewery','Brew Co','Ales']),
    ('carclean',array['Car Care','Valeting','Car Wash','Shine']),
    ('carrepair',array['Auto','Motors','Garage','Car Service']),
    ('cleaning',array['Cleaning','Cleaning Services','Clean Team','Facility Care']),
    ('courier',array['Couriers','Express','Delivery','Parcel']),
    ('electrician',array['Electrical','Electric','Power Installations','Wiring']),
    ('factory',array['Industries','Manufacturing','Engineering','Works']),
    ('farm',array['Farm','Farms','Growers','Produce']),
    ('fuelstation',array['Fuel','Service Station','Petrol','Energy Stop']),
    ('furniture',array['Furniture','Interiors','Woodworks','Design']),
    ('handy',array['Property Care','Handyman Service','Fix-It','Home Services']),
    ('hardware',array['Building Supplies','Builders Merchant','Timber & Tools','Trade Centre']),
    ('laundry',array['Laundry','Linen Service','Laundry Works','Wash House']),
    ('mktg',array['Media','Marketing','Creative','Agency']),
    ('oilgas',array['Energy','Petroleum','Oil','Fuels']),
    ('plumber',array['Plumbing','Pipe & Heating','Plumbers','Heating']),
    ('salmon',array['Seafood','Salmon','Aqua','Fisheries']),
    ('security',array['Security','Guarding','Protection','Watch']),
    ('staffing',array['Staffing','Recruitment','Temps','People']),
    ('trucking',array['Haulage','Freight','Transport','Trucking']),
    ('vineyard',array['Vineyards','Wine Estate','Winery','Cellars']),
    ('wh3pl',array['Logistics','Warehousing','Fulfilment','Storage']),
    ('wholesale',array['Wholesale','Trading','Distribution','Cash & Carry'])) as x(t, ws) where x.t = p_trade), 'Supply');
$$;
create or replace function private.supply_trade_name(p_trade text) returns text language sql immutable as $$
  select coalesce((select n from (values ('bakery','Bakery and pastry'), ('brewery','Craft brewery'), ('carclean','Mobile car cleaning'), ('carrepair','Car repair workshop'), ('cleaning','Cleaning company'), ('courier','Courier and last-mile delivery'), ('electrician','Electrical contractor'), ('factory','Manufacturing factory'), ('farm','Farm and forestry'), ('fuelstation','Filling station'), ('furniture','Furniture workshop'), ('handy','Handyman'), ('hardware','Building-supplies store'), ('laundry','Laundry service'), ('mktg','Marketing agency'), ('oilgas','Oil and gas company'), ('plumber','Plumbing firm'), ('salmon','Salmon farm'), ('security','Security company'), ('staffing','Staffing agency'), ('trucking','Freight trucking'), ('vineyard','Vineyard and winery'), ('wh3pl','Warehouse and fulfilment'), ('wholesale','Wholesaler')) as x(t, n) where x.t = p_trade), p_trade);
$$;
create or replace function private.supply_line_lead(p_line text) returns int language sql immutable as $$
  select coalesce((select d from (values ('food',3), ('care',3), ('wares',3), ('produce',3), ('bread',1), ('beer',3), ('wine',4), ('fish',2), ('parts',4), ('build',3), ('fuel',1), ('furn',10), ('upkeep',2), ('machines',3), ('carserv',1), ('valet',1), ('freight',2), ('parcel',1), ('deliv',0), ('whouse',2), ('clean',1), ('laundry',2), ('guards',2), ('temp',2), ('ads',5)) as x(l, d) where x.l = p_line), 2);
$$;

-- A supplier owner the world runs, from the names of that country.
create or replace function private.supply_bot_new(cc text) returns uuid language plpgsql security definer set search_path = '' as $$
declare pl record; uid uuid := gen_random_uuid(); nm text; k int := 0; s int; days int;
begin
  select * into pl from private.supply_places() sp where sp.country = cc;
  if not found or cardinality(pl.first_names) = 0 or cardinality(pl.last_names) = 0 then return null; end if;
  select coalesce(max(b.slot), 999) + 1 into s from public.bots b where b.slot >= 1000;
  loop
    nm := pl.first_names[1 + abs(hashtext('sf' || s || ':' || k)) % cardinality(pl.first_names)] || ' '
       || pl.last_names[1 + abs(hashtext('sl' || s || ':' || k)) % cardinality(pl.last_names)];
    exit when char_length(nm) between 2 and 20 and nm ~ '^[[:alpha:][:digit:] ._''-]+$' and private.name_problem(nm) is null
          and not exists (select 1 from public.profiles where lower(display_name) = lower(nm));
    k := k + 1;
    if k > 40 then return null; end if;
  end loop;
  days := 30 + abs(hashtext(nm)) % 300;
  insert into auth.users (id, aud, role, banned_until, created_at, updated_at)
    values (uid, 'authenticated', 'authenticated', 'infinity', now(), now());
  insert into public.profiles (id, display_name, avatar_colour, country_code, level, privacy, game_week, trades_completed, created_at,
                               adult_confirmed, is_bot, last_seen_at)
    values (uid, nm, abs(hashtext(nm)) % 8, cc, 1 + days * 3 / 14, 'public', days * 3, days * 2, now() - make_interval(days => days), true, true, now());
  insert into public.bots (user_id, slot, active, supplier) values (uid, s, false, true);
  return uid;
end $$;

-- Keeps every line supplied in each currency players use: at least two suppliers with room for 1.3 times the largest need on the line.
-- Real players count first; the world's supplier companies fill the gap and stop taking buyers once two real players cover a line.
create or replace function private.supply_fill() returns int language plpgsql security definer set search_path = '' as $$
declare cur text; ln text; need int; want int; covered int; real_cov int; made int := 0; tr text; owner uuid; pc text; pcities text[]; nm text; co text;
        city text; uv numeric; wk date := date_trunc('week', now())::date; key text; salt int; w int;
        logos text[] := array['mark','ring','square','triangle','leaf','wave','spark','anchor','bridge','gear','arrow','key','shield','tower',
                              'compass','crown','fox','owl','bull','stag','falcon'];
begin
  -- They run like any steady player's companies: seen about, past the new-supplier limit, delivering 95 to 99 percent.
  update public.profiles p set last_seen_at = now()
   where p.deleted_at is null and private.bot_awake(p.id) and exists (select 1 from public.bots b where b.user_id = p.id and b.supplier);
  update public.supply_listings l set clean_weeks = greatest(l.clean_weeks, 10), disputes = 0
   where not l.stopped and l.owner_id in (select b.user_id from public.bots b where b.supplier) and (l.clean_weeks < 10 or l.disputes > 0);
  insert into public.supply_reports (listing_id, week, delivered_pct, late_orders)
    select l.id, wk, 95 + abs(hashtext(l.id::text || wk::text)) % 5, 0
      from public.supply_listings l where not l.stopped and l.owner_id in (select b.user_id from public.bots b where b.supplier)
    on conflict (listing_id, week) do nothing;

  for cur in select distinct sp.currency from public.profiles p join private.supply_places() sp on sp.country = p.country_code
              where not p.is_bot and p.deleted_at is null and p.adult_confirmed and p.last_seen_at > now() - interval '14 days' order by 1 loop
    for ln in select distinct t.line_id from public.supply_trade_lines t order by 1 loop
      select greatest(20, coalesce(max(coalesce(c.need, c.units_per_week)), 0)) into need
        from public.supply_contracts c join public.supply_listings l on l.id = c.listing_id
       where c.ended_at is null and c.line_id = ln and l.currency = cur;
      want := ceil(need * 1.3)::int;
      -- Their own listings grow first when buyers need more.
      update public.supply_listings l set capacity_per_week = least(1000000, private.supply_committed(l.id) + want * 2)
       where l.line_id = ln and l.currency = cur and not l.stopped and not l.paused
         and l.owner_id in (select b.user_id from public.bots b where b.supplier)
         and private.supply_effective_capacity(l) - private.supply_committed(l.id) < want;
      select count(distinct l.owner_id),
             count(distinct l.owner_id) filter (where not exists (select 1 from public.bots b where b.user_id = l.owner_id and b.supplier))
        into covered, real_cov
        from public.supply_listings l
       where l.line_id = ln and l.currency = cur and not l.stopped and not l.paused and (l.expires_at is null or l.expires_at > now())
         and private.supply_effective_capacity(l) - private.supply_committed(l.id) >= want;
      if real_cov >= 2 then
        update public.supply_listings l set stopped = true
         where l.line_id = ln and l.currency = cur and not l.stopped and private.supply_committed(l.id) = 0
           and l.owner_id in (select b.user_id from public.bots b where b.supplier);
        continue;
      end if;
      while covered < 2 loop
        salt := abs(hashtext(cur || ':' || ln || ':' || covered || ':' || made));
        select t.trade_id into tr from public.supply_trade_lines t where t.line_id = ln order by hashtext(t.trade_id || cur || covered::text) limit 1;
        select sp.country, sp.cities into pc, pcities from private.supply_places() sp where sp.currency = cur order by hashtext(sp.country || ln || covered::text) limit 1;
        exit when tr is null or pc is null or coalesce(cardinality(pcities), 0) = 0;
        -- One owner runs up to three supplier companies, one per line.
        select b.user_id into owner from public.bots b join public.profiles p on p.id = b.user_id
         where b.supplier and p.deleted_at is null and p.country_code = pc
           and (select count(*) from public.supply_listings x where x.owner_id = b.user_id and not x.stopped) < 3
           and not exists (select 1 from public.supply_listings x where x.owner_id = b.user_id and x.line_id = ln and not x.stopped)
         order by hashtext(b.user_id::text || ln) limit 1;
        if owner is null then owner := private.supply_bot_new(pc); end if;
        exit when owner is null;
        select display_name into nm from public.profiles where id = owner;
        co := left(split_part(nm, ' ', 2) || ' ' || private.supply_trade_word(tr, salt), 40);
        city := pcities[1 + salt % cardinality(pcities)];
        key := left('sup-' || ln || '-' || tr, 64);
        insert into public.companies_public (owner_id, company_key, name, trade, city, country, health)
          values (owner, key, co, left(private.supply_trade_name(tr), 40), city, pc, (array['steady','growing','thriving'])[1 + salt % 3]::public.company_health)
          on conflict (owner_id, company_key) do nothing;
        select percentile_cont(0.5) within group (order by s.unit_value) into uv
          from public.supply_listings s where s.line_id = ln and s.currency = cur and not s.stopped;
        uv := round(coalesce(uv, 1000 * private.currency_scale(cur)), 2);
        w := 20 + salt % 300;
        insert into public.supply_listings (owner_id, company_key, company_name, trade_id, city, region, line_id, price_tier, quality_tier, capacity_per_week,
            lead_days, min_order, terms_days, unit_value, currency, weeks_trading, orders_total, orders_on_time, units_promised, units_delivered,
            clean_weeks, lifetime_units, logo_id)
          values (owner, key, co, tr, city, '', ln, 1, 1, want * 3, private.supply_line_lead(ln), 1, 14, uv, cur, w, w * 3, w * 3 - w / 20, w * 40,
            (w * 40 * (95 + salt % 5)) / 100, 12, (w * 40 * (95 + salt % 5)) / 100, logos[1 + salt % cardinality(logos)]);
        covered := covered + 1;
        made := made + 1;
      end loop;
    end loop;
  end loop;
  return made;
end $$;

-- The hourly bots job also keeps the supply lines filled, including after the computer-run players are removed.
create or replace function private.bot_tick() returns int language plpgsql security definer set search_path = '' as $$
declare target int := private.bot_target(); b public.bots; p public.profiles; hour_key bigint := floor(extract(epoch from now()) / 3600)::bigint;
        l public.exchange_listings; n int := 0; wk int; nw numeric; share numeric;
begin
  perform private.supply_fill();
  if private.fakes_removed() then return 0; end if;
  perform private.bot_ensure(target);
  update public.bots set active = slot < target where not supplier;
  for b in select * from public.bots where active and not supplier order by slot loop
    select * into p from public.profiles where id = b.user_id;
    wk := floor(extract(epoch from now() - p.created_at) / 86400 * 3)::int;
    update public.profiles set game_week = wk, level = 1 + wk / 14, trades_completed = greatest(trades_completed, wk * 2 / 3),
           last_seen_at = case when private.bot_awake(p.id) then now() else last_seen_at end
     where id = p.id;
    nw := round(15000 * power(1.19, b.slot) * (1 + 0.012 * wk) * (0.97 + (abs(hashtext(p.id::text || hour_key::text)) % 60) / 1000.0));
    share := ((abs(hashtext(p.id::text || 'tr')) % 220) / 1000.0) - 0.06;
    update public.leaderboard_entries set net_worth = nw, trading_result = round(nw * share), game_week = wk, updated_at = now() where user_id = p.id;
    perform private.bot_events(b, p, hour_key);
    n := n + 1;
  end loop;
  for l in select * from public.exchange_listings where delisted_at is null and not exists (select 1 from public.profiles o where o.id = owner_id and o.is_bot) loop
    perform private.bot_quote(l, hour_key);
  end loop;
  return n;
end $$;

-- Removing the computer-run players keeps the supplier companies that stand in for missing suppliers, then refills any line left short.
create or replace function public.admin_remove_fake_players(p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin(); why text := trim(coalesce(p_reason, '')); n int; gone uuid[];
begin
  if char_length(why) < 3 then raise exception 'reason_required' using errcode = 'P0001'; end if;
  insert into public.world_flags (key, value, updated_by) values ('fakes_removed', 'true'::jsonb, uid)
    on conflict (key) do update set value = 'true'::jsonb, updated_at = now(), updated_by = uid;
  select coalesce(array_agg(p.id), '{}') into gone from public.profiles p
   where p.is_bot and not exists (select 1 from public.bots b where b.user_id = p.id and b.supplier);
  update public.supply_contracts set ended_at = now(), end_reason = 'stopped'
   where ended_at is null and (supplier_id in (select unnest(gone)) or buyer_id in (select unnest(gone)));
  update public.supply_listings set stopped = true where not stopped and owner_id in (select unnest(gone));
  update public.exchange_orders set status = 'cancelled' where status = 'open' and trader_id in (select unnest(gone));
  update public.exchange_listings set delisted_at = now() where delisted_at is null and owner_id in (select unnest(gone));
  delete from public.leaderboard_entries where user_id in (select id from public.profiles where is_bot);
  delete from public.companies_public where owner_id in (select unnest(gone));
  update public.bots set active = false;
  update public.profiles set deleted_at = now() where id in (select unnest(gone)) and deleted_at is null;
  get diagnostics n = row_count;
  perform private.supply_fill();
  perform private.audit(uid, 'remove_fake_players', 'world', null, to_jsonb(n), why);
  return jsonb_build_object('removed', n);
end $$;

-- A deal carries the buyer's need a week, worked out by the game (p_units). It takes what the supplier has room for, up to that need.
create or replace function private.supply_contract_json(c public.supply_contracts) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'buyerCompanyKey', c.buyer_company_key, 'lineID', c.line_id, 'listingID', c.listing_id,
    'supplierOwnerID', c.supplier_id, 'supplierName', c.supplier_name, 'unitsPerWeek', c.units_per_week, 'need', coalesce(c.need, c.units_per_week),
    'unitPrice', c.unit_price, 'signedAt', c.signed_at, 'endedAt', c.ended_at, 'endReason', c.end_reason);
$$;

create or replace function public.sign_supply_contract(p_company_key text, p_line_id text, p_listing uuid, p_units int, p_currency text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_player(); l public.supply_listings; why text; c public.supply_contracts; room int; units int;
begin
  perform private.require_free(uid, 'trade');
  if p_units is null or p_units < 1 then raise exception 'invalid_units' using errcode = 'P0001'; end if;
  select * into l from public.supply_listings where id = p_listing for update;
  if not found or l.line_id <> p_line_id or private.is_blocked_between(uid, l.owner_id)
     or not exists (select 1 from public.supply_trade_lines t where t.trade_id = l.trade_id and t.line_id = l.line_id) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if l.currency <> p_currency then raise exception 'currency_mismatch' using errcode = 'P0001'; end if;
  update public.supply_contracts set ended_at = now(), end_reason = 'replaced' where buyer_id = uid and buyer_company_key = p_company_key and line_id = p_line_id and ended_at is null;
  room := private.supply_effective_capacity(l) - private.supply_committed(l.id);
  units := least(p_units, room);
  why := private.supply_availability(l, uid, greatest(1, units));
  if why <> 'available' then raise exception 'listing_%', why using errcode = 'P0001'; end if;
  if units < greatest(1, l.min_order) then raise exception 'listing_full' using errcode = 'P0001'; end if;
  insert into public.supply_contracts (buyer_id, buyer_company_key, line_id, listing_id, supplier_id, supplier_name, units_per_week, unit_price, need)
    values (uid, p_company_key, p_line_id, l.id, l.owner_id, private.display_name(l.owner_id), units, private.supply_unit_price(l), p_units) returning * into c;
  perform private.settle(l.owner_id, 0, l.currency, 'supply_notice', c.id::text || ':start',
    private.display_name(uid) || ' started buying ' || ceil(units * 52.0 / 12)::int || ' units a month from you.',
    jsonb_build_object('companyKey', l.company_key, 'listingID', l.id, 'units', units));
  return private.supply_contract_json(c);
end $$;

-- A supplier company's owner opens like any player's card.
create or replace function public.profile_by_code(p_code text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_user(); target uuid;
begin
  select p.id into target from public.profiles p
   where private.code_key(p.code) = private.code_key(p_code) and p.deleted_at is null
     and (not p.is_bot or exists (select 1 from public.bots b where b.user_id = p.id and b.supplier));
  if target is null or (target <> uid and private.is_blocked_between(uid, target)) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  return private.profile_json(uid, target);
end $$;

grant execute on function public.admin_remove_fake_players(text), public.sign_supply_contract(text, text, uuid, int, text), public.profile_by_code(text) to authenticated;
