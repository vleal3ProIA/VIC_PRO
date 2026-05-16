-- ============================================================================
-- 0014 · tenant_subscriptions: cancel_at_period_end
-- ----------------------------------------------------------------------------
-- Stripe permite "cancel at period end": el cliente sigue con acceso hasta
-- el final del periodo facturado y entonces la suscripción se elimina.
-- Hasta ahora detectábamos este estado ad-hoc con `canceled_at IS NOT NULL
-- AND status='active'`, pero un campo dedicado:
--
--   - Es más explícito (la UI puede preguntar `WHERE cancel_at_period_end`).
--   - Distingue de cancelaciones inmediatas (donde status pasa a 'canceled'
--     directamente).
--   - Coincide 1:1 con el campo del objeto subscription de Stripe → menos
--     errores de mapeo en el webhook.
-- ============================================================================

alter table public.tenant_subscriptions
  add column if not exists cancel_at_period_end boolean not null default false;

comment on column public.tenant_subscriptions.cancel_at_period_end is
  'true cuando el cliente programó la cancelación pero todavía tiene acceso hasta current_period_end. Espejo del campo homónimo de Stripe.';
