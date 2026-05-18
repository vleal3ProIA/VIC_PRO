-- ============================================================================
-- 0038 · Uploads: antivirus scan async (PR-C)
-- ----------------------------------------------------------------------------
-- Anyade columnas a `public.uploads` para registrar el estado del scan
-- antivirus que dispara la Edge Function `scan-upload` tras cada upload
-- confirmado (`confirm_upload` en `upload-file`). Mas la RPC
-- `admin_uploads_scan_stats` para que el admin tenga visibilidad.
--
-- **Columnas nuevas**:
--   - `virus_scan_status`: enum textual con check constraint:
--     * 'pending'    -> cola, scan-upload va a procesarlo
--     * 'clean'      -> VirusTotal no detecto malware
--     * 'suspicious' -> >=1 motor lo flageo. El upload queda
--                       soft-deleted (deleted_at = now()) automaticamente.
--     * 'error'      -> fallo en la llamada a VirusTotal (network, quota,
--                       etc.). El upload SE MANTIENE accesible -- no es
--                       razonable bloquear archivos legitimos por una
--                       caida de servicio externo. Reintentable manual.
--     * 'skipped'    -> archivo > 32 MB (limite free tier de VT) o tipo
--                       que no aceptamos en VT (texto plano, etc.).
--   - `virus_scan_result`: jsonb con el detalle: nombre del scan, motores
--     positivos / totales, lista de motores flageados, link al reporte
--     publico de VT, timestamp.
--   - `virus_scan_at`: cuando se actualizo el status. NULL = nunca
--     escaneado (todos los uploads pre-PR-C).
--
-- **Backfill**: filas existentes (pre-migracion) se marcan como
-- 'skipped' con un motivo. NO las escaneamos retroactivamente -- el
-- riesgo es bajo (eran de antes de PR-A whitelist + magic bytes) y
-- no queremos consumir la cuota gratis del primer dia.
-- ============================================================================

alter table public.uploads
  add column if not exists virus_scan_status text not null default 'pending'
    check (virus_scan_status in (
      'pending', 'clean', 'suspicious', 'error', 'skipped'
    )),
  add column if not exists virus_scan_result jsonb,
  add column if not exists virus_scan_at     timestamptz;

-- Backfill: filas existentes -> skipped (no las re-escaneamos).
update public.uploads
  set virus_scan_status = 'skipped',
      virus_scan_result = jsonb_build_object(
        'reason', 'pre_pr_c_backfill',
        'note',   'Upload existed before antivirus integration. No retro-scan.'
      ),
      virus_scan_at = now()
  where virus_scan_status = 'pending' and confirmed_at is not null;

-- Indice para encontrar suspicious facil (dashboard admin, alertas).
create index if not exists uploads_suspicious_idx
  on public.uploads(virus_scan_at desc)
  where virus_scan_status = 'suspicious';

-- Indice para el cron de retry (pending > 30 min = probable que se
-- haya colgado el scan).
create index if not exists uploads_scan_pending_idx
  on public.uploads(virus_scan_at)
  where virus_scan_status = 'pending';

-- ─────────────── RPC: admin_uploads_scan_stats ───────────────
-- Devuelve agregado para el dashboard admin: cuantos uploads en cada
-- estado, ultimos suspicious detectados. Una sola RPC -> un round-trip.

create or replace function public.admin_uploads_scan_stats(
  p_limit_suspicious int default 20
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

  with counts as (
    select
      count(*) filter (where virus_scan_status = 'clean')::int       as clean,
      count(*) filter (where virus_scan_status = 'suspicious')::int  as suspicious,
      count(*) filter (where virus_scan_status = 'pending')::int     as pending,
      count(*) filter (where virus_scan_status = 'error')::int       as scan_error,
      count(*) filter (where virus_scan_status = 'skipped')::int     as skipped,
      count(*)::int                                                  as total
    from public.uploads
    where confirmed_at is not null
  ),
  recent_suspicious as (
    select
      id, user_id, filename, mime_type, size_bytes,
      virus_scan_result, virus_scan_at
    from public.uploads
    where virus_scan_status = 'suspicious'
    order by virus_scan_at desc nulls last
    limit greatest(1, least(p_limit_suspicious, 100))
  )
  select jsonb_build_object(
    'counts', (select to_jsonb(c.*) from counts c),
    'recent_suspicious', coalesce(
      (select jsonb_agg(to_jsonb(rs.*)) from recent_suspicious rs),
      '[]'::jsonb
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_uploads_scan_stats(int) from public;
grant execute on function public.admin_uploads_scan_stats(int)
  to authenticated;
