-- ============================================================================
-- 0055_quiz.sql · Cuestionario tipo test (Fase 3)
-- ----------------------------------------------------------------------------
-- Preguntas de opción múltiple generadas por IA a partir del temario (o de una
-- sección). `options` es un array JSON de textos; `correct_index` apunta a la
-- opción correcta. `explanation` justifica la respuesta.
--
-- Estadísticas ligeras por pregunta (times_seen / times_correct) para señalar
-- puntos débiles. `node_id` nulo = pregunta del temario completo. Todo RLS por
-- propietario; la Edge Function de generación usa service_role.
-- ============================================================================

create table if not exists public.quiz_questions (
  id            uuid primary key default gen_random_uuid(),
  subject_id    uuid not null references public.subjects(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  node_id       uuid references public.index_nodes(id) on delete set null,
  question      text not null,
  options       jsonb not null,
  correct_index int  not null default 0,
  explanation   text,
  times_seen    int  not null default 0,
  times_correct int  not null default 0,
  created_at    timestamptz not null default now()
);

create index if not exists quiz_questions_subject_idx
  on public.quiz_questions (subject_id);

alter table public.quiz_questions enable row level security;

drop policy if exists "quiz_questions_owner_all" on public.quiz_questions;
create policy "quiz_questions_owner_all"
  on public.quiz_questions for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
