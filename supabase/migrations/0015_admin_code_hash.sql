-- One-time administrator code, as a hash only (the code itself is not in the repository). 0013's redeem_admin_code compares
-- encode(extensions.digest(upper(trim(code)), 'sha256'), 'hex') against admin_codes.code_hash; the code is spent by the first account
-- that redeems it and, from the moment this migration is applied, expires after 30 days.
insert into public.admin_codes (code_hash, expires_at)
values ('ef37103772372c4a4b7dabb9ece49b8cab9daa76c830983d5ac0abce1471786c', now() + interval '30 days')
on conflict (code_hash) do nothing;
