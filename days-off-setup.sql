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

-- Fill in every open day for every barber (shop hours), through the booking window,
-- skipping days a barber turned off. The site calls this when it loads, so customers
-- can always pick a date without anyone opening the barber desk first.
create or replace function public.fill_open_days()
returns integer language plpgsql security definer set search_path = public as $$
declare v_months int := 0; v_end date; v_n int := 0;
begin
  begin
    select coalesce((to_jsonb(s) ->> 'booking_months')::int, 0) into v_months from public.shop_settings s where s.id = 1;
  exception when others then v_months := 0;
  end;
  v_end := case when coalesce(v_months, 0) > 0 then (current_date + make_interval(months => v_months))::date else current_date + 14 end;
  insert into public.availability (barber_id, day, start_min, end_min)
  select b.id, d::date, h.open_min, h.close_min
  from public.barbers b
  cross join generate_series(current_date::timestamp, (v_end - 1)::timestamp, interval '1 day') d
  join public.shop_hours h on h.day_of_week = extract(dow from d)::int and h.open_min is not null and h.close_min > h.open_min
  where coalesce((to_jsonb(b) ->> 'active')::boolean, true)
    and not exists (select 1 from public.availability a where a.barber_id = b.id and a.day::date = d::date)
    and not exists (select 1 from public.days_off o where o.barber_id = b.id::text and o.day = d::date)
  on conflict (barber_id, day) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
grant execute on function public.fill_open_days() to anon, authenticated;
