-- ============================================================================
-- 0018 · Coupons + Promotion Codes
-- ----------------------------------------------------------------------------
-- Mirror local de los recursos Coupon / PromotionCode de Stripe, gestionados
-- desde el panel admin de la app y sincronizados con la Stripe Billing API.
--
-- Conceptos:
--   - **Coupon**: la regla de descuento (%/€ fijo + duración + tope de
--     canjes + planes a los que aplica). NO se canjea directamente — solo
--     vía un PromotionCode asociado.
--   - **PromotionCode**: el código alfanumérico que el cliente teclea en
--     el checkout (ej. `VERANO2026`). Vinculado a 1 cupón. Puede tener su
--     propio tope/expiración y restricción "primera transacción".
--
-- Sync con Stripe:
--   - Al crear: la Edge Function `admin-coupons` crea primero en Stripe,
--     luego inserta aquí con el id devuelto.
--   - Al desactivar: marcamos `is_active=false` aquí Y `deleted=true` en
--     Stripe (Stripe los soft-deletes; los códigos canjeados antes siguen
--     contabilizando, los nuevos canjes se rechazan).
--   - El campo `times_redeemed` se actualiza por el webhook
--     `customer.subscription.created` / `invoice.paid` mirando el descuento
--     aplicado. Si no, se queda a 0 — es informativo, no de seguridad.
--
-- RLS:
--   - Admin: lectura y escritura total.
--   - Usuarios anónimos/autenticados: pueden LEER promotion_codes activos
--     **vía RPC** (no acceso directo) para validar en /billing/plans antes
--     del checkout — la Edge Function `validate-promotion-code` lo
--     encapsula.
-- ============================================================================

-- 1) Tabla coupons ────────────────────────────────────────────────────────

do $$ begin
  create type public.coupon_duration as enum ('once','repeating','forever');
exception when duplicate_object then null; end $$;

create table if not exists public.coupons (
  id                     uuid primary key default gen_random_uuid(),
  -- Stripe id (`coupon_xxx`). Nullable solo hasta que el sync inicial
  -- termina; en la práctica siempre está rellenado tras un create OK.
  stripe_coupon_id       text unique,
  -- Etiqueta para el admin (no se muestra al cliente). Ej. "Black Friday 2026".
  name                   text not null check (char_length(name) between 1 and 80),
  -- Exactamente UNO de percent_off / amount_off debe estar a non-null.
  percent_off            numeric(5,2) check (percent_off is null or (percent_off > 0 and percent_off <= 100)),
  amount_off_cents       integer       check (amount_off_cents is null or amount_off_cents > 0),
  -- Moneda solo aplica a amount_off; debe coincidir con la del plan en
  -- el checkout. Si percent_off, queda null.
  currency               text check (currency is null or currency in ('EUR','USD','GBP')),
  duration               public.coupon_duration not null default 'once',
  -- Solo aplica si duration='repeating'. Stripe lo exige entonces.
  duration_in_months     integer check (duration_in_months is null or duration_in_months > 0),
  -- Tope total de canjes en toda la vida del cupón (NULL = ilimitado).
  max_redemptions        integer check (max_redemptions is null or max_redemptions > 0),
  -- Fecha tras la cual el cupón ya no se puede canjear (NULL = sin caducidad).
  redeem_by              timestamptz,
  -- Restricción de planes: NULL = aplica a todos los planes activos;
  -- de lo contrario solo a los listados aquí (por slug, no por uuid, para
  -- que sobreviva a renombres de plan).
  applies_to_plan_slugs  text[],
  -- Mirror de un toggle admin. Si se desactiva, se borra en Stripe
  -- (Stripe usa "deleted=true" como soft-delete) y aquí queda is_active=false.
  is_active              boolean not null default true,
  -- Contador informativo; lo actualiza el webhook al detectar discount aplicado.
  times_redeemed         integer not null default 0,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),

  -- Reglas de coherencia: O bien percent o bien amount, nunca los dos
  -- ni ninguno; si repeating, duration_in_months obligatorio.
  constraint coupon_exactly_one_off check (
    (percent_off is not null)::int + (amount_off_cents is not null)::int = 1
  ),
  constraint coupon_amount_needs_currency check (
    amount_off_cents is null or currency is not null
  ),
  constraint coupon_repeating_needs_months check (
    duration <> 'repeating' or duration_in_months is not null
  )
);

drop trigger if exists coupons_set_updated_at on public.coupons;
create trigger coupons_set_updated_at
  before update on public.coupons
  for each row execute function public.set_updated_at();

create index if not exists coupons_active_idx on public.coupons(is_active) where is_active;

-- 2) Tabla promotion_codes ────────────────────────────────────────────────

create table if not exists public.promotion_codes (
  id                       uuid primary key default gen_random_uuid(),
  -- Stripe id (`promo_xxx`). Nullable solo en el window de creación.
  stripe_promotion_code_id text unique,
  coupon_id                uuid not null references public.coupons(id) on delete restrict,
  -- Código que teclea el cliente. Lo guardamos uppercase para evitar
  -- ambigüedad y porque Stripe lo trata case-insensitive en la práctica.
  code                     text not null unique
                           check (code ~ '^[A-Z0-9_-]{3,32}$'),
  -- Tope independiente del cupón (puede ser más restrictivo).
  max_redemptions          integer check (max_redemptions is null or max_redemptions > 0),
  -- Caducidad propia (puede ser más temprana que la del cupón).
  expires_at               timestamptz,
  -- Si true, solo aplica al primer pago del cliente (Stripe lo enforce).
  first_time_transaction   boolean not null default false,
  is_active                boolean not null default true,
  times_redeemed           integer not null default 0,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

drop trigger if exists promotion_codes_set_updated_at on public.promotion_codes;
create trigger promotion_codes_set_updated_at
  before update on public.promotion_codes
  for each row execute function public.set_updated_at();

create index if not exists promotion_codes_code_idx on public.promotion_codes(code) where is_active;
create index if not exists promotion_codes_coupon_idx on public.promotion_codes(coupon_id);

-- 3) RLS ───────────────────────────────────────────────────────────────────
-- Por defecto NEGAMOS todo y solo abrimos al admin. El acceso "público"
-- para validar códigos pasa por RPC SECURITY DEFINER (más abajo) que sí
-- puede leer las dos tablas saltando RLS.

alter table public.coupons enable row level security;
alter table public.promotion_codes enable row level security;

drop policy if exists coupons_admin_all on public.coupons;
create policy coupons_admin_all on public.coupons
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists promotion_codes_admin_all on public.promotion_codes;
create policy promotion_codes_admin_all on public.promotion_codes
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 4) RPC pública: lookup_promotion_code(p_code text)
-- ----------------------------------------------------------------------------
-- Devuelve metadatos del código + cupón si el código existe, está activo,
-- no caducó y aún tiene canjes disponibles. NO revela códigos inexistentes
-- ni desactivados (devuelve fila vacía → la Edge Function responde "código
-- no válido" de forma uniforme para no facilitar enumeración).
--
-- La Edge Function `validate-promotion-code` la llama con el JWT del user.
-- Como es SECURITY DEFINER, salta RLS y puede leer las dos tablas; pero el
-- shape de la respuesta no expone la lista completa de códigos ni datos
-- internos como `created_at` o `stripe_*_id`.

create or replace function public.lookup_promotion_code(p_code text)
returns table (
  promotion_code_id       uuid,
  code                    text,
  first_time_transaction  boolean,
  coupon_id               uuid,
  coupon_name             text,
  percent_off             numeric,
  amount_off_cents        integer,
  currency                text,
  duration                text,
  duration_in_months      integer,
  applies_to_plan_slugs   text[]
)
language sql
stable
security definer
set search_path = public
as $$
  select
    pc.id,
    pc.code,
    pc.first_time_transaction,
    c.id,
    c.name,
    c.percent_off,
    c.amount_off_cents,
    c.currency,
    c.duration::text,
    c.duration_in_months,
    c.applies_to_plan_slugs
  from public.promotion_codes pc
  join public.coupons c on c.id = pc.coupon_id
  where pc.code = upper(p_code)
    and pc.is_active
    and c.is_active
    and (pc.expires_at is null or pc.expires_at > now())
    and (c.redeem_by is null or c.redeem_by > now())
    and (pc.max_redemptions is null or pc.times_redeemed < pc.max_redemptions)
    and (c.max_redemptions is null or c.times_redeemed < c.max_redemptions)
  limit 1;
$$;

revoke all on function public.lookup_promotion_code(text) from public;
grant execute on function public.lookup_promotion_code(text) to anon, authenticated;
