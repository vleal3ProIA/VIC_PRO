-- ============================================================================
-- 0026 · Changelog (What's new)
-- ----------------------------------------------------------------------------
-- Sistema para que los admins publiquen entradas tipo "What's new":
-- nuevas features, mejoras, fixes. Visible desde el menu de ayuda (?)
-- en el AppBar. Cuando hay entradas nuevas desde la ultima visita del
-- user, el icono muestra un badge rojo.
--
-- **Modelo**:
--   - `version`        : etiqueta libre ("2026.05", "v3.2.1", null). NO
--                        es semver, solo display.
--   - `title`          : titular obligatorio (max 200).
--   - `body`           : cuerpo en Markdown ligero (max 5000). El cliente
--                        renderiza con `markdown` package.
--   - `category`       : enum 'feature' | 'improvement' | 'fix' | 'security'.
--                        La UI pinta un chip por color.
--   - `published_at`   : NULL = borrador, no visible para users normales.
--                        Set = visible para todos. Sirve tambien como
--                        sort key (newest first).
--
-- **Indicador "What's new"** del menu de ayuda:
--   - Cada user tiene `changelog_seen_at` en su profile.
--   - Badge visible si existe entrada con `published_at > changelog_seen_at`
--     (o si nunca lo abrio).
--   - RPC `mark_changelog_seen()` lo actualiza a now() cuando abre la
--     pagina /changelog.
-- ============================================================================

create table if not exists public.changelog_entries (
  id            uuid primary key default gen_random_uuid(),
  version       text check (version is null or char_length(version) between 1 and 40),
  title         text not null check (char_length(title) between 1 and 200),
  body          text not null check (char_length(body) between 1 and 5000),
  category      text not null default 'feature'
                check (category in ('feature', 'improvement', 'fix', 'security')),
  published_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Query caliente: entradas publicadas ordenadas por fecha desc para
-- la pagina /changelog y el chequeo del badge.
create index if not exists changelog_published_idx
  on public.changelog_entries(published_at desc)
  where published_at is not null;

-- Trigger touch updated_at.
create or replace function public.changelog_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists changelog_touch on public.changelog_entries;
create trigger changelog_touch
  before update on public.changelog_entries
  for each row execute function public.changelog_touch_updated_at();

-- ─────────────────────────── RLS ───────────────────────────
-- Lectura: cualquier usuario autenticado puede ver entradas publicadas.
-- CRUD (incluido ver borradores): solo admin.

alter table public.changelog_entries enable row level security;

drop policy if exists "changelog_select_published" on public.changelog_entries;
create policy "changelog_select_published"
  on public.changelog_entries for select
  using (
    published_at is not null
    or public.is_admin()
  );

drop policy if exists "changelog_admin_insert" on public.changelog_entries;
create policy "changelog_admin_insert"
  on public.changelog_entries for insert
  with check (public.is_admin());

drop policy if exists "changelog_admin_update" on public.changelog_entries;
create policy "changelog_admin_update"
  on public.changelog_entries for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "changelog_admin_delete" on public.changelog_entries;
create policy "changelog_admin_delete"
  on public.changelog_entries for delete
  using (public.is_admin());

-- ─────────────────── Profile: changelog_seen_at ───────────────────
-- Timestamp de la ultima vez que el user abrio /changelog. Sirve para
-- el badge "what's new" del menu de ayuda. Anadimos la columna a
-- profiles porque es 1:1 con user_id, no merece tabla separada.

alter table public.profiles
  add column if not exists changelog_seen_at timestamptz;

-- ─────────────────── RPC: mark_changelog_seen ───────────────────
-- Llamada al entrar a /changelog. Actualiza changelog_seen_at = now()
-- para que el badge desaparezca.

create or replace function public.mark_changelog_seen()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
    set changelog_seen_at = now()
    where id = auth.uid();
end;
$$;

revoke all on function public.mark_changelog_seen() from public;
grant execute on function public.mark_changelog_seen() to authenticated;

-- ─────────────────── RPC: has_unseen_changelog ───────────────────
-- Devuelve true si hay alguna entrada publicada con published_at
-- posterior al changelog_seen_at del user (o si nunca lo abrio).
-- Lo llama el AppBar al cargar para decidir si pintar el badge rojo.
-- Es barato: el indice parcial sirve directamente.

create or replace function public.has_unseen_changelog()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seen timestamptz;
  v_exists boolean;
begin
  select changelog_seen_at into v_seen
    from public.profiles
    where id = auth.uid();

  -- Si nunca lo abrio (v_seen es null), basta con que exista
  -- cualquier entrada publicada.
  select exists(
    select 1 from public.changelog_entries
    where published_at is not null
      and (v_seen is null or published_at > v_seen)
  ) into v_exists;

  return coalesce(v_exists, false);
end;
$$;

revoke all on function public.has_unseen_changelog() from public;
grant execute on function public.has_unseen_changelog() to authenticated;
