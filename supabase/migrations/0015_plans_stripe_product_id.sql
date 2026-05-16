-- ============================================================================
-- 0015 · plans: stripe_product_id
-- ----------------------------------------------------------------------------
-- Para sincronizar cambios del admin (nombre, descripción) con Stripe,
-- necesitamos el `Product` ID además de los `Price` IDs.
--
-- Hasta ahora solo guardábamos `stripe_price_monthly` y `stripe_price_yearly`.
-- Esto es suficiente para el flujo de pago, pero no para llamar a
-- `stripe.products.update(product_id, {name, description})`.
--
-- El backfill se hace en runtime por la Edge Function `admin-plans` la
-- primera vez que el admin carga la página: si el plan no tiene
-- `stripe_product_id`, se obtiene vía `stripe.prices.retrieve(price_id)`
-- y se persiste. Así no necesitamos meterlos a mano.
-- ============================================================================

alter table public.plans
  add column if not exists stripe_product_id text;

comment on column public.plans.stripe_product_id is
  'ID del Product en Stripe (prod_...). Se backfillea automáticamente la primera vez que el admin edita un plan que ya tenía Price IDs.';
