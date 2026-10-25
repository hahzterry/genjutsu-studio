-- Private video ratings + gallery consent (2026-10-25). Additive only: one new table, one nullable column. Users rate their own finished videos
-- (1–5 stars + optional comment) on My videos; only the owner's dashboard shows them, nothing is public.
-- Writes go through the jobs edge function (service role); clients can read only their own ratings.
begin;
create table if not exists public.ratings (
  job_id     uuid primary key references public.jobs(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  stars      smallint not null check (stars between 1 and 5),
  comment    text check (comment is null or char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ratings_user on public.ratings (user_id);
alter table public.ratings enable row level security;
drop policy if exists "own ratings" on public.ratings;
create policy "own ratings" on public.ratings for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.ratings from public, anon, authenticated;
grant select on public.ratings to authenticated;

-- Opt-in to show this finished video (and its prompt) in the public gallery. Null = no consent.
-- Set/cleared by the owner on My videos through the jobs edge function. A video may only be used in the
-- gallery when this is set AND the job is at least 4 days old (rule in CLAUDE.md).
alter table public.jobs add column if not exists gallery_opt_in_at timestamptz;
commit;
