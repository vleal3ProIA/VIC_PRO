-- ============================================================================
-- 0098_saved_tests.sql · Tests guardados (plantillas reutilizables)
-- ----------------------------------------------------------------------------
-- Hasta ahora cada "test" era efimero: el usuario configuraba ambito + cantidad,
-- arrancaba el runner y al terminar se guardaba un `exam_attempts` (snapshot
-- del intento). No habia forma de REPETIR EXACTAMENTE el mismo test.
--
-- Este modelo introduce `saved_tests`: cada fila es un test plantilla con
-- nombre, lista FIJA de question_ids (snapshot, sobrevive a regeneraciones del
-- banco) y metadatos. Los `exam_attempts` ahora pueden enlazar via `saved_test_id`
-- al test del que son intento, permitiendo:
--   - Repetir el mismo test las veces que quiera.
--   - Ver progreso (lista de attempts de un mismo saved_test ordenados por
--     fecha, grafica de evolucion).
--   - Combinar varios saved_tests en uno nuevo (RPC `combine_saved_tests`).
--
-- Todo RLS por propietario. La RPC tambien valida ownership.
-- ============================================================================

create table if not exists public.saved_tests (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  subject_id      uuid not null references public.subjects(id) on delete cascade,
  title           text not null,
  -- jsonb array de question_ids (uuid strings) del banco; snapshot inmutable.
  question_ids    jsonb not null default '[]'::jsonb,
  -- node_ids elegidos por el usuario al crear el test (para mostrar el alcance
  -- en la UI o reconstruir el titulo descriptivo).
  node_ids        jsonb not null default '[]'::jsonb,
  -- Conteo cacheado (jsonb_array_length(question_ids) seria suficiente, pero
  -- una columna int es 1000x mas barata en filtros y listings).
  question_count  int   not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists saved_tests_subject_idx
  on public.saved_tests (subject_id, created_at desc);
create index if not exists saved_tests_user_idx
  on public.saved_tests (user_id, created_at desc);

alter table public.saved_tests enable row level security;

drop policy if exists "saved_tests_owner_all" on public.saved_tests;
create policy "saved_tests_owner_all"
  on public.saved_tests for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Trigger para mantener updated_at al renombrar o tocar.
create or replace function public._saved_tests_touch_updated()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists saved_tests_touch_updated on public.saved_tests;
create trigger saved_tests_touch_updated
  before update on public.saved_tests
  for each row execute function public._saved_tests_touch_updated();

-- ----------------------------------------------------------------------------
-- Enlace exam_attempts -> saved_tests (opcional: solo los attempts que vengan
-- de un test guardado lo rellenaran; los attempts ad-hoc legados quedan en
-- NULL).
-- ----------------------------------------------------------------------------
alter table public.exam_attempts
  add column if not exists saved_test_id uuid references public.saved_tests(id)
    on delete set null;

create index if not exists exam_attempts_saved_test_idx
  on public.exam_attempts (saved_test_id, created_at desc)
  where saved_test_id is not null;

-- ----------------------------------------------------------------------------
-- RPC combine_saved_tests · une las preguntas de varios saved_tests en uno
-- nuevo. Valida que TODOS los origenes pertenezcan al mismo usuario y subject.
-- Devuelve el id del nuevo saved_test.
-- ----------------------------------------------------------------------------
create or replace function public.combine_saved_tests(
  p_source_ids uuid[],
  p_title      text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id   uuid := auth.uid();
  v_subject   uuid;
  v_owner_chk int;
  v_qids      jsonb;
  v_nids      jsonb;
  v_new_id    uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_source_ids is null or array_length(p_source_ids, 1) is null then
    raise exception 'no_sources' using errcode = '22023';
  end if;

  -- Todos los origenes deben ser del usuario y del MISMO subject.
  select count(distinct subject_id), max(subject_id)
    into v_owner_chk, v_subject
  from public.saved_tests
  where id = any(p_source_ids)
    and user_id = v_user_id;

  if v_owner_chk is null or v_owner_chk = 0 then
    raise exception 'no_accessible_sources' using errcode = '42501';
  end if;
  if v_owner_chk > 1 then
    raise exception 'mixed_subjects' using errcode = '22023';
  end if;

  -- Union de question_ids (preserva orden de aparicion, dedupe por igualdad
  -- jsonb).
  select coalesce(jsonb_agg(distinct q), '[]'::jsonb)
    into v_qids
  from public.saved_tests s,
       lateral jsonb_array_elements(s.question_ids) q
  where s.id = any(p_source_ids)
    and s.user_id = v_user_id;

  -- Union de node_ids (aproximada — solo para mostrar alcance).
  select coalesce(jsonb_agg(distinct n), '[]'::jsonb)
    into v_nids
  from public.saved_tests s,
       lateral jsonb_array_elements(s.node_ids) n
  where s.id = any(p_source_ids)
    and s.user_id = v_user_id;

  insert into public.saved_tests
    (user_id, subject_id, title, question_ids, node_ids, question_count)
  values
    (v_user_id, v_subject, coalesce(nullif(trim(p_title), ''), 'Test combinado'),
     v_qids, v_nids, coalesce(jsonb_array_length(v_qids), 0))
  returning id into v_new_id;

  return v_new_id;
end $$;

grant execute on function public.combine_saved_tests(uuid[], text) to authenticated;
