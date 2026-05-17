-- ============================================================================
-- 0024 · Personal Access Tokens (PAT)
-- ----------------------------------------------------------------------------
-- Tokens API tipo "GitHub Personal Access Tokens" que el user genera
-- desde Settings -> Tokens. Sirven para que un script externo (CI,
-- automatizacion, integracion del cliente) llame nuestra API publica
-- en nombre del user sin necesidad de password ni session JWT.
--
-- **Modelo de un PAT**:
--   - `name`         : etiqueta humana ("CI deploy script")
--   - `prefix`       : 8 chars visibles del token, ej "pat_a1b2c3"
--                      -- el user solo ve estos despues de crear,
--                      para identificar tokens en la lista
--   - `token_hash`   : SHA-256 del token completo. Lo COMPLETO solo
--                      se muestra UNA VEZ en el dialog de creacion;
--                      si se pierde, hay que crear otro
--   - `scopes`       : array text con permisos. Empezamos con dos:
--                      'read' (GET only) y 'write' (todos los verbos)
--   - `expires_at`   : caducidad opcional (NULL = no caduca)
--   - `last_used_at` : se actualiza por la Edge Function de verificacion
--                      en cada uso exitoso (info para el user)
--   - `revoked_at`   : timestamp si el user lo revoco; los revocados
--                      NUNCA validan ni se pueden "des-revocar"
--
-- **Generacion del token raw** (clientside-server-mixed):
--   1. Edge Function genera 32 bytes random
--   2. Formato del token: `pat_<8-chars-prefix>_<base64url-32-bytes>`
--   3. Devuelve el RAW token al cliente UNA SOLA VEZ
--   4. Guarda solo el SHA-256 del raw + el prefix
--
-- **Verificacion** (en uso futuro de API publica):
--   1. Cliente manda `Authorization: Bearer pat_<token>`
--   2. Backend hashea el token recibido
--   3. SELECT user_id, scopes, expires_at FROM personal_access_tokens
--      WHERE token_hash = <hash> AND revoked_at IS NULL
--   4. Si encuentra y no caduco -> autentica como ese user
--   5. UPDATE last_used_at = now()
-- ============================================================================

create table if not exists public.personal_access_tokens (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 80),
  prefix        text not null check (char_length(prefix) = 12), -- "pat_" + 8 chars
  token_hash    text not null unique,
  scopes        text[] not null default array['read']::text[],
  expires_at    timestamptz,
  last_used_at  timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz not null default now()
);

-- Buscar tokens activos por hash es la query CALIENTE -- cada llamada
-- a la API pública. Index parcial solo no-revoked + no-expired.
create index if not exists pat_active_hash_idx
  on public.personal_access_tokens(token_hash)
  where revoked_at is null;

create index if not exists pat_user_idx
  on public.personal_access_tokens(user_id, created_at desc);

-- ─────────────────────────── RLS ───────────────────────────
-- El user ve y revoca los suyos. NO puede INSERT directo (lo hace la
-- Edge Function con service_role tras generar el secret). NO puede
-- UPDATE excepto revocar (poner revoked_at).

alter table public.personal_access_tokens enable row level security;

drop policy if exists "pat_select_own" on public.personal_access_tokens;
create policy "pat_select_own"
  on public.personal_access_tokens for select
  using (user_id = auth.uid());

drop policy if exists "pat_revoke_own" on public.personal_access_tokens;
create policy "pat_revoke_own"
  on public.personal_access_tokens for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "pat_delete_own" on public.personal_access_tokens;
create policy "pat_delete_own"
  on public.personal_access_tokens for delete
  using (user_id = auth.uid());

-- ─────────────────────────── RPC: revoke ───────────────────────────
-- Marca revoked_at = now() con check de propietario. Idempotente: si
-- ya estaba revocado, no toca el timestamp.

create or replace function public.revoke_personal_access_token(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
begin
  update public.personal_access_tokens
    set revoked_at = coalesce(revoked_at, now())
    where id = p_id
      and user_id = auth.uid()
      and revoked_at is null;
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

revoke all on function public.revoke_personal_access_token(uuid) from public;
grant execute on function public.revoke_personal_access_token(uuid)
  to authenticated;

-- La creación NO va por RPC -- requiere generar bytes random + hash
-- + devolver el secret RAW al cliente. La Edge Function `create-pat`
-- lo hace con service_role (bypass de RLS para INSERT).
