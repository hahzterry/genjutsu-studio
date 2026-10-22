-- Genjutsu Light for custom uploads (2026-10-22). Additive only: a new column with a default and a new
-- create_job overload. The 13-argument create_job from 005 stays, so the previous generate keeps working
-- during the deploy (its jobs get model 'full'; Light presets are still recognised by file name).
begin;

alter table public.jobs add column if not exists model text not null default 'full';
alter table public.jobs drop constraint if exists jobs_model_check;
alter table public.jobs add constraint jobs_model_check check (model in ('full', 'light'));

create or replace function public.create_job(
  p_user uuid, p_trend text, p_workflow text, p_resolution text, p_prompt text,
  p_video_url text, p_image_urls jsonb, p_cost integer, p_billed_secs integer, p_mock boolean,
  p_user_daily_jobs integer, p_user_daily_credits integer, p_site_daily_credits integer, p_model text,
  out job_id uuid, out reason text
) language plpgsql security definer set search_path = public as $$
declare v_user_jobs integer; v_user_credits integer; v_site_credits integer;
begin
  if p_cost is null or p_cost <= 0 then reason := 'bad_cost'; return; end if;
  if p_model is null or p_model not in ('full', 'light') then reason := 'bad_config'; return; end if;
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
  insert into jobs (user_id, trend, workflow, resolution, prompt, video_url, image_urls, cost, billed_secs, mock, model)
  values (p_user, p_trend, p_workflow, p_resolution, p_prompt, p_video_url, p_image_urls, p_cost, p_billed_secs, p_mock, p_model)
  returning id into job_id;
end $$;
revoke execute on function public.create_job(uuid, text, text, text, text, text, jsonb, integer, integer, boolean, integer, integer, integer, text)
  from public, anon, authenticated;

-- Existing Light jobs (presets/light-*) get the right model for the dashboard and reports.
update public.jobs set model = 'light' where model = 'full' and video_url like '%/storage/v1/object/public/presets/light-%';

commit;
