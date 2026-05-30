-- ============================================================================
-- 0080 · Audit digest trigger
-- ----------------------------------------------------------------------------
-- AFTER UPDATE en audit_reports. Solo dispara cuando:
--   - status pasa a 'completed' (transición real, no UPDATE idempotente).
--   - triggered_by IS NULL (= audit AUTOMATICO via cron, no manual desde
--     la UI de un admin humano).
--
-- Si fue lanzado por un admin desde /admin/audit, ese admin ya esta
-- viendo la pagina del report y no necesita digest por email/in-app.
--
-- Cuando dispara: invoca pg_net.http_post a la EF `send-audit-digest`
-- pasando solo `audit_id` en el body. La EF se encarga de leer el
-- report, calcular el resumen y notificar al super-admin + todos los
-- admins regulares (de-duplicados por id).
--
-- Vault names: `supabase_project_url` y `supabase_service_role_key`
-- (mismos que 0076_notify_post_authorization_header.sql -- VERIFICADO).
-- Si faltan -> warning silencioso, no se bloquea el UPDATE original.
--
-- Headers: igual que 0076:
--   - Authorization: Bearer <jwt>  -> pasa el gateway de Supabase Auth
--                                     (defensive: aun si verify_jwt=true
--                                     por algun re-deploy accidental).
--   - X-Internal-Auth: <jwt>       -> chequeo interno de la propia EF
--                                     (defense-in-depth).
-- ============================================================================

create or replace function public.fire_audit_digest()
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
  -- Solo audits AUTOMATICOS que acaban de completarse.
  -- old.status != 'completed' AND new.status = 'completed' AND
  -- triggered_by IS NULL.
  if old.status = 'completed'
     or new.status <> 'completed'
     or new.triggered_by is not null then
    return new;
  end if;

  -- Vault: project_url + service_role_key. Misma convencion que 0076.
  begin
    select decrypted_secret into v_url
    from vault.decrypted_secrets
    where name = 'supabase_project_url'
    limit 1;
  exception when others then
    raise warning 'fire_audit_digest: vault read project_url failed: %', sqlerrm;
    return new;
  end;

  begin
    select decrypted_secret into v_jwt
    from vault.decrypted_secrets
    where name = 'supabase_service_role_key'
    limit 1;
  exception when others then
    raise warning 'fire_audit_digest: vault read service_role_key failed: %', sqlerrm;
    return new;
  end;

  if v_url is null or v_url = '' then
    raise warning 'fire_audit_digest: missing supabase_project_url in vault';
    return new;
  end if;
  if v_jwt is null or v_jwt = '' then
    raise warning 'fire_audit_digest: missing supabase_service_role_key in vault';
    return new;
  end if;

  v_endpoint := rtrim(v_url, '/') || '/functions/v1/send-audit-digest';

  -- Fire-and-forget. Si http_post falla, log warning y seguimos --
  -- nunca bloqueamos el UPDATE original del audit.
  begin
    perform net.http_post(
      url     := v_endpoint,
      body    := jsonb_build_object('audit_id', new.id),
      headers := jsonb_build_object(
        'Content-Type',    'application/json',
        -- (a) gateway Supabase Auth (verify_jwt=true tolerante)
        'Authorization',   'Bearer ' || v_jwt,
        -- (b) chequeo interno EF (defense-in-depth)
        'X-Internal-Auth', v_jwt
      )
    );
  exception when others then
    raise warning 'fire_audit_digest: net.http_post failed: %', sqlerrm;
  end;

  return new;
end;
$$;

revoke all on function public.fire_audit_digest() from public;

comment on function public.fire_audit_digest() is
  'AFTER UPDATE trigger handler on audit_reports. Fires send-audit-digest '
  'EF when an AUTOMATIC audit (triggered_by IS NULL) transitions to '
  'status=''completed''. Reads vault secrets supabase_project_url + '
  'supabase_service_role_key (same as 0076). Fire-and-forget; never '
  'blocks the UPDATE.';

drop trigger if exists fire_audit_digest_trg on public.audit_reports;
create trigger fire_audit_digest_trg
  after update of status on public.audit_reports
  for each row
  execute function public.fire_audit_digest();
