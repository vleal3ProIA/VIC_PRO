-- ============================================================================
-- 0083 · Error reports: capability gate + trigger AFTER INSERT
-- ----------------------------------------------------------------------------
-- Cierra el pipeline ERROR_REPORTING (0082) con dos piezas:
--
--   1) Anyade `view_error_reports` a la whitelist de capabilities. La
--      tabla `admin_capabilities` tiene un CHECK constraint duro
--      (ver 0044 + 0050) y para extenderlo hay que DROP+ADD. Lista
--      completa al final con la nueva entrada.
--
--   2) Endurece la RLS de `public.error_reports`: solo super-admin O
--      admin con capability `view_error_reports` puede leer / actualizar
--      / borrar. La 0082 dejaba el gate en `is_admin()` (cualquier
--      admin) -- ahora hay que tener la capability explicita (el super
--      la hereda automaticamente via `has_capability`).
--
--   3) Trigger AFTER INSERT en `error_reports` que dispara la EF
--      `notify-error-report` via `pg_net.http_post`. Mismo patron que
--      0080 (`fire_audit_digest_trg`): vault secrets
--      `supabase_project_url` + `supabase_service_role_key`,
--      fire-and-forget, Authorization Bearer + X-Internal-Auth.
-- ============================================================================

-- ─────────────── 1) Whitelist de capabilities ───────────────
-- Mismo idiom que 0050: drop + add con TODAS las entradas vigentes.
alter table public.admin_capabilities
  drop constraint if exists admin_capabilities_capability_check;
alter table public.admin_capabilities
  add constraint admin_capabilities_capability_check
  check (capability in (
    'manage_users',
    'manage_plans',
    'manage_coupons',
    'manage_branding',
    'manage_app_branding',
    'manage_broadcasts',
    'manage_changelog',
    'manage_flags',
    'manage_incidents',
    'view_email_log',
    'view_metrics',
    'manage_trash',
    'run_audits',
    'manage_ai',
    'view_ai_content',
    'view_error_reports'
  ));

-- ─────────────── 2) RLS endurecida en error_reports ───────────────
-- 0082 ya tiene SELECT/UPDATE/DELETE para `is_admin()`. Sustituimos por
-- `is_super_admin() OR has_capability('view_error_reports')`. Asi solo
-- los admins con la capability explicita ven los reports. El super tiene
-- todas las capabilities automaticamente, sigue viendo todo.

drop policy if exists "error_reports_admin_read"      on public.error_reports;
drop policy if exists "error_reports_admin_update"    on public.error_reports;
drop policy if exists "error_reports_admin_delete"    on public.error_reports;
-- Tambien drop las nuevas si quedaron de un intento parcial previo
-- (re-run idempotente -- pasara si un push anterior fallo a medias).
drop policy if exists "error_reports_read_with_cap"   on public.error_reports;
drop policy if exists "error_reports_update_with_cap" on public.error_reports;
drop policy if exists "error_reports_delete_with_cap" on public.error_reports;

create policy "error_reports_read_with_cap"
  on public.error_reports for select to authenticated
  using (
    public.is_super_admin()
    or public.has_capability('view_error_reports')
  );

create policy "error_reports_update_with_cap"
  on public.error_reports for update to authenticated
  using (
    public.is_super_admin()
    or public.has_capability('view_error_reports')
  )
  with check (
    public.is_super_admin()
    or public.has_capability('view_error_reports')
  );

create policy "error_reports_delete_with_cap"
  on public.error_reports for delete to authenticated
  using (
    public.is_super_admin()
    or public.has_capability('view_error_reports')
  );

-- INSERT sigue SIN policy => bloqueado para `authenticated`. Solo
-- service_role inserta (las Edge Functions via `error_reporter.ts`).

-- ─────────────── 3) Trigger AFTER INSERT -> EF notify-error-report ───────────
-- Patron identico a 0080. Lee vault secrets, fire-and-forget. Si algo
-- falla solo emite warning -- nunca bloquea el INSERT del report.

create or replace function public.fire_error_report_notify()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $$
declare
  v_url       text;
  v_jwt       text;
  v_endpoint  text;
begin
  -- Vault: project_url + service_role_key.
  begin
    select decrypted_secret into v_url
    from vault.decrypted_secrets
    where name = 'supabase_project_url'
    limit 1;
  exception when others then
    raise warning 'fire_error_report_notify: vault read project_url failed: %', sqlerrm;
    return new;
  end;

  begin
    select decrypted_secret into v_jwt
    from vault.decrypted_secrets
    where name = 'supabase_service_role_key'
    limit 1;
  exception when others then
    raise warning 'fire_error_report_notify: vault read service_role_key failed: %', sqlerrm;
    return new;
  end;

  if v_url is null or v_url = '' then
    raise warning 'fire_error_report_notify: missing supabase_project_url in vault';
    return new;
  end if;
  if v_jwt is null or v_jwt = '' then
    raise warning 'fire_error_report_notify: missing supabase_service_role_key in vault';
    return new;
  end if;

  v_endpoint := rtrim(v_url, '/') || '/functions/v1/notify-error-report';

  -- Fire-and-forget. Nunca bloqueamos el INSERT original.
  begin
    perform net.http_post(
      url     := v_endpoint,
      body    := jsonb_build_object('error_report_id', new.id),
      headers := jsonb_build_object(
        'Content-Type',    'application/json',
        -- (a) gateway Supabase Auth (verify_jwt=true tolerante)
        'Authorization',   'Bearer ' || v_jwt,
        -- (b) chequeo interno EF (defense-in-depth)
        'X-Internal-Auth', v_jwt
      )
    );
  exception when others then
    raise warning 'fire_error_report_notify: net.http_post failed: %', sqlerrm;
  end;

  return new;
end;
$$;

revoke all on function public.fire_error_report_notify() from public;

comment on function public.fire_error_report_notify() is
  'AFTER INSERT trigger handler on error_reports. Fires notify-error-report '
  'EF via pg_net.http_post. Reads vault secrets supabase_project_url + '
  'supabase_service_role_key. Fire-and-forget; never blocks the INSERT.';

drop trigger if exists fire_error_report_notify_trg on public.error_reports;
create trigger fire_error_report_notify_trg
  after insert on public.error_reports
  for each row
  execute function public.fire_error_report_notify();
