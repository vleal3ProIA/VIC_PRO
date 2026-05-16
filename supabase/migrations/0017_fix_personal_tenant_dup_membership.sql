-- ============================================================================
-- 0017 · HOTFIX: signup falla con duplicate PK en tenant_members
-- ----------------------------------------------------------------------------
-- En 0009 introduje dos triggers que insertan en `tenant_members` para el
-- mismo evento (creación de tenant personal):
--
--   1. `handle_new_user_personal_tenant()` (en auth.users AFTER INSERT)
--      inserta el tenant → luego intenta INSERT directo en tenant_members
--      SIN ON CONFLICT.
--
--   2. `handle_new_tenant_membership()` (en public.tenants AFTER INSERT)
--      inserta la membership con ON CONFLICT DO NOTHING.
--
-- Orden real de ejecución cuando se crea un usuario:
--   - `handle_new_user_personal_tenant` arranca.
--   - INSERT en `tenants` → dispara `on_tenant_created_membership` que
--     ya crea la fila en tenant_members (owner_id, 'owner').
--   - `handle_new_user_personal_tenant` continúa y vuelve a intentar el
--     INSERT en tenant_members → PK duplicada → la transacción explota
--     → Supabase responde con "Database error saving new user".
--
-- Síntoma: cualquier signup nuevo post-0009 falla.
-- Causa raíz: redundancia entre los dos triggers; ninguno fue probado
-- después del otro porque el backfill en 0009 ya manejaba a los users
-- existentes con ON CONFLICT DO NOTHING.
--
-- Fix: eliminar el INSERT manual de membership en
-- `handle_new_user_personal_tenant`. El trigger general
-- `on_tenant_created_membership` se encarga de crearla.
-- ============================================================================

create or replace function public.handle_new_user_personal_tenant()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog as $$
declare
  v_slug  text;
  v_local text;
begin
  v_local := split_part(coalesce(new.email, ''), '@', 1);
  if v_local = '' then v_local := substring(new.id::text, 1, 8); end if;

  v_slug := substring(
    regexp_replace(lower(v_local), '[^a-z0-9-]+', '-', 'g')
    from 1 for 30
  );
  v_slug := regexp_replace(v_slug, '^-+|-+$', '', 'g');
  if char_length(v_slug) < 3 then
    v_slug := 'u-' || substring(new.id::text, 1, 8);
  end if;
  if exists (select 1 from public.tenants where slug = v_slug) then
    v_slug := substring(v_slug from 1 for 21)
              || '-' || substring(new.id::text, 1, 8);
  end if;

  -- Insertamos el tenant. El trigger `on_tenant_created_membership` se
  -- encarga de crear la fila en `tenant_members` con role='owner'.
  -- NO hacemos un INSERT manual aquí — sería duplicado.
  insert into public.tenants (name, slug, owner_id, is_personal)
  values (
    coalesce(new.email, 'Personal'),
    v_slug,
    new.id,
    true
  );

  return new;
end;
$$;
