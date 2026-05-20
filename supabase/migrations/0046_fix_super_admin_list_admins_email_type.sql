-- ============================================================================
-- 0046 · Fix: super_admin_list_admins() cast auth.users.email a text
-- ----------------------------------------------------------------------------
-- La RPC `super_admin_list_admins()` declara `email text` pero
-- `auth.users.email` es `varchar(255)` en Supabase. PostgreSQL es
-- estricto con `RETURNS TABLE(...)`: cuando los tipos no coinciden
-- exactamente entre la columna declarada y la columna SELECTed, lanza
--
--     ERROR 42804: structure of query does not match function result type
--     details: Returned type character varying(255) does not match
--              expected type text in column 2
--
-- Esto rompia la pantalla `/admin/admins` (la UI mostraba el error de
-- carga). Bug introducido en 0044.
--
-- **Fix**: recrear la funcion con `u.email::text`. La firma publica
-- (return type) sigue igual -- `CREATE OR REPLACE FUNCTION` la
-- mantiene. Solo cambia el cuerpo.
--
-- profiles.display_name ya es `text` (definido en 0001), asi que no
-- necesita cast. Solo el email.
-- ============================================================================

create or replace function public.super_admin_list_admins()
returns table (
  user_id        uuid,
  email          text,
  display_name   text,
  is_super_admin boolean,
  capabilities   text[],
  created_at     timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'super admin only';
  end if;

  return query
  select
    p.id as user_id,
    -- CAST: auth.users.email es varchar(255), aqui se declara text.
    -- Sin el cast: ERROR 42804 desde el cliente PostgREST.
    u.email::text,
    p.display_name,
    p.is_super_admin,
    coalesce(
      (select array_agg(ac.capability order by ac.capability)
       from public.admin_capabilities ac
       where ac.user_id = p.id),
      array[]::text[]
    ) as capabilities,
    p.created_at
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.role = 'admin' or p.is_super_admin = true
  order by p.is_super_admin desc, u.email;
end;
$$;

comment on function public.super_admin_list_admins() is
  'PR-Super-A2 (fixed by 0046): lista todos los admins + super para la '
  'UI /admin/admins. Solo el super admin puede invocarla.';
