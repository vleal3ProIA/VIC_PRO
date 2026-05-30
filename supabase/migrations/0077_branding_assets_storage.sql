-- ============================================================================
-- 0077 · Storage para assets de branding (logo, favicon, og-image)
-- ----------------------------------------------------------------------------
-- Crea el bucket `branding-assets` (público para lectura — los logos los lee
-- TODO el mundo, incluido /login en anónimo) y las políticas RLS que
-- restringen escritura SOLO a admins con `manage_app_branding`.
--
-- Path: `branding-assets/<kind>` donde kind es 'logo' / 'logo-dark' /
-- 'favicon' / 'og-image'. Es un singleton por deploy (hay UN branding).
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'branding-assets',
  'branding-assets',
  true,
  5242880,  -- 5 MB max per file
  array['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml',
        'image/x-icon', 'image/vnd.microsoft.icon']
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Lectura pública.
drop policy if exists "branding_assets_public_read" on storage.objects;
create policy "branding_assets_public_read"
  on storage.objects for select
  using (bucket_id = 'branding-assets');

-- Escritura solo admins con la capability.
drop policy if exists "branding_assets_admin_write_insert" on storage.objects;
create policy "branding_assets_admin_write_insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'branding-assets'
    and public.has_capability('manage_app_branding')
  );

drop policy if exists "branding_assets_admin_write_update" on storage.objects;
create policy "branding_assets_admin_write_update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'branding-assets'
    and public.has_capability('manage_app_branding')
  )
  with check (
    bucket_id = 'branding-assets'
    and public.has_capability('manage_app_branding')
  );

drop policy if exists "branding_assets_admin_write_delete" on storage.objects;
create policy "branding_assets_admin_write_delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'branding-assets'
    and public.has_capability('manage_app_branding')
  );
