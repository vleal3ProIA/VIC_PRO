-- ============================================================================
-- 0022 · Onboarding wizard del usuario
-- ----------------------------------------------------------------------------
-- Estado de onboarding por user: `onboarding_completed_at` en
-- `profiles`. NULL = nunca completó el wizard; tras llegar al último
-- paso pasa a `now()`.
--
-- El guard del router lee esta columna: si user logged-in y onboarding
-- != completado → redirige a /onboarding. El user puede saltarlo entero
-- con un botón "Skip" que también marca completed.
--
-- Por qué una columna en profiles y no una tabla `user_onboarding`
-- separada con N pasos: el wizard inicial es genérico y tiene flujo
-- lineal (no se vuelve a empezar). Si el dia de mañana queremos
-- onboarding multi-track (uno por feature), creamos `user_onboarding
-- (user_id, track, completed_at)`.
-- ============================================================================

alter table public.profiles
  add column if not exists onboarding_completed_at timestamptz;

-- Index parcial para encontrar rápidamente usuarios SIN onboarding —
-- usado por jobs futuros (recordatorios por email, etc.). Como la
-- mayoría de usuarios pasados el primer día tendrán `completed_at`
-- non-null, el index es muy compacto.
create index if not exists profiles_pending_onboarding_idx
  on public.profiles(id)
  where onboarding_completed_at is null;

-- RPC para marcar el onboarding como completado. SECURITY DEFINER +
-- check de auth.uid() asegura que solo el dueño puede tocar su propia
-- fila. Idempotente: si ya estaba completado, no toca el timestamp.
create or replace function public.mark_onboarding_completed()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz;
begin
  -- Devolvemos el timestamp resultante (existente o el nuevo).
  update public.profiles
    set onboarding_completed_at = coalesce(onboarding_completed_at, now())
    where id = auth.uid()
    returning onboarding_completed_at into v_now;
  return v_now;
end;
$$;

revoke all on function public.mark_onboarding_completed() from public;
grant execute on function public.mark_onboarding_completed() to authenticated;

comment on column public.profiles.onboarding_completed_at is
  'Timestamp en que el user completó (o saltó) el wizard de onboarding inicial. NULL = pendiente.';
comment on function public.mark_onboarding_completed() is
  'Marca el onboarding del user actual como completado. Idempotente. Devuelve el timestamp resultante.';
