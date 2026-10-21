-- Job emails (2026-10-21): when the "ready" / "didn't come out" email was sent. Set once by a conditional
-- update (where notified_at is null), so each job is emailed at most once. Additive.
alter table public.jobs add column if not exists notified_at timestamptz;
