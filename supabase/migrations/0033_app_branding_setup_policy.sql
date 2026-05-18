-- ============================================================================
-- 0033 · Fix del wizard /setup — permitir UPDATE de app_branding
--                                durante la configuracion inicial
-- ----------------------------------------------------------------------------
-- Bug detectado al ejecutar el wizard por primera vez:
--   PGRST116: Cannot coerce the result to a single JSON object
--
-- Causa raiz: el wizard `/setup` hace `UPDATE app_branding` ANTES de
-- crear el primer admin. La policy `app_branding_admin_update` de la
-- migracion 0028 requiere `is_admin()` que en ese momento es false
-- (no existe ningun admin todavia). RLS silencia el UPDATE, devuelve
-- 0 filas, `.single()` revienta.
--
-- Fix: anyadir una policy adicional que permite UPDATE mientras el
-- proyecto este en estado "pre-setup" (`setup_completed = false`).
-- En cuanto la RPC `bootstrap_first_admin()` marca el flag a true al
-- final del wizard, esta policy ya no aplica y solo admin puede modificar.
--
-- Seguridad: el window de exposicion es minutos durante la primera
-- configuracion, en una BD que aun no tiene users autenticados. Una
-- vez `setup_completed = true`, la policy queda inert y solo
-- `app_branding_admin_update` decide. NO se puede revertir
-- `setup_completed` a false a traves de RLS porque la propia policy
-- `app_branding_admin_update` (admin-only) seria la unica via, y un
-- admin ya tiene permiso por su lado.
-- ============================================================================

drop policy if exists "app_branding_update_during_setup" on public.app_branding;
create policy "app_branding_update_during_setup"
  on public.app_branding for update
  -- USING evalua el estado ANTES del UPDATE: permite tocar el row solo
  -- si setup_completed actualmente es false.
  using (setup_completed = false);
  -- Sin WITH CHECK -- el wizard NO marca setup_completed en este
  -- UPDATE (lo hace `bootstrap_first_admin()` al final, via SECURITY
  -- DEFINER que bypassa RLS). Asi mantenemos la invariante de que
  -- esta policy NO permite "deshacer" el setup completado.
