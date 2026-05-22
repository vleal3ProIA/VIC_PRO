-- ============================================================================
-- 0049 · Toggles de métodos de inicio de sesión (admin)
-- ----------------------------------------------------------------------------
-- El admin puede ocultar/mostrar cada método de login alternativo desde
-- `/admin/app-branding` (por si un proveedor falla o aún no está
-- implementado). El login lee estos flags y solo muestra los activos.
--
-- Email + contraseña es el método base y NO es configurable (siempre on).
-- Los flags solo cubren los métodos alternativos:
--   - Google (OAuth)
--   - Apple (OAuth)
--   - Magic link
--   - OTP (código por email)
--   - Passkey (WebAuthn)
--
-- Default `true` (comportamiento actual: todos visibles). El admin los
-- apaga cuando quiera.
--
-- **RLS**: no hace falta cambiar policies. La escritura de `app_branding`
-- ya está gateada por `has_capability('manage_app_branding')` (0048) a
-- nivel de fila; las columnas nuevas quedan cubiertas. El SELECT sigue
-- siendo público (anon+authenticated) para que el login las lea.
-- ============================================================================

alter table public.app_branding
  add column if not exists auth_google_enabled boolean not null default true,
  add column if not exists auth_apple_enabled boolean not null default true,
  add column if not exists auth_magic_link_enabled boolean not null default true,
  add column if not exists auth_otp_enabled boolean not null default true,
  add column if not exists auth_passkey_enabled boolean not null default true;
