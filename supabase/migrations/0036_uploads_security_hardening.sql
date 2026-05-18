-- ============================================================================
-- 0036 · Uploads: hardening de seguridad (PR-A)
-- ----------------------------------------------------------------------------
-- Anyade columnas para soportar el nuevo flow de upload en dos pasos:
--   1) `request_upload_url`  -> Edge function valida mime/cuota/filename,
--      genera signed upload URL y crea fila 'pending' (confirmed_at=null).
--   2) Cliente sube directo a Supabase Storage via signed URL.
--   3) `confirm_upload`      -> Edge function descarga primeros 64KB,
--      valida magic bytes, calcula sha256, marca magic_validated=true y
--      confirmed_at=now().
--
-- Una fila con confirmed_at=null y > 1 hora de antiguedad queda
-- "huerfana" (el cliente no llamo a confirm_upload). Un cron job futuro
-- las purga + borra el object correspondiente.
--
-- **Columnas nuevas**:
--   - `sha256`            hex string de 64 chars, NULL hasta confirm
--   - `magic_validated`   true si la validacion de magic bytes paso
--   - `confirmed_at`      timestamp de confirm_upload exitoso
--
-- **Indices**:
--   - `uploads_pending_idx`: parcial para encontrar huerfanos a purgar
--   - `uploads_sha256_idx`: para deduplicacion futura + VirusTotal lookup
--
-- **Compatibilidad**: filas existentes (pre-migracion) se marcan como
-- legacy (magic_validated=false, confirmed_at=created_at). No bloqueamos
-- su descarga -- la sospecha que tenemos es solo sobre uploads nuevos.
-- Si en revision encontramos un upload viejo malicioso, lo borramos
-- manualmente.
-- ============================================================================

alter table public.uploads
  add column if not exists sha256          text,
  add column if not exists magic_validated boolean not null default false,
  add column if not exists confirmed_at    timestamptz;

-- sha256 debe ser hex de 64 chars (256 bits). Validamos en BD para que
-- un Edge Function con bug no inserte basura.
alter table public.uploads
  drop constraint if exists uploads_sha256_format;
alter table public.uploads
  add constraint uploads_sha256_format
  check (sha256 is null or sha256 ~ '^[a-f0-9]{64}$');

-- Marcar las filas existentes como "legacy confirmed" para no romper
-- nada que ya este subido. magic_validated queda en false (default),
-- indicando que NO se valido magic bytes -- util para reporting.
update public.uploads
  set confirmed_at = coalesce(confirmed_at, created_at)
  where confirmed_at is null;

-- Indice parcial: encontrar uploads "huerfanos" (request_upload_url
-- pero nunca confirm_upload). Lo usara el cron de purga.
create index if not exists uploads_pending_idx
  on public.uploads(created_at)
  where confirmed_at is null;

-- Indice por sha256 para deduplicacion futura + lookup en VirusTotal
-- (PR-C). Parcial porque solo las filas confirmadas tienen hash.
create index if not exists uploads_sha256_idx
  on public.uploads(sha256)
  where sha256 is not null and deleted_at is null;

-- ─────────────────────────── RLS update ───────────────────────────
-- La policy de SELECT ya excluye deleted_at. Anyadimos exclusion de
-- pendientes: no queremos que el cliente vea una fila a medias en
-- la lista hasta que confirm_upload haya completado. Esto evita que
-- aparezca un row "fantasma" en /account-settings/files si el cliente
-- abandona el upload (cerro pestanya antes de confirmar).

drop policy if exists "uploads_select_own_or_tenant" on public.uploads;
create policy "uploads_select_own_or_tenant"
  on public.uploads for select
  using (
    deleted_at is null
    and confirmed_at is not null   -- pending NO visible al cliente
    and (
      user_id = auth.uid()
      or (
        tenant_id is not null
        and tenant_id in (select public.user_tenants(auth.uid()))
      )
    )
  );

-- ─────────────────────────── RPC: purge_pending_uploads ───────────────
-- Helper para que el cron job de mantenimiento pueda eliminar uploads
-- huerfanos > 1 hora. Devuelve la lista de paths que el cron debera
-- tambien eliminar del bucket de Storage (la RPC NO toca Storage --
-- eso es responsabilidad del caller con service_role).

create or replace function public.purge_pending_uploads(
  p_older_than interval default interval '1 hour'
)
returns table (id uuid, path text, bucket text)
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Caller debe ser admin o service_role. Para service_role aceptamos
  -- el claim correspondiente; para admin via JWT, is_admin().
  if not (
    public.is_admin()
    or current_setting('request.jwt.claims', true)::jsonb->>'role'
       = 'service_role'
  ) then
    raise exception 'admin or service_role only';
  end if;

  return query
    with deleted as (
      delete from public.uploads
      where confirmed_at is null
        and created_at < now() - p_older_than
      returning id, path, bucket
    )
    select * from deleted;
end;
$$;

revoke all on function public.purge_pending_uploads(interval) from public;
grant execute on function public.purge_pending_uploads(interval)
  to authenticated;
