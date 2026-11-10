insert into public.admin_codes (code_hash, expires_at)
values ('ef37103772372c4a4b7dabb9ece49b8cab9daa76c830983d5ac0abce1471786c', now() + interval '30 days')
on conflict (code_hash) do nothing;
