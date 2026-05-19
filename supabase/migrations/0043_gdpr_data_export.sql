-- ============================================================================
-- 0043 · GDPR data export RPC (Article 15: Right of Access)
-- ----------------------------------------------------------------------------
-- El RGPD (UE) y leyes equivalentes (CCPA, LGPD, etc.) obligan a que
-- el usuario pueda descargar sus datos personales en formato legible
-- maquina. Esta RPC genera un JSONB que recopila TODOS los registros
-- del `auth.uid()` actual repartidos por las tablas del sistema.
--
-- **Por que un solo JSONB y no un ZIP**: la mayoria de SaaS retornan
-- JSON. Los uploads ya estan en Storage con sus URLs publicas/firmadas
-- accesibles desde el listado -- no es necesario empaquetar los bytes.
-- El user puede pedir las URLs y descargar lo que necesite.
--
-- **Que se OMITE** (intencionalmente):
--   - `token_hash` de PATs (hash, no util sin el secret original que
--     ya no se conserva).
--   - `secret_hash` de webhooks (idem).
--   - `path` y `bucket` de uploads (info tecnica de Storage; el user
--     ve sus archivos en /files con URLs firmadas).
--   - Datos sensibles de otros users (joins limitados a su propio
--     auth.uid).
--
-- **Limit**: audit_logs y email_log se truncan a las 1000 entradas mas
-- recientes -- evitar exports gigantes que rompen el browser. El user
-- con > 1000 entradas raras vez necesita el historial completo en un
-- export; si lo necesita, support con admin query.
--
-- **Llamada**:
--   const { data } = await supabase.rpc('get_my_data_export');
--   downloadJson(data, 'gdpr-export-YYYY-MM-DD.json');
--
-- **Tests**: ver SECURITY.md sec. 11. La validacion manual recomendada
-- es ejecutar la RPC con un user de prueba y verificar que el JSONB
-- tiene todas las secciones esperadas.
-- ============================================================================

create or replace function public.get_my_data_export()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_email  text;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- Email del user (vive en auth.users, no podemos joinar directamente
  -- desde el cliente -- aqui SECURITY DEFINER bypassa RLS).
  select email into v_email from auth.users where id = v_uid;

  -- Construimos el JSON anidado seccion por seccion.
  v_result := jsonb_build_object(
    'export_meta', jsonb_build_object(
      'user_id',        v_uid,
      'exported_at',    now(),
      'format_version', 'v1',
      'notice',         'Este export contiene tus datos personales bajo '
                     || 'el Articulo 15 del RGPD (UE) y normativas '
                     || 'equivalentes. NO compartas este fichero -- '
                     || 'incluye tu email y tu historial de actividad.'
    ),

    -- ─── Account (auth.users) ───
    'account', (
      select jsonb_build_object(
        'email',              email,
        'created_at',         created_at,
        'last_sign_in_at',    last_sign_in_at,
        'email_confirmed_at', email_confirmed_at,
        'banned_until',       banned_until,
        'metadata',           raw_user_meta_data
      )
      from auth.users
      where id = v_uid
    ),

    -- ─── Profile (public.profiles) ───
    'profile', (
      select jsonb_build_object(
        'username',     username,
        'display_name', display_name,
        'avatar_url',   avatar_url,
        'locale',       locale,
        'theme_mode',   theme_mode,
        'created_at',   created_at,
        'updated_at',   updated_at
      )
      from public.profiles
      where id = v_uid
    ),

    -- ─── Tenants (memberships) ───
    'tenants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tenant_id', t.id,
        'tenant_name', t.name,
        'tenant_slug', t.slug,
        'role',      tm.role,
        'joined_at', tm.joined_at
      ) order by tm.joined_at)
      from public.tenant_members tm
      join public.tenants t on t.id = tm.tenant_id
      where tm.user_id = v_uid
    ), '[]'::jsonb),

    -- ─── Uploads (sin path/bucket, son info tecnica) ───
    'uploads', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',         id,
        'filename',   filename,
        'mime_type',  mime_type,
        'size_bytes', size_bytes,
        'tenant_id',  tenant_id,
        'created_at', created_at,
        'deleted_at', deleted_at
      ) order by created_at desc)
      from public.uploads
      where user_id = v_uid
    ), '[]'::jsonb),

    -- ─── Personal Access Tokens (sin token_hash) ───
    'personal_access_tokens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',           id,
        'name',         name,
        'prefix',       prefix,
        'scopes',       scopes,
        'expires_at',   expires_at,
        'last_used_at', last_used_at,
        'revoked_at',   revoked_at,
        'created_at',   created_at
      ) order by created_at desc)
      from public.personal_access_tokens
      where user_id = v_uid
    ), '[]'::jsonb),

    -- ─── Webhook endpoints (sin secret_hash) ───
    'webhook_endpoints', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',                   id,
        'tenant_id',            tenant_id,
        'url',                  url,
        'description',          description,
        'events',               events,
        'active',               active,
        'consecutive_failures', consecutive_failures,
        'disabled_reason',      disabled_reason,
        'created_at',           created_at
      ) order by created_at desc)
      from public.webhook_endpoints
      where user_id = v_uid
    ), '[]'::jsonb),

    -- ─── Audit logs (truncado a 1000 mas recientes) ───
    'audit_logs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'event',       event,
        'metadata',    metadata,
        'occurred_at', occurred_at
      ) order by occurred_at desc)
      from (
        select event, metadata, occurred_at
        from public.audit_logs
        where user_id = v_uid
        order by occurred_at desc
        limit 1000
      ) sub
    ), '[]'::jsonb),

    -- ─── Notifications recibidas ───
    'notifications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',         id,
        'tenant_id',  tenant_id,
        'type',       type,
        'category',   category,
        'title',      title,
        'body',       body,
        'action_url', action_url,
        'read_at',    read_at,
        'created_at', created_at
      ) order by created_at desc)
      from public.notifications
      where user_id = v_uid
    ), '[]'::jsonb),

    -- ─── Emails enviados a este user (truncado a 1000) ───
    -- Filtramos por to_user_id (FK conocida). NO usamos to_email
    -- (puede ser email de un user borrado o de un invitado externo,
    -- no necesariamente este user).
    'emails_received', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type',       type,
        'subject',    subject,
        'status',     status,
        'locale',     locale,
        'sent_at',    sent_at,
        'created_at', created_at
      ) order by created_at desc)
      from (
        select type, subject, status, locale, sent_at, created_at
        from public.email_log
        where to_user_id = v_uid
        order by created_at desc
        limit 1000
      ) sub
    ), '[]'::jsonb)
  );

  return v_result;
end;
$$;

-- La RPC se invoca con el JWT del user -- service_role/anon no la
-- necesitan, no debemos exponerla mas alla de authenticated.
revoke all on function public.get_my_data_export() from public;
grant execute on function public.get_my_data_export() to authenticated;

comment on function public.get_my_data_export() is
  'GDPR Article 15: returns a JSONB with ALL data we hold about the '
  'caller (auth.uid()). Strips secrets (token_hash, secret_hash) and '
  'technical metadata (Storage paths). audit_logs and email_log are '
  'truncated to the 1000 most recent entries -- contact support if '
  'you need the full history.';
