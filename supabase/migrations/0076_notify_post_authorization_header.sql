-- ============================================================================
-- 0076 · Fix: notify_super_admins_post añade Authorization header
-- ----------------------------------------------------------------------------
-- Síntoma observado tras 0075: la llamada llega al servidor pero recibe
-- HTTP 403. Causa: la EF `notify-super-admins` se desplegó SIN `--no-verify-jwt`
-- (la primera vez fue manual desde la máquina del admin antes de que el
-- workflow de CI estuviese activo), así que el gateway de Supabase Auth
-- exige un `Authorization: Bearer <jwt>` antes de pasar al handler.
--
-- Fix doble:
--   1. Añadimos `Authorization: Bearer <service_role_jwt>` al http_post
--      para satisfacer al gateway sin importar el estado de verify_jwt.
--   2. Mantenemos `X-Internal-Auth: <service_role_jwt>` para el chequeo
--      interno de la propia EF (defense-in-depth si alguien quitara el
--      gateway en el futuro).
--
-- Esto es robusto: funciona con verify_jwt=true (caso actual) Y con
-- verify_jwt=false (caso ideal tras re-deploy). El service_role JWT es
-- un token de servicio que el gateway acepta como bearer válido.
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

  begin
    perform net.http_post(
      url     := v_endpoint,
      body    := p_payload,
      headers := jsonb_build_object(
        'Content-Type',    'application/json',
        -- (a) Gateway de Supabase Auth: exige Bearer si verify_jwt=true.
        -- service_role JWT es válido y pasa el check del gateway.
        'Authorization',   'Bearer ' || v_jwt,
        -- (b) Validación interna de la propia EF: defense-in-depth, no
        -- depende del gateway. La EF compara este header con su env
        -- SUPABASE_SERVICE_ROLE_KEY y rechaza si no matchea.
        'X-Internal-Auth', v_jwt
      )
    );
    return true;
  exception when others then
    raise warning 'notify_super_admins_post: http_post failed: %', sqlerrm;
    return false;
  end;
end;
$$;

revoke all on function public.notify_super_admins_post(jsonb) from public;

comment on function public.notify_super_admins_post(jsonb) is
  'Internal helper: fire-and-forget HTTP POST a notify-super-admins via '
  'net.http_post. Manda Authorization Bearer + X-Internal-Auth para pasar '
  'tanto el gateway de Supabase Auth (verify_jwt=true) como la validación '
  'interna del handler. Lee credenciales de vault.decrypted_secrets. '
  'No-op si faltan o si http_post falla — nunca bloquea ni lanza.';
