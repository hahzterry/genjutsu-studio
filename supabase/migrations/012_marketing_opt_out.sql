-- Marketing email opt-out (2026-10-23). Additive only: one nullable column.
-- Set by the unsubscribe edge function (service role); clients only read their own profile row.
begin;
alter table public.profiles add column if not exists marketing_opt_out_at timestamptz;
commit;
