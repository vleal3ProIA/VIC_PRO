-- ============================================================================
-- 0001 · Initial schema: profiles + RLS + trigger on auth.users
-- ----------------------------------------------------------------------------
-- Crea la tabla `public.profiles` con preferencias por usuario (idioma y
-- tema), conectada 1:1 con `auth.users`. Habilita Row Level Security y
-- registra un trigger que crea automáticamente el perfil al firmar un
-- usuario nuevo.
--
-- Aplicar:
--   - Vía dashboard: SQL Editor → New query → pegar este archivo → Run.
--   - Vía CLI:       supabase db push
-- ============================================================================

-- 1) Tabla profiles ---------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text unique,
  display_name  text,
  avatar_url    text,
  locale        text not null default 'en'
                check (locale in ('es','en','de','fr','it','pt','ru','uk')),
  theme_mode    text not null default 'system'
                check (theme_mode in ('system','light','dark')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.profiles is
  'User-facing profile + UI preferences (locale, theme). One row per auth.users.';

-- 2) updated_at automático --------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- 3) Trigger: crear profile al firmar un usuario ----------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'username')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4) Row Level Security -----------------------------------------------------
alter table public.profiles enable row level security;

-- Cada usuario puede leer su propio profile
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

-- Cada usuario puede actualizar su propio profile
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- El insert lo hace el trigger SECURITY DEFINER, no usuarios anónimos.
-- No exponemos delete: el cascade desde auth.users se ocupa cuando se borra
-- una cuenta.

-- 5) Índices útiles ---------------------------------------------------------
create index if not exists profiles_username_idx on public.profiles (username);
