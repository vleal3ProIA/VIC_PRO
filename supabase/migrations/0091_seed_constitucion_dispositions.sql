-- ========================================================================
-- 0091 · Anyadir disposiciones de la Constitucion al subject existente
-- ------------------------------------------------------------------------
-- La 0090 omitio las 15 disposiciones (4 adicionales + 9 transitorias +
-- 1 derogatoria + 1 final) por bug en el regex. Esta migracion las
-- anyade como hermanos de los Titulos (parent = root, depth=1).
--
-- content_hash = md5(title) -> si el subject viejo tenia las mismas
-- disposiciones con md5(title), las preguntas en question_bank se
-- enlazan automaticamente.
-- ========================================================================

do $$
declare
  v_subject_id uuid;
  v_user_id    uuid;
  v_root_id    uuid;
  v_tmp_id     uuid;
  v_position   int;
begin
  -- Localizar subject Constitucion.
  select s.id, s.user_id into v_subject_id, v_user_id
  from public.subjects s
  join public.profiles p on p.id = s.user_id
  where p.is_super_admin = true
    and s.title ilike '%constituci%espa%'
  order by s.created_at desc
  limit 1;

  if v_subject_id is null then
    raise notice '[0091] subject no encontrado, skipping';
    return;
  end if;

  -- Localizar nodo raiz.
  select id into v_root_id
  from public.index_nodes
  where subject_id = v_subject_id and parent_id is null
  limit 1;

  if v_root_id is null then
    raise notice '[0091] root no encontrado, skipping';
    return;
  end if;

  -- Calcular position siguiente (despues del ultimo Titulo).
  select coalesce(max(position), -1) + 1 into v_position
  from public.index_nodes
  where parent_id = v_root_id;

  raise notice '[0091] anyadiendo disposiciones desde position=%', v_position;


  -- Disposicion 1: Disposición adicional primera
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición adicional primera'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición adicional primera', v_position + 0, 1, md5('Disposición adicional primera'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d1$La Constitución ampara y respeta los derechos históricos de
los territorios forales.

   La actualización general de dicho régimen foral se llevará a
cabo, en su caso, en el marco de la Constitución y de los Es-
tatutos de Autonomía.

                                                                                                     63$d1$);
  end if;

  -- Disposicion 2: Disposición adicional segunda
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición adicional segunda'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición adicional segunda', v_position + 1, 1, md5('Disposición adicional segunda'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d2$La declaración de mayoría de edad contenida en el artículo

12 de esta Constitución no perjudica las situaciones ampara-
das por los derechos forales en el ámbito del Derecho privado.$d2$);
  end if;

  -- Disposicion 3: Disposición adicional tercera
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición adicional tercera'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición adicional tercera', v_position + 2, 1, md5('Disposición adicional tercera'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d3$La modificación del régimen económico y fiscal del archi-

piélago canario requerirá informe previo de la Comunidad
Autónoma o, en su caso, del órgano provisional autonómico.$d3$);
  end if;

  -- Disposicion 4: Disposición adicional cuarta
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición adicional cuarta'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición adicional cuarta', v_position + 3, 1, md5('Disposición adicional cuarta'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d4$En las Comunidades Autónomas donde tengan su sede más

de una Audiencia Territorial, los Estatutos de Autonomía res-
pectivos podrán mantener las existentes, distribuyendo las
competencias entre ellas, siempre de conformidad con lo pre-
visto en la ley orgánica del poder judicial y dentro de la unidad
e independencia de éste.$d4$);
  end if;

  -- Disposicion 5: Disposición transitoria primera
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición transitoria primera'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición transitoria primera', v_position + 4, 1, md5('Disposición transitoria primera'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d5$En los territorios dotados de un régimen provisional de au-
tonomía, sus órganos colegiados superiores, mediante acuer-
do adoptado por la mayoría absoluta de sus miembros, podrán
sustituir la iniciativa que en el apartado 2 del artículo 143 atri-
buye a las Diputaciones Provinciales o a los órganos interinsu-
lares correspondientes.$d5$);
  end if;

  -- Disposicion 6: Disposición transitoria segunda
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición transitoria segunda'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición transitoria segunda', v_position + 5, 1, md5('Disposición transitoria segunda'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d6$Los territorios que en el pasado hubiesen plebiscitado afir-
mativamente proyectos de Estatuto de autonomía y cuenten,
al tiempo de promulgarse esta Constitución, con regímenes
provisionales de autonomía podrán proceder inmediatamente
en la forma que se prevé en el apartado 2 del artículo 148,
cuando así lo acordaren, por mayoría absoluta, sus órganos
preautonómicos colegiados superiores, comunicándolo al
Gobierno. El proyecto de Estatuto será elaborado de acuerdo
con lo establecido en el artículo 151, número 2, a convocatoria
del órgano colegiado preautonómico.$d6$);
  end if;

  -- Disposicion 7: Disposición transitoria tercera
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición transitoria tercera'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición transitoria tercera', v_position + 6, 1, md5('Disposición transitoria tercera'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d7$La iniciativa del proceso autonómico por parte de las Cor-
poraciones locales o de sus miembros, prevista en el apartado

64
2 del artículo 143, se entiende diferida, con todos sus efectos,
hasta la celebración de las primeras elecciones locales una vez
vigente la Constitución.$d7$);
  end if;

  -- Disposicion 8: Disposición transitoria cuarta
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición transitoria cuarta'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición transitoria cuarta', v_position + 7, 1, md5('Disposición transitoria cuarta'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d8$1. En el caso de Navarra, y a efectos de su incorporación al
Consejo General Vasco o al régimen autonómico vasco que le
sustituya, en lugar de lo que establece el artículo 143 de la
Constitución, la iniciativa corresponde al Órgano Foral com-
petente, el cual adoptará su decisión por mayoría de los miem-
bros que lo componen. Para la validez de dicha iniciativa será
preciso, además, que la decisión del Órgano Foral competen-
te sea ratificada por referéndum expresamente convocado al
efecto, y aprobado por mayoría de los votos válidos emitidos.

   2. Si la iniciativa no prosperase, solamente se podrá repro-
ducir la misma en distinto período del mandato del Órgano
Foral competente, y en todo caso, cuando haya transcurrido el
plazo mínimo que establece el artículo 143.$d8$);
  end if;

  -- Disposicion 9: Disposición transitoria quinta
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición transitoria quinta'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición transitoria quinta', v_position + 8, 1, md5('Disposición transitoria quinta'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d9$Las ciudades de Ceuta y Melilla podrán constituirse en Comu-
nidades Autónomas si así lo deciden sus respectivos Ayunta-
mientos, mediante acuerdo adoptado por la mayoría absoluta de
sus miembros y así lo autorizan las Cortes Generales, mediante
una ley orgánica, en los términos previstos en el artículo 144.$d9$);
  end if;

  -- Disposicion 10: Disposición transitoria sexta
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición transitoria sexta'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición transitoria sexta', v_position + 9, 1, md5('Disposición transitoria sexta'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d10$Cuando se remitieran a la Comisión Constitucional del Con-

greso varios proyectos de Estatuto, se dictaminarán por el
orden de entrada en aquélla, y el plazo de dos meses a que se
refiere el artículo 151 empezará a contar desde que la Comi-
sión termine el estudio del proyecto o proyectos de que suce-
sivamente haya conocido.$d10$);
  end if;

  -- Disposicion 11: Disposición transitoria séptima
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición transitoria séptima'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición transitoria séptima', v_position + 10, 1, md5('Disposición transitoria séptima'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d11$Los organismos provisionales autonómicos se considerarán

disueltos en los siguientes casos:

   a) Una vez constituidos los órganos que establezcan los Es-
      tatutos de Autonomía aprobados conforme a esta Cons-
      titución.

                                                                                                     65
   b) En el supuesto de que la iniciativa del proceso autonómi-
      co no llegara a prosperar por no cumplir los requisitos
      previstos en el artículo 143.

   c) Si el organismo no hubiera ejercido el derecho que le re-
      conoce la disposición transitoria primera en el plazo de
      tres años.$d11$);
  end if;

  -- Disposicion 12: Disposición transitoria octava
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición transitoria octava'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición transitoria octava', v_position + 11, 1, md5('Disposición transitoria octava'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d12$1. Las Cámaras que han aprobado la presente Constitución
asumirán, tras la entrada en vigor de la misma, las funciones y
competencias que en ella se señalan, respectivamente, para el
Congreso y el Senado, sin que en ningún caso su mandato se
extienda más allá del 15 de junio de 1981.

   2. A los efectos de lo establecido en el artículo 99, la pro-
mulgación de la Constitución se considerará como supuesto
constitucional en el que procede su aplicación. A tal efecto, a
partir de la citada promulgación se abrirá un período de trein-
ta días para la aplicación de lo dispuesto en dicho artículo.

   Durante este período, el actual Presidente del Gobierno, que
asumirá las funciones y competencias que para dicho cargo
establece la Constitución, podrá optar por utilizar la facultad
que le reconoce el artículo 115 o dar paso, mediante la dimi-
sión, a la aplicación de lo establecido en el artículo 99, que-
dando en este último caso en la situación prevista en el apar-
tado 2 del artículo 101.

   3. En caso de disolución, de acuerdo con lo previsto en el
artículo 115, y si no se hubiera desarrollado legalmente lo pre-
visto en los artículos 68 y 69, serán de aplicación en las elec-
ciones las normas vigentes con anterioridad, con las solas
excepciones de que en lo referente a inelegibilidades e incom-
patibilidades se aplicará directamente lo previsto en el inciso
segundo de la letra b) del apartado 1 del artículo 70 de la
Constitución, así como lo dispuesto en la misma respecto a la
edad para el voto y lo establecido en el artículo 69,3.$d12$);
  end if;

  -- Disposicion 13: Disposición transitoria novena
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición transitoria novena'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición transitoria novena', v_position + 12, 1, md5('Disposición transitoria novena'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d13$A los tres años de la elección por vez primera de los miem-
bros del Tribunal Constitucional se procederá por sorteo para
la designación de un grupo de cuatro miembros de la misma
procedencia electiva que haya de cesar y renovarse. A estos
solos efectos se entenderán agrupados como miembros de la

66
misma procedencia a los dos designados a propuesta del Go-
bierno y a los dos que proceden de la formulada por el Con-
sejo General del Poder Judicial. Del mismo modo se procede-
rá transcurridos otros tres años entre los dos grupos no
afectados por el sorteo anterior. A partir de entonces se estará
a lo establecido en el número 3 del artículo 159.$d13$);
  end if;

  -- Disposicion 14: Disposición derogatoria
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición derogatoria'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición derogatoria', v_position + 13, 1, md5('Disposición derogatoria'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d14$1. Queda derogada la Ley 1/1977, de 4 de enero, para la Re-

forma Política, así como, en tanto en cuanto no estuvieran ya
derogadas por la anteriormente mencionada Ley, la de Princi-
pios del Movimiento Nacional, de 17 de mayo de 1958; el Fue-
ro de los Españoles, de 17 de julio de 1945; el del Trabajo, de 9
de marzo de 1938; la Ley Constitutiva de las Cortes, de 17 de
julio de 1942; la Ley de Sucesión en la Jefatura del Estado, de
26 de julio de 1947, todas ellas modificadas por la Ley Orgáni-
ca del Estado, de 10 de enero de 1967, y en los mismos térmi-
nos esta última y la de Referéndum Nacional de 22 de octubre
de 1945.

   2. En tanto en cuanto pudiera conservar alguna vigencia, se
considera definitivamente derogada la Ley de 25 de octubre de
1839 en lo que pudiera afectar a las provincias de Álava, Gui-
púzcoa y Vizcaya.

   En los mismos términos se considera definitivamente dero-
gada la Ley de 21 de julio de 1876.

   3. Asimismo quedan derogadas cuantas disposiciones se
opongan a lo establecido en esta Constitución.$d14$);
  end if;

  -- Disposicion 15: Disposición final
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = 'Disposición final'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Disposición final', v_position + 14, 1, md5('Disposición final'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', $d15$Esta Constitución entrará en vigor el mismo día de la publi-

cación de su texto oficial en el boletín oficial del Estado. Se
publicará también en las demás lenguas de España.

                                                                                                     67
   POR TANTO,
   MANDO A TODOS LOS ESPAÑOLES, PARTICULARES Y
AUTORIDADES, QUE GUARDEN Y HAGAN GUARDAR ESTA
CONSTITUCIÓN COMO NORMA FUNDAMENTAL DEL ESTADO.
   PALACIO DE LAS CORTES, A VEINTISIETE DE DICIEMBRE DE
MIL NOVECIENTOS SETENTA Y OCHO.

                                                                 JUAN CARLOS
                     EL PRESIDENTE DE LAS CORTES

                            Antonio Hernández Gil
      EL PRESIDENTE DEL CONGRESO DE LOS DIPUTADOS

                  Fernando Álvarez de Miranda y Torres
                       EL PRESIDENTE DEL SENADO
                             Antonio Fontán Pérez

68$d15$);
  end if;

  raise notice '[0091] disposiciones anyadidas';
end $$;
