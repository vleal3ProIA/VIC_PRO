-- ========================================================================
-- 0094 · Re-asignar content_hash en question_bank · regex con \y de PG
-- ------------------------------------------------------------------------
-- La 0093 usaba `\b` como word boundary pero PostgreSQL regex advanced
-- lo interpreta como BACKSPACE (\x08), no boundary. Resultado: el regex
-- nunca matcheaba. Esta migracion usa `\y` (que SI es word boundary en
-- PG) y ademas captura tambien el caso de "Articulo X.Y" o "Articulo X,".
--
-- La 0093 ya reseteo todo al raiz. Esta 0094 ahora mueve las que SI
-- tienen referencia a un articulo concreto al nodo correspondiente.
-- ========================================================================

do $$
declare
  v_subject_id uuid := '942f19b7-e60c-4e58-bde4-629ded718b96';
  v_root_hash text := md5('Constitución Española');
  v_updated int;
begin
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
      -- regex con \y (word boundary PostgreSQL advanced). Captura
      -- "Articulo N" / "art. N" / "Articulos N" donde N son digitos.
      -- (\d+)\y evita matchear "Articulo 1" dentro de "Articulo 10".
      (regexp_match(
        ft.full,
        '\yart(?:\.|[ií]culo[s]?)\s+(\d+)\y',
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
  raise notice '[0094] question_bank rows updated: %', v_updated;
end $$;
