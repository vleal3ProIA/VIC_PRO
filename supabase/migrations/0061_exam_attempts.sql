-- ============================================================================
-- 0061_exam_attempts.sql · Historial de tests realizados (Fase 4)
-- ----------------------------------------------------------------------------
-- Cada fila es un test COMPLETADO por el usuario: guarda la nota, el desglose
-- (aciertos/fallos/en blanco), la configuración (secciones, penalización,
-- tiempo) y un SNAPSHOT de las preguntas con la respuesta marcada, para poder
-- revisar el intento más tarde o repetirlo con las mismas preguntas y comparar
-- la evolución.
--
-- Todo RLS por propietario; se escribe desde el cliente con la sesión del
-- usuario (no hace falta Edge Function).
-- ============================================================================

create table if not exists public.exam_attempts (
  id              uuid primary key default gen_random_uuid(),
  subject_id      uuid not null references public.subjects(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  total           int  not null default 0,
  answered        int  not null default 0,
  correct         int  not null default 0,
  wrong           int  not null default 0,
  blank           int  not null default 0,
  grade           numeric(5, 2) not null default 0,
  penalty         boolean not null default true,
  timed           boolean not null default false,
  minutes         int  not null default 0,
  elapsed_seconds int  not null default 0,
  node_ids        jsonb not null default '[]'::jsonb,
  questions       jsonb not null default '[]'::jsonb,
  created_at      timestamptz not null default now()
);

create index if not exists exam_attempts_subject_idx
  on public.exam_attempts (subject_id, created_at desc);

alter table public.exam_attempts enable row level security;

drop policy if exists "exam_attempts_owner_all" on public.exam_attempts;
create policy "exam_attempts_owner_all"
  on public.exam_attempts for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
