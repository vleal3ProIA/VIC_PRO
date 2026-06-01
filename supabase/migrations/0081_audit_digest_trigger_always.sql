-- ============================================================================
-- 0081 · Audit digest trigger: relax condition to fire on ALL completed audits
-- ----------------------------------------------------------------------------
-- En 0080 el trigger solo disparaba si `triggered_by IS NULL` (audit
-- automatico via cron). La intencion era no spamear al admin que lanza
-- manualmente desde la UI.
--
-- En la practica: hace falta que dispare TAMBIEN para manuales porque:
--   1. El admin que lanza desde la UI quiere el digest por email/in-app
--      (no solo viendo la pagina del report).
--   2. El RESTO de admins se enteran via el digest -- ahora mismo solo
--      ve el resultado quien lo lanzo manualmente.
--   3. Los runs disparados desde GitHub Actions con la API de Supabase
--      Studio (re-run de un workflow anterior) podrian ser detectados
--      como "manual" segun como Auth los etiquete.
--
-- Decision: el trigger dispara para CUALQUIER transition a 'completed'.
-- La EF `send-audit-digest` igualmente se de-duplica por id de
-- recipient en el INSERT a notifications (si el mismo audit_id le
-- entrara dos veces, mandaria dos digests -- que es deseable: cada
-- run del audit merece su email/notif).
--
-- Si en el futuro vuelve a hacer falta filtrar por automatic-vs-manual,
-- mover el filtro a la propia EF (mas facil de iterar que SQL).
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
  -- Solo audits que ACABAN de completarse (transition real).
  -- Sin filtro por triggered_by -- todos disparan digest.
  if old.status = 'completed' or new.status <> 'completed' then
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
        'Authorization',   'Bearer ' || v_jwt,
        'X-Internal-Auth', v_jwt
      )
    );
  exception when others then
    raise warning 'fire_audit_digest: net.http_post failed: %', sqlerrm;
  end;

  return new;
end;
$$;

comment on function public.fire_audit_digest() is
  'AFTER UPDATE trigger handler on audit_reports. Fires send-audit-digest '
  'EF when any audit transitions to status=''completed'' (no triggered_by '
  'filter -- automatic AND manual both notify admins). Reads vault secrets '
  'supabase_project_url + supabase_service_role_key (same as 0076). '
  'Fire-and-forget; never blocks the UPDATE.';

-- Trigger ya existe desde 0080 -- solo hace falta reemplazar la funcion.
-- Por seguridad lo recreamos por si la primera migration no se aplico
-- limpia.
drop trigger if exists fire_audit_digest_trg on public.audit_reports;
create trigger fire_audit_digest_trg
  after update of status on public.audit_reports
  for each row
  execute function public.fire_audit_digest();
