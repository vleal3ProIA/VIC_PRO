-- ========================================================================
-- 0093 · Re-asignar content_hash en question_bank usando regex sobre el TEXTO
-- ------------------------------------------------------------------------
-- La 0092 falló porque hacía match por texto IDÉNTICO entre JSON y BD, pero
-- diferencias en whitespace/Unicode rompieron la mayoría de los matches.
--
-- Este SQL replica la lógica del parser Python original PERO directamente
-- en BD: busca "Artículo N" (o variantes) en `question` Y en cada opción
-- de `options` jsonb. Para la PRIMERA referencia encontrada, asigna
-- content_hash = md5("Artículo N").
--
-- Si no hay referencia → md5("Constitución Española") (raíz).
--
-- Solo actualiza filas cuyo nuevo hash difiere del actual.
-- ========================================================================

do $$
declare
  v_subject_id uuid := '942f19b7-e60c-4e58-bde4-629ded718b96';
  v_root_hash text := md5('Constitución Española');
  v_updated int;
begin
  -- Build a CTE that joins each row in question_bank with the first
  -- "Artículo N" mention found in either question or any option string.
  with full_text as (
    select
      qb.id,
      qb.question
        || ' '
        || coalesce(
             (select string_agg(opt::text, ' ')
              from jsonb_array_elements_text(qb.options) opt),
             ''
           ) as full
    from public.question_bank qb
  ),
  matched as (
    select
      ft.id,
      (regexp_match(
        ft.full,
        'art(?:\.|[ií]culo[s]?)\s+(\d+)\b',
        'i'
      ))[1] as art_num
    from full_text ft
  ),
  target as (
    select
      m.id,
      case
        when m.art_num is not null and exists (
          select 1 from public.index_nodes n
          where n.subject_id = v_subject_id
            and n.title = 'Artículo ' || m.art_num
        )
        then md5('Artículo ' || m.art_num)
        else v_root_hash
      end as new_hash
    from matched m
  )
  update public.question_bank qb
  set content_hash = t.new_hash
  from target t
  where qb.id = t.id
    and qb.content_hash <> t.new_hash;

  get diagnostics v_updated = row_count;
  raise notice '[0093] question_bank rows updated: %', v_updated;
end $$;
