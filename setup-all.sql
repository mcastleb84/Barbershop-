-- setup-all.sql
-- ONE script for the whole database. Paste into Supabase > SQL Editor > New query, then tap Run.
-- Safe to run as many times as you like: it only adds what is missing and refreshes the app's functions.
-- It replaces running these one by one: disclaimer-setup, booking-window, live-photo,
-- employees-setup, days-off-setup and cancel-security, and adds photo storage and reminders.
--
-- At the end it shows a checklist. Every line should say OK.
-- A line that says MISSING is something the app needs that this database does not have yet.
-- The core tables (barbers, bookings, shop hours, staff) and the booking function come from the
-- original shop-setup.sql, which is not in this repo, so this script can check them but not create them.


-- ============================================================
-- 1. Barber policies (no-show fee, late policy)
-- ============================================================

alter table public.barbers add column if not exists disclaimer text not null default '';

alter table public.barbers drop constraint if exists barbers_disclaimer_len;
alter table public.barbers add constraint barbers_disclaimer_len check (char_length(disclaimer) <= 500);

-- ============================================================
-- 2. How far ahead customers can book
-- ============================================================

alter table public.shop_settings add column if not exists booking_months smallint not null default 0;

alter table public.shop_settings drop constraint if exists shop_settings_booking_months_ok;
alter table public.shop_settings add constraint shop_settings_booking_months_ok check (booking_months in (0, 1, 2, 3));

-- ============================================================
-- 3. Shop look: colors and background photo, readable by customers, sent live to open apps
-- ============================================================

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

-- Owner settings save into row 1. If that row is missing, saving colors fails, so add it.
do $$
begin
  insert into public.shop_settings (id) values (1) on conflict (id) do nothing;
exception when others then
  raise notice 'Could not add shop_settings row 1 (%). Add your shop name in Owner settings.', sqlerrm;
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

-- ============================================================
-- 4. Employees: add, edit and remove from the barber desk
-- ============================================================

alter table public.barbers add column if not exists active boolean not null default true;

-- 2. Logins waiting to be claimed: the owner adds an email before the employee has an account.
create table if not exists public.staff_invites (
  email      text primary key,
  barber_id  text not null,
  is_admin   boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.staff_invites enable row level security;
revoke all on public.staff_invites from anon, authenticated;

-- 3. Is the signed-in user an owner?
create or replace function public.emp_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where user_id = auth.uid() and is_admin);
$$;

-- 4. Employee list for the owner (includes login emails).
create or replace function public.list_employees()
returns table (barber_id text, name text, active boolean, email text, is_admin boolean, status text)
language plpgsql stable security definer set search_path = public, auth as $$
#variable_conflict use_column
begin
  if not public.emp_is_admin() then raise exception 'Only the shop owner can manage employees'; end if;
  return query
  select b.id::text, b.name::text, coalesce(b.active, true),
         coalesce(u.email, i.email)::text,
         coalesce(s.is_admin, i.is_admin, false),
         case when s.user_id is not null then 'linked'
              when i.email is not null then 'invited'
              else 'none' end
  from public.barbers b
  left join lateral (select s2.user_id, s2.is_admin from public.staff s2
                     where s2.barber_id::text = b.id::text limit 1) s on true
  left join auth.users u on u.id = s.user_id
  left join lateral (select i2.email, i2.is_admin from public.staff_invites i2
                     where i2.barber_id = b.id::text limit 1) i on true
  order by coalesce(b.active, true) desc, b.name;
end $$;

-- 5. Add (p_barber empty) or edit an employee: name, login email, owner access.
create or replace function public.save_employee(p_barber text, p_name text, p_email text, p_admin boolean)
returns text language plpgsql security definer set search_path = public, auth as $$
declare
  v_id    text;
  v_uid   uuid;
  v_email text    := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_admin boolean := coalesce(p_admin, false);
begin
  if not public.emp_is_admin() then raise exception 'Only the shop owner can manage employees'; end if;
  if nullif(trim(coalesce(p_name, '')), '') is null then raise exception 'Enter a name'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'That email does not look right'; end if;

  if coalesce(p_barber, '') = '' then
    insert into public.barbers (name) values (trim(p_name)) returning id::text into v_id;
  else
    -- The owner cannot change their own login or owner access here (avoids locking yourself out).
    if exists (select 1 from public.staff where barber_id::text = p_barber and user_id = auth.uid())
       and (not v_admin or v_email is distinct from lower(auth.email())) then
      raise exception 'You cannot change your own login or owner access';
    end if;
    update public.barbers set name = trim(p_name), active = true
      where id::text = p_barber returning id::text into v_id;
    if v_id is null then raise exception 'Employee not found'; end if;
  end if;

  if v_email is null then
    delete from public.staff where barber_id::text = v_id and user_id <> auth.uid();
    delete from public.staff_invites where barber_id = v_id;
    return v_id;
  end if;

  select id into v_uid from auth.users where lower(email) = v_email limit 1;
  if v_uid is not null and exists (select 1 from public.staff where user_id = v_uid and barber_id::text <> v_id) then
    raise exception 'That email already belongs to another employee';
  end if;
  if exists (select 1 from public.staff_invites where email = v_email and barber_id <> v_id) then
    raise exception 'That email already belongs to another employee';
  end if;

  delete from public.staff where barber_id::text = v_id and user_id is distinct from v_uid;
  delete from public.staff_invites where barber_id = v_id or email = v_email;

  if v_uid is not null then
    if exists (select 1 from public.staff where user_id = v_uid) then
      update public.staff set is_admin = v_admin where user_id = v_uid;
    else
      insert into public.staff (user_id, barber_id, is_admin)
        select v_uid, b.id, v_admin from public.barbers b where b.id::text = v_id;
    end if;
  else
    -- No account yet: it links automatically when they sign up with this email.
    insert into public.staff_invites (email, barber_id, is_admin) values (v_email, v_id, v_admin);
  end if;
  return v_id;
end $$;

-- 6. Remove an employee: takes away their login and open days, hides them from customers.
create or replace function public.remove_employee(p_barber text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.emp_is_admin() then raise exception 'Only the shop owner can manage employees'; end if;
  if exists (select 1 from public.staff where barber_id::text = p_barber and user_id = auth.uid()) then
    raise exception 'You cannot remove yourself';
  end if;
  if exists (select 1 from public.bookings where barber_id::text = p_barber and day::date >= current_date) then
    raise exception 'This barber still has upcoming appointments. Cancel or move them first.';
  end if;
  delete from public.staff where barber_id::text = p_barber;
  delete from public.staff_invites where barber_id = p_barber;
  delete from public.availability where barber_id::text = p_barber and day::date >= current_date;
  update public.barbers set active = false where id::text = p_barber;
end $$;

-- 7. Runs when an employee signs in: links their account if the owner added their email.
create or replace function public.claim_staff_invite()
returns boolean language plpgsql security definer set search_path = public, auth as $$
declare v_email text := lower(auth.email());
begin
  if auth.uid() is null or v_email is null then return false; end if;
  if exists (select 1 from public.staff where user_id = auth.uid()) then return true; end if;
  insert into public.staff (user_id, barber_id, is_admin)
    select auth.uid(), b.id, i.is_admin
    from public.staff_invites i join public.barbers b on b.id::text = i.barber_id
    where i.email = v_email limit 1;
  if found then
    delete from public.staff_invites where email = v_email;
    return true;
  end if;
  return false;
end $$;

revoke all on function public.emp_is_admin()                              from public, anon;
revoke all on function public.list_employees()                            from public, anon;
revoke all on function public.save_employee(text, text, text, boolean)    from public, anon;
revoke all on function public.remove_employee(text)                       from public, anon;
revoke all on function public.claim_staff_invite()                        from public, anon;
grant execute on function public.emp_is_admin()                           to authenticated;
grant execute on function public.list_employees()                         to authenticated;
grant execute on function public.save_employee(text, text, text, boolean) to authenticated;
grant execute on function public.remove_employee(text)                    to authenticated;
grant execute on function public.claim_staff_invite()                     to authenticated;

-- ============================================================
-- 5. Days off and filling open days
-- ============================================================

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

-- ============================================================
-- 6. Cancel security: name plus phone or cancel code
-- ============================================================

alter table public.bookings add column if not exists cancel_code text
  default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
update public.bookings set cancel_code = upper(substr(md5(random()::text || id::text || clock_timestamp()::text), 1, 6))
  where cancel_code is null;

-- 2. The code can be shown once, right after booking. Existing bookings are marked as already shown.
alter table public.bookings add column if not exists code_shown boolean not null default true;
alter table public.bookings alter column code_shown set default false;

-- Does this secret (phone number or cancel code) match the booking?
create or replace function public.booking_secret_ok(p_phone text, p_code text, p_secret text)
returns boolean language sql immutable as $$
  select case
    when nullif(trim(coalesce(p_secret, '')), '') is null then false
    when upper(trim(p_secret)) = upper(coalesce(p_code, '')) then true
    else length(regexp_replace(p_secret, '\D', '', 'g')) >= 7
         and right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10)
           = right(regexp_replace(p_secret, '\D', '', 'g'), 10)
  end;
$$;

-- 3. Right after booking: get the cancel code once.
create or replace function public.booking_code(p_id text, p_name text)
returns text language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  update public.bookings set code_shown = true
   where id::text = p_id
     and lower(trim(customer_name)) = lower(trim(p_name))
     and not code_shown
  returning cancel_code into v_code;
  return v_code;
end $$;

-- 4. Find my upcoming appointments (name + phone or code).
create or replace function public.find_my_bookings(p_name text, p_secret text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', b.id, 'barber_id', b.barber_id, 'day', b.day, 'start_min', b.start_min)
                  order by b.day, b.start_min), '[]'::json)
  from public.bookings b
  where lower(trim(b.customer_name)) = lower(trim(p_name))
    and b.day::date >= current_date
    and public.booking_secret_ok(b.customer_phone, b.cancel_code, p_secret);
$$;

-- 5. Cancel one appointment (name + phone or code). Uses the shop's existing cancel step,
--    so the barber desk still gets the cancellation alert.
create or replace function public.cancel_my_booking(p_id text, p_name text, p_secret text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_id   public.bookings.id%type;
  v_name text;
  v_res  text;
begin
  select b.id, b.customer_name into v_id, v_name
    from public.bookings b
   where b.id::text = p_id
     and lower(trim(b.customer_name)) = lower(trim(p_name))
     and public.booking_secret_ok(b.customer_phone, b.cancel_code, p_secret);
  if v_id is null then return false; end if;
  v_res := (public.cancel_booking(p_id => v_id, p_name => v_name))::text;
  return coalesce(v_res, '') not in ('', 'false', 'f', '0');
end $$;

grant execute on function public.booking_code(text, text)           to anon, authenticated;
grant execute on function public.find_my_bookings(text, text)       to anon, authenticated;
grant execute on function public.cancel_my_booking(text, text, text) to anon, authenticated;

-- 6. Close the old name-only lookup and cancel. (Still used internally by step 5.)
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('find_bookings', 'cancel_booking')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;


-- ============================================================
-- 7. Shop photos in Supabase Storage
-- ============================================================
-- The owner's photo is stored as a normal image file. Anyone can view it; only the owner can add or remove it.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('shop-photos', 'shop-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists shop_photos_owner_read   on storage.objects;
drop policy if exists shop_photos_owner_add    on storage.objects;
drop policy if exists shop_photos_owner_change on storage.objects;
drop policy if exists shop_photos_owner_remove on storage.objects;
create policy shop_photos_owner_read   on storage.objects for select to authenticated using (bucket_id = 'shop-photos' and public.emp_is_admin());
create policy shop_photos_owner_add    on storage.objects for insert to authenticated with check (bucket_id = 'shop-photos' and public.emp_is_admin());
create policy shop_photos_owner_change on storage.objects for update to authenticated using (bucket_id = 'shop-photos' and public.emp_is_admin()) with check (bucket_id = 'shop-photos' and public.emp_is_admin());
create policy shop_photos_owner_remove on storage.objects for delete to authenticated using (bucket_id = 'shop-photos' and public.emp_is_admin());

-- ============================================================
-- 8. Customer email on bookings (optional, for reminders)
-- ============================================================
alter table public.bookings add column if not exists customer_email text;
alter table public.bookings add column if not exists reminder_sent_at timestamptz;

-- Right after booking, the app adds the email. Only works on a brand-new booking (before its cancel code is shown).
create or replace function public.set_booking_email(p_id text, p_name text, p_email text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(coalesce(p_email, '')));
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 120 then return false; end if;
  update public.bookings set customer_email = v_email
   where id::text = p_id
     and lower(trim(customer_name)) = lower(trim(p_name))
     and customer_email is null
     and not coalesce(code_shown, true);
  return found;
end $$;
revoke all on function public.set_booking_email(text, text, text) from public;
grant execute on function public.set_booking_email(text, text, text) to anon, authenticated;

-- ============================================================
-- 9. Appointment reminders by text (Twilio) and email (Resend)
-- ============================================================
create extension if not exists http with schema extensions;
create extension if not exists pg_cron;

-- Your reminder settings and keys. Private: the apps cannot read this table.
create table if not exists public.reminder_settings (
  id            int primary key default 1 check (id = 1),
  enabled       boolean not null default false,
  time_zone     text not null default 'America/New_York',
  site_url      text not null default 'https://mcastleb84.github.io/Barbershop-/',
  send_from     int  not null default 9,    -- earliest hour to send (9 = 9 AM)
  send_until    int  not null default 20,   -- latest hour to send (20 = 8 PM)
  twilio_sid    text not null default '',
  twilio_token  text not null default '',
  twilio_from   text not null default '',   -- your Twilio number, like +15551234567
  resend_key    text not null default '',
  email_from    text not null default ''    -- like 'Fresh Cuts <reminders@freshcuts.com>'
);
insert into public.reminder_settings (id) values (1) on conflict (id) do nothing;
alter table public.reminder_settings enable row level security;
revoke all on public.reminder_settings from anon, authenticated;

create table if not exists public.reminder_log (
  id         bigserial primary key,
  booking_id text,
  channel    text,
  sent_to    text,
  ok         boolean,
  detail     text,
  created_at timestamptz not null default now()
);
alter table public.reminder_log enable row level security;
revoke all on public.reminder_log from anon, authenticated;

-- US phone numbers become +1XXXXXXXXXX. Anything else that already starts with + is kept.
create or replace function public.reminder_phone(p text)
returns text language sql immutable as $$
  select case
    when length(regexp_replace(coalesce(p, ''), '\D', '', 'g')) = 10 then '+1' || regexp_replace(p, '\D', '', 'g')
    when length(regexp_replace(coalesce(p, ''), '\D', '', 'g')) = 11 and regexp_replace(p, '\D', '', 'g') like '1%' then '+' || regexp_replace(p, '\D', '', 'g')
    when trim(coalesce(p, '')) like '+%' and length(regexp_replace(p, '\D', '', 'g')) between 8 and 15 then '+' || regexp_replace(p, '\D', '', 'g')
    else null end;
$$;

create or replace function public.reminder_send_text(p_to text, p_body text, p_booking text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare c public.reminder_settings; r extensions.http_response; v_ok boolean := false; v_detail text;
begin
  select * into c from public.reminder_settings where id = 1;
  if c.twilio_sid = '' or c.twilio_token = '' or c.twilio_from = '' then return false; end if;
  begin
    r := extensions.http((
      'POST', 'https://api.twilio.com/2010-04-01/Accounts/' || c.twilio_sid || '/Messages.json',
      array[('Authorization', 'Basic ' || replace(encode(convert_to(c.twilio_sid || ':' || c.twilio_token, 'UTF8'), 'base64'), E'\n', ''))::extensions.http_header],
      'application/x-www-form-urlencoded',
      'To=' || extensions.urlencode(p_to) || '&From=' || extensions.urlencode(c.twilio_from) || '&Body=' || extensions.urlencode(p_body)
    )::extensions.http_request);
    v_ok := r.status between 200 and 299; v_detail := r.status || ' ' || left(r.content, 300);
  exception when others then v_detail := sqlerrm;
  end;
  insert into public.reminder_log (booking_id, channel, sent_to, ok, detail) values (p_booking, 'text', p_to, v_ok, v_detail);
  return v_ok;
end $$;

create or replace function public.reminder_send_email(p_to text, p_subject text, p_body text, p_booking text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare c public.reminder_settings; r extensions.http_response; v_ok boolean := false; v_detail text;
begin
  select * into c from public.reminder_settings where id = 1;
  if c.resend_key = '' or c.email_from = '' then return false; end if;
  begin
    r := extensions.http((
      'POST', 'https://api.resend.com/emails',
      array[('Authorization', 'Bearer ' || c.resend_key)::extensions.http_header],
      'application/json',
      json_build_object('from', c.email_from, 'to', json_build_array(p_to), 'subject', p_subject, 'text', p_body)::text
    )::extensions.http_request);
    v_ok := r.status between 200 and 299; v_detail := r.status || ' ' || left(r.content, 300);
  exception when others then v_detail := sqlerrm;
  end;
  insert into public.reminder_log (booking_id, channel, sent_to, ok, detail) values (p_booking, 'email', p_to, v_ok, v_detail);
  return v_ok;
end $$;

-- Every 15 minutes: remind customers whose appointment is 2 to 24 hours away (only between send_from and send_until).
create or replace function public.send_due_reminders()
returns integer language plpgsql security definer set search_path = public as $$
declare c public.reminder_settings; b record; v_shop text; v_when text; v_msg text; v_n int := 0; v_hour int;
begin
  select * into c from public.reminder_settings where id = 1;
  if not found or not c.enabled then return 0; end if;
  v_hour := extract(hour from now() at time zone c.time_zone)::int;
  if v_hour < c.send_from or v_hour >= c.send_until then return 0; end if;
  select coalesce(nullif(trim(s.name), ''), 'the shop') into v_shop from public.shop_settings s where s.id = 1;

  for b in
    select k.*, coalesce(nullif(trim(br.name), ''), 'your barber') as barber_name,
           ((k.day::date + make_interval(mins => k.start_min)) at time zone c.time_zone) as appt_at
      from public.bookings k left join public.barbers br on br.id::text = k.barber_id::text
     where k.reminder_sent_at is null
       and (public.reminder_phone(k.customer_phone) is not null or coalesce(k.customer_email, '') <> '')
       and ((k.day::date + make_interval(mins => k.start_min)) at time zone c.time_zone) between now() + interval '2 hours' and now() + interval '24 hours'
     order by k.day, k.start_min
     limit 50
  loop
    update public.bookings set reminder_sent_at = now() where id = b.id;   -- marked first, so nobody gets two
    v_when := to_char(b.appt_at at time zone c.time_zone, 'FMDay, Mon FMDD "at" FMHH12:MI AM');
    v_msg := 'Reminder from ' || v_shop || ': your appointment with ' || b.barber_name || ' is ' || v_when || '.'
             || ' Need to cancel? ' || c.site_url;
    if public.reminder_phone(b.customer_phone) is not null then
      perform public.reminder_send_text(public.reminder_phone(b.customer_phone), v_msg || ' Reply STOP to opt out.', b.id::text);
    end if;
    if coalesce(b.customer_email, '') <> '' then
      perform public.reminder_send_email(b.customer_email, 'Reminder: ' || v_shop || ', ' || v_when, v_msg, b.id::text);
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Try your setup: select public.send_test_reminder('+15551234567', 'you@example.com');
create or replace function public.send_test_reminder(p_phone text, p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare t boolean; e boolean; v_shop text;
begin
  select coalesce(nullif(trim(name), ''), 'the shop') into v_shop from public.shop_settings where id = 1;
  t := case when public.reminder_phone(p_phone) is null then null
            else public.reminder_send_text(public.reminder_phone(p_phone), 'Test reminder from ' || v_shop || '. Texts are working.', 'test') end;
  e := case when coalesce(p_email, '') = '' then null
            else public.reminder_send_email(p_email, 'Test reminder from ' || v_shop, 'Emails are working.', 'test') end;
  return 'Text: ' || coalesce(case when t then 'sent' else 'FAILED (see reminder_log)' end, 'skipped')
      || ' | Email: ' || coalesce(case when e then 'sent' else 'FAILED (see reminder_log)' end, 'skipped');
end $$;

revoke all on function public.reminder_send_text(text, text, text)          from public, anon, authenticated;
revoke all on function public.reminder_send_email(text, text, text, text)   from public, anon, authenticated;
revoke all on function public.send_due_reminders()                          from public, anon, authenticated;
revoke all on function public.send_test_reminder(text, text)                from public, anon, authenticated;

-- Run the reminder check every 15 minutes.
select cron.unschedule(jobid) from cron.job where jobname = 'booking-reminders';
select cron.schedule('booking-reminders', '*/15 * * * *', 'select public.send_due_reminders()');

-- ============================================================
-- 10. Checklist: does the database have everything the app uses?
-- ============================================================
with need(part, kind, tbl, col) as (values
  ('Barbers',            'col', 'barbers',       'id'),
  ('Barbers',            'col', 'barbers',       'name'),
  ('Barbers',            'col', 'barbers',       'active'),
  ('Barbers',            'col', 'barbers',       'specialties'),
  ('Barbers',            'col', 'barbers',       'disclaimer'),
  ('Barbers',            'col', 'barbers',       'cashapp'),
  ('Barbers',            'col', 'barbers',       'venmo'),
  ('Barbers',            'col', 'barbers',       'card_link'),
  ('Bookings',           'col', 'bookings',      'customer_phone'),
  ('Bookings',           'col', 'bookings',      'note'),
  ('Bookings',           'col', 'bookings',      'cancel_code'),
  ('Bookings',           'col', 'bookings',      'code_shown'),
  ('Open times',         'col', 'availability',  'end_min'),
  ('Taken times',        'col', 'taken_slots',   'start_min'),
  ('Shop hours',         'col', 'shop_hours',    'close_min'),
  ('Barber notes',       'col', 'notes',         'body'),
  ('Recent activity',    'col', 'activity',      'kind'),
  ('Staff logins',       'col', 'staff',         'is_admin'),
  ('Employee invites',   'col', 'staff_invites', 'email'),
  ('Days off',           'col', 'days_off',      'day'),
  ('Shop details',       'col', 'shop_settings', 'name'),
  ('Shop details',       'col', 'shop_settings', 'address'),
  ('Shop details',       'col', 'shop_settings', 'phone'),
  ('Shop payments',      'col', 'shop_settings', 'cashapp'),
  ('Shop payments',      'col', 'shop_settings', 'venmo'),
  ('Shop payments',      'col', 'shop_settings', 'card_link'),
  ('Booking window',     'col', 'shop_settings', 'booking_months'),
  ('Shop look',          'col', 'shop_settings', 'theme'),
  ('Booking',            'fn',  'book_appointment',   null),
  ('Cancelling',         'fn',  'cancel_booking',     null),
  ('Cancelling',         'fn',  'cancel_my_booking',  null),
  ('Cancelling',         'fn',  'find_my_bookings',   null),
  ('Cancel code',        'fn',  'booking_code',       null),
  ('Open days',          'fn',  'fill_open_days',     null),
  ('Employees',          'fn',  'list_employees',     null),
  ('Employees',          'fn',  'save_employee',      null),
  ('Employees',          'fn',  'remove_employee',    null),
  ('Employee sign-in',   'fn',  'claim_staff_invite', null),
  ('Reminder email',     'col', 'bookings',      'customer_email'),
  ('Reminder email',     'fn',  'set_booking_email',  null),
  ('Reminders',          'fn',  'send_due_reminders', null)
)
select part as "what", coalesce(tbl || '.' || col, tbl) as "needs",
  case when (kind = 'col' and exists (select 1 from information_schema.columns c
                                      where c.table_schema = 'public' and c.table_name = need.tbl and c.column_name = need.col))
         or (kind = 'fn'  and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                      where n.nspname = 'public' and p.proname = need.tbl))
       then 'OK' else 'MISSING' end as "status"
from need
union all
select 'Shop settings row', 'shop_settings id 1',
  case when exists (select 1 from public.shop_settings where id = 1) then 'OK' else 'MISSING' end
union all
select 'Live updates', 'shop_settings in realtime',
  case when exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'shop_settings')
       then 'OK' else 'MISSING' end
union all
select 'Customers can read shop look', 'read rule on shop_settings',
  case when has_table_privilege('anon', 'public.shop_settings', 'select')
        and (not (select relrowsecurity from pg_class where oid = 'public.shop_settings'::regclass)
             or exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'shop_settings'
                        and cmd in ('SELECT', 'ALL') and roles && array['anon', 'public']::name[]))
       then 'OK' else 'MISSING' end
union all
select 'Photo storage', 'shop-photos bucket',
  case when exists (select 1 from storage.buckets where id = 'shop-photos' and public) then 'OK' else 'MISSING' end
union all
select 'Reminders schedule', 'every 15 minutes',
  case when exists (select 1 from cron.job where jobname = 'booking-reminders' and active) then 'OK' else 'MISSING' end
union all
select 'Reminders', 'turned on',
  (select case when enabled then 'ON' else 'OFF (see step 3 in the reminders guide)' end from public.reminder_settings where id = 1)
union all
select 'Reminder texts', 'Twilio keys',
  (select case when twilio_sid <> '' and twilio_token <> '' and twilio_from <> '' then 'OK' else 'NOT SET UP' end from public.reminder_settings where id = 1)
union all
select 'Reminder emails', 'Resend key',
  (select case when resend_key <> '' and email_from <> '' then 'OK' else 'NOT SET UP' end from public.reminder_settings where id = 1)
union all
select 'Saved shop look', 'theme on shop_settings',
  coalesce((select case when coalesce(theme, '') = '' then 'EMPTY (nothing saved from Owner settings yet)'
                        when theme like '%data:image%' then 'OK, ' || round(length(theme) / 1024.0) || ' KB (photo moves to Storage next time the owner opens the Staff app)'
                        else 'OK, ' || round(length(theme) / 1024.0) || ' KB saved' end
            from public.shop_settings where id = 1), 'MISSING');
