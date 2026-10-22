-- Nightly backup + daily database audit (2026-10-22). Additive only: two new read-only functions.
-- Both are security definer, callable only by service_role (the backup / daily-report edge functions).
begin;

-- Every base table in public (found at run time, so a new table is backed up automatically), plus the
-- auth.users columns needed to restore accounts. The edge function encrypts this before it leaves Supabase.
create or replace function public.backup_snapshot() returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; v_rows jsonb; v_tables jsonb := '{}'::jsonb;
begin
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p') order by 1 loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I t', r.relname) into v_rows;
    v_tables := v_tables || jsonb_build_object(r.relname, v_rows);
  end loop;
  return jsonb_build_object(
    'taken_at', now(),
    'tables', v_tables,
    'auth_users', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'email', email, 'created_at', created_at,
                     'email_confirmed_at', email_confirmed_at, 'last_sign_in_at', last_sign_in_at) order by created_at), '[]'::jsonb)
                   from auth.users));
end $$;
revoke execute on function public.backup_snapshot() from public, anon, authenticated;

-- Structure and health of the database, without personal data: tables (RLS, policies, row counts),
-- functions callable by site visitors, storage buckets, and money sanity checks.
create or replace function public.schema_audit() returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; v_n bigint; v_tables jsonb := '[]'::jsonb;
begin
  for r in select c.relname, c.relkind, c.relrowsecurity
             from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') order by 1 loop
    v_n := null;
    if r.relkind in ('r', 'p') then execute format('select count(*) from public.%I', r.relname) into v_n; end if;
    v_tables := v_tables || jsonb_build_object('name', r.relname,
      'kind', case r.relkind when 'v' then 'view' when 'm' then 'matview' else 'table' end,
      'rls', r.relrowsecurity, 'rows', v_n,
      'policies', (select coalesce(jsonb_agg(policyname order by policyname), '[]'::jsonb) from pg_policies
                    where schemaname = 'public' and tablename = r.relname));
  end loop;
  return jsonb_build_object(
    'tables', v_tables,
    'visitor_functions', (select coalesce(jsonb_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' order by p.proname), '[]'::jsonb)
                            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname = 'public'
                             and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
    'buckets', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'public', public) order by id), '[]'::jsonb) from storage.buckets),
    'checks', jsonb_build_object(
      'users_without_profile', (select count(*) from auth.users u where not exists (select 1 from profiles p where p.user_id = u.id)),
      'negative_balances', (select count(*) from profiles where credits < 0),
      -- More credits than the user ever bought (minus chargebacks): credits appeared from nowhere.
      'balance_above_purchases', (select coalesce(jsonb_agg(p.user_id), '[]'::jsonb) from profiles p
                                   where p.credits > (select coalesce(sum(x.credits - coalesce(x.clawed_credits, 0)), 0)
                                                        from payments x where x.user_id = p.user_id and x.status = 'completed')),
      'credits_outstanding', (select coalesce(sum(credits), 0) from profiles),
      'completed_jobs_without_cost', (select count(*) from jobs where status = 'completed' and not mock and (cost is null or cost <= 0 or billed_secs is null)),
      'old_unfinished_jobs', (select count(*) from jobs where status in ('queued', 'in_progress', 'submitting') and created_at < now() - interval '2 hours'),
      'old_created_payments', (select count(*) from payments where status = 'created' and created_at < now() - interval '1 day' and created_at > now() - interval '8 days')
    ));
end $$;
revoke execute on function public.schema_audit() from public, anon, authenticated;

commit;
