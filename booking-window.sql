-- booking-window.sql
-- Lets the owner choose how far ahead customers can book (0 = 2 weeks, or 1, 2, 3, 6 months).
-- Paste into Supabase > SQL Editor > New query, then tap Run. Safe to run more than once.

alter table public.shop_settings add column if not exists booking_months smallint not null default 0;

alter table public.shop_settings drop constraint if exists shop_settings_booking_months_ok;
alter table public.shop_settings add constraint shop_settings_booking_months_ok check (booking_months in (0, 1, 2, 3, 6));
