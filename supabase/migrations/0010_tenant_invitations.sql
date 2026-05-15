-- ============================================================================
-- 0010 · Tenant invitations
-- ----------------------------------------------------------------------------
-- Sistema de invitaciones por email/token para añadir miembros a un tenant.
--
-- Diseño:
--   - El admin crea una invitación con (email, role, expires_at).
--   - El backend genera un token plaintext + su SHA-256 hash. **Solo el
--     hash se guarda**; el plaintext va en el email/URL al invitado.
--   - Al aceptar (otro flujo), el server hashea el token presentado y
--     busca en la tabla. Match → crea tenant_members + marca accepted_at.
--   - Una invitación se puede revocar (sin borrarla, para auditar). Una
--     invitación aceptada o revocada NO bloquea reinvitar al mismo email.
--
-- RLS:
--   - SELECT/INSERT/UPDATE/DELETE: solo admin del tenant.
--   - El flujo de aceptación va por Edge Function (SECURITY DEFINER) y
--     bypasea RLS — necesario porque el invitado AÚN no es miembro.
-- ============================================================================

create table if not exists public.tenant_invitations (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  -- Email en minúsculas (forzado por check); evita duplicados case-sensitive.
  email        text not null check (email = lower(email) and email like '%_@__%'),
  role         public.tenant_role not null default 'member',
  -- Hash SHA-256 del token (hex 64 chars). El plaintext NUNCA se guarda.
  token_hash   text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  invited_by   uuid references auth.users(id) on delete set null,
  expires_at   timestamptz not null,
  accepted_at  timestamptz,
  accepted_by  uuid references auth.users(id) on delete set null,
  revoked_at   timestamptz,
  created_at   timestamptz not null default now()
);

-- Solo una invitación PENDIENTE por (tenant, email). Las aceptadas o
-- revocadas no cuentan (se permite re-invitar después).
create unique index if not exists tenant_invitations_pending_unique
  on public.tenant_invitations (tenant_id, email)
  where accepted_at is null and revoked_at is null;

create index if not exists tenant_invitations_token_hash_idx
  on public.tenant_invitations (token_hash);
create index if not exists tenant_invitations_tenant_id_idx
  on public.tenant_invitations (tenant_id);

-- RLS
alter table public.tenant_invitations enable row level security;

drop policy if exists "invitations_select_admin" on public.tenant_invitations;
create policy "invitations_select_admin"
  on public.tenant_invitations for select
  using (public.is_tenant_admin(tenant_id));

drop policy if exists "invitations_insert_admin" on public.tenant_invitations;
create policy "invitations_insert_admin"
  on public.tenant_invitations for insert
  with check (public.is_tenant_admin(tenant_id));

drop policy if exists "invitations_update_admin" on public.tenant_invitations;
create policy "invitations_update_admin"
  on public.tenant_invitations for update
  using (public.is_tenant_admin(tenant_id));

drop policy if exists "invitations_delete_admin" on public.tenant_invitations;
create policy "invitations_delete_admin"
  on public.tenant_invitations for delete
  using (public.is_tenant_admin(tenant_id));

-- Helper: invitaciones pendientes de un tenant (no expiradas, no aceptadas,
-- no revocadas). Útil para el "badge count" en la UI.
create or replace function public.pending_invitation_count(p_tenant_id uuid)
returns integer
language sql stable security definer
set search_path = public, pg_catalog as $$
  select count(*)::integer
  from public.tenant_invitations
  where tenant_id = p_tenant_id
    and accepted_at is null
    and revoked_at is null
    and expires_at > now();
$$;

-- Helper: lista miembros de un tenant con info de su profile + email para
-- mostrarlos en la UI sin tener que hacer 2 queries desde el cliente.
-- SECURITY DEFINER porque accede a auth.users (donde el cliente no llega
-- directamente). El WHERE filtra a tenants donde el caller es miembro;
-- así nadie puede enumerar miembros de un tenant ajeno aunque tenga el id.
create or replace function public.list_tenant_members_with_profile(
  p_tenant_id uuid
)
returns table (
  tenant_id    uuid,
  user_id      uuid,
  role         public.tenant_role,
  joined_at    timestamptz,
  username     text,
  display_name text,
  avatar_url   text,
  email        text
)
language sql stable security definer
set search_path = public, pg_catalog as $$
  select
    tm.tenant_id,
    tm.user_id,
    tm.role,
    tm.joined_at,
    p.username,
    p.display_name,
    p.avatar_url,
    u.email::text
  from public.tenant_members tm
  left join public.profiles p on p.id = tm.user_id
  left join auth.users u      on u.id = tm.user_id
  where tm.tenant_id = p_tenant_id
    and tm.tenant_id in (select public.user_tenants(auth.uid()))
  order by
    case tm.role when 'owner' then 0 when 'admin' then 1 else 2 end,
    tm.joined_at;
$$;
