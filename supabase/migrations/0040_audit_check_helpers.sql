-- ============================================================================
-- 0040 · Audit Center: RPCs helper para checks de RLS (PR-Audit-2)
-- ----------------------------------------------------------------------------
-- Los checks `rls.coverage` y `rls.no_policies` necesitan inspeccionar
-- pg_catalog (pg_tables, pg_policies). Como esos catalogos no son
-- accesibles directamente por roles `authenticated` / `service_role`
-- via PostgREST, exponemos RPCs SECURITY DEFINER que devuelven la
-- info necesaria para los checks. Solo admin puede invocarlas.
-- ============================================================================

-- ─────────────── RPC: admin_audit_tables_without_rls ───────────────
-- Devuelve tablas en el schema `public` que NO tienen Row Level Security
-- habilitado. Excluye tablas internas (pg_*, schema_migrations).
--
-- **Riesgo de finding**: critical. Sin RLS, cualquier user autenticado
-- puede leer/escribir cualquier fila via PostgREST.

create or replace function public.admin_audit_tables_without_rls()
returns table (table_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  return query
  select t.tablename::text
  from pg_tables t
  where t.schemaname = 'public'
    and t.rowsecurity = false
    -- Excluimos sistema (no aplica, pg_tables ya filtra schema, pero
    -- por defensa-en-profundidad).
    and t.tablename not like 'pg_%'
    and t.tablename not like '_supabase_%';
end;
$$;

revoke all on function public.admin_audit_tables_without_rls() from public;
grant execute on function public.admin_audit_tables_without_rls()
  to authenticated;

-- ─────────────── RPC: admin_audit_tables_no_policies ───────────────
-- Tablas que TIENEN RLS habilitado pero NO tienen ninguna policy.
-- Resultado: bloqueadas TOTAL para users normales (efectivamente
-- inaccesibles via PostgREST). Suele ser intencional (auditoria
-- append-only), pero merece revision.

create or replace function public.admin_audit_tables_no_policies()
returns table (table_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
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

revoke all on function public.admin_audit_tables_no_policies() from public;
grant execute on function public.admin_audit_tables_no_policies()
  to authenticated;

-- ─────────────── RPC: admin_audit_mfa_admin_coverage ───────────────
-- Devuelve agregado de admins con/sin MFA. Si hay admins sin MFA es
-- finding 'high' -- esos admins son un compromise punto unico.
--
-- MFA enabled = el user tiene al menos un factor 'verified' en
-- auth.mfa_factors (TOTP).

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
  if not public.is_admin() then
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
    (select count(*)::int from admins)                              as total_admins,
    (select count(*)::int from admins_with_mfa)                     as with_mfa,
    (select count(*)::int from admins) -
      (select count(*)::int from admins_with_mfa)                   as without_mfa,
    coalesce(
      array(
        select a.id from admins a
        where a.id not in (select user_id from admins_with_mfa)
      ),
      array[]::uuid[]
    )                                                                as admins_without_mfa_ids;
end;
$$;

revoke all on function public.admin_audit_mfa_admin_coverage() from public;
grant execute on function public.admin_audit_mfa_admin_coverage()
  to authenticated;

-- ─────────────── RPC: admin_audit_email_failure_rate ───────────────
-- Calcula el % de emails fallidos en los ultimos N dias (default 7).
-- Si la tasa > 20% es finding 'high' (problema de SMTP / bouncing).

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
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  return query
  with stats as (
    select
      count(*)::int                                                 as total_rows,
      count(*) filter (where status = 'failed')::int                as failed_rows
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

revoke all on function public.admin_audit_email_failure_rate(int) from public;
grant execute on function public.admin_audit_email_failure_rate(int)
  to authenticated;
