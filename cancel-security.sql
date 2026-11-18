-- cancel-security.sql
-- Customers now need their name PLUS the phone number they booked with (or their cancel code)
-- to see or cancel an appointment. Before this, a name alone was enough.
-- Paste into Supabase > SQL Editor > New query, then tap Run. Safe to run more than once.

-- 1. A private cancel code on every booking.
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
