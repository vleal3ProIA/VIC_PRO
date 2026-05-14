-- ============================================================================
-- 0005 · Roles de usuario (admin / user)
-- ----------------------------------------------------------------------------
-- Añade `role` a `public.profiles`. Valores en BD: 'admin' | 'user'.
-- ('guest' es un estado de la app — sin sesión — no se guarda en BD.)
--
-- Seguridad — evitar escalada de privilegios:
--   La policy `profiles_update_own` (migración 0001) deja al usuario
--   actualizar SU fila. Sin protección, podría ponerse `role = 'admin'`.
--   Por eso añadimos un trigger que, en cada UPDATE, si quien edita NO es
--   admin, fuerza `role` a su valor anterior. Solo un admin puede cambiar
--   roles (vía SQL o una futura pantalla de administración).
--
-- Aplicar:
--   - Dashboard: SQL Editor → New query → pegar este archivo → Run.
--   - CLI:       supabase db push
-- ============================================================================

-- 1) Columna role ------------------------------------------------------------
alter table public.profiles
  add column if not exists role text not null default 'user'
  check (role in ('admin', 'user'));

create index if not exists profiles_role_idx on public.profiles (role);

-- 2) Helper: ¿el usuario actual es admin? ------------------------------------
-- SECURITY DEFINER para poder leer profiles sin chocar con RLS, y estable
-- para que el planner lo cachee dentro de la misma query.
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- 3) Trigger anti-escalada de privilegios ------------------------------------
create or replace function public.prevent_role_self_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Si cambia el `role`:
  --   - `auth.uid() is null`  → la edición viene de la service_role / SQL
  --     Editor / admin API (un contexto de confianza): se permite.
  --   - usuario autenticado    → solo se permite si es admin; si no, se
  --     revierte silenciosamente al valor anterior.
  if new.role is distinct from old.role
     and auth.uid() is not null
     and not public.is_admin() then
    new.role := old.role;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_role on public.profiles;
create trigger profiles_guard_role
  before update on public.profiles
  for each row execute function public.prevent_role_self_escalation();

-- ----------------------------------------------------------------------------
-- Para nombrar a un admin (hazlo a mano desde el SQL Editor cuando lo
-- necesites — corre como service_role, así que el trigger lo permite):
--
--   update public.profiles set role = 'admin'
--   where id = (select id from auth.users where email = 'tu@email.com');
-- ----------------------------------------------------------------------------
