-- ============================================================================
-- 0008 · Audit log (registro de actividad del usuario)
-- ----------------------------------------------------------------------------
-- Almacena eventos relevantes de seguridad del usuario para "Actividad
-- reciente" en Ajustes y para auditoría futura. Es **append-only**: el
-- propio usuario solo puede insertar entradas suyas y leer las suyas —
-- nadie puede actualizar ni borrar (excepto el cascade al borrar la cuenta).
--
-- `event` es un string con namespace puntuado:
--   auth.login.password, auth.login.oauth, auth.login.passkey,
--   auth.login.mfa_recovery, auth.logout,
--   account.password_changed, account.email_change_requested,
--   mfa.enabled, mfa.disabled,
--   passkey.added, passkey.removed
--
-- La app define las constantes en `lib/features/audit/domain/audit_events.dart`.
-- ============================================================================

create table if not exists public.audit_logs (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  event        text not null,
  metadata     jsonb,
  occurred_at  timestamptz not null default now()
);

create index if not exists audit_logs_user_time_idx
  on public.audit_logs (user_id, occurred_at desc);

alter table public.audit_logs enable row level security;

-- El usuario lee SUS propios eventos (para la pantalla "Actividad reciente").
drop policy if exists "audit_logs_select_own" on public.audit_logs;
create policy "audit_logs_select_own"
  on public.audit_logs for select
  using (auth.uid() = user_id);

-- Inserta SOLO sus propias filas, y solo el usuario autenticado (rol
-- `authenticated`). Las Edge Functions con service_role se saltan RLS.
drop policy if exists "audit_logs_insert_own" on public.audit_logs;
create policy "audit_logs_insert_own"
  on public.audit_logs for insert
  to authenticated
  with check (auth.uid() = user_id);

-- No exponemos update ni delete: el log es append-only. Si alguna vez se
-- necesita purgar por GDPR, se hace borrando la cuenta del usuario
-- (cascade) o vía un job administrativo con service_role.
