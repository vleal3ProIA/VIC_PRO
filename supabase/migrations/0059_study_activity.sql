-- ============================================================================
-- 0059_study_activity.sql · Días de estudio (racha) (Fase 3)
-- ----------------------------------------------------------------------------
-- Un registro por (usuario, día) en el que el usuario estudió (repasar
-- flashcards, responder test/simulacro...). Sirve para la racha diaria y un
-- mini-calendario de actividad. Todo RLS por propietario.
-- ============================================================================

create table if not exists public.study_activity (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null,
  primary key (user_id, day)
);

alter table public.study_activity enable row level security;

drop policy if exists "study_activity_owner_all" on public.study_activity;
create policy "study_activity_owner_all"
  on public.study_activity for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
