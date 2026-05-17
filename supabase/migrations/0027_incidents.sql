-- ============================================================================
-- 0027 · Incidents / Status page
-- ----------------------------------------------------------------------------
-- Sistema de incident reporting estilo status.stripe.com /
-- status.github.com. Sirve dos propositos:
--   1) Una pagina publica `/status` (SIN auth) que muestra el estado
--      operativo de la app + lista de incidentes abiertos + historico.
--      Es señal de confianza para evaluadores que aun no se han
--      registrado.
--   2) Un banner DENTRO de la app (PrivateShell) que se pinta arriba
--      del todo cuando hay incidente activo de severidad >= major.
--      Canal critico para avisar de caidas y de ventanas de mantenimiento.
--
-- **Modelo**:
--   - `title`         : titular ("Login outage in EU region")
--   - `body`          : descripcion / progress updates (max 5000)
--   - `status`        : enum 4-estados estilo Atlassian Statuspage:
--                       'investigating' | 'identified' | 'monitoring' | 'resolved'
--   - `severity`      : 'minor' | 'major' | 'critical' | 'maintenance'
--                       (banner in-app solo si major/critical/maintenance
--                       y status != resolved)
--   - `components`    : text[] de servicios afectados ('api', 'auth',
--                       'billing', 'storage', 'webhooks'...). Display only.
--   - `started_at`    : cuando empezo (timestamp del incidente, NO de
--                       cuando se creo el row)
--   - `resolved_at`   : cuando se cerro; NULL = todavia activo
--   - `published`     : el admin puede dejarlo en borrador antes de
--                       publicarlo. Solo si published=true se ve en /status.
--
-- **Overall status** del badge global se calcula client-side a partir
-- de los incidentes activos:
--   - cualquier 'critical' activo  -> 'major_outage'
--   - cualquier 'major' activo     -> 'partial_outage'
--   - cualquier 'maintenance'      -> 'maintenance'
--   - cualquier 'minor' activo     -> 'degraded'
--   - ninguno                       -> 'operational'
-- ============================================================================

create table if not exists public.incidents (
  id            uuid primary key default gen_random_uuid(),
  title         text not null check (char_length(title) between 1 and 200),
  body          text not null default '' check (char_length(body) <= 5000),
  status        text not null default 'investigating'
                check (status in ('investigating', 'identified', 'monitoring', 'resolved')),
  severity      text not null default 'minor'
                check (severity in ('minor', 'major', 'critical', 'maintenance')),
  components    text[] not null default '{}'::text[],
  started_at    timestamptz not null default now(),
  resolved_at   timestamptz,
  published     boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Query caliente del /status page y del banner: activos publicados
-- ordenados por inicio desc.
create index if not exists incidents_active_idx
  on public.incidents(started_at desc)
  where published = true and resolved_at is null;

-- Historico: todos los publicados (resueltos o no) por inicio desc.
create index if not exists incidents_published_idx
  on public.incidents(started_at desc)
  where published = true;

-- Trigger touch updated_at + autoset resolved_at cuando status pasa a
-- 'resolved' y aun no estaba seteado. Idempotente al revertir.
create or replace function public.incidents_touch_and_resolve()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  if new.status = 'resolved' and new.resolved_at is null then
    new.resolved_at := now();
  end if;
  if new.status <> 'resolved' then
    new.resolved_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists incidents_touch on public.incidents;
create trigger incidents_touch
  before update on public.incidents
  for each row execute function public.incidents_touch_and_resolve();

-- Mismo manejo en INSERT (si crean directamente como 'resolved').
drop trigger if exists incidents_insert_touch on public.incidents;
create trigger incidents_insert_touch
  before insert on public.incidents
  for each row execute function public.incidents_touch_and_resolve();

-- ─────────────────────────── RLS ───────────────────────────
-- Lectura: cualquier (incluso anon) si published=true. Para que la
-- pagina /status funcione SIN sesion, usamos `to anon, authenticated`.
-- CRUD: solo admin via helper public.is_admin().

alter table public.incidents enable row level security;

drop policy if exists "incidents_select_public" on public.incidents;
create policy "incidents_select_public"
  on public.incidents for select
  to anon, authenticated
  using (published = true or public.is_admin());

drop policy if exists "incidents_admin_insert" on public.incidents;
create policy "incidents_admin_insert"
  on public.incidents for insert
  with check (public.is_admin());

drop policy if exists "incidents_admin_update" on public.incidents;
create policy "incidents_admin_update"
  on public.incidents for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "incidents_admin_delete" on public.incidents;
create policy "incidents_admin_delete"
  on public.incidents for delete
  using (public.is_admin());
