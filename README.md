# Upstride

Career guidance from people one step ahead.

Upstride is a two-sided career platform. Learners, from final-year students to experienced professionals, book one-to-one sessions with verified working professionals ("guides") in their field. Guides set their own services and prices, accept requests, run sessions and share scorecards.

**Live site:** https://upstride-connect.github.io/Upstride/

## What works

| Area | What it does |
|---|---|
| Accounts | Sign up as a learner or a guide, sign in, reset password by email |
| Guide directory | Public list of verified guides, filter by field, profile with services and reviews |
| Booking | Learners pick a service, then one of the guide's open date-wise time slots (IST); prices are locked at booking time |
| Reschedule | Learners and guides can move an upcoming session to another free slot; a learner's change needs the guide's OK |
| Learner dashboard | Upcoming and past sessions, reschedule, cancel, scorecards, ratings, profile with photo and password, plan and payment history |
| Guide dashboard | Requests to accept or reject, availability slots (with weekly repeat), meeting links, start session (placeholder), mark completed, scorecards, services, profile with photo, plan, earnings history and UPI payout details |
| Admin dashboard | Accept or reject guide applications, accept/reject/cancel/reschedule bookings, switch to own guide dashboard |

Not included yet: online payments, built-in video calls, email notifications for bookings. Guides paste a Google Meet or Zoom link for now.

## How it's built

- **Front end:** plain HTML, CSS and JavaScript, hosted on GitHub Pages. No build step. Theme in `css/theme.css` (navy and blue, Inter).
- **Back end:** [Supabase](https://supabase.com) (Postgres database + authentication). The browser talks to Supabase directly using the public anon key.
- **Security:** every table has row-level security. Learners only see their own bookings, guides only see bookings made with them, contact details are private, only admins can verify guides, and prices and statuses are enforced in the database, not the browser. See `supabase/schema.sql`.

```
index.html        home page (live guide list)
practice.html     free sample interview questions by field
login.html        sign in, sign up, password reset
guides.html       guide directory, guide profile and booking
dashboard.html    learner, guide and admin dashboards
css/              site.css (brand styles), app.css (app pages)
js/config.js      your Supabase URL and anon key
js/core.js        shared helpers
supabase/         schema.sql, reset.sql, tests/
```

## Setup (one time)

1. **Create a Supabase project** at supabase.com (free tier). Region: Mumbai.
2. **Create the database:** Supabase → SQL Editor → New query → paste all of `supabase/schema.sql` → Run. Then run each file in `supabase/migrations/` the same way, in number order.
3. **Connect the site:** Supabase → Project Settings → API. Copy the Project URL and the `anon` `public` key into `js/config.js`. Never use the `service_role` key in the site.
   Also in `js/config.js`:
   - `CONTACT_EMAIL`: the support address shown in the footer, privacy notice and terms (empty hides it).
   - `FEE_COLLECTED`: keep `false` while learners pay guides directly; set `true` once online checkout collects the 15% fee.
4. **Set the redirect URLs:** Supabase → Authentication → URL Configuration.
   - Site URL: `https://upstride-connect.github.io/Upstride/`
   - Redirect URLs: add `https://upstride-connect.github.io/Upstride/**`
5. **Make yourself admin:** sign up on the site, confirm your email, then run in the SQL Editor:
   ```sql
   update public.profiles set role = 'admin'
   where id = (select id from auth.users where email = 'you@example.com');
   ```
6. **Verify guides:** sign in → Dashboard → To verify → Verify guide. Only verified guides appear in the directory.

## Database updates

Schema changes ship as numbered files in `supabase/migrations/`. Run each new file once in the Supabase SQL Editor. Every file is safe to run more than once.

| File | What it adds |
|---|---|
| `002_guide_rejection.sql` | Admins can reject guide applications |
| `003_slots_and_reschedule.sql` | Guide time slots, slot-based booking, rescheduling |
| `004_profile_photos.sql` | Profile photos (storage bucket), guide UPI payout details |
| `005_learners_only_booking.sql` | Only learner accounts can book sessions |
| `006_learner_payment_details.sql` | Learners see their guide's UPI ID on accepted sessions |

`supabase/update_5_and_6.sql` contains updates 5 and 6 together, if you have run neither yet.

## Testing

Browser checks (uses a stand-in for Supabase, needs Playwright):

```bash
python3 tests/ui_check.py
```

## Testing the database

The security rules have automated tests that run against a local Postgres:

```bash
python3 supabase/tests/run_tests.py   # needs psql and a local Postgres
```

They check sign-up, verification, privacy, booking rules, scorecards, reviews and double-booking.

## Before a public launch

- When the final domain is ready, update the `og:image` address in the `<head>` of each page (it points at the GitHub Pages address for now).
- Have a lawyer review `privacy.html` and `terms.html`.
- Turn on a custom SMTP sender in Supabase (the built-in email service is rate-limited and meant for testing).
- Add a privacy policy and terms (India's DPDP Act applies to learner data).
- Add payments (e.g. Razorpay) and booking email notifications.
