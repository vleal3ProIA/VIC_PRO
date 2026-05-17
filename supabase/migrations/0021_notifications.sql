-- ============================================================================
-- 0021 · In-app notifications
-- ----------------------------------------------------------------------------
-- Sistema de notificaciones in-app generico, reusable por CUALQUIER
-- feature futura del producto. NO incluye email/push -- esos canales se
-- montan encima en PRs posteriores (3.F Email transaccional, 3.X Push
-- via web push API).
--
-- Modelo:
--
--   notifications (uuid)
--   ├── user_id      -> a quién va dirigida (auth.users)
--   ├── tenant_id    -> a qué tenant pertenece (nullable: notifs
--   │                   "globales" del user no atadas a tenant, p.ej.
--   │                   security alerts)
--   ├── type         -> nivel visual: info | success | warning | error
--   ├── category     -> agrupador libre: 'billing', 'team', 'system',
--   │                   'security', etc. Para filtros y preferencias.
--   ├── title        -> primera linea (siempre)
--   ├── body         -> texto secundario opcional
--   ├── action_url   -> deep link interno opcional ("/billing/invoices")
--   ├── read_at      -> NULL = sin leer; cuando se marca pasa a now()
--   └── created_at
--
-- RLS:
--   - SELECT: solo SUS propias notifs (user_id = auth.uid()).
--   - INSERT: solo service_role (las crean Edge Functions, nunca el
--     cliente directamente).
--   - UPDATE: solo el dueno, y SOLO para tocar read_at.
--   - DELETE: solo el dueno.
--
-- Cleanup: las RLS no las purgan. Un cron job futuro borra read=true
-- mas viejas que 90 dias para mantener la tabla compacta.
-- ============================================================================

do $$ begin
  create type public.notification_type as enum (
    'info','success','warning','error'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  tenant_id   uuid references public.tenants(id) on delete cascade,
  type        public.notification_type not null default 'info',
  category    text not null check (char_length(category) between 1 and 40),
  title       text not null check (char_length(title) between 1 and 200),
  body        text check (body is null or char_length(body) <= 1000),
  action_url  text check (action_url is null or char_length(action_url) <= 500),
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

-- Index PARCIAL solo sobre no leidas: la consulta caliente es
-- "cuantas no leidas tiene este user" para el badge. Si la tabla crece a
-- 100k rows, este index sigue siendo pequeno porque solo indexa el
-- subset no leido.
create index if not exists notifications_unread_idx
  on public.notifications(user_id, created_at desc)
  where read_at is null;

-- Index general por user + fecha para la pantalla /notifications que
-- muestra TODO el historial paginado.
create index if not exists notifications_user_created_idx
  on public.notifications(user_id, created_at desc);

-- ─────────────────────────── RLS ───────────────────────────

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications for select
  using (user_id = auth.uid());

-- UPDATE: solo el dueno y solo para tocar read_at. El WITH CHECK impide
-- que un user modifique title/body/etc. de notifs ajenas o las propias.
drop policy if exists "notifications_update_own_read_at" on public.notifications;
create policy "notifications_update_own_read_at"
  on public.notifications for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
  on public.notifications for delete
  using (user_id = auth.uid());

-- INSERT NO se permite a `authenticated` -- solo service_role (via Edge
-- Functions). De lo contrario un cliente podria spammearse a si mismo.
-- service_role bypasea RLS automaticamente.

-- ─────────────────────────── RPCs ───────────────────────────

-- get_unread_notifications_count() -> int
-- Optimizada con el index parcial. La consume el badge del AppBar.
create or replace function public.get_unread_notifications_count()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(count(*), 0)::int
  from public.notifications
  where user_id = auth.uid()
    and read_at is null;
$$;

-- mark_notification_read(id) -> bool (true si marco algo)
-- Idempotente: si ya estaba leida, no hace nada y devuelve false.
create or replace function public.mark_notification_read(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
begin
  update public.notifications
    set read_at = now()
    where id = p_id
      and user_id = auth.uid()
      and read_at is null;
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

-- mark_all_notifications_read() -> int (count marcadas)
create or replace function public.mark_all_notifications_read()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
begin
  update public.notifications
    set read_at = now()
    where user_id = auth.uid()
      and read_at is null;
  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke all on function public.get_unread_notifications_count() from public;
revoke all on function public.mark_notification_read(uuid) from public;
revoke all on function public.mark_all_notifications_read() from public;
grant execute on function public.get_unread_notifications_count() to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;

comment on table public.notifications is
  'In-app notifications per user. Insertadas por Edge Functions con service_role; leidas/marcadas por el propio usuario via RLS.';
