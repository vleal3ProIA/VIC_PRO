-- ============================================================================
-- 0060_exam.sql · Banco de preguntas de examen por sección (Fase 4)
-- ----------------------------------------------------------------------------
-- A diferencia de `quiz_questions` (cuestionario rápido del temario), este es
-- el banco para los TESTS configurables: cada pregunta va etiquetada con la
-- sección del índice (`node_id`) a la que pertenece, para poder elegir de qué
-- partes hacer el test y saltar a esa sección del temario al revisar.
--
-- Se reemplaza por completo al generar un test nuevo (el ámbito lo elige el
-- usuario). Todo RLS por propietario; la Edge Function usa service_role.
-- ============================================================================

create table if not exists public.exam_questions (
  id            uuid primary key default gen_random_uuid(),
  subject_id    uuid not null references public.subjects(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  node_id       uuid references public.index_nodes(id) on delete set null,
  question      text not null,
  options       jsonb not null,
  correct_index int  not null default 0,
  explanation   text,
  created_at    timestamptz not null default now()
);

create index if not exists exam_questions_subject_idx
  on public.exam_questions (subject_id);

alter table public.exam_questions enable row level security;

drop policy if exists "exam_questions_owner_all" on public.exam_questions;
create policy "exam_questions_owner_all"
  on public.exam_questions for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
