-- ============================================================================
-- 0045 · super_admin_promote_to_admin_by_email
-- ----------------------------------------------------------------------------
-- Helper para PR-Super-A2 (UI): el super admin promueve por email (lo
-- que conoce, no el UUID). Resuelve el email a un user_id de auth.users
-- y delega en `super_admin_promote_to_admin(uuid)` definido en 0044.
--
-- **Por que aqui y no en 0044?** 0044 ya esta deployed (commit 48c8e81).
-- En vez de tocarla retroactivamente -- riesgo de divergencia entre
-- entornos -- anyadimos esta sola RPC como migracion separada.
--
-- **Errores estandarizados** (la UI los mapea a textos i18n):
--   P0001 'super admin only'   -- caller no es super
--   P0002 'user not found'     -- email no existe en auth.users
--   P0003 'already admin'      -- el user ya tiene role='admin' (super_admin_promote_to_admin no lo ve como error, asi que validamos aqui antes de delegar)
--
-- **Defensa en profundidad**: solo el super puede llamar (check interno).
-- El delegado `super_admin_promote_to_admin(uuid)` tambien valida -- si
-- alguien hackeara esta funcion, la siguiente capa lo bloquearia.
-- ============================================================================

create or replace function public.super_admin_promote_to_admin_by_email(
  p_email text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid;
  v_normalized text;
  v_current_role text;
begin
  -- 1) Validacion super.
  if not public.is_super_admin() then
    raise exception 'super admin only' using errcode = 'P0001';
  end if;

  -- 2) Normalizar email: trim + lowercase. auth.users.email se guarda en
  --    lowercase por Supabase, pero el super puede teclearlo con
  --    mayusculas/espacios. Hacemos LOWER en ambos lados por si acaso.
  v_normalized := lower(trim(coalesce(p_email, '')));
  if v_normalized = '' then
    raise exception 'email required' using errcode = 'P0001';
  end if;

  -- 3) Lookup. LIMIT 1 defensivo (no deberia haber duplicados; constraint UNIQUE).
  select id into v_user_id
  from auth.users
  where lower(email) = v_normalized
  limit 1;

  if v_user_id is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  -- 4) Anti-noop: si ya es admin (o el propio super), no llamamos al
  --    delegado -- de lo contrario el caller no diferencia "promovido"
  --    de "ya era admin", lo que confunde en la UI.
  select role into v_current_role
  from public.profiles
  where id = v_user_id;

  if v_current_role = 'admin' then
    raise exception 'already admin' using errcode = 'P0003';
  end if;

  -- 5) Delegar. La funcion de 0044 hace UPDATE profiles.role='admin'.
  --    No le asigna ninguna capability -- el super lo hara con
  --    super_admin_grant_capability(uuid, text).
  perform public.super_admin_promote_to_admin(v_user_id);

  return v_user_id;
end;
$$;

revoke all on function public.super_admin_promote_to_admin_by_email(text) from public;
grant execute on function public.super_admin_promote_to_admin_by_email(text) to authenticated;

comment on function public.super_admin_promote_to_admin_by_email(text) is
  'PR-Super-A2: lookup user by email + promote a admin. Solo super. '
  'Errores: P0001 super only / email required, P0002 user not found, '
  'P0003 already admin. Devuelve el user_id promovido (para que la UI '
  'invalide cache).';
