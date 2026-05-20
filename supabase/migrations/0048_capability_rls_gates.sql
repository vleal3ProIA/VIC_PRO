-- ============================================================================
-- 0048 · Capability gate en RLS para tablas sin Edge Function (A4)
-- ----------------------------------------------------------------------------
-- A3 cerro el gap de capabilities en las 7 Edge Functions admin. Pero
-- 4 capabilities NO tienen EF dedicada -- sus paginas admin escriben
-- DIRECTO a tabla via PostgREST, protegidas solo por RLS `is_admin()`:
--
--   manage_flags        -> feature_flags / feature_flag_overrides
--   manage_changelog    -> changelog_entries
--   manage_incidents    -> incidents
--   manage_app_branding -> app_branding
--
-- **El gap**: un admin con `role='admin'` pero SIN una de estas
-- capabilities podia escribir en esas tablas via REST directo, aunque
-- la UI (A2) le ocultara la pagina. RLS solo miraba `is_admin()`.
--
-- **Fix**: migrar las policies de ESCRITURA (insert/update/delete) de
-- `is_admin()` a `has_capability('<cap>')`. El super admin pasa
-- siempre (la RPC devuelve true para super). Los admins normales
-- necesitan la capability concreta.
--
-- **Reads PUBLICOS se preservan**:
--   - `feature_flags` select abierto a authenticated (evaluar flags).
--   - `app_branding` select abierto a anon+authenticated (branding del
--     login).
--   - `changelog_entries` / `incidents`: lo publicado es visible para
--     todos; solo la visibilidad de DRAFTS (no publicados) se gatea por
--     capability (antes era cualquier admin; ahora admin con la cap).
--
-- **Setup wizard intacto**: `app_branding_update_during_setup` (0033)
-- NO se toca -- sigue permitiendo el UPDATE durante el bootstrap
-- (setup_completed=false), OR'd con la policy de capability.
--
-- `has_capability` es SECURITY DEFINER STABLE igual que `is_admin()`,
-- asi que funciona dentro de policies RLS sin problema (resuelve
-- auth.uid() del caller).
-- ============================================================================

-- ─────────────── 1) feature_flags + feature_flag_overrides ───────────────

drop policy if exists "ff_admin_write" on public.feature_flags;
create policy "ff_admin_write"
  on public.feature_flags for all to authenticated
  using (public.has_capability('manage_flags'))
  with check (public.has_capability('manage_flags'));

drop policy if exists "ff_overrides_admin_write" on public.feature_flag_overrides;
create policy "ff_overrides_admin_write"
  on public.feature_flag_overrides for all to authenticated
  using (public.has_capability('manage_flags'))
  with check (public.has_capability('manage_flags'));

-- ─────────────── 2) changelog_entries ───────────────

-- Select: publicado visible para todos; drafts solo admin CON la cap.
drop policy if exists "changelog_select_published" on public.changelog_entries;
create policy "changelog_select_published"
  on public.changelog_entries for select
  using (
    published_at is not null
    or public.has_capability('manage_changelog')
  );

drop policy if exists "changelog_admin_insert" on public.changelog_entries;
create policy "changelog_admin_insert"
  on public.changelog_entries for insert
  with check (public.has_capability('manage_changelog'));

drop policy if exists "changelog_admin_update" on public.changelog_entries;
create policy "changelog_admin_update"
  on public.changelog_entries for update
  using (public.has_capability('manage_changelog'))
  with check (public.has_capability('manage_changelog'));

drop policy if exists "changelog_admin_delete" on public.changelog_entries;
create policy "changelog_admin_delete"
  on public.changelog_entries for delete
  using (public.has_capability('manage_changelog'));

-- ─────────────── 3) incidents ───────────────

drop policy if exists "incidents_select_public" on public.incidents;
create policy "incidents_select_public"
  on public.incidents for select
  to anon, authenticated
  using (published = true or public.has_capability('manage_incidents'));

drop policy if exists "incidents_admin_insert" on public.incidents;
create policy "incidents_admin_insert"
  on public.incidents for insert
  with check (public.has_capability('manage_incidents'));

drop policy if exists "incidents_admin_update" on public.incidents;
create policy "incidents_admin_update"
  on public.incidents for update
  using (public.has_capability('manage_incidents'))
  with check (public.has_capability('manage_incidents'));

drop policy if exists "incidents_admin_delete" on public.incidents;
create policy "incidents_admin_delete"
  on public.incidents for delete
  using (public.has_capability('manage_incidents'));

-- ─────────────── 4) app_branding ───────────────
-- Solo cambia la policy de UPDATE admin. La de SELECT (publica) y la
-- de setup-wizard (0033) NO se tocan.

drop policy if exists "app_branding_admin_update" on public.app_branding;
create policy "app_branding_admin_update"
  on public.app_branding for update
  using (public.has_capability('manage_app_branding'))
  with check (public.has_capability('manage_app_branding'));
