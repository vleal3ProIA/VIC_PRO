-- ============================================================================
-- 0070 · Flags de visibilidad para las secciones de Workspace
-- ----------------------------------------------------------------------------
-- Tres secciones de la pestaña "Workspace" de los ajustes pueden ocultarse
-- desde `/admin/flags` cuando el deploy aún no quiere exponerlas (o cuando el
-- producto las deshabilita por completo):
--
--   - Tokens API   (`workspace_tokens_visible`)
--   - Webhooks     (`workspace_webhooks_visible`)
--   - Equipo       (`workspace_team_visible`)
--
-- Mismo patrón que el ya existente `audit_log_visible`. Default `true` (la
-- migración no rompe nada: las tres secciones siguen viéndose como hasta
-- ahora). El admin las apaga cuando quiera; la UI las oculta tanto en la
-- vista list (móvil) como en el master-detail (escritorio).
-- ============================================================================

insert into public.feature_flags (key, description, enabled)
values
  ('workspace_tokens_visible',
   'Muestra la sección "Tokens API" en la pestaña Workspace de ajustes',
   true),
  ('workspace_webhooks_visible',
   'Muestra la sección "Webhooks" en la pestaña Workspace de ajustes',
   true),
  ('workspace_team_visible',
   'Muestra la sección "Equipo y miembros" en la pestaña Workspace de ajustes',
   true)
on conflict (key) do nothing;
