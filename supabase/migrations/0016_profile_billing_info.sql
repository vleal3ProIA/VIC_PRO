-- ============================================================================
-- 0016 · profiles: campos de facturación
-- ----------------------------------------------------------------------------
-- Añade los campos que Stripe necesita en el Customer para que las facturas
-- salgan correctas (nombre, dirección, NIF/VAT). Antes de pasar por
-- Checkout, la UI exige que el usuario rellene estos campos.
--
-- Todos nullables — los users existentes los rellenan cuando vayan al
-- primer checkout. RLS sigue siendo "el user ve/edita su propio profile".
-- ============================================================================

alter table public.profiles
  add column if not exists first_name     text,
  add column if not exists last_name      text,
  add column if not exists date_of_birth  date,
  add column if not exists address_line1  text,
  add column if not exists address_line2  text,
  add column if not exists city           text,
  add column if not exists postal_code    text,
  -- Código ISO 3166-1 alpha-2 (ES, US, DE...). Lo validamos en cliente
  -- contra la lista de países que Stripe acepta.
  add column if not exists country        text
    check (country is null or country ~ '^[A-Z]{2}$'),
  -- Tax ID libre por simplicidad (NIF, VAT, EIN...). Validación
  -- específica por país se hace en cliente.
  add column if not exists tax_id         text,
  add column if not exists tax_id_type    text;

comment on column public.profiles.country is
  'ISO 3166-1 alpha-2. Validado por regex; lista de países permitidos se gestiona en cliente.';
comment on column public.profiles.tax_id is
  'NIF, VAT, EIN, etc. Tipo en tax_id_type para Stripe (eu_vat, es_cif…).';
comment on column public.profiles.tax_id_type is
  'Stripe tax ID type: eu_vat | es_cif | us_ein | etc. Lista en https://stripe.com/docs/api/customers/object#customer_object-tax_ids';
