# Barbershop-

Booking app for a barbershop: customers book at index.html, staff use desk.html.

**Database setup:** run `setup-all.sql` in Supabase (SQL Editor > New query > paste > Run).
It is safe to run again any time, and ends with a checklist. Every line should say OK.

**Reminders:** texts (Twilio) and emails (Resend) go out about a day before each appointment.
Add your keys in Supabase with the "Turn on reminders" query in setup-all.sql's notes, then check `reminder_log` if one doesn't arrive.
