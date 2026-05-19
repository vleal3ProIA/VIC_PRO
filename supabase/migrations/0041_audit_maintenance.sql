-- ============================================================================
-- 0041 · Audit Center: helpers de mantenimiento (PR-Audit-4)
-- ----------------------------------------------------------------------------
-- Cierra el lote V1 anyadiendo dos operaciones de mantenimiento que se
-- invocan **externamente** (no via pg_cron -- no esta disponible en plan
-- Supabase free):
--
-- 1. `admin_audit_recover_stuck()`  Marca como 'failed' los reports
--    que llevan status='running' > 30 min. Esto pasa si la Edge
--    Function `run-audit` muere a mitad (deploy, OOM, crash) y la row
--    quedaria stuck para siempre, falseando el polling de la UI y
--    el rate-limit.
--
-- 2. `admin_audit_purge_old(p_older_than)`  Borra reports > 90 dias.
--    Los reports historicos viejos no aportan valor (los findings
--    suelen estar resueltos hace tiempo) y consumen storage. Vienen
--    con default 90d pero el admin puede pasar otro intervalo si
--    quiere ser mas / menos agresivo.
--
-- **Invocacion**: ambas son RPCs admin-only (`is_admin()`). El plan
-- de ejecucion es uno de:
--   - GitHub Actions cron job que llama a la RPC con un PAT admin.
--   - Supabase Pro/Team: Cron Jobs nativo via dashboard.
--   - Manual desde /admin/audit > "Maintenance" (futura UI).
--
-- Ambas devuelven `int` con el numero de rows afectadas, util para
-- logging y para diagnosticar (0 = todo limpio).
-- ============================================================================

-- ─────────────── RPC: admin_audit_recover_stuck ───────────────
-- Marca como 'failed' los audits cuyo status='running' lleva > 30 min.
-- Es defensivo: en operacion normal un audit completo dura ~10s, asi
-- que 30min es 180x el tiempo normal -- razonablemente seguro.
--
-- El campo `error` se rellena con un marcador para que el admin sepa
-- por que aparece como failed (no fue un check que crasheo, fue el
-- container que murio).

create or replace function public.admin_audit_recover_stuck()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  update public.audit_reports
  set status      = 'failed',
      error       = 'stuck_recovered: audit was running > 30 min and was '
                 || 'marked failed by maintenance. The Edge Function probably '
                 || 'died mid-run (deploy, OOM, timeout). No data loss -- just '
                 || 'rerun.',
      finished_at = coalesce(finished_at, now())
  where status = 'running'
    and started_at < now() - interval '30 minutes';

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke all on function public.admin_audit_recover_stuck() from public;
grant execute on function public.admin_audit_recover_stuck()
  to authenticated;

-- ─────────────── RPC: admin_audit_purge_old ───────────────
-- Borra reports antiguos. Default `90 days` -- el admin puede pasar
-- otro intervalo. Min 7 dias por seguridad (evitar nuke-todo accidental
-- con `p_older_than => '1 hour'`).
--
-- Nota: NO usamos soft-delete -- los reports historicos no se referencian
-- desde ningun otro lado, asi que un DELETE limpio es seguro.

create or replace function public.admin_audit_purge_old(
  p_older_than interval default interval '90 days'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
  v_min     interval := interval '7 days';
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  -- Floor de 7 dias para evitar accidentes (`'1 hour'` purga todos
  -- los reports).
  if p_older_than < v_min then
    p_older_than := v_min;
  end if;

  delete from public.audit_reports
  where started_at < now() - p_older_than;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.admin_audit_purge_old(interval) from public;
grant execute on function public.admin_audit_purge_old(interval)
  to authenticated;
