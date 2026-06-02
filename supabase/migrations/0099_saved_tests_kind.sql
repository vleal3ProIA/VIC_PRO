-- ============================================================================
-- 0099_saved_tests_kind.sql · Tests guardados de V/F y Ensayo (mismo modelo)
-- ----------------------------------------------------------------------------
-- El modelo `saved_tests` se introdujo en 0098 para tests A/B/C/D (mock).
-- Aqui lo extendemos para que admita tres tipos: 'mock' | 'tf' | 'essay'.
-- Las preguntas referenciadas viven en tablas distintas segun el kind:
--   mock  -> public.question_bank
--   tf    -> public.tf_bank
--   essay -> public.essay_bank
-- La columna `question_ids` (jsonb) sigue siendo un snapshot por id.
--
-- `exam_attempts` gana tambien la columna `kind` para diferenciar intentos
-- de cada tipo (V/F y ensayo no tenian historial persistente — ahora si).
--
-- La RPC `combine_saved_tests` valida ademas que TODOS los origenes
-- compartan el MISMO kind (no se pueden combinar mock con tf).
-- ============================================================================

alter table public.saved_tests
  add column if not exists kind text not null default 'mock';

alter table public.saved_tests
  drop constraint if exists saved_tests_kind_check;
alter table public.saved_tests
  add constraint saved_tests_kind_check
  check (kind in ('mock','tf','essay'));

create index if not exists saved_tests_subject_kind_idx
  on public.saved_tests (subject_id, kind, created_at desc);

alter table public.exam_attempts
  add column if not exists kind text not null default 'mock';

alter table public.exam_attempts
  drop constraint if exists exam_attempts_kind_check;
alter table public.exam_attempts
  add constraint exam_attempts_kind_check
  check (kind in ('mock','tf','essay'));

create index if not exists exam_attempts_subject_kind_idx
  on public.exam_attempts (subject_id, kind, created_at desc);

-- Re-definir combine_saved_tests para validar mismo kind.
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
  v_kind      text;
  v_kind_ok   int;
  v_subj_ok   int;
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

  -- Todos los origenes deben ser del usuario, mismo subject y mismo kind.
  select
    count(distinct subject_id),
    count(distinct kind),
    max(subject_id),
    max(kind)
  into v_subj_ok, v_kind_ok, v_subject, v_kind
  from public.saved_tests
  where id = any(p_source_ids)
    and user_id = v_user_id;

  if v_subj_ok is null or v_subj_ok = 0 then
    raise exception 'no_accessible_sources' using errcode = '42501';
  end if;
  if v_subj_ok > 1 then
    raise exception 'mixed_subjects' using errcode = '22023';
  end if;
  if v_kind_ok > 1 then
    raise exception 'mixed_kinds' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(distinct q), '[]'::jsonb)
    into v_qids
  from public.saved_tests s,
       lateral jsonb_array_elements(s.question_ids) q
  where s.id = any(p_source_ids)
    and s.user_id = v_user_id;

  select coalesce(jsonb_agg(distinct n), '[]'::jsonb)
    into v_nids
  from public.saved_tests s,
       lateral jsonb_array_elements(s.node_ids) n
  where s.id = any(p_source_ids)
    and s.user_id = v_user_id;

  insert into public.saved_tests
    (user_id, subject_id, title, kind, question_ids, node_ids, question_count)
  values
    (v_user_id, v_subject,
     coalesce(nullif(trim(p_title), ''), 'Test combinado'),
     v_kind, v_qids, v_nids,
     coalesce(jsonb_array_length(v_qids), 0))
  returning id into v_new_id;

  return v_new_id;
end $$;

grant execute on function public.combine_saved_tests(uuid[], text) to authenticated;
