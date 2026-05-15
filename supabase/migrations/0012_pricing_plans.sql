-- ============================================================================
-- 0012 · Pricing: plans + tenant_subscriptions + entitlements
-- ----------------------------------------------------------------------------
-- Modelo de datos para SaaS billing **sin** integración Stripe todavía. La
-- columna `stripe_*` queda nullable; la siguiente PR (1.E) la rellena al
-- crear/actualizar suscripciones vía webhooks.
--
-- Conceptos:
--   - **Plan**: oferta de catálogo. Tiene precio mensual/anual y un mapa
--     de `features` (entitlements: límites + flags-de-plan).
--   - **Subscription**: relación tenant ↔ plan, con período y estado. Un
--     tenant puede tener histórico, pero solo UNA active/trialing a la vez.
--   - **Entitlement**: cuota o capacidad derivada del plan activo
--     (`max_members`, `ai_credits_per_month`, `white_label`, …). Lo lee
--     la UI/el backend para gatear acciones.
--
-- Defaults:
--   - Al crear un tenant, trigger lo suscribe al plan `free`.
-- ============================================================================

-- 1) Tabla plans ───────────────────────────────────────────────────────────

create table if not exists public.plans (
  id                    uuid primary key default gen_random_uuid(),
  slug                  text not null unique
                        check (slug ~ '^[a-z][a-z0-9_]{1,30}$'),
  name                  text not null check (char_length(name) between 1 and 80),
  description           text,
  -- Precios en centavos para evitar floats. NULL en planes "contact us".
  price_monthly_cents   integer check (price_monthly_cents is null or price_monthly_cents >= 0),
  price_yearly_cents    integer check (price_yearly_cents  is null or price_yearly_cents  >= 0),
  currency              text not null default 'EUR'
                        check (currency in ('EUR','USD','GBP')),
  -- `features` = entitlements del plan. Forma libre jsonb pero seguimos
  -- una convención: claves snake_case, números enteros para cuotas, bool
  -- para capabilities, strings para enums.
  -- Ej. {"max_members": 5, "ai_credits": 100, "white_label": false}
  features              jsonb not null default '{}'::jsonb,
  -- Orden de visualización en la /billing/plans (más bajo = más a la izquierda).
  position              integer not null default 0,
  -- Plan oculto del catálogo público (p.ej. 'enterprise' negociado a mano).
  is_active             boolean not null default true,
  -- Stripe Product/Price IDs (se rellenan al crear el plan en Stripe).
  stripe_price_monthly  text,
  stripe_price_yearly   text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

drop trigger if exists plans_set_updated_at on public.plans;
create trigger plans_set_updated_at
  before update on public.plans
  for each row execute function public.set_updated_at();

-- 2) Tabla tenant_subscriptions ───────────────────────────────────────────

do $$ begin
  create type public.subscription_status as enum (
    'trialing','active','past_due','canceled','incomplete'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.billing_period as enum ('monthly','yearly');
exception when duplicate_object then null;
end $$;

create table if not exists public.tenant_subscriptions (
  id                     uuid primary key default gen_random_uuid(),
  tenant_id              uuid not null references public.tenants(id) on delete cascade,
  plan_id                uuid not null references public.plans(id)   on delete restrict,
  status                 public.subscription_status not null default 'active',
  billing_period         public.billing_period      not null default 'monthly',
  -- Período de cobro actual. NULL para planes gratis (sin facturación real).
  current_period_start   timestamptz,
  current_period_end     timestamptz,
  trial_end              timestamptz,
  canceled_at            timestamptz,
  -- Stripe metadata (se rellena en 1.E con webhooks).
  stripe_subscription_id text,
  stripe_customer_id     text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

drop trigger if exists tenant_subscriptions_set_updated_at on public.tenant_subscriptions;
create trigger tenant_subscriptions_set_updated_at
  before update on public.tenant_subscriptions
  for each row execute function public.set_updated_at();

-- Solo UNA suscripción "viva" por tenant (trialing/active/past_due/incomplete).
-- Una `canceled` ya no compite.
create unique index if not exists tenant_subscriptions_one_live
  on public.tenant_subscriptions (tenant_id)
  where status in ('trialing','active','past_due','incomplete');

create index if not exists tenant_subscriptions_plan_idx
  on public.tenant_subscriptions (plan_id);

-- 3) RLS ───────────────────────────────────────────────────────────────────

alter table public.plans                  enable row level security;
alter table public.tenant_subscriptions   enable row level security;

-- Plans: público para todos los autenticados (catálogo).
drop policy if exists "plans_select_authenticated" on public.plans;
create policy "plans_select_authenticated"
  on public.plans for select to authenticated
  using (is_active or public.is_admin());

drop policy if exists "plans_admin_write" on public.plans;
create policy "plans_admin_write"
  on public.plans for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Subscriptions: el usuario ve las de sus tenants.
drop policy if exists "subs_select_member" on public.tenant_subscriptions;
create policy "subs_select_member"
  on public.tenant_subscriptions for select to authenticated
  using (tenant_id in (select public.user_tenants(auth.uid())));

-- Escritura solo admin global (los cambios "normales" vendrán por webhooks
-- de Stripe con service_role; el cliente nunca cambia su plan directamente).
drop policy if exists "subs_admin_write" on public.tenant_subscriptions;
create policy "subs_admin_write"
  on public.tenant_subscriptions for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 4) Trigger: nuevo tenant → suscripción al plan free ─────────────────────

create or replace function public.handle_new_tenant_subscription()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog as $$
declare
  v_free_plan_id uuid;
begin
  select id into v_free_plan_id from public.plans where slug = 'free' limit 1;
  if v_free_plan_id is null then return new; end if;  -- defensivo

  insert into public.tenant_subscriptions (tenant_id, plan_id, status, billing_period)
  values (new.id, v_free_plan_id, 'active', 'monthly')
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_tenant_created_subscription on public.tenants;
create trigger on_tenant_created_subscription
  after insert on public.tenants
  for each row execute function public.handle_new_tenant_subscription();

-- 5) RPC `tenant_entitlements(tenant_id)` ─────────────────────────────────
-- Devuelve el `features jsonb` del plan activo del tenant. La UI lo lee
-- para gatear acciones (ej. "ya estás en el límite de miembros").

create or replace function public.tenant_entitlements(p_tenant_id uuid)
returns jsonb
language sql stable security definer
set search_path = public, pg_catalog as $$
  select coalesce(p.features, '{}'::jsonb)
  from public.tenant_subscriptions s
  join public.plans p on p.id = s.plan_id
  where s.tenant_id = p_tenant_id
    and s.status in ('trialing','active')
    -- Asegura que el caller pertenece al tenant (no se puede consultar ajeno):
    and s.tenant_id in (select public.user_tenants(auth.uid()))
  limit 1;
$$;

comment on function public.tenant_entitlements(uuid) is
  'Devuelve `features jsonb` del plan activo del tenant — los entitlements (cuotas + capabilities) que la UI usa para gatear.';

-- 6) Seed plans ────────────────────────────────────────────────────────────
-- Idempotente: si ya existen, no se duplican.

insert into public.plans (slug, name, description, price_monthly_cents, price_yearly_cents, features, position)
values
  ('free',
   'Free',
   'Gratis para siempre. Perfecto para empezar.',
   0, 0,
   '{"max_members": 3, "max_storage_gb": 1, "ai_credits": 0, "support": "community"}'::jsonb,
   10),
  ('pro',
   'Pro',
   'Para equipos pequeños que necesitan más.',
   1900, 19000,
   '{"max_members": 25, "max_storage_gb": 50, "ai_credits": 1000, "support": "email", "custom_domain": true}'::jsonb,
   20),
  ('business',
   'Business',
   'Empresas en crecimiento con necesidades avanzadas.',
   4900, 49000,
   '{"max_members": 100, "max_storage_gb": 250, "ai_credits": 10000, "support": "priority", "custom_domain": true, "sso": true, "audit_log_retention_days": 365}'::jsonb,
   30),
  ('enterprise',
   'Enterprise',
   'Precio bajo demanda. SSO, SLA, y soporte 24/7.',
   null, null,
   '{"max_members": -1, "max_storage_gb": -1, "ai_credits": -1, "support": "dedicated", "custom_domain": true, "sso": true, "audit_log_retention_days": -1, "white_label": true}'::jsonb,
   40)
on conflict (slug) do nothing;

-- Asegura que los tenants ya existentes (creados antes de esta migración)
-- tienen una suscripción al plan free.

insert into public.tenant_subscriptions (tenant_id, plan_id, status, billing_period)
select t.id, p.id, 'active', 'monthly'
from public.tenants t
cross join public.plans p
where p.slug = 'free'
  and not exists (
    select 1 from public.tenant_subscriptions s
    where s.tenant_id = t.id
      and s.status in ('trialing','active','past_due','incomplete')
  );
