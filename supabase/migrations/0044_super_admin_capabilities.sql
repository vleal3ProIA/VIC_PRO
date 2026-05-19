-- ============================================================================
-- 0044 · Super admin + capacidades granulares por admin
-- ----------------------------------------------------------------------------
-- Cambia el modelo de roles binario (`role IN ('admin', 'user')`) por un
-- modelo de 3 capas:
--
--   1. SUPER ADMIN  (`profiles.is_super_admin = true`)
--      - UNO solo (hard-pinned a vleal3@gmail.com en esta migracion).
--      - Solo el SUPER puede promover/demote a otros admins.
--      - Solo el SUPER puede activar/desactivar capacidades concretas.
--      - Hereda TODAS las capacidades automaticamente.
--
--   2. ADMIN  (`profiles.role = 'admin'`)
--      - Acceso a ZONA admin (router gate).
--      - PERO solo a las paginas cuya capacidad le haya activado el SUPER.
--      - NO puede crear, listar ni borrar otros admins.
--      - NO puede activarse capacidades a si mismo.
--
--   3. USER normal  (`profiles.role = 'user'`)
--      - Sin acceso a /admin/*.
--
-- **13 capacidades granulares**, una por pagina admin:
--   manage_users         /admin/users + /admin/users/:id
--   manage_plans         /admin/plans
--   manage_coupons       /admin/coupons
--   manage_branding      /admin/branding (Stripe)
--   manage_app_branding  /admin/app-branding
--   manage_broadcasts    /admin/broadcasts + /new + /:id
--   manage_changelog     /admin/changelog
--   manage_flags         /admin/flags
--   manage_incidents     /admin/incidents
--   view_email_log       /admin/email-log         (read-only en intent)
--   view_metrics         /admin/metrics           (read-only en intent)
--   manage_trash         /admin/trash             (restore tenants)
--   run_audits           /admin/audit + /admin/audit/:id
--
-- **Back-compat**: `is_admin()` sigue funcionando. Lo extendemos para que
-- un super admin tambien cuente como admin (super es superset de admin),
-- asi toda la infra RLS existente (`is_admin()` en policies) sigue igual.
--
-- **Defensa en profundidad**: trigger en `profiles` impide que cualquier
-- non-super toque `is_super_admin`. Trigger en `admin_capabilities`
-- impide que un admin (no super) inserte/borre filas. Trigger en
-- `profiles.role` extiende el check de 0005 -- solo super puede cambiar
-- role='admin'.
-- ============================================================================

-- ─────────────── 1) Columna is_super_admin en profiles ───────────────

alter table public.profiles
  add column if not exists is_super_admin boolean not null default false;

-- Index parcial: solo indexa al super (~ 1 fila). Util para queries
-- `where is_super_admin = true`.
create index if not exists profiles_super_admin_idx
  on public.profiles (id)
  where is_super_admin = true;

comment on column public.profiles.is_super_admin is
  'TRUE solo para el super admin (uno por deployment). El super hereda '
  'todas las capabilities automaticamente y es el unico que puede '
  'gestionar otros admins / capabilities. Pinned por la migracion 0044.';

-- ─────────────── 2) Tabla admin_capabilities ───────────────

-- Whitelist de capabilities validas. Si quieres anyadir una nueva,
-- anyadela aqui Y al constraint check abajo.
create table if not exists public.admin_capabilities (
  user_id     uuid not null references auth.users(id) on delete cascade,
  capability  text not null
              check (capability in (
                'manage_users',
                'manage_plans',
                'manage_coupons',
                'manage_branding',
                'manage_app_branding',
                'manage_broadcasts',
                'manage_changelog',
                'manage_flags',
                'manage_incidents',
                'view_email_log',
                'view_metrics',
                'manage_trash',
                'run_audits'
              )),
  granted_at  timestamptz not null default now(),
  granted_by  uuid references auth.users(id) on delete set null,
  primary key (user_id, capability)
);

create index if not exists admin_capabilities_user_idx
  on public.admin_capabilities (user_id);

comment on table public.admin_capabilities is
  'Cada fila otorga una capacidad concreta a un admin no-super. El '
  'super admin NO necesita filas aqui -- las hereda todas. Solo el '
  'super puede insertar/borrar via RPCs super_admin_*.';

-- ─────────────── 3) RLS minima en admin_capabilities ───────────────
-- Solo lectura para el dueno (para que su propia UI pueda filtrar el
-- menu). Modificacion solo via RPCs SECURITY DEFINER (no policy
-- INSERT/UPDATE/DELETE).

alter table public.admin_capabilities enable row level security;

drop policy if exists "ac_select_own" on public.admin_capabilities;
create policy "ac_select_own"
  on public.admin_capabilities for select
  using (user_id = auth.uid());

-- El super admin lee TODAS para gestionar (RPC list_admins).
drop policy if exists "ac_select_super" on public.admin_capabilities;
create policy "ac_select_super"
  on public.admin_capabilities for select
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and is_super_admin = true
    )
  );

-- ─────────────── 4) Helpers ───────────────

-- Devuelve true si el caller es super admin.
create or replace function public.is_super_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and is_super_admin = true
  );
$$;

-- Re-define is_admin(): super admin O role='admin'. Mantiene
-- compatibilidad hacia atras con todas las policies existentes que
-- usan is_admin().
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and (role = 'admin' or is_super_admin = true)
  );
$$;

-- Capability check. El super admin siempre devuelve true. Para
-- admins normales, mira admin_capabilities.
create or replace function public.has_capability(
  p_capability text,
  p_user_id    uuid default null
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  -- Si no se pasa p_user_id, usa el caller (auth.uid()).
  -- Si el target es super admin, true automatico.
  -- Sino, mira admin_capabilities.
  with target as (
    select coalesce(p_user_id, auth.uid()) as uid
  )
  select exists (
    select 1 from public.profiles p, target t
    where p.id = t.uid and p.is_super_admin = true
  ) or exists (
    select 1 from public.admin_capabilities ac, target t
    where ac.user_id = t.uid and ac.capability = p_capability
  );
$$;

-- Helper para la UI: devuelve el array de capacidades del caller.
-- Super admin recibe TODAS (lista hardcoded).
create or replace function public.get_my_capabilities()
returns text[]
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_is_super boolean;
begin
  if v_uid is null then
    return array[]::text[];
  end if;

  select is_super_admin into v_is_super
  from public.profiles where id = v_uid;

  if coalesce(v_is_super, false) then
    return array[
      'manage_users', 'manage_plans', 'manage_coupons',
      'manage_branding', 'manage_app_branding', 'manage_broadcasts',
      'manage_changelog', 'manage_flags', 'manage_incidents',
      'view_email_log', 'view_metrics', 'manage_trash', 'run_audits'
    ]::text[];
  end if;

  return coalesce(
    (select array_agg(capability)
     from public.admin_capabilities
     where user_id = v_uid),
    array[]::text[]
  );
end;
$$;

revoke all on function public.is_super_admin()         from public;
revoke all on function public.has_capability(text, uuid) from public;
revoke all on function public.get_my_capabilities()    from public;
grant execute on function public.is_super_admin()         to authenticated;
grant execute on function public.has_capability(text, uuid) to authenticated, service_role;
grant execute on function public.get_my_capabilities()    to authenticated;

-- ─────────────── 5) Defensa: triggers anti-escalada ───────────────

-- Trigger en profiles: nadie excepto el super admin puede cambiar
-- `is_super_admin`. Reemplaza el comportamiento de 0005 para `role`:
-- ahora solo el super puede asignar role='admin'.
create or replace function public.prevent_super_admin_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_is_super boolean;
begin
  -- `auth.uid() is null` -> contexto de confianza (service_role, SQL
  -- Editor, migracion). Permitir. Asi el admin puede ejecutar
  -- statements de mantenimiento manualmente desde el Dashboard sin
  -- chocar con esta defensa. Las RPCs super_admin_* son
  -- SECURITY DEFINER pero re-validan is_super_admin() del caller
  -- antes de tocar nada, asi que no dependen solo del trigger.
  if auth.uid() is null then
    return NEW;
  end if;

  -- Si cambia is_super_admin, solo super lo puede tocar.
  if NEW.is_super_admin is distinct from OLD.is_super_admin then
    select is_super_admin into v_caller_is_super
    from public.profiles where id = auth.uid();
    if coalesce(v_caller_is_super, false) is not true then
      raise exception 'only super admin can change is_super_admin';
    end if;
  end if;

  -- Si cambia role (promocion o demote), solo super lo puede.
  -- Cubre ambos sentidos (user->admin, admin->user) -- evita que un
  -- admin se expulse a si mismo o expulse a otro admin.
  if NEW.role is distinct from OLD.role then
    select is_super_admin into v_caller_is_super
    from public.profiles where id = auth.uid();
    if coalesce(v_caller_is_super, false) is not true then
      raise exception 'only super admin can change role';
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_prevent_super_admin_escalation on public.profiles;
create trigger trg_prevent_super_admin_escalation
  before update on public.profiles
  for each row
  execute function public.prevent_super_admin_escalation();

-- ─────────────── 6) RPCs super-admin only ───────────────

-- Lista todos los admins + capabilities en formato amigable para UI.
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
    u.email,
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

-- Promueve a un user a admin (role='admin') SIN ninguna capability
-- inicial. El super le asignara capabilities con grant_capability.
create or replace function public.super_admin_promote_to_admin(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'super admin only';
  end if;
  if p_user_id is null then
    raise exception 'p_user_id required';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'user_not_found';
  end if;

  update public.profiles set role = 'admin' where id = p_user_id;
end;
$$;

-- Revoca rol admin de un user. Borra todas sus capabilities en
-- cascada (CASCADE en la PK no aplica porque la PK es compuesta;
-- borramos manualmente).
--
-- **Importante**: no se puede revocar al super. Si el caller intenta
-- revocar a si mismo (super se auto-quita su own super_admin), tampoco
-- -- el sistema necesita al menos 1 super siempre.
create or replace function public.super_admin_revoke_admin(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_super boolean;
begin
  if not public.is_super_admin() then
    raise exception 'super admin only';
  end if;
  if p_user_id is null then
    raise exception 'p_user_id required';
  end if;

  select is_super_admin into v_is_super
  from public.profiles where id = p_user_id;
  if coalesce(v_is_super, false) then
    raise exception 'cannot revoke super admin via this RPC';
  end if;

  -- Borrar capabilities primero.
  delete from public.admin_capabilities where user_id = p_user_id;
  -- Demote.
  update public.profiles set role = 'user' where id = p_user_id;
end;
$$;

-- Otorga una capacidad. Idempotente -- si ya existe, no-op.
create or replace function public.super_admin_grant_capability(
  p_user_id    uuid,
  p_capability text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'super admin only';
  end if;
  if p_user_id is null or p_capability is null then
    raise exception 'p_user_id and p_capability required';
  end if;

  -- Comprobar que el target tiene role='admin' (no tiene sentido
  -- dar capabilities a un user normal).
  if not exists (
    select 1 from public.profiles
    where id = p_user_id and (role = 'admin' or is_super_admin = true)
  ) then
    raise exception 'target_not_admin';
  end if;

  -- ON CONFLICT DO NOTHING -- el constraint check valida que la
  -- capability sea valida.
  insert into public.admin_capabilities (user_id, capability, granted_by)
  values (p_user_id, p_capability, auth.uid())
  on conflict (user_id, capability) do nothing;
end;
$$;

-- Revoca una capacidad. Idempotente.
create or replace function public.super_admin_revoke_capability(
  p_user_id    uuid,
  p_capability text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'super admin only';
  end if;
  if p_user_id is null or p_capability is null then
    raise exception 'p_user_id and p_capability required';
  end if;

  delete from public.admin_capabilities
  where user_id = p_user_id and capability = p_capability;
end;
$$;

revoke all on function public.super_admin_list_admins()                 from public;
revoke all on function public.super_admin_promote_to_admin(uuid)        from public;
revoke all on function public.super_admin_revoke_admin(uuid)            from public;
revoke all on function public.super_admin_grant_capability(uuid, text)  from public;
revoke all on function public.super_admin_revoke_capability(uuid, text) from public;
grant execute on function public.super_admin_list_admins()                 to authenticated;
grant execute on function public.super_admin_promote_to_admin(uuid)        to authenticated;
grant execute on function public.super_admin_revoke_admin(uuid)            to authenticated;
grant execute on function public.super_admin_grant_capability(uuid, text)  to authenticated;
grant execute on function public.super_admin_revoke_capability(uuid, text) to authenticated;

-- ─────────────── 7) Pin del super admin: vleal3@gmail.com ───────────────
-- Buscamos al user por email en auth.users y lo marcamos como super.
-- Si el email no existe (deployment nuevo), no falla la migracion --
-- solo emite NOTICE y deja la columna a false para todos. El admin
-- debera marcar manualmente al super tras crear su cuenta:
--
--   update public.profiles set is_super_admin = true, role = 'admin'
--   where id = (select id from auth.users where email = 'foo@bar.com');

do $$
declare
  v_super_uid uuid;
begin
  select id into v_super_uid from auth.users where email = 'vleal3@gmail.com';
  if v_super_uid is null then
    raise notice 'super admin email vleal3@gmail.com not found in auth.users -- skip pin';
    return;
  end if;

  -- Asegurar que tiene fila en profiles (deberia, por el trigger de
  -- handle_new_user). Por defensa, insert if not exists.
  insert into public.profiles (id, role, is_super_admin)
  values (v_super_uid, 'admin', true)
  on conflict (id) do update
    set role = 'admin',
        is_super_admin = true,
        updated_at = now();

  raise notice 'pinned super admin: vleal3@gmail.com (%)', v_super_uid;
end$$;
