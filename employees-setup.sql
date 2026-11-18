-- employees-setup.sql
-- Lets the shop owner add, edit and remove employees from the barber desk.
-- Paste all of this into Supabase > SQL Editor > New query, then tap Run.
-- Safe to run more than once.

-- 1. Removed employees are hidden, not deleted, so past bookings keep their barber.
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
