-- ============================================================================
-- 0042 · Database maintenance: purgas extendidas (admin-only RPCs)
-- ----------------------------------------------------------------------------
-- Extiende el patron `admin_audit_purge_old` (migracion 0041) a tres
-- tablas mas que crecen sin limpieza automatica:
--
--   1. `audit_logs`       Eventos por user (login, upload, delete...).
--                          Default purga > 90 dias. Lo que ya no se
--                          consulta para soporte ni compliance.
--
--   2. `email_log`        Auditoria de envios SMTP. Default > 180 dias.
--                          GDPR -- los registros de envios automaticos
--                          se conservan 6 meses por defecto en la mayor
--                          parte de los DPA. Configurable.
--
--   3. `notifications`    Feed in-app. Default > 60 dias Y leidas. Las
--                          no leidas NO se purgan a menos que el caller
--                          pase `p_include_unread = true` -- proteccion
--                          contra perder info que el user aun no vio.
--
-- **Invocacion**: igual que las RPCs de 0041 -- via cron externo
-- (GitHub Actions / Supabase Pro Cron / manual). Ver
-- DEPLOYMENT.md > "Database maintenance".
--
-- **Floor de seguridad**: cada RPC tiene un minimo (audit_logs 30d,
-- email_log 60d, notifications 14d) para evitar accidentes con
-- `'1 hour'::interval`. Devuelven cuantas rows se borraron.
-- ============================================================================

-- ─────────────── RPC: admin_audit_logs_purge_old ───────────────
-- Pruga audit_logs antiguos. El user puede consultar sus eventos en
-- /activity, pero solo nos interesan los recientes para soporte. Para
-- compliance el log de admin (events tipo "upload.deleted",
-- "role.changed") deberia conservarse mas (en una tabla separada o
-- mediante export periodico antes del purge). Para este V1, default
-- 90 dias asume que esto es solo "activity feed".

create or replace function public.admin_audit_logs_purge_old(
  p_older_than interval default interval '90 days'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
  v_min     interval := interval '30 days';
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  -- Floor de seguridad: nunca borrar < 30 dias de logs.
  if p_older_than < v_min then
    p_older_than := v_min;
  end if;

  delete from public.audit_logs
  where occurred_at < now() - p_older_than;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.admin_audit_logs_purge_old(interval) from public;
grant execute on function public.admin_audit_logs_purge_old(interval)
  to authenticated;

-- ─────────────── RPC: admin_email_log_purge_old ───────────────
-- Purga email_log antiguos. Compliance: la mayoria de DPAs piden
-- conservar logs de envios 6 meses. Default 180 dias. Floor 60 dias.

create or replace function public.admin_email_log_purge_old(
  p_older_than interval default interval '180 days'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
  v_min     interval := interval '60 days';
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  if p_older_than < v_min then
    p_older_than := v_min;
  end if;

  delete from public.email_log
  where created_at < now() - p_older_than;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.admin_email_log_purge_old(interval) from public;
grant execute on function public.admin_email_log_purge_old(interval)
  to authenticated;

-- ─────────────── RPC: admin_notifications_purge_old ───────────────
-- Purga notifications viejas. Default: solo las LEIDAS y > 60 dias.
-- Las no leidas se conservan -- el user aun no las ha visto.
--
-- Si quieres limpiar agresivamente (ej. user con bandeja saturada),
-- pasa `p_include_unread => true`. Floor 14 dias en ambos casos.

create or replace function public.admin_notifications_purge_old(
  p_older_than     interval default interval '60 days',
  p_include_unread boolean  default false
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
  v_min     interval := interval '14 days';
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  if p_older_than < v_min then
    p_older_than := v_min;
  end if;

  if p_include_unread then
    -- Borra TODO lo antiguo (leido o no).
    delete from public.notifications
    where created_at < now() - p_older_than;
  else
    -- Borra solo las leidas. Protege a users con backlog largo.
    delete from public.notifications
    where created_at < now() - p_older_than
      and read_at is not null;
  end if;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.admin_notifications_purge_old(interval, boolean)
  from public;
grant execute on function public.admin_notifications_purge_old(interval, boolean)
  to authenticated;
