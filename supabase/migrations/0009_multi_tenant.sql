-- ============================================================================
-- 0009 · Multi-Tenant base
-- ----------------------------------------------------------------------------
-- Establece el modelo de datos para multi-tenancy:
--
--   tenants                ──┐
--                            │ (owner_id)
--                            ├──→ auth.users
--   tenant_members ──────────┘ (user_id, role)
--
-- Reglas:
--   - Un usuario puede pertenecer a MUCHOS tenants (real multi-tenant SaaS).
--   - Cada usuario nuevo recibe automáticamente un "tenant personal"
--     (is_personal = true) donde es owner. Es su sandbox por defecto.
--   - El tenant personal NO se puede borrar (RLS lo impide). Sirve siempre
--     como fallback si el usuario sale de todos los demás tenants.
--   - Roles: owner > admin > member. La granularidad fina por permission
--     strings vendrá en Bloque 2 (M2 RBAC).
--
-- Esta migración NO añade `tenant_id` a las tablas existentes (profiles,
-- audit_logs, etc.). Eso vendrá en migraciones posteriores controladas para
-- minimizar riesgo de despliegue.
-- ============================================================================

-- 1) Tabla tenants ──────────────────────────────────────────────────────────

create table if not exists public.tenants (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 80),
  -- Slug URL-safe: 3-40 chars, [a-z0-9-]. Único en la BD.
  slug        text not null unique
              check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
  owner_id    uuid not null references auth.users(id) on delete restrict,
  -- Marca para el tenant auto-creado en signup. Se usa para impedir su
  -- borrado: el usuario debe tener SIEMPRE al menos su tenant personal.
  is_personal boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists tenants_owner_id_idx on public.tenants (owner_id);

-- 2) Enum de roles ─────────────────────────────────────────────────────────

do $$ begin
  create type public.tenant_role as enum ('owner', 'admin', 'member');
exception
  when duplicate_object then null;
end $$;

-- 3) Tabla tenant_members ──────────────────────────────────────────────────

create table if not exists public.tenant_members (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  role      public.tenant_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (tenant_id, user_id)
);

create index if not exists tenant_members_user_id_idx
  on public.tenant_members (user_id);

-- 4) Helpers SECURITY DEFINER ──────────────────────────────────────────────
-- Estas funciones se invocan desde políticas RLS y desde el cliente vía
-- RPC. Son SECURITY DEFINER para no entrar en recursión con sus propias
-- políticas RLS (la función bypasea RLS y devuelve la verdad).

create or replace function public.user_tenants(p_user_id uuid)
returns setof uuid
language sql stable security definer
set search_path = public, pg_catalog as $$
  select tenant_id from public.tenant_members where user_id = p_user_id;
$$;
comment on function public.user_tenants(uuid) is
  'Set de tenant_id a los que pertenece p_user_id. Bypasea RLS para uso en políticas.';

create or replace function public.is_tenant_member(p_tenant_id uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_catalog as $$
  select exists (
    select 1 from public.tenant_members
    where tenant_id = p_tenant_id and user_id = auth.uid()
  );
$$;
comment on function public.is_tenant_member(uuid) is
  'true si el usuario actual es miembro (cualquier rol) de p_tenant_id.';

create or replace function public.is_tenant_admin(p_tenant_id uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_catalog as $$
  select exists (
    select 1 from public.tenant_members
    where tenant_id = p_tenant_id
      and user_id   = auth.uid()
      and role      in ('owner', 'admin')
  );
$$;
comment on function public.is_tenant_admin(uuid) is
  'true si el usuario actual es owner o admin del tenant.';

-- 5) RLS — tenants ─────────────────────────────────────────────────────────

alter table public.tenants enable row level security;

-- SELECT: solo los tenants en los que soy miembro.
drop policy if exists "tenants_select_member" on public.tenants;
create policy "tenants_select_member"
  on public.tenants for select
  using (id in (select public.user_tenants(auth.uid())));

-- INSERT: cualquier usuario autenticado puede crear un tenant (será owner).
-- Forzamos que owner_id = auth.uid() para evitar que se cree con otro owner.
drop policy if exists "tenants_insert_authenticated" on public.tenants;
create policy "tenants_insert_authenticated"
  on public.tenants for insert
  to authenticated
  with check (owner_id = auth.uid() and is_personal = false);

-- UPDATE: solo admin del tenant. (owner_id no se puede cambiar desde aquí,
-- el cliente no debería intentarlo; transferir ownership es un flujo aparte.)
drop policy if exists "tenants_update_admin" on public.tenants;
create policy "tenants_update_admin"
  on public.tenants for update
  using (public.is_tenant_admin(id));

-- DELETE: solo el owner Y solo si NO es el tenant personal.
drop policy if exists "tenants_delete_owner_non_personal" on public.tenants;
create policy "tenants_delete_owner_non_personal"
  on public.tenants for delete
  using (owner_id = auth.uid() and is_personal = false);

-- 6) RLS — tenant_members ──────────────────────────────────────────────────

alter table public.tenant_members enable row level security;

-- SELECT: veo los miembros de los tenants donde estoy.
drop policy if exists "tenant_members_select_in_my_tenants" on public.tenant_members;
create policy "tenant_members_select_in_my_tenants"
  on public.tenant_members for select
  using (tenant_id in (select public.user_tenants(auth.uid())));

-- INSERT: solo admin/owner. (Las invitaciones tendrán su propia tabla y
-- flujo en la migración 1.B; esta política cubre operaciones programáticas.)
drop policy if exists "tenant_members_insert_admin" on public.tenant_members;
create policy "tenant_members_insert_admin"
  on public.tenant_members for insert
  with check (public.is_tenant_admin(tenant_id));

-- DELETE: admin puede sacar a cualquiera; cualquier usuario puede salirse
-- de un tenant él mismo. Owner NO se puede sacar a sí mismo (el flujo de
-- transferir ownership va aparte).
drop policy if exists "tenant_members_delete" on public.tenant_members;
create policy "tenant_members_delete"
  on public.tenant_members for delete
  using (
    -- Soy admin Y el target no es el owner.
    (
      public.is_tenant_admin(tenant_id)
      and role <> 'owner'
    )
    or
    -- Me estoy yendo yo mismo Y no soy el owner.
    (
      user_id = auth.uid() and role <> 'owner'
    )
  );

-- UPDATE: solo admin puede cambiar role de otros miembros.
drop policy if exists "tenant_members_update_admin" on public.tenant_members;
create policy "tenant_members_update_admin"
  on public.tenant_members for update
  using (public.is_tenant_admin(tenant_id));

-- 7) Trigger: auto-crear tenant personal en signup ────────────────────────
-- Cuando se inserta un nuevo usuario en auth.users, le creamos su tenant
-- personal y le añadimos como owner. Va EN PARALELO al trigger de profiles
-- (0001) — son independientes.

create or replace function public.handle_new_user_personal_tenant()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog as $$
declare
  v_tenant_id uuid;
  v_slug      text;
  v_local     text;  -- parte local del email
begin
  -- Slug = parte local del email, normalizada. Si el email es null
  -- (registro vía OAuth sin email), usamos un fragmento del user_id.
  v_local := split_part(coalesce(new.email, ''), '@', 1);
  if v_local = '' then v_local := substring(new.id::text, 1, 8); end if;

  v_slug := substring(
    regexp_replace(lower(v_local), '[^a-z0-9-]+', '-', 'g')
    from 1 for 30
  );
  -- El check del slug pide 3-40 chars, empezar/acabar en [a-z0-9].
  v_slug := regexp_replace(v_slug, '^-+|-+$', '', 'g');
  if char_length(v_slug) < 3 then
    v_slug := 'u-' || substring(new.id::text, 1, 8);
  end if;

  -- Colisión: añadimos fragmento del user_id.
  if exists (select 1 from public.tenants where slug = v_slug) then
    v_slug := substring(v_slug from 1 for 21) || '-' || substring(new.id::text, 1, 8);
  end if;

  insert into public.tenants (name, slug, owner_id, is_personal)
  values (
    coalesce(new.email, 'Personal'),
    v_slug,
    new.id,
    true
  )
  returning id into v_tenant_id;

  insert into public.tenant_members (tenant_id, user_id, role)
  values (v_tenant_id, new.id, 'owner');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_personal_tenant on auth.users;
create trigger on_auth_user_created_personal_tenant
  after insert on auth.users
  for each row execute function public.handle_new_user_personal_tenant();

-- 8) Backfill: usuarios existentes obtienen su tenant personal ────────────
-- Idempotente: solo crea el tenant para users que aún no tienen uno marcado
-- como personal.

do $$
declare
  rec       record;
  v_tenant_id uuid;
  v_slug    text;
  v_local   text;
begin
  for rec in
    select u.id, u.email
    from auth.users u
    where u.id not in (
      select owner_id from public.tenants where is_personal = true
    )
  loop
    v_local := split_part(coalesce(rec.email, ''), '@', 1);
    if v_local = '' then v_local := substring(rec.id::text, 1, 8); end if;

    v_slug := substring(
      regexp_replace(lower(v_local), '[^a-z0-9-]+', '-', 'g')
      from 1 for 30
    );
    v_slug := regexp_replace(v_slug, '^-+|-+$', '', 'g');
    if char_length(v_slug) < 3 then
      v_slug := 'u-' || substring(rec.id::text, 1, 8);
    end if;
    if exists (select 1 from public.tenants where slug = v_slug) then
      v_slug := substring(v_slug from 1 for 21) || '-' || substring(rec.id::text, 1, 8);
    end if;

    insert into public.tenants (name, slug, owner_id, is_personal)
    values (coalesce(rec.email, 'Personal'), v_slug, rec.id, true)
    on conflict do nothing
    returning id into v_tenant_id;

    if v_tenant_id is not null then
      insert into public.tenant_members (tenant_id, user_id, role)
      values (v_tenant_id, rec.id, 'owner')
      on conflict do nothing;
    end if;
  end loop;
end $$;

-- 9) Trigger: auto-añadir owner como miembro cuando se crea un tenant ────
-- Resuelve el problema del "huevo y la gallina" en RLS: la política de
-- `tenant_members_insert_admin` exige ser admin del tenant, pero al crear
-- un tenant nuevo nadie es miembro todavía. Este trigger inserta la fila
-- de membership como SECURITY DEFINER inmediatamente después del INSERT
-- en `tenants`.
--
-- Para tenants personales (creados desde `handle_new_user_personal_tenant`),
-- la fila de membership YA se inserta en esa función. Aquí usamos
-- ON CONFLICT DO NOTHING para evitar dobles inserciones en ese caso.

create or replace function public.handle_new_tenant_membership()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog as $$
begin
  insert into public.tenant_members (tenant_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (tenant_id, user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_tenant_created_membership on public.tenants;
create trigger on_tenant_created_membership
  after insert on public.tenants
  for each row execute function public.handle_new_tenant_membership();

-- 10) updated_at trigger ───────────────────────────────────────────────────

create or replace function public.tenants_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists tenants_touch_updated_at_trg on public.tenants;
create trigger tenants_touch_updated_at_trg
  before update on public.tenants
  for each row execute function public.tenants_touch_updated_at();
