-- ============================================================================
-- 0073 · GDPR export · limpieza extra (avatar URL + tenant personal + metadata)
-- ----------------------------------------------------------------------------
-- Tras 0072 quedaban tres fugas todavía en el export:
--
--   1. `profile.avatar_url` filtraba: (a) el hostname interno del proyecto
--      Supabase (`xxxx.supabase.co` → recon) y (b) el UUID del usuario
--      dentro del path (`/avatars/<uuid>/avatar`). Lo SUSTITUIMOS por
--      `profile.has_custom_avatar` (boolean).
--
--   2. Para el workspace personal auto-creado al registrarse, `tenants[].name`
--      era literalmente el email del usuario (redundante con `account.email`
--      y leak innecesario si el fichero se filtrase). Añadimos `is_personal`
--      y enmascaramos el nombre cuando coincide con el email.
--
--   3. `account.metadata` contenía duplicados de `account.email`,
--      `profile.*` y banderas internas (`email_verified` redundante con
--      `account.email_confirmed_at`, `phone_verified` que no usamos).
--      Eliminado entero.
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

  select email into v_email from auth.users where id = v_uid;

  v_result := jsonb_build_object(
    'export_meta', jsonb_build_object(
      'exported_at',    now(),
      'format_version', 'v3',
      'notice',         'Este export contiene tus datos personales bajo '
                     || 'el Articulo 15 del RGPD (UE) y normativas '
                     || 'equivalentes. No incluye identificadores internos '
                     || 'del sistema. NO compartas este fichero — incluye '
                     || 'tu email y tu historial de actividad.'
    ),

    -- ─── Account (auth.users) — sin metadata (eran duplicados) ───
    'account', (
      select jsonb_build_object(
        'email',              email,
        'created_at',         created_at,
        'last_sign_in_at',    last_sign_in_at,
        'email_confirmed_at', email_confirmed_at,
        'banned_until',       banned_until
      )
      from auth.users
      where id = v_uid
    ),

    -- ─── Profile — avatar_url reemplazado por has_custom_avatar bool ───
    'profile', (
      select jsonb_build_object(
        'username',          username,
        'display_name',      display_name,
        'has_custom_avatar', (avatar_url is not null
                              and length(trim(avatar_url)) > 0),
        'locale',            locale,
        'theme_mode',        theme_mode,
        'created_at',        created_at,
        'updated_at',        updated_at
      )
      from public.profiles
      where id = v_uid
    ),

    -- ─── Tenants: marca el workspace personal y enmascara su name ───
    'tenants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name',        case when t.name = v_email then null else t.name end,
        'is_personal', (t.name = v_email),
        'role',        tm.role,
        'joined_at',   tm.joined_at
      ) order by tm.joined_at)
      from public.tenant_members tm
      join public.tenants t on t.id = tm.tenant_id
      where tm.user_id = v_uid
    ), '[]'::jsonb),

    -- ─── Uploads (sin id/tenant_id; renombrados: kind, uploaded_at) ───
    'uploads', coalesce((
      select jsonb_agg(jsonb_build_object(
        'filename',    filename,
        'kind',        mime_type,
        'size_bytes',  size_bytes,
        'uploaded_at', created_at,
        'deleted_at',  deleted_at
      ) order by created_at desc)
      from public.uploads
      where user_id = v_uid
    ), '[]'::jsonb),

    -- ─── PATs (sin id/prefix) ───
    'personal_access_tokens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name',         name,
        'scopes',       scopes,
        'expires_at',   expires_at,
        'last_used_at', last_used_at,
        'revoked_at',   revoked_at,
        'created_at',   created_at
      ) order by created_at desc)
      from public.personal_access_tokens
      where user_id = v_uid
    ), '[]'::jsonb),

    -- ─── Webhook endpoints (sin id/tenant_id) ───
    'webhook_endpoints', coalesce((
      select jsonb_agg(jsonb_build_object(
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

    -- ─── Audit logs: resumen de logins + eventos no-login con metadata
    --     depurada (sin upload_id/tenant_id/sha256) ───
    'audit_logs', jsonb_build_object(
      'login_summary', coalesce((
        select jsonb_build_object(
          'total',    count(*),
          'first_at', min(occurred_at),
          'last_at',  max(occurred_at)
        )
        from public.audit_logs
        where user_id = v_uid
          and event like 'auth.login.%'
      ), '{}'::jsonb),
      'other_events', coalesce((
        select jsonb_agg(jsonb_build_object(
          'event',       event,
          'metadata',    coalesce(metadata, '{}'::jsonb)
                          - 'upload_id' - 'tenant_id' - 'sha256',
          'occurred_at', occurred_at
        ) order by occurred_at desc)
        from (
          select event, metadata, occurred_at
          from public.audit_logs
          where user_id = v_uid
            and event not like 'auth.login.%'
          order by occurred_at desc
          limit 500
        ) sub
      ), '[]'::jsonb)
    ),

    -- ─── Notifications (sin id/tenant_id) ───
    'notifications', coalesce((
      select jsonb_agg(jsonb_build_object(
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

    -- ─── Emails recibidos (truncado a 1000) ───
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

revoke all on function public.get_my_data_export() from public;
grant execute on function public.get_my_data_export() to authenticated;

comment on function public.get_my_data_export() is
  'GDPR Article 15 (v3): returns a JSONB with the caller''s personal data. '
  'Strips: all internal UUIDs, secrets (token_hash/secret_hash), Storage '
  'paths/avatar URL (replaced with has_custom_avatar bool), tenant name '
  'when it equals user email (auto-personal-workspace marker), and the '
  'auth.users raw_user_meta_data blob (was a duplicate of profile/account). '
  'audit_logs split into login_summary + other_events (max 500); email_log '
  'truncated to 1000 most recent.';
