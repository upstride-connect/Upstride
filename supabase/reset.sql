-- Removes everything schema.sql creates, so it can be run again from scratch.
-- WARNING: deletes all Upstride data (accounts in auth.users are kept).
drop trigger if exists on_auth_user_created on auth.users;
drop view if exists public.guide_directory;
drop table if exists public.reviews, public.scorecards, public.bookings, public.services,
  public.guide_profiles, public.learner_profiles, public.contacts, public.profiles cascade;
drop function if exists public.handle_new_user(), public.guard_profile(), public.guard_guide_profile(),
  public.prepare_booking(), public.guard_booking(), public.score_overall(), public.touch_updated_at(),
  public.is_admin(), public.is_trusted(), public.pick(text, text[]);
drop domain if exists public.career_field;
