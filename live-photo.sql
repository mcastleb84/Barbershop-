-- Live updates for the shop's look (background photo and colors).
-- Run this once in Supabase: SQL Editor -> New query -> paste -> Run.
-- After this, a photo added in the Staff app shows up in open customer apps within seconds.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'shop_settings'
  ) then
    alter publication supabase_realtime add table public.shop_settings;
  end if;
end $$;
