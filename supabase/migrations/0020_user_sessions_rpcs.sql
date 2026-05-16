-- ============================================================================
-- 0020 · RPCs públicas para que el usuario gestione sus auth.sessions
-- ----------------------------------------------------------------------------
-- Supabase BLOQUEA el acceso REST al schema `auth` por defecto — esto es
-- una restricción de seguridad: ningún cliente debería leer `auth.users`
-- u otras tablas internas via PostgREST. La Edge Function intentaba con
-- `admin.schema('auth').from('sessions')` y recibía `Invalid schema: auth`.
--
-- Solución limpia: exponemos tres funciones SECURITY DEFINER en el schema
-- `public` que ENCAPSULAN la lectura/escritura de `auth.sessions` y
-- `auth.refresh_tokens`. La Edge Function (o el cliente, llegado el caso)
-- las llama via `.rpc('...')` y solo ve los datos del propio usuario.
--
-- La autorización va por `auth.uid()` dentro de cada función — si el
-- caller no tiene JWT válido, `auth.uid()` es NULL y la query devuelve
-- 0 filas / 0 deletes. No hace falta extra check.
-- ============================================================================

-- ────────────────────── list_user_sessions() ──────────────────────
-- Devuelve TODAS las sesiones activas del usuario actual. La columna
-- `is_current` se calcula comparando con `p_current_session_id` que
-- llega del JWT (claim session_id) — si el caller no lo pasa, queda
-- false en todas y la UI no marca ninguna.

create or replace function public.list_user_sessions(
  p_current_session_id uuid default null
)
returns table (
  id           uuid,
  user_agent   text,
  ip           text,
  created_at   timestamptz,
  updated_at   timestamptz,
  not_after    timestamptz,
  aal          text,
  is_current   boolean
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    s.id,
    s.user_agent,
    s.ip::text,
    s.created_at,
    s.updated_at,
    s.not_after,
    s.aal::text,
    (p_current_session_id is not null and s.id = p_current_session_id)
  from auth.sessions s
  where s.user_id = auth.uid()
  order by s.updated_at desc nulls last, s.created_at desc;
$$;

-- ────────────────────── revoke_user_session() ──────────────────────
-- Borra una sesión concreta del propio usuario. Si el id no pertenece
-- al usuario actual, no borra nada (silent no-op por seguridad, no
-- queremos filtrar si el id existe en otra cuenta).
-- Devuelve `true` si se borró algo, `false` si no.

create or replace function public.revoke_user_session(p_session_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_deleted int;
begin
  -- Revocamos primero los refresh_tokens asociados (defensivo — el
  -- cascade del FK los borraría igual, pero así no quedan vivos si en
  -- alguna versión de Supabase cambian la FK).
  update auth.refresh_tokens
    set revoked = true
    where session_id = p_session_id
      and user_id = auth.uid();

  delete from auth.sessions
    where id = p_session_id
      and user_id = auth.uid();
  get diagnostics v_deleted = row_count;
  return v_deleted > 0;
end;
$$;

-- ────────────────────── revoke_other_user_sessions() ──────────────────────
-- Borra TODAS las sesiones del propio usuario EXCEPTO la indicada (la
-- "actual"). Si el caller no proporciona p_current_session_id, abortamos
-- para evitar deslogueo accidental — esto fuerza al cliente a saber qué
-- sesión está usando (la extraemos del JWT claim session_id).
-- Devuelve el número de sesiones revocadas.

create or replace function public.revoke_other_user_sessions(
  p_current_session_id uuid
)
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_deleted int;
begin
  if p_current_session_id is null then
    raise exception 'p_current_session_id required';
  end if;

  update auth.refresh_tokens
    set revoked = true
    where user_id = auth.uid()
      and session_id <> p_current_session_id;

  delete from auth.sessions
    where user_id = auth.uid()
      and id <> p_current_session_id;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

-- ────────────────────── Permisos ──────────────────────
-- Solo `authenticated`. `anon` no tiene auth.uid() así que no podría
-- hacer nada útil, pero por defensa explícita lo revocamos.

revoke all on function public.list_user_sessions(uuid) from public;
revoke all on function public.revoke_user_session(uuid) from public;
revoke all on function public.revoke_other_user_sessions(uuid) from public;
grant execute on function public.list_user_sessions(uuid) to authenticated;
grant execute on function public.revoke_user_session(uuid) to authenticated;
grant execute on function public.revoke_other_user_sessions(uuid) to authenticated;

comment on function public.list_user_sessions(uuid) is
  'Lista las sesiones activas del usuario actual. Marca is_current=true en la sesión que coincide con p_current_session_id (extraído del JWT por el caller).';
comment on function public.revoke_user_session(uuid) is
  'Borra una sesión del propio usuario + sus refresh_tokens. Devuelve true si se borró algo.';
comment on function public.revoke_other_user_sessions(uuid) is
  'Borra todas las sesiones del propio usuario excepto p_current_session_id. Devuelve el número de revocadas.';
