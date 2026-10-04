-- =====================================================================
-- Upstride database schema (Supabase / Postgres 15+)
--
-- Run this whole file once in Supabase: SQL Editor -> New query -> Run.
-- It is safe to run on a fresh project. To start over, run reset.sql first.
--
-- Tables
--   profiles          one row per account (learner, guide or admin)
--   contacts          private email/phone, visible only to the owner and admins
--   learner_profiles  career stage, field and goal for learners
--   guide_profiles    public profile for guides, with admin verification
--   services          what each guide offers, with price and duration
--   bookings          session requests and their status
--   scorecards        feedback a guide writes after a session
--   reviews           star rating a learner leaves after a completed session
--   guide_directory   public view of verified guides for the website
--
-- Security: every table uses row-level security. Browser code only ever
-- holds the public "anon" key, so these policies are what protect data.
-- =====================================================================

-- ---------- Allowed values ------------------------------------------------

create domain public.career_field as text
  check (value in ('Software Development','Business Analysis','Quality Assurance',
                   'Data Analytics','Marketing','Leadership'));

create or replace function public.pick(val text, allowed text[])
returns text language sql immutable as $$
  select case when val = any(allowed) then val else null end
$$;

-- ---------- Tables --------------------------------------------------------

create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        text not null default 'learner' check (role in ('learner','guide','admin')),
  full_name   text not null default '' check (char_length(full_name) <= 120),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.contacts (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  email       text,
  phone       text check (phone is null or char_length(phone) <= 20),
  updated_at  timestamptz not null default now()
);

create table public.learner_profiles (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  career_stage  text check (career_stage in ('Final-year student','Recent graduate',
                  '1–3 years experience','3–8 years experience','8+ years experience')),
  field         public.career_field,
  goal          text check (char_length(goal) <= 200),
  updated_at    timestamptz not null default now()
);

create table public.guide_profiles (
  user_id           uuid primary key references public.profiles(id) on delete cascade,
  headline          text not null default '' check (char_length(headline) <= 120),
  field             public.career_field,
  years_experience  text check (years_experience in ('3–5 years','5–10 years','10–15 years','15+ years')),
  bio               text not null default '' check (char_length(bio) <= 1500),
  linkedin_url      text check (linkedin_url is null or char_length(linkedin_url) <= 300),
  availability      text check (availability in ('Weekday evenings','Weekends','Both')),
  is_verified       boolean not null default false,
  is_rejected       boolean not null default false,  -- admin turned the application down
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table public.services (
  id            uuid primary key default gen_random_uuid(),
  guide_id      uuid not null references public.guide_profiles(user_id) on delete cascade,
  title         text not null check (char_length(title) between 3 and 120),
  description   text not null default '' check (char_length(description) <= 500),
  duration_min  int  not null default 60 check (duration_min between 15 and 240),
  price_inr     int  not null check (price_inr between 0 and 100000),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

create table public.bookings (
  id            uuid primary key default gen_random_uuid(),
  learner_id    uuid not null references public.profiles(id) on delete cascade,
  guide_id      uuid not null references public.guide_profiles(user_id) on delete cascade,
  service_id    uuid references public.services(id) on delete set null,
  -- copied from the service at booking time, so later price edits don't change past bookings
  service_title text not null default '',
  price_inr     int  not null default 0,
  duration_min  int  not null default 60,
  scheduled_at  timestamptz not null,
  status        text not null default 'requested'
                check (status in ('requested','accepted','declined','cancelled','completed')),
  learner_note  text not null default '' check (char_length(learner_note) <= 1000),
  guide_note    text not null default '' check (char_length(guide_note) <= 1000),
  meeting_link  text check (meeting_link is null or meeting_link ~* '^https://'),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.scorecards (
  booking_id  uuid primary key references public.bookings(id) on delete cascade,
  criteria    jsonb not null default '[]'::jsonb check (jsonb_typeof(criteria) = 'array'),
  overall     numeric(2,1),
  note        text not null default '' check (char_length(note) <= 2000),
  fixes       text not null default '' check (char_length(fixes) <= 1000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.reviews (
  booking_id  uuid primary key references public.bookings(id) on delete cascade,
  guide_id    uuid not null references public.guide_profiles(user_id) on delete cascade,
  learner_id  uuid not null references public.profiles(id) on delete cascade,
  rating      int  not null check (rating between 1 and 5),
  comment     text not null default '' check (char_length(comment) <= 1000),
  created_at  timestamptz not null default now()
);

create index on public.services (guide_id);
create index on public.bookings (guide_id, scheduled_at);
create index on public.bookings (learner_id, scheduled_at);
create index on public.reviews (guide_id);
-- a guide cannot accept two sessions that start at the same time
create unique index bookings_no_double_accept
  on public.bookings (guide_id, scheduled_at) where status = 'accepted';

-- ---------- Helper functions ----------------------------------------------

-- security definer so policies can call it without recursing into profiles' own policy
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
$$;

-- true for admins, and for trusted server-side work (Supabase SQL editor, service key),
-- where no end user is signed in
create or replace function public.is_trusted()
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is null or public.is_admin()
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

create trigger t_profiles_touch  before update on public.profiles         for each row execute function public.touch_updated_at();
create trigger t_contacts_touch  before update on public.contacts         for each row execute function public.touch_updated_at();
create trigger t_learner_touch   before update on public.learner_profiles for each row execute function public.touch_updated_at();
create trigger t_guide_touch     before update on public.guide_profiles   for each row execute function public.touch_updated_at();
create trigger t_bookings_touch  before update on public.bookings         for each row execute function public.touch_updated_at();
create trigger t_scorecard_touch before update on public.scorecards       for each row execute function public.touch_updated_at();

-- ---------- New account setup ---------------------------------------------
-- Supabase Auth creates a row in auth.users on sign-up. This trigger turns the
-- sign-up form fields (sent as user metadata) into profile rows. Unknown or
-- invalid values are dropped rather than failing the sign-up.

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  meta   jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  r      text  := case when meta->>'role' = 'guide' then 'guide' else 'learner' end;
  fields text[] := array['Software Development','Business Analysis','Quality Assurance',
                         'Data Analytics','Marketing','Leadership'];
  price  int;
  svc    text;
begin
  insert into public.profiles (id, role, full_name)
  values (new.id, r, left(coalesce(meta->>'full_name', ''), 120));

  insert into public.contacts (user_id, email, phone)
  values (new.id, new.email, left(nullif(meta->>'phone', ''), 20));

  if r = 'learner' then
    insert into public.learner_profiles (user_id, career_stage, field, goal)
    values (new.id,
            public.pick(meta->>'career_stage', array['Final-year student','Recent graduate',
              '1–3 years experience','3–8 years experience','8+ years experience']),
            public.pick(meta->>'field', fields),
            left(meta->>'goal', 200));
  else
    insert into public.guide_profiles (user_id, headline, field, years_experience, linkedin_url, availability)
    values (new.id,
            left(coalesce(meta->>'headline', ''), 120),
            public.pick(meta->>'field', fields),
            public.pick(meta->>'years_experience', array['3–5 years','5–10 years','10–15 years','15+ years']),
            left(nullif(meta->>'linkedin_url', ''), 300),
            public.pick(meta->>'availability', array['Weekday evenings','Weekends','Both']));

    price := case when coalesce(meta->>'price_inr', '') ~ '^\d{1,6}$'
                  then least((meta->>'price_inr')::int, 100000) else 999 end;

    if jsonb_typeof(meta->'services') = 'array' then
      for svc in select jsonb_array_elements_text(meta->'services') loop
        insert into public.services (guide_id, title, duration_min, price_inr)
        select new.id, t.title, t.mins, price
        from (values ('Mock panels',         'Mock panel with scorecard', 60),
                     ('Workshops',           'Interview workshop (group)', 120),
                     ('Career roadmap',      'Career roadmap session', 45),
                     ('Resume review',       'Resume & LinkedIn review', 45),
                     ('Leadership coaching', 'Leadership coaching', 60)) as t(key, title, mins)
        where t.key = svc;
      end loop;
    end if;
  end if;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Guards on sensitive columns -------------------------------------

-- only admins can change someone's role
create or replace function public.guard_profile()
returns trigger language plpgsql as $$
begin
  if new.role is distinct from old.role and not public.is_trusted() then
    new.role := old.role;
  end if;
  new.id := old.id;
  return new;
end $$;
create trigger t_guard_profile before update on public.profiles
  for each row execute function public.guard_profile();

-- only admins can verify or reject a guide
create or replace function public.guard_guide_profile()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then
    new.is_verified := old.is_verified;
    new.is_rejected := old.is_rejected;
  end if;
  if new.is_verified then new.is_rejected := false; end if;
  new.user_id := old.user_id;
  return new;
end $$;
create trigger t_guard_guide before update on public.guide_profiles
  for each row execute function public.guard_guide_profile();

-- new bookings: fill in the service details and check the request is valid
create or replace function public.prepare_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare s record;
begin
  if new.learner_id is distinct from auth.uid() and not public.is_trusted() then
    raise exception 'You can only book sessions for yourself.';
  end if;
  if new.learner_id = new.guide_id then
    raise exception 'You cannot book a session with yourself.';
  end if;
  select sv.* into s from public.services sv
    join public.guide_profiles g on g.user_id = sv.guide_id
   where sv.id = new.service_id and sv.guide_id = new.guide_id
     and sv.is_active and g.is_verified;
  if not found then
    raise exception 'This service is not available for booking.';
  end if;
  if new.scheduled_at < now() + interval '2 hours' then
    raise exception 'Choose a time at least 2 hours from now.';
  end if;
  new.service_title := s.title;
  new.price_inr     := s.price_inr;
  new.duration_min  := s.duration_min;
  new.status        := 'requested';
  new.meeting_link  := null;
  new.guide_note    := '';
  return new;
end $$;
create trigger t_prepare_booking before insert on public.bookings
  for each row execute function public.prepare_booking();

-- booking updates: each side can only make the changes that belong to them
create or replace function public.guard_booking()
returns trigger language plpgsql as $$
declare me uuid := auth.uid();
begin
  if public.is_trusted() then return new; end if;

  if new.learner_id is distinct from old.learner_id or new.guide_id is distinct from old.guide_id
     or new.service_id is distinct from old.service_id or new.service_title is distinct from old.service_title
     or new.price_inr is distinct from old.price_inr or new.duration_min is distinct from old.duration_min
     or new.scheduled_at is distinct from old.scheduled_at or new.created_at is distinct from old.created_at then
    raise exception 'Booking details cannot be changed. Cancel and book again instead.';
  end if;

  if me = old.guide_id then
    if new.learner_note is distinct from old.learner_note then
      raise exception 'Only the learner can edit their note.';
    end if;
    if new.status is distinct from old.status and not (
         (old.status = 'requested' and new.status in ('accepted','declined'))
      or (old.status = 'accepted'  and new.status in ('completed','cancelled'))) then
      raise exception 'A booking cannot move from % to %.', old.status, new.status;
    end if;
  elsif me = old.learner_id then
    if new.meeting_link is distinct from old.meeting_link or new.guide_note is distinct from old.guide_note then
      raise exception 'Only the guide can change the meeting link or guide note.';
    end if;
    if new.status is distinct from old.status and not
       (old.status in ('requested','accepted') and new.status = 'cancelled') then
      raise exception 'You can only cancel a requested or accepted booking.';
    end if;
  else
    raise exception 'Not allowed.';
  end if;
  return new;
end $$;
create trigger t_guard_booking before update on public.bookings
  for each row execute function public.guard_booking();

-- scorecards: work out the overall score from the criteria
create or replace function public.score_overall()
returns trigger language plpgsql as $$
begin
  select round(avg((c->>'score')::numeric), 1) into new.overall
    from jsonb_array_elements(new.criteria) c
   where (c->>'score') ~ '^[0-5]$';
  return new;
end $$;
create trigger t_score_overall before insert or update on public.scorecards
  for each row execute function public.score_overall();

-- ---------- Row-level security ---------------------------------------------

alter table public.profiles         enable row level security;
alter table public.contacts         enable row level security;
alter table public.learner_profiles enable row level security;
alter table public.guide_profiles   enable row level security;
alter table public.services         enable row level security;
alter table public.bookings         enable row level security;
alter table public.scorecards       enable row level security;
alter table public.reviews          enable row level security;

-- profiles: your own, verified guides (public), people you have a booking with, admins see all
create policy profiles_read on public.profiles for select using (
  id = auth.uid()
  or public.is_admin()
  or exists (select 1 from public.guide_profiles g where g.user_id = profiles.id and g.is_verified)
  or exists (select 1 from public.bookings b
             where (b.learner_id = profiles.id and b.guide_id = auth.uid())
                or (b.guide_id = profiles.id and b.learner_id = auth.uid()))
);
create policy profiles_update on public.profiles for update
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

-- contacts: private
create policy contacts_read on public.contacts for select using (user_id = auth.uid() or public.is_admin());
create policy contacts_update on public.contacts for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- learner profiles: own, admins, and guides the learner has booked
create policy learner_read on public.learner_profiles for select using (
  user_id = auth.uid() or public.is_admin()
  or exists (select 1 from public.bookings b where b.learner_id = learner_profiles.user_id and b.guide_id = auth.uid())
);
create policy learner_insert on public.learner_profiles for insert with check (user_id = auth.uid());
create policy learner_update on public.learner_profiles for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- guide profiles: verified ones are public
create policy guide_read on public.guide_profiles for select using (
  is_verified or user_id = auth.uid() or public.is_admin()
  or exists (select 1 from public.bookings b where b.guide_id = guide_profiles.user_id and b.learner_id = auth.uid())
);
create policy guide_insert on public.guide_profiles for insert with check (
  user_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'guide')
);
create policy guide_update on public.guide_profiles for update
  using (user_id = auth.uid() or public.is_admin()) with check (user_id = auth.uid() or public.is_admin());

-- services: active services of verified guides are public; guides manage their own
create policy services_read on public.services for select using (
  guide_id = auth.uid() or public.is_admin()
  or (is_active and exists (select 1 from public.guide_profiles g where g.user_id = services.guide_id and g.is_verified))
);
create policy services_insert on public.services for insert with check (guide_id = auth.uid());
create policy services_update on public.services for update
  using (guide_id = auth.uid()) with check (guide_id = auth.uid());
create policy services_delete on public.services for delete using (guide_id = auth.uid());

-- bookings: only the two people involved (and admins)
create policy bookings_read on public.bookings for select using (
  learner_id = auth.uid() or guide_id = auth.uid() or public.is_admin()
);
create policy bookings_insert on public.bookings for insert with check (learner_id = auth.uid());
create policy bookings_update on public.bookings for update
  using (learner_id = auth.uid() or guide_id = auth.uid() or public.is_admin())
  with check (learner_id = auth.uid() or guide_id = auth.uid() or public.is_admin());

-- scorecards: written by the guide, read by both sides
create policy scorecards_read on public.scorecards for select using (
  public.is_admin() or exists (select 1 from public.bookings b where b.id = scorecards.booking_id
                               and (b.learner_id = auth.uid() or b.guide_id = auth.uid()))
);
create policy scorecards_write on public.scorecards for insert with check (
  exists (select 1 from public.bookings b where b.id = scorecards.booking_id
          and b.guide_id = auth.uid() and b.status in ('accepted','completed'))
);
create policy scorecards_update on public.scorecards for update using (
  exists (select 1 from public.bookings b where b.id = scorecards.booking_id and b.guide_id = auth.uid())
) with check (
  exists (select 1 from public.bookings b where b.id = scorecards.booking_id and b.guide_id = auth.uid())
);

-- reviews: public; only the learner of a completed session can write one
create policy reviews_read on public.reviews for select using (true);
create policy reviews_insert on public.reviews for insert with check (
  learner_id = auth.uid() and exists (
    select 1 from public.bookings b where b.id = reviews.booking_id and b.learner_id = auth.uid()
      and b.guide_id = reviews.guide_id and b.status = 'completed')
);

-- ---------- Public directory view ------------------------------------------

create view public.guide_directory with (security_invoker = true) as
select g.user_id as guide_id,
       p.full_name,
       g.headline,
       g.field,
       g.years_experience,
       g.bio,
       g.linkedin_url,
       g.availability,
       (select min(s.price_inr) from public.services s where s.guide_id = g.user_id and s.is_active) as from_price,
       (select round(avg(r.rating)::numeric, 1) from public.reviews r where r.guide_id = g.user_id) as rating,
       (select count(*) from public.reviews r where r.guide_id = g.user_id) as review_count
  from public.guide_profiles g
  join public.profiles p on p.id = g.user_id
 where g.is_verified;

-- ---------- Privileges --------------------------------------------------------
-- Supabase grants these by default; they are listed so the file also works elsewhere.

grant usage on schema public to anon, authenticated;
-- anon needs select on bookings only because policies look it up; RLS returns no rows to visitors
grant select on public.profiles, public.guide_profiles, public.services, public.reviews,
                public.bookings, public.guide_directory to anon;
revoke insert, update, delete on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;
revoke delete on public.profiles, public.contacts, public.bookings, public.reviews from authenticated;
