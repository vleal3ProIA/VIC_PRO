-- ============================================================================
-- 0003 · Códigos de recuperación de MFA
-- ----------------------------------------------------------------------------
-- Tabla donde se guardan los códigos de recuperación de MFA, SOLO como hash
-- (SHA-256). El usuario los ve una única vez al generarlos.
--
-- Se generan y se consumen exclusivamente desde la Edge Function
-- `mfa-recovery` (con la service_role key). El usuario solo puede LEER sus
-- propias filas — útil para mostrar "te quedan N códigos" sin exponer nada
-- sensible (solo hashes).
--
-- Al borrar el usuario de auth.users, sus códigos se van por ON DELETE CASCADE.
--
-- Aplicar:
--   - Dashboard: SQL Editor → New query → pegar este archivo → Run.
--   - CLI:       supabase db push
-- ============================================================================

create table if not exists public.mfa_recovery_codes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  code_hash   text not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

comment on table public.mfa_recovery_codes is
  'Hashes (SHA-256) de los códigos de recuperación de MFA. Generados y '
  'consumidos solo por la Edge Function mfa-recovery.';

create index if not exists mfa_recovery_codes_user_idx
  on public.mfa_recovery_codes (user_id);

-- Row Level Security ---------------------------------------------------------
alter table public.mfa_recovery_codes enable row level security;

-- El usuario puede LEER sus propios códigos (para contar los no usados).
-- No exponemos insert/update/delete: eso lo hace la Edge Function con la
-- service_role key (que se salta RLS).
drop policy if exists "mfa_recovery_select_own" on public.mfa_recovery_codes;
create policy "mfa_recovery_select_own"
  on public.mfa_recovery_codes for select
  using (auth.uid() = user_id);
