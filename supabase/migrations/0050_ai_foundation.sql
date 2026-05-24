-- ============================================================================
-- 0050_ai_foundation.sql · Cimientos de las funciones de IA (Fase 0)
-- ----------------------------------------------------------------------------
-- Registro de proveedores de IA gestionable desde el superadmin (Gemini,
-- Claude, OpenAI, ...), credenciales (API keys) SOLO-servidor con rotacion y
-- fallback gratis -> pago, y registro de uso/coste para cuotas y metricas.
--
-- Seguridad de las API keys: la tabla `ai_credentials` tiene RLS activado y
-- SIN policies (mismo patron que `webhook_secrets`): solo `service_role` (las
-- Edge Functions) la lee. El cliente NUNCA ve las keys; el superadmin las
-- gestiona a traves de una Edge Function (write-only + preview enmascarada).
--
-- Nuevas capabilities:
--   * `manage_ai`       -> gestionar proveedores / keys / config de IA.
--   * `view_ai_content` -> ver el contenido generado por temario (Fase 1+).
--
-- NOTA: pgvector / tablas de embeddings (RAG para "pregunta a la IA") se
-- anyadiran en su propia migracion cuando lleguemos a esa fase. Aqui no se
-- activan para que esta migracion haga una sola cosa coherente.
-- ============================================================================

-- ─────────────────── Capabilities nuevas (whitelist CHECK) ───────────────────
-- El CHECK de `admin_capabilities.capability` es una whitelist. Para anyadir
-- nuevas hay que recrear el constraint con la lista COMPLETA + las nuevas.
alter table public.admin_capabilities
  drop constraint if exists admin_capabilities_capability_check;
alter table public.admin_capabilities
  add constraint admin_capabilities_capability_check
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
    'run_audits',
    'manage_ai',
    'view_ai_content'
  ));

-- ─────────────────── Proveedores de IA (catalogo configurable) ───────────────
-- Cada fila es un proveedor que el superadmin activa/desactiva, prioriza y
-- configura (modelo por defecto, base_url para APIs compatibles/OpenRouter).
-- El `slug` mapea con el adaptador de codigo en la Edge Function `ai-gateway`.
create table if not exists public.ai_providers (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,            -- 'gemini', 'anthropic', ...
  display_name  text not null,
  tier          text not null default 'free'     -- gratis vs pago
                check (tier in ('free', 'paid')),
  enabled       boolean not null default false,
  priority      int not null default 100,        -- menor = se intenta antes
  default_model text,                             -- p.ej. 'gemini-1.5-flash'
  base_url      text,                             -- APIs compatibles / OpenRouter
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists ai_providers_enabled_priority_idx
  on public.ai_providers (enabled, priority);

drop trigger if exists ai_providers_set_updated_at on public.ai_providers;
create trigger ai_providers_set_updated_at
  before update on public.ai_providers
  for each row execute function public.set_updated_at();

-- ─────────────────── Credenciales (API keys) SOLO-servidor ───────────────────
-- Varias keys por proveedor (rotacion: "un par de cuentas gratis de Gemini").
-- RLS activado y SIN policies (patron `webhook_secrets`): solo service_role.
-- `key_last4` permite a la UI mostrar una preview enmascarada sin exponer la
-- key. `cooldown_until` la salta temporalmente si agoto cuota o dio error.
create table if not exists public.ai_credentials (
  id              uuid primary key default gen_random_uuid(),
  provider_id     uuid not null references public.ai_providers(id) on delete cascade,
  label           text,                           -- "cuenta gratis #1"
  api_key         text not null,                  -- SECRETO: jamas al cliente
  key_last4       text,                           -- preview enmascarada (UI)
  enabled         boolean not null default true,
  disabled_reason text,                           -- 'quota_exhausted'|'invalid'|...
  cooldown_until  timestamptz,                    -- saltarla hasta esta hora
  last_used_at    timestamptz,
  created_at      timestamptz not null default now()
);

create index if not exists ai_credentials_provider_idx
  on public.ai_credentials (provider_id);

-- ─────────────────── Uso / coste (cuotas + metricas) ─────────────────────────
-- Una fila por llamada al gateway. `user_id` con ON DELETE SET NULL: si el
-- usuario borra su cuenta, el registro de uso se conserva anonimizado para
-- metricas agregadas (no es dato personal una vez desvinculado).
create table if not exists public.ai_usage (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete set null,
  provider_id   uuid references public.ai_providers(id) on delete set null,
  task_type     text,                             -- 'index'|'views'|'aids'|'questions'|'qa'
  model         text,
  input_tokens  int not null default 0,
  output_tokens int not null default 0,
  cost_usd      numeric(12,6) not null default 0,
  subject_id    uuid,                             -- (FK a subjects se anyade en Fase 1)
  created_at    timestamptz not null default now()
);

create index if not exists ai_usage_user_idx on public.ai_usage (user_id);
create index if not exists ai_usage_created_idx on public.ai_usage (created_at);

-- ─────────────────────────────── RLS ─────────────────────────────────────────
alter table public.ai_providers   enable row level security;
alter table public.ai_credentials enable row level security;
alter table public.ai_usage       enable row level security;

-- ai_providers: lectura y gestion para admins con capability 'manage_ai'
-- (super_admin pasa siempre via has_capability). Las Edge Functions usan
-- service_role y saltan RLS. NO hay secretos en esta tabla (las keys van en
-- ai_credentials), por eso el cliente puede leerla directamente. Una sola
-- policy `for all`: el USING cubre select/delete y el WITH CHECK insert/update.
drop policy if exists "ai_providers_admin_select" on public.ai_providers;
drop policy if exists "ai_providers_admin_write" on public.ai_providers;
drop policy if exists "ai_providers_admin_all" on public.ai_providers;
create policy "ai_providers_admin_all"
  on public.ai_providers for all
  using (public.has_capability('manage_ai'))
  with check (public.has_capability('manage_ai'));

-- ai_credentials: SIN policies -> bloqueada para CUALQUIER cliente. Solo
-- service_role (Edge Functions). El superadmin gestiona las keys via la Edge
-- Function `ai-admin` (write-only + preview enmascarada).

-- ai_usage: lectura para admins con 'view_metrics' o 'manage_ai'; la escritura
-- solo la hace service_role (sin policies de insert/update/delete).
drop policy if exists "ai_usage_admin_select" on public.ai_usage;
create policy "ai_usage_admin_select"
  on public.ai_usage for select
  using (
    public.has_capability('view_metrics') or public.has_capability('manage_ai')
  );

-- ─────────────────── Seed de proveedores conocidos (deshabilitados) ──────────
-- Se crean DESHABILITADOS y sin keys; el superadmin los activa y anyade su API
-- key desde el panel. Idempotente con `on conflict (slug) do nothing`.
-- `default_model` es editable desde el panel (los IDs de modelo cambian).
insert into public.ai_providers
  (slug, display_name, tier, enabled, priority, default_model, base_url)
values
  ('gemini',     'Google Gemini',      'free', false, 10,  'gemini-1.5-flash',         null),
  ('groq',       'Groq',               'free', false, 20,  'llama-3.3-70b-versatile',  null),
  ('openrouter', 'OpenRouter',         'free', false, 30,  null,                        'https://openrouter.ai/api/v1'),
  ('anthropic',  'Anthropic (Claude)', 'paid', false, 100, 'claude-3-5-sonnet-latest',  null),
  ('openai',     'OpenAI',             'paid', false, 110, 'gpt-4o-mini',               null),
  ('deepseek',   'DeepSeek',           'paid', false, 120, 'deepseek-chat',             'https://api.deepseek.com')
on conflict (slug) do nothing;
