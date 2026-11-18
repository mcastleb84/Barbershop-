-- disclaimer-setup.sql
-- Lets each barber post a policy (no-show fee, late policy, deposits) that customers must agree to before booking.
-- Paste into Supabase > SQL Editor > New query, then tap Run. Safe to run more than once.

alter table public.barbers add column if not exists disclaimer text not null default '';

alter table public.barbers drop constraint if exists barbers_disclaimer_len;
alter table public.barbers add constraint barbers_disclaimer_len check (char_length(disclaimer) <= 500);
