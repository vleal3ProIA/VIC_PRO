-- ============================================================================
-- 0082 · Error reports (pipeline ERROR_REPORTING)
-- ----------------------------------------------------------------------------
-- Tabla unica donde las Edge Functions vuelcan el detalle tecnico de
-- CUALQUIER error que ocurra dentro de un try/catch. La UI cliente NO
-- recibe esa informacion (solo un `error_code = 'generic_error'` + el
-- `error_id` para que el admin lo localice en /admin/errors). Asi el
-- usuario final nunca ve stacks, mensajes de proveedor IA, detalles de
-- credenciales caidas, etc.
--
-- **Quien escribe**: SOLO las Edge Functions via service_role
-- (`error_reporter.ts`). No hay policy de INSERT para `authenticated`.
--
-- **Quien lee/actualiza/borra**: admin + super_admin (cualquier admin
-- ve los reports; las marcas de "resuelto" / "borrado" estan reservadas
-- a ellos).
--
-- **AI diagnosis**: el admin puede pulsar "Diagnosticar con IA" en el
-- detalle de un error. La EF `diagnose-error` cachea el resultado en
-- `ai_diagnosis` (jsonb {why, what_user_did, how_to_fix}) para no
-- regenerar y no quemar tokens. NO se invoca automaticamente al crear
-- el report -- solo bajo demanda del admin.
-- ============================================================================

create table if not exists public.error_reports (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users(id) on delete set null,
  fn              text not null,
  error_code      text,
  error_message   text not null,
  error_details   jsonb,
  context         jsonb,
  severity        text not null default 'medium'
                  check (severity in ('low','medium','high','critical')),
  status          text not null default 'open'
                  check (status in ('open','in_progress','resolved','dismissed')),
  resolution_notes text,
  ai_diagnosis    jsonb,
  created_at      timestamptz not null default now(),
  resolved_at     timestamptz,
  resolved_by     uuid references auth.users(id) on delete set null
);

-- Hot query: lista abierta ordenada por fecha desc (lo que abre la
-- pagina admin por defecto). Index PARCIAL para que el tamano se quede
-- pequeno aunque la tabla crezca.
create index if not exists error_reports_open_idx
  on public.error_reports(created_at desc)
  where status = 'open';

-- Lookup por user (filtro "ver errores de fulano" en la UI).
create index if not exists error_reports_user_idx
  on public.error_reports(user_id, created_at desc);

-- Lookup por funcion (filtro "ver errores de generate-views").
create index if not exists error_reports_fn_idx
  on public.error_reports(fn, created_at desc);

-- ─────────────────────────── RLS ───────────────────────────

alter table public.error_reports enable row level security;

-- Lectura: admin + super_admin (is_admin() ya incluye super, ver 0044).
drop policy if exists "error_reports_admin_read" on public.error_reports;
create policy "error_reports_admin_read"
  on public.error_reports for select to authenticated
  using (public.is_admin() or public.is_super_admin());

-- Update: admin + super (marcar resuelto, anyadir notas, etc.).
drop policy if exists "error_reports_admin_update" on public.error_reports;
create policy "error_reports_admin_update"
  on public.error_reports for update to authenticated
  using (public.is_admin() or public.is_super_admin())
  with check (public.is_admin() or public.is_super_admin());

-- Delete: admin + super.
drop policy if exists "error_reports_admin_delete" on public.error_reports;
create policy "error_reports_admin_delete"
  on public.error_reports for delete to authenticated
  using (public.is_admin() or public.is_super_admin());

-- INSERT: SIN policy => bloqueado para `authenticated`. Las Edge
-- Functions insertan con service_role (bypass RLS automatico). De este
-- modo un cliente comprometido no puede spammear esta tabla.

comment on table public.error_reports is
  'Detalle tecnico de errores backend. Insertadas por Edge Functions '
  'con service_role; leidas/actualizadas/borradas por admin via RLS. '
  'La UI cliente nunca recibe el detalle -- solo el id para que el '
  'admin lo abra en /admin/errors.';
