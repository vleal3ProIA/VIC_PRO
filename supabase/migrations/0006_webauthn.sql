-- ============================================================================
-- 0006 · WebAuthn / Passkeys
-- ----------------------------------------------------------------------------
-- Tablas para almacenar credenciales WebAuthn (passkeys) y challenges
-- temporales de la "ceremonia" de registro/autenticación.
--
-- - `webauthn_credentials`: una fila por passkey registrado. Guarda la
--   public key + contador (anti-clonado). Nunca la private key (esa nunca
--   sale del dispositivo del usuario).
-- - `webauthn_challenges`: nonce temporal generado por el servidor en
--   "options" y consumido en "verify". TTL 5 min. Se va con el usuario al
--   borrarlo (cascade).
--
-- La Edge Function `webauthn` (service_role) hace toda la lógica. El usuario
-- puede leer/borrar SUS propios credenciales para listar/quitar passkeys
-- desde Ajustes.
-- ============================================================================

-- 1) Credenciales registradas ------------------------------------------------
create table if not exists public.webauthn_credentials (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  credential_id   text not null unique,           -- base64url
  public_key      text not null,                  -- base64url (COSE public key)
  counter         bigint not null default 0,
  device_type     text,                           -- 'singleDevice' | 'multiDevice'
  backed_up       boolean,
  transports      text[],                         -- ['internal','hybrid',...]
  friendly_name   text,
  created_at      timestamptz not null default now(),
  last_used_at    timestamptz
);

create index if not exists webauthn_credentials_user_idx
  on public.webauthn_credentials (user_id);

alter table public.webauthn_credentials enable row level security;

-- El usuario lista sus propios passkeys (en Ajustes).
drop policy if exists "webauthn_credentials_select_own"
  on public.webauthn_credentials;
create policy "webauthn_credentials_select_own"
  on public.webauthn_credentials for select
  using (auth.uid() = user_id);

-- El usuario puede borrar uno de los suyos. Insert/update SOLO por la
-- Edge Function con service_role (la firma criptográfica se verifica ahí).
drop policy if exists "webauthn_credentials_delete_own"
  on public.webauthn_credentials;
create policy "webauthn_credentials_delete_own"
  on public.webauthn_credentials for delete
  using (auth.uid() = user_id);

-- 2) Challenges temporales ---------------------------------------------------
create table if not exists public.webauthn_challenges (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade,  -- null en auth
  challenge    text not null,
  type         text not null check (type in ('registration', 'authentication')),
  expires_at   timestamptz not null default (now() + interval '5 minutes'),
  created_at   timestamptz not null default now()
);

create index if not exists webauthn_challenges_expires_idx
  on public.webauthn_challenges (expires_at);

-- Los challenges los maneja exclusivamente la Edge Function: el usuario no
-- necesita verlos. RLS habilitado SIN policies → bloqueado por completo
-- para usuarios; la service_role se la salta.
alter table public.webauthn_challenges enable row level security;
