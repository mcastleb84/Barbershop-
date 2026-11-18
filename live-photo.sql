-- Shop look (colors and background photo) for everyone, with live updates.
-- Run once in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.

-- 1. A place to keep the shop look
alter table public.shop_settings add column if not exists theme text not null default '';

-- 2. Customers (not signed in) can read the shop look
grant select on public.shop_settings to anon, authenticated;
do $$
begin
  if exists (select 1 from pg_class where oid = 'public.shop_settings'::regclass and relrowsecurity)
     and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'shop_settings'
                     and cmd in ('SELECT', 'ALL') and roles && array['anon', 'public']::name[])
  then
    create policy shop_settings_read_all on public.shop_settings for select to anon, authenticated using (true);
  end if;
end $$;

-- 3. Send changes to open apps right away
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'shop_settings'
  ) then
    alter publication supabase_realtime add table public.shop_settings;
  end if;
end $$;

-- 4. Show what is saved now. If "theme" is empty, the Staff app has not saved a look yet.
select id, length(theme) as saved_look_size, left(theme, 80) as saved_look_start from public.shop_settings;
