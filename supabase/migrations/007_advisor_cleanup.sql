-- Supabase advisor cleanup (2026-10-21). Additive / in-place only: no drops, no renames.
begin;

-- keepalive reads no table (select 1), but run it with the caller's rights so the
-- "security definer view" lint is gone. anon keeps its SELECT grant from 004.
alter view public.keepalive set (security_invoker = true);

-- handle_new_user is only a trigger on auth.users; nobody should call it over /rest/v1/rpc.
-- The Auth service (supabase_auth_admin) inserts users, so it keeps EXECUTE explicitly.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.handle_new_user() to supabase_auth_admin;

-- Index for the payments -> users foreign key (dashboard and per-user lookups).
create index if not exists payments_user on public.payments (user_id);

-- Same policies, faster form: (select auth.uid()) is evaluated once per query, not per row.
alter policy "own profile"  on public.profiles using ((select auth.uid()) = user_id);
alter policy "own payments" on public.payments using ((select auth.uid()) = user_id);
alter policy "own jobs"     on public.jobs     using ((select auth.uid()) = user_id);

commit;
