-- ========================================================================
-- 0087 · Seed: recuperacion de 12 preguntas missing del 0086
-- ------------------------------------------------------------------------
-- En el PDF fuente, 15 preguntas tenian un typo en su numero de pregunta
-- (ej. "170" aparecia como "3670"). El parser principal las descarto por
-- estar fuera del rango del bloque. Aqui las recuperamos manualmente,
-- localizandolas entre las preguntas N-1 y N+1 que SI estaban en el JSON.
--
-- Estas se anyaden al subject Constitucion (mismo patron que 0086).
-- ========================================================================

do $$
declare
  v_subject_id uuid;
  v_user_id    uuid;
  v_root_id    uuid;
begin
  select s.id, s.user_id
    into v_subject_id, v_user_id
  from public.subjects s
  join public.profiles p on p.id = s.user_id
  where p.is_super_admin = true
    and s.title ilike '%constituci_n%espa_ola%'
  order by s.created_at asc
  limit 1;

  if v_subject_id is null then
    raise notice '[seed-recovered] subject Constitucion no encontrado. Skipping.';
    return;
  end if;

  select id into v_root_id
  from public.index_nodes
  where subject_id = v_subject_id and parent_id is null
  order by position asc
  limit 1;

  with batch (number, question, opt_a, opt_b, opt_c, opt_d, correct_index) as (
    values
      (170, 'Todos tienen derecho a:', 'La vida', 'La integridad física', 'La integridad moral', 'Todas las contestaciones anteriores son correctas.', 3),
      (380, 'La responsabilidad criminal del Presidente y los demás miembros del Gobierno será exigible, en su caso:', 'Ante la Sala de lo Penal de la Audiencia Provincial de Madrid.', 'Ante la Sala de lo Penal de la Audiencia Nacional.', 'Ante la Sala de lo Penal del Tribunal Superior de Justicia de Madrid.', 'Ante la Sala de lo Penal del Tribunal Supremo.', 3),
      (463, 'La Constitución entró en vigor el día', '27 de diciembre de 1978.', '31 de octubre de 1978.', '1 de enero de 1979.', '29 de diciembre de 1978.', 3),
      (536, 'La relación entre la Alcaldía y el Pleno del Ayuntamiento:', 'Es jerárquica siendo el Pleno el órgano superior de la Alcaldía', 'Es jerárquica siendo el Alcalde el órgano superior del Pleno', 'Carece de relación jerárquica.', 'Tiene carácter de apoyo, corresponde al Pleno el informe de asuntos para la Resolución de la Alcaldía.', 2),
      (849, '¿Quién debe proponer al Rey el nombramiento de un Ministro?', 'El Presidente del Gobierno.', 'El Presidente del Congreso.', 'El Presidente del Tribunal Supremo.', 'Ese nombramiento no tiene propuesta.', 0),
      (1446, '¿Cuál de las siguientes es una forma de gestión directa?', 'Organismo Autónomo local.', 'Arrendamiento.', 'Concierto.', 'Gestión interesada.', 0),
      (2060, 'Respecto del Ministerio Fiscal, la ley regulará:', 'Nada, porque su regulación ha de ser mediante ley orgánica', 'Su estructura', 'Su estatuto orgánico', 'Sus funciones.', 2),
      (3421, 'Una de las siguientes afirmaciones es falsa.', 'Los Presidentes de las cámaras ejercerán en ellas las funciones de policía.', 'Las comisiones de las cámaras podrán aprobar proyectos o proposiciones de Ley.', 'Las cámaras elaborarán sus propios estatutos, que serán aprobados por mayoría simple, además aprobarán sus propios presupuestos.', 'Todas las respuestas son correctas.', 2),
      (3531, 'En el Título preliminar de la Constitución Española se establece que España es un Estado:', 'Plural de derecho', 'Democrático del pueblo', 'Social y democrático de derecho', 'Popular y democrático de derecho.', 2),
      (3542, 'La inviolabilidad, respecto al Defensor del Pueblo:', 'No la tiene.', 'La posee sobre cualquier actuación, personal o propia del cargo, que realice.', 'La ostenta en cuanto a los actos que realice en el ejercicio de sus competencias como tal.', 'Supone que está exento de dar cuenta de su trabajo a las Cortes Generales.', 2),
      (3847, 'En torno al medio ambiente:', 'Todos tienen derecho a disfrutar de un medio ambiente adecuado para el desarrollo de la persona.', 'La Constitución no impone el deber de conservarlo.', 'El derecho a disfrutarlo es fundamental para las personas.', 'Se encuentra reconocido como Derecho en el art. 44 de la Constitución.', 0),
      (3949, 'La Policía Judicial depende, en sus funciones de averiguación del delito y descubrimiento de delincuentes:', 'De los Jueces, de los Tribunales y de los Fiscales.', 'Del Centro Superior de Investigaciones de la Defensa.', 'Del Ministerio del Interior.', 'Del Ministerio de Defensa, cuando sea la Guardia Civil la que ejerza las funciones de Policía Judicial.', 0)
  )
  insert into public.exam_questions (subject_id, user_id, node_id, question, options, correct_index, explanation)
  select
    v_subject_id, v_user_id, v_root_id,
    b.question,
    jsonb_build_array(b.opt_a, b.opt_b, b.opt_c, b.opt_d),
    b.correct_index,
    null
  from batch b
  where not exists (
    select 1 from public.exam_questions eq
    where eq.subject_id = v_subject_id and eq.question = b.question
  );

  raise notice '[seed-recovered] Insercion completada.';
end $$;
