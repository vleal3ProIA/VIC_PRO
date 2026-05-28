-- ============================================================================
-- 0072 · GDPR data export cleanup (v2 — user-friendly + PII minimisation)
-- ----------------------------------------------------------------------------
-- Reescritura de `get_my_data_export()` (originalmente en 0043) tras una
-- revision UX/seguridad:
--
--   1. **Privacidad por minimizacion**: eliminamos identificadores
--      internos (UUIDs de user/tenant/upload, slugs de tenant). Si el
--      usuario comparte el fichero (mail, soporte) no expone superficie
--      de reconocimiento del backend ni convenciones de nombrado interno.
--      Datos personales reales se mantienen (email, perfil, archivos).
--   2. **Ruido fuera**: el historial de `auth.login.*` puede tener cientos
--      de entradas casi identicas. Lo agregamos a un `login_summary`
--      `{total, first_at, last_at}` y dejamos los `other_events`
--      (limit 500) que sí son interesantes (cambios MFA, 2FA, deletes…).
--   3. **Hashes internos** (`metadata.sha256`, PAT `prefix`) — son
--      identificadores tecnicos de integridad/lookup, NO datos
--      personales. Se eliminan.
--   4. **Renombrado plain-English** se hace **client-side** (PDF/labels).
--      El JSON mantiene snake_case mas razonable para portabilidad
--      (`uploaded_at`, `kind`).
--
-- Compatibilidad: el PDF client-side espera v2; el JSON lo lleva en
-- `export_meta.format_version`.
-- ============================================================================

create or replace function public.get_my_data_export()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  v_result := jsonb_build_object(
    'export_meta', jsonb_build_object(
      'exported_at',    now(),
      'format_version', 'v2',
      'notice',         'Este export contiene tus datos personales bajo '
                     || 'el Articulo 15 del RGPD (UE) y normativas '
                     || 'equivalentes. No incluye identificadores '
                     || 'internos del sistema. NO compartas este '
                     || 'fichero — incluye tu email y tu historial '
                     || 'de actividad.'
    ),

    -- ─── Account (auth.users) ───
    -- Strip `sub` from metadata (es el user id duplicado).
    'account', (
      select jsonb_build_object(
        'email',              email,
        'created_at',         created_at,
        'last_sign_in_at',    last_sign_in_at,
        'email_confirmed_at', email_confirmed_at,
        'banned_until',       banned_until,
        'metadata',           coalesce(raw_user_meta_data, '{}'::jsonb)
                              - 'sub'
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

    -- ─── Tenants (memberships) sin tenant_id ni tenant_slug ───
    'tenants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name',      t.name,
        'role',      tm.role,
        'joined_at', tm.joined_at
      ) order by tm.joined_at)
      from public.tenant_members tm
      join public.tenants t on t.id = tm.tenant_id
      where tm.user_id = v_uid
    ), '[]'::jsonb),

    -- ─── Uploads (sin id, sin tenant_id; renombrado human-friendly) ───
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

    -- ─── Personal Access Tokens (sin id, sin prefix) ───
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

    -- ─── Webhook endpoints (sin id, sin tenant_id) ───
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

    -- ─── Audit logs: agregado de logins + otros eventos ───
    --
    -- `auth.login.*` (success, failure, password_invalid…) genera mucho
    -- ruido — colapsamos a count/first/last. El resto va completo (max
    -- 500), strippeando ids internos del metadata.
    'audit_logs', jsonb_build_object(
      'login_summary', (
        select jsonb_build_object(
          'total',    coalesce(count(*), 0),
          'first_at', min(occurred_at),
          'last_at',  max(occurred_at)
        )
        from public.audit_logs
        where user_id = v_uid
          and event like 'auth.login.%'
      ),
      'other_events', coalesce((
        select jsonb_agg(jsonb_build_object(
          'event',       event,
          'metadata',    (coalesce(metadata, '{}'::jsonb)
                            - 'upload_id'
                            - 'tenant_id'
                            - 'sha256'),
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

    -- ─── Notifications recibidas (sin id, sin tenant_id) ───
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
  'GDPR Article 15 (v2): user-facing JSON with ALL personal data of '
  'auth.uid(). Excludes internal UUIDs (user/tenant/upload), tenant '
  'slugs and internal integrity hashes. auth.login.* events are '
  'aggregated into a summary; other events are capped at 500 most '
  'recent. email_log capped at 1000.';
