-- ============================================================================
-- 0075 · Fix: notify_super_admins_post usa schema correcto de pg_net
-- ----------------------------------------------------------------------------
-- La migración 0074 creó `public.notify_super_admins_post(jsonb)` invocando
-- `extensions.http_post(...)`. Esa función NO EXISTE con esa signatura: la
-- versión correcta de `pg_net` vive en el schema `net` (no `extensions`),
-- y la firma usa parámetros `url`, `body`, `params`, `headers`,
-- `timeout_milliseconds`.
--
-- Síntoma observado:
--   - El trigger AFTER INSERT en `profiles` se disparaba.
--   - `notify_super_admins_post` retornaba `false` siempre.
--   - `net._http_response` siempre vacía.
--   - El exception handler tragaba el error
--     "function extensions.http_post(url => ..., body => ..., headers => ...)
--     does not exist" sin que nadie lo viera.
--
-- Fix: reescribimos la función para invocar `net.http_post(url, body, headers)`
-- (los 3 args con nombre — los otros tienen default). El resto de la lógica
-- se mantiene idéntica (lectura del vault, defensa, exception handler).
-- ============================================================================

create or replace function public.notify_super_admins_post(
  p_payload jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public, net
as $$
declare
  v_url       text;
  v_jwt       text;
  v_endpoint  text;
begin
  -- Defensa #1: secret URL.
  select decrypted_secret into v_url
  from vault.decrypted_secrets
  where name = 'supabase_project_url'
  limit 1;
  if v_url is null or v_url = '' then
    raise warning 'notify_super_admins_post: missing supabase_project_url in vault';
    return false;
  end if;

  -- Defensa #2: service role key.
  select decrypted_secret into v_jwt
  from vault.decrypted_secrets
  where name = 'supabase_service_role_key'
  limit 1;
  if v_jwt is null or v_jwt = '' then
    raise warning 'notify_super_admins_post: missing supabase_service_role_key in vault';
    return false;
  end if;

  v_endpoint := rtrim(v_url, '/') || '/functions/v1/notify-super-admins';

  -- net.http_post (NO extensions.http_post — esa no existe). Async: encola
  -- en pg_net.background_workers y devuelve enseguida. NUNCA bloquea la
  -- transacción que disparó el trigger.
  begin
    perform net.http_post(
      url     := v_endpoint,
      body    := p_payload,
      headers := jsonb_build_object(
        'Content-Type',    'application/json',
        'X-Internal-Auth', v_jwt
      )
    );
    return true;
  exception when others then
    -- En el catch loguamos el SQLERRM para diagnosticar en el futuro
    -- (antes lo silenciábamos por completo y por eso este bug pasó
    -- desapercibido hasta el primer signup real).
    raise warning 'notify_super_admins_post: http_post failed: %', sqlerrm;
    return false;
  end;
end;
$$;

revoke all on function public.notify_super_admins_post(jsonb) from public;

comment on function public.notify_super_admins_post(jsonb) is
  'Internal helper: fire-and-forget HTTP POST a notify-super-admins via '
  'net.http_post (pg_net schema). Lee credenciales de vault.decrypted_secrets. '
  'No-op si faltan o si http_post falla — nunca bloquea ni lanza. '
  'Fix 0075: corrige schema extensions -> net (la función no existía en '
  'extensions).';
