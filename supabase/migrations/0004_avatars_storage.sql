-- ============================================================================
-- 0004 · Storage para avatares
-- ----------------------------------------------------------------------------
-- Crea el bucket `avatars` (público para lectura) y las políticas RLS sobre
-- `storage.objects` para que cada usuario solo pueda subir/actualizar/borrar
-- archivos dentro de SU carpeta: `avatars/{user_id}/...`.
--
-- La app sube a `avatars/{user_id}/avatar` y guarda la URL pública (con un
-- `?v=timestamp` para invalidar caché) en `public.profiles.avatar_url`.
--
-- Aplicar:
--   - Dashboard: SQL Editor → New query → pegar este archivo → Run.
--   - CLI:       supabase db push
-- ============================================================================

-- 1) Bucket público ----------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

-- 2) Políticas RLS sobre storage.objects -------------------------------------
-- Lectura: el bucket es público, cualquiera puede leer los avatares.
drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- Subida: el usuario autenticado solo puede escribir en su propia carpeta.
drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Actualizar (upsert sobre el mismo archivo).
drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Borrar su propio avatar.
drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
