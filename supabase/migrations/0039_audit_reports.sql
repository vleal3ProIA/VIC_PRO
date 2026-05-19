-- ============================================================================
-- 0039 · Audit Center: tabla audit_reports + RPCs (PR-Audit-1)
-- ----------------------------------------------------------------------------
-- Tabla para persistir los resultados de auditoria del sistema que el
-- admin ejecuta desde /admin/audit. Cada ejecucion = 1 fila.
--
-- **Modelo**:
--   - `started_at` / `finished_at` : duracion de la auditoria.
--   - `status`                     : ciclo de vida 'running' / 'completed' /
--                                    'failed'.
--   - `triggered_by`               : admin que lanzo la auditoria
--                                    (auditoria de auditorias).
--   - `findings`                   : jsonb con array de findings detallados.
--                                    Cada finding tiene { check_id, title,
--                                    severity, impact, recommendation,
--                                    affected_count, details }.
--   - `summary`                    : jsonb agregado para listas. Estructura:
--                                    { "by_severity": {critical: 0, high: 2,
--                                    medium: 5, low: 3, info: 12},
--                                    "total_checks_run": 12, "duration_ms":
--                                    4350 }.
--   - `error`                      : texto si status='failed' (truncado a 500).
--
-- **RLS**: SELECT admin-only. INSERT/UPDATE solo service_role (lo hace
-- la Edge Function `run-audit`).
--
-- **No tiene FKs duras a tablas internas** -- los `findings` referencian
-- entidades del sistema (uploads, broadcasts, users) por id en `details`
-- pero no como FKs reales: si la entidad se borra, el report historico
-- debe seguir mostrandose para no perder rastro de incidentes pasados.
--
-- **Retencion**: por ahora SIN purga automatica. Un cron futuro podra
-- borrar reportes > 90 dias. El volumen esperado es bajo (~ 1 audit por
-- semana en uso tipico) asi que no es urgente.
-- ============================================================================

create table if not exists public.audit_reports (
  id            uuid primary key default gen_random_uuid(),
  started_at    timestamptz not null default now(),
  finished_at   timestamptz,
  status        text not null default 'running'
                check (status in ('running', 'completed', 'failed')),
  triggered_by  uuid references auth.users(id) on delete set null,
  findings      jsonb not null default '[]'::jsonb,
  summary       jsonb not null default '{}'::jsonb,
  error         text
);

-- Index para la query mas comun: lista de los N reports mas recientes.
create index if not exists audit_reports_started_idx
  on public.audit_reports (started_at desc);

-- Index parcial para encontrar audits "atascados" (status running > 1h).
-- Un cron futuro los marcara como failed.
create index if not exists audit_reports_stuck_idx
  on public.audit_reports (started_at)
  where status = 'running';

-- ─────────────────────────── RLS ───────────────────────────
-- SELECT: solo admin. Los reports contienen detalles del sistema que
-- podrian filtrar info sensible a un user normal (ej. emails de
-- otros users, paths de uploads).
-- INSERT/UPDATE: solo service_role (Edge Function `run-audit`).
-- DELETE: no se expone -- los reports historicos son inmutables.

alter table public.audit_reports enable row level security;

drop policy if exists "audit_reports_admin_select" on public.audit_reports;
create policy "audit_reports_admin_select"
  on public.audit_reports for select
  using (public.is_admin());

-- ─────────────── RPC: admin_audit_reports_list ───────────────
-- Devuelve los N reports mas recientes, sin el campo `findings`
-- completo (pesado). El detalle se pide aparte por id.
--
-- Estructura devuelta (TABLE):
--   id, started_at, finished_at, status, summary, triggered_by

create or replace function public.admin_audit_reports_list(
  p_limit int default 20
)
returns table (
  id            uuid,
  started_at    timestamptz,
  finished_at   timestamptz,
  status        text,
  summary       jsonb,
  triggered_by  uuid
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
  select
    r.id, r.started_at, r.finished_at, r.status, r.summary, r.triggered_by
  from public.audit_reports r
  order by r.started_at desc
  limit greatest(1, least(coalesce(p_limit, 20), 100));
end;
$$;

revoke all on function public.admin_audit_reports_list(int) from public;
grant execute on function public.admin_audit_reports_list(int)
  to authenticated;

-- ─────────────── RPC: admin_audit_report_detail ───────────────
-- Devuelve un report completo incluido findings.

create or replace function public.admin_audit_report_detail(
  p_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  select to_jsonb(r.*) into v_result
  from public.audit_reports r
  where r.id = p_id;

  if v_result is null then
    raise exception 'report_not_found';
  end if;
  return v_result;
end;
$$;

revoke all on function public.admin_audit_report_detail(uuid) from public;
grant execute on function public.admin_audit_report_detail(uuid)
  to authenticated;
