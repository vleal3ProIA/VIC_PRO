-- ============================================================================
-- 0074 · Super-admin alerts (user lifecycle events)
-- ----------------------------------------------------------------------------
-- Notifica a TODOS los super_admins por email + in-app cuando ocurre
-- uno de estos 3 eventos de ciclo de vida de usuario:
--
--   1. user.registered      <- nuevo signup (trigger AFTER INSERT en
--                              public.profiles, creado abajo).
--   2. user.role_changed    <- super promueve/revoca admin (las RPCs
--                              super_admin_promote_to_admin /
--                              super_admin_revoke_admin disparan tambien
--                              el http_post, ver mas abajo).
--   3. user.deleted         <- user borra su cuenta (lo dispara la EF
--                              delete-account ANTES de borrar para tener
--                              email/username; aqui solo dejamos la
--                              infra http_post, no toca nada SQL extra).
--
-- Patron: el trigger / RPC hace un `pg_net.http_post` async (no
-- bloqueante) a la EF `notify-super-admins`, que es la unica que sabe
-- (a) quienes son los super admins, (b) como renderizar el email y
-- (c) como insertar la fila en `public.notifications`. Asi la BD no
-- tiene que saber nada de email ni i18n: separacion de responsabilidades.
--
-- ============================================================================
-- ONE-TIME SETUP (admin, antes de que estos triggers/RPCs disparen util):
--
--   1) Asegurar que tienes los secrets en Supabase Edge Function env
--      (ya estan: SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY se inyectan
--      automaticamente; SMTP_* ya configurado para send-email).
--
--   2) Almacenar en `vault.decrypted_secrets` la URL del proyecto y el
--      service-role JWT para que el trigger pueda leerlos:
--
--        select vault.create_secret(
--          'https://jzgtghddqofxewzmpmbx.supabase.co',
--          'supabase_project_url'
--        );
--        select vault.create_secret(
--          '<service-role-jwt>',
--          'supabase_service_role_key'
--        );
--
--      (Reemplazar `<service-role-jwt>` por el JWT desde
--       Project Settings -> API -> `service_role` key.)
--
--   3) Desplegar la EF nueva:
--        supabase functions deploy notify-super-admins
--
-- Si los secrets del vault no existen aun, los triggers/RPCs hacen
-- no-op silencioso (la registracion / cambio de rol funciona igual).
-- Asi el deploy es "fail-safe" — nunca rompemos UX por un secret que
-- falta.
-- ============================================================================

-- ─────────────── 1) Extension pg_net (HTTP async desde SQL) ───────────────
-- Supabase la trae preinstalada en `extensions`; este `create extension`
-- es idempotente -- si ya existe, no-op.

create extension if not exists pg_net with schema extensions;

-- ─────────────── 2) Helper interno: post fire-and-forget ───────────────
--
-- Lee los 2 secrets del vault. Si alguno falta, devuelve false sin
-- lanzar (los triggers que lo invocan tratan esto como "se ignora la
-- alerta" y siguen su camino sin bloquear nada).
--
-- SECURITY DEFINER porque el vault.decrypted_secrets requiere
-- privilegios que el rol authenticated no tiene. Solo el dueno
-- (postgres) puede leer ese schema; este wrapper lo encapsula.

create or replace function public.notify_super_admins_post(
  p_payload jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url       text;
  v_jwt       text;
  v_endpoint  text;
begin
  -- Defensa #1: secret URL. Si no esta, no-op silencioso.
  select decrypted_secret into v_url
  from vault.decrypted_secrets
  where name = 'supabase_project_url'
  limit 1;
  if v_url is null or v_url = '' then
    return false;
  end if;

  -- Defensa #2: service role key.
  select decrypted_secret into v_jwt
  from vault.decrypted_secrets
  where name = 'supabase_service_role_key'
  limit 1;
  if v_jwt is null or v_jwt = '' then
    return false;
  end if;

  v_endpoint := rtrim(v_url, '/') || '/functions/v1/notify-super-admins';

  -- pg_net.http_post es async: encola la request en la cola de
  -- pg_net.background_workers y devuelve enseguida. NUNCA bloquea
  -- la transaccion que dispara el trigger.
  -- Wrap en exception handler defensivo extra -- si pg_net falla por
  -- alguna razon (worker caido, permisos, etc.), seguimos sin error.
  begin
    perform extensions.http_post(
      url     := v_endpoint,
      body    := p_payload,
      headers := jsonb_build_object(
        'Content-Type',    'application/json',
        'X-Internal-Auth', v_jwt
      )
    );
    return true;
  exception when others then
    -- No leakeamos v_jwt en el mensaje. Solo log de "fallo el post".
    raise warning 'notify_super_admins_post: http_post failed (silenced)';
    return false;
  end;
end;
$$;

revoke all on function public.notify_super_admins_post(jsonb) from public;
-- Solo se invoca desde triggers/RPCs SECURITY DEFINER del propio
-- schema. authenticated / anon NO deben poder llamarla.

comment on function public.notify_super_admins_post(jsonb) is
  'Internal helper: fire-and-forget HTTP POST a notify-super-admins. '
  'Lee credenciales de vault.decrypted_secrets. No-op si faltan. '
  'Nunca bloquea ni lanza.';

-- ─────────────── 3) Trigger user.registered ───────────────
--
-- AFTER INSERT en public.profiles -> dispara la alerta. NO usamos
-- auth.users porque el trigger handle_new_user() (0001) crea la
-- fila en profiles inmediatamente tras el insert en auth.users con
-- los datos canonicos (username derivado del email).

create or replace function public.notify_super_admins_user_registered()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email    text;
  v_username text;
begin
  -- Sacar email desde auth.users (profiles solo tiene username/display).
  begin
    select u.email::text into v_email
    from auth.users u
    where u.id = NEW.id;
  exception when others then
    v_email := null;
  end;

  v_username := coalesce(NEW.username, NEW.display_name, '');

  -- Fire-and-forget. Si falla todo (no hay secrets / pg_net caido /
  -- vault inaccesible), se traga el error y la registracion sigue.
  begin
    perform public.notify_super_admins_post(jsonb_build_object(
      'event',    'user.registered',
      'user_id',  NEW.id,
      'email',    coalesce(v_email, ''),
      'username', v_username
    ));
  exception when others then
    -- NUNCA bloquear el signup por un fallo de notificacion.
    null;
  end;

  return NEW;
end;
$$;

drop trigger if exists trg_notify_super_admins_user_registered on public.profiles;
create trigger trg_notify_super_admins_user_registered
  after insert on public.profiles
  for each row
  execute function public.notify_super_admins_user_registered();

comment on function public.notify_super_admins_user_registered() is
  'Trigger AFTER INSERT en profiles -> alerta async a super_admins. '
  'No bloquea: cualquier fallo se traga silenciosamente.';

-- ─────────────── 4) Hook en RPCs de cambio de rol ───────────────
--
-- La promocion / demote de admin se hace via RPCs SECURITY DEFINER
-- (definidas en 0044). NO via Edge Function. Reescribimos esas RPCs
-- para que, tras el UPDATE exitoso, disparen el http_post con el
-- prev_role -> new_role.
--
-- Estrategia: capturamos el valor anterior dentro de la RPC, hacemos
-- el UPDATE, y disparamos la alerta. El wrap en exception handler
-- protege la operacion principal: si la alerta falla, el cambio de
-- rol persiste y la UI no se entera del fallo.

create or replace function public.super_admin_promote_to_admin(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prev_role text;
  v_email     text;
  v_username  text;
begin
  if not public.is_super_admin() then
    raise exception 'super admin only';
  end if;
  if p_user_id is null then
    raise exception 'p_user_id required';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'user_not_found';
  end if;

  -- Capturar prev_role ANTES del update para el payload.
  select role into v_prev_role from public.profiles where id = p_user_id;

  update public.profiles set role = 'admin' where id = p_user_id;

  -- Datos del subject (para el payload de la alerta).
  begin
    select u.email::text into v_email from auth.users u where u.id = p_user_id;
  exception when others then
    v_email := null;
  end;
  select coalesce(p.username, p.display_name, '') into v_username
  from public.profiles p where p.id = p_user_id;

  -- Fire-and-forget. El cambio de rol ya esta persistido; la alerta
  -- es best-effort.
  begin
    perform public.notify_super_admins_post(jsonb_build_object(
      'event',     'user.role_changed',
      'user_id',   p_user_id,
      'email',     coalesce(v_email, ''),
      'username',  v_username,
      'prev_role', coalesce(v_prev_role, 'user'),
      'new_role',  'admin'
    ));
  exception when others then
    null;
  end;
end;
$$;

create or replace function public.super_admin_revoke_admin(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_super  boolean;
  v_prev_role text;
  v_email     text;
  v_username  text;
begin
  if not public.is_super_admin() then
    raise exception 'super admin only';
  end if;
  if p_user_id is null then
    raise exception 'p_user_id required';
  end if;

  select is_super_admin into v_is_super
  from public.profiles where id = p_user_id;
  if coalesce(v_is_super, false) then
    raise exception 'cannot revoke super admin via this RPC';
  end if;

  -- Capturar prev_role ANTES del update.
  select role into v_prev_role from public.profiles where id = p_user_id;

  -- Borrar capabilities primero (mismo orden que 0044).
  delete from public.admin_capabilities where user_id = p_user_id;
  -- Demote.
  update public.profiles set role = 'user' where id = p_user_id;

  begin
    select u.email::text into v_email from auth.users u where u.id = p_user_id;
  exception when others then
    v_email := null;
  end;
  select coalesce(p.username, p.display_name, '') into v_username
  from public.profiles p where p.id = p_user_id;

  begin
    perform public.notify_super_admins_post(jsonb_build_object(
      'event',     'user.role_changed',
      'user_id',   p_user_id,
      'email',     coalesce(v_email, ''),
      'username',  v_username,
      'prev_role', coalesce(v_prev_role, 'admin'),
      'new_role',  'user'
    ));
  exception when others then
    null;
  end;
end;
$$;

-- Re-grant (las RPCs ya existian; CREATE OR REPLACE preserva grants,
-- pero por defensa re-aplicamos para que el deploy sea idempotente).
revoke all on function public.super_admin_promote_to_admin(uuid) from public;
revoke all on function public.super_admin_revoke_admin(uuid)     from public;
grant execute on function public.super_admin_promote_to_admin(uuid) to authenticated;
grant execute on function public.super_admin_revoke_admin(uuid)     to authenticated;

-- ─────────────── 5) (No hay trigger para user.deleted) ───────────────
--
-- La EF `delete-account` invoca notify-super-admins ANTES de
-- ejecutar auth.admin.deleteUser, porque despues el row de profiles
-- ya no existe y perderiamos email/username. No hay nada SQL que
-- anyadir aqui.
