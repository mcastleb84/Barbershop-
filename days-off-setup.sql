-- days-off-setup.sql
-- Every open day is now checked as available for each barber automatically.
-- This table remembers the days a barber unchecked, so they stay off.
-- Paste into Supabase > SQL Editor > New query, then tap Run. Safe to run more than once.

create table if not exists public.days_off (
  barber_id  text not null,
  day        date not null,
  created_at timestamptz not null default now(),
  primary key (barber_id, day)
);
alter table public.days_off enable row level security;
revoke all on public.days_off from anon;
grant select, insert, update, delete on public.days_off to authenticated;

-- Who is signed in as staff, and may they change this barber's days? (Runs with its own rights,
-- so it works however the staff table's own permissions are set up.)
create or replace function public.days_off_is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where user_id = auth.uid());
$$;
create or replace function public.days_off_can_edit(p_barber text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff s where s.user_id = auth.uid() and (s.is_admin or s.barber_id::text = p_barber));
$$;
revoke all on function public.days_off_is_staff() from public, anon;
revoke all on function public.days_off_can_edit(text) from public, anon;
grant execute on function public.days_off_is_staff() to authenticated;
grant execute on function public.days_off_can_edit(text) to authenticated;

drop policy if exists days_off_read on public.days_off;
create policy days_off_read on public.days_off for select to authenticated
  using (public.days_off_is_staff());

drop policy if exists days_off_write on public.days_off;
create policy days_off_write on public.days_off for all to authenticated
  using (public.days_off_can_edit(barber_id))
  with check (public.days_off_can_edit(barber_id));
