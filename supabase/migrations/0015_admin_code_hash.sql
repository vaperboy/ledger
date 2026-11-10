insert into public.admin_codes (code_hash, expires_at)
values ('5efbd6b23499c8d5070dd2228036a7fc5ac4bc22f2b030c599157974715ef045', now() + interval '30 days')
on conflict (code_hash) do nothing;
