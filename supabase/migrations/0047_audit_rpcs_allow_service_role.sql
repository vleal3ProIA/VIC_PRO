-- ============================================================================
-- 0047 · Audit RPCs: permitir service_role / SQL Editor (sin auth context)
-- ----------------------------------------------------------------------------
-- Las 4 RPCs de 0040 (`admin_audit_*`) rechazaban toda llamada sin
-- `is_admin() = true`. Pero la Edge Function `run-audit` crea un
-- cliente con `service_role`, donde `auth.uid()` es NULL --
-- consecuentemente `is_admin()` devuelve false y la llamada cae con
-- "admin only".
--
-- Sintoma visible: en cada audit, 4 findings tipo `audit.check_failed`
-- con detail `{"error": "admin only"}`:
--   - rls.coverage failed
--   - rls.no_policies failed
--   - auth.mfa_admin_coverage failed
--   - emails.failure_rate failed
--
-- **Fix**: aplicar el mismo patron que usamos en 0044
-- (`prevent_super_admin_escalation`): permitir el paso cuando
-- `auth.uid() IS NULL` (contexto de confianza: service_role, SQL
-- Editor, cron). Si hay sesion authenticated, seguimos exigiendo
-- `is_admin()`.
--
-- Semantica: "is_admin() true O caller sin auth context".
--
-- **NO es una bajada de seguridad**: service_role ya bypassea RLS y
-- ya tiene poder ilimitado en la BD. Solo desbloqueamos el uso
-- legitimo de estas RPCs desde Edge Functions, que es para lo que
-- existen.
--
-- Migracion: CREATE OR REPLACE las 4 funciones con el guard relajado.
-- Las firmas (return type + args) no cambian. Sin downtime.
-- ============================================================================

-- ─────────────── 1) admin_audit_tables_without_rls ───────────────

create or replace function public.admin_audit_tables_without_rls()
returns table (table_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Bypass para service_role / SQL Editor (auth.uid() IS NULL).
  -- Mismo patron que `prevent_super_admin_escalation` (0044).
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'admin only';
  end if;

  return query
  select t.tablename::text
  from pg_tables t
  where t.schemaname = 'public'
    and t.rowsecurity = false
    and t.tablename not like 'pg_%'
    and t.tablename not like '_supabase_%';
end;
$$;

-- ─────────────── 2) admin_audit_tables_no_policies ───────────────

create or replace function public.admin_audit_tables_no_policies()
returns table (table_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'admin only';
  end if;

  return query
  select t.tablename::text
  from pg_tables t
  where t.schemaname = 'public'
    and t.rowsecurity = true
    and not exists (
      select 1 from pg_policies p
      where p.schemaname = t.schemaname
        and p.tablename = t.tablename
    )
    and t.tablename not like 'pg_%'
    and t.tablename not like '_supabase_%';
end;
$$;

-- ─────────────── 3) admin_audit_mfa_admin_coverage ───────────────

create or replace function public.admin_audit_mfa_admin_coverage()
returns table (
  total_admins  int,
  with_mfa      int,
  without_mfa   int,
  admins_without_mfa_ids uuid[]
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'admin only';
  end if;

  return query
  with admins as (
    select pf.id
    from public.profiles pf
    where pf.role = 'admin'
  ),
  admins_with_mfa as (
    select distinct f.user_id
    from auth.mfa_factors f
    where f.status = 'verified'
      and f.user_id in (select id from admins)
  )
  select
    (select count(*)::int from admins),
    (select count(*)::int from admins_with_mfa),
    (select count(*)::int from admins) -
      (select count(*)::int from admins_with_mfa),
    coalesce(
      array(
        select a.id from admins a
        where a.id not in (select user_id from admins_with_mfa)
      ),
      array[]::uuid[]
    );
end;
$$;

-- ─────────────── 4) admin_audit_email_failure_rate ───────────────

create or replace function public.admin_audit_email_failure_rate(
  p_days int default 7
)
returns table (
  total     int,
  failed    int,
  rate_pct  numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'admin only';
  end if;

  return query
  with stats as (
    select
      count(*)::int                                    as total_rows,
      count(*) filter (where status = 'failed')::int   as failed_rows
    from public.email_log
    where created_at > now() - make_interval(days => greatest(1, p_days))
  )
  select
    total_rows,
    failed_rows,
    case
      when total_rows = 0 then 0
      else round((failed_rows::numeric * 100 / total_rows::numeric), 2)
    end
  from stats;
end;
$$;

-- Sin cambios en grants -- las funciones ya estaban GRANTed a
-- `authenticated` desde 0040. service_role siempre puede ejecutar
-- funciones SECURITY DEFINER por definicion (es superuser).

comment on function public.admin_audit_tables_without_rls() is
  'PR-Audit-2, fixed by 0047. Bypass auth.uid() IS NULL para que '
  'run-audit Edge Function (service_role) pueda invocar.';
comment on function public.admin_audit_tables_no_policies() is
  'PR-Audit-2, fixed by 0047. Idem bypass service_role.';
comment on function public.admin_audit_mfa_admin_coverage() is
  'PR-Audit-2, fixed by 0047. Idem bypass service_role.';
comment on function public.admin_audit_email_failure_rate(int) is
  'PR-Audit-2, fixed by 0047. Idem bypass service_role.';
