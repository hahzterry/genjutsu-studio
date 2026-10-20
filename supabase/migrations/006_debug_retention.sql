-- Reproducibility (2026-10-21): keep the provider's raw replies for failed jobs, owner-only,
-- and keep uploads for a fixed retention window instead of deleting them when a job ends.

create table if not exists public.job_debug (
  job_id        uuid primary key references public.jobs(id) on delete cascade,
  submit_status integer,          -- HTTP status of the submit call
  submit_body   text,             -- raw submit reply (truncated)
  final_body    text,             -- raw status reply when the job ended badly (truncated)
  updated_at    timestamptz not null default now()
);
alter table public.job_debug enable row level security;   -- no policies: clients can never read it
revoke all on public.job_debug from public, anon, authenticated;

-- Uploads older than p_days (paths inside the private "inputs" bucket), for the retention sweep.
create or replace function public.expired_inputs(p_days integer, p_limit integer) returns setof text
language sql security definer set search_path = public, storage as $$
  select name from storage.objects
   where bucket_id = 'inputs' and created_at < now() - make_interval(days => greatest(p_days, 1))
   order by created_at limit least(greatest(p_limit, 1), 1000)
$$;
revoke execute on function public.expired_inputs(integer, integer) from public, anon, authenticated;
