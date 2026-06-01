-- ========================================================================
-- 0088 · Seed question_bank · enlazar 3676 preguntas Constitucion al banco global
-- ------------------------------------------------------------------------
-- Las migraciones 0086 + 0087 insertaron preguntas en `exam_questions`
-- (banco subject-specific). Pero el CLIENTE Dart (`listExamQuestions`)
-- busca preguntas en `question_bank` (banco GLOBAL) cuyo `content_hash`
-- coincida con el de algun `index_nodes` del subject.
--
-- Sin esta migracion, las 3676 preguntas estan "huerfanas": el cliente
-- no las ve y siempre llama a la IA -> gasta tokens innecesariamente.
--
-- Pasos:
--   1) Poblar `index_nodes.content_hash` para los 212 nodos del subject
--      Constitucion (usa md5 del texto cuando existe, md5 del title como
--      fallback).
--   2) Copiar de `exam_questions` -> `question_bank` enlazando por
--      content_hash. Idempotente con WHERE NOT EXISTS.
-- ========================================================================

do $$
declare
  v_subject_id uuid;
  v_updated_hashes int;
  v_inserted_bank  int;
begin
  -- Localizar el subject Constitucion.
  select s.id into v_subject_id
  from public.subjects s
  join public.profiles p on p.id = s.user_id
  where p.is_super_admin = true
    and s.title ilike '%constituci_n%espa_ola%'
  order by s.created_at asc
  limit 1;

  if v_subject_id is null then
    raise notice '[0088] subject Constitucion no encontrado. Skipping.';
    return;
  end if;

  -- 1a) Poblar content_hash desde node_content (kind='original' primero,
  -- 'intro' si no hay original).
  update public.index_nodes n
  set content_hash = sub.hash
  from (
    select
      nc.node_id,
      md5(nc.content) as hash
    from public.node_content nc
    join public.index_nodes nn on nn.id = nc.node_id
    where nn.subject_id = v_subject_id
      and nc.kind in ('original', 'intro')
      and nc.content is not null
      and length(trim(nc.content)) > 0
  ) sub
  where n.id = sub.node_id
    and n.content_hash is null;

  get diagnostics v_updated_hashes = row_count;
  raise notice '[0088] index_nodes con hash actualizado desde node_content: %', v_updated_hashes;

  -- 1b) Fallback: nodos sin node_content -> md5(title).
  update public.index_nodes
  set content_hash = md5(title)
  where subject_id = v_subject_id
    and content_hash is null
    and length(trim(title)) > 0;

  get diagnostics v_updated_hashes = row_count;
  raise notice '[0088] index_nodes con hash desde title (fallback): %', v_updated_hashes;

  -- 2) Copiar preguntas de exam_questions a question_bank.
  -- Idempotente: si ya existe la pregunta en el banco con el mismo
  -- content_hash, no se duplica.
  insert into public.question_bank (
    content_hash, question, options, correct_index, explanation, lang
  )
  select distinct on (n.content_hash, eq.question)
    n.content_hash,
    eq.question,
    eq.options,
    eq.correct_index,
    eq.explanation,
    coalesce(
      (select language from public.subjects where id = v_subject_id),
      'es'
    ) as lang
  from public.exam_questions eq
  join public.index_nodes n on n.id = eq.node_id
  where eq.subject_id = v_subject_id
    and n.content_hash is not null
    and not exists (
      select 1 from public.question_bank qb
      where qb.content_hash = n.content_hash
        and qb.question = eq.question
    );

  get diagnostics v_inserted_bank = row_count;
  raise notice '[0088] preguntas insertadas en question_bank: %', v_inserted_bank;
end $$;
