-- ============================================================================
-- 0011 · Feature Flags
-- ----------------------------------------------------------------------------
-- Toggle remoto para activar/desactivar funcionalidades sin redesplegar.
-- Soporta:
--   - Toggle global (`enabled`).
--   - Rollout progresivo por % de usuarios (`rollout_percentage`).
--   - Overrides explícitos por tenant o por usuario.
--   - Valores no booleanos (`value jsonb`) — para flags de "configuración",
--     no solo "on/off". Ej. `{"max_uploads": 100, "model": "gpt-4"}`.
--
-- Resolución por la RPC `my_feature_flags(tenant_id)`. Orden de precedencia:
--   1. Override de usuario (más específico)
--   2. Override de tenant
--   3. Rollout aleatorio determinista (hash(user_id + key) % 100 < %)
--   4. `enabled` global
--
-- RLS:
--   - Lectura: cualquier autenticado puede ver los flags (no son secretos).
--   - Escritura: solo admins globales (`public.is_admin()` de la migración 0005).
-- ============================================================================

-- 1) Tabla feature_flags ───────────────────────────────────────────────────

create table if not exists public.feature_flags (
  key                text primary key
                     check (key ~ '^[a-z][a-z0-9_]{1,60}$'),
  description        text,
  enabled            boolean not null default false,
  -- Rollout en %: 0=nadie (salvo overrides), 100=todos. Determinista por
  -- usuario: el mismo user_id siempre obtiene el mismo veredicto, así un
  -- usuario al 30% rollout no parpadea entre on/off entre sesiones.
  rollout_percentage int     not null default 0
                     check (rollout_percentage between 0 and 100),
  value              jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

drop trigger if exists feature_flags_set_updated_at on public.feature_flags;
create trigger feature_flags_set_updated_at
  before update on public.feature_flags
  for each row execute function public.set_updated_at();

-- 2) Tabla feature_flag_overrides ─────────────────────────────────────────

create table if not exists public.feature_flag_overrides (
  id         uuid primary key default gen_random_uuid(),
  flag_key   text not null references public.feature_flags(key)
                  on delete cascade,
  tenant_id  uuid references public.tenants(id) on delete cascade,
  user_id    uuid references auth.users(id) on delete cascade,
  enabled    boolean,
  value      jsonb,
  created_at timestamptz not null default now(),
  -- Override debe apuntar A UNO Y SOLO UNO de tenant/user.
  check (
    (tenant_id is not null and user_id is null) or
    (tenant_id is null and user_id is not null)
  ),
  -- Override debe especificar AL MENOS un cambio (enabled o value).
  check (enabled is not null or value is not null)
);

-- Solo un override por (flag, tenant) y un override por (flag, user).
create unique index if not exists ff_override_per_tenant
  on public.feature_flag_overrides (flag_key, tenant_id)
  where tenant_id is not null;
create unique index if not exists ff_override_per_user
  on public.feature_flag_overrides (flag_key, user_id)
  where user_id is not null;

-- 3) RLS ───────────────────────────────────────────────────────────────────

alter table public.feature_flags enable row level security;
alter table public.feature_flag_overrides enable row level security;

-- Lectura abierta a autenticados. Los flags no son secretos: el cliente
-- los necesita para gatear UI.
drop policy if exists "ff_select_authenticated" on public.feature_flags;
create policy "ff_select_authenticated"
  on public.feature_flags for select to authenticated using (true);

-- Escritura solo admin global. `is_admin()` viene de 0005_user_roles.sql.
drop policy if exists "ff_admin_write" on public.feature_flags;
create policy "ff_admin_write"
  on public.feature_flags for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Overrides: el usuario ve los suyos + los de tenants donde es miembro.
drop policy if exists "ff_overrides_select" on public.feature_flag_overrides;
create policy "ff_overrides_select"
  on public.feature_flag_overrides for select to authenticated
  using (
    user_id = auth.uid()
    or (tenant_id is not null and tenant_id in (
      select public.user_tenants(auth.uid())
    ))
  );

-- Escritura solo admin global.
drop policy if exists "ff_overrides_admin_write" on public.feature_flag_overrides;
create policy "ff_overrides_admin_write"
  on public.feature_flag_overrides for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 4) RPC `my_feature_flags` ───────────────────────────────────────────────
-- Resuelve para el caller (auth.uid()) el estado efectivo de TODOS los flags.
-- `p_tenant_id` opcional: si se pasa, evalúa también overrides por tenant.
-- Devuelve `source` para que la UI/observabilidad sepa de dónde viene el
-- veredicto (debugging de rollout).

create or replace function public.my_feature_flags(p_tenant_id uuid default null)
returns table (
  key     text,
  enabled boolean,
  value   jsonb,
  source  text
)
language sql stable security definer
set search_path = public, pg_catalog as $$
  with base as (
    select * from public.feature_flags
  ),
  user_ov as (
    select flag_key, enabled, value
    from public.feature_flag_overrides
    where user_id = auth.uid()
  ),
  tenant_ov as (
    select flag_key, enabled, value
    from public.feature_flag_overrides
    where p_tenant_id is not null and tenant_id = p_tenant_id
  )
  select
    b.key,
    coalesce(
      uo.enabled,
      to_v.enabled,
      case
        when b.rollout_percentage = 0   then null
        when b.rollout_percentage = 100 then true
        else (
          abs(hashtext(coalesce(auth.uid()::text, '') || b.key)) % 100
          < b.rollout_percentage
        )
      end,
      b.enabled
    ) as enabled,
    coalesce(uo.value, to_v.value, b.value) as value,
    case
      when uo.enabled is not null or uo.value is not null then 'user'
      when to_v.enabled is not null or to_v.value is not null then 'tenant'
      when b.rollout_percentage > 0 and b.rollout_percentage < 100 then 'rollout'
      else 'global'
    end as source
  from base b
  left join user_ov   uo   on uo.flag_key = b.key
  left join tenant_ov to_v on to_v.flag_key = b.key;
$$;

comment on function public.my_feature_flags(uuid) is
  'Estado efectivo de todos los flags para el caller, con override por usuario, tenant, rollout aleatorio determinista, o default global. Returns one row per flag.';

-- 5) Flags semilla (idempotente) ──────────────────────────────────────────
-- Algunas claves de partida que la app puede usar inmediatamente. Quedan
-- a `enabled=false` por defecto; el admin las activa desde la UI.

insert into public.feature_flags (key, description, enabled)
values
  ('new_dashboard',       'Activa el nuevo diseño del home',                       false),
  ('audit_log_visible',   'Muestra la pestaña "Actividad reciente" en ajustes',    true),
  ('billing_v2',          'Cambios de UX del flujo de billing v2',                 false),
  ('ai_assistant',        'Asistente IA experimental',                             false)
on conflict (key) do nothing;
