-- ========================================================================
-- 0096 · Normalizar content_hash de los nodos de la Constitucion
-- ------------------------------------------------------------------------
-- Las EFs (generate-exam, generate-tf, generate-essay) tras la 0090 fueron
-- ejecutadas para algun nodo (p.ej. Articulo 9 al pulsar "Explicado") y
-- sobrescribieron `index_nodes.content_hash` con SHA-256 del texto.
--
-- El banco de 3579 preguntas (regenerado en 0095) usa md5(title) como
-- content_hash. Por tanto el JOIN del cliente (que filtra preguntas con
-- `index_nodes.content_hash IN (...)`) NO encuentra esas 21 preguntas del
-- Articulo 9 ni cualesquiera otras secciones cuyo hash fue sobrescrito.
--
-- Este SQL fuerza `content_hash = md5(title)` en TODOS los nodos del
-- subject Constitucion, sea cual sea el valor actual.
--
-- Tras aplicar la 0096, las EFs (corregidas en este mismo PR) no volveran
-- a sobrescribir un content_hash existente: respetaran el md5(title) si
-- ya esta presente.
-- ========================================================================

do $$
declare
  v_subject_id uuid := '942f19b7-e60c-4e58-bde4-629ded718b96';
  v_updated int;
begin
  -- Verificar que el subject existe (defensivo).
  if not exists (select 1 from public.subjects where id = v_subject_id) then
    raise notice '[0096] subject Constitucion no encontrado, skipping';
    return;
  end if;

  update public.index_nodes
  set content_hash = md5(title)
  where subject_id = v_subject_id
    and (content_hash is null or content_hash <> md5(title));

  get diagnostics v_updated = row_count;
  raise notice '[0096] index_nodes content_hash normalized to md5(title): % rows', v_updated;
end $$;
