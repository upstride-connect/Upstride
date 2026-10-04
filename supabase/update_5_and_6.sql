-- Upstride database updates 5 and 6 in one file (30 Sep 2026).
-- Run once in Supabase: SQL Editor -> New query -> paste all of this -> Run. Safe to run again.

-- Update 5 (30 Sep 2026): only learner accounts can book sessions.
-- Run once in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.

create or replace function public.prepare_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare s record; sl record;
begin
  if new.learner_id is distinct from auth.uid() and not public.is_trusted() then
    raise exception 'You can only book sessions for yourself.';
  end if;
  -- anyone signed in must hold a learner account (the SQL editor, with no signed-in user, is exempt)
  if auth.uid() is not null and not exists (select 1 from public.profiles where id = auth.uid() and role = 'learner') then
    raise exception 'Only learner accounts can book sessions.';
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
  if new.slot_id is null then
    raise exception 'Choose one of the available time slots.';
  end if;
  select * into sl from public.availability_slots where id = new.slot_id and guide_id = new.guide_id;
  if not found then
    raise exception 'That time slot is no longer available. Please choose another.';
  end if;
  if sl.starts_at < now() + interval '2 hours' then
    raise exception 'Choose a slot at least 2 hours from now.';
  end if;
  if not public.slot_is_free(new.slot_id) then
    raise exception 'That time slot has just been taken. Please choose another.';
  end if;
  new.scheduled_at  := sl.starts_at;
  new.service_title := s.title;
  new.price_inr     := s.price_inr;
  new.duration_min  := s.duration_min;
  new.status        := 'requested';
  new.meeting_link  := null;
  new.guide_note    := '';
  new.reschedule_count := 0;
  new.last_rescheduled_by := null;
  return new;
end $$;

-- Update 6 (30 Sep 2026): learners can see the UPI ID of the guide they need to pay.
-- A learner sees a guide's UPI ID only for their own sessions that the guide has accepted
-- or completed. Everyone else's payout details stay private.
-- Run once in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.

create or replace function public.my_payment_details()
returns table (booking_id uuid, upi text)
language sql stable security definer set search_path = public as $$
  select b.id, c.payout_upi
    from public.bookings b
    join public.contacts c on c.user_id = b.guide_id
   where b.learner_id = auth.uid()
     and b.status in ('accepted', 'completed')
     and c.payout_upi is not null;
$$;

revoke all on function public.my_payment_details() from public, anon;
grant execute on function public.my_payment_details() to authenticated;
