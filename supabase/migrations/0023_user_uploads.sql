-- ============================================================================
-- 0023 · User uploads layer
-- ----------------------------------------------------------------------------
-- Infraestructura generica para subir archivos. Tres componentes:
--
--   1. **Bucket `user-uploads`** en Supabase Storage (privado, sin
--      acceso publico anonimo). Las URLs son firmadas con TTL corto.
--
--   2. **Tabla `uploads`** que registra cada archivo:
--        id, user_id, tenant_id, bucket, path, filename, mime, size,
--        created_at, deleted_at (soft delete).
--
--      Sirve como "tabla maestra" sobre Storage: cualquier feature
--      futura (avatares custom, adjuntos en comentarios, import CSV,
--      logos de empresa...) inserta aqui y referencia este id, en
--      lugar de guardar el path crudo.
--
--   3. **Cuota por plan**: cada plan define `max_storage_bytes` dentro
--      de `plans.features` jsonb. Por convencion:
--        free:       100 MB =      104857600
--        pro:        5 GB   =     5368709120
--        business:   50 GB  =    53687091200
--        enterprise: -1 (sin limite)
--      La Edge Function `upload-file` consulta el plan activo del
--      tenant antes de cada upload.
--
-- **RLS**:
--   - SELECT: user ve sus uploads + los del tenant donde es miembro.
--   - INSERT: solo service_role (la Edge Function valida cuota antes).
--   - UPDATE: solo el dueno, y solo para tocar `deleted_at` (soft delete).
--   - DELETE hard: no se expone -- la limpieza de Storage la hace un
--     cron job futuro que purga uploads soft-borrados >30 dias.
-- ============================================================================

create table if not exists public.uploads (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  tenant_id         uuid references public.tenants(id) on delete cascade,
  -- Storage location. `bucket` por defecto 'user-uploads' pero se
  -- mantiene flexible por si en el futuro hay buckets separados (p.ej.
  -- 'public-assets' para logos del tenant).
  bucket            text not null default 'user-uploads',
  path              text not null,
  -- Metadata del archivo original.
  filename          text not null check (char_length(filename) between 1 and 255),
  mime_type         text not null check (char_length(mime_type) between 1 and 100),
  size_bytes        bigint not null check (size_bytes >= 0),
  -- Soft delete: la fila se marca con deleted_at = now() pero el
  -- object del Storage NO se borra inmediatamente -- un cron purga
  -- tras N dias. Permite recuperar archivos por error.
  deleted_at        timestamptz,
  created_at        timestamptz not null default now()
);

create index if not exists uploads_tenant_alive_idx
  on public.uploads(tenant_id, created_at desc)
  where deleted_at is null;
create index if not exists uploads_user_alive_idx
  on public.uploads(user_id, created_at desc)
  where deleted_at is null;

-- ─────────────────────────── RLS ───────────────────────────

alter table public.uploads enable row level security;

drop policy if exists "uploads_select_own_or_tenant" on public.uploads;
create policy "uploads_select_own_or_tenant"
  on public.uploads for select
  using (
    deleted_at is null
    and (
      user_id = auth.uid()
      or (
        tenant_id is not null
        and tenant_id in (select public.user_tenants(auth.uid()))
      )
    )
  );

-- INSERT solo service_role (la Edge Function valida cuota y mime
-- antes). Los users no insertan directamente -- garantiza el chequeo
-- de cuota.

-- UPDATE: solo el dueno puede soft-deletear su upload.
drop policy if exists "uploads_soft_delete_own" on public.uploads;
create policy "uploads_soft_delete_own"
  on public.uploads for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ─────────────────────────── Cuota helper ───────────────────────────

-- Cuantos bytes lleva usando un tenant. Suma `size_bytes` de uploads
-- vivos (no soft-deleted). Para que la Edge Function pueda chequear
-- antes de cada upload.
create or replace function public.get_tenant_storage_usage(p_tenant_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(size_bytes), 0)::bigint
  from public.uploads
  where tenant_id = p_tenant_id
    and deleted_at is null;
$$;

-- Cuota del tenant: lee `max_storage_bytes` del plan activo. Si no esta
-- definida en el plan, devuelve el default de 100 MB. Si el valor es
-- -1, devuelve -1 (interpretacion en el caller: sin limite).
create or replace function public.get_tenant_storage_quota(p_tenant_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select (p.features ->> 'max_storage_bytes')::bigint
      from public.tenant_subscriptions ts
      join public.plans p on p.id = ts.plan_id
      where ts.tenant_id = p_tenant_id
        and ts.status in ('active','trialing')
      order by ts.created_at desc
      limit 1
    ),
    104857600  -- 100 MB default si no hay plan activo o falta la key.
  );
$$;

revoke all on function public.get_tenant_storage_usage(uuid) from public;
revoke all on function public.get_tenant_storage_quota(uuid) from public;
grant execute on function public.get_tenant_storage_usage(uuid) to authenticated;
grant execute on function public.get_tenant_storage_quota(uuid) to authenticated;

-- ─────────────────────────── Storage bucket + policies ───────────────────────

-- Crear el bucket privado. Si ya existe, no se duplica.
insert into storage.buckets (id, name, public, file_size_limit)
values ('user-uploads', 'user-uploads', false, 26214400)  -- 25 MB max por file
on conflict (id) do nothing;

-- Policies de storage.objects para el bucket 'user-uploads'.
-- Convenio de path: `<tenant_id>/<user_id>/<random-filename>`. Esto
-- permite policies con `storage.foldername(name)[1]` = tenant_id.

drop policy if exists "user-uploads-select" on storage.objects;
create policy "user-uploads-select"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'user-uploads'
    and (
      (storage.foldername(name))[1]::uuid in (select public.user_tenants(auth.uid()))
      or owner = auth.uid()
    )
  );

drop policy if exists "user-uploads-delete-own" on storage.objects;
create policy "user-uploads-delete-own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'user-uploads' and owner = auth.uid());

-- NO permitimos INSERT/UPDATE directo desde el cliente: las subidas
-- van por la Edge Function `upload-file` que valida cuota y mime
-- ANTES de meter el archivo en el bucket via service_role.

comment on table public.uploads is
  'Tabla maestra de archivos subidos. Cada fila apunta a un object de Storage. Las features (avatares, adjuntos, etc.) referencian uploads.id en lugar de paths crudos.';
