-- ============================================================================
-- 0013 · Stripe event log para idempotencia de webhooks
-- ----------------------------------------------------------------------------
-- Stripe garantiza "at-least-once" delivery — un mismo evento puede llegar
-- varias veces (reintentos, timeouts del receptor). Para procesar cada uno
-- exactamente UNA vez, antes de aplicar el cambio guardamos su id aquí.
-- Si ya existe → es un duplicado, devolvemos 200 sin tocar nada.
--
-- Política de retención: limpiar eventos > 30 días con un cron (vendrá en
-- una migración posterior).
-- ============================================================================

create table if not exists public.stripe_event_log (
  id           text primary key,            -- el evt_xxxx de Stripe
  type         text not null,               -- 'customer.subscription.updated'…
  api_version  text,
  received_at  timestamptz not null default now(),
  -- Hash del payload para detectar reintentos con cambio de contenido
  -- (no debería pasar pero útil para forensics).
  payload_hash text
);

create index if not exists stripe_event_log_received_idx
  on public.stripe_event_log (received_at desc);

-- RLS: lectura solo admin global; INSERT solo desde service_role (las
-- Edge Functions usan service_role para escribir).
alter table public.stripe_event_log enable row level security;

drop policy if exists "stripe_events_admin_read" on public.stripe_event_log;
create policy "stripe_events_admin_read"
  on public.stripe_event_log for select to authenticated
  using (public.is_admin());

-- No hay policy de INSERT/UPDATE/DELETE para autenticados → service_role
-- los hace siempre desde Edge Functions.

comment on table public.stripe_event_log is
  'Idempotencia de webhooks de Stripe — un evento procesado deja aquí su id.';
