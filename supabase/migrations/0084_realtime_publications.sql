-- ============================================================================
-- 0084 · Realtime publications · notifications + reports
-- ----------------------------------------------------------------------------
-- Por defecto las tablas NO estan en la publication `supabase_realtime`,
-- asi que los clientes Flutter que se suscriben a `postgres_changes` no
-- reciben eventos aunque los INSERTs ocurran.
--
-- Esta migracion ANYade las tablas que la UI necesita observar en tiempo
-- real:
--   - `notifications`  -> badge de la campana + lista in-app.
--   - `error_reports`  -> listado admin para refrescar tras INSERT.
--   - `audit_reports`  -> idem audit center.
--
-- Sin esto el cliente tiene que recargar la pagina para ver cambios; el
-- usuario lo nota como "delay raro".
--
-- Pattern: do block + condicional sobre `pg_publication_tables`, asi es
-- idempotente (no falla si la tabla ya esta anyadida).
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'error_reports'
  ) then
    alter publication supabase_realtime add table public.error_reports;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'audit_reports'
  ) then
    alter publication supabase_realtime add table public.audit_reports;
  end if;
end $$;
