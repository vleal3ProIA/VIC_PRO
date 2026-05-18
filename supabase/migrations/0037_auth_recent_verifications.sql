-- ============================================================================
-- 0037 · Re-autenticacion para acciones criticas (PR-F)
-- ----------------------------------------------------------------------------
-- Tabla + helper RPC para enforcement server-side de re-auth con
-- password en acciones destructivas o de privilegio.
--
-- **Por que?**
--   El flow actual de /delete-account pide password en frontend y hace
--   `signInWithPassword` antes de invocar la Edge Function. Pero la
--   Edge Function SOLO valida el JWT -- no confirma que la verificacion
--   reciente con password haya pasado. Un atacante con JWT robado
--   (XSS, cookie steal) puede invocar delete-account directamente
--   saltandose el modal. Ver SECURITY.md sec.6 PR-F.
--
-- **Como funciona el flow tras PR-F**:
--   1. Cliente pide al user su password en un modal.
--   2. Cliente invoca Edge Function `verify-password` con
--      { password, action_kind }. La function valida con
--      signInWithPassword temporal + INSERT en esta tabla.
--   3. Cliente invoca la accion destructiva (delete-account, etc.).
--   4. La Edge Function destructiva LLAMA a `has_recent_verification()`
--      RPC para confirmar que existe una fila con action_kind correcto
--      y verified_at < TTL (5 min). Si no, 403.
--
-- **Acciones cubiertas en PR-F inicial** (mas se anyaden mas adelante):
--   - 'delete_account'           -> /delete-account
--   - 'create_pat_write'         -> /tokens (PAT con scope write)
--
-- **Anyadidos como deuda explicita** (PR-F-bis o despues):
--   - 'change_email'             -> requiere reescribir el flow actual
--                                   (hoy es client-side updateUser).
--   - 'webhook_secret_rotate'    -> requiere endpoint server-side.
--   - 'role_change'              -> requiere endpoint admin para cambiar role.
--
-- **Por que TTL 5 min y no algo mas largo/corto?**
--   - 1 min seria fricciona (el user pide password, navega a la pagina,
--     puede tardar 30s + leer disclaimer + click destructivo).
--   - 15 min es ventana demasiado grande post-secuestro.
--   - 5 min es balance estandar de la industria (GitHub usa 5-30 min
--     dependiendo de la accion).
-- ============================================================================

create table if not exists public.auth_recent_verifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  action_kind  text not null check (char_length(action_kind) between 1 and 40),
  verified_at  timestamptz not null default now()
);

-- Indice compuesto: el lookup tipico es
--   "este user tiene verificacion fresca de este action_kind?"
-- ORDER BY verified_at DESC LIMIT 1 -> 1 lectura por check.
create index if not exists auth_recent_verifications_lookup_idx
  on public.auth_recent_verifications(user_id, action_kind, verified_at desc);

-- ─────────────────────────── RLS ───────────────────────────
-- SELECT: el user lee sus propias verificaciones (util para UI:
--   "tu re-auth caduca en 4:13 minutos").
-- INSERT/UPDATE/DELETE: solo service_role (a traves de verify-password
--   Edge Function). El cliente NUNCA escribe directamente -- de otra
--   forma podria fabricar verificaciones falsas.

alter table public.auth_recent_verifications enable row level security;

drop policy if exists "auth_recent_verifications_select_own"
  on public.auth_recent_verifications;
create policy "auth_recent_verifications_select_own"
  on public.auth_recent_verifications for select
  using (user_id = auth.uid());

-- ─────────────── RPC: has_recent_verification ───────────────
-- Devuelve true si el user actual tiene una verificacion fresca para
-- el action_kind dado. La invocan las Edge Functions destructivas
-- antes de actuar. SECURITY DEFINER para que funcione tanto desde
-- JWT de user (auth.uid()) como desde service_role (donde auth.uid()
-- es null -- en ese caso esperamos que el caller pase explicito el
-- p_user_id).

create or replace function public.has_recent_verification(
  p_action_kind text,
  p_ttl         interval default interval '5 minutes',
  p_user_id     uuid     default null   -- override para service_role
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  -- Resolver el user: si caller pasa p_user_id (service_role usecase),
  -- usar ese; sino, el del JWT actual.
  v_uid := coalesce(p_user_id, auth.uid());
  if v_uid is null then
    return false;
  end if;

  return exists (
    select 1
    from public.auth_recent_verifications
    where user_id = v_uid
      and action_kind = p_action_kind
      and verified_at > now() - p_ttl
  );
end;
$$;

revoke all on function public.has_recent_verification(text, interval, uuid)
  from public;
grant execute on function public.has_recent_verification(text, interval, uuid)
  to authenticated, service_role;

-- ─────────────── RPC: consume_recent_verification ───────────────
-- Variante que ADEMAS de comprobar, BORRA la fila si existe (uso de
-- una sola vez). Util para acciones que NO deberian poder repetirse
-- con la misma verificacion (ej. delete_account -- si por algun bug
-- el cliente reintenta tras un fail intermedio, queremos que pida
-- password de nuevo).
--
-- Devuelve true si habia verificacion fresca (y la consumio); false
-- si no la habia (y no hace nada).

create or replace function public.consume_recent_verification(
  p_action_kind text,
  p_ttl         interval default interval '5 minutes',
  p_user_id     uuid     default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_id  uuid;
begin
  v_uid := coalesce(p_user_id, auth.uid());
  if v_uid is null then
    return false;
  end if;

  delete from public.auth_recent_verifications
  where id = (
    select id
    from public.auth_recent_verifications
    where user_id = v_uid
      and action_kind = p_action_kind
      and verified_at > now() - p_ttl
    order by verified_at desc
    limit 1
  )
  returning id into v_id;

  return v_id is not null;
end;
$$;

revoke all on function public.consume_recent_verification(text, interval, uuid)
  from public;
grant execute on function public.consume_recent_verification(text, interval, uuid)
  to authenticated, service_role;

-- ─────────────── Cleanup automatico ───────────────
-- Las filas expiran logicamente tras 5 min, pero fisicamente se quedan
-- hasta que un cron las purgue. Como no hay pg_cron en plan free de
-- Supabase, dejamos un helper para que una Edge Function de
-- mantenimiento (futura) lo llame.

create or replace function public.purge_old_verifications(
  p_older_than interval default interval '1 hour'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  delete from public.auth_recent_verifications
  where verified_at < now() - p_older_than;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.purge_old_verifications(interval) from public;
grant execute on function public.purge_old_verifications(interval) to service_role;
