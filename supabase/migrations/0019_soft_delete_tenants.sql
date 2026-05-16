-- ============================================================================
-- 0019 · Soft delete para tenants + tenant_members
-- ----------------------------------------------------------------------------
-- Convierte el borrado de tenants/memberships en SOFT delete: añadimos
-- `deleted_at` y filtramos las filas borradas de todas las queries
-- normales. Los hard-deletes solo se permiten desde un futuro cron de
-- limpieza (purga tras N días) — fuera del scope de esta migración.
--
-- **Por qué soft delete**:
--   - **Recuperación**: un click admin restaura un tenant borrado por error.
--   - **Auditoría**: la fila sigue ahí para forense / disputas / GDPR
--     (con el derecho al olvido también cubierto vía purga manual).
--   - **Consistencia**: las suscripciones Stripe del tenant siguen
--     existiendo en Stripe; el soft-delete las desliga lógicamente sin
--     cancelar el `stripe_customer_id` (el admin decide después si lo
--     deja o lo cancela en Stripe directamente).
--
-- **Política de visibilidad**:
--   - Usuarios normales: NO ven tenants/memberships con `deleted_at`.
--   - Admins globales (`is_admin()`): SÍ ven todo, incluyendo borrados.
--     Esto habilita la pantalla `/admin/trash`.
--
-- **Cascade lógico**:
--   - Al soft-deletear un tenant, marcamos también todos sus
--     `tenant_members` con el mismo `deleted_at`. Al restaurar, los
--     volvemos a la vida en bloque.
--
-- **Hard delete real**:
--   - Las políticas de DELETE existentes siguen funcionando para tests
--     y limpieza de datos viejos; no las tocamos. Para uso operacional
--     se prefiere las RPCs definidas aquí.
-- ============================================================================

-- 1) Columnas ──────────────────────────────────────────────────────────────

alter table public.tenants
  add column if not exists deleted_at timestamptz;
alter table public.tenant_members
  add column if not exists deleted_at timestamptz;

-- Índices parciales: solo indexan filas NO borradas (más compacto y
-- acelera el filtro habitual `deleted_at is null`).
create index if not exists tenants_alive_idx
  on public.tenants(id) where deleted_at is null;
create index if not exists tenant_members_alive_idx
  on public.tenant_members(tenant_id, user_id) where deleted_at is null;

-- 2) Actualizar RLS para excluir borrados ─────────────────────────────────
-- Mantenemos las policies existentes pero añadimos la condición
-- `deleted_at is null OR public.is_admin()` para que solo el admin global
-- vea las filas borradas.

-- Tenants SELECT
drop policy if exists "tenants_select_member" on public.tenants;
create policy "tenants_select_member"
  on public.tenants for select
  using (
    (deleted_at is null or public.is_admin())
    and id in (select public.user_tenants(auth.uid()))
  );

-- Tenants UPDATE: solo admin del tenant, y si no está borrado.
drop policy if exists "tenants_update_admin" on public.tenants;
create policy "tenants_update_admin"
  on public.tenants for update
  using (
    deleted_at is null
    and public.is_tenant_admin(id)
  );

-- Tenant_members SELECT
drop policy if exists "tenant_members_select_in_my_tenants" on public.tenant_members;
create policy "tenant_members_select_in_my_tenants"
  on public.tenant_members for select
  using (
    (deleted_at is null or public.is_admin())
    and tenant_id in (select public.user_tenants(auth.uid()))
  );

-- 3) Helper `user_tenants` debe excluir tenants borrados ───────────────────
-- Esta función la usan varias políticas. La hacemos consciente del soft
-- delete: si el caller no es admin global, devolvemos solo tenants vivos.

-- IMPORTANTE: el parámetro DEBE llamarse `p_user_id` igual que en
-- la migración 0009 — Postgres no permite renombrar parámetros con
-- CREATE OR REPLACE FUNCTION (SQLSTATE 42P13).
create or replace function public.user_tenants(p_user_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select tm.tenant_id
  from public.tenant_members tm
  join public.tenants t on t.id = tm.tenant_id
  where tm.user_id = p_user_id
    and (tm.deleted_at is null or public.is_admin())
    and (t.deleted_at is null or public.is_admin());
$$;

-- 4) RPCs de soft delete + restore + listado admin ────────────────────────

create or replace function public.soft_delete_tenant(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_owner boolean;
  v_is_personal boolean;
begin
  -- Autorización: admin global o owner del tenant. Tenant personal NO se
  -- puede borrar (igual que la policy DELETE original).
  select (owner_id = auth.uid()), is_personal
    into v_is_owner, v_is_personal
  from public.tenants
  where id = p_tenant_id;

  if v_is_personal then
    raise exception 'cannot_delete_personal_tenant';
  end if;
  if not (public.is_admin() or coalesce(v_is_owner, false)) then
    raise exception 'not_authorized';
  end if;

  update public.tenants
    set deleted_at = now()
    where id = p_tenant_id and deleted_at is null;
  -- Cascade lógico: marcar también a todos los miembros como borrados.
  update public.tenant_members
    set deleted_at = now()
    where tenant_id = p_tenant_id and deleted_at is null;
end;
$$;

create or replace function public.restore_tenant(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Solo admin global puede restaurar. El owner ya no "ve" el tenant
  -- (RLS lo oculta), así que dependemos del admin para revertir.
  if not public.is_admin() then
    raise exception 'not_authorized';
  end if;

  update public.tenants
    set deleted_at = null
    where id = p_tenant_id;
  update public.tenant_members
    set deleted_at = null
    where tenant_id = p_tenant_id;
end;
$$;

/// Devuelve los tenants borrados con metadatos útiles para la pantalla
/// admin de papelera. SECURITY DEFINER + check de admin = la única forma
/// de leer la lista; usuarios normales reciben 0 filas siempre.
create or replace function public.list_deleted_tenants()
returns table (
  id            uuid,
  name          text,
  slug          text,
  owner_id      uuid,
  deleted_at    timestamptz,
  member_count  bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.id,
    t.name,
    t.slug,
    t.owner_id,
    t.deleted_at,
    (
      select count(*)
      from public.tenant_members tm
      where tm.tenant_id = t.id
    )
  from public.tenants t
  where t.deleted_at is not null
    and public.is_admin()  -- short-circuit: si no es admin, 0 filas.
  order by t.deleted_at desc;
$$;

revoke all on function public.soft_delete_tenant(uuid) from public;
revoke all on function public.restore_tenant(uuid) from public;
revoke all on function public.list_deleted_tenants() from public;
grant execute on function public.soft_delete_tenant(uuid) to authenticated;
grant execute on function public.restore_tenant(uuid) to authenticated;
grant execute on function public.list_deleted_tenants() to authenticated;

comment on function public.soft_delete_tenant(uuid) is
  'Marca un tenant y todos sus miembros como borrados (deleted_at=now()). Solo admin global o owner del tenant. No aplica a tenants personales.';
comment on function public.restore_tenant(uuid) is
  'Restaura un tenant soft-borrado y todos sus miembros. Solo admin global.';
comment on function public.list_deleted_tenants() is
  'Lista de tenants borrados con metadatos. Solo admin global recibe filas; el resto recibe 0.';
