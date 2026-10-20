-- Spending caps (2026-10-20). After strangers ran real renders on sandbox credits, every
-- real render is admitted by one atomic check: per-user daily count + site-wide daily spend.

alter table public.jobs add column if not exists mock boolean not null default false;
alter table public.jobs add column if not exists surcharge integer;           -- extra credits if the output ran longer than billed
alter table public.payments add column if not exists clawed_at timestamptz;
alter table public.profiles add column if not exists frozen boolean not null default false; -- set on a PayPal dispute
create index if not exists jobs_created on public.jobs (created_at desc);

-- Holds the credits and inserts the job in one transaction, under a lock, so concurrent
-- requests can't slip past the caps. Returns the job id, or null with p_reason set.
create or replace function public.create_job(
  p_user uuid, p_trend text, p_workflow text, p_resolution text, p_prompt text,
  p_video_url text, p_image_urls jsonb, p_cost integer, p_billed_secs integer, p_mock boolean,
  p_user_daily_jobs integer, p_user_daily_credits integer, p_site_daily_credits integer,
  out job_id uuid, out reason text
) language plpgsql security definer set search_path = public as $$
declare v_user_jobs integer; v_user_credits integer; v_site_credits integer;
begin
  if p_cost is null or p_cost <= 0 then reason := 'bad_cost'; return; end if;
  if p_user_daily_jobs is null or p_user_daily_credits is null or p_site_daily_credits is null
     or p_user_daily_jobs < 1 or p_user_daily_credits < 1 or p_site_daily_credits < 1 then
    reason := 'bad_config'; return;
  end if;
  perform pg_advisory_xact_lock(hashtext('genjutsu_create_job'));
  if exists (select 1 from profiles where user_id = p_user and frozen) then reason := 'frozen'; return; end if;
  if not p_mock then
    -- Refunded (failed / nsfw / canceled) jobs cost nothing, so they don't count.
    select count(*) into v_user_jobs from jobs
     where user_id = p_user and not mock and not refunded and created_at > now() - interval '24 hours';
    if v_user_jobs >= p_user_daily_jobs then reason := 'user_limit'; return; end if;
    select coalesce(sum(cost), 0) into v_user_credits from jobs
     where user_id = p_user and not mock and not refunded and created_at > now() - interval '24 hours';
    if v_user_credits + p_cost > p_user_daily_credits then reason := 'user_limit'; return; end if;
    select coalesce(sum(cost), 0) into v_site_credits from jobs
     where not mock and not refunded and created_at > now() - interval '24 hours';
    if v_site_credits + p_cost > p_site_daily_credits then reason := 'site_limit'; return; end if;
  end if;
  update profiles set credits = credits - p_cost where user_id = p_user and credits >= p_cost;
  if not found then reason := 'no_credits'; return; end if;
  insert into jobs (user_id, trend, workflow, resolution, prompt, video_url, image_urls, cost, billed_secs, mock)
  values (p_user, p_trend, p_workflow, p_resolution, p_prompt, p_video_url, p_image_urls, p_cost, p_billed_secs, p_mock)
  returning id into job_id;
end $$;
revoke execute on function public.create_job(uuid, text, text, text, text, text, jsonb, integer, integer, boolean, integer, integer, integer)
  from public, anon, authenticated;

update public.jobs set mock = true where hf_request_id like 'mock:%';

-- Same as 004, plus clawed_at so the daily report sees chargebacks on older payments.
create or replace function public.claw_payment(p_order_id text, p_target integer) returns integer
language plpgsql security definer set search_path = public as $$
declare v_user uuid; v_prev integer; v_delta integer;
begin
  select user_id, clawed_credits into v_user, v_prev from payments
   where order_id = p_order_id and status = 'completed' for update;
  if v_user is null or p_target <= v_prev then return 0; end if;
  v_delta := p_target - v_prev;
  update payments set clawed_credits = p_target, clawed_at = now() where order_id = p_order_id;
  update profiles set credits = credits - v_delta where user_id = v_user;
  return v_delta;
end $$;
revoke execute on function public.claw_payment(text, integer) from public, anon, authenticated;

-- Aggregates for the owner's daily report (no emails or other personal data leave the DB).
create or replace function public.usage_report() returns jsonb
language sql security definer set search_path = public as $$
  with w(label, since) as (values ('24h', now() - interval '24 hours'), ('7d', now() - interval '7 days'))
  select jsonb_object_agg(label, jsonb_build_object(
    'signups',           (select count(*) from auth.users where created_at > since),
    'payments',          (select count(*) from payments where status = 'completed' and completed_at > since),
    'payments_usd',      (select coalesce(sum(usd), 0) from payments where status = 'completed' and completed_at > since),
    'clawed_credits',    (select coalesce(sum(clawed_credits), 0) from payments where clawed_at > since),
    'frozen_accounts',   (select count(*) from profiles where frozen),
    'jobs_to_reconcile', (select count(*) from jobs where not mock and (status = 'submit_unknown'
                            or (status = 'submitting' and created_at < now() - interval '10 minutes'))),
    'renders_started',   (select count(*) from jobs where not mock and created_at > since),
    'renders_completed', (select count(*) from jobs where not mock and status = 'completed' and created_at > since),
    'renders_failed',    (select count(*) from jobs where not mock and status in ('failed','nsfw','canceled') and created_at > since),
    'render_secs',       (select coalesce(sum(billed_secs), 0) from jobs where not mock and status = 'completed' and created_at > since),
    'credits_spent',     (select coalesce(sum(cost), 0) from jobs where not mock and not refunded and created_at > since),
    'users_making_videos', (select count(distinct user_id) from jobs where not mock and created_at > since)
  )) from w
$$;
revoke execute on function public.usage_report() from public, anon, authenticated;

-- Output ran longer than it was billed: charge the difference once (balance may go negative = debt).
create or replace function public.charge_surcharge(p_job uuid, p_credits integer) returns integer
language plpgsql security definer set search_path = public as $$
declare v_user uuid;
begin
  if p_credits <= 0 then return 0; end if;
  update jobs set surcharge = p_credits where id = p_job and surcharge is null returning user_id into v_user;
  if v_user is null then return 0; end if;
  update profiles set credits = credits - p_credits where user_id = v_user;
  return p_credits;
end $$;
revoke execute on function public.charge_surcharge(uuid, integer) from public, anon, authenticated;
