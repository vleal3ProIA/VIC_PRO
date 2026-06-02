-- ========================================================================
-- 0089 · Seed Constitucion: estructura completa SIN llamar a IA
-- ------------------------------------------------------------------------
-- Parser local (tools/parse_constitucion_index.py) extrajo el texto del PDF
-- y la jerarquia Titulo > Capitulo > Seccion > Articulo. Esta migracion:
--
--   1. Localiza el subject Constitucion del super-admin.
--   2. UPSERT document con extracted_text completo + status='ready'.
--   3. Borra index_nodes y node_content existentes del subject (clean slate).
--   4. Crea root node + jerarquia completa.
--   5. INSERT node_content kind='original' por cada Articulo.
--   6. content_hash = md5(label) para cada nodo (compatible con subject viejo,
--      donde se usaba este fallback -> las 3696 preguntas en question_bank se
--      enlazan automaticamente).
--   7. subjects.index_status='ready'.
--
-- Resultado: el cliente puede generar Test del Articulo X sin gastar tokens
-- (las preguntas estan en question_bank). Los "Explicado" / "Resumen" / V-F
-- siguen llamando a IA pero con Groq disponible como fallback de Gemini.
-- ========================================================================
do $$
declare
  v_subject_id uuid;
  v_user_id    uuid;
  v_root_id    uuid;
  v_doc_id     uuid;
  v_storage_path text;
begin
  -- 1) Localizar (o crear) subject Constitucion del super-admin.
  -- Localizar primero el user_id del super-admin.
  select id into v_user_id
  from public.profiles
  where is_super_admin = true
  order by created_at asc
  limit 1;

  if v_user_id is null then
    raise exception '[0090] no super-admin encontrado, no puedo crear subject';
  end if;

  -- Buscar subject existente.
  select s.id into v_subject_id
  from public.subjects s
  where s.user_id = v_user_id
    and s.title ilike '%constituci%espa%'
  order by s.created_at desc
  limit 1;

  if v_subject_id is null then
    -- Crearlo.
    insert into public.subjects (user_id, title, language, shareable)
    values (v_user_id, 'Constitución Española', 'es', true)
    returning id into v_subject_id;
    raise notice '[0090] subject CREADO: %', v_subject_id;
  else
    raise notice '[0090] subject existente: %', v_subject_id;
  end if;

  raise notice '[0090] subject=%, user=%', v_subject_id, v_user_id;

  -- 2) UPSERT document. Buscamos el ultimo doc del subject (si hay) y lo
  -- updateamos. Si no, insertamos uno nuevo.
  select d.id, d.storage_path into v_doc_id, v_storage_path
  from public.documents d
  where d.subject_id = v_subject_id
  order by d.created_at desc nulls last
  limit 1;

  if v_doc_id is not null then
    update public.documents set
      status = 'ready',
      extracted_text = $body$CONSTITUCIÓN
    ES PAÑOL A
    Constitución Española

                   Cortes Generales
«BOE» núm. 311, de 29 de diciembre de 1978

         Referencia: BOE-A-1978-31229
Catálogo de publicaciones de la Administración General del
Estado https://cpage.mpr.gob.es/

NIPO (edición impresa): 143-25-047-7
NIPO (edición on line): 143-25-048-2
Depósito Legal: M-23773-2025
Fecha de edición: noviembre 2025
Diseña e imprime: Masquelibros, S.L.
Impreso en papeles FSC y PEFC.
                            ÍNDICE

Preámbulo......................................................................................... 5
TÍTULO PRELIMINAR....................................................................... 6
TÍTULO I. De los derechos y deberes fundamentales............. 8

   CAPÍTULO PRIMERO. De los españoles y los extranjeros.. 8
   CAPÍTULO SEGUNDO. Derechos y libertades....................... 9

      Sección 1.a De los derechos fundamentales y de
         las libertades públicas......................................................... 9

      Sección 2.a De los derechos y deberes de
         los ciudadanos..................................................................... 15

   CAPÍTULO TERCERO. De los principios rectores de
      la política social y económica.............................................. 17

   CAPÍTULO CUARTO. De las garantías de las libertades
      y derechos fundamentales.................................................... 20

   CAPÍTULO QUINTO. De la suspensión de los derechos
      y libertades................................................................................. 21

TÍTULO II. De la Corona................................................................. 21
TÍTULO III. De las Cortes Generales............................................ 25

   CAPÍTULO PRIMERO. De las Cámaras.................................... 25
   CAPÍTULO SEGUNDO. De la elaboración de las leyes........ 30
   CAPÍTULO TERCERO. De los Tratados Internacionales...... 33
TÍTULO IV. Del Gobierno y de la Administración..................... 35
TÍTULO V. De las relaciones entre el Gobierno
   y las Cortes Generales................................................................ 38
TÍTULO VI. Del Poder Judicial....................................................... 41
TÍTULO VII. Economía y Hacienda............................................... 44
TÍTULO VIII. De la Organización Territorial del Estado............ 48
   CAPÍTULO PRIMERO. Principios generales............................ 48
   CAPÍTULO SEGUNDO. De la Administración Local............. 48
   CAPÍTULO TERCERO. De las Comunidades Autónomas... 49
TÍTULO IX. Del Tribunal Constitucional...................................... 60
TÍTULO X. De la reforma constitucional..................................... 62
Disposiciones adicionales.............................................................. 63

                                                                                                       3
Disposiciones transitorias............................................................... 64
Disposición derogatoria................................................................. 67
Disposición final............................................................................... 67

4
                 TEXTO CONSOLIDADO

            Última modificación: 17 de febrero de 2024

DON JUAN CARLOS I, REY DE ESPAÑA, A TODOS LOS QUE
LA PRESENTE VIEREN Y ENTENDIEREN,
SABED: QUE LAS CORTES HAN APROBADO Y EL PUEBLO
ESPAÑOL RATIFICADO LA SIGUIENTE CONSTITUCIÓN:

                                 PREÁMBULO

   La Nación española, deseando establecer la justicia, la liber-
tad y la seguridad y promover el bien de cuantos la integran,
en uso de su soberanía, proclama su voluntad de:

   Garantizar la convivencia democrática dentro de la Consti-
tución y de las leyes conforme a un orden económico y social
justo.

   Consolidar un Estado de Derecho que asegure el imperio de
la ley como expresión de la voluntad popular.

   Proteger a todos los españoles y pueblos de España en el
ejercicio de los derechos humanos, sus culturas y tradiciones,
lenguas e instituciones.

   Promover el progreso de la cultura y de la economía para
asegurar a todos una digna calidad de vida.

   Establecer una sociedad democrática avanzada, y
   Colaborar en el fortalecimiento de unas relaciones pacíficas
y de eficaz cooperación entre todos los pueblos de la Tierra.
   En consecuencia, las Cortes aprueban y el pueblo español
ratifica la siguiente

                                                                                                       5
                      CONSTITUCIÓN

                            TÍTULO PRELIMINAR

ς  Artículo 1
   1. España se constituye en un Estado social y democrático

de Derecho, que propugna como valores superiores de su or-
denamiento jurídico la libertad, la justicia, la igualdad y el plu-
ralismo político.

   2. La soberanía nacional reside en el pueblo español, del que
emanan los poderes del Estado.

   3. La forma política del Estado español es la Monarquía par-
lamentaria.

ς  Artículo 2
   La Constitución se fundamenta en la indisoluble unidad de

la Nación española, patria común e indivisible de todos los
españoles, y reconoce y garantiza el derecho a la autonomía
de las nacionalidades y regiones que la integran y la solidaridad
entre todas ellas.

ς  Artículo 3
   1. El castellano es la lengua española oficial del Estado. To-

dos los españoles tienen el deber de conocerla y el derecho a
usarla.

   2. Las demás lenguas españolas serán también oficiales en
las respectivas Comunidades Autónomas de acuerdo con sus
Estatutos.

   3. La riqueza de las distintas modalidades lingüísticas de Es-
paña es un patrimonio cultural que será objeto de especial
respeto y protección.

ς  Artículo 4
   1. La bandera de España está formada por tres franjas hori-

zontales, roja, amarilla y roja, siendo la amarilla de doble an-
chura que cada una de las rojas.

6
   2. Los Estatutos podrán reconocer banderas y enseñas pro-
pias de las Comunidades Autónomas. Estas se utilizarán junto
a la bandera de España en sus edificios públicos y en sus actos
oficiales.

ς  Artículo 5

   La capital del Estado es la villa de Madrid.

ς  Artículo 6

   Los partidos políticos expresan el pluralismo político, con-
curren a la formación y manifestación de la voluntad popular
y son instrumento fundamental para la participación política.
Su creación y el ejercicio de su actividad son libres dentro del
respeto a la Constitución y a la ley. Su estructura interna y
funcionamiento deberán ser democráticos.

ς  Artículo 7

   Los sindicatos de trabajadores y las asociaciones empresa-
riales contribuyen a la defensa y promoción de los intereses
económicos y sociales que les son propios. Su creación y el
ejercicio de su actividad son libres dentro del respeto a la
Constitución y a la ley. Su estructura interna y funcionamiento
deberán ser democráticos.

ς  Artículo 8

   1. Las Fuerzas Armadas, constituidas por el Ejército de Tierra,
la Armada y el Ejército del Aire, tienen como misión garantizar
la soberanía e independencia de España, defender su integri-
dad territorial y el ordenamiento constitucional.

   2. Una ley orgánica regulará las bases de la organización
militar conforme a los principios de la presente Constitución.

ς  Artículo 9

   1. Los ciudadanos y los poderes públicos están sujetos a la
Constitución y al resto del ordenamiento jurídico.

   2. Corresponde a los poderes públicos promover las condi-
ciones para que la libertad y la igualdad del individuo y de los
grupos en que se integra sean reales y efectivas; remover los
obstáculos que impidan o dificulten su plenitud y facilitar la

                                                                                                       7
participación de todos los ciudadanos en la vida política, eco-
nómica, cultural y social.

   3. La Constitución garantiza el principio de legalidad, la jerar-
quía normativa, la publicidad de las normas, la irretroactividad
de las disposiciones sancionadoras no favorables o restrictivas
de derechos individuales, la seguridad jurídica, la responsabili-
dad y la interdicción de la arbitrariedad de los poderes públicos.

                                    TÍTULO I
             De los derechos y deberes fundamentales

ς  Artículo 10

   1. La dignidad de la persona, los derechos inviolables que le
son inherentes, el libre desarrollo de la personalidad, el respe-
to a la ley y a los derechos de los demás son fundamento del
orden político y de la paz social.

   2. Las normas relativas a los derechos fundamentales y a las
libertades que la Constitución reconoce se interpretarán de
conformidad con la Declaración Universal de Derechos Hu-
manos y los tratados y acuerdos internacionales sobre las mis-
mas materias ratificados por España.

                            CAPÍTULO PRIMERO
                  De los españoles y los extranjeros

ς  Artículo 11

   1. La nacionalidad española se adquiere, se conserva y se
pierde de acuerdo con lo establecido por la ley.

   2. Ningún español de origen podrá ser privado de su nacio-
nalidad.

   3. El Estado podrá concertar tratados de doble nacionalidad
con los países iberoamericanos o con aquellos que hayan te-
nido o tengan una particular vinculación con España. En estos
mismos países, aun cuando no reconozcan a sus ciudadanos
un derecho recíproco, podrán naturalizarse los españoles sin
perder su nacionalidad de origen.

ς  Artículo 12

   Los españoles son mayores de edad a los dieciocho años.

8
ς  Artículo 13

   1. Los extranjeros gozarán en España de las libertades públi-
cas que garantiza el presente Título en los términos que esta-
blezcan los tratados y la ley.

   2. Solamente los españoles serán titulares de los derechos
reconocidos en el artículo 23, salvo lo que, atendiendo a cri-
terios de reciprocidad, pueda establecerse por tratado o ley
para el derecho de sufragio activo y pasivo en las elecciones
municipales.

   3. La extradición sólo se concederá en cumplimiento de un
tratado o de la ley, atendiendo al principio de reciprocidad.
Quedan excluidos de la extradición los delitos políticos, no
considerándose como tales los actos de terrorismo.

   4. La ley establecerá los términos en que los ciudadanos de
otros países y los apátridas podrán gozar del derecho de asilo
en España.

                           CAPÍTULO SEGUNDO
                           Derechos y libertades

ς  Artículo 14

   Los españoles son iguales ante la ley, sin que pueda preva-
lecer discriminación alguna por razón de nacimiento, raza,
sexo, religión, opinión o cualquier otra condición o circuns-
tancia personal o social.

  Sección 1.ª De los derechos fundamentales y de las libertades
                                     públicas

ς  Artículo 15

   Todos tienen derecho a la vida y a la integridad física y mo-
ral, sin que, en ningún caso, puedan ser sometidos a tortura ni
a penas o tratos inhumanos o degradantes. Queda abolida la
pena de muerte, salvo lo que puedan disponer las leyes pena-
les militares para tiempos de guerra.

ς  Artículo 16

   1. Se garantiza la libertad ideológica, religiosa y de culto de
los individuos y las comunidades sin más limitación, en sus

                                                                                                       9
manifestaciones, que la necesaria para el mantenimiento del
orden público protegido por la ley.

   2. Nadie podrá ser obligado a declarar sobre su ideología,
religión o creencias.

   3. Ninguna confesión tendrá carácter estatal. Los poderes
públicos tendrán en cuenta las creencias religiosas de la socie-
dad española y mantendrán las consiguientes relaciones de
cooperación con la Iglesia Católica y las demás confesiones.

ς  Artículo 17

   1. Toda persona tiene derecho a la libertad y a la seguridad.
Nadie puede ser privado de su libertad, sino con la observancia
de lo establecido en este artículo y en los casos y en la forma
previstos en la ley.

   2. La detención preventiva no podrá durar más del tiempo
estrictamente necesario para la realización de las averiguacio-
nes tendentes al esclarecimiento de los hechos, y, en todo
caso, en el plazo máximo de setenta y dos horas, el detenido
deberá ser puesto en libertad o a disposición de la autoridad
judicial.

   3. Toda persona detenida debe ser informada de forma in-
mediata, y de modo que le sea comprensible, de sus derechos
y de las razones de su detención, no pudiendo ser obligada a
declarar. Se garantiza la asistencia de abogado al detenido en
las diligencias policiales y judiciales, en los términos que la ley
establezca.

   4. La ley regulará un procedimiento de «habeas corpus»
para producir la inmediata puesta a disposición judicial de toda
persona detenida ilegalmente. Asimismo, por ley se determi-
nará el plazo máximo de duración de la prisión provisional.

ς  Artículo 18

   1. Se garantiza el derecho al honor, a la intimidad personal y
familiar y a la propia imagen.

   2. El domicilio es inviolable. Ninguna entrada o registro po-
drá hacerse en él sin consentimiento del titular o resolución
judicial, salvo en caso de flagrante delito.

   3. Se garantiza el secreto de las comunicaciones y, en espe-
cial, de las postales, telegráficas y telefónicas, salvo resolución
judicial.

10
   4. La ley limitará el uso de la informática para garantizar el
honor y la intimidad personal y familiar de los ciudadanos y el
pleno ejercicio de sus derechos.

ς  Artículo 19

   Los españoles tienen derecho a elegir libremente su resi-
dencia y a circular por el territorio nacional.

   Asimismo, tienen derecho a entrar y salir libremente de Es-
paña en los términos que la ley establezca. Este derecho no
podrá ser limitado por motivos políticos o ideológicos.

ς  Artículo 20

   1. Se reconocen y protegen los derechos:

     a)	A expresar y difundir libremente los pensamientos, ideas
         y opiniones mediante la palabra, el escrito o cualquier
         otro medio de reproducción.

     b)	A la producción y creación literaria, artística, científica y
         técnica.

     c) A la libertad de cátedra.
     d)	A comunicar o recibir libremente información veraz por

         cualquier medio de difusión. La ley regulará el derecho
         a la cláusula de conciencia y al secreto profesional en el
         ejercicio de estas libertades.

   2. El ejercicio de estos derechos no puede restringirse me-
diante ningún tipo de censura previa.

   3. La ley regulará la organización y el control parlamentario
de los medios de comunicación social dependientes del Esta-
do o de cualquier ente público y garantizará el acceso a dichos
medios de los grupos sociales y políticos significativos, respe-
tando el pluralismo de la sociedad y de las diversas lenguas de
España.

   4. Estas libertades tienen su límite en el respeto a los dere-
chos reconocidos en este Título, en los preceptos de las leyes
que lo desarrollen y, especialmente, en el derecho al honor, a
la intimidad, a la propia imagen y a la protección de la juventud
y de la infancia.

   5. Sólo podrá acordarse el secuestro de publicaciones, gra-
baciones y otros medios de información en virtud de resolu-
ción judicial.

                                                                                                      11
ς  Artículo 21

   1. Se reconoce el derecho de reunión pacífica y sin armas. El
ejercicio de este derecho no necesitará autorización previa.

   2. En los casos de reuniones en lugares de tránsito público y
manifestaciones se dará comunicación previa a la autoridad,
que sólo podrá prohibirlas cuando existan razones fundadas
de alteración del orden público, con peligro para personas o
bienes.

ς  Artículo 22

   1. Se reconoce el derecho de asociación.
   2. Las asociaciones que persigan fines o utilicen medios ti-
pificados como delito son ilegales.
   3. Las asociaciones constituidas al amparo de este artículo
deberán inscribirse en un registro a los solos efectos de publi-
cidad.
   4. Las asociaciones sólo podrán ser disueltas o suspendidas
en sus actividades en virtud de resolución judicial motivada.
   5. Se prohíben las asociaciones secretas y las de carácter
paramilitar.

ς  Artículo 23

   1. Los ciudadanos tienen el derecho a participar en los asun-
tos públicos, directamente o por medio de representantes, li-
bremente elegidos en elecciones periódicas por sufragio uni-
versal.

   2. Asimismo, tienen derecho a acceder en condiciones de
igualdad a las funciones y cargos públicos, con los requisitos
que señalen las leyes.

ς  Artículo 24

   1. Todas las personas tienen derecho a obtener la tutela
efectiva de los jueces y tribunales en el ejercicio de sus dere-
chos e intereses legítimos, sin que, en ningún caso, pueda
producirse indefensión.

   2. Asimismo, todos tienen derecho al Juez ordinario prede-
terminado por la ley, a la defensa y a la asistencia de letrado, a
ser informados de la acusación formulada contra ellos, a un
proceso público sin dilaciones indebidas y con todas las ga-
rantías, a utilizar los medios de prueba pertinentes para su

12
defensa, a no declarar contra sí mismos, a no confesarse cul-
pables y a la presunción de inocencia.

   La ley regulará los casos en que, por razón de parentesco o
de secreto profesional, no se estará obligado a declarar sobre
hechos presuntamente delictivos.

ς  Artículo 25

   1. Nadie puede ser condenado o sancionado por acciones u
omisiones que en el momento de producirse no constituyan
delito, falta o infracción administrativa, según la legislación
vigente en aquel momento.

   2. Las penas privativas de libertad y las medidas de seguridad
estarán orientadas hacia la reeducación y reinserción social y
no podrán consistir en trabajos forzados. El condenado a pena
de prisión que estuviere cumpliendo la misma gozará de los
derechos fundamentales de este Capítulo, a excepción de los
que se vean expresamente limitados por el contenido del fallo
condenatorio, el sentido de la pena y la ley penitenciaria. En
todo caso, tendrá derecho a un trabajo remunerado y a los
beneficios correspondientes de la Seguridad Social, así como
al acceso a la cultura y al desarrollo integral de su personali-
dad.

   3. La Administración civil no podrá imponer sanciones que,
directa o subsidiariamente, impliquen privación de libertad.

ς  Artículo 26

   Se prohíben los Tribunales de Honor en el ámbito de la Ad-
ministración civil y de las organizaciones profesionales.

ς  Artículo 27

   1. Todos tienen el derecho a la educación. Se reconoce la
libertad de enseñanza.

   2. La educación tendrá por objeto el pleno desarrollo de la
personalidad humana en el respeto a los principios democrá-
ticos de convivencia y a los derechos y libertades fundamen-
tales.

   3. Los poderes públicos garantizan el derecho que asiste a
los padres para que sus hijos reciban la formación religiosa y
moral que esté de acuerdo con sus propias convicciones.

   4. La enseñanza básica es obligatoria y gratuita.

                                                                                                     13
   5. Los poderes públicos garantizan el derecho de todos a la
educación, mediante una programación general de la ense-
ñanza, con participación efectiva de todos los sectores afecta-
dos y la creación de centros docentes.

   6. Se reconoce a las personas físicas y jurídicas la libertad de
creación de centros docentes, dentro del respeto a los princi-
pios constitucionales.

   7. Los profesores, los padres y, en su caso, los alumnos in-
tervendrán en el control y gestión de todos los centros soste-
nidos por la Administración con fondos públicos, en los térmi-
nos que la ley establezca.

   8. Los poderes públicos inspeccionarán y homologarán el
sistema educativo para garantizar el cumplimiento de las leyes.

   9. Los poderes públicos ayudarán a los centros docentes
que reúnan los requisitos que la ley establezca.

   10. Se reconoce la autonomía de las Universidades, en los
términos que la ley establezca.

ς  Artículo 28

   1. Todos tienen derecho a sindicarse libremente. La ley po-
drá limitar o exceptuar el ejercicio de este derecho a las Fuer-
zas o Institutos armados o a los demás Cuerpos sometidos a
disciplina militar y regulará las peculiaridades de su ejercicio
para los funcionarios públicos. La libertad sindical comprende
el derecho a fundar sindicatos y a afiliarse al de su elección,
así como el derecho de los sindicatos a formar confederacio-
nes y a fundar organizaciones sindicales internacionales o a
afiliarse a las mismas. Nadie podrá ser obligado a afiliarse a un
sindicato.

   2. Se reconoce el derecho a la huelga de los trabajadores para
la defensa de sus intereses. La ley que regule el ejercicio de este
derecho establecerá las garantías precisas para asegurar el
mantenimiento de los servicios esenciales de la comunidad.

ς  Artículo 29

   1. Todos los españoles tendrán el derecho de petición indi-
vidual y colectiva, por escrito, en la forma y con los efectos
que determine la ley.

   2. Los miembros de las Fuerzas o Institutos armados o de los
Cuerpos sometidos a disciplina militar podrán ejercer este de-

14
recho sólo individualmente y con arreglo a lo dispuesto en su
legislación específica.

     Sección 2.ª De los derechos y deberes de los ciudadanos

ς  Artículo 30

   1. Los españoles tienen el derecho y el deber de defender a
España.

   2. La ley fijará las obligaciones militares de los españoles y
regulará, con las debidas garantías, la objeción de conciencia,
así como las demás causas de exención del servicio militar
obligatorio, pudiendo imponer, en su caso, una prestación so-
cial sustitutoria.

   3. Podrá establecerse un servicio civil para el cumplimiento
de fines de interés general.

   4. Mediante ley podrán regularse los deberes de los ciuda-
danos en los casos de grave riesgo, catástrofe o calamidad
pública.

ς  Artículo 31

   1. Todos contribuirán al sostenimiento de los gastos públicos
de acuerdo con su capacidad económica mediante un sistema
tributario justo inspirado en los principios de igualdad y progre-
sividad que, en ningún caso, tendrá alcance confiscatorio.

   2. El gasto público realizará una asignación equitativa de los
recursos públicos, y su programación y ejecución responderán
a los criterios de eficiencia y economía.

   3. Sólo podrán establecerse prestaciones personales o patri-
moniales de carácter público con arreglo a la ley.

ς  Artículo 32

   1. El hombre y la mujer tienen derecho a contraer matrimo-
nio con plena igualdad jurídica.

   2. La ley regulará las formas de matrimonio, la edad y capa-
cidad para contraerlo, los derechos y deberes de los cónyuges,
las causas de separación y disolución y sus efectos.

ς  Artículo 33

   1. Se reconoce el derecho a la propiedad privada y a la he-
rencia.

                                                                                                     15
   2. La función social de estos derechos delimitará su conte-
nido, de acuerdo con las leyes.

   3. Nadie podrá ser privado de sus bienes y derechos sino por
causa justificada de utilidad pública o interés social, mediante
la correspondiente indemnización y de conformidad con lo
dispuesto por las leyes.

ς  Artículo 34

   1. Se reconoce el derecho de fundación para fines de interés
general, con arreglo a la ley.

   2. Regirá también para las fundaciones lo dispuesto en los
apartados 2 y 4 del artículo 22.

ς  Artículo 35

   1. Todos los españoles tienen el deber de trabajar y el dere-
cho al trabajo, a la libre elección de profesión u oficio, a la
promoción a través del trabajo y a una remuneración suficien-
te para satisfacer sus necesidades y las de su familia, sin que en
ningún caso pueda hacerse discriminación por razón de sexo.

   2. La ley regulará un estatuto de los trabajadores.

ς  Artículo 36

   La ley regulará las peculiaridades propias del régimen jurídi-
co de los Colegios Profesionales y el ejercicio de las profesio-
nes tituladas. La estructura interna y el funcionamiento de los
Colegios deberán ser democráticos.

ς  Artículo 37

   1. La ley garantizará el derecho a la negociación colectiva
laboral entre los representantes de los trabajadores y empre-
sarios, así como la fuerza vinculante de los convenios.

   2. Se reconoce el derecho de los trabajadores y empresarios
a adoptar medidas de conflicto colectivo. La ley que regule el
ejercicio de este derecho, sin perjuicio de las limitaciones que
puedan establecer, incluirá las garantías precisas para asegurar
el funcionamiento de los servicios esenciales de la comunidad.

ς  Artículo 38
   Se reconoce la libertad de empresa en el marco de la eco-

nomía de mercado. Los poderes públicos garantizan y prote-

16
gen su ejercicio y la defensa de la productividad, de acuerdo
con las exigencias de la economía general y, en su caso, de la
planificación.

                            CAPÍTULO TERCERO
 De los principios rectores de la política social y económica

ς  Artículo 39

   1. Los poderes públicos aseguran la protección social, eco-
nómica y jurídica de la familia.

   2. Los poderes públicos aseguran, asimismo, la protección
integral de los hijos, iguales éstos ante la ley con independen-
cia de su filiación, y de las madres, cualquiera que sea su esta-
do civil. La ley posibilitará la investigación de la paternidad.

   3. Los padres deben prestar asistencia de todo orden a los
hijos habidos dentro o fuera del matrimonio, durante su mino-
ría de edad y en los demás casos en que legalmente proceda.

   4. Los niños gozarán de la protección prevista en los acuer-
dos internacionales que velan por sus derechos.

ς  Artículo 40
   1. Los poderes públicos promoverán las condiciones favora-

bles para el progreso social y económico y para una distribu-
ción de la renta regional y personal más equitativa, en el mar-
co de una política de estabilidad económica. De manera
especial realizarán una política orientada al pleno empleo.

   2. Asimismo, los poderes públicos fomentarán una política
que garantice la formación y readaptación profesionales; vela-
rán por la seguridad e higiene en el trabajo y garantizarán el
descanso necesario, mediante la limitación de la jornada labo-
ral, las vacaciones periódicas retribuidas y la promoción de
centros adecuados.

ς  Artículo 41
   Los poderes públicos mantendrán un régimen público de

Seguridad Social para todos los ciudadanos, que garantice la
asistencia y prestaciones sociales suficientes ante situaciones
de necesidad, especialmente en caso de desempleo. La asis-
tencia y prestaciones complementarias serán libres.

                                                                                                     17
ς  Artículo 42

   El Estado velará especialmente por la salvaguardia de los
derechos económicos y sociales de los trabajadores españoles
en el extranjero y orientará su política hacia su retorno.

ς  Artículo 43

   1. Se reconoce el derecho a la protección de la salud.
   2. Compete a los poderes públicos organizar y tutelar la sa-
lud pública a través de medidas preventivas y de las prestacio-
nes y servicios necesarios. La ley establecerá los derechos y
deberes de todos al respecto.
   3. Los poderes públicos fomentarán la educación sanitaria,
la educación física y el deporte. Asimismo facilitarán la ade-
cuada utilización del ocio.

ς  Artículo 44

   1. Los poderes públicos promoverán y tutelarán el acceso a
la cultura, a la que todos tienen derecho.

   2. Los poderes públicos promoverán la ciencia y la investi-
gación científica y técnica en beneficio del interés general.

ς  Artículo 45

   1. Todos tienen el derecho a disfrutar de un medio ambiente
adecuado para el desarrollo de la persona, así como el deber
de conservarlo.

   2. Los poderes públicos velarán por la utilización racional de
todos los recursos naturales, con el fin de proteger y mejorar
la calidad de la vida y defender y restaurar el medio ambiente,
apoyándose en la indispensable solidaridad colectiva.

   3. Para quienes violen lo dispuesto en el apartado anterior,
en los términos que la ley fije se establecerán sanciones pena-
les o, en su caso, administrativas, así como la obligación de
reparar el daño causado.

ς  Artículo 46

   Los poderes públicos garantizarán la conservación y promo-
verán el enriquecimiento del patrimonio histórico, cultural y
artístico de los pueblos de España y de los bienes que lo inte-
gran, cualquiera que sea su régimen jurídico y su titularidad. La
ley penal sancionará los atentados contra este patrimonio.

18
ς  Artículo 47

   Todos los españoles tienen derecho a disfrutar de una vi-
vienda digna y adecuada. Los poderes públicos promoverán
las condiciones necesarias y establecerán las normas pertinen-
tes para hacer efectivo este derecho, regulando la utilización
del suelo de acuerdo con el interés general para impedir la
especulación. La comunidad participará en las plusvalías que
genere la acción urbanística de los entes públicos.

ς  Artículo 48

   Los poderes públicos promoverán las condiciones para la
participación libre y eficaz de la juventud en el desarrollo polí-
tico, social, económico y cultural.

ς  Artículo 49

   1. Las personas con discapacidad ejercen los derechos pre-
vistos en este Título en condiciones de libertad e igualdad
reales y efectivas. Se regulará por ley la protección especial
que sea necesaria para dicho ejercicio.

   2. Los poderes públicos impulsarán las políticas que garan-
ticen la plena autonomía personal y la inclusión social de las
personas con discapacidad, en entornos universalmente acce-
sibles. Asimismo, fomentarán la participación de sus organiza-
ciones, en los términos que la ley establezca. Se atenderán
particularmente las necesidades específicas de las mujeres y
los menores con discapacidad.

ς  Artículo 50

   Los poderes públicos garantizarán, mediante pensiones ade-
cuadas y periódicamente actualizadas, la suficiencia económica
a los ciudadanos durante la tercera edad. Asimismo, y con inde-
pendencia de las obligaciones familiares, promoverán su bien-
estar mediante un sistema de servicios sociales que atenderán
sus problemas específicos de salud, vivienda, cultura y ocio.

ς  Artículo 51

   1. Los poderes públicos garantizarán la defensa de los con-
sumidores y usuarios, protegiendo, mediante procedimientos
eficaces, la seguridad, la salud y los legítimos intereses econó-
micos de los mismos.

                                                                                                     19
   2. Los poderes públicos promoverán la información y la
educación de los consumidores y usuarios, fomentarán sus
organizaciones y oirán a éstas en las cuestiones que puedan
afectar a aquéllos, en los términos que la ley establezca.

   3. En el marco de lo dispuesto por los apartados anteriores,
la ley regulará el comercio interior y el régimen de autoriza-
ción de productos comerciales.

ς  Artículo 52

   La ley regulará las organizaciones profesionales que contri-
buyan a la defensa de los intereses económicos que les sean
propios. Su estructura interna y funcionamiento deberán ser
democráticos.

                            CAPÍTULO CUARTO
De las garantías de las libertades y derechos fundamentales

ς  Artículo 53

   1. Los derechos y libertades reconocidos en el Capítulo segun-
do del presente Título vinculan a todos los poderes públicos. Sólo
por ley, que en todo caso deberá respetar su contenido esencial,
podrá regularse el ejercicio de tales derechos y libertades, que se
tutelarán de acuerdo con lo previsto en el artículo 161, 1, a).

   2. Cualquier ciudadano podrá recabar la tutela de las liber-
tades y derechos reconocidos en el artículo 14 y la Sección
primera del Capítulo segundo ante los Tribunales ordinarios
por un procedimiento basado en los principios de preferencia
y sumariedad y, en su caso, a través del recurso de amparo
ante el Tribunal Constitucional. Este último recurso será apli-
cable a la objeción de conciencia reconocida en el artículo 30.

   3. El reconocimiento, el respeto y la protección de los princi-
pios reconocidos en el Capítulo tercero informarán la legisla-
ción positiva, la práctica judicial y la actuación de los poderes
públicos. Sólo podrán ser alegados ante la Jurisdicción ordinaria
de acuerdo con lo que dispongan las leyes que los desarrollen.

ς  Artículo 54

   Una ley orgánica regulará la institución del Defensor del
Pueblo, como alto comisionado de las Cortes Generales, de-

20
signado por éstas para la defensa de los derechos comprendi-
dos en este Título, a cuyo efecto podrá supervisar la actividad
de la Administración, dando cuenta a las Cortes Generales.

                            CAPÍTULO QUINTO
          De la suspensión de los derechos y libertades

ς  Artículo 55

   1. Los derechos reconocidos en los artículos 17, 18, apartados
2 y 3, artículos 19, 20, apartados 1, a) y d), y 5, artículos 21, 28,
apartado 2, y artículo 37, apartado 2, podrán ser suspendidos
cuando se acuerde la declaración del estado de excepción o de
sitio en los términos previstos en la Constitución. Se exceptúa
de lo establecido anteriormente el apartado 3 del artículo 17
para el supuesto de declaración de estado de excepción.

   2. Una ley orgánica podrá determinar la forma y los casos en
los que, de forma individual y con la necesaria intervención
judicial y el adecuado control parlamentario, los derechos re-
conocidos en los artículos 17, apartado 2, y 18, apartados 2 y 3,
pueden ser suspendidos para personas determinadas, en rela-
ción con las investigaciones correspondientes a la actuación
de bandas armadas o elementos terroristas.

   La utilización injustificada o abusiva de las facultades reco-
nocidas en dicha ley orgánica producirá responsabilidad penal,
como violación de los derechos y libertades reconocidos por
las leyes.

                                    TÍTULO II
                                 De la Corona

ς  Artículo 56

   1. El Rey es el Jefe del Estado, símbolo de su unidad y per-
manencia, arbitra y modera el funcionamiento regular de las
instituciones, asume la más alta representación del Estado
español en las relaciones internacionales, especialmente con
las naciones de su comunidad histórica, y ejerce las funciones
que le atribuyen expresamente la Constitución y las leyes.

   2. Su título es el de Rey de España y podrá utilizar los demás
que correspondan a la Corona.

                                                                                                     21
   3. La persona del Rey es inviolable y no está sujeta a respon-
sabilidad. Sus actos estarán siempre refrendados en la forma
establecida en el artículo 64, careciendo de validez sin dicho
refrendo, salvo lo dispuesto en el artículo 65, 2.

ς  Artículo 57

   1. La Corona de España es hereditaria en los sucesores de S.
M. Don Juan Carlos I de Borbón, legítimo heredero de la di-
nastía histórica. La sucesión en el trono seguirá el orden regu-
lar de primogenitura y representación, siendo preferida siem-
pre la línea anterior a las posteriores; en la misma línea, el
grado más próximo al más remoto; en el mismo grado, el va-
rón a la mujer, y en el mismo sexo, la persona de más edad a
la de menos.

   2. El Príncipe heredero, desde su nacimiento o desde que se
produzca el hecho que origine el llamamiento, tendrá la dig-
nidad de Príncipe de Asturias y los demás títulos vinculados
tradicionalmente al sucesor de la Corona de España.

   3. Extinguidas todas las líneas llamadas en Derecho, las Cor-
tes Generales proveerán a la sucesión en la Corona en la forma
que más convenga a los intereses de España.

   4. Aquellas personas que teniendo derecho a la sucesión en
el trono contrajeren matrimonio contra la expresa prohibición
del Rey y de las Cortes Generales, quedarán excluidas en la
sucesión a la Corona por sí y sus descendientes.

   5. Las abdicaciones y renuncias y cualquier duda de hecho
o de derecho que ocurra en el orden de sucesión a la Corona
se resolverán por una ley orgánica.

ς  Artículo 58

   La Reina consorte o el consorte de la Reina no podrán asu-
mir funciones constitucionales, salvo lo dispuesto para la Re-
gencia.

ς  Artículo 59

   1. Cuando el Rey fuere menor de edad, el padre o la madre
del Rey y, en su defecto, el pariente mayor de edad más próxi-
mo a suceder en la Corona, según el orden establecido en la
Constitución, entrará a ejercer inmediatamente la Regencia y
la ejercerá durante el tiempo de la minoría de edad del Rey.

22
   2. Si el Rey se inhabilitare para el ejercicio de su autoridad y
la imposibilidad fuere reconocida por las Cortes Generales,
entrará a ejercer inmediatamente la Regencia el Príncipe here-
dero de la Corona, si fuere mayor de edad. Si no lo fuere, se
procederá de la manera prevista en el apartado anterior, hasta
que el Príncipe heredero alcance la mayoría de edad.

   3. Si no hubiere ninguna persona a quien corresponda la
Regencia, ésta será nombrada por las Cortes Generales, y se
compondrá de una, tres o cinco personas.

   4. Para ejercer la Regencia es preciso ser español y mayor de
edad.

   5. La Regencia se ejercerá por mandato constitucional y
siempre en nombre del Rey.

ς  Artículo 60

   1. Será tutor del Rey menor la persona que en su testamen-
to hubiese nombrado el Rey difunto, siempre que sea mayor
de edad y español de nacimiento; si no lo hubiese nombrado,
será tutor el padre o la madre mientras permanezcan viudos.
En su defecto, lo nombrarán las Cortes Generales, pero no
podrán acumularse los cargos de Regente y de tutor sino en el
padre, madre o ascendientes directos del Rey.

   2. El ejercicio de la tutela es también incompatible con el de
todo cargo o representación política.

ς  Artículo 61

   1. El Rey, al ser proclamado ante las Cortes Generales,
prestará juramento de desempeñar fielmente sus funciones,
guardar y hacer guardar la Constitución y las leyes y respe-
tar los derechos de los ciudadanos y de las Comunidades
Autónomas.

   2. El Príncipe heredero, al alcanzar la mayoría de edad, y el
Regente o Regentes al hacerse cargo de sus funciones, pres-
tarán el mismo juramento, así como el de fidelidad al Rey.

ς  Artículo 62

   Corresponde al Rey:

   a) Sancionar y promulgar las leyes.
   b) Convocar y disolver las Cortes Generales y convocar

      elecciones en los términos previstos en la Constitución.

                                                                                                     23
   c) Convocar a referéndum en los casos previstos en la Cons-
      titución.

   d) Proponer el candidato a Presidente del Gobierno y, en su
      caso, nombrarlo, así como poner fin a sus funciones en
      los términos previstos en la Constitución.

   e) Nombrar y separar a los miembros del Gobierno, a pro-
      puesta de su Presidente.

   f) Expedir los decretos acordados en el Consejo de Minis-
      tros, conferir los empleos civiles y militares y conceder
      honores y distinciones con arreglo a las leyes.

   g) Ser informado de los asuntos de Estado y presidir, a estos
      efectos, las sesiones del Consejo de Ministros, cuando lo
      estime oportuno, a petición del Presidente del Gobierno.

   h) El mando supremo de las Fuerzas Armadas.
   i) Ejercer el derecho de gracia con arreglo a la ley, que no

      podrá autorizar indultos generales.
   j) El Alto Patronazgo de las Reales Academias.

ς  Artículo 63

   1. El Rey acredita a los embajadores y otros representantes
diplomáticos. Los representantes extranjeros en España están
acreditados ante él.

   2. Al Rey corresponde manifestar el consentimiento del Es-
tado para obligarse internacionalmente por medio de tratados,
de conformidad con la Constitución y las leyes.

   3. Al Rey corresponde, previa autorización de las Cortes Ge-
nerales, declarar la guerra y hacer la paz.

ς  Artículo 64

   1. Los actos del Rey serán refrendados por el Presidente del
Gobierno y, en su caso, por los Ministros competentes. La pro-
puesta y el nombramiento del Presidente del Gobierno, y la
disolución prevista en el artículo 99, serán refrendados por el
Presidente del Congreso.

   2. De los actos del Rey serán responsables las personas que
los refrenden.

ς  Artículo 65

   1. El Rey recibe de los Presupuestos del Estado una cantidad
global para el sostenimiento de su Familia y Casa, y distribuye
libremente la misma.

24
   2. El Rey nombra y releva libremente a los miembros civiles
y militares de su Casa.

                                   TÍTULO III
                          De las Cortes Generales

                            CAPÍTULO PRIMERO
                                De las Cámaras

ς  Artículo 66

   1. Las Cortes Generales representan al pueblo español y es-
tán formadas por el Congreso de los Diputados y el Senado.

   2. Las Cortes Generales ejercen la potestad legislativa del
Estado, aprueban sus Presupuestos, controlan la acción del
Gobierno y tienen las demás competencias que les atribuya la
Constitución.

   3. Las Cortes Generales son inviolables.

ς  Artículo 67
   1. Nadie podrá ser miembro de las dos Cámaras simultánea-

mente, ni acumular el acta de una Asamblea de Comunidad
Autónoma con la de Diputado al Congreso.

   2. Los miembros de las Cortes Generales no estarán ligados
por mandato imperativo.

   3. Las reuniones de Parlamentarios que se celebren sin con-
vocatoria reglamentaria no vincularán a las Cámaras, y no po-
drán ejercer sus funciones ni ostentar sus privilegios.

ς  Artículo 68
   1. El Congreso se compone de un mínimo de 300 y un máxi-

mo de 400 Diputados, elegidos por sufragio universal, libre,
igual, directo y secreto, en los términos que establezca la ley.

   2. La circunscripción electoral es la provincia. Las poblaciones
de Ceuta y Melilla estarán representadas cada una de ellas por un
Diputado. La ley distribuirá el número total de Diputados, asig-
nando una representación mínima inicial a cada circunscripción
y distribuyendo los demás en proporción a la población.

   3. La elección se verificará en cada circunscripción aten-
diendo a criterios de representación proporcional.

                                                                                                     25
   4. El Congreso es elegido por cuatro años. El mandato de
los Diputados termina cuatro años después de su elección o el
día de la disolución de la Cámara.

   5. Son electores y elegibles todos los españoles que estén
en pleno uso de sus derechos políticos.

   La ley reconocerá y el Estado facilitará el ejercicio del dere-
cho de sufragio a los españoles que se encuentren fuera del
territorio de España.

   6. Las elecciones tendrán lugar entre los treinta días y se-
senta días desde la terminación del mandato. El Congreso
electo deberá ser convocado dentro de los veinticinco días
siguientes a la celebración de las elecciones.

ς  Artículo 69

   1. El Senado es la Cámara de representación territorial.
   2. En cada provincia se elegirán cuatro Senadores por sufra-
gio universal, libre, igual, directo y secreto por los votantes de
cada una de ellas, en los términos que señale una ley orgánica.
   3. En las provincias insulares, cada isla o agrupación de ellas,
con Cabildo o Consejo Insular, constituirá una circunscripción
a efectos de elección de Senadores, correspondiendo tres a
cada una de las islas mayores –Gran Canaria, Mallorca y Tene-
rife– y uno a cada una de las siguientes islas o agrupaciones:
Ibiza-Formentera, Menorca, Fuerteventura, Gomera, Hierro,
Lanzarote y La Palma.
   4. Las poblaciones de Ceuta y Melilla elegirán cada una de
ellas dos Senadores.
   5. Las Comunidades Autónomas designarán además un Senador
y otro más por cada millón de habitantes de su respectivo territo-
rio. La designación corresponderá a la Asamblea legislativa o, en su
defecto, al órgano colegiado superior de la Comunidad Autónoma,
de acuerdo con lo que establezcan los Estatutos, que asegurarán,
en todo caso, la adecuada representación proporcional.
   6. El Senado es elegido por cuatro años. El mandato de los
Senadores termina cuatro años después de su elección o el día
de la disolución de la Cámara.

ς  Artículo 70

   1. La ley electoral determinará las causas de inelegibilidad e
incompatibilidad de los Diputados y Senadores, que compren-
derán, en todo caso:

26
     a)	A los componentes del Tribunal Constitucional.
     b)	A los altos cargos de la Administración del Estado que

         determine la ley, con la excepción de los miembros del
         Gobierno.
     c)	Al Defensor del Pueblo.
     d)	A los Magistrados, Jueces y Fiscales en activo.
     e)	A los militares profesionales y miembros de las Fuerzas
         y Cuerpos de Seguridad y Policía en activo.
     f)	A los miembros de las Juntas Electorales.

   2. La validez de las actas y credenciales de los miembros de
ambas Cámaras estará sometida al control judicial, en los tér-
minos que establezca la ley electoral.

ς  Artículo 71

   1. Los Diputados y Senadores gozarán de inviolabilidad por
las opiniones manifestadas en el ejercicio de sus funciones.

   2. Durante el período de su mandato los Diputados y Sena-
dores gozarán asimismo de inmunidad y sólo podrán ser de-
tenidos en caso de flagrante delito. No podrán ser inculpados
ni procesados sin la previa autorización de la Cámara respec-
tiva.

   3. En las causas contra Diputados y Senadores será compe-
tente la Sala de lo Penal del Tribunal Supremo.

   4. Los Diputados y Senadores percibirán una asignación que
será fijada por las respectivas Cámaras.

ς  Artículo 72

   1. Las Cámaras establecen sus propios Reglamentos, aprue-
ban autónomamente sus presupuestos y, de común acuerdo,
regulan el Estatuto del Personal de las Cortes Generales. Los
Reglamentos y su reforma serán sometidos a una votación fi-
nal sobre su totalidad, que requerirá la mayoría absoluta.

   2. Las Cámaras eligen sus respectivos Presidentes y los de-
más miembros de sus Mesas. Las sesiones conjuntas serán
presididas por el Presidente del Congreso y se regirán por un
Reglamento de las Cortes Generales aprobado por mayoría
absoluta de cada Cámara.

   3. Los Presidentes de las Cámaras ejercen en nombre de las
mismas todos los poderes administrativos y facultades de po-
licía en el interior de sus respectivas sedes.

                                                                                                     27
ς  Artículo 73

   1. Las Cámaras se reunirán anualmente en dos períodos or-
dinarios de sesiones: el primero, de septiembre a diciembre, y
el segundo, de febrero a junio.

   2. Las Cámaras podrán reunirse en sesiones extraordinarias
a petición del Gobierno, de la Diputación Permanente o de la
mayoría absoluta de los miembros de cualquiera de las Cáma-
ras. Las sesiones extraordinarias deberán convocarse sobre un
orden del día determinado y serán clausuradas una vez que
éste haya sido agotado.

ς  Artículo 74

   1. Las Cámaras se reunirán en sesión conjunta para ejercer
las competencias no legislativas que el Título II atribuye expre-
samente a las Cortes Generales.

   2. Las decisiones de las Cortes Generales previstas en los artí-
culos 94, 1, 145, 2 y 158, 2, se adoptarán por mayoría de cada una
de las Cámaras. En el primer caso, el procedimiento se iniciará
por el Congreso, y en los otros dos, por el Senado. En ambos
casos, si no hubiera acuerdo entre Senado y Congreso, se inten-
tará obtener por una Comisión Mixta compuesta de igual núme-
ro de Diputados y Senadores. La Comisión presentará un texto
que será votado por ambas Cámaras. Si no se aprueba en la forma
establecida, decidirá el Congreso por mayoría absoluta.

ς  Artículo 75

   1. Las Cámaras funcionarán en Pleno y por Comisiones.
   2. Las Cámaras podrán delegar en las Comisiones Legislati-
vas Permanentes la aprobación de proyectos o proposiciones
de ley. El Pleno podrá, no obstante, recabar en cualquier mo-
mento el debate y votación de cualquier proyecto o proposi-
ción de ley que haya sido objeto de esta delegación.
   3. Quedan exceptuados de lo dispuesto en el apartado an-
terior la reforma constitucional, las cuestiones internacionales,
las leyes orgánicas y de bases y los Presupuestos Generales del
Estado.

ς  Artículo 76

   1. El Congreso y el Senado, y, en su caso, ambas Cámaras
conjuntamente, podrán nombrar Comisiones de investigación

28
sobre cualquier asunto de interés público. Sus conclusiones no
serán vinculantes para los Tribunales, ni afectarán a las resolu-
ciones judiciales, sin perjuicio de que el resultado de la inves-
tigación sea comunicado al Ministerio Fiscal para el ejercicio,
cuando proceda, de las acciones oportunas.

   2. Será obligatorio comparecer a requerimiento de las Cá-
maras. La ley regulará las sanciones que puedan imponerse
por incumplimiento de esta obligación.

ς  Artículo 77

   1. Las Cámaras pueden recibir peticiones individuales y co-
lectivas, siempre por escrito, quedando prohibida la presenta-
ción directa por manifestaciones ciudadanas.

   2. Las Cámaras pueden remitir al Gobierno las peticiones
que reciban. El Gobierno está obligado a explicarse sobre su
contenido, siempre que las Cámaras lo exijan.

ς  Artículo 78

   1. En cada Cámara habrá una Diputación Permanente com-
puesta por un mínimo de veintiún miembros, que representa-
rán a los grupos parlamentarios, en proporción a su importan-
cia numérica.

   2. Las Diputaciones Permanentes estarán presididas por el
Presidente de la Cámara respectiva y tendrán como funciones
la prevista en el artículo 73, la de asumir las facultades que
correspondan a las Cámaras, de acuerdo con los artículos 86
y 116, en caso de que éstas hubieren sido disueltas o hubiere
expirado su mandato y la de velar por los poderes de las Cá-
maras cuando éstas no estén reunidas.

   3. Expirado el mandato o en caso de disolución, las Diputa-
ciones Permanentes seguirán ejerciendo sus funciones hasta
la constitución de las nuevas Cortes Generales.

   4. Reunida la Cámara correspondiente, la Diputación Per-
manente dará cuenta de los asuntos tratados y de sus decisio-
nes.

ς  Artículo 79

   1. Para adoptar acuerdos, las Cámaras deben estar reunidas
reglamentariamente y con asistencia de la mayoría de sus
miembros.

                                                                                                     29
   2. Dichos acuerdos, para ser válidos, deberán ser aprobados
por la mayoría de los miembros presentes, sin perjuicio de las
mayorías especiales que establezcan la Constitución o las le-
yes orgánicas y las que para elección de personas establezcan
los Reglamentos de las Cámaras.

   3. El voto de Senadores y Diputados es personal e indelega-
ble.

ς  Artículo 80

   Las sesiones plenarias de las Cámaras serán públicas, salvo
acuerdo en contrario de cada Cámara, adoptado por mayoría
absoluta o con arreglo al Reglamento.

                           CAPÍTULO SEGUNDO
                     De la elaboración de las leyes

ς  Artículo 81

   1. Son leyes orgánicas las relativas al desarrollo de los dere-
chos fundamentales y de las libertades públicas, las que aprue-
ben los Estatutos de Autonomía y el régimen electoral general
y las demás previstas en la Constitución.

   2. La aprobación, modificación o derogación de las leyes
orgánicas exigirá mayoría absoluta del Congreso, en una vota-
ción final sobre el conjunto del proyecto.

ς  Artículo 82
   1. Las Cortes Generales podrán delegar en el Gobierno la

potestad de dictar normas con rango de ley sobre materias
determinadas no incluidas en el artículo anterior.

   2. La delegación legislativa deberá otorgarse mediante una
ley de bases cuando su objeto sea la formación de textos arti-
culados o por una ley ordinaria cuando se trate de refundir
varios textos legales en uno solo.

   3. La delegación legislativa habrá de otorgarse al Gobierno de
forma expresa para materia concreta y con fijación del plazo
para su ejercicio. La delegación se agota por el uso que de ella
haga el Gobierno mediante la publicación de la norma corres-
pondiente. No podrá entenderse concedida de modo implícito
o por tiempo indeterminado. Tampoco podrá permitir la subde-
legación a autoridades distintas del propio Gobierno.

30
   4. Las leyes de bases delimitarán con precisión el objeto y
alcance de la delegación legislativa y los principios y criterios
que han de seguirse en su ejercicio.

   5. La autorización para refundir textos legales determinará el
ámbito normativo a que se refiere el contenido de la delega-
ción, especificando si se circunscribe a la mera formulación de
un texto único o si se incluye la de regularizar, aclarar y armo-
nizar los textos legales que han de ser refundidos.

   6. Sin perjuicio de la competencia propia de los Tribunales,
las leyes de delegación podrán establecer en cada caso fór-
mulas adicionales de control.

ς  Artículo 83

   Las leyes de bases no podrán en ningún caso:

   a) Autorizar la modificación de la propia ley de bases.
   b) Facultar para dictar normas con carácter retroactivo.

ς  Artículo 84

   Cuando una proposición de ley o una enmienda fuere con-
traria a una delegación legislativa en vigor, el Gobierno está
facultado para oponerse a su tramitación. En tal supuesto,
podrá presentarse una proposición de ley para la derogación
total o parcial de la ley de delegación.

ς  Artículo 85

   Las disposiciones del Gobierno que contengan legislación
delegada recibirán el título de Decretos Legislativos.

ς  Artículo 86

   1. En caso de extraordinaria y urgente necesidad, el Gobier-
no podrá dictar disposiciones legislativas provisionales que
tomarán la forma de Decretos-leyes y que no podrán afectar
al ordenamiento de las instituciones básicas del Estado, a los
derechos, deberes y libertades de los ciudadanos regulados en
el Título I, al régimen de las Comunidades Autónomas ni al
Derecho electoral general.

   2. Los Decretos-leyes deberán ser inmediatamente someti-
dos a debate y votación de totalidad al Congreso de los Dipu-
tados, convocado al efecto si no estuviere reunido, en el plazo
de los treinta días siguientes a su promulgación. El Congreso

                                                                                                     31
habrá de pronunciarse expresamente dentro de dicho plazo
sobre su convalidación o derogación, para lo cual el Regla-
mento establecerá un procedimiento especial y sumario.

   3. Durante el plazo establecido en el apartado anterior, las
Cortes podrán tramitarlos como proyectos de ley por el pro-
cedimiento de urgencia.

ς  Artículo 87

   1. La iniciativa legislativa corresponde al Gobierno, al Con-
greso y al Senado, de acuerdo con la Constitución y los Regla-
mentos de las Cámaras.

   2. Las Asambleas de las Comunidades Autónomas podrán
solicitar del Gobierno la adopción de un proyecto de ley o
remitir a la Mesa del Congreso una proposición de ley, dele-
gando ante dicha Cámara un máximo de tres miembros de la
Asamblea encargados de su defensa.

   3. Una ley orgánica regulará las formas de ejercicio y requi-
sitos de la iniciativa popular para la presentación de proposi-
ciones de ley. En todo caso se exigirán no menos de 500.000
firmas acreditadas. No procederá dicha iniciativa en materias
propias de ley orgánica, tributarias o de carácter internacional,
ni en lo relativo a la prerrogativa de gracia.

ς  Artículo 88

   Los proyectos de ley serán aprobados en Consejo de Minis-
tros, que los someterá al Congreso, acompañados de una ex-
posición de motivos y de los antecedentes necesarios para
pronunciarse sobre ellos.

ς  Artículo 89

   1. La tramitación de las proposiciones de ley se regulará por
los Reglamentos de las Cámaras, sin que la prioridad debida a
los proyectos de ley impida el ejercicio de la iniciativa legisla-
tiva en los términos regulados por el artículo 87.

   2. Las proposiciones de ley que, de acuerdo con el artículo
87, tome en consideración el Senado, se remitirán al Congreso
para su trámite en éste como tal proposición.

ς  Artículo 90

   1. Aprobado un proyecto de ley ordinaria u orgánica por el
Congreso de los Diputados, su Presidente dará inmediata

32
cuenta del mismo al Presidente del Senado, el cual lo somete-
rá a la deliberación de éste.

   2. El Senado en el plazo de dos meses, a partir del día de la
recepción del texto, puede, mediante mensaje motivado, opo-
ner su veto o introducir enmiendas al mismo. El veto deberá
ser aprobado por mayoría absoluta. El proyecto no podrá ser
sometido al Rey para sanción sin que el Congreso ratifique por
mayoría absoluta, en caso de veto, el texto inicial, o por ma-
yoría simple, una vez transcurridos dos meses desde la inter-
posición del mismo, o se pronuncie sobre las enmiendas,
aceptándolas o no por mayoría simple.

   3. El plazo de dos meses de que el Senado dispone para
vetar o enmendar el proyecto se reducirá al de veinte días na-
turales en los proyectos declarados urgentes por el Gobierno
o por el Congreso de los Diputados.

ς  Artículo 91

   El Rey sancionará en el plazo de quince días las leyes apro-
badas por las Cortes Generales, y las promulgará y ordenará su
inmediata publicación.

ς  Artículo 92

   1. Las decisiones políticas de especial trascendencia podrán
ser sometidas a referéndum consultivo de todos los ciudada-
nos.

   2. El referéndum será convocado por el Rey, mediante pro-
puesta del Presidente del Gobierno, previamente autorizada
por el Congreso de los Diputados.

   3. Una ley orgánica regulará las condiciones y el procedi-
miento de las distintas modalidades de referéndum previstas
en esta Constitución.

                            CAPÍTULO TERCERO
                    De los Tratados Internacionales

ς  Artículo 93

   Mediante ley orgánica se podrá autorizar la celebración de
tratados por los que se atribuya a una organización o institu-
ción internacional el ejercicio de competencias derivadas de la
Constitución. Corresponde a las Cortes Generales o al Gobier-

                                                                                                     33
no, según los casos, la garantía del cumplimiento de estos
tratados y de las resoluciones emanadas de los organismos
internacionales o supranacionales titulares de la cesión.

ς  Artículo 94

   1. La prestación del consentimiento del Estado para obligar-
se por medio de tratados o convenios requerirá la previa auto-
rización de las Cortes Generales, en los siguientes casos:

     a)	Tratados de carácter político.
     b)	T ratados o convenios de carácter militar.
     c)	T ratados o convenios que afecten a la integridad terri-

         torial del Estado o a los derechos y deberes fundamen-
         tales establecidos en el Título I.
     d)	T ratados o convenios que impliquen obligaciones fi-
         nancieras para la Hacienda Pública.
     e)	T ratados o convenios que supongan modificación o
         derogación de alguna ley o exijan medidas legislativas
         para su ejecución.

   2. El Congreso y el Senado serán inmediatamente informa-
dos de la conclusión de los restantes tratados o convenios.

ς  Artículo 95

   1. La celebración de un tratado internacional que contenga
estipulaciones contrarias a la Constitución exigirá la previa re-
visión constitucional.

   2. El Gobierno o cualquiera de las Cámaras puede requerir
al Tribunal Constitucional para que declare si existe o no esa
contradicción.

ς  Artículo 96

   1. Los tratados internacionales válidamente celebrados, una
vez publicados oficialmente en España, formarán parte del or-
denamiento interno. Sus disposiciones sólo podrán ser dero-
gadas, modificadas o suspendidas en la forma prevista en los
propios tratados o de acuerdo con las normas generales del
Derecho internacional.

   2. Para la denuncia de los tratados y convenios internacio-
nales se utilizará el mismo procedimiento previsto para su
aprobación en el artículo 94.

34
                                   TÍTULO IV

                 Del Gobierno y de la Administración

ς  Artículo 97

   El Gobierno dirige la política interior y exterior, la Adminis-
tración civil y militar y la defensa del Estado. Ejerce la función
ejecutiva y la potestad reglamentaria de acuerdo con la Cons-
titución y las leyes.

ς  Artículo 98

   1. El Gobierno se compone del Presidente, de los Vicepresi-
dentes, en su caso, de los Ministros y de los demás miembros
que establezca la ley.

   2. El Presidente dirige la acción del Gobierno y coordina las
funciones de los demás miembros del mismo, sin perjuicio de la
competencia y responsabilidad directa de éstos en su gestión.

   3. Los miembros del Gobierno no podrán ejercer otras fun-
ciones representativas que las propias del mandato parlamen-
tario, ni cualquier otra función pública que no derive de su
cargo, ni actividad profesional o mercantil alguna.

   4. La ley regulará el estatuto e incompatibilidades de los
miembros del Gobierno.

ς  Artículo 99

   1. Después de cada renovación del Congreso de los Diputa-
dos, y en los demás supuestos constitucionales en que así
proceda, el Rey, previa consulta con los representantes desig-
nados por los Grupos políticos con representación parlamen-
taria, y a través del Presidente del Congreso, propondrá un
candidato a la Presidencia del Gobierno.

   2. El candidato propuesto conforme a lo previsto en el apar-
tado anterior expondrá ante el Congreso de los Diputados el
programa político del Gobierno que pretenda formar y solici-
tará la confianza de la Cámara.

   3. Si el Congreso de los Diputados, por el voto de la mayoría
absoluta de sus miembros, otorgare su confianza a dicho can-
didato, el Rey le nombrará Presidente. De no alcanzarse dicha
mayoría, se someterá la misma propuesta a nueva votación
cuarenta y ocho horas después de la anterior, y la confianza se
entenderá otorgada si obtuviere la mayoría simple.

                                                                                                     35
   4. Si efectuadas las citadas votaciones no se otorgase la
confianza para la investidura, se tramitarán sucesivas propues-
tas en la forma prevista en los apartados anteriores.

   5. Si transcurrido el plazo de dos meses, a partir de la prime-
ra votación de investidura, ningún candidato hubiere obtenido
la confianza del Congreso, el Rey disolverá ambas Cámaras y
convocará nuevas elecciones con el refrendo del Presidente
del Congreso.

ς  Artículo 100

   Los demás miembros del Gobierno serán nombrados y se-
parados por el Rey, a propuesta de su Presidente.

ς  Artículo 101

   1. El Gobierno cesa tras la celebración de elecciones gene-
rales, en los casos de pérdida de la confianza parlamentaria
previstos en la Constitución, o por dimisión o fallecimiento de
su Presidente.

   2. El Gobierno cesante continuará en funciones hasta la
toma de posesión del nuevo Gobierno.

ς  Artículo 102

   1. La responsabilidad criminal del Presidente y los demás
miembros del Gobierno será exigible, en su caso, ante la Sala
de lo Penal del Tribunal Supremo.

   2. Si la acusación fuere por traición o por cualquier delito
contra la seguridad del Estado en el ejercicio de sus funciones,
sólo podrá ser planteada por iniciativa de la cuarta parte de los
miembros del Congreso, y con la aprobación de la mayoría
absoluta del mismo.

   3. La prerrogativa real de gracia no será aplicable a ninguno
de los supuestos del presente artículo.

ς  Artículo 103

   1. La Administración Pública sirve con objetividad los intere-
ses generales y actúa de acuerdo con los principios de eficacia,
jerarquía, descentralización, desconcentración y coordinación,
con sometimiento pleno a la ley y al Derecho.

   2. Los órganos de la Administración del Estado son creados,
regidos y coordinados de acuerdo con la ley.

36
   3. La ley regulará el estatuto de los funcionarios públicos,
el acceso a la función pública de acuerdo con los principios
de mérito y capacidad, las peculiaridades del ejercicio de su
derecho a sindicación, el sistema de incompatibilidades y
las garantías para la imparcialidad en el ejercicio de sus fun-
ciones.

ς  Artículo 104

   1. Las Fuerzas y Cuerpos de seguridad, bajo la dependencia
del Gobierno, tendrán como misión proteger el libre ejercicio
de los derechos y libertades y garantizar la seguridad ciudadana.

   2. Una ley orgánica determinará las funciones, principios
básicos de actuación y estatutos de las Fuerzas y Cuerpos de
seguridad.

ς  Artículo 105

   La ley regulará:

   a) La audiencia de los ciudadanos, directamente o a través
      de las organizaciones y asociaciones reconocidas por la
      ley, en el procedimiento de elaboración de las disposicio-
      nes administrativas que les afecten.

   b) El acceso de los ciudadanos a los archivos y registros ad-
      ministrativos, salvo en lo que afecte a la seguridad y de-
      fensa del Estado, la averiguación de los delitos y la intimi-
      dad de las personas.

   c) El procedimiento a través del cual deben producirse los
      actos administrativos, garantizando, cuando proceda, la
      audiencia del interesado.

ς  Artículo 106

   1. Los Tribunales controlan la potestad reglamentaria y la
legalidad de la actuación administrativa, así como el someti-
miento de ésta a los fines que la justifican.

   2. Los particulares, en los términos establecidos por la ley,
tendrán derecho a ser indemnizados por toda lesión que su-
fran en cualquiera de sus bienes y derechos, salvo en los casos
de fuerza mayor, siempre que la lesión sea consecuencia del
funcionamiento de los servicios públicos.

                                                                                                     37
ς  Artículo 107
   El Consejo de Estado es el supremo órgano consultivo del

Gobierno. Una ley orgánica regulará su composición y com-
petencia.

                                    TÍTULO V
 De las relaciones entre el Gobierno y las Cortes Generales

ς  Artículo 108
   El Gobierno responde solidariamente en su gestión política

ante el Congreso de los Diputados.

ς  Artículo 109
   Las Cámaras y sus Comisiones podrán recabar, a través de

los Presidentes de aquéllas, la información y ayuda que preci-
sen del Gobierno y de sus Departamentos y de cualesquiera
autoridades del Estado y de las Comunidades Autónomas.

ς  Artículo 110
   1. Las Cámaras y sus Comisiones pueden reclamar la pre-

sencia de los miembros del Gobierno.
   2. Los miembros del Gobierno tienen acceso a las sesiones

de las Cámaras y a sus Comisiones y la facultad de hacerse oír
en ellas, y podrán solicitar que informen ante las mismas fun-
cionarios de sus Departamentos.

ς  Artículo 111
   1. El Gobierno y cada uno de sus miembros están sometidos

a las interpelaciones y preguntas que se le formulen en las
Cámaras. Para esta clase de debate los Reglamentos estable-
cerán un tiempo mínimo semanal.

   2. Toda interpelación podrá dar lugar a una moción en la
que la Cámara manifieste su posición.

ς  Artículo 112
   El Presidente del Gobierno, previa deliberación del Consejo

de Ministros, puede plantear ante el Congreso de los Diputa-
dos la cuestión de confianza sobre su programa o sobre una
declaración de política general. La confianza se entenderá

38
otorgada cuando vote a favor de la misma la mayoría simple
de los Diputados.

ς  Artículo 113

   1. El Congreso de los Diputados puede exigir la responsabi-
lidad política del Gobierno mediante la adopción por mayoría
absoluta de la moción de censura.

   2. La moción de censura deberá ser propuesta al menos por
la décima parte de los Diputados, y habrá de incluir un candi-
dato a la Presidencia del Gobierno.

   3. La moción de censura no podrá ser votada hasta que
transcurran cinco días desde su presentación. En los dos pri-
meros días de dicho plazo podrán presentarse mociones alter-
nativas.

   4. Si la moción de censura no fuere aprobada por el Con-
greso, sus signatarios no podrán presentar otra durante el mis-
mo período de sesiones.

ς  Artículo 114

   1. Si el Congreso niega su confianza al Gobierno, éste pre-
sentará su dimisión al Rey, procediéndose a continuación a la
designación de Presidente del Gobierno, según lo dispuesto en
el artículo 99.

   2. Si el Congreso adopta una moción de censura, el Gobier-
no presentará su dimisión al Rey y el candidato incluido en
aquélla se entenderá investido de la confianza de la Cámara a
los efectos previstos en el artículo 99. El Rey le nombrará Pre-
sidente del Gobierno.

ς  Artículo 115

   1. El Presidente del Gobierno, previa deliberación del Con-
sejo de Ministros, y bajo su exclusiva responsabilidad, podrá
proponer la disolución del Congreso, del Senado o de las Cor-
tes Generales, que será decretada por el Rey. El decreto de
disolución fijará la fecha de las elecciones.

   2. La propuesta de disolución no podrá presentarse cuando
esté en trámite una moción de censura.

   3. No procederá nueva disolución antes de que transcurra
un año desde la anterior, salvo lo dispuesto en el artículo 99,
apartado 5.

                                                                                                     39
ς  Artículo 116

   1. Una ley orgánica regulará los estados de alarma, de ex-
cepción y de sitio, y las competencias y limitaciones corres-
pondientes.

   2. El estado de alarma será declarado por el Gobierno me-
diante decreto acordado en Consejo de Ministros por un plazo
máximo de quince días, dando cuenta al Congreso de los Di-
putados, reunido inmediatamente al efecto y sin cuya autori-
zación no podrá ser prorrogado dicho plazo. El decreto deter-
minará el ámbito territorial a que se extienden los efectos de
la declaración.

   3. El estado de excepción será declarado por el Gobierno
mediante decreto acordado en Consejo de Ministros, previa
autorización del Congreso de los Diputados. La autorización y
proclamación del estado de excepción deberá determinar ex-
presamente los efectos del mismo, el ámbito territorial a que
se extiende y su duración, que no podrá exceder de treinta
días, prorrogables por otro plazo igual, con los mismos requi-
sitos.

   4. El estado de sitio será declarado por la mayoría absoluta
del Congreso de los Diputados, a propuesta exclusiva del Go-
bierno. El Congreso determinará su ámbito territorial, duración
y condiciones.

   5. No podrá procederse a la disolución del Congreso mien-
tras estén declarados algunos de los estados comprendidos en
el presente artículo, quedando automáticamente convocadas
las Cámaras si no estuvieren en período de sesiones. Su fun-
cionamiento, así como el de los demás poderes constitucio-
nales del Estado, no podrán interrumpirse durante la vigencia
de estos estados.

   Disuelto el Congreso o expirado su mandato, si se produje-
re alguna de las situaciones que dan lugar a cualquiera de di-
chos estados, las competencias del Congreso serán asumidas
por su Diputación Permanente.

   6. La declaración de los estados de alarma, de excepción y
de sitio no modificarán el principio de responsabilidad del Go-
bierno y de sus agentes reconocidos en la Constitución y en
las leyes.

40
                                   TÍTULO VI
                             Del Poder Judicial

ς  Artículo 117

   1. La justicia emana del pueblo y se administra en nombre
del Rey por Jueces y Magistrados integrantes del poder judi-
cial, independientes, inamovibles, responsables y sometidos
únicamente al imperio de la ley.

   2. Los Jueces y Magistrados no podrán ser separados, sus-
pendidos, trasladados ni jubilados, sino por alguna de las cau-
sas y con las garantías previstas en la ley.

   3. El ejercicio de la potestad jurisdiccional en todo tipo de
procesos, juzgando y haciendo ejecutar lo juzgado, corres-
ponde exclusivamente a los Juzgados y Tribunales determina-
dos por las leyes, según las normas de competencia y proce-
dimiento que las mismas establezcan.

   4. Los Juzgados y Tribunales no ejercerán más funciones que
las señaladas en el apartado anterior y las que expresamente les
sean atribuidas por ley en garantía de cualquier derecho.

   5. El principio de unidad jurisdiccional es la base de la orga-
nización y funcionamiento de los Tribunales. La ley regulará el
ejercicio de la jurisdicción militar en el ámbito estrictamente
castrense y en los supuestos de estado de sitio, de acuerdo
con los principios de la Constitución.

   6. Se prohíben los Tribunales de excepción.

ς  Artículo 118

   Es obligado cumplir las sentencias y demás resoluciones
firmes de los Jueces y Tribunales, así como prestar la colabo-
ración requerida por éstos en el curso del proceso y en la eje-
cución de lo resuelto.

ς  Artículo 119

   La justicia será gratuita cuando así lo disponga la ley y, en
todo caso, respecto de quienes acrediten insuficiencia de re-
cursos para litigar.

ς  Artículo 120

   1. Las actuaciones judiciales serán públicas, con las excep-
ciones que prevean las leyes de procedimiento.

                                                                                                     41
   2. El procedimiento será predominantemente oral, sobre
todo en materia criminal.

   3. Las sentencias serán siempre motivadas y se pronunciarán
en audiencia pública.

ς  Artículo 121

   Los daños causados por error judicial, así como los que sean
consecuencia del funcionamiento anormal de la Administra-
ción de Justicia, darán derecho a una indemnización a cargo
del Estado, conforme a la ley.

ς  Artículo 122

   1. La ley orgánica del poder judicial determinará la constitu-
ción, funcionamiento y gobierno de los Juzgados y Tribunales,
así como el estatuto jurídico de los Jueces y Magistrados de
carrera, que formarán un Cuerpo único, y del personal al ser-
vicio de la Administración de Justicia.

   2. El Consejo General del Poder Judicial es el órgano de go-
bierno del mismo. La ley orgánica establecerá su estatuto y el
régimen de incompatibilidades de sus miembros y sus funcio-
nes, en particular en materia de nombramientos, ascensos,
inspección y régimen disciplinario.

   3. El Consejo General del Poder Judicial estará integrado
por el Presidente del Tribunal Supremo, que lo presidirá, y por
veinte miembros nombrados por el Rey por un período de cin-
co años. De éstos, doce entre Jueces y Magistrados de todas
las categorías judiciales, en los términos que establezca la ley
orgánica; cuatro a propuesta del Congreso de los Diputados, y
cuatro a propuesta del Senado, elegidos en ambos casos por
mayoría de tres quintos de sus miembros, entre abogados y
otros juristas, todos ellos de reconocida competencia y con
más de quince años de ejercicio en su profesión.

ς  Artículo 123

   1. El Tribunal Supremo, con jurisdicción en toda España, es
el órgano jurisdiccional superior en todos los órdenes, salvo lo
dispuesto en materia de garantías constitucionales.

   2. El Presidente del Tribunal Supremo será nombrado por el
Rey, a propuesta del Consejo General del Poder Judicial, en la
forma que determine la ley.

42
ς  Artículo 124

   1. El Ministerio Fiscal, sin perjuicio de las funciones enco-
mendadas a otros órganos, tiene por misión promover la ac-
ción de la justicia en defensa de la legalidad, de los derechos
de los ciudadanos y del interés público tutelado por la ley, de
oficio o a petición de los interesados, así como velar por la
independencia de los Tribunales y procurar ante éstos la satis-
facción del interés social.

   2. El Ministerio Fiscal ejerce sus funciones por medio de ór-
ganos propios conforme a los principios de unidad de actua-
ción y dependencia jerárquica y con sujeción, en todo caso, a
los de legalidad e imparcialidad.

   3. La ley regulará el estatuto orgánico del Ministerio Fiscal.
   4. El Fiscal General del Estado será nombrado por el Rey, a
propuesta del Gobierno, oído el Consejo General del Poder
Judicial.

ς  Artículo 125

   Los ciudadanos podrán ejercer la acción popular y participar
en la Administración de Justicia mediante la institución del
Jurado, en la forma y con respecto a aquellos procesos pena-
les que la ley determine, así como en los Tribunales consuetu-
dinarios y tradicionales.

ς  Artículo 126

   La policía judicial depende de los Jueces, de los Tribunales y
del Ministerio Fiscal en sus funciones de averiguación del de-
lito y descubrimiento y aseguramiento del delincuente, en los
términos que la ley establezca.

ς  Artículo 127

   1. Los Jueces y Magistrados así como los Fiscales, mientras
se hallen en activo, no podrán desempeñar otros cargos públi-
cos, ni pertenecer a partidos políticos o sindicatos. La ley es-
tablecerá el sistema y modalidades de asociación profesional
de los Jueces, Magistrados y Fiscales.

   2. La ley establecerá el régimen de incompatibilidades de los
miembros del poder judicial, que deberá asegurar la total inde-
pendencia de los mismos.

                                                                                                     43
                                   TÍTULO VII
                           Economía y Hacienda

ς  Artículo 128

   1. Toda la riqueza del país en sus distintas formas y sea cual
fuere su titularidad está subordinada al interés general.

   2. Se reconoce la iniciativa pública en la actividad económi-
ca. Mediante ley se podrá reservar al sector público recursos o
servicios esenciales, especialmente en caso de monopolio y
asimismo acordar la intervención de empresas cuando así lo
exigiere el interés general.

ς  Artículo 129

   1. La ley establecerá las formas de participación de los inte-
resados en la Seguridad Social y en la actividad de los organis-
mos públicos cuya función afecte directamente a la calidad de
la vida o al bienestar general.

   2. Los poderes públicos promoverán eficazmente las diver-
sas formas de participación en la empresa y fomentarán, me-
diante una legislación adecuada, las sociedades cooperativas.
También establecerán los medios que faciliten el acceso de los
trabajadores a la propiedad de los medios de producción.

ς  Artículo 130

   1. Los poderes públicos atenderán a la modernización y de-
sarrollo de todos los sectores económicos y, en particular, de
la agricultura, de la ganadería, de la pesca y de la artesanía, a
fin de equiparar el nivel de vida de todos los españoles.

   2. Con el mismo fin, se dispensará un tratamiento especial a
las zonas de montaña.

ς  Artículo 131

   1. El Estado, mediante ley, podrá planificar la actividad econó-
mica general para atender a las necesidades colectivas, equilibrar
y armonizar el desarrollo regional y sectorial y estimular el creci-
miento de la renta y de la riqueza y su más justa distribución.

   2. El Gobierno elaborará los proyectos de planificación, de
acuerdo con las previsiones que le sean suministradas por las
Comunidades Autónomas y el asesoramiento y colaboración
de los sindicatos y otras organizaciones profesionales, empre-

44
sariales y económicas. A tal fin se constituirá un Consejo, cuya
composición y funciones se desarrollarán por ley.

ς  Artículo 132

   1. La ley regulará el régimen jurídico de los bienes de domi-
nio público y de los comunales, inspirándose en los principios
de inalienabilidad, imprescriptibilidad e inembargabilidad, así
como su desafectación.

   2. Son bienes de dominio público estatal los que determine
la ley y, en todo caso, la zona marítimo-terrestre, las playas, el
mar territorial y los recursos naturales de la zona económica y
la plataforma continental.

   3. Por ley se regularán el Patrimonio del Estado y el Patrimo-
nio Nacional, su administración, defensa y conservación.

ς  Artículo 133

   1. La potestad originaria para establecer los tributos corres-
ponde exclusivamente al Estado, mediante ley.

   2. Las Comunidades Autónomas y las Corporaciones locales
podrán establecer y exigir tributos, de acuerdo con la Consti-
tución y las leyes.

   3. Todo beneficio fiscal que afecte a los tributos del Estado
deberá establecerse en virtud de ley.

   4. Las administraciones públicas sólo podrán contraer obli-
gaciones financieras y realizar gastos de acuerdo con las leyes.

ς  Artículo 134

   1. Corresponde al Gobierno la elaboración de los Presu-
puestos Generales del Estado y a las Cortes Generales, su exa-
men, enmienda y aprobación.

   2. Los Presupuestos Generales del Estado tendrán carácter
anual, incluirán la totalidad de los gastos e ingresos del sector
público estatal y en ellos se consignará el importe de los be-
neficios fiscales que afecten a los tributos del Estado.

   3. El Gobierno deberá presentar ante el Congreso de los Di-
putados los Presupuestos Generales del Estado al menos tres
meses antes de la expiración de los del año anterior.

   4. Si la Ley de Presupuestos no se aprobara antes del primer
día del ejercicio económico correspondiente, se considerarán
automáticamente prorrogados los Presupuestos del ejercicio
anterior hasta la aprobación de los nuevos.

                                                                                                     45
   5. Aprobados los Presupuestos Generales del Estado, el Go-
bierno podrá presentar proyectos de ley que impliquen au-
mento del gasto público o disminución de los ingresos corres-
pondientes al mismo ejercicio presupuestario.

   6. Toda proposición o enmienda que suponga aumento de
los créditos o disminución de los ingresos presupuestarios re-
querirá la conformidad del Gobierno para su tramitación.

   7. La Ley de Presupuestos no puede crear tributos. Podrá
modificarlos cuando una ley tributaria sustantiva así lo prevea.

ς  Artículo 135

   1. Todas las Administraciones Públicas adecuarán sus actua-
ciones al principio de estabilidad presupuestaria.

   2. El Estado y las Comunidades Autónomas no podrán incu-
rrir en un déficit estructural que supere los márgenes estable-
cidos, en su caso, por la Unión Europea para sus Estados
Miembros.

   Una ley orgánica fijará el déficit estructural máximo permiti-
do al Estado y a las Comunidades Autónomas, en relación con
su producto interior bruto. Las Entidades Locales deberán pre-
sentar equilibrio presupuestario.

   3. El Estado y las Comunidades Autónomas habrán de estar
autorizados por ley para emitir deuda pública o contraer cré-
dito.

   Los créditos para satisfacer los intereses y el capital de la
deuda pública de las Administraciones se entenderán siempre
incluidos en el estado de gastos de sus presupuestos y su pago
gozará de prioridad absoluta. Estos créditos no podrán ser ob-
jeto de enmienda o modificación, mientras se ajusten a las
condiciones de la ley de emisión.

   El volumen de deuda pública del conjunto de las Adminis-
traciones Públicas en relación con el producto interior bruto
del Estado no podrá superar el valor de referencia establecido
en el Tratado de Funcionamiento de la Unión Europea.

   4. Los límites de déficit estructural y de volumen de deuda
pública sólo podrán superarse en caso de catástrofes natura-
les, recesión económica o situaciones de emergencia extraor-
dinaria que escapen al control del Estado y perjudiquen consi-
derablemente la situación financiera o la sostenibilidad
económica o social del Estado, apreciadas por la mayoría ab-
soluta de los miembros del Congreso de los Diputados.

46
   5. Una ley orgánica desarrollará los principios a que se refie-
re este artículo, así como la participación, en los procedimien-
tos respectivos, de los órganos de coordinación institucional
entre las Administraciones Públicas en materia de política fiscal
y financiera. En todo caso, regulará:

     a)	La distribución de los límites de déficit y de deuda entre
         las distintas Administraciones Públicas, los supuestos
         excepcionales de superación de los mismos y la forma
         y plazo de corrección de las desviaciones que sobre
         uno y otro pudieran producirse.

     b)	L a metodología y el procedimiento para el cálculo del
         déficit estructural.

     c)	L a responsabilidad de cada Administración Pública en
         caso de incumplimiento de los objetivos de estabilidad
         presupuestaria.

   6. Las Comunidades Autónomas, de acuerdo con sus res-
pectivos Estatutos y dentro de los límites a que se refiere este
artículo, adoptarán las disposiciones que procedan para la
aplicación efectiva del principio de estabilidad en sus normas
y decisiones presupuestarias.

ς  Artículo 136

   1. El Tribunal de Cuentas es el supremo órgano fiscalizador
de las cuentas y de la gestión económica de Estado, así como
del sector público.

   Dependerá directamente de las Cortes Generales y ejercerá
sus funciones por delegación de ellas en el examen y compro-
bación de la Cuenta General del Estado.

   2. Las cuentas del Estado y del sector público estatal se ren-
dirán al Tribunal de Cuentas y serán censuradas por éste.

   El Tribunal de Cuentas, sin perjuicio de su propia jurisdic-
ción, remitirá a las Cortes Generales un informe anual en el
que, cuando proceda, comunicará las infracciones o respon-
sabilidades en que, a su juicio, se hubiere incurrido.

   3. Los miembros del Tribunal de Cuentas gozarán de la mis-
ma independencia e inamovilidad y estarán sometidos a las
mismas incompatibilidades que los Jueces.

   4. Una ley orgánica regulará la composición, organización y
funciones del Tribunal de Cuentas.

                                                                                                     47
                                  TÍTULO VIII
              De la Organización Territorial del Estado

                            CAPÍTULO PRIMERO
                            Principios generales

ς  Artículo 137
   El Estado se organiza territorialmente en municipios, en pro-

vincias y en las Comunidades Autónomas que se constituyan.
Todas estas entidades gozan de autonomía para la gestión de
sus respectivos intereses.

ς  Artículo 138
   1. El Estado garantiza la realización efectiva del principio de

solidaridad consagrado en el artículo 2 de la Constitución,
velando por el establecimiento de un equilibrio económico,
adecuado y justo entre las diversas partes del territorio espa-
ñol, y atendiendo en particular a las circunstancias del hecho
insular.

   2. Las diferencias entre los Estatutos de las distintas Comu-
nidades Autónomas no podrán implicar, en ningún caso, privi-
legios económicos o sociales.

ς  Artículo 139
   1. Todos los españoles tienen los mismos derechos y obliga-

ciones en cualquier parte del territorio del Estado.
   2. Ninguna autoridad podrá adoptar medidas que directa o

indirectamente obstaculicen la libertad de circulación y esta-
blecimiento de las personas y la libre circulación de bienes en
todo el territorio español.

                           CAPÍTULO SEGUNDO
                       De la Administración Local

ς  Artículo 140
   La Constitución garantiza la autonomía de los municipios.

Estos gozarán de personalidad jurídica plena. Su gobierno y
administración corresponde a sus respectivos Ayuntamientos,

48
integrados por los Alcaldes y los Concejales. Los Concejales
serán elegidos por los vecinos del municipio mediante sufragio
universal, igual, libre, directo y secreto, en la forma establecida
por la ley. Los Alcaldes serán elegidos por los Concejales o por
los vecinos. La ley regulará las condiciones en las que proceda
el régimen del concejo abierto.

ς  Artículo 141

   1. La provincia es una entidad local con personalidad jurídica
propia, determinada por la agrupación de municipios y división
territorial para el cumplimiento de las actividades del Estado.
Cualquier alteración de los límites provinciales habrá de ser
aprobada por las Cortes Generales mediante ley orgánica.

   2. El gobierno y la administración autónoma de las provin-
cias estarán encomendados a Diputaciones u otras Corpora-
ciones de carácter representativo.

   3. Se podrán crear agrupaciones de municipios diferentes de
la provincia.

   4. En los archipiélagos, las islas tendrán además su adminis-
tración propia en forma de Cabildos o Consejos.

ς  Artículo 142

   Las Haciendas locales deberán disponer de los medios sufi-
cientes para el desempeño de las funciones que la ley atribuye
a las Corporaciones respectivas y se nutrirán fundamental-
mente de tributos propios y de participación en los del Estado
y de las Comunidades Autónomas.

                            CAPÍTULO TERCERO
                   De las Comunidades Autónomas

ς  Artículo 143

   1. En el ejercicio del derecho a la autonomía reconocido en
el artículo 2 de la Constitución, las provincias limítrofes con
características históricas, culturales y económicas comunes,
los territorios insulares y las provincias con entidad regional
histórica podrán acceder a su autogobierno y constituirse en
Comunidades Autónomas con arreglo a lo previsto en este
Título y en los respectivos Estatutos.

                                                                                                     49
   2. La iniciativa del proceso autonómico corresponde a todas
las Diputaciones interesadas o al órgano interinsular correspon-
diente y a las dos terceras partes de los municipios cuya pobla-
ción represente, al menos, la mayoría del censo electoral de
cada provincia o isla. Estos requisitos deberán ser cumplidos en
el plazo de seis meses desde el primer acuerdo adoptado al
respecto por alguna de las Corporaciones locales interesadas.

   3. La iniciativa, en caso de no prosperar, solamente podrá
reiterarse pasados cinco años.

ς  Artículo 144

   Las Cortes Generales, mediante ley orgánica, podrán, por
motivos de interés nacional:

   a) Autorizar la constitución de una comunidad autónoma
      cuando su ámbito territorial no supere el de una provincia
      y no reúna las condiciones del apartado 1 del artículo 143.

   b) Autorizar o acordar, en su caso, un Estatuto de autonomía
      para territorios que no estén integrados en la organiza-
      ción provincial.

   c) Sustituir la iniciativa de las Corporaciones locales a que se
      refiere el apartado 2 del artículo 143.

ς  Artículo 145

   1. En ningún caso se admitirá la federación de Comunidades
Autónomas.

   2. Los Estatutos podrán prever los supuestos, requisitos y
términos en que las Comunidades Autónomas podrán celebrar
convenios entre sí para la gestión y prestación de servicios
propios de las mismas, así como el carácter y efectos de la
correspondiente comunicación a las Cortes Generales. En los
demás supuestos, los acuerdos de cooperación entre las Co-
munidades Autónomas necesitarán la autorización de las Cor-
tes Generales.

ς  Artículo 146

   El proyecto de Estatuto será elaborado por una asamblea
compuesta por los miembros de la Diputación u órgano inter­
insular de las provincias afectadas y por los Diputados y Sena-
dores elegidos en ellas y será elevado a las Cortes Generales
para su tramitación como ley.

50
ς  Artículo 147

   1. Dentro de los términos de la presente Constitución, los
Estatutos serán la norma institucional básica de cada Comuni-
dad Autónoma y el Estado los reconocerá y amparará como
parte integrante de su ordenamiento jurídico.

   2. Los Estatutos de autonomía deberán contener:

     a)	La denominación de la Comunidad que mejor corres-
         ponda a su identidad histórica.

     b)	L a delimitación de su territorio.
     c)	La denominación, organización y sede de las institucio-

         nes autónomas propias.
     d)	L as competencias asumidas dentro del marco estable-

         cido en la Constitución y las bases para el traspaso de
         los servicios correspondientes a las mismas.

   3. La reforma de los Estatutos se ajustará al procedimiento
establecido en los mismos y requerirá, en todo caso, la apro-
bación por las Cortes Generales, mediante ley orgánica.

ς  Artículo 148

   1. Las Comunidades Autónomas podrán asumir competen-
cias en las siguientes materias:

   1.ª Organización de sus instituciones de autogobierno.
   2.ª Las alteraciones de los términos municipales compren-
didos en su territorio y, en general, las funciones que corres-
pondan a la Administración del Estado sobre las Corporaciones
locales y cuya transferencia autorice la legislación sobre Régi-
men Local.
   3.ª Ordenación del territorio, urbanismo y vivienda.
   4.ª Las obras públicas de interés de la Comunidad Autóno-
ma en su propio territorio.
   5.ª Los ferrocarriles y carreteras cuyo itinerario se desarrolle
íntegramente en el territorio de la Comunidad Autónoma y, en
los mismos términos, el transporte desarrollado por estos me-
dios o por cable.
   6.ª Los puertos de refugio, los puertos y aeropuertos depor-
tivos y, en general, los que no desarrollen actividades comer-
ciales.
   7.ª La agricultura y ganadería, de acuerdo con la ordenación
general de la economía.

                                                                                                     51
   8.ª Los montes y aprovechamientos forestales.
   9.ª La gestión en materia de protección del medio ambiente.
   10.ª Los proyectos, construcción y explotación de los apro-
vechamientos hidráulicos, canales y regadíos de interés de la
Comunidad Autónoma; las aguas minerales y termales.
   11.ª La pesca en aguas interiores, el marisqueo y la acuicul-
tura, la caza y la pesca fluvial.
   12.ª Ferias interiores.
   13.ª El fomento del desarrollo económico de la Comunidad
Autónoma dentro de los objetivos marcados por la política
económica nacional.
   14.ª La artesanía.
   15.ª Museos, bibliotecas y conservatorios de música de inte-
rés para la Comunidad Autónoma.
   16.ª Patrimonio monumental de interés de la Comunidad
Autónoma.
   17.ª El fomento de la cultura, de la investigación y, en su
caso, de la enseñanza de la lengua de la Comunidad Autóno-
ma.
   18.ª Promoción y ordenación del turismo en su ámbito te-
rritorial.
   19.ª Promoción del deporte y de la adecuada utilización del
ocio.
   20.ª Asistencia social.
   21.ª Sanidad e higiene.
   22.ª La vigilancia y protección de sus edificios e instalacio-
nes. La coordinación y demás facultades en relación con las
policías locales en los términos que establezca una ley orgáni-
ca.

   2. Transcurridos cinco años, y mediante la reforma de sus
Estatutos, las Comunidades Autónomas podrán ampliar suce-
sivamente sus competencias dentro del marco establecido en
el artículo 149.

ς  Artículo 149

   1. El Estado tiene competencia exclusiva sobre las siguientes
materias:

   1.ª La regulación de las condiciones básicas que garanticen
la igualdad de todos los españoles en el ejercicio de los dere-
chos y en el cumplimiento de los deberes constitucionales.

52
   2.ª Nacionalidad, inmigración, emigración, extranjería y de-
recho de asilo.

   3.ª Relaciones internacionales.
   4.ª Defensa y Fuerzas Armadas.
   5.ª Administración de Justicia.
   6.ª Legislación mercantil, penal y penitenciaria; legislación
procesal, sin perjuicio de las necesarias especialidades que en
este orden se deriven de las particularidades del derecho sus-
tantivo de las Comunidades Autónomas.
   7.ª Legislación laboral; sin perjuicio de su ejecución por los
órganos de las Comunidades Autónomas.
   8.ª Legislación civil, sin perjuicio de la conservación, modi-
ficación y desarrollo por las Comunidades Autónomas de los
derechos civiles, forales o especiales, allí donde existan. En
todo caso, las reglas relativas a la aplicación y eficacia de las
normas jurídicas, relaciones jurídico-civiles relativas a las for-
mas de matrimonio, ordenación de los registros e instrumen-
tos públicos, bases de las obligaciones contractuales, normas
para resolver los conflictos de leyes y determinación de las
fuentes del Derecho, con respeto, en este último caso, a las
normas de derecho foral o especial.
   9.ª Legislación sobre propiedad intelectual e industrial.
   10.ª Régimen aduanero y arancelario; comercio exterior.
   11.ª Sistema monetario: divisas, cambio y convertibilidad;
bases de la ordenación de crédito, banca y seguros.
   12.ª Legislación sobre pesas y medidas, determinación de la
hora oficial.
   13.ª Bases y coordinación de la planificación general de la
actividad económica.
   14.ª Hacienda general y Deuda del Estado.
   15.ª Fomento y coordinación general de la investigación
científica y técnica.
   16.ª Sanidad exterior. Bases y coordinación general de la
sanidad. Legislación sobre productos farmacéuticos.
   17.ª Legislación básica y régimen económico de la Seguridad
Social, sin perjuicio de la ejecución de sus servicios por las
Comunidades Autónomas.
   18.ª Las bases del régimen jurídico de las Administraciones
públicas y del régimen estatutario de sus funcionarios que, en
todo caso, garantizarán a los administrados un tratamiento
común ante ellas; el procedimiento administrativo común, sin

                                                                                                     53
perjuicio de las especialidades derivadas de la organización
propia de las Comunidades Autónomas; legislación sobre ex-
propiación forzosa; legislación básica sobre contratos y con-
cesiones administrativas y el sistema de responsabilidad de
todas las Administraciones públicas.

   19.ª Pesca marítima, sin perjuicio de las competencias que
en la ordenación del sector se atribuyan a las Comunidades
Autónomas.

   20.ª Marina mercante y abanderamiento de buques; ilumi-
nación de costas y señales marítimas; puertos de interés gene-
ral; aeropuertos de interés general; control del espacio aéreo,
tránsito y transporte aéreo, servicio meteorológico y matricu-
lación de aeronaves.

   21.ª Ferrocarriles y transportes terrestres que transcurran por
el territorio de más de una Comunidad Autónoma; régimen
general de comunicaciones; tráfico y circulación de vehículos
a motor; correos y telecomunicaciones; cables aéreos, sub-
marinos y radiocomunicación.

   22.ª La legislación, ordenación y concesión de recursos y apro-
vechamientos hidráulicos cuando las aguas discurran por más de
una Comunidad Autónoma, y la autorización de las instalaciones
eléctricas cuando su aprovechamiento afecte a otra Comunidad
o el transporte de energía salga de su ámbito territorial.

   23.ª Legislación básica sobre protección del medio ambien-
te, sin perjuicio de las facultades de las Comunidades Autóno-
mas de establecer normas adicionales de protección. La legis-
lación básica sobre montes, aprovechamientos forestales y
vías pecuarias.

   24.ª Obras públicas de interés general o cuya realización
afecte a más de una Comunidad Autónoma.

   25.ª Bases de régimen minero y energético.
   26.ª Régimen de producción, comercio, tenencia y uso de
armas y explosivos.
   27.ª Normas básicas del régimen de prensa, radio y televi-
sión y, en general, de todos los medios de comunicación so-
cial, sin perjuicio de las facultades que en su desarrollo y eje-
cución correspondan a las Comunidades Autónomas.
   28.ª Defensa del patrimonio cultural, artístico y monumental
español contra la exportación y la expoliación; museos, biblio-
tecas y archivos de titularidad estatal, sin perjuicio de su ges-
tión por parte de las Comunidades Autónomas.

54
   29.ª Seguridad pública, sin perjuicio de la posibilidad de
creación de policías por las Comunidades Autónomas en la
forma que se establezca en los respectivos Estatutos en el
marco de lo que disponga una ley orgánica.

   30.ª Regulación de las condiciones de obtención, expedi-
ción y homologación de títulos académicos y profesionales y
normas básicas para el desarrollo del artículo 27 de la Consti-
tución, a fin de garantizar el cumplimiento de las obligaciones
de los poderes públicos en esta materia.

   31.ª Estadística para fines estatales.
   32.ª Autorización para la convocatoria de consultas popula-
res por vía de referéndum.

   2. Sin perjuicio de las competencias que podrán asumir las
Comunidades Autónomas, el Estado considerará el servicio de
la cultura como deber y atribución esencial y facilitará la co-
municación cultural entre las Comunidades Autónomas, de
acuerdo con ellas.

   3. Las materias no atribuidas expresamente al Estado por
esta Constitución podrán corresponder a las Comunidades
Autónomas, en virtud de sus respectivos Estatutos. La compe-
tencia sobre las materias que no se hayan asumido por los
Estatutos de Autonomía corresponderá al Estado, cuyas nor-
mas prevalecerán, en caso de conflicto, sobre las de las Co-
munidades Autónomas en todo lo que no esté atribuido a la
exclusiva competencia de éstas. El derecho estatal será, en
todo caso, supletorio del derecho de las Comunidades Autó-
nomas.

ς  Artículo 150

   1. Las Cortes Generales, en materias de competencia estatal,
podrán atribuir a todas o a alguna de las Comunidades Autó-
nomas la facultad de dictar, para sí mismas, normas legislativas
en el marco de los principios, bases y directrices fijados por
una ley estatal. Sin perjuicio de la competencia de los Tribuna-
les, en cada ley marco se establecerá la modalidad del control
de las Cortes Generales sobre estas normas legislativas de las
Comunidades Autónomas.

   2. El Estado podrá transferir o delegar en las Comunidades
Autónomas, mediante ley orgánica, facultades correspondien-
tes a materia de titularidad estatal que por su propia naturaleza

                                                                                                     55
sean susceptibles de transferencia o delegación. La ley preve-
rá en cada caso la correspondiente transferencia de medios
financieros, así como las formas de control que se reserve el
Estado.

   3. El Estado podrá dictar leyes que establezcan los principios
necesarios para armonizar las disposiciones normativas de las
Comunidades Autónomas, aun en el caso de materias atribui-
das a la competencia de éstas, cuando así lo exija el interés
general. Corresponde a las Cortes Generales, por mayoría ab-
soluta de cada Cámara, la apreciación de esta necesidad.

ς  Artículo 151

   1. No será preciso dejar transcurrir el plazo de cinco años, a
que se refiere el apartado 2 del artículo 148, cuando la inicia-
tiva del proceso autonómico sea acordada dentro del plazo
del artículo 143.2, además de por las Diputaciones o los órga-
nos interinsulares correspondientes, por las tres cuartas partes
de los municipios de cada una de las provincias afectadas que
representen, al menos, la mayoría del censo electoral de cada
una de ellas y dicha iniciativa sea ratificada mediante referén-
dum por el voto afirmativo de la mayoría absoluta de los elec-
tores de cada provincia en los términos que establezca una ley
orgánica.

   2. En el supuesto previsto en el apartado anterior, el proce-
dimiento para la elaboración del Estatuto será el siguiente:

   1.º El Gobierno convocará a todos los Diputados y Senado-
res elegidos en las circunscripciones comprendidas en el ám-
bito territorial que pretenda acceder al autogobierno, para que
se constituyan en Asamblea, a los solos efectos de elaborar el
correspondiente proyecto de Estatuto de autonomía, median-
te el acuerdo de la mayoría absoluta de sus miembros.

   2.º Aprobado el proyecto de Estatuto por la Asamblea de
Parlamentarios, se remitirá a la Comisión Constitucional del
Congreso, la cual, dentro del plazo de dos meses, lo examina-
rá con el concurso y asistencia de una delegación de la Asam-
blea proponente para determinar de común acuerdo su for-
mulación definitiva.

   3.º Si se alcanzare dicho acuerdo, el texto resultante será
sometido a referéndum del cuerpo electoral de las provincias
comprendidas en el ámbito territorial del proyectado Estatuto.

56
   4.º Si el proyecto de Estatuto es aprobado en cada provincia
por la mayoría de los votos válidamente emitidos, será elevado
a las Cortes Generales. Los plenos de ambas Cámaras decidi-
rán sobre el texto mediante un voto de ratificación. Aprobado
el Estatuto, el Rey lo sancionará y lo promulgará como ley.

   5.º De no alcanzarse el acuerdo a que se refiere el apartado
2 de este número, el proyecto de Estatuto será tramitado
como proyecto de ley ante las Cortes Generales. El texto apro-
bado por éstas será sometido a referéndum del cuerpo elec-
toral de las provincias comprendidas en el ámbito territorial del
proyectado Estatuto. En caso de ser aprobado por la mayoría
de los votos válidamente emitidos en cada provincia, procede-
rá su promulgación en los términos del párrafo anterior.

   3. En los casos de los párrafos 4.º y 5.º del apartado anterior,
la no aprobación del proyecto de Estatuto por una o varias
provincias no impedirá la constitución entre las restantes de la
Comunidad Autónoma proyectada, en la forma que establezca
la ley orgánica prevista en el apartado 1 de este artículo.

ς  Artículo 152

   1. En los Estatutos aprobados por el procedimiento a que se
refiere el artículo anterior, la organización institucional auto-
nómica se basará en una Asamblea Legislativa, elegida por
sufragio universal, con arreglo a un sistema de representación
proporcional que asegure, además, la representación de las
diversas zonas del territorio; un Consejo de Gobierno con fun-
ciones ejecutivas y administrativas y un Presidente, elegido por
la Asamblea, de entre sus miembros, y nombrado por el Rey, al
que corresponde la dirección del Consejo de Gobierno, la su-
prema representación de la respectiva Comunidad y la ordina-
ria del Estado en aquélla. El Presidente y los miembros del
Consejo de Gobierno serán políticamente responsables ante la
Asamblea.

   Un Tribunal Superior de Justicia, sin perjuicio de la jurisdic-
ción que corresponde al Tribunal Supremo, culminará la orga-
nización judicial en el ámbito territorial de la Comunidad Au-
tónoma. En los Estatutos de las Comunidades Autónomas
podrán establecerse los supuestos y las formas de participa-
ción de aquéllas en la organización de las demarcaciones ju-
diciales del territorio. Todo ello de conformidad con lo previs-

                                                                                                     57
to en la ley orgánica del poder judicial y dentro de la unidad e
independencia de éste.

   Sin perjuicio de lo dispuesto en el artículo 123, las sucesivas
instancias procesales, en su caso, se agotarán ante órganos
judiciales radicados en el mismo territorio de la Comunidad
Autónoma en que esté el órgano competente en primera ins-
tancia.

   2. Una vez sancionados y promulgados los respectivos Esta-
tutos, solamente podrán ser modificados mediante los proce-
dimientos en ellos establecidos y con referéndum entre los
electores inscritos en los censos correspondientes.

   3. Mediante la agrupación de municipios limítrofes, los Esta-
tutos podrán establecer circunscripciones territoriales propias,
que gozarán de plena personalidad jurídica.

ς  Artículo 153

   El control de la actividad de los órganos de las Comunidades
Autónomas se ejercerá:

   a) Por el Tribunal Constitucional, el relativo a la constitucio-
      nalidad de sus disposiciones normativas con fuerza de ley.

   b) Por el Gobierno, previo dictamen del Consejo de Estado,
      el del ejercicio de funciones delegadas a que se refiere el
      apartado 2 del artículo 150.

   c) Por la jurisdicción contencioso-administrativa, el de la
      administración autónoma y sus normas reglamentarias.

   d) Por el Tribunal de Cuentas, el económico y presupuestario.

ς  Artículo 154

   Un Delegado nombrado por el Gobierno dirigirá la Adminis-
tración del Estado en el territorio de la Comunidad Autónoma
y la coordinará, cuando proceda, con la administración propia
de la Comunidad.

ς  Artículo 155

   1. Si una Comunidad Autónoma no cumpliere las obligacio-
nes que la Constitución u otras leyes le impongan, o actuare
de forma que atente gravemente al interés general de España,
el Gobierno, previo requerimiento al Presidente de la Comuni-
dad Autónoma y, en el caso de no ser atendido, con la apro-
bación por mayoría absoluta del Senado, podrá adoptar las

58
medidas necesarias para obligar a aquélla al cumplimiento
forzoso de dichas obligaciones o para la protección del men-
cionado interés general.

   2. Para la ejecución de las medidas previstas en el apartado
anterior, el Gobierno podrá dar instrucciones a todas las auto-
ridades de las Comunidades Autónomas.

ς  Artículo 156

   1. Las Comunidades Autónomas gozarán de autonomía fi-
nanciera para el desarrollo y ejecución de sus competencias
con arreglo a los principios de coordinación con la Hacienda
estatal y de solidaridad entre todos los españoles.

   2. Las Comunidades Autónomas podrán actuar como dele-
gados o colaboradores del Estado para la recaudación, la ges-
tión y la liquidación de los recursos tributarios de aquél, de
acuerdo con las leyes y los Estatutos.

ς  Artículo 157

   1. Los recursos de las Comunidades Autónomas estarán
constituidos por:

     a)	Impuestos cedidos total o parcialmente por el Estado;
         recargos sobre impuestos estatales y otras participacio-
         nes en los ingresos del Estado.

     b)	S us propios impuestos, tasas y contribuciones especia-
         les.

     c)	T ransferencias de un Fondo de Compensación interte-
         rritorial y otras asignaciones con cargo a los Presupues-
         tos Generales del Estado.

     d)	Rendimientos procedentes de su patrimonio e ingresos
         de derecho privado.

     e)	El producto de las operaciones de crédito.

   2. Las Comunidades Autónomas no podrán en ningún caso
adoptar medidas tributarias sobre bienes situados fuera de su
territorio o que supongan obstáculo para la libre circulación de
mercancías o servicios.

   3. Mediante ley orgánica podrá regularse el ejercicio de las
competencias financieras enumeradas en el precedente apar-
tado 1, las normas para resolver los conflictos que pudieran
surgir y las posibles formas de colaboración financiera entre
las Comunidades Autónomas y el Estado.

                                                                                                     59
ς  Artículo 158

   1. En los Presupuestos Generales del Estado podrá estable-
cerse una asignación a las Comunidades Autónomas en fun-
ción del volumen de los servicios y actividades estatales que
hayan asumido y de la garantía de un nivel mínimo en la pres-
tación de los servicios públicos fundamentales en todo el te-
rritorio español.

   2. Con el fin de corregir desequilibrios económicos interterri-
toriales y hacer efectivo el principio de solidaridad, se constitui-
rá un Fondo de Compensación con destino a gastos de inver-
sión, cuyos recursos serán distribuidos por las Cortes Generales
entre las Comunidades Autónomas y provincias, en su caso.

                                   TÍTULO IX

                       Del Tribunal Constitucional

ς  Artículo 159

   1. El Tribunal Constitucional se compone de 12 miembros
nombrados por el Rey; de ellos, cuatro a propuesta del Con-
greso por mayoría de tres quintos de sus miembros; cuatro a
propuesta del Senado, con idéntica mayoría; dos a propuesta
del Gobierno, y dos a propuesta del Consejo General del Poder
Judicial.

   2. Los miembros del Tribunal Constitucional deberán ser
nombrados entre Magistrados y Fiscales, Profesores de Univer-
sidad, funcionarios públicos y Abogados, todos ellos juristas de
reconocida competencia con más de quince años de ejercicio
profesional.

   3. Los miembros del Tribunal Constitucional serán designa-
dos por un período de nueve años y se renovarán por terceras
partes cada tres.

   4. La condición de miembro del Tribunal Constitucional es
incompatible: con todo mandato representativo; con los cargos
políticos o administrativos; con el desempeño de funciones di-
rectivas en un partido político o en un sindicato y con el empleo
al servicio de los mismos; con el ejercicio de las carreras judicial
y fiscal, y con cualquier actividad profesional o mercantil.

   En lo demás los miembros del Tribunal Constitucional ten-
drán las incompatibilidades propias de los miembros del poder
judicial.

60
   5. Los miembros del Tribunal Constitucional serán indepen-
dientes e inamovibles en el ejercicio de su mandato.

ς  Artículo 160

   El Presidente del Tribunal Constitucional será nombrado en-
tre sus miembros por el Rey, a propuesta del mismo Tribunal
en pleno y por un período de tres años.

ς  Artículo 161

   1. El Tribunal Constitucional tiene jurisdicción en todo el te-
rritorio español y es competente para conocer:

     a)	Del recurso de inconstitucionalidad contra leyes y dis-
         posiciones normativas con fuerza de ley. La declaración
         de inconstitucionalidad de una norma jurídica con ran-
         go de ley, interpretada por la jurisprudencia, afectará a
         ésta, si bien la sentencia o sentencias recaídas no per-
         derán el valor de cosa juzgada.

     b)	D el recurso de amparo por violación de los derechos y
         libertades referidos en el artículo 53, 2, de esta Consti-
         tución, en los casos y formas que la ley establezca.

     c)	D e los conflictos de competencia entre el Estado y las
         Comunidades Autónomas o de los de éstas entre sí.

     d)	D e las demás materias que le atribuyan la Constitución
         o las leyes orgánicas.

   2. El Gobierno podrá impugnar ante el Tribunal Constitucio-
nal las disposiciones y resoluciones adoptadas por los órganos
de las Comunidades Autónomas. La impugnación producirá la
suspensión de la disposición o resolución recurrida, pero el
Tribunal, en su caso, deberá ratificarla o levantarla en un plazo
no superior a cinco meses.

ς  Artículo 162

   1. Están legitimados:

      a)	Para interponer el recurso de inconstitucionalidad, el
          Presidente del Gobierno, el Defensor del Pueblo, 50
          Diputados, 50 Senadores, los órganos colegiados eje-
          cutivos de las Comunidades Autónomas y, en su caso,
          las Asambleas de las mismas.

                                                                                                     61
      b)	Para interponer el recurso de amparo, toda persona
          natural o jurídica que invoque un interés legítimo, así
          como el Defensor del Pueblo y el Ministerio Fiscal.

   2. En los demás casos, la ley orgánica determinará las per-
sonas y órganos legitimados.

ς  Artículo 163
   Cuando un órgano judicial considere, en algún proceso, que

una norma con rango de ley, aplicable al caso, de cuya validez
dependa el fallo, pueda ser contraria a la Constitución, plan-
teará la cuestión ante el Tribunal Constitucional en los supues-
tos, en la forma y con los efectos que establezca la ley, que en
ningún caso serán suspensivos.

ς  Artículo 164
   1. Las sentencias del Tribunal Constitucional se publicarán

en el boletín oficial del Estado con los votos particulares, si los
hubiere. Tienen el valor de cosa juzgada a partir del día si-
guiente de su publicación y no cabe recurso alguno contra
ellas. Las que declaren la inconstitucionalidad de una ley o de
una norma con fuerza de ley y todas las que no se limiten a la
estimación subjetiva de un derecho, tienen plenos efectos
frente a todos.

   2. Salvo que en el fallo se disponga otra cosa, subsistirá la
vigencia de la ley en la parte no afectada por la inconstitucio-
nalidad.

ς  Artículo 165
   Una ley orgánica regulará el funcionamiento del Tribunal

Constitucional, el estatuto de sus miembros, el procedimiento
ante el mismo y las condiciones para el ejercicio de las accio-
nes.

                                    TÍTULO X
                      De la reforma constitucional

ς  Artículo 166
   La iniciativa de reforma constitucional se ejercerá en los tér-

minos previstos en los apartados 1 y 2 del artículo 87.

62
ς  Artículo 167

   1. Los proyectos de reforma constitucional deberán ser
aprobados por una mayoría de tres quintos de cada una de las
Cámaras. Si no hubiera acuerdo entre ambas, se intentará ob-
tenerlo mediante la creación de una Comisión de composición
paritaria de Diputados y Senadores, que presentará un texto
que será votado por el Congreso y el Senado.

   2. De no lograrse la aprobación mediante el procedimiento
del apartado anterior, y siempre que el texto hubiere obtenido
el voto favorable de la mayoría absoluta del Senado, el Con-
greso, por mayoría de dos tercios, podrá aprobar la reforma.

   3. Aprobada la reforma por las Cortes Generales, será some-
tida a referéndum para su ratificación cuando así lo soliciten,
dentro de los quince días siguientes a su aprobación, una dé-
cima parte de los miembros de cualquiera de las Cámaras.

ς  Artículo 168

   1. Cuando se propusiere la revisión total de la Constitución
o una parcial que afecte al Título preliminar, al Capítulo segun-
do, Sección primera del Título I, o al Título II, se procederá a la
aprobación del principio por mayoría de dos tercios de cada
Cámara, y a la disolución inmediata de las Cortes.

   2. Las Cámaras elegidas deberán ratificar la decisión y pro-
ceder al estudio del nuevo texto constitucional, que deberá ser
aprobado por mayoría de dos tercios de ambas Cámaras.

   3. Aprobada la reforma por las Cortes Generales, será some-
tida a referéndum para su ratificación.

ς  Artículo 169

   No podrá iniciarse la reforma constitucional en tiempo de
guerra o de vigencia de alguno de los estados previstos en el
artículo 116.

ς  Disposición adicional primera

   La Constitución ampara y respeta los derechos históricos de
los territorios forales.

   La actualización general de dicho régimen foral se llevará a
cabo, en su caso, en el marco de la Constitución y de los Es-
tatutos de Autonomía.

                                                                                                     63
ς  Disposición adicional segunda
   La declaración de mayoría de edad contenida en el artículo

12 de esta Constitución no perjudica las situaciones ampara-
das por los derechos forales en el ámbito del Derecho privado.

ς  Disposición adicional tercera
   La modificación del régimen económico y fiscal del archi-

piélago canario requerirá informe previo de la Comunidad
Autónoma o, en su caso, del órgano provisional autonómico.

ς  Disposición adicional cuarta
   En las Comunidades Autónomas donde tengan su sede más

de una Audiencia Territorial, los Estatutos de Autonomía res-
pectivos podrán mantener las existentes, distribuyendo las
competencias entre ellas, siempre de conformidad con lo pre-
visto en la ley orgánica del poder judicial y dentro de la unidad
e independencia de éste.

ς  Disposición transitoria primera

   En los territorios dotados de un régimen provisional de au-
tonomía, sus órganos colegiados superiores, mediante acuer-
do adoptado por la mayoría absoluta de sus miembros, podrán
sustituir la iniciativa que en el apartado 2 del artículo 143 atri-
buye a las Diputaciones Provinciales o a los órganos interinsu-
lares correspondientes.

ς  Disposición transitoria segunda

   Los territorios que en el pasado hubiesen plebiscitado afir-
mativamente proyectos de Estatuto de autonomía y cuenten,
al tiempo de promulgarse esta Constitución, con regímenes
provisionales de autonomía podrán proceder inmediatamente
en la forma que se prevé en el apartado 2 del artículo 148,
cuando así lo acordaren, por mayoría absoluta, sus órganos
preautonómicos colegiados superiores, comunicándolo al
Gobierno. El proyecto de Estatuto será elaborado de acuerdo
con lo establecido en el artículo 151, número 2, a convocatoria
del órgano colegiado preautonómico.

ς  Disposición transitoria tercera

   La iniciativa del proceso autonómico por parte de las Cor-
poraciones locales o de sus miembros, prevista en el apartado

64
2 del artículo 143, se entiende diferida, con todos sus efectos,
hasta la celebración de las primeras elecciones locales una vez
vigente la Constitución.

ς  Disposición transitoria cuarta

   1. En el caso de Navarra, y a efectos de su incorporación al
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
plazo mínimo que establece el artículo 143.

ς  Disposición transitoria quinta

   Las ciudades de Ceuta y Melilla podrán constituirse en Comu-
nidades Autónomas si así lo deciden sus respectivos Ayunta-
mientos, mediante acuerdo adoptado por la mayoría absoluta de
sus miembros y así lo autorizan las Cortes Generales, mediante
una ley orgánica, en los términos previstos en el artículo 144.

ς  Disposición transitoria sexta
   Cuando se remitieran a la Comisión Constitucional del Con-

greso varios proyectos de Estatuto, se dictaminarán por el
orden de entrada en aquélla, y el plazo de dos meses a que se
refiere el artículo 151 empezará a contar desde que la Comi-
sión termine el estudio del proyecto o proyectos de que suce-
sivamente haya conocido.

ς  Disposición transitoria séptima
   Los organismos provisionales autonómicos se considerarán

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
      tres años.

ς  Disposición transitoria octava

   1. Las Cámaras que han aprobado la presente Constitución
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
edad para el voto y lo establecido en el artículo 69,3.

ς  Disposición transitoria novena

   A los tres años de la elección por vez primera de los miem-
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
a lo establecido en el número 3 del artículo 159.

ς  Disposición derogatoria
   1. Queda derogada la Ley 1/1977, de 4 de enero, para la Re-

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
opongan a lo establecido en esta Constitución.

ς  Disposición final
   Esta Constitución entrará en vigor el mismo día de la publi-

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

68
$body$,
      error = null
    where id = v_doc_id;
    raise notice '[0089] document actualizado: %', v_doc_id;
  else
    insert into public.documents (subject_id, user_id, storage_path, file_name, mime_type, status, extracted_text)
    values (v_subject_id, v_user_id, v_subject_id::text || '/manual-constitucion.pdf', 'CONSTITUCIÓN ESPAÑOLA 2025.pdf', 'application/pdf', 'ready', $body$CONSTITUCIÓN
    ES PAÑOL A
    Constitución Española

                   Cortes Generales
«BOE» núm. 311, de 29 de diciembre de 1978

         Referencia: BOE-A-1978-31229
Catálogo de publicaciones de la Administración General del
Estado https://cpage.mpr.gob.es/

NIPO (edición impresa): 143-25-047-7
NIPO (edición on line): 143-25-048-2
Depósito Legal: M-23773-2025
Fecha de edición: noviembre 2025
Diseña e imprime: Masquelibros, S.L.
Impreso en papeles FSC y PEFC.
                            ÍNDICE

Preámbulo......................................................................................... 5
TÍTULO PRELIMINAR....................................................................... 6
TÍTULO I. De los derechos y deberes fundamentales............. 8

   CAPÍTULO PRIMERO. De los españoles y los extranjeros.. 8
   CAPÍTULO SEGUNDO. Derechos y libertades....................... 9

      Sección 1.a De los derechos fundamentales y de
         las libertades públicas......................................................... 9

      Sección 2.a De los derechos y deberes de
         los ciudadanos..................................................................... 15

   CAPÍTULO TERCERO. De los principios rectores de
      la política social y económica.............................................. 17

   CAPÍTULO CUARTO. De las garantías de las libertades
      y derechos fundamentales.................................................... 20

   CAPÍTULO QUINTO. De la suspensión de los derechos
      y libertades................................................................................. 21

TÍTULO II. De la Corona................................................................. 21
TÍTULO III. De las Cortes Generales............................................ 25

   CAPÍTULO PRIMERO. De las Cámaras.................................... 25
   CAPÍTULO SEGUNDO. De la elaboración de las leyes........ 30
   CAPÍTULO TERCERO. De los Tratados Internacionales...... 33
TÍTULO IV. Del Gobierno y de la Administración..................... 35
TÍTULO V. De las relaciones entre el Gobierno
   y las Cortes Generales................................................................ 38
TÍTULO VI. Del Poder Judicial....................................................... 41
TÍTULO VII. Economía y Hacienda............................................... 44
TÍTULO VIII. De la Organización Territorial del Estado............ 48
   CAPÍTULO PRIMERO. Principios generales............................ 48
   CAPÍTULO SEGUNDO. De la Administración Local............. 48
   CAPÍTULO TERCERO. De las Comunidades Autónomas... 49
TÍTULO IX. Del Tribunal Constitucional...................................... 60
TÍTULO X. De la reforma constitucional..................................... 62
Disposiciones adicionales.............................................................. 63

                                                                                                       3
Disposiciones transitorias............................................................... 64
Disposición derogatoria................................................................. 67
Disposición final............................................................................... 67

4
                 TEXTO CONSOLIDADO

            Última modificación: 17 de febrero de 2024

DON JUAN CARLOS I, REY DE ESPAÑA, A TODOS LOS QUE
LA PRESENTE VIEREN Y ENTENDIEREN,
SABED: QUE LAS CORTES HAN APROBADO Y EL PUEBLO
ESPAÑOL RATIFICADO LA SIGUIENTE CONSTITUCIÓN:

                                 PREÁMBULO

   La Nación española, deseando establecer la justicia, la liber-
tad y la seguridad y promover el bien de cuantos la integran,
en uso de su soberanía, proclama su voluntad de:

   Garantizar la convivencia democrática dentro de la Consti-
tución y de las leyes conforme a un orden económico y social
justo.

   Consolidar un Estado de Derecho que asegure el imperio de
la ley como expresión de la voluntad popular.

   Proteger a todos los españoles y pueblos de España en el
ejercicio de los derechos humanos, sus culturas y tradiciones,
lenguas e instituciones.

   Promover el progreso de la cultura y de la economía para
asegurar a todos una digna calidad de vida.

   Establecer una sociedad democrática avanzada, y
   Colaborar en el fortalecimiento de unas relaciones pacíficas
y de eficaz cooperación entre todos los pueblos de la Tierra.
   En consecuencia, las Cortes aprueban y el pueblo español
ratifica la siguiente

                                                                                                       5
                      CONSTITUCIÓN

                            TÍTULO PRELIMINAR

ς  Artículo 1
   1. España se constituye en un Estado social y democrático

de Derecho, que propugna como valores superiores de su or-
denamiento jurídico la libertad, la justicia, la igualdad y el plu-
ralismo político.

   2. La soberanía nacional reside en el pueblo español, del que
emanan los poderes del Estado.

   3. La forma política del Estado español es la Monarquía par-
lamentaria.

ς  Artículo 2
   La Constitución se fundamenta en la indisoluble unidad de

la Nación española, patria común e indivisible de todos los
españoles, y reconoce y garantiza el derecho a la autonomía
de las nacionalidades y regiones que la integran y la solidaridad
entre todas ellas.

ς  Artículo 3
   1. El castellano es la lengua española oficial del Estado. To-

dos los españoles tienen el deber de conocerla y el derecho a
usarla.

   2. Las demás lenguas españolas serán también oficiales en
las respectivas Comunidades Autónomas de acuerdo con sus
Estatutos.

   3. La riqueza de las distintas modalidades lingüísticas de Es-
paña es un patrimonio cultural que será objeto de especial
respeto y protección.

ς  Artículo 4
   1. La bandera de España está formada por tres franjas hori-

zontales, roja, amarilla y roja, siendo la amarilla de doble an-
chura que cada una de las rojas.

6
   2. Los Estatutos podrán reconocer banderas y enseñas pro-
pias de las Comunidades Autónomas. Estas se utilizarán junto
a la bandera de España en sus edificios públicos y en sus actos
oficiales.

ς  Artículo 5

   La capital del Estado es la villa de Madrid.

ς  Artículo 6

   Los partidos políticos expresan el pluralismo político, con-
curren a la formación y manifestación de la voluntad popular
y son instrumento fundamental para la participación política.
Su creación y el ejercicio de su actividad son libres dentro del
respeto a la Constitución y a la ley. Su estructura interna y
funcionamiento deberán ser democráticos.

ς  Artículo 7

   Los sindicatos de trabajadores y las asociaciones empresa-
riales contribuyen a la defensa y promoción de los intereses
económicos y sociales que les son propios. Su creación y el
ejercicio de su actividad son libres dentro del respeto a la
Constitución y a la ley. Su estructura interna y funcionamiento
deberán ser democráticos.

ς  Artículo 8

   1. Las Fuerzas Armadas, constituidas por el Ejército de Tierra,
la Armada y el Ejército del Aire, tienen como misión garantizar
la soberanía e independencia de España, defender su integri-
dad territorial y el ordenamiento constitucional.

   2. Una ley orgánica regulará las bases de la organización
militar conforme a los principios de la presente Constitución.

ς  Artículo 9

   1. Los ciudadanos y los poderes públicos están sujetos a la
Constitución y al resto del ordenamiento jurídico.

   2. Corresponde a los poderes públicos promover las condi-
ciones para que la libertad y la igualdad del individuo y de los
grupos en que se integra sean reales y efectivas; remover los
obstáculos que impidan o dificulten su plenitud y facilitar la

                                                                                                       7
participación de todos los ciudadanos en la vida política, eco-
nómica, cultural y social.

   3. La Constitución garantiza el principio de legalidad, la jerar-
quía normativa, la publicidad de las normas, la irretroactividad
de las disposiciones sancionadoras no favorables o restrictivas
de derechos individuales, la seguridad jurídica, la responsabili-
dad y la interdicción de la arbitrariedad de los poderes públicos.

                                    TÍTULO I
             De los derechos y deberes fundamentales

ς  Artículo 10

   1. La dignidad de la persona, los derechos inviolables que le
son inherentes, el libre desarrollo de la personalidad, el respe-
to a la ley y a los derechos de los demás son fundamento del
orden político y de la paz social.

   2. Las normas relativas a los derechos fundamentales y a las
libertades que la Constitución reconoce se interpretarán de
conformidad con la Declaración Universal de Derechos Hu-
manos y los tratados y acuerdos internacionales sobre las mis-
mas materias ratificados por España.

                            CAPÍTULO PRIMERO
                  De los españoles y los extranjeros

ς  Artículo 11

   1. La nacionalidad española se adquiere, se conserva y se
pierde de acuerdo con lo establecido por la ley.

   2. Ningún español de origen podrá ser privado de su nacio-
nalidad.

   3. El Estado podrá concertar tratados de doble nacionalidad
con los países iberoamericanos o con aquellos que hayan te-
nido o tengan una particular vinculación con España. En estos
mismos países, aun cuando no reconozcan a sus ciudadanos
un derecho recíproco, podrán naturalizarse los españoles sin
perder su nacionalidad de origen.

ς  Artículo 12

   Los españoles son mayores de edad a los dieciocho años.

8
ς  Artículo 13

   1. Los extranjeros gozarán en España de las libertades públi-
cas que garantiza el presente Título en los términos que esta-
blezcan los tratados y la ley.

   2. Solamente los españoles serán titulares de los derechos
reconocidos en el artículo 23, salvo lo que, atendiendo a cri-
terios de reciprocidad, pueda establecerse por tratado o ley
para el derecho de sufragio activo y pasivo en las elecciones
municipales.

   3. La extradición sólo se concederá en cumplimiento de un
tratado o de la ley, atendiendo al principio de reciprocidad.
Quedan excluidos de la extradición los delitos políticos, no
considerándose como tales los actos de terrorismo.

   4. La ley establecerá los términos en que los ciudadanos de
otros países y los apátridas podrán gozar del derecho de asilo
en España.

                           CAPÍTULO SEGUNDO
                           Derechos y libertades

ς  Artículo 14

   Los españoles son iguales ante la ley, sin que pueda preva-
lecer discriminación alguna por razón de nacimiento, raza,
sexo, religión, opinión o cualquier otra condición o circuns-
tancia personal o social.

  Sección 1.ª De los derechos fundamentales y de las libertades
                                     públicas

ς  Artículo 15

   Todos tienen derecho a la vida y a la integridad física y mo-
ral, sin que, en ningún caso, puedan ser sometidos a tortura ni
a penas o tratos inhumanos o degradantes. Queda abolida la
pena de muerte, salvo lo que puedan disponer las leyes pena-
les militares para tiempos de guerra.

ς  Artículo 16

   1. Se garantiza la libertad ideológica, religiosa y de culto de
los individuos y las comunidades sin más limitación, en sus

                                                                                                       9
manifestaciones, que la necesaria para el mantenimiento del
orden público protegido por la ley.

   2. Nadie podrá ser obligado a declarar sobre su ideología,
religión o creencias.

   3. Ninguna confesión tendrá carácter estatal. Los poderes
públicos tendrán en cuenta las creencias religiosas de la socie-
dad española y mantendrán las consiguientes relaciones de
cooperación con la Iglesia Católica y las demás confesiones.

ς  Artículo 17

   1. Toda persona tiene derecho a la libertad y a la seguridad.
Nadie puede ser privado de su libertad, sino con la observancia
de lo establecido en este artículo y en los casos y en la forma
previstos en la ley.

   2. La detención preventiva no podrá durar más del tiempo
estrictamente necesario para la realización de las averiguacio-
nes tendentes al esclarecimiento de los hechos, y, en todo
caso, en el plazo máximo de setenta y dos horas, el detenido
deberá ser puesto en libertad o a disposición de la autoridad
judicial.

   3. Toda persona detenida debe ser informada de forma in-
mediata, y de modo que le sea comprensible, de sus derechos
y de las razones de su detención, no pudiendo ser obligada a
declarar. Se garantiza la asistencia de abogado al detenido en
las diligencias policiales y judiciales, en los términos que la ley
establezca.

   4. La ley regulará un procedimiento de «habeas corpus»
para producir la inmediata puesta a disposición judicial de toda
persona detenida ilegalmente. Asimismo, por ley se determi-
nará el plazo máximo de duración de la prisión provisional.

ς  Artículo 18

   1. Se garantiza el derecho al honor, a la intimidad personal y
familiar y a la propia imagen.

   2. El domicilio es inviolable. Ninguna entrada o registro po-
drá hacerse en él sin consentimiento del titular o resolución
judicial, salvo en caso de flagrante delito.

   3. Se garantiza el secreto de las comunicaciones y, en espe-
cial, de las postales, telegráficas y telefónicas, salvo resolución
judicial.

10
   4. La ley limitará el uso de la informática para garantizar el
honor y la intimidad personal y familiar de los ciudadanos y el
pleno ejercicio de sus derechos.

ς  Artículo 19

   Los españoles tienen derecho a elegir libremente su resi-
dencia y a circular por el territorio nacional.

   Asimismo, tienen derecho a entrar y salir libremente de Es-
paña en los términos que la ley establezca. Este derecho no
podrá ser limitado por motivos políticos o ideológicos.

ς  Artículo 20

   1. Se reconocen y protegen los derechos:

     a)	A expresar y difundir libremente los pensamientos, ideas
         y opiniones mediante la palabra, el escrito o cualquier
         otro medio de reproducción.

     b)	A la producción y creación literaria, artística, científica y
         técnica.

     c) A la libertad de cátedra.
     d)	A comunicar o recibir libremente información veraz por

         cualquier medio de difusión. La ley regulará el derecho
         a la cláusula de conciencia y al secreto profesional en el
         ejercicio de estas libertades.

   2. El ejercicio de estos derechos no puede restringirse me-
diante ningún tipo de censura previa.

   3. La ley regulará la organización y el control parlamentario
de los medios de comunicación social dependientes del Esta-
do o de cualquier ente público y garantizará el acceso a dichos
medios de los grupos sociales y políticos significativos, respe-
tando el pluralismo de la sociedad y de las diversas lenguas de
España.

   4. Estas libertades tienen su límite en el respeto a los dere-
chos reconocidos en este Título, en los preceptos de las leyes
que lo desarrollen y, especialmente, en el derecho al honor, a
la intimidad, a la propia imagen y a la protección de la juventud
y de la infancia.

   5. Sólo podrá acordarse el secuestro de publicaciones, gra-
baciones y otros medios de información en virtud de resolu-
ción judicial.

                                                                                                      11
ς  Artículo 21

   1. Se reconoce el derecho de reunión pacífica y sin armas. El
ejercicio de este derecho no necesitará autorización previa.

   2. En los casos de reuniones en lugares de tránsito público y
manifestaciones se dará comunicación previa a la autoridad,
que sólo podrá prohibirlas cuando existan razones fundadas
de alteración del orden público, con peligro para personas o
bienes.

ς  Artículo 22

   1. Se reconoce el derecho de asociación.
   2. Las asociaciones que persigan fines o utilicen medios ti-
pificados como delito son ilegales.
   3. Las asociaciones constituidas al amparo de este artículo
deberán inscribirse en un registro a los solos efectos de publi-
cidad.
   4. Las asociaciones sólo podrán ser disueltas o suspendidas
en sus actividades en virtud de resolución judicial motivada.
   5. Se prohíben las asociaciones secretas y las de carácter
paramilitar.

ς  Artículo 23

   1. Los ciudadanos tienen el derecho a participar en los asun-
tos públicos, directamente o por medio de representantes, li-
bremente elegidos en elecciones periódicas por sufragio uni-
versal.

   2. Asimismo, tienen derecho a acceder en condiciones de
igualdad a las funciones y cargos públicos, con los requisitos
que señalen las leyes.

ς  Artículo 24

   1. Todas las personas tienen derecho a obtener la tutela
efectiva de los jueces y tribunales en el ejercicio de sus dere-
chos e intereses legítimos, sin que, en ningún caso, pueda
producirse indefensión.

   2. Asimismo, todos tienen derecho al Juez ordinario prede-
terminado por la ley, a la defensa y a la asistencia de letrado, a
ser informados de la acusación formulada contra ellos, a un
proceso público sin dilaciones indebidas y con todas las ga-
rantías, a utilizar los medios de prueba pertinentes para su

12
defensa, a no declarar contra sí mismos, a no confesarse cul-
pables y a la presunción de inocencia.

   La ley regulará los casos en que, por razón de parentesco o
de secreto profesional, no se estará obligado a declarar sobre
hechos presuntamente delictivos.

ς  Artículo 25

   1. Nadie puede ser condenado o sancionado por acciones u
omisiones que en el momento de producirse no constituyan
delito, falta o infracción administrativa, según la legislación
vigente en aquel momento.

   2. Las penas privativas de libertad y las medidas de seguridad
estarán orientadas hacia la reeducación y reinserción social y
no podrán consistir en trabajos forzados. El condenado a pena
de prisión que estuviere cumpliendo la misma gozará de los
derechos fundamentales de este Capítulo, a excepción de los
que se vean expresamente limitados por el contenido del fallo
condenatorio, el sentido de la pena y la ley penitenciaria. En
todo caso, tendrá derecho a un trabajo remunerado y a los
beneficios correspondientes de la Seguridad Social, así como
al acceso a la cultura y al desarrollo integral de su personali-
dad.

   3. La Administración civil no podrá imponer sanciones que,
directa o subsidiariamente, impliquen privación de libertad.

ς  Artículo 26

   Se prohíben los Tribunales de Honor en el ámbito de la Ad-
ministración civil y de las organizaciones profesionales.

ς  Artículo 27

   1. Todos tienen el derecho a la educación. Se reconoce la
libertad de enseñanza.

   2. La educación tendrá por objeto el pleno desarrollo de la
personalidad humana en el respeto a los principios democrá-
ticos de convivencia y a los derechos y libertades fundamen-
tales.

   3. Los poderes públicos garantizan el derecho que asiste a
los padres para que sus hijos reciban la formación religiosa y
moral que esté de acuerdo con sus propias convicciones.

   4. La enseñanza básica es obligatoria y gratuita.

                                                                                                     13
   5. Los poderes públicos garantizan el derecho de todos a la
educación, mediante una programación general de la ense-
ñanza, con participación efectiva de todos los sectores afecta-
dos y la creación de centros docentes.

   6. Se reconoce a las personas físicas y jurídicas la libertad de
creación de centros docentes, dentro del respeto a los princi-
pios constitucionales.

   7. Los profesores, los padres y, en su caso, los alumnos in-
tervendrán en el control y gestión de todos los centros soste-
nidos por la Administración con fondos públicos, en los térmi-
nos que la ley establezca.

   8. Los poderes públicos inspeccionarán y homologarán el
sistema educativo para garantizar el cumplimiento de las leyes.

   9. Los poderes públicos ayudarán a los centros docentes
que reúnan los requisitos que la ley establezca.

   10. Se reconoce la autonomía de las Universidades, en los
términos que la ley establezca.

ς  Artículo 28

   1. Todos tienen derecho a sindicarse libremente. La ley po-
drá limitar o exceptuar el ejercicio de este derecho a las Fuer-
zas o Institutos armados o a los demás Cuerpos sometidos a
disciplina militar y regulará las peculiaridades de su ejercicio
para los funcionarios públicos. La libertad sindical comprende
el derecho a fundar sindicatos y a afiliarse al de su elección,
así como el derecho de los sindicatos a formar confederacio-
nes y a fundar organizaciones sindicales internacionales o a
afiliarse a las mismas. Nadie podrá ser obligado a afiliarse a un
sindicato.

   2. Se reconoce el derecho a la huelga de los trabajadores para
la defensa de sus intereses. La ley que regule el ejercicio de este
derecho establecerá las garantías precisas para asegurar el
mantenimiento de los servicios esenciales de la comunidad.

ς  Artículo 29

   1. Todos los españoles tendrán el derecho de petición indi-
vidual y colectiva, por escrito, en la forma y con los efectos
que determine la ley.

   2. Los miembros de las Fuerzas o Institutos armados o de los
Cuerpos sometidos a disciplina militar podrán ejercer este de-

14
recho sólo individualmente y con arreglo a lo dispuesto en su
legislación específica.

     Sección 2.ª De los derechos y deberes de los ciudadanos

ς  Artículo 30

   1. Los españoles tienen el derecho y el deber de defender a
España.

   2. La ley fijará las obligaciones militares de los españoles y
regulará, con las debidas garantías, la objeción de conciencia,
así como las demás causas de exención del servicio militar
obligatorio, pudiendo imponer, en su caso, una prestación so-
cial sustitutoria.

   3. Podrá establecerse un servicio civil para el cumplimiento
de fines de interés general.

   4. Mediante ley podrán regularse los deberes de los ciuda-
danos en los casos de grave riesgo, catástrofe o calamidad
pública.

ς  Artículo 31

   1. Todos contribuirán al sostenimiento de los gastos públicos
de acuerdo con su capacidad económica mediante un sistema
tributario justo inspirado en los principios de igualdad y progre-
sividad que, en ningún caso, tendrá alcance confiscatorio.

   2. El gasto público realizará una asignación equitativa de los
recursos públicos, y su programación y ejecución responderán
a los criterios de eficiencia y economía.

   3. Sólo podrán establecerse prestaciones personales o patri-
moniales de carácter público con arreglo a la ley.

ς  Artículo 32

   1. El hombre y la mujer tienen derecho a contraer matrimo-
nio con plena igualdad jurídica.

   2. La ley regulará las formas de matrimonio, la edad y capa-
cidad para contraerlo, los derechos y deberes de los cónyuges,
las causas de separación y disolución y sus efectos.

ς  Artículo 33

   1. Se reconoce el derecho a la propiedad privada y a la he-
rencia.

                                                                                                     15
   2. La función social de estos derechos delimitará su conte-
nido, de acuerdo con las leyes.

   3. Nadie podrá ser privado de sus bienes y derechos sino por
causa justificada de utilidad pública o interés social, mediante
la correspondiente indemnización y de conformidad con lo
dispuesto por las leyes.

ς  Artículo 34

   1. Se reconoce el derecho de fundación para fines de interés
general, con arreglo a la ley.

   2. Regirá también para las fundaciones lo dispuesto en los
apartados 2 y 4 del artículo 22.

ς  Artículo 35

   1. Todos los españoles tienen el deber de trabajar y el dere-
cho al trabajo, a la libre elección de profesión u oficio, a la
promoción a través del trabajo y a una remuneración suficien-
te para satisfacer sus necesidades y las de su familia, sin que en
ningún caso pueda hacerse discriminación por razón de sexo.

   2. La ley regulará un estatuto de los trabajadores.

ς  Artículo 36

   La ley regulará las peculiaridades propias del régimen jurídi-
co de los Colegios Profesionales y el ejercicio de las profesio-
nes tituladas. La estructura interna y el funcionamiento de los
Colegios deberán ser democráticos.

ς  Artículo 37

   1. La ley garantizará el derecho a la negociación colectiva
laboral entre los representantes de los trabajadores y empre-
sarios, así como la fuerza vinculante de los convenios.

   2. Se reconoce el derecho de los trabajadores y empresarios
a adoptar medidas de conflicto colectivo. La ley que regule el
ejercicio de este derecho, sin perjuicio de las limitaciones que
puedan establecer, incluirá las garantías precisas para asegurar
el funcionamiento de los servicios esenciales de la comunidad.

ς  Artículo 38
   Se reconoce la libertad de empresa en el marco de la eco-

nomía de mercado. Los poderes públicos garantizan y prote-

16
gen su ejercicio y la defensa de la productividad, de acuerdo
con las exigencias de la economía general y, en su caso, de la
planificación.

                            CAPÍTULO TERCERO
 De los principios rectores de la política social y económica

ς  Artículo 39

   1. Los poderes públicos aseguran la protección social, eco-
nómica y jurídica de la familia.

   2. Los poderes públicos aseguran, asimismo, la protección
integral de los hijos, iguales éstos ante la ley con independen-
cia de su filiación, y de las madres, cualquiera que sea su esta-
do civil. La ley posibilitará la investigación de la paternidad.

   3. Los padres deben prestar asistencia de todo orden a los
hijos habidos dentro o fuera del matrimonio, durante su mino-
ría de edad y en los demás casos en que legalmente proceda.

   4. Los niños gozarán de la protección prevista en los acuer-
dos internacionales que velan por sus derechos.

ς  Artículo 40
   1. Los poderes públicos promoverán las condiciones favora-

bles para el progreso social y económico y para una distribu-
ción de la renta regional y personal más equitativa, en el mar-
co de una política de estabilidad económica. De manera
especial realizarán una política orientada al pleno empleo.

   2. Asimismo, los poderes públicos fomentarán una política
que garantice la formación y readaptación profesionales; vela-
rán por la seguridad e higiene en el trabajo y garantizarán el
descanso necesario, mediante la limitación de la jornada labo-
ral, las vacaciones periódicas retribuidas y la promoción de
centros adecuados.

ς  Artículo 41
   Los poderes públicos mantendrán un régimen público de

Seguridad Social para todos los ciudadanos, que garantice la
asistencia y prestaciones sociales suficientes ante situaciones
de necesidad, especialmente en caso de desempleo. La asis-
tencia y prestaciones complementarias serán libres.

                                                                                                     17
ς  Artículo 42

   El Estado velará especialmente por la salvaguardia de los
derechos económicos y sociales de los trabajadores españoles
en el extranjero y orientará su política hacia su retorno.

ς  Artículo 43

   1. Se reconoce el derecho a la protección de la salud.
   2. Compete a los poderes públicos organizar y tutelar la sa-
lud pública a través de medidas preventivas y de las prestacio-
nes y servicios necesarios. La ley establecerá los derechos y
deberes de todos al respecto.
   3. Los poderes públicos fomentarán la educación sanitaria,
la educación física y el deporte. Asimismo facilitarán la ade-
cuada utilización del ocio.

ς  Artículo 44

   1. Los poderes públicos promoverán y tutelarán el acceso a
la cultura, a la que todos tienen derecho.

   2. Los poderes públicos promoverán la ciencia y la investi-
gación científica y técnica en beneficio del interés general.

ς  Artículo 45

   1. Todos tienen el derecho a disfrutar de un medio ambiente
adecuado para el desarrollo de la persona, así como el deber
de conservarlo.

   2. Los poderes públicos velarán por la utilización racional de
todos los recursos naturales, con el fin de proteger y mejorar
la calidad de la vida y defender y restaurar el medio ambiente,
apoyándose en la indispensable solidaridad colectiva.

   3. Para quienes violen lo dispuesto en el apartado anterior,
en los términos que la ley fije se establecerán sanciones pena-
les o, en su caso, administrativas, así como la obligación de
reparar el daño causado.

ς  Artículo 46

   Los poderes públicos garantizarán la conservación y promo-
verán el enriquecimiento del patrimonio histórico, cultural y
artístico de los pueblos de España y de los bienes que lo inte-
gran, cualquiera que sea su régimen jurídico y su titularidad. La
ley penal sancionará los atentados contra este patrimonio.

18
ς  Artículo 47

   Todos los españoles tienen derecho a disfrutar de una vi-
vienda digna y adecuada. Los poderes públicos promoverán
las condiciones necesarias y establecerán las normas pertinen-
tes para hacer efectivo este derecho, regulando la utilización
del suelo de acuerdo con el interés general para impedir la
especulación. La comunidad participará en las plusvalías que
genere la acción urbanística de los entes públicos.

ς  Artículo 48

   Los poderes públicos promoverán las condiciones para la
participación libre y eficaz de la juventud en el desarrollo polí-
tico, social, económico y cultural.

ς  Artículo 49

   1. Las personas con discapacidad ejercen los derechos pre-
vistos en este Título en condiciones de libertad e igualdad
reales y efectivas. Se regulará por ley la protección especial
que sea necesaria para dicho ejercicio.

   2. Los poderes públicos impulsarán las políticas que garan-
ticen la plena autonomía personal y la inclusión social de las
personas con discapacidad, en entornos universalmente acce-
sibles. Asimismo, fomentarán la participación de sus organiza-
ciones, en los términos que la ley establezca. Se atenderán
particularmente las necesidades específicas de las mujeres y
los menores con discapacidad.

ς  Artículo 50

   Los poderes públicos garantizarán, mediante pensiones ade-
cuadas y periódicamente actualizadas, la suficiencia económica
a los ciudadanos durante la tercera edad. Asimismo, y con inde-
pendencia de las obligaciones familiares, promoverán su bien-
estar mediante un sistema de servicios sociales que atenderán
sus problemas específicos de salud, vivienda, cultura y ocio.

ς  Artículo 51

   1. Los poderes públicos garantizarán la defensa de los con-
sumidores y usuarios, protegiendo, mediante procedimientos
eficaces, la seguridad, la salud y los legítimos intereses econó-
micos de los mismos.

                                                                                                     19
   2. Los poderes públicos promoverán la información y la
educación de los consumidores y usuarios, fomentarán sus
organizaciones y oirán a éstas en las cuestiones que puedan
afectar a aquéllos, en los términos que la ley establezca.

   3. En el marco de lo dispuesto por los apartados anteriores,
la ley regulará el comercio interior y el régimen de autoriza-
ción de productos comerciales.

ς  Artículo 52

   La ley regulará las organizaciones profesionales que contri-
buyan a la defensa de los intereses económicos que les sean
propios. Su estructura interna y funcionamiento deberán ser
democráticos.

                            CAPÍTULO CUARTO
De las garantías de las libertades y derechos fundamentales

ς  Artículo 53

   1. Los derechos y libertades reconocidos en el Capítulo segun-
do del presente Título vinculan a todos los poderes públicos. Sólo
por ley, que en todo caso deberá respetar su contenido esencial,
podrá regularse el ejercicio de tales derechos y libertades, que se
tutelarán de acuerdo con lo previsto en el artículo 161, 1, a).

   2. Cualquier ciudadano podrá recabar la tutela de las liber-
tades y derechos reconocidos en el artículo 14 y la Sección
primera del Capítulo segundo ante los Tribunales ordinarios
por un procedimiento basado en los principios de preferencia
y sumariedad y, en su caso, a través del recurso de amparo
ante el Tribunal Constitucional. Este último recurso será apli-
cable a la objeción de conciencia reconocida en el artículo 30.

   3. El reconocimiento, el respeto y la protección de los princi-
pios reconocidos en el Capítulo tercero informarán la legisla-
ción positiva, la práctica judicial y la actuación de los poderes
públicos. Sólo podrán ser alegados ante la Jurisdicción ordinaria
de acuerdo con lo que dispongan las leyes que los desarrollen.

ς  Artículo 54

   Una ley orgánica regulará la institución del Defensor del
Pueblo, como alto comisionado de las Cortes Generales, de-

20
signado por éstas para la defensa de los derechos comprendi-
dos en este Título, a cuyo efecto podrá supervisar la actividad
de la Administración, dando cuenta a las Cortes Generales.

                            CAPÍTULO QUINTO
          De la suspensión de los derechos y libertades

ς  Artículo 55

   1. Los derechos reconocidos en los artículos 17, 18, apartados
2 y 3, artículos 19, 20, apartados 1, a) y d), y 5, artículos 21, 28,
apartado 2, y artículo 37, apartado 2, podrán ser suspendidos
cuando se acuerde la declaración del estado de excepción o de
sitio en los términos previstos en la Constitución. Se exceptúa
de lo establecido anteriormente el apartado 3 del artículo 17
para el supuesto de declaración de estado de excepción.

   2. Una ley orgánica podrá determinar la forma y los casos en
los que, de forma individual y con la necesaria intervención
judicial y el adecuado control parlamentario, los derechos re-
conocidos en los artículos 17, apartado 2, y 18, apartados 2 y 3,
pueden ser suspendidos para personas determinadas, en rela-
ción con las investigaciones correspondientes a la actuación
de bandas armadas o elementos terroristas.

   La utilización injustificada o abusiva de las facultades reco-
nocidas en dicha ley orgánica producirá responsabilidad penal,
como violación de los derechos y libertades reconocidos por
las leyes.

                                    TÍTULO II
                                 De la Corona

ς  Artículo 56

   1. El Rey es el Jefe del Estado, símbolo de su unidad y per-
manencia, arbitra y modera el funcionamiento regular de las
instituciones, asume la más alta representación del Estado
español en las relaciones internacionales, especialmente con
las naciones de su comunidad histórica, y ejerce las funciones
que le atribuyen expresamente la Constitución y las leyes.

   2. Su título es el de Rey de España y podrá utilizar los demás
que correspondan a la Corona.

                                                                                                     21
   3. La persona del Rey es inviolable y no está sujeta a respon-
sabilidad. Sus actos estarán siempre refrendados en la forma
establecida en el artículo 64, careciendo de validez sin dicho
refrendo, salvo lo dispuesto en el artículo 65, 2.

ς  Artículo 57

   1. La Corona de España es hereditaria en los sucesores de S.
M. Don Juan Carlos I de Borbón, legítimo heredero de la di-
nastía histórica. La sucesión en el trono seguirá el orden regu-
lar de primogenitura y representación, siendo preferida siem-
pre la línea anterior a las posteriores; en la misma línea, el
grado más próximo al más remoto; en el mismo grado, el va-
rón a la mujer, y en el mismo sexo, la persona de más edad a
la de menos.

   2. El Príncipe heredero, desde su nacimiento o desde que se
produzca el hecho que origine el llamamiento, tendrá la dig-
nidad de Príncipe de Asturias y los demás títulos vinculados
tradicionalmente al sucesor de la Corona de España.

   3. Extinguidas todas las líneas llamadas en Derecho, las Cor-
tes Generales proveerán a la sucesión en la Corona en la forma
que más convenga a los intereses de España.

   4. Aquellas personas que teniendo derecho a la sucesión en
el trono contrajeren matrimonio contra la expresa prohibición
del Rey y de las Cortes Generales, quedarán excluidas en la
sucesión a la Corona por sí y sus descendientes.

   5. Las abdicaciones y renuncias y cualquier duda de hecho
o de derecho que ocurra en el orden de sucesión a la Corona
se resolverán por una ley orgánica.

ς  Artículo 58

   La Reina consorte o el consorte de la Reina no podrán asu-
mir funciones constitucionales, salvo lo dispuesto para la Re-
gencia.

ς  Artículo 59

   1. Cuando el Rey fuere menor de edad, el padre o la madre
del Rey y, en su defecto, el pariente mayor de edad más próxi-
mo a suceder en la Corona, según el orden establecido en la
Constitución, entrará a ejercer inmediatamente la Regencia y
la ejercerá durante el tiempo de la minoría de edad del Rey.

22
   2. Si el Rey se inhabilitare para el ejercicio de su autoridad y
la imposibilidad fuere reconocida por las Cortes Generales,
entrará a ejercer inmediatamente la Regencia el Príncipe here-
dero de la Corona, si fuere mayor de edad. Si no lo fuere, se
procederá de la manera prevista en el apartado anterior, hasta
que el Príncipe heredero alcance la mayoría de edad.

   3. Si no hubiere ninguna persona a quien corresponda la
Regencia, ésta será nombrada por las Cortes Generales, y se
compondrá de una, tres o cinco personas.

   4. Para ejercer la Regencia es preciso ser español y mayor de
edad.

   5. La Regencia se ejercerá por mandato constitucional y
siempre en nombre del Rey.

ς  Artículo 60

   1. Será tutor del Rey menor la persona que en su testamen-
to hubiese nombrado el Rey difunto, siempre que sea mayor
de edad y español de nacimiento; si no lo hubiese nombrado,
será tutor el padre o la madre mientras permanezcan viudos.
En su defecto, lo nombrarán las Cortes Generales, pero no
podrán acumularse los cargos de Regente y de tutor sino en el
padre, madre o ascendientes directos del Rey.

   2. El ejercicio de la tutela es también incompatible con el de
todo cargo o representación política.

ς  Artículo 61

   1. El Rey, al ser proclamado ante las Cortes Generales,
prestará juramento de desempeñar fielmente sus funciones,
guardar y hacer guardar la Constitución y las leyes y respe-
tar los derechos de los ciudadanos y de las Comunidades
Autónomas.

   2. El Príncipe heredero, al alcanzar la mayoría de edad, y el
Regente o Regentes al hacerse cargo de sus funciones, pres-
tarán el mismo juramento, así como el de fidelidad al Rey.

ς  Artículo 62

   Corresponde al Rey:

   a) Sancionar y promulgar las leyes.
   b) Convocar y disolver las Cortes Generales y convocar

      elecciones en los términos previstos en la Constitución.

                                                                                                     23
   c) Convocar a referéndum en los casos previstos en la Cons-
      titución.

   d) Proponer el candidato a Presidente del Gobierno y, en su
      caso, nombrarlo, así como poner fin a sus funciones en
      los términos previstos en la Constitución.

   e) Nombrar y separar a los miembros del Gobierno, a pro-
      puesta de su Presidente.

   f) Expedir los decretos acordados en el Consejo de Minis-
      tros, conferir los empleos civiles y militares y conceder
      honores y distinciones con arreglo a las leyes.

   g) Ser informado de los asuntos de Estado y presidir, a estos
      efectos, las sesiones del Consejo de Ministros, cuando lo
      estime oportuno, a petición del Presidente del Gobierno.

   h) El mando supremo de las Fuerzas Armadas.
   i) Ejercer el derecho de gracia con arreglo a la ley, que no

      podrá autorizar indultos generales.
   j) El Alto Patronazgo de las Reales Academias.

ς  Artículo 63

   1. El Rey acredita a los embajadores y otros representantes
diplomáticos. Los representantes extranjeros en España están
acreditados ante él.

   2. Al Rey corresponde manifestar el consentimiento del Es-
tado para obligarse internacionalmente por medio de tratados,
de conformidad con la Constitución y las leyes.

   3. Al Rey corresponde, previa autorización de las Cortes Ge-
nerales, declarar la guerra y hacer la paz.

ς  Artículo 64

   1. Los actos del Rey serán refrendados por el Presidente del
Gobierno y, en su caso, por los Ministros competentes. La pro-
puesta y el nombramiento del Presidente del Gobierno, y la
disolución prevista en el artículo 99, serán refrendados por el
Presidente del Congreso.

   2. De los actos del Rey serán responsables las personas que
los refrenden.

ς  Artículo 65

   1. El Rey recibe de los Presupuestos del Estado una cantidad
global para el sostenimiento de su Familia y Casa, y distribuye
libremente la misma.

24
   2. El Rey nombra y releva libremente a los miembros civiles
y militares de su Casa.

                                   TÍTULO III
                          De las Cortes Generales

                            CAPÍTULO PRIMERO
                                De las Cámaras

ς  Artículo 66

   1. Las Cortes Generales representan al pueblo español y es-
tán formadas por el Congreso de los Diputados y el Senado.

   2. Las Cortes Generales ejercen la potestad legislativa del
Estado, aprueban sus Presupuestos, controlan la acción del
Gobierno y tienen las demás competencias que les atribuya la
Constitución.

   3. Las Cortes Generales son inviolables.

ς  Artículo 67
   1. Nadie podrá ser miembro de las dos Cámaras simultánea-

mente, ni acumular el acta de una Asamblea de Comunidad
Autónoma con la de Diputado al Congreso.

   2. Los miembros de las Cortes Generales no estarán ligados
por mandato imperativo.

   3. Las reuniones de Parlamentarios que se celebren sin con-
vocatoria reglamentaria no vincularán a las Cámaras, y no po-
drán ejercer sus funciones ni ostentar sus privilegios.

ς  Artículo 68
   1. El Congreso se compone de un mínimo de 300 y un máxi-

mo de 400 Diputados, elegidos por sufragio universal, libre,
igual, directo y secreto, en los términos que establezca la ley.

   2. La circunscripción electoral es la provincia. Las poblaciones
de Ceuta y Melilla estarán representadas cada una de ellas por un
Diputado. La ley distribuirá el número total de Diputados, asig-
nando una representación mínima inicial a cada circunscripción
y distribuyendo los demás en proporción a la población.

   3. La elección se verificará en cada circunscripción aten-
diendo a criterios de representación proporcional.

                                                                                                     25
   4. El Congreso es elegido por cuatro años. El mandato de
los Diputados termina cuatro años después de su elección o el
día de la disolución de la Cámara.

   5. Son electores y elegibles todos los españoles que estén
en pleno uso de sus derechos políticos.

   La ley reconocerá y el Estado facilitará el ejercicio del dere-
cho de sufragio a los españoles que se encuentren fuera del
territorio de España.

   6. Las elecciones tendrán lugar entre los treinta días y se-
senta días desde la terminación del mandato. El Congreso
electo deberá ser convocado dentro de los veinticinco días
siguientes a la celebración de las elecciones.

ς  Artículo 69

   1. El Senado es la Cámara de representación territorial.
   2. En cada provincia se elegirán cuatro Senadores por sufra-
gio universal, libre, igual, directo y secreto por los votantes de
cada una de ellas, en los términos que señale una ley orgánica.
   3. En las provincias insulares, cada isla o agrupación de ellas,
con Cabildo o Consejo Insular, constituirá una circunscripción
a efectos de elección de Senadores, correspondiendo tres a
cada una de las islas mayores –Gran Canaria, Mallorca y Tene-
rife– y uno a cada una de las siguientes islas o agrupaciones:
Ibiza-Formentera, Menorca, Fuerteventura, Gomera, Hierro,
Lanzarote y La Palma.
   4. Las poblaciones de Ceuta y Melilla elegirán cada una de
ellas dos Senadores.
   5. Las Comunidades Autónomas designarán además un Senador
y otro más por cada millón de habitantes de su respectivo territo-
rio. La designación corresponderá a la Asamblea legislativa o, en su
defecto, al órgano colegiado superior de la Comunidad Autónoma,
de acuerdo con lo que establezcan los Estatutos, que asegurarán,
en todo caso, la adecuada representación proporcional.
   6. El Senado es elegido por cuatro años. El mandato de los
Senadores termina cuatro años después de su elección o el día
de la disolución de la Cámara.

ς  Artículo 70

   1. La ley electoral determinará las causas de inelegibilidad e
incompatibilidad de los Diputados y Senadores, que compren-
derán, en todo caso:

26
     a)	A los componentes del Tribunal Constitucional.
     b)	A los altos cargos de la Administración del Estado que

         determine la ley, con la excepción de los miembros del
         Gobierno.
     c)	Al Defensor del Pueblo.
     d)	A los Magistrados, Jueces y Fiscales en activo.
     e)	A los militares profesionales y miembros de las Fuerzas
         y Cuerpos de Seguridad y Policía en activo.
     f)	A los miembros de las Juntas Electorales.

   2. La validez de las actas y credenciales de los miembros de
ambas Cámaras estará sometida al control judicial, en los tér-
minos que establezca la ley electoral.

ς  Artículo 71

   1. Los Diputados y Senadores gozarán de inviolabilidad por
las opiniones manifestadas en el ejercicio de sus funciones.

   2. Durante el período de su mandato los Diputados y Sena-
dores gozarán asimismo de inmunidad y sólo podrán ser de-
tenidos en caso de flagrante delito. No podrán ser inculpados
ni procesados sin la previa autorización de la Cámara respec-
tiva.

   3. En las causas contra Diputados y Senadores será compe-
tente la Sala de lo Penal del Tribunal Supremo.

   4. Los Diputados y Senadores percibirán una asignación que
será fijada por las respectivas Cámaras.

ς  Artículo 72

   1. Las Cámaras establecen sus propios Reglamentos, aprue-
ban autónomamente sus presupuestos y, de común acuerdo,
regulan el Estatuto del Personal de las Cortes Generales. Los
Reglamentos y su reforma serán sometidos a una votación fi-
nal sobre su totalidad, que requerirá la mayoría absoluta.

   2. Las Cámaras eligen sus respectivos Presidentes y los de-
más miembros de sus Mesas. Las sesiones conjuntas serán
presididas por el Presidente del Congreso y se regirán por un
Reglamento de las Cortes Generales aprobado por mayoría
absoluta de cada Cámara.

   3. Los Presidentes de las Cámaras ejercen en nombre de las
mismas todos los poderes administrativos y facultades de po-
licía en el interior de sus respectivas sedes.

                                                                                                     27
ς  Artículo 73

   1. Las Cámaras se reunirán anualmente en dos períodos or-
dinarios de sesiones: el primero, de septiembre a diciembre, y
el segundo, de febrero a junio.

   2. Las Cámaras podrán reunirse en sesiones extraordinarias
a petición del Gobierno, de la Diputación Permanente o de la
mayoría absoluta de los miembros de cualquiera de las Cáma-
ras. Las sesiones extraordinarias deberán convocarse sobre un
orden del día determinado y serán clausuradas una vez que
éste haya sido agotado.

ς  Artículo 74

   1. Las Cámaras se reunirán en sesión conjunta para ejercer
las competencias no legislativas que el Título II atribuye expre-
samente a las Cortes Generales.

   2. Las decisiones de las Cortes Generales previstas en los artí-
culos 94, 1, 145, 2 y 158, 2, se adoptarán por mayoría de cada una
de las Cámaras. En el primer caso, el procedimiento se iniciará
por el Congreso, y en los otros dos, por el Senado. En ambos
casos, si no hubiera acuerdo entre Senado y Congreso, se inten-
tará obtener por una Comisión Mixta compuesta de igual núme-
ro de Diputados y Senadores. La Comisión presentará un texto
que será votado por ambas Cámaras. Si no se aprueba en la forma
establecida, decidirá el Congreso por mayoría absoluta.

ς  Artículo 75

   1. Las Cámaras funcionarán en Pleno y por Comisiones.
   2. Las Cámaras podrán delegar en las Comisiones Legislati-
vas Permanentes la aprobación de proyectos o proposiciones
de ley. El Pleno podrá, no obstante, recabar en cualquier mo-
mento el debate y votación de cualquier proyecto o proposi-
ción de ley que haya sido objeto de esta delegación.
   3. Quedan exceptuados de lo dispuesto en el apartado an-
terior la reforma constitucional, las cuestiones internacionales,
las leyes orgánicas y de bases y los Presupuestos Generales del
Estado.

ς  Artículo 76

   1. El Congreso y el Senado, y, en su caso, ambas Cámaras
conjuntamente, podrán nombrar Comisiones de investigación

28
sobre cualquier asunto de interés público. Sus conclusiones no
serán vinculantes para los Tribunales, ni afectarán a las resolu-
ciones judiciales, sin perjuicio de que el resultado de la inves-
tigación sea comunicado al Ministerio Fiscal para el ejercicio,
cuando proceda, de las acciones oportunas.

   2. Será obligatorio comparecer a requerimiento de las Cá-
maras. La ley regulará las sanciones que puedan imponerse
por incumplimiento de esta obligación.

ς  Artículo 77

   1. Las Cámaras pueden recibir peticiones individuales y co-
lectivas, siempre por escrito, quedando prohibida la presenta-
ción directa por manifestaciones ciudadanas.

   2. Las Cámaras pueden remitir al Gobierno las peticiones
que reciban. El Gobierno está obligado a explicarse sobre su
contenido, siempre que las Cámaras lo exijan.

ς  Artículo 78

   1. En cada Cámara habrá una Diputación Permanente com-
puesta por un mínimo de veintiún miembros, que representa-
rán a los grupos parlamentarios, en proporción a su importan-
cia numérica.

   2. Las Diputaciones Permanentes estarán presididas por el
Presidente de la Cámara respectiva y tendrán como funciones
la prevista en el artículo 73, la de asumir las facultades que
correspondan a las Cámaras, de acuerdo con los artículos 86
y 116, en caso de que éstas hubieren sido disueltas o hubiere
expirado su mandato y la de velar por los poderes de las Cá-
maras cuando éstas no estén reunidas.

   3. Expirado el mandato o en caso de disolución, las Diputa-
ciones Permanentes seguirán ejerciendo sus funciones hasta
la constitución de las nuevas Cortes Generales.

   4. Reunida la Cámara correspondiente, la Diputación Per-
manente dará cuenta de los asuntos tratados y de sus decisio-
nes.

ς  Artículo 79

   1. Para adoptar acuerdos, las Cámaras deben estar reunidas
reglamentariamente y con asistencia de la mayoría de sus
miembros.

                                                                                                     29
   2. Dichos acuerdos, para ser válidos, deberán ser aprobados
por la mayoría de los miembros presentes, sin perjuicio de las
mayorías especiales que establezcan la Constitución o las le-
yes orgánicas y las que para elección de personas establezcan
los Reglamentos de las Cámaras.

   3. El voto de Senadores y Diputados es personal e indelega-
ble.

ς  Artículo 80

   Las sesiones plenarias de las Cámaras serán públicas, salvo
acuerdo en contrario de cada Cámara, adoptado por mayoría
absoluta o con arreglo al Reglamento.

                           CAPÍTULO SEGUNDO
                     De la elaboración de las leyes

ς  Artículo 81

   1. Son leyes orgánicas las relativas al desarrollo de los dere-
chos fundamentales y de las libertades públicas, las que aprue-
ben los Estatutos de Autonomía y el régimen electoral general
y las demás previstas en la Constitución.

   2. La aprobación, modificación o derogación de las leyes
orgánicas exigirá mayoría absoluta del Congreso, en una vota-
ción final sobre el conjunto del proyecto.

ς  Artículo 82
   1. Las Cortes Generales podrán delegar en el Gobierno la

potestad de dictar normas con rango de ley sobre materias
determinadas no incluidas en el artículo anterior.

   2. La delegación legislativa deberá otorgarse mediante una
ley de bases cuando su objeto sea la formación de textos arti-
culados o por una ley ordinaria cuando se trate de refundir
varios textos legales en uno solo.

   3. La delegación legislativa habrá de otorgarse al Gobierno de
forma expresa para materia concreta y con fijación del plazo
para su ejercicio. La delegación se agota por el uso que de ella
haga el Gobierno mediante la publicación de la norma corres-
pondiente. No podrá entenderse concedida de modo implícito
o por tiempo indeterminado. Tampoco podrá permitir la subde-
legación a autoridades distintas del propio Gobierno.

30
   4. Las leyes de bases delimitarán con precisión el objeto y
alcance de la delegación legislativa y los principios y criterios
que han de seguirse en su ejercicio.

   5. La autorización para refundir textos legales determinará el
ámbito normativo a que se refiere el contenido de la delega-
ción, especificando si se circunscribe a la mera formulación de
un texto único o si se incluye la de regularizar, aclarar y armo-
nizar los textos legales que han de ser refundidos.

   6. Sin perjuicio de la competencia propia de los Tribunales,
las leyes de delegación podrán establecer en cada caso fór-
mulas adicionales de control.

ς  Artículo 83

   Las leyes de bases no podrán en ningún caso:

   a) Autorizar la modificación de la propia ley de bases.
   b) Facultar para dictar normas con carácter retroactivo.

ς  Artículo 84

   Cuando una proposición de ley o una enmienda fuere con-
traria a una delegación legislativa en vigor, el Gobierno está
facultado para oponerse a su tramitación. En tal supuesto,
podrá presentarse una proposición de ley para la derogación
total o parcial de la ley de delegación.

ς  Artículo 85

   Las disposiciones del Gobierno que contengan legislación
delegada recibirán el título de Decretos Legislativos.

ς  Artículo 86

   1. En caso de extraordinaria y urgente necesidad, el Gobier-
no podrá dictar disposiciones legislativas provisionales que
tomarán la forma de Decretos-leyes y que no podrán afectar
al ordenamiento de las instituciones básicas del Estado, a los
derechos, deberes y libertades de los ciudadanos regulados en
el Título I, al régimen de las Comunidades Autónomas ni al
Derecho electoral general.

   2. Los Decretos-leyes deberán ser inmediatamente someti-
dos a debate y votación de totalidad al Congreso de los Dipu-
tados, convocado al efecto si no estuviere reunido, en el plazo
de los treinta días siguientes a su promulgación. El Congreso

                                                                                                     31
habrá de pronunciarse expresamente dentro de dicho plazo
sobre su convalidación o derogación, para lo cual el Regla-
mento establecerá un procedimiento especial y sumario.

   3. Durante el plazo establecido en el apartado anterior, las
Cortes podrán tramitarlos como proyectos de ley por el pro-
cedimiento de urgencia.

ς  Artículo 87

   1. La iniciativa legislativa corresponde al Gobierno, al Con-
greso y al Senado, de acuerdo con la Constitución y los Regla-
mentos de las Cámaras.

   2. Las Asambleas de las Comunidades Autónomas podrán
solicitar del Gobierno la adopción de un proyecto de ley o
remitir a la Mesa del Congreso una proposición de ley, dele-
gando ante dicha Cámara un máximo de tres miembros de la
Asamblea encargados de su defensa.

   3. Una ley orgánica regulará las formas de ejercicio y requi-
sitos de la iniciativa popular para la presentación de proposi-
ciones de ley. En todo caso se exigirán no menos de 500.000
firmas acreditadas. No procederá dicha iniciativa en materias
propias de ley orgánica, tributarias o de carácter internacional,
ni en lo relativo a la prerrogativa de gracia.

ς  Artículo 88

   Los proyectos de ley serán aprobados en Consejo de Minis-
tros, que los someterá al Congreso, acompañados de una ex-
posición de motivos y de los antecedentes necesarios para
pronunciarse sobre ellos.

ς  Artículo 89

   1. La tramitación de las proposiciones de ley se regulará por
los Reglamentos de las Cámaras, sin que la prioridad debida a
los proyectos de ley impida el ejercicio de la iniciativa legisla-
tiva en los términos regulados por el artículo 87.

   2. Las proposiciones de ley que, de acuerdo con el artículo
87, tome en consideración el Senado, se remitirán al Congreso
para su trámite en éste como tal proposición.

ς  Artículo 90

   1. Aprobado un proyecto de ley ordinaria u orgánica por el
Congreso de los Diputados, su Presidente dará inmediata

32
cuenta del mismo al Presidente del Senado, el cual lo somete-
rá a la deliberación de éste.

   2. El Senado en el plazo de dos meses, a partir del día de la
recepción del texto, puede, mediante mensaje motivado, opo-
ner su veto o introducir enmiendas al mismo. El veto deberá
ser aprobado por mayoría absoluta. El proyecto no podrá ser
sometido al Rey para sanción sin que el Congreso ratifique por
mayoría absoluta, en caso de veto, el texto inicial, o por ma-
yoría simple, una vez transcurridos dos meses desde la inter-
posición del mismo, o se pronuncie sobre las enmiendas,
aceptándolas o no por mayoría simple.

   3. El plazo de dos meses de que el Senado dispone para
vetar o enmendar el proyecto se reducirá al de veinte días na-
turales en los proyectos declarados urgentes por el Gobierno
o por el Congreso de los Diputados.

ς  Artículo 91

   El Rey sancionará en el plazo de quince días las leyes apro-
badas por las Cortes Generales, y las promulgará y ordenará su
inmediata publicación.

ς  Artículo 92

   1. Las decisiones políticas de especial trascendencia podrán
ser sometidas a referéndum consultivo de todos los ciudada-
nos.

   2. El referéndum será convocado por el Rey, mediante pro-
puesta del Presidente del Gobierno, previamente autorizada
por el Congreso de los Diputados.

   3. Una ley orgánica regulará las condiciones y el procedi-
miento de las distintas modalidades de referéndum previstas
en esta Constitución.

                            CAPÍTULO TERCERO
                    De los Tratados Internacionales

ς  Artículo 93

   Mediante ley orgánica se podrá autorizar la celebración de
tratados por los que se atribuya a una organización o institu-
ción internacional el ejercicio de competencias derivadas de la
Constitución. Corresponde a las Cortes Generales o al Gobier-

                                                                                                     33
no, según los casos, la garantía del cumplimiento de estos
tratados y de las resoluciones emanadas de los organismos
internacionales o supranacionales titulares de la cesión.

ς  Artículo 94

   1. La prestación del consentimiento del Estado para obligar-
se por medio de tratados o convenios requerirá la previa auto-
rización de las Cortes Generales, en los siguientes casos:

     a)	Tratados de carácter político.
     b)	T ratados o convenios de carácter militar.
     c)	T ratados o convenios que afecten a la integridad terri-

         torial del Estado o a los derechos y deberes fundamen-
         tales establecidos en el Título I.
     d)	T ratados o convenios que impliquen obligaciones fi-
         nancieras para la Hacienda Pública.
     e)	T ratados o convenios que supongan modificación o
         derogación de alguna ley o exijan medidas legislativas
         para su ejecución.

   2. El Congreso y el Senado serán inmediatamente informa-
dos de la conclusión de los restantes tratados o convenios.

ς  Artículo 95

   1. La celebración de un tratado internacional que contenga
estipulaciones contrarias a la Constitución exigirá la previa re-
visión constitucional.

   2. El Gobierno o cualquiera de las Cámaras puede requerir
al Tribunal Constitucional para que declare si existe o no esa
contradicción.

ς  Artículo 96

   1. Los tratados internacionales válidamente celebrados, una
vez publicados oficialmente en España, formarán parte del or-
denamiento interno. Sus disposiciones sólo podrán ser dero-
gadas, modificadas o suspendidas en la forma prevista en los
propios tratados o de acuerdo con las normas generales del
Derecho internacional.

   2. Para la denuncia de los tratados y convenios internacio-
nales se utilizará el mismo procedimiento previsto para su
aprobación en el artículo 94.

34
                                   TÍTULO IV

                 Del Gobierno y de la Administración

ς  Artículo 97

   El Gobierno dirige la política interior y exterior, la Adminis-
tración civil y militar y la defensa del Estado. Ejerce la función
ejecutiva y la potestad reglamentaria de acuerdo con la Cons-
titución y las leyes.

ς  Artículo 98

   1. El Gobierno se compone del Presidente, de los Vicepresi-
dentes, en su caso, de los Ministros y de los demás miembros
que establezca la ley.

   2. El Presidente dirige la acción del Gobierno y coordina las
funciones de los demás miembros del mismo, sin perjuicio de la
competencia y responsabilidad directa de éstos en su gestión.

   3. Los miembros del Gobierno no podrán ejercer otras fun-
ciones representativas que las propias del mandato parlamen-
tario, ni cualquier otra función pública que no derive de su
cargo, ni actividad profesional o mercantil alguna.

   4. La ley regulará el estatuto e incompatibilidades de los
miembros del Gobierno.

ς  Artículo 99

   1. Después de cada renovación del Congreso de los Diputa-
dos, y en los demás supuestos constitucionales en que así
proceda, el Rey, previa consulta con los representantes desig-
nados por los Grupos políticos con representación parlamen-
taria, y a través del Presidente del Congreso, propondrá un
candidato a la Presidencia del Gobierno.

   2. El candidato propuesto conforme a lo previsto en el apar-
tado anterior expondrá ante el Congreso de los Diputados el
programa político del Gobierno que pretenda formar y solici-
tará la confianza de la Cámara.

   3. Si el Congreso de los Diputados, por el voto de la mayoría
absoluta de sus miembros, otorgare su confianza a dicho can-
didato, el Rey le nombrará Presidente. De no alcanzarse dicha
mayoría, se someterá la misma propuesta a nueva votación
cuarenta y ocho horas después de la anterior, y la confianza se
entenderá otorgada si obtuviere la mayoría simple.

                                                                                                     35
   4. Si efectuadas las citadas votaciones no se otorgase la
confianza para la investidura, se tramitarán sucesivas propues-
tas en la forma prevista en los apartados anteriores.

   5. Si transcurrido el plazo de dos meses, a partir de la prime-
ra votación de investidura, ningún candidato hubiere obtenido
la confianza del Congreso, el Rey disolverá ambas Cámaras y
convocará nuevas elecciones con el refrendo del Presidente
del Congreso.

ς  Artículo 100

   Los demás miembros del Gobierno serán nombrados y se-
parados por el Rey, a propuesta de su Presidente.

ς  Artículo 101

   1. El Gobierno cesa tras la celebración de elecciones gene-
rales, en los casos de pérdida de la confianza parlamentaria
previstos en la Constitución, o por dimisión o fallecimiento de
su Presidente.

   2. El Gobierno cesante continuará en funciones hasta la
toma de posesión del nuevo Gobierno.

ς  Artículo 102

   1. La responsabilidad criminal del Presidente y los demás
miembros del Gobierno será exigible, en su caso, ante la Sala
de lo Penal del Tribunal Supremo.

   2. Si la acusación fuere por traición o por cualquier delito
contra la seguridad del Estado en el ejercicio de sus funciones,
sólo podrá ser planteada por iniciativa de la cuarta parte de los
miembros del Congreso, y con la aprobación de la mayoría
absoluta del mismo.

   3. La prerrogativa real de gracia no será aplicable a ninguno
de los supuestos del presente artículo.

ς  Artículo 103

   1. La Administración Pública sirve con objetividad los intere-
ses generales y actúa de acuerdo con los principios de eficacia,
jerarquía, descentralización, desconcentración y coordinación,
con sometimiento pleno a la ley y al Derecho.

   2. Los órganos de la Administración del Estado son creados,
regidos y coordinados de acuerdo con la ley.

36
   3. La ley regulará el estatuto de los funcionarios públicos,
el acceso a la función pública de acuerdo con los principios
de mérito y capacidad, las peculiaridades del ejercicio de su
derecho a sindicación, el sistema de incompatibilidades y
las garantías para la imparcialidad en el ejercicio de sus fun-
ciones.

ς  Artículo 104

   1. Las Fuerzas y Cuerpos de seguridad, bajo la dependencia
del Gobierno, tendrán como misión proteger el libre ejercicio
de los derechos y libertades y garantizar la seguridad ciudadana.

   2. Una ley orgánica determinará las funciones, principios
básicos de actuación y estatutos de las Fuerzas y Cuerpos de
seguridad.

ς  Artículo 105

   La ley regulará:

   a) La audiencia de los ciudadanos, directamente o a través
      de las organizaciones y asociaciones reconocidas por la
      ley, en el procedimiento de elaboración de las disposicio-
      nes administrativas que les afecten.

   b) El acceso de los ciudadanos a los archivos y registros ad-
      ministrativos, salvo en lo que afecte a la seguridad y de-
      fensa del Estado, la averiguación de los delitos y la intimi-
      dad de las personas.

   c) El procedimiento a través del cual deben producirse los
      actos administrativos, garantizando, cuando proceda, la
      audiencia del interesado.

ς  Artículo 106

   1. Los Tribunales controlan la potestad reglamentaria y la
legalidad de la actuación administrativa, así como el someti-
miento de ésta a los fines que la justifican.

   2. Los particulares, en los términos establecidos por la ley,
tendrán derecho a ser indemnizados por toda lesión que su-
fran en cualquiera de sus bienes y derechos, salvo en los casos
de fuerza mayor, siempre que la lesión sea consecuencia del
funcionamiento de los servicios públicos.

                                                                                                     37
ς  Artículo 107
   El Consejo de Estado es el supremo órgano consultivo del

Gobierno. Una ley orgánica regulará su composición y com-
petencia.

                                    TÍTULO V
 De las relaciones entre el Gobierno y las Cortes Generales

ς  Artículo 108
   El Gobierno responde solidariamente en su gestión política

ante el Congreso de los Diputados.

ς  Artículo 109
   Las Cámaras y sus Comisiones podrán recabar, a través de

los Presidentes de aquéllas, la información y ayuda que preci-
sen del Gobierno y de sus Departamentos y de cualesquiera
autoridades del Estado y de las Comunidades Autónomas.

ς  Artículo 110
   1. Las Cámaras y sus Comisiones pueden reclamar la pre-

sencia de los miembros del Gobierno.
   2. Los miembros del Gobierno tienen acceso a las sesiones

de las Cámaras y a sus Comisiones y la facultad de hacerse oír
en ellas, y podrán solicitar que informen ante las mismas fun-
cionarios de sus Departamentos.

ς  Artículo 111
   1. El Gobierno y cada uno de sus miembros están sometidos

a las interpelaciones y preguntas que se le formulen en las
Cámaras. Para esta clase de debate los Reglamentos estable-
cerán un tiempo mínimo semanal.

   2. Toda interpelación podrá dar lugar a una moción en la
que la Cámara manifieste su posición.

ς  Artículo 112
   El Presidente del Gobierno, previa deliberación del Consejo

de Ministros, puede plantear ante el Congreso de los Diputa-
dos la cuestión de confianza sobre su programa o sobre una
declaración de política general. La confianza se entenderá

38
otorgada cuando vote a favor de la misma la mayoría simple
de los Diputados.

ς  Artículo 113

   1. El Congreso de los Diputados puede exigir la responsabi-
lidad política del Gobierno mediante la adopción por mayoría
absoluta de la moción de censura.

   2. La moción de censura deberá ser propuesta al menos por
la décima parte de los Diputados, y habrá de incluir un candi-
dato a la Presidencia del Gobierno.

   3. La moción de censura no podrá ser votada hasta que
transcurran cinco días desde su presentación. En los dos pri-
meros días de dicho plazo podrán presentarse mociones alter-
nativas.

   4. Si la moción de censura no fuere aprobada por el Con-
greso, sus signatarios no podrán presentar otra durante el mis-
mo período de sesiones.

ς  Artículo 114

   1. Si el Congreso niega su confianza al Gobierno, éste pre-
sentará su dimisión al Rey, procediéndose a continuación a la
designación de Presidente del Gobierno, según lo dispuesto en
el artículo 99.

   2. Si el Congreso adopta una moción de censura, el Gobier-
no presentará su dimisión al Rey y el candidato incluido en
aquélla se entenderá investido de la confianza de la Cámara a
los efectos previstos en el artículo 99. El Rey le nombrará Pre-
sidente del Gobierno.

ς  Artículo 115

   1. El Presidente del Gobierno, previa deliberación del Con-
sejo de Ministros, y bajo su exclusiva responsabilidad, podrá
proponer la disolución del Congreso, del Senado o de las Cor-
tes Generales, que será decretada por el Rey. El decreto de
disolución fijará la fecha de las elecciones.

   2. La propuesta de disolución no podrá presentarse cuando
esté en trámite una moción de censura.

   3. No procederá nueva disolución antes de que transcurra
un año desde la anterior, salvo lo dispuesto en el artículo 99,
apartado 5.

                                                                                                     39
ς  Artículo 116

   1. Una ley orgánica regulará los estados de alarma, de ex-
cepción y de sitio, y las competencias y limitaciones corres-
pondientes.

   2. El estado de alarma será declarado por el Gobierno me-
diante decreto acordado en Consejo de Ministros por un plazo
máximo de quince días, dando cuenta al Congreso de los Di-
putados, reunido inmediatamente al efecto y sin cuya autori-
zación no podrá ser prorrogado dicho plazo. El decreto deter-
minará el ámbito territorial a que se extienden los efectos de
la declaración.

   3. El estado de excepción será declarado por el Gobierno
mediante decreto acordado en Consejo de Ministros, previa
autorización del Congreso de los Diputados. La autorización y
proclamación del estado de excepción deberá determinar ex-
presamente los efectos del mismo, el ámbito territorial a que
se extiende y su duración, que no podrá exceder de treinta
días, prorrogables por otro plazo igual, con los mismos requi-
sitos.

   4. El estado de sitio será declarado por la mayoría absoluta
del Congreso de los Diputados, a propuesta exclusiva del Go-
bierno. El Congreso determinará su ámbito territorial, duración
y condiciones.

   5. No podrá procederse a la disolución del Congreso mien-
tras estén declarados algunos de los estados comprendidos en
el presente artículo, quedando automáticamente convocadas
las Cámaras si no estuvieren en período de sesiones. Su fun-
cionamiento, así como el de los demás poderes constitucio-
nales del Estado, no podrán interrumpirse durante la vigencia
de estos estados.

   Disuelto el Congreso o expirado su mandato, si se produje-
re alguna de las situaciones que dan lugar a cualquiera de di-
chos estados, las competencias del Congreso serán asumidas
por su Diputación Permanente.

   6. La declaración de los estados de alarma, de excepción y
de sitio no modificarán el principio de responsabilidad del Go-
bierno y de sus agentes reconocidos en la Constitución y en
las leyes.

40
                                   TÍTULO VI
                             Del Poder Judicial

ς  Artículo 117

   1. La justicia emana del pueblo y se administra en nombre
del Rey por Jueces y Magistrados integrantes del poder judi-
cial, independientes, inamovibles, responsables y sometidos
únicamente al imperio de la ley.

   2. Los Jueces y Magistrados no podrán ser separados, sus-
pendidos, trasladados ni jubilados, sino por alguna de las cau-
sas y con las garantías previstas en la ley.

   3. El ejercicio de la potestad jurisdiccional en todo tipo de
procesos, juzgando y haciendo ejecutar lo juzgado, corres-
ponde exclusivamente a los Juzgados y Tribunales determina-
dos por las leyes, según las normas de competencia y proce-
dimiento que las mismas establezcan.

   4. Los Juzgados y Tribunales no ejercerán más funciones que
las señaladas en el apartado anterior y las que expresamente les
sean atribuidas por ley en garantía de cualquier derecho.

   5. El principio de unidad jurisdiccional es la base de la orga-
nización y funcionamiento de los Tribunales. La ley regulará el
ejercicio de la jurisdicción militar en el ámbito estrictamente
castrense y en los supuestos de estado de sitio, de acuerdo
con los principios de la Constitución.

   6. Se prohíben los Tribunales de excepción.

ς  Artículo 118

   Es obligado cumplir las sentencias y demás resoluciones
firmes de los Jueces y Tribunales, así como prestar la colabo-
ración requerida por éstos en el curso del proceso y en la eje-
cución de lo resuelto.

ς  Artículo 119

   La justicia será gratuita cuando así lo disponga la ley y, en
todo caso, respecto de quienes acrediten insuficiencia de re-
cursos para litigar.

ς  Artículo 120

   1. Las actuaciones judiciales serán públicas, con las excep-
ciones que prevean las leyes de procedimiento.

                                                                                                     41
   2. El procedimiento será predominantemente oral, sobre
todo en materia criminal.

   3. Las sentencias serán siempre motivadas y se pronunciarán
en audiencia pública.

ς  Artículo 121

   Los daños causados por error judicial, así como los que sean
consecuencia del funcionamiento anormal de la Administra-
ción de Justicia, darán derecho a una indemnización a cargo
del Estado, conforme a la ley.

ς  Artículo 122

   1. La ley orgánica del poder judicial determinará la constitu-
ción, funcionamiento y gobierno de los Juzgados y Tribunales,
así como el estatuto jurídico de los Jueces y Magistrados de
carrera, que formarán un Cuerpo único, y del personal al ser-
vicio de la Administración de Justicia.

   2. El Consejo General del Poder Judicial es el órgano de go-
bierno del mismo. La ley orgánica establecerá su estatuto y el
régimen de incompatibilidades de sus miembros y sus funcio-
nes, en particular en materia de nombramientos, ascensos,
inspección y régimen disciplinario.

   3. El Consejo General del Poder Judicial estará integrado
por el Presidente del Tribunal Supremo, que lo presidirá, y por
veinte miembros nombrados por el Rey por un período de cin-
co años. De éstos, doce entre Jueces y Magistrados de todas
las categorías judiciales, en los términos que establezca la ley
orgánica; cuatro a propuesta del Congreso de los Diputados, y
cuatro a propuesta del Senado, elegidos en ambos casos por
mayoría de tres quintos de sus miembros, entre abogados y
otros juristas, todos ellos de reconocida competencia y con
más de quince años de ejercicio en su profesión.

ς  Artículo 123

   1. El Tribunal Supremo, con jurisdicción en toda España, es
el órgano jurisdiccional superior en todos los órdenes, salvo lo
dispuesto en materia de garantías constitucionales.

   2. El Presidente del Tribunal Supremo será nombrado por el
Rey, a propuesta del Consejo General del Poder Judicial, en la
forma que determine la ley.

42
ς  Artículo 124

   1. El Ministerio Fiscal, sin perjuicio de las funciones enco-
mendadas a otros órganos, tiene por misión promover la ac-
ción de la justicia en defensa de la legalidad, de los derechos
de los ciudadanos y del interés público tutelado por la ley, de
oficio o a petición de los interesados, así como velar por la
independencia de los Tribunales y procurar ante éstos la satis-
facción del interés social.

   2. El Ministerio Fiscal ejerce sus funciones por medio de ór-
ganos propios conforme a los principios de unidad de actua-
ción y dependencia jerárquica y con sujeción, en todo caso, a
los de legalidad e imparcialidad.

   3. La ley regulará el estatuto orgánico del Ministerio Fiscal.
   4. El Fiscal General del Estado será nombrado por el Rey, a
propuesta del Gobierno, oído el Consejo General del Poder
Judicial.

ς  Artículo 125

   Los ciudadanos podrán ejercer la acción popular y participar
en la Administración de Justicia mediante la institución del
Jurado, en la forma y con respecto a aquellos procesos pena-
les que la ley determine, así como en los Tribunales consuetu-
dinarios y tradicionales.

ς  Artículo 126

   La policía judicial depende de los Jueces, de los Tribunales y
del Ministerio Fiscal en sus funciones de averiguación del de-
lito y descubrimiento y aseguramiento del delincuente, en los
términos que la ley establezca.

ς  Artículo 127

   1. Los Jueces y Magistrados así como los Fiscales, mientras
se hallen en activo, no podrán desempeñar otros cargos públi-
cos, ni pertenecer a partidos políticos o sindicatos. La ley es-
tablecerá el sistema y modalidades de asociación profesional
de los Jueces, Magistrados y Fiscales.

   2. La ley establecerá el régimen de incompatibilidades de los
miembros del poder judicial, que deberá asegurar la total inde-
pendencia de los mismos.

                                                                                                     43
                                   TÍTULO VII
                           Economía y Hacienda

ς  Artículo 128

   1. Toda la riqueza del país en sus distintas formas y sea cual
fuere su titularidad está subordinada al interés general.

   2. Se reconoce la iniciativa pública en la actividad económi-
ca. Mediante ley se podrá reservar al sector público recursos o
servicios esenciales, especialmente en caso de monopolio y
asimismo acordar la intervención de empresas cuando así lo
exigiere el interés general.

ς  Artículo 129

   1. La ley establecerá las formas de participación de los inte-
resados en la Seguridad Social y en la actividad de los organis-
mos públicos cuya función afecte directamente a la calidad de
la vida o al bienestar general.

   2. Los poderes públicos promoverán eficazmente las diver-
sas formas de participación en la empresa y fomentarán, me-
diante una legislación adecuada, las sociedades cooperativas.
También establecerán los medios que faciliten el acceso de los
trabajadores a la propiedad de los medios de producción.

ς  Artículo 130

   1. Los poderes públicos atenderán a la modernización y de-
sarrollo de todos los sectores económicos y, en particular, de
la agricultura, de la ganadería, de la pesca y de la artesanía, a
fin de equiparar el nivel de vida de todos los españoles.

   2. Con el mismo fin, se dispensará un tratamiento especial a
las zonas de montaña.

ς  Artículo 131

   1. El Estado, mediante ley, podrá planificar la actividad econó-
mica general para atender a las necesidades colectivas, equilibrar
y armonizar el desarrollo regional y sectorial y estimular el creci-
miento de la renta y de la riqueza y su más justa distribución.

   2. El Gobierno elaborará los proyectos de planificación, de
acuerdo con las previsiones que le sean suministradas por las
Comunidades Autónomas y el asesoramiento y colaboración
de los sindicatos y otras organizaciones profesionales, empre-

44
sariales y económicas. A tal fin se constituirá un Consejo, cuya
composición y funciones se desarrollarán por ley.

ς  Artículo 132

   1. La ley regulará el régimen jurídico de los bienes de domi-
nio público y de los comunales, inspirándose en los principios
de inalienabilidad, imprescriptibilidad e inembargabilidad, así
como su desafectación.

   2. Son bienes de dominio público estatal los que determine
la ley y, en todo caso, la zona marítimo-terrestre, las playas, el
mar territorial y los recursos naturales de la zona económica y
la plataforma continental.

   3. Por ley se regularán el Patrimonio del Estado y el Patrimo-
nio Nacional, su administración, defensa y conservación.

ς  Artículo 133

   1. La potestad originaria para establecer los tributos corres-
ponde exclusivamente al Estado, mediante ley.

   2. Las Comunidades Autónomas y las Corporaciones locales
podrán establecer y exigir tributos, de acuerdo con la Consti-
tución y las leyes.

   3. Todo beneficio fiscal que afecte a los tributos del Estado
deberá establecerse en virtud de ley.

   4. Las administraciones públicas sólo podrán contraer obli-
gaciones financieras y realizar gastos de acuerdo con las leyes.

ς  Artículo 134

   1. Corresponde al Gobierno la elaboración de los Presu-
puestos Generales del Estado y a las Cortes Generales, su exa-
men, enmienda y aprobación.

   2. Los Presupuestos Generales del Estado tendrán carácter
anual, incluirán la totalidad de los gastos e ingresos del sector
público estatal y en ellos se consignará el importe de los be-
neficios fiscales que afecten a los tributos del Estado.

   3. El Gobierno deberá presentar ante el Congreso de los Di-
putados los Presupuestos Generales del Estado al menos tres
meses antes de la expiración de los del año anterior.

   4. Si la Ley de Presupuestos no se aprobara antes del primer
día del ejercicio económico correspondiente, se considerarán
automáticamente prorrogados los Presupuestos del ejercicio
anterior hasta la aprobación de los nuevos.

                                                                                                     45
   5. Aprobados los Presupuestos Generales del Estado, el Go-
bierno podrá presentar proyectos de ley que impliquen au-
mento del gasto público o disminución de los ingresos corres-
pondientes al mismo ejercicio presupuestario.

   6. Toda proposición o enmienda que suponga aumento de
los créditos o disminución de los ingresos presupuestarios re-
querirá la conformidad del Gobierno para su tramitación.

   7. La Ley de Presupuestos no puede crear tributos. Podrá
modificarlos cuando una ley tributaria sustantiva así lo prevea.

ς  Artículo 135

   1. Todas las Administraciones Públicas adecuarán sus actua-
ciones al principio de estabilidad presupuestaria.

   2. El Estado y las Comunidades Autónomas no podrán incu-
rrir en un déficit estructural que supere los márgenes estable-
cidos, en su caso, por la Unión Europea para sus Estados
Miembros.

   Una ley orgánica fijará el déficit estructural máximo permiti-
do al Estado y a las Comunidades Autónomas, en relación con
su producto interior bruto. Las Entidades Locales deberán pre-
sentar equilibrio presupuestario.

   3. El Estado y las Comunidades Autónomas habrán de estar
autorizados por ley para emitir deuda pública o contraer cré-
dito.

   Los créditos para satisfacer los intereses y el capital de la
deuda pública de las Administraciones se entenderán siempre
incluidos en el estado de gastos de sus presupuestos y su pago
gozará de prioridad absoluta. Estos créditos no podrán ser ob-
jeto de enmienda o modificación, mientras se ajusten a las
condiciones de la ley de emisión.

   El volumen de deuda pública del conjunto de las Adminis-
traciones Públicas en relación con el producto interior bruto
del Estado no podrá superar el valor de referencia establecido
en el Tratado de Funcionamiento de la Unión Europea.

   4. Los límites de déficit estructural y de volumen de deuda
pública sólo podrán superarse en caso de catástrofes natura-
les, recesión económica o situaciones de emergencia extraor-
dinaria que escapen al control del Estado y perjudiquen consi-
derablemente la situación financiera o la sostenibilidad
económica o social del Estado, apreciadas por la mayoría ab-
soluta de los miembros del Congreso de los Diputados.

46
   5. Una ley orgánica desarrollará los principios a que se refie-
re este artículo, así como la participación, en los procedimien-
tos respectivos, de los órganos de coordinación institucional
entre las Administraciones Públicas en materia de política fiscal
y financiera. En todo caso, regulará:

     a)	La distribución de los límites de déficit y de deuda entre
         las distintas Administraciones Públicas, los supuestos
         excepcionales de superación de los mismos y la forma
         y plazo de corrección de las desviaciones que sobre
         uno y otro pudieran producirse.

     b)	L a metodología y el procedimiento para el cálculo del
         déficit estructural.

     c)	L a responsabilidad de cada Administración Pública en
         caso de incumplimiento de los objetivos de estabilidad
         presupuestaria.

   6. Las Comunidades Autónomas, de acuerdo con sus res-
pectivos Estatutos y dentro de los límites a que se refiere este
artículo, adoptarán las disposiciones que procedan para la
aplicación efectiva del principio de estabilidad en sus normas
y decisiones presupuestarias.

ς  Artículo 136

   1. El Tribunal de Cuentas es el supremo órgano fiscalizador
de las cuentas y de la gestión económica de Estado, así como
del sector público.

   Dependerá directamente de las Cortes Generales y ejercerá
sus funciones por delegación de ellas en el examen y compro-
bación de la Cuenta General del Estado.

   2. Las cuentas del Estado y del sector público estatal se ren-
dirán al Tribunal de Cuentas y serán censuradas por éste.

   El Tribunal de Cuentas, sin perjuicio de su propia jurisdic-
ción, remitirá a las Cortes Generales un informe anual en el
que, cuando proceda, comunicará las infracciones o respon-
sabilidades en que, a su juicio, se hubiere incurrido.

   3. Los miembros del Tribunal de Cuentas gozarán de la mis-
ma independencia e inamovilidad y estarán sometidos a las
mismas incompatibilidades que los Jueces.

   4. Una ley orgánica regulará la composición, organización y
funciones del Tribunal de Cuentas.

                                                                                                     47
                                  TÍTULO VIII
              De la Organización Territorial del Estado

                            CAPÍTULO PRIMERO
                            Principios generales

ς  Artículo 137
   El Estado se organiza territorialmente en municipios, en pro-

vincias y en las Comunidades Autónomas que se constituyan.
Todas estas entidades gozan de autonomía para la gestión de
sus respectivos intereses.

ς  Artículo 138
   1. El Estado garantiza la realización efectiva del principio de

solidaridad consagrado en el artículo 2 de la Constitución,
velando por el establecimiento de un equilibrio económico,
adecuado y justo entre las diversas partes del territorio espa-
ñol, y atendiendo en particular a las circunstancias del hecho
insular.

   2. Las diferencias entre los Estatutos de las distintas Comu-
nidades Autónomas no podrán implicar, en ningún caso, privi-
legios económicos o sociales.

ς  Artículo 139
   1. Todos los españoles tienen los mismos derechos y obliga-

ciones en cualquier parte del territorio del Estado.
   2. Ninguna autoridad podrá adoptar medidas que directa o

indirectamente obstaculicen la libertad de circulación y esta-
blecimiento de las personas y la libre circulación de bienes en
todo el territorio español.

                           CAPÍTULO SEGUNDO
                       De la Administración Local

ς  Artículo 140
   La Constitución garantiza la autonomía de los municipios.

Estos gozarán de personalidad jurídica plena. Su gobierno y
administración corresponde a sus respectivos Ayuntamientos,

48
integrados por los Alcaldes y los Concejales. Los Concejales
serán elegidos por los vecinos del municipio mediante sufragio
universal, igual, libre, directo y secreto, en la forma establecida
por la ley. Los Alcaldes serán elegidos por los Concejales o por
los vecinos. La ley regulará las condiciones en las que proceda
el régimen del concejo abierto.

ς  Artículo 141

   1. La provincia es una entidad local con personalidad jurídica
propia, determinada por la agrupación de municipios y división
territorial para el cumplimiento de las actividades del Estado.
Cualquier alteración de los límites provinciales habrá de ser
aprobada por las Cortes Generales mediante ley orgánica.

   2. El gobierno y la administración autónoma de las provin-
cias estarán encomendados a Diputaciones u otras Corpora-
ciones de carácter representativo.

   3. Se podrán crear agrupaciones de municipios diferentes de
la provincia.

   4. En los archipiélagos, las islas tendrán además su adminis-
tración propia en forma de Cabildos o Consejos.

ς  Artículo 142

   Las Haciendas locales deberán disponer de los medios sufi-
cientes para el desempeño de las funciones que la ley atribuye
a las Corporaciones respectivas y se nutrirán fundamental-
mente de tributos propios y de participación en los del Estado
y de las Comunidades Autónomas.

                            CAPÍTULO TERCERO
                   De las Comunidades Autónomas

ς  Artículo 143

   1. En el ejercicio del derecho a la autonomía reconocido en
el artículo 2 de la Constitución, las provincias limítrofes con
características históricas, culturales y económicas comunes,
los territorios insulares y las provincias con entidad regional
histórica podrán acceder a su autogobierno y constituirse en
Comunidades Autónomas con arreglo a lo previsto en este
Título y en los respectivos Estatutos.

                                                                                                     49
   2. La iniciativa del proceso autonómico corresponde a todas
las Diputaciones interesadas o al órgano interinsular correspon-
diente y a las dos terceras partes de los municipios cuya pobla-
ción represente, al menos, la mayoría del censo electoral de
cada provincia o isla. Estos requisitos deberán ser cumplidos en
el plazo de seis meses desde el primer acuerdo adoptado al
respecto por alguna de las Corporaciones locales interesadas.

   3. La iniciativa, en caso de no prosperar, solamente podrá
reiterarse pasados cinco años.

ς  Artículo 144

   Las Cortes Generales, mediante ley orgánica, podrán, por
motivos de interés nacional:

   a) Autorizar la constitución de una comunidad autónoma
      cuando su ámbito territorial no supere el de una provincia
      y no reúna las condiciones del apartado 1 del artículo 143.

   b) Autorizar o acordar, en su caso, un Estatuto de autonomía
      para territorios que no estén integrados en la organiza-
      ción provincial.

   c) Sustituir la iniciativa de las Corporaciones locales a que se
      refiere el apartado 2 del artículo 143.

ς  Artículo 145

   1. En ningún caso se admitirá la federación de Comunidades
Autónomas.

   2. Los Estatutos podrán prever los supuestos, requisitos y
términos en que las Comunidades Autónomas podrán celebrar
convenios entre sí para la gestión y prestación de servicios
propios de las mismas, así como el carácter y efectos de la
correspondiente comunicación a las Cortes Generales. En los
demás supuestos, los acuerdos de cooperación entre las Co-
munidades Autónomas necesitarán la autorización de las Cor-
tes Generales.

ς  Artículo 146

   El proyecto de Estatuto será elaborado por una asamblea
compuesta por los miembros de la Diputación u órgano inter­
insular de las provincias afectadas y por los Diputados y Sena-
dores elegidos en ellas y será elevado a las Cortes Generales
para su tramitación como ley.

50
ς  Artículo 147

   1. Dentro de los términos de la presente Constitución, los
Estatutos serán la norma institucional básica de cada Comuni-
dad Autónoma y el Estado los reconocerá y amparará como
parte integrante de su ordenamiento jurídico.

   2. Los Estatutos de autonomía deberán contener:

     a)	La denominación de la Comunidad que mejor corres-
         ponda a su identidad histórica.

     b)	L a delimitación de su territorio.
     c)	La denominación, organización y sede de las institucio-

         nes autónomas propias.
     d)	L as competencias asumidas dentro del marco estable-

         cido en la Constitución y las bases para el traspaso de
         los servicios correspondientes a las mismas.

   3. La reforma de los Estatutos se ajustará al procedimiento
establecido en los mismos y requerirá, en todo caso, la apro-
bación por las Cortes Generales, mediante ley orgánica.

ς  Artículo 148

   1. Las Comunidades Autónomas podrán asumir competen-
cias en las siguientes materias:

   1.ª Organización de sus instituciones de autogobierno.
   2.ª Las alteraciones de los términos municipales compren-
didos en su territorio y, en general, las funciones que corres-
pondan a la Administración del Estado sobre las Corporaciones
locales y cuya transferencia autorice la legislación sobre Régi-
men Local.
   3.ª Ordenación del territorio, urbanismo y vivienda.
   4.ª Las obras públicas de interés de la Comunidad Autóno-
ma en su propio territorio.
   5.ª Los ferrocarriles y carreteras cuyo itinerario se desarrolle
íntegramente en el territorio de la Comunidad Autónoma y, en
los mismos términos, el transporte desarrollado por estos me-
dios o por cable.
   6.ª Los puertos de refugio, los puertos y aeropuertos depor-
tivos y, en general, los que no desarrollen actividades comer-
ciales.
   7.ª La agricultura y ganadería, de acuerdo con la ordenación
general de la economía.

                                                                                                     51
   8.ª Los montes y aprovechamientos forestales.
   9.ª La gestión en materia de protección del medio ambiente.
   10.ª Los proyectos, construcción y explotación de los apro-
vechamientos hidráulicos, canales y regadíos de interés de la
Comunidad Autónoma; las aguas minerales y termales.
   11.ª La pesca en aguas interiores, el marisqueo y la acuicul-
tura, la caza y la pesca fluvial.
   12.ª Ferias interiores.
   13.ª El fomento del desarrollo económico de la Comunidad
Autónoma dentro de los objetivos marcados por la política
económica nacional.
   14.ª La artesanía.
   15.ª Museos, bibliotecas y conservatorios de música de inte-
rés para la Comunidad Autónoma.
   16.ª Patrimonio monumental de interés de la Comunidad
Autónoma.
   17.ª El fomento de la cultura, de la investigación y, en su
caso, de la enseñanza de la lengua de la Comunidad Autóno-
ma.
   18.ª Promoción y ordenación del turismo en su ámbito te-
rritorial.
   19.ª Promoción del deporte y de la adecuada utilización del
ocio.
   20.ª Asistencia social.
   21.ª Sanidad e higiene.
   22.ª La vigilancia y protección de sus edificios e instalacio-
nes. La coordinación y demás facultades en relación con las
policías locales en los términos que establezca una ley orgáni-
ca.

   2. Transcurridos cinco años, y mediante la reforma de sus
Estatutos, las Comunidades Autónomas podrán ampliar suce-
sivamente sus competencias dentro del marco establecido en
el artículo 149.

ς  Artículo 149

   1. El Estado tiene competencia exclusiva sobre las siguientes
materias:

   1.ª La regulación de las condiciones básicas que garanticen
la igualdad de todos los españoles en el ejercicio de los dere-
chos y en el cumplimiento de los deberes constitucionales.

52
   2.ª Nacionalidad, inmigración, emigración, extranjería y de-
recho de asilo.

   3.ª Relaciones internacionales.
   4.ª Defensa y Fuerzas Armadas.
   5.ª Administración de Justicia.
   6.ª Legislación mercantil, penal y penitenciaria; legislación
procesal, sin perjuicio de las necesarias especialidades que en
este orden se deriven de las particularidades del derecho sus-
tantivo de las Comunidades Autónomas.
   7.ª Legislación laboral; sin perjuicio de su ejecución por los
órganos de las Comunidades Autónomas.
   8.ª Legislación civil, sin perjuicio de la conservación, modi-
ficación y desarrollo por las Comunidades Autónomas de los
derechos civiles, forales o especiales, allí donde existan. En
todo caso, las reglas relativas a la aplicación y eficacia de las
normas jurídicas, relaciones jurídico-civiles relativas a las for-
mas de matrimonio, ordenación de los registros e instrumen-
tos públicos, bases de las obligaciones contractuales, normas
para resolver los conflictos de leyes y determinación de las
fuentes del Derecho, con respeto, en este último caso, a las
normas de derecho foral o especial.
   9.ª Legislación sobre propiedad intelectual e industrial.
   10.ª Régimen aduanero y arancelario; comercio exterior.
   11.ª Sistema monetario: divisas, cambio y convertibilidad;
bases de la ordenación de crédito, banca y seguros.
   12.ª Legislación sobre pesas y medidas, determinación de la
hora oficial.
   13.ª Bases y coordinación de la planificación general de la
actividad económica.
   14.ª Hacienda general y Deuda del Estado.
   15.ª Fomento y coordinación general de la investigación
científica y técnica.
   16.ª Sanidad exterior. Bases y coordinación general de la
sanidad. Legislación sobre productos farmacéuticos.
   17.ª Legislación básica y régimen económico de la Seguridad
Social, sin perjuicio de la ejecución de sus servicios por las
Comunidades Autónomas.
   18.ª Las bases del régimen jurídico de las Administraciones
públicas y del régimen estatutario de sus funcionarios que, en
todo caso, garantizarán a los administrados un tratamiento
común ante ellas; el procedimiento administrativo común, sin

                                                                                                     53
perjuicio de las especialidades derivadas de la organización
propia de las Comunidades Autónomas; legislación sobre ex-
propiación forzosa; legislación básica sobre contratos y con-
cesiones administrativas y el sistema de responsabilidad de
todas las Administraciones públicas.

   19.ª Pesca marítima, sin perjuicio de las competencias que
en la ordenación del sector se atribuyan a las Comunidades
Autónomas.

   20.ª Marina mercante y abanderamiento de buques; ilumi-
nación de costas y señales marítimas; puertos de interés gene-
ral; aeropuertos de interés general; control del espacio aéreo,
tránsito y transporte aéreo, servicio meteorológico y matricu-
lación de aeronaves.

   21.ª Ferrocarriles y transportes terrestres que transcurran por
el territorio de más de una Comunidad Autónoma; régimen
general de comunicaciones; tráfico y circulación de vehículos
a motor; correos y telecomunicaciones; cables aéreos, sub-
marinos y radiocomunicación.

   22.ª La legislación, ordenación y concesión de recursos y apro-
vechamientos hidráulicos cuando las aguas discurran por más de
una Comunidad Autónoma, y la autorización de las instalaciones
eléctricas cuando su aprovechamiento afecte a otra Comunidad
o el transporte de energía salga de su ámbito territorial.

   23.ª Legislación básica sobre protección del medio ambien-
te, sin perjuicio de las facultades de las Comunidades Autóno-
mas de establecer normas adicionales de protección. La legis-
lación básica sobre montes, aprovechamientos forestales y
vías pecuarias.

   24.ª Obras públicas de interés general o cuya realización
afecte a más de una Comunidad Autónoma.

   25.ª Bases de régimen minero y energético.
   26.ª Régimen de producción, comercio, tenencia y uso de
armas y explosivos.
   27.ª Normas básicas del régimen de prensa, radio y televi-
sión y, en general, de todos los medios de comunicación so-
cial, sin perjuicio de las facultades que en su desarrollo y eje-
cución correspondan a las Comunidades Autónomas.
   28.ª Defensa del patrimonio cultural, artístico y monumental
español contra la exportación y la expoliación; museos, biblio-
tecas y archivos de titularidad estatal, sin perjuicio de su ges-
tión por parte de las Comunidades Autónomas.

54
   29.ª Seguridad pública, sin perjuicio de la posibilidad de
creación de policías por las Comunidades Autónomas en la
forma que se establezca en los respectivos Estatutos en el
marco de lo que disponga una ley orgánica.

   30.ª Regulación de las condiciones de obtención, expedi-
ción y homologación de títulos académicos y profesionales y
normas básicas para el desarrollo del artículo 27 de la Consti-
tución, a fin de garantizar el cumplimiento de las obligaciones
de los poderes públicos en esta materia.

   31.ª Estadística para fines estatales.
   32.ª Autorización para la convocatoria de consultas popula-
res por vía de referéndum.

   2. Sin perjuicio de las competencias que podrán asumir las
Comunidades Autónomas, el Estado considerará el servicio de
la cultura como deber y atribución esencial y facilitará la co-
municación cultural entre las Comunidades Autónomas, de
acuerdo con ellas.

   3. Las materias no atribuidas expresamente al Estado por
esta Constitución podrán corresponder a las Comunidades
Autónomas, en virtud de sus respectivos Estatutos. La compe-
tencia sobre las materias que no se hayan asumido por los
Estatutos de Autonomía corresponderá al Estado, cuyas nor-
mas prevalecerán, en caso de conflicto, sobre las de las Co-
munidades Autónomas en todo lo que no esté atribuido a la
exclusiva competencia de éstas. El derecho estatal será, en
todo caso, supletorio del derecho de las Comunidades Autó-
nomas.

ς  Artículo 150

   1. Las Cortes Generales, en materias de competencia estatal,
podrán atribuir a todas o a alguna de las Comunidades Autó-
nomas la facultad de dictar, para sí mismas, normas legislativas
en el marco de los principios, bases y directrices fijados por
una ley estatal. Sin perjuicio de la competencia de los Tribuna-
les, en cada ley marco se establecerá la modalidad del control
de las Cortes Generales sobre estas normas legislativas de las
Comunidades Autónomas.

   2. El Estado podrá transferir o delegar en las Comunidades
Autónomas, mediante ley orgánica, facultades correspondien-
tes a materia de titularidad estatal que por su propia naturaleza

                                                                                                     55
sean susceptibles de transferencia o delegación. La ley preve-
rá en cada caso la correspondiente transferencia de medios
financieros, así como las formas de control que se reserve el
Estado.

   3. El Estado podrá dictar leyes que establezcan los principios
necesarios para armonizar las disposiciones normativas de las
Comunidades Autónomas, aun en el caso de materias atribui-
das a la competencia de éstas, cuando así lo exija el interés
general. Corresponde a las Cortes Generales, por mayoría ab-
soluta de cada Cámara, la apreciación de esta necesidad.

ς  Artículo 151

   1. No será preciso dejar transcurrir el plazo de cinco años, a
que se refiere el apartado 2 del artículo 148, cuando la inicia-
tiva del proceso autonómico sea acordada dentro del plazo
del artículo 143.2, además de por las Diputaciones o los órga-
nos interinsulares correspondientes, por las tres cuartas partes
de los municipios de cada una de las provincias afectadas que
representen, al menos, la mayoría del censo electoral de cada
una de ellas y dicha iniciativa sea ratificada mediante referén-
dum por el voto afirmativo de la mayoría absoluta de los elec-
tores de cada provincia en los términos que establezca una ley
orgánica.

   2. En el supuesto previsto en el apartado anterior, el proce-
dimiento para la elaboración del Estatuto será el siguiente:

   1.º El Gobierno convocará a todos los Diputados y Senado-
res elegidos en las circunscripciones comprendidas en el ám-
bito territorial que pretenda acceder al autogobierno, para que
se constituyan en Asamblea, a los solos efectos de elaborar el
correspondiente proyecto de Estatuto de autonomía, median-
te el acuerdo de la mayoría absoluta de sus miembros.

   2.º Aprobado el proyecto de Estatuto por la Asamblea de
Parlamentarios, se remitirá a la Comisión Constitucional del
Congreso, la cual, dentro del plazo de dos meses, lo examina-
rá con el concurso y asistencia de una delegación de la Asam-
blea proponente para determinar de común acuerdo su for-
mulación definitiva.

   3.º Si se alcanzare dicho acuerdo, el texto resultante será
sometido a referéndum del cuerpo electoral de las provincias
comprendidas en el ámbito territorial del proyectado Estatuto.

56
   4.º Si el proyecto de Estatuto es aprobado en cada provincia
por la mayoría de los votos válidamente emitidos, será elevado
a las Cortes Generales. Los plenos de ambas Cámaras decidi-
rán sobre el texto mediante un voto de ratificación. Aprobado
el Estatuto, el Rey lo sancionará y lo promulgará como ley.

   5.º De no alcanzarse el acuerdo a que se refiere el apartado
2 de este número, el proyecto de Estatuto será tramitado
como proyecto de ley ante las Cortes Generales. El texto apro-
bado por éstas será sometido a referéndum del cuerpo elec-
toral de las provincias comprendidas en el ámbito territorial del
proyectado Estatuto. En caso de ser aprobado por la mayoría
de los votos válidamente emitidos en cada provincia, procede-
rá su promulgación en los términos del párrafo anterior.

   3. En los casos de los párrafos 4.º y 5.º del apartado anterior,
la no aprobación del proyecto de Estatuto por una o varias
provincias no impedirá la constitución entre las restantes de la
Comunidad Autónoma proyectada, en la forma que establezca
la ley orgánica prevista en el apartado 1 de este artículo.

ς  Artículo 152

   1. En los Estatutos aprobados por el procedimiento a que se
refiere el artículo anterior, la organización institucional auto-
nómica se basará en una Asamblea Legislativa, elegida por
sufragio universal, con arreglo a un sistema de representación
proporcional que asegure, además, la representación de las
diversas zonas del territorio; un Consejo de Gobierno con fun-
ciones ejecutivas y administrativas y un Presidente, elegido por
la Asamblea, de entre sus miembros, y nombrado por el Rey, al
que corresponde la dirección del Consejo de Gobierno, la su-
prema representación de la respectiva Comunidad y la ordina-
ria del Estado en aquélla. El Presidente y los miembros del
Consejo de Gobierno serán políticamente responsables ante la
Asamblea.

   Un Tribunal Superior de Justicia, sin perjuicio de la jurisdic-
ción que corresponde al Tribunal Supremo, culminará la orga-
nización judicial en el ámbito territorial de la Comunidad Au-
tónoma. En los Estatutos de las Comunidades Autónomas
podrán establecerse los supuestos y las formas de participa-
ción de aquéllas en la organización de las demarcaciones ju-
diciales del territorio. Todo ello de conformidad con lo previs-

                                                                                                     57
to en la ley orgánica del poder judicial y dentro de la unidad e
independencia de éste.

   Sin perjuicio de lo dispuesto en el artículo 123, las sucesivas
instancias procesales, en su caso, se agotarán ante órganos
judiciales radicados en el mismo territorio de la Comunidad
Autónoma en que esté el órgano competente en primera ins-
tancia.

   2. Una vez sancionados y promulgados los respectivos Esta-
tutos, solamente podrán ser modificados mediante los proce-
dimientos en ellos establecidos y con referéndum entre los
electores inscritos en los censos correspondientes.

   3. Mediante la agrupación de municipios limítrofes, los Esta-
tutos podrán establecer circunscripciones territoriales propias,
que gozarán de plena personalidad jurídica.

ς  Artículo 153

   El control de la actividad de los órganos de las Comunidades
Autónomas se ejercerá:

   a) Por el Tribunal Constitucional, el relativo a la constitucio-
      nalidad de sus disposiciones normativas con fuerza de ley.

   b) Por el Gobierno, previo dictamen del Consejo de Estado,
      el del ejercicio de funciones delegadas a que se refiere el
      apartado 2 del artículo 150.

   c) Por la jurisdicción contencioso-administrativa, el de la
      administración autónoma y sus normas reglamentarias.

   d) Por el Tribunal de Cuentas, el económico y presupuestario.

ς  Artículo 154

   Un Delegado nombrado por el Gobierno dirigirá la Adminis-
tración del Estado en el territorio de la Comunidad Autónoma
y la coordinará, cuando proceda, con la administración propia
de la Comunidad.

ς  Artículo 155

   1. Si una Comunidad Autónoma no cumpliere las obligacio-
nes que la Constitución u otras leyes le impongan, o actuare
de forma que atente gravemente al interés general de España,
el Gobierno, previo requerimiento al Presidente de la Comuni-
dad Autónoma y, en el caso de no ser atendido, con la apro-
bación por mayoría absoluta del Senado, podrá adoptar las

58
medidas necesarias para obligar a aquélla al cumplimiento
forzoso de dichas obligaciones o para la protección del men-
cionado interés general.

   2. Para la ejecución de las medidas previstas en el apartado
anterior, el Gobierno podrá dar instrucciones a todas las auto-
ridades de las Comunidades Autónomas.

ς  Artículo 156

   1. Las Comunidades Autónomas gozarán de autonomía fi-
nanciera para el desarrollo y ejecución de sus competencias
con arreglo a los principios de coordinación con la Hacienda
estatal y de solidaridad entre todos los españoles.

   2. Las Comunidades Autónomas podrán actuar como dele-
gados o colaboradores del Estado para la recaudación, la ges-
tión y la liquidación de los recursos tributarios de aquél, de
acuerdo con las leyes y los Estatutos.

ς  Artículo 157

   1. Los recursos de las Comunidades Autónomas estarán
constituidos por:

     a)	Impuestos cedidos total o parcialmente por el Estado;
         recargos sobre impuestos estatales y otras participacio-
         nes en los ingresos del Estado.

     b)	S us propios impuestos, tasas y contribuciones especia-
         les.

     c)	T ransferencias de un Fondo de Compensación interte-
         rritorial y otras asignaciones con cargo a los Presupues-
         tos Generales del Estado.

     d)	Rendimientos procedentes de su patrimonio e ingresos
         de derecho privado.

     e)	El producto de las operaciones de crédito.

   2. Las Comunidades Autónomas no podrán en ningún caso
adoptar medidas tributarias sobre bienes situados fuera de su
territorio o que supongan obstáculo para la libre circulación de
mercancías o servicios.

   3. Mediante ley orgánica podrá regularse el ejercicio de las
competencias financieras enumeradas en el precedente apar-
tado 1, las normas para resolver los conflictos que pudieran
surgir y las posibles formas de colaboración financiera entre
las Comunidades Autónomas y el Estado.

                                                                                                     59
ς  Artículo 158

   1. En los Presupuestos Generales del Estado podrá estable-
cerse una asignación a las Comunidades Autónomas en fun-
ción del volumen de los servicios y actividades estatales que
hayan asumido y de la garantía de un nivel mínimo en la pres-
tación de los servicios públicos fundamentales en todo el te-
rritorio español.

   2. Con el fin de corregir desequilibrios económicos interterri-
toriales y hacer efectivo el principio de solidaridad, se constitui-
rá un Fondo de Compensación con destino a gastos de inver-
sión, cuyos recursos serán distribuidos por las Cortes Generales
entre las Comunidades Autónomas y provincias, en su caso.

                                   TÍTULO IX

                       Del Tribunal Constitucional

ς  Artículo 159

   1. El Tribunal Constitucional se compone de 12 miembros
nombrados por el Rey; de ellos, cuatro a propuesta del Con-
greso por mayoría de tres quintos de sus miembros; cuatro a
propuesta del Senado, con idéntica mayoría; dos a propuesta
del Gobierno, y dos a propuesta del Consejo General del Poder
Judicial.

   2. Los miembros del Tribunal Constitucional deberán ser
nombrados entre Magistrados y Fiscales, Profesores de Univer-
sidad, funcionarios públicos y Abogados, todos ellos juristas de
reconocida competencia con más de quince años de ejercicio
profesional.

   3. Los miembros del Tribunal Constitucional serán designa-
dos por un período de nueve años y se renovarán por terceras
partes cada tres.

   4. La condición de miembro del Tribunal Constitucional es
incompatible: con todo mandato representativo; con los cargos
políticos o administrativos; con el desempeño de funciones di-
rectivas en un partido político o en un sindicato y con el empleo
al servicio de los mismos; con el ejercicio de las carreras judicial
y fiscal, y con cualquier actividad profesional o mercantil.

   En lo demás los miembros del Tribunal Constitucional ten-
drán las incompatibilidades propias de los miembros del poder
judicial.

60
   5. Los miembros del Tribunal Constitucional serán indepen-
dientes e inamovibles en el ejercicio de su mandato.

ς  Artículo 160

   El Presidente del Tribunal Constitucional será nombrado en-
tre sus miembros por el Rey, a propuesta del mismo Tribunal
en pleno y por un período de tres años.

ς  Artículo 161

   1. El Tribunal Constitucional tiene jurisdicción en todo el te-
rritorio español y es competente para conocer:

     a)	Del recurso de inconstitucionalidad contra leyes y dis-
         posiciones normativas con fuerza de ley. La declaración
         de inconstitucionalidad de una norma jurídica con ran-
         go de ley, interpretada por la jurisprudencia, afectará a
         ésta, si bien la sentencia o sentencias recaídas no per-
         derán el valor de cosa juzgada.

     b)	D el recurso de amparo por violación de los derechos y
         libertades referidos en el artículo 53, 2, de esta Consti-
         tución, en los casos y formas que la ley establezca.

     c)	D e los conflictos de competencia entre el Estado y las
         Comunidades Autónomas o de los de éstas entre sí.

     d)	D e las demás materias que le atribuyan la Constitución
         o las leyes orgánicas.

   2. El Gobierno podrá impugnar ante el Tribunal Constitucio-
nal las disposiciones y resoluciones adoptadas por los órganos
de las Comunidades Autónomas. La impugnación producirá la
suspensión de la disposición o resolución recurrida, pero el
Tribunal, en su caso, deberá ratificarla o levantarla en un plazo
no superior a cinco meses.

ς  Artículo 162

   1. Están legitimados:

      a)	Para interponer el recurso de inconstitucionalidad, el
          Presidente del Gobierno, el Defensor del Pueblo, 50
          Diputados, 50 Senadores, los órganos colegiados eje-
          cutivos de las Comunidades Autónomas y, en su caso,
          las Asambleas de las mismas.

                                                                                                     61
      b)	Para interponer el recurso de amparo, toda persona
          natural o jurídica que invoque un interés legítimo, así
          como el Defensor del Pueblo y el Ministerio Fiscal.

   2. En los demás casos, la ley orgánica determinará las per-
sonas y órganos legitimados.

ς  Artículo 163
   Cuando un órgano judicial considere, en algún proceso, que

una norma con rango de ley, aplicable al caso, de cuya validez
dependa el fallo, pueda ser contraria a la Constitución, plan-
teará la cuestión ante el Tribunal Constitucional en los supues-
tos, en la forma y con los efectos que establezca la ley, que en
ningún caso serán suspensivos.

ς  Artículo 164
   1. Las sentencias del Tribunal Constitucional se publicarán

en el boletín oficial del Estado con los votos particulares, si los
hubiere. Tienen el valor de cosa juzgada a partir del día si-
guiente de su publicación y no cabe recurso alguno contra
ellas. Las que declaren la inconstitucionalidad de una ley o de
una norma con fuerza de ley y todas las que no se limiten a la
estimación subjetiva de un derecho, tienen plenos efectos
frente a todos.

   2. Salvo que en el fallo se disponga otra cosa, subsistirá la
vigencia de la ley en la parte no afectada por la inconstitucio-
nalidad.

ς  Artículo 165
   Una ley orgánica regulará el funcionamiento del Tribunal

Constitucional, el estatuto de sus miembros, el procedimiento
ante el mismo y las condiciones para el ejercicio de las accio-
nes.

                                    TÍTULO X
                      De la reforma constitucional

ς  Artículo 166
   La iniciativa de reforma constitucional se ejercerá en los tér-

minos previstos en los apartados 1 y 2 del artículo 87.

62
ς  Artículo 167

   1. Los proyectos de reforma constitucional deberán ser
aprobados por una mayoría de tres quintos de cada una de las
Cámaras. Si no hubiera acuerdo entre ambas, se intentará ob-
tenerlo mediante la creación de una Comisión de composición
paritaria de Diputados y Senadores, que presentará un texto
que será votado por el Congreso y el Senado.

   2. De no lograrse la aprobación mediante el procedimiento
del apartado anterior, y siempre que el texto hubiere obtenido
el voto favorable de la mayoría absoluta del Senado, el Con-
greso, por mayoría de dos tercios, podrá aprobar la reforma.

   3. Aprobada la reforma por las Cortes Generales, será some-
tida a referéndum para su ratificación cuando así lo soliciten,
dentro de los quince días siguientes a su aprobación, una dé-
cima parte de los miembros de cualquiera de las Cámaras.

ς  Artículo 168

   1. Cuando se propusiere la revisión total de la Constitución
o una parcial que afecte al Título preliminar, al Capítulo segun-
do, Sección primera del Título I, o al Título II, se procederá a la
aprobación del principio por mayoría de dos tercios de cada
Cámara, y a la disolución inmediata de las Cortes.

   2. Las Cámaras elegidas deberán ratificar la decisión y pro-
ceder al estudio del nuevo texto constitucional, que deberá ser
aprobado por mayoría de dos tercios de ambas Cámaras.

   3. Aprobada la reforma por las Cortes Generales, será some-
tida a referéndum para su ratificación.

ς  Artículo 169

   No podrá iniciarse la reforma constitucional en tiempo de
guerra o de vigencia de alguno de los estados previstos en el
artículo 116.

ς  Disposición adicional primera

   La Constitución ampara y respeta los derechos históricos de
los territorios forales.

   La actualización general de dicho régimen foral se llevará a
cabo, en su caso, en el marco de la Constitución y de los Es-
tatutos de Autonomía.

                                                                                                     63
ς  Disposición adicional segunda
   La declaración de mayoría de edad contenida en el artículo

12 de esta Constitución no perjudica las situaciones ampara-
das por los derechos forales en el ámbito del Derecho privado.

ς  Disposición adicional tercera
   La modificación del régimen económico y fiscal del archi-

piélago canario requerirá informe previo de la Comunidad
Autónoma o, en su caso, del órgano provisional autonómico.

ς  Disposición adicional cuarta
   En las Comunidades Autónomas donde tengan su sede más

de una Audiencia Territorial, los Estatutos de Autonomía res-
pectivos podrán mantener las existentes, distribuyendo las
competencias entre ellas, siempre de conformidad con lo pre-
visto en la ley orgánica del poder judicial y dentro de la unidad
e independencia de éste.

ς  Disposición transitoria primera

   En los territorios dotados de un régimen provisional de au-
tonomía, sus órganos colegiados superiores, mediante acuer-
do adoptado por la mayoría absoluta de sus miembros, podrán
sustituir la iniciativa que en el apartado 2 del artículo 143 atri-
buye a las Diputaciones Provinciales o a los órganos interinsu-
lares correspondientes.

ς  Disposición transitoria segunda

   Los territorios que en el pasado hubiesen plebiscitado afir-
mativamente proyectos de Estatuto de autonomía y cuenten,
al tiempo de promulgarse esta Constitución, con regímenes
provisionales de autonomía podrán proceder inmediatamente
en la forma que se prevé en el apartado 2 del artículo 148,
cuando así lo acordaren, por mayoría absoluta, sus órganos
preautonómicos colegiados superiores, comunicándolo al
Gobierno. El proyecto de Estatuto será elaborado de acuerdo
con lo establecido en el artículo 151, número 2, a convocatoria
del órgano colegiado preautonómico.

ς  Disposición transitoria tercera

   La iniciativa del proceso autonómico por parte de las Cor-
poraciones locales o de sus miembros, prevista en el apartado

64
2 del artículo 143, se entiende diferida, con todos sus efectos,
hasta la celebración de las primeras elecciones locales una vez
vigente la Constitución.

ς  Disposición transitoria cuarta

   1. En el caso de Navarra, y a efectos de su incorporación al
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
plazo mínimo que establece el artículo 143.

ς  Disposición transitoria quinta

   Las ciudades de Ceuta y Melilla podrán constituirse en Comu-
nidades Autónomas si así lo deciden sus respectivos Ayunta-
mientos, mediante acuerdo adoptado por la mayoría absoluta de
sus miembros y así lo autorizan las Cortes Generales, mediante
una ley orgánica, en los términos previstos en el artículo 144.

ς  Disposición transitoria sexta
   Cuando se remitieran a la Comisión Constitucional del Con-

greso varios proyectos de Estatuto, se dictaminarán por el
orden de entrada en aquélla, y el plazo de dos meses a que se
refiere el artículo 151 empezará a contar desde que la Comi-
sión termine el estudio del proyecto o proyectos de que suce-
sivamente haya conocido.

ς  Disposición transitoria séptima
   Los organismos provisionales autonómicos se considerarán

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
      tres años.

ς  Disposición transitoria octava

   1. Las Cámaras que han aprobado la presente Constitución
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
edad para el voto y lo establecido en el artículo 69,3.

ς  Disposición transitoria novena

   A los tres años de la elección por vez primera de los miem-
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
a lo establecido en el número 3 del artículo 159.

ς  Disposición derogatoria
   1. Queda derogada la Ley 1/1977, de 4 de enero, para la Re-

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
opongan a lo establecido en esta Constitución.

ς  Disposición final
   Esta Constitución entrará en vigor el mismo día de la publi-

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

68
$body$)
    returning id into v_doc_id;
    raise notice '[0089] document creado: %', v_doc_id;
  end if;

  -- 3) Limpiar index_nodes existentes (cascade borra node_content).
  delete from public.index_nodes where subject_id = v_subject_id;

  -- 4) Crear nodo raiz.
  insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
  values (
    v_subject_id, v_user_id, null,
    'Constitución Española',
    0, 0,
    md5('Constitución Española')
  )
  returning id into v_root_id;

  raise notice '[0089] root=%', v_root_id;

  -- 5) Insertar jerarquia completa via CTEs encadenadas.
  -- Para preservar relaciones padre-hijo, generamos un uuid por nodo y
  -- referenciamos por indice. Hacemos un INSERT por NIVEL (depth 1 -> 2 -> 3 -> 4)
  -- para no tener problemas de orden de FK.

  declare
    v_node_ids uuid[] := array_fill(null::uuid, ARRAY[204]);
  begin
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'Preámbulo', 0, 1, md5('Preámbulo'))
    returning id into v_node_ids[1];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[1], v_user_id, 'original', $c1$La Nación española, deseando establecer la justicia, la liber-
tad y la seguridad y promover el bien de cuantos la integran,
en uso de su soberanía, proclama su voluntad de:

   Garantizar la convivencia democrática dentro de la Consti-
tución y de las leyes conforme a un orden económico y social
justo.

   Consolidar un Estado de Derecho que asegure el imperio de
la ley como expresión de la voluntad popular.

   Proteger a todos los españoles y pueblos de España en el
ejercicio de los derechos humanos, sus culturas y tradiciones,
lenguas e instituciones.

   Promover el progreso de la cultura y de la economía para
asegurar a todos una digna calidad de vida.

   Establecer una sociedad democrática avanzada, y
   Colaborar en el fortalecimiento de unas relaciones pacíficas
y de eficaz cooperación entre todos los pueblos de la Tierra.
   En consecuencia, las Cortes aprueban y el pueblo español
ratifica la siguiente

                                                                                                       5
                      CONSTITUCIÓN$c1$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO PRELIMINAR', 1, 1, md5('TÍTULO PRELIMINAR'))
    returning id into v_node_ids[2];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[2], 'Artículo 1', 0, 2, md5('Artículo 1'))
    returning id into v_node_ids[3];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[3], v_user_id, 'original', $c3$1. España se constituye en un Estado social y democrático

de Derecho, que propugna como valores superiores de su or-
denamiento jurídico la libertad, la justicia, la igualdad y el plu-
ralismo político.

   2. La soberanía nacional reside en el pueblo español, del que
emanan los poderes del Estado.

   3. La forma política del Estado español es la Monarquía par-
lamentaria.$c3$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[2], 'Artículo 2', 1, 2, md5('Artículo 2'))
    returning id into v_node_ids[4];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[4], v_user_id, 'original', $c4$La Constitución se fundamenta en la indisoluble unidad de

la Nación española, patria común e indivisible de todos los
españoles, y reconoce y garantiza el derecho a la autonomía
de las nacionalidades y regiones que la integran y la solidaridad
entre todas ellas.$c4$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[2], 'Artículo 3', 2, 2, md5('Artículo 3'))
    returning id into v_node_ids[5];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[5], v_user_id, 'original', $c5$1. El castellano es la lengua española oficial del Estado. To-

dos los españoles tienen el deber de conocerla y el derecho a
usarla.

   2. Las demás lenguas españolas serán también oficiales en
las respectivas Comunidades Autónomas de acuerdo con sus
Estatutos.

   3. La riqueza de las distintas modalidades lingüísticas de Es-
paña es un patrimonio cultural que será objeto de especial
respeto y protección.$c5$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[2], 'Artículo 4', 3, 2, md5('Artículo 4'))
    returning id into v_node_ids[6];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[6], v_user_id, 'original', $c6$1. La bandera de España está formada por tres franjas hori-

zontales, roja, amarilla y roja, siendo la amarilla de doble an-
chura que cada una de las rojas.

6
   2. Los Estatutos podrán reconocer banderas y enseñas pro-
pias de las Comunidades Autónomas. Estas se utilizarán junto
a la bandera de España en sus edificios públicos y en sus actos
oficiales.$c6$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[2], 'Artículo 5', 4, 2, md5('Artículo 5'))
    returning id into v_node_ids[7];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[7], v_user_id, 'original', $c7$La capital del Estado es la villa de Madrid.$c7$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[2], 'Artículo 6', 5, 2, md5('Artículo 6'))
    returning id into v_node_ids[8];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[8], v_user_id, 'original', $c8$Los partidos políticos expresan el pluralismo político, con-
curren a la formación y manifestación de la voluntad popular
y son instrumento fundamental para la participación política.
Su creación y el ejercicio de su actividad son libres dentro del
respeto a la Constitución y a la ley. Su estructura interna y
funcionamiento deberán ser democráticos.$c8$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[2], 'Artículo 7', 6, 2, md5('Artículo 7'))
    returning id into v_node_ids[9];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[9], v_user_id, 'original', $c9$Los sindicatos de trabajadores y las asociaciones empresa-
riales contribuyen a la defensa y promoción de los intereses
económicos y sociales que les son propios. Su creación y el
ejercicio de su actividad son libres dentro del respeto a la
Constitución y a la ley. Su estructura interna y funcionamiento
deberán ser democráticos.$c9$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[2], 'Artículo 8', 7, 2, md5('Artículo 8'))
    returning id into v_node_ids[10];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[10], v_user_id, 'original', $c10$1. Las Fuerzas Armadas, constituidas por el Ejército de Tierra,
la Armada y el Ejército del Aire, tienen como misión garantizar
la soberanía e independencia de España, defender su integri-
dad territorial y el ordenamiento constitucional.

   2. Una ley orgánica regulará las bases de la organización
militar conforme a los principios de la presente Constitución.$c10$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[2], 'Artículo 9', 8, 2, md5('Artículo 9'))
    returning id into v_node_ids[11];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[11], v_user_id, 'original', $c11$1. Los ciudadanos y los poderes públicos están sujetos a la
Constitución y al resto del ordenamiento jurídico.

   2. Corresponde a los poderes públicos promover las condi-
ciones para que la libertad y la igualdad del individuo y de los
grupos en que se integra sean reales y efectivas; remover los
obstáculos que impidan o dificulten su plenitud y facilitar la

                                                                                                       7
participación de todos los ciudadanos en la vida política, eco-
nómica, cultural y social.

   3. La Constitución garantiza el principio de legalidad, la jerar-
quía normativa, la publicidad de las normas, la irretroactividad
de las disposiciones sancionadoras no favorables o restrictivas
de derechos individuales, la seguridad jurídica, la responsabili-
dad y la interdicción de la arbitrariedad de los poderes públicos.$c11$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO I', 2, 1, md5('TÍTULO I'))
    returning id into v_node_ids[12];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[12], 'Artículo 10', 0, 2, md5('Artículo 10'))
    returning id into v_node_ids[13];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[13], v_user_id, 'original', $c13$1. La dignidad de la persona, los derechos inviolables que le
son inherentes, el libre desarrollo de la personalidad, el respe-
to a la ley y a los derechos de los demás son fundamento del
orden político y de la paz social.

   2. Las normas relativas a los derechos fundamentales y a las
libertades que la Constitución reconoce se interpretarán de
conformidad con la Declaración Universal de Derechos Hu-
manos y los tratados y acuerdos internacionales sobre las mis-
mas materias ratificados por España.$c13$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[12], 'CAPÍTULO PRIMERO', 1, 2, md5('CAPÍTULO PRIMERO'))
    returning id into v_node_ids[14];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[14], 'Artículo 11', 0, 3, md5('Artículo 11'))
    returning id into v_node_ids[15];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[15], v_user_id, 'original', $c15$1. La nacionalidad española se adquiere, se conserva y se
pierde de acuerdo con lo establecido por la ley.

   2. Ningún español de origen podrá ser privado de su nacio-
nalidad.

   3. El Estado podrá concertar tratados de doble nacionalidad
con los países iberoamericanos o con aquellos que hayan te-
nido o tengan una particular vinculación con España. En estos
mismos países, aun cuando no reconozcan a sus ciudadanos
un derecho recíproco, podrán naturalizarse los españoles sin
perder su nacionalidad de origen.$c15$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[14], 'Artículo 12', 1, 3, md5('Artículo 12'))
    returning id into v_node_ids[16];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[16], v_user_id, 'original', $c16$Los españoles son mayores de edad a los dieciocho años.

8$c16$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[14], 'Artículo 13', 2, 3, md5('Artículo 13'))
    returning id into v_node_ids[17];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[17], v_user_id, 'original', $c17$1. Los extranjeros gozarán en España de las libertades públi-
cas que garantiza el presente Título en los términos que esta-
blezcan los tratados y la ley.

   2. Solamente los españoles serán titulares de los derechos
reconocidos en el artículo 23, salvo lo que, atendiendo a cri-
terios de reciprocidad, pueda establecerse por tratado o ley
para el derecho de sufragio activo y pasivo en las elecciones
municipales.

   3. La extradición sólo se concederá en cumplimiento de un
tratado o de la ley, atendiendo al principio de reciprocidad.
Quedan excluidos de la extradición los delitos políticos, no
considerándose como tales los actos de terrorismo.

   4. La ley establecerá los términos en que los ciudadanos de
otros países y los apátridas podrán gozar del derecho de asilo
en España.$c17$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[12], 'CAPÍTULO SEGUNDO', 2, 2, md5('CAPÍTULO SEGUNDO'))
    returning id into v_node_ids[18];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[18], 'Artículo 14', 0, 3, md5('Artículo 14'))
    returning id into v_node_ids[19];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[19], v_user_id, 'original', $c19$Los españoles son iguales ante la ley, sin que pueda preva-
lecer discriminación alguna por razón de nacimiento, raza,
sexo, religión, opinión o cualquier otra condición o circuns-
tancia personal o social.$c19$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[18], 'Sección 1.ª De los derechos fundamentales y de las libertades', 1, 3, md5('Sección 1.ª De los derechos fundamentales y de las libertades'))
    returning id into v_node_ids[20];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 15', 0, 4, md5('Artículo 15'))
    returning id into v_node_ids[21];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[21], v_user_id, 'original', $c21$Todos tienen derecho a la vida y a la integridad física y mo-
ral, sin que, en ningún caso, puedan ser sometidos a tortura ni
a penas o tratos inhumanos o degradantes. Queda abolida la
pena de muerte, salvo lo que puedan disponer las leyes pena-
les militares para tiempos de guerra.$c21$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 16', 1, 4, md5('Artículo 16'))
    returning id into v_node_ids[22];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[22], v_user_id, 'original', $c22$1. Se garantiza la libertad ideológica, religiosa y de culto de
los individuos y las comunidades sin más limitación, en sus

                                                                                                       9
manifestaciones, que la necesaria para el mantenimiento del
orden público protegido por la ley.

   2. Nadie podrá ser obligado a declarar sobre su ideología,
religión o creencias.

   3. Ninguna confesión tendrá carácter estatal. Los poderes
públicos tendrán en cuenta las creencias religiosas de la socie-
dad española y mantendrán las consiguientes relaciones de
cooperación con la Iglesia Católica y las demás confesiones.$c22$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 17', 2, 4, md5('Artículo 17'))
    returning id into v_node_ids[23];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[23], v_user_id, 'original', $c23$1. Toda persona tiene derecho a la libertad y a la seguridad.
Nadie puede ser privado de su libertad, sino con la observancia
de lo establecido en este artículo y en los casos y en la forma
previstos en la ley.

   2. La detención preventiva no podrá durar más del tiempo
estrictamente necesario para la realización de las averiguacio-
nes tendentes al esclarecimiento de los hechos, y, en todo
caso, en el plazo máximo de setenta y dos horas, el detenido
deberá ser puesto en libertad o a disposición de la autoridad
judicial.

   3. Toda persona detenida debe ser informada de forma in-
mediata, y de modo que le sea comprensible, de sus derechos
y de las razones de su detención, no pudiendo ser obligada a
declarar. Se garantiza la asistencia de abogado al detenido en
las diligencias policiales y judiciales, en los términos que la ley
establezca.

   4. La ley regulará un procedimiento de «habeas corpus»
para producir la inmediata puesta a disposición judicial de toda
persona detenida ilegalmente. Asimismo, por ley se determi-
nará el plazo máximo de duración de la prisión provisional.$c23$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 18', 3, 4, md5('Artículo 18'))
    returning id into v_node_ids[24];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[24], v_user_id, 'original', $c24$1. Se garantiza el derecho al honor, a la intimidad personal y
familiar y a la propia imagen.

   2. El domicilio es inviolable. Ninguna entrada o registro po-
drá hacerse en él sin consentimiento del titular o resolución
judicial, salvo en caso de flagrante delito.

   3. Se garantiza el secreto de las comunicaciones y, en espe-
cial, de las postales, telegráficas y telefónicas, salvo resolución
judicial.

10
   4. La ley limitará el uso de la informática para garantizar el
honor y la intimidad personal y familiar de los ciudadanos y el
pleno ejercicio de sus derechos.$c24$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 19', 4, 4, md5('Artículo 19'))
    returning id into v_node_ids[25];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[25], v_user_id, 'original', $c25$Los españoles tienen derecho a elegir libremente su resi-
dencia y a circular por el territorio nacional.

   Asimismo, tienen derecho a entrar y salir libremente de Es-
paña en los términos que la ley establezca. Este derecho no
podrá ser limitado por motivos políticos o ideológicos.$c25$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 20', 5, 4, md5('Artículo 20'))
    returning id into v_node_ids[26];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[26], v_user_id, 'original', $c26$1. Se reconocen y protegen los derechos:

     a)	A expresar y difundir libremente los pensamientos, ideas
         y opiniones mediante la palabra, el escrito o cualquier
         otro medio de reproducción.

     b)	A la producción y creación literaria, artística, científica y
         técnica.

     c) A la libertad de cátedra.
     d)	A comunicar o recibir libremente información veraz por

         cualquier medio de difusión. La ley regulará el derecho
         a la cláusula de conciencia y al secreto profesional en el
         ejercicio de estas libertades.

   2. El ejercicio de estos derechos no puede restringirse me-
diante ningún tipo de censura previa.

   3. La ley regulará la organización y el control parlamentario
de los medios de comunicación social dependientes del Esta-
do o de cualquier ente público y garantizará el acceso a dichos
medios de los grupos sociales y políticos significativos, respe-
tando el pluralismo de la sociedad y de las diversas lenguas de
España.

   4. Estas libertades tienen su límite en el respeto a los dere-
chos reconocidos en este Título, en los preceptos de las leyes
que lo desarrollen y, especialmente, en el derecho al honor, a
la intimidad, a la propia imagen y a la protección de la juventud
y de la infancia.

   5. Sólo podrá acordarse el secuestro de publicaciones, gra-
baciones y otros medios de información en virtud de resolu-
ción judicial.

                                                                                                      11$c26$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 21', 6, 4, md5('Artículo 21'))
    returning id into v_node_ids[27];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[27], v_user_id, 'original', $c27$1. Se reconoce el derecho de reunión pacífica y sin armas. El
ejercicio de este derecho no necesitará autorización previa.

   2. En los casos de reuniones en lugares de tránsito público y
manifestaciones se dará comunicación previa a la autoridad,
que sólo podrá prohibirlas cuando existan razones fundadas
de alteración del orden público, con peligro para personas o
bienes.$c27$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 22', 7, 4, md5('Artículo 22'))
    returning id into v_node_ids[28];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[28], v_user_id, 'original', $c28$1. Se reconoce el derecho de asociación.
   2. Las asociaciones que persigan fines o utilicen medios ti-
pificados como delito son ilegales.
   3. Las asociaciones constituidas al amparo de este artículo
deberán inscribirse en un registro a los solos efectos de publi-
cidad.
   4. Las asociaciones sólo podrán ser disueltas o suspendidas
en sus actividades en virtud de resolución judicial motivada.
   5. Se prohíben las asociaciones secretas y las de carácter
paramilitar.$c28$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 23', 8, 4, md5('Artículo 23'))
    returning id into v_node_ids[29];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[29], v_user_id, 'original', $c29$1. Los ciudadanos tienen el derecho a participar en los asun-
tos públicos, directamente o por medio de representantes, li-
bremente elegidos en elecciones periódicas por sufragio uni-
versal.

   2. Asimismo, tienen derecho a acceder en condiciones de
igualdad a las funciones y cargos públicos, con los requisitos
que señalen las leyes.$c29$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 24', 9, 4, md5('Artículo 24'))
    returning id into v_node_ids[30];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[30], v_user_id, 'original', $c30$1. Todas las personas tienen derecho a obtener la tutela
efectiva de los jueces y tribunales en el ejercicio de sus dere-
chos e intereses legítimos, sin que, en ningún caso, pueda
producirse indefensión.

   2. Asimismo, todos tienen derecho al Juez ordinario prede-
terminado por la ley, a la defensa y a la asistencia de letrado, a
ser informados de la acusación formulada contra ellos, a un
proceso público sin dilaciones indebidas y con todas las ga-
rantías, a utilizar los medios de prueba pertinentes para su

12
defensa, a no declarar contra sí mismos, a no confesarse cul-
pables y a la presunción de inocencia.

   La ley regulará los casos en que, por razón de parentesco o
de secreto profesional, no se estará obligado a declarar sobre
hechos presuntamente delictivos.$c30$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 25', 10, 4, md5('Artículo 25'))
    returning id into v_node_ids[31];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[31], v_user_id, 'original', $c31$1. Nadie puede ser condenado o sancionado por acciones u
omisiones que en el momento de producirse no constituyan
delito, falta o infracción administrativa, según la legislación
vigente en aquel momento.

   2. Las penas privativas de libertad y las medidas de seguridad
estarán orientadas hacia la reeducación y reinserción social y
no podrán consistir en trabajos forzados. El condenado a pena
de prisión que estuviere cumpliendo la misma gozará de los
derechos fundamentales de este Capítulo, a excepción de los
que se vean expresamente limitados por el contenido del fallo
condenatorio, el sentido de la pena y la ley penitenciaria. En
todo caso, tendrá derecho a un trabajo remunerado y a los
beneficios correspondientes de la Seguridad Social, así como
al acceso a la cultura y al desarrollo integral de su personali-
dad.

   3. La Administración civil no podrá imponer sanciones que,
directa o subsidiariamente, impliquen privación de libertad.$c31$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 26', 11, 4, md5('Artículo 26'))
    returning id into v_node_ids[32];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[32], v_user_id, 'original', $c32$Se prohíben los Tribunales de Honor en el ámbito de la Ad-
ministración civil y de las organizaciones profesionales.$c32$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 27', 12, 4, md5('Artículo 27'))
    returning id into v_node_ids[33];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[33], v_user_id, 'original', $c33$1. Todos tienen el derecho a la educación. Se reconoce la
libertad de enseñanza.

   2. La educación tendrá por objeto el pleno desarrollo de la
personalidad humana en el respeto a los principios democrá-
ticos de convivencia y a los derechos y libertades fundamen-
tales.

   3. Los poderes públicos garantizan el derecho que asiste a
los padres para que sus hijos reciban la formación religiosa y
moral que esté de acuerdo con sus propias convicciones.

   4. La enseñanza básica es obligatoria y gratuita.

                                                                                                     13
   5. Los poderes públicos garantizan el derecho de todos a la
educación, mediante una programación general de la ense-
ñanza, con participación efectiva de todos los sectores afecta-
dos y la creación de centros docentes.

   6. Se reconoce a las personas físicas y jurídicas la libertad de
creación de centros docentes, dentro del respeto a los princi-
pios constitucionales.

   7. Los profesores, los padres y, en su caso, los alumnos in-
tervendrán en el control y gestión de todos los centros soste-
nidos por la Administración con fondos públicos, en los térmi-
nos que la ley establezca.

   8. Los poderes públicos inspeccionarán y homologarán el
sistema educativo para garantizar el cumplimiento de las leyes.

   9. Los poderes públicos ayudarán a los centros docentes
que reúnan los requisitos que la ley establezca.

   10. Se reconoce la autonomía de las Universidades, en los
términos que la ley establezca.$c33$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 28', 13, 4, md5('Artículo 28'))
    returning id into v_node_ids[34];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[34], v_user_id, 'original', $c34$1. Todos tienen derecho a sindicarse libremente. La ley po-
drá limitar o exceptuar el ejercicio de este derecho a las Fuer-
zas o Institutos armados o a los demás Cuerpos sometidos a
disciplina militar y regulará las peculiaridades de su ejercicio
para los funcionarios públicos. La libertad sindical comprende
el derecho a fundar sindicatos y a afiliarse al de su elección,
así como el derecho de los sindicatos a formar confederacio-
nes y a fundar organizaciones sindicales internacionales o a
afiliarse a las mismas. Nadie podrá ser obligado a afiliarse a un
sindicato.

   2. Se reconoce el derecho a la huelga de los trabajadores para
la defensa de sus intereses. La ley que regule el ejercicio de este
derecho establecerá las garantías precisas para asegurar el
mantenimiento de los servicios esenciales de la comunidad.$c34$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[20], 'Artículo 29', 14, 4, md5('Artículo 29'))
    returning id into v_node_ids[35];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[35], v_user_id, 'original', $c35$1. Todos los españoles tendrán el derecho de petición indi-
vidual y colectiva, por escrito, en la forma y con los efectos
que determine la ley.

   2. Los miembros de las Fuerzas o Institutos armados o de los
Cuerpos sometidos a disciplina militar podrán ejercer este de-

14
recho sólo individualmente y con arreglo a lo dispuesto en su
legislación específica.$c35$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[18], 'Sección 2.ª De los derechos y deberes de los ciudadanos', 2, 3, md5('Sección 2.ª De los derechos y deberes de los ciudadanos'))
    returning id into v_node_ids[36];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[36], 'Artículo 30', 0, 4, md5('Artículo 30'))
    returning id into v_node_ids[37];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[37], v_user_id, 'original', $c37$1. Los españoles tienen el derecho y el deber de defender a
España.

   2. La ley fijará las obligaciones militares de los españoles y
regulará, con las debidas garantías, la objeción de conciencia,
así como las demás causas de exención del servicio militar
obligatorio, pudiendo imponer, en su caso, una prestación so-
cial sustitutoria.

   3. Podrá establecerse un servicio civil para el cumplimiento
de fines de interés general.

   4. Mediante ley podrán regularse los deberes de los ciuda-
danos en los casos de grave riesgo, catástrofe o calamidad
pública.$c37$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[36], 'Artículo 31', 1, 4, md5('Artículo 31'))
    returning id into v_node_ids[38];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[38], v_user_id, 'original', $c38$1. Todos contribuirán al sostenimiento de los gastos públicos
de acuerdo con su capacidad económica mediante un sistema
tributario justo inspirado en los principios de igualdad y progre-
sividad que, en ningún caso, tendrá alcance confiscatorio.

   2. El gasto público realizará una asignación equitativa de los
recursos públicos, y su programación y ejecución responderán
a los criterios de eficiencia y economía.

   3. Sólo podrán establecerse prestaciones personales o patri-
moniales de carácter público con arreglo a la ley.$c38$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[36], 'Artículo 32', 2, 4, md5('Artículo 32'))
    returning id into v_node_ids[39];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[39], v_user_id, 'original', $c39$1. El hombre y la mujer tienen derecho a contraer matrimo-
nio con plena igualdad jurídica.

   2. La ley regulará las formas de matrimonio, la edad y capa-
cidad para contraerlo, los derechos y deberes de los cónyuges,
las causas de separación y disolución y sus efectos.$c39$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[36], 'Artículo 33', 3, 4, md5('Artículo 33'))
    returning id into v_node_ids[40];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[40], v_user_id, 'original', $c40$1. Se reconoce el derecho a la propiedad privada y a la he-
rencia.

                                                                                                     15
   2. La función social de estos derechos delimitará su conte-
nido, de acuerdo con las leyes.

   3. Nadie podrá ser privado de sus bienes y derechos sino por
causa justificada de utilidad pública o interés social, mediante
la correspondiente indemnización y de conformidad con lo
dispuesto por las leyes.$c40$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[36], 'Artículo 34', 4, 4, md5('Artículo 34'))
    returning id into v_node_ids[41];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[41], v_user_id, 'original', $c41$1. Se reconoce el derecho de fundación para fines de interés
general, con arreglo a la ley.

   2. Regirá también para las fundaciones lo dispuesto en los
apartados 2 y 4 del artículo 22.$c41$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[36], 'Artículo 35', 5, 4, md5('Artículo 35'))
    returning id into v_node_ids[42];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[42], v_user_id, 'original', $c42$1. Todos los españoles tienen el deber de trabajar y el dere-
cho al trabajo, a la libre elección de profesión u oficio, a la
promoción a través del trabajo y a una remuneración suficien-
te para satisfacer sus necesidades y las de su familia, sin que en
ningún caso pueda hacerse discriminación por razón de sexo.

   2. La ley regulará un estatuto de los trabajadores.$c42$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[36], 'Artículo 36', 6, 4, md5('Artículo 36'))
    returning id into v_node_ids[43];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[43], v_user_id, 'original', $c43$La ley regulará las peculiaridades propias del régimen jurídi-
co de los Colegios Profesionales y el ejercicio de las profesio-
nes tituladas. La estructura interna y el funcionamiento de los
Colegios deberán ser democráticos.$c43$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[36], 'Artículo 37', 7, 4, md5('Artículo 37'))
    returning id into v_node_ids[44];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[44], v_user_id, 'original', $c44$1. La ley garantizará el derecho a la negociación colectiva
laboral entre los representantes de los trabajadores y empre-
sarios, así como la fuerza vinculante de los convenios.

   2. Se reconoce el derecho de los trabajadores y empresarios
a adoptar medidas de conflicto colectivo. La ley que regule el
ejercicio de este derecho, sin perjuicio de las limitaciones que
puedan establecer, incluirá las garantías precisas para asegurar
el funcionamiento de los servicios esenciales de la comunidad.$c44$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[36], 'Artículo 38', 8, 4, md5('Artículo 38'))
    returning id into v_node_ids[45];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[45], v_user_id, 'original', $c45$Se reconoce la libertad de empresa en el marco de la eco-

nomía de mercado. Los poderes públicos garantizan y prote-

16
gen su ejercicio y la defensa de la productividad, de acuerdo
con las exigencias de la economía general y, en su caso, de la
planificación.$c45$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[12], 'CAPÍTULO TERCERO', 3, 2, md5('CAPÍTULO TERCERO'))
    returning id into v_node_ids[46];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 39', 0, 3, md5('Artículo 39'))
    returning id into v_node_ids[47];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[47], v_user_id, 'original', $c47$1. Los poderes públicos aseguran la protección social, eco-
nómica y jurídica de la familia.

   2. Los poderes públicos aseguran, asimismo, la protección
integral de los hijos, iguales éstos ante la ley con independen-
cia de su filiación, y de las madres, cualquiera que sea su esta-
do civil. La ley posibilitará la investigación de la paternidad.

   3. Los padres deben prestar asistencia de todo orden a los
hijos habidos dentro o fuera del matrimonio, durante su mino-
ría de edad y en los demás casos en que legalmente proceda.

   4. Los niños gozarán de la protección prevista en los acuer-
dos internacionales que velan por sus derechos.$c47$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 40', 1, 3, md5('Artículo 40'))
    returning id into v_node_ids[48];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[48], v_user_id, 'original', $c48$1. Los poderes públicos promoverán las condiciones favora-

bles para el progreso social y económico y para una distribu-
ción de la renta regional y personal más equitativa, en el mar-
co de una política de estabilidad económica. De manera
especial realizarán una política orientada al pleno empleo.

   2. Asimismo, los poderes públicos fomentarán una política
que garantice la formación y readaptación profesionales; vela-
rán por la seguridad e higiene en el trabajo y garantizarán el
descanso necesario, mediante la limitación de la jornada labo-
ral, las vacaciones periódicas retribuidas y la promoción de
centros adecuados.$c48$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 41', 2, 3, md5('Artículo 41'))
    returning id into v_node_ids[49];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[49], v_user_id, 'original', $c49$Los poderes públicos mantendrán un régimen público de

Seguridad Social para todos los ciudadanos, que garantice la
asistencia y prestaciones sociales suficientes ante situaciones
de necesidad, especialmente en caso de desempleo. La asis-
tencia y prestaciones complementarias serán libres.

                                                                                                     17$c49$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 42', 3, 3, md5('Artículo 42'))
    returning id into v_node_ids[50];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[50], v_user_id, 'original', $c50$El Estado velará especialmente por la salvaguardia de los
derechos económicos y sociales de los trabajadores españoles
en el extranjero y orientará su política hacia su retorno.$c50$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 43', 4, 3, md5('Artículo 43'))
    returning id into v_node_ids[51];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[51], v_user_id, 'original', $c51$1. Se reconoce el derecho a la protección de la salud.
   2. Compete a los poderes públicos organizar y tutelar la sa-
lud pública a través de medidas preventivas y de las prestacio-
nes y servicios necesarios. La ley establecerá los derechos y
deberes de todos al respecto.
   3. Los poderes públicos fomentarán la educación sanitaria,
la educación física y el deporte. Asimismo facilitarán la ade-
cuada utilización del ocio.$c51$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 44', 5, 3, md5('Artículo 44'))
    returning id into v_node_ids[52];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[52], v_user_id, 'original', $c52$1. Los poderes públicos promoverán y tutelarán el acceso a
la cultura, a la que todos tienen derecho.

   2. Los poderes públicos promoverán la ciencia y la investi-
gación científica y técnica en beneficio del interés general.$c52$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 45', 6, 3, md5('Artículo 45'))
    returning id into v_node_ids[53];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[53], v_user_id, 'original', $c53$1. Todos tienen el derecho a disfrutar de un medio ambiente
adecuado para el desarrollo de la persona, así como el deber
de conservarlo.

   2. Los poderes públicos velarán por la utilización racional de
todos los recursos naturales, con el fin de proteger y mejorar
la calidad de la vida y defender y restaurar el medio ambiente,
apoyándose en la indispensable solidaridad colectiva.

   3. Para quienes violen lo dispuesto en el apartado anterior,
en los términos que la ley fije se establecerán sanciones pena-
les o, en su caso, administrativas, así como la obligación de
reparar el daño causado.$c53$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 46', 7, 3, md5('Artículo 46'))
    returning id into v_node_ids[54];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[54], v_user_id, 'original', $c54$Los poderes públicos garantizarán la conservación y promo-
verán el enriquecimiento del patrimonio histórico, cultural y
artístico de los pueblos de España y de los bienes que lo inte-
gran, cualquiera que sea su régimen jurídico y su titularidad. La
ley penal sancionará los atentados contra este patrimonio.

18$c54$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 47', 8, 3, md5('Artículo 47'))
    returning id into v_node_ids[55];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[55], v_user_id, 'original', $c55$Todos los españoles tienen derecho a disfrutar de una vi-
vienda digna y adecuada. Los poderes públicos promoverán
las condiciones necesarias y establecerán las normas pertinen-
tes para hacer efectivo este derecho, regulando la utilización
del suelo de acuerdo con el interés general para impedir la
especulación. La comunidad participará en las plusvalías que
genere la acción urbanística de los entes públicos.$c55$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 48', 9, 3, md5('Artículo 48'))
    returning id into v_node_ids[56];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[56], v_user_id, 'original', $c56$Los poderes públicos promoverán las condiciones para la
participación libre y eficaz de la juventud en el desarrollo polí-
tico, social, económico y cultural.$c56$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 49', 10, 3, md5('Artículo 49'))
    returning id into v_node_ids[57];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[57], v_user_id, 'original', $c57$1. Las personas con discapacidad ejercen los derechos pre-
vistos en este Título en condiciones de libertad e igualdad
reales y efectivas. Se regulará por ley la protección especial
que sea necesaria para dicho ejercicio.

   2. Los poderes públicos impulsarán las políticas que garan-
ticen la plena autonomía personal y la inclusión social de las
personas con discapacidad, en entornos universalmente acce-
sibles. Asimismo, fomentarán la participación de sus organiza-
ciones, en los términos que la ley establezca. Se atenderán
particularmente las necesidades específicas de las mujeres y
los menores con discapacidad.$c57$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 50', 11, 3, md5('Artículo 50'))
    returning id into v_node_ids[58];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[58], v_user_id, 'original', $c58$Los poderes públicos garantizarán, mediante pensiones ade-
cuadas y periódicamente actualizadas, la suficiencia económica
a los ciudadanos durante la tercera edad. Asimismo, y con inde-
pendencia de las obligaciones familiares, promoverán su bien-
estar mediante un sistema de servicios sociales que atenderán
sus problemas específicos de salud, vivienda, cultura y ocio.$c58$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 51', 12, 3, md5('Artículo 51'))
    returning id into v_node_ids[59];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[59], v_user_id, 'original', $c59$1. Los poderes públicos garantizarán la defensa de los con-
sumidores y usuarios, protegiendo, mediante procedimientos
eficaces, la seguridad, la salud y los legítimos intereses econó-
micos de los mismos.

                                                                                                     19
   2. Los poderes públicos promoverán la información y la
educación de los consumidores y usuarios, fomentarán sus
organizaciones y oirán a éstas en las cuestiones que puedan
afectar a aquéllos, en los términos que la ley establezca.

   3. En el marco de lo dispuesto por los apartados anteriores,
la ley regulará el comercio interior y el régimen de autoriza-
ción de productos comerciales.$c59$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[46], 'Artículo 52', 13, 3, md5('Artículo 52'))
    returning id into v_node_ids[60];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[60], v_user_id, 'original', $c60$La ley regulará las organizaciones profesionales que contri-
buyan a la defensa de los intereses económicos que les sean
propios. Su estructura interna y funcionamiento deberán ser
democráticos.$c60$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[12], 'CAPÍTULO CUARTO', 4, 2, md5('CAPÍTULO CUARTO'))
    returning id into v_node_ids[61];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[61], 'Artículo 53', 0, 3, md5('Artículo 53'))
    returning id into v_node_ids[62];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[62], v_user_id, 'original', $c62$1. Los derechos y libertades reconocidos en el Capítulo segun-
do del presente Título vinculan a todos los poderes públicos. Sólo
por ley, que en todo caso deberá respetar su contenido esencial,
podrá regularse el ejercicio de tales derechos y libertades, que se
tutelarán de acuerdo con lo previsto en el artículo 161, 1, a).

   2. Cualquier ciudadano podrá recabar la tutela de las liber-
tades y derechos reconocidos en el artículo 14 y la Sección
primera del Capítulo segundo ante los Tribunales ordinarios
por un procedimiento basado en los principios de preferencia
y sumariedad y, en su caso, a través del recurso de amparo
ante el Tribunal Constitucional. Este último recurso será apli-
cable a la objeción de conciencia reconocida en el artículo 30.

   3. El reconocimiento, el respeto y la protección de los princi-
pios reconocidos en el Capítulo tercero informarán la legisla-
ción positiva, la práctica judicial y la actuación de los poderes
públicos. Sólo podrán ser alegados ante la Jurisdicción ordinaria
de acuerdo con lo que dispongan las leyes que los desarrollen.$c62$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[61], 'Artículo 54', 1, 3, md5('Artículo 54'))
    returning id into v_node_ids[63];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[63], v_user_id, 'original', $c63$Una ley orgánica regulará la institución del Defensor del
Pueblo, como alto comisionado de las Cortes Generales, de-

20
signado por éstas para la defensa de los derechos comprendi-
dos en este Título, a cuyo efecto podrá supervisar la actividad
de la Administración, dando cuenta a las Cortes Generales.$c63$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[12], 'CAPÍTULO QUINTO', 5, 2, md5('CAPÍTULO QUINTO'))
    returning id into v_node_ids[64];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[64], 'Artículo 55', 0, 3, md5('Artículo 55'))
    returning id into v_node_ids[65];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[65], v_user_id, 'original', $c65$1. Los derechos reconocidos en los artículos 17, 18, apartados
2 y 3, artículos 19, 20, apartados 1, a) y d), y 5, artículos 21, 28,
apartado 2, y artículo 37, apartado 2, podrán ser suspendidos
cuando se acuerde la declaración del estado de excepción o de
sitio en los términos previstos en la Constitución. Se exceptúa
de lo establecido anteriormente el apartado 3 del artículo 17
para el supuesto de declaración de estado de excepción.

   2. Una ley orgánica podrá determinar la forma y los casos en
los que, de forma individual y con la necesaria intervención
judicial y el adecuado control parlamentario, los derechos re-
conocidos en los artículos 17, apartado 2, y 18, apartados 2 y 3,
pueden ser suspendidos para personas determinadas, en rela-
ción con las investigaciones correspondientes a la actuación
de bandas armadas o elementos terroristas.

   La utilización injustificada o abusiva de las facultades reco-
nocidas en dicha ley orgánica producirá responsabilidad penal,
como violación de los derechos y libertades reconocidos por
las leyes.$c65$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO II', 3, 1, md5('TÍTULO II'))
    returning id into v_node_ids[66];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 56', 0, 2, md5('Artículo 56'))
    returning id into v_node_ids[67];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[67], v_user_id, 'original', $c67$1. El Rey es el Jefe del Estado, símbolo de su unidad y per-
manencia, arbitra y modera el funcionamiento regular de las
instituciones, asume la más alta representación del Estado
español en las relaciones internacionales, especialmente con
las naciones de su comunidad histórica, y ejerce las funciones
que le atribuyen expresamente la Constitución y las leyes.

   2. Su título es el de Rey de España y podrá utilizar los demás
que correspondan a la Corona.

                                                                                                     21
   3. La persona del Rey es inviolable y no está sujeta a respon-
sabilidad. Sus actos estarán siempre refrendados en la forma
establecida en el artículo 64, careciendo de validez sin dicho
refrendo, salvo lo dispuesto en el artículo 65, 2.$c67$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 57', 1, 2, md5('Artículo 57'))
    returning id into v_node_ids[68];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[68], v_user_id, 'original', $c68$1. La Corona de España es hereditaria en los sucesores de S.
M. Don Juan Carlos I de Borbón, legítimo heredero de la di-
nastía histórica. La sucesión en el trono seguirá el orden regu-
lar de primogenitura y representación, siendo preferida siem-
pre la línea anterior a las posteriores; en la misma línea, el
grado más próximo al más remoto; en el mismo grado, el va-
rón a la mujer, y en el mismo sexo, la persona de más edad a
la de menos.

   2. El Príncipe heredero, desde su nacimiento o desde que se
produzca el hecho que origine el llamamiento, tendrá la dig-
nidad de Príncipe de Asturias y los demás títulos vinculados
tradicionalmente al sucesor de la Corona de España.

   3. Extinguidas todas las líneas llamadas en Derecho, las Cor-
tes Generales proveerán a la sucesión en la Corona en la forma
que más convenga a los intereses de España.

   4. Aquellas personas que teniendo derecho a la sucesión en
el trono contrajeren matrimonio contra la expresa prohibición
del Rey y de las Cortes Generales, quedarán excluidas en la
sucesión a la Corona por sí y sus descendientes.

   5. Las abdicaciones y renuncias y cualquier duda de hecho
o de derecho que ocurra en el orden de sucesión a la Corona
se resolverán por una ley orgánica.$c68$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 58', 2, 2, md5('Artículo 58'))
    returning id into v_node_ids[69];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[69], v_user_id, 'original', $c69$La Reina consorte o el consorte de la Reina no podrán asu-
mir funciones constitucionales, salvo lo dispuesto para la Re-
gencia.$c69$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 59', 3, 2, md5('Artículo 59'))
    returning id into v_node_ids[70];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[70], v_user_id, 'original', $c70$1. Cuando el Rey fuere menor de edad, el padre o la madre
del Rey y, en su defecto, el pariente mayor de edad más próxi-
mo a suceder en la Corona, según el orden establecido en la
Constitución, entrará a ejercer inmediatamente la Regencia y
la ejercerá durante el tiempo de la minoría de edad del Rey.

22
   2. Si el Rey se inhabilitare para el ejercicio de su autoridad y
la imposibilidad fuere reconocida por las Cortes Generales,
entrará a ejercer inmediatamente la Regencia el Príncipe here-
dero de la Corona, si fuere mayor de edad. Si no lo fuere, se
procederá de la manera prevista en el apartado anterior, hasta
que el Príncipe heredero alcance la mayoría de edad.

   3. Si no hubiere ninguna persona a quien corresponda la
Regencia, ésta será nombrada por las Cortes Generales, y se
compondrá de una, tres o cinco personas.

   4. Para ejercer la Regencia es preciso ser español y mayor de
edad.

   5. La Regencia se ejercerá por mandato constitucional y
siempre en nombre del Rey.$c70$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 60', 4, 2, md5('Artículo 60'))
    returning id into v_node_ids[71];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[71], v_user_id, 'original', $c71$1. Será tutor del Rey menor la persona que en su testamen-
to hubiese nombrado el Rey difunto, siempre que sea mayor
de edad y español de nacimiento; si no lo hubiese nombrado,
será tutor el padre o la madre mientras permanezcan viudos.
En su defecto, lo nombrarán las Cortes Generales, pero no
podrán acumularse los cargos de Regente y de tutor sino en el
padre, madre o ascendientes directos del Rey.

   2. El ejercicio de la tutela es también incompatible con el de
todo cargo o representación política.$c71$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 61', 5, 2, md5('Artículo 61'))
    returning id into v_node_ids[72];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[72], v_user_id, 'original', $c72$1. El Rey, al ser proclamado ante las Cortes Generales,
prestará juramento de desempeñar fielmente sus funciones,
guardar y hacer guardar la Constitución y las leyes y respe-
tar los derechos de los ciudadanos y de las Comunidades
Autónomas.

   2. El Príncipe heredero, al alcanzar la mayoría de edad, y el
Regente o Regentes al hacerse cargo de sus funciones, pres-
tarán el mismo juramento, así como el de fidelidad al Rey.$c72$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 62', 6, 2, md5('Artículo 62'))
    returning id into v_node_ids[73];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[73], v_user_id, 'original', $c73$Corresponde al Rey:

   a) Sancionar y promulgar las leyes.
   b) Convocar y disolver las Cortes Generales y convocar

      elecciones en los términos previstos en la Constitución.

                                                                                                     23
   c) Convocar a referéndum en los casos previstos en la Cons-
      titución.

   d) Proponer el candidato a Presidente del Gobierno y, en su
      caso, nombrarlo, así como poner fin a sus funciones en
      los términos previstos en la Constitución.

   e) Nombrar y separar a los miembros del Gobierno, a pro-
      puesta de su Presidente.

   f) Expedir los decretos acordados en el Consejo de Minis-
      tros, conferir los empleos civiles y militares y conceder
      honores y distinciones con arreglo a las leyes.

   g) Ser informado de los asuntos de Estado y presidir, a estos
      efectos, las sesiones del Consejo de Ministros, cuando lo
      estime oportuno, a petición del Presidente del Gobierno.

   h) El mando supremo de las Fuerzas Armadas.
   i) Ejercer el derecho de gracia con arreglo a la ley, que no

      podrá autorizar indultos generales.
   j) El Alto Patronazgo de las Reales Academias.$c73$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 63', 7, 2, md5('Artículo 63'))
    returning id into v_node_ids[74];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[74], v_user_id, 'original', $c74$1. El Rey acredita a los embajadores y otros representantes
diplomáticos. Los representantes extranjeros en España están
acreditados ante él.

   2. Al Rey corresponde manifestar el consentimiento del Es-
tado para obligarse internacionalmente por medio de tratados,
de conformidad con la Constitución y las leyes.

   3. Al Rey corresponde, previa autorización de las Cortes Ge-
nerales, declarar la guerra y hacer la paz.$c74$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 64', 8, 2, md5('Artículo 64'))
    returning id into v_node_ids[75];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[75], v_user_id, 'original', $c75$1. Los actos del Rey serán refrendados por el Presidente del
Gobierno y, en su caso, por los Ministros competentes. La pro-
puesta y el nombramiento del Presidente del Gobierno, y la
disolución prevista en el artículo 99, serán refrendados por el
Presidente del Congreso.

   2. De los actos del Rey serán responsables las personas que
los refrenden.$c75$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[66], 'Artículo 65', 9, 2, md5('Artículo 65'))
    returning id into v_node_ids[76];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[76], v_user_id, 'original', $c76$1. El Rey recibe de los Presupuestos del Estado una cantidad
global para el sostenimiento de su Familia y Casa, y distribuye
libremente la misma.

24
   2. El Rey nombra y releva libremente a los miembros civiles
y militares de su Casa.$c76$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO III', 4, 1, md5('TÍTULO III'))
    returning id into v_node_ids[77];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[77], 'CAPÍTULO PRIMERO', 0, 2, md5('CAPÍTULO PRIMERO'))
    returning id into v_node_ids[78];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 66', 0, 3, md5('Artículo 66'))
    returning id into v_node_ids[79];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[79], v_user_id, 'original', $c79$1. Las Cortes Generales representan al pueblo español y es-
tán formadas por el Congreso de los Diputados y el Senado.

   2. Las Cortes Generales ejercen la potestad legislativa del
Estado, aprueban sus Presupuestos, controlan la acción del
Gobierno y tienen las demás competencias que les atribuya la
Constitución.

   3. Las Cortes Generales son inviolables.$c79$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 67', 1, 3, md5('Artículo 67'))
    returning id into v_node_ids[80];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[80], v_user_id, 'original', $c80$1. Nadie podrá ser miembro de las dos Cámaras simultánea-

mente, ni acumular el acta de una Asamblea de Comunidad
Autónoma con la de Diputado al Congreso.

   2. Los miembros de las Cortes Generales no estarán ligados
por mandato imperativo.

   3. Las reuniones de Parlamentarios que se celebren sin con-
vocatoria reglamentaria no vincularán a las Cámaras, y no po-
drán ejercer sus funciones ni ostentar sus privilegios.$c80$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 68', 2, 3, md5('Artículo 68'))
    returning id into v_node_ids[81];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[81], v_user_id, 'original', $c81$1. El Congreso se compone de un mínimo de 300 y un máxi-

mo de 400 Diputados, elegidos por sufragio universal, libre,
igual, directo y secreto, en los términos que establezca la ley.

   2. La circunscripción electoral es la provincia. Las poblaciones
de Ceuta y Melilla estarán representadas cada una de ellas por un
Diputado. La ley distribuirá el número total de Diputados, asig-
nando una representación mínima inicial a cada circunscripción
y distribuyendo los demás en proporción a la población.

   3. La elección se verificará en cada circunscripción aten-
diendo a criterios de representación proporcional.

                                                                                                     25
   4. El Congreso es elegido por cuatro años. El mandato de
los Diputados termina cuatro años después de su elección o el
día de la disolución de la Cámara.

   5. Son electores y elegibles todos los españoles que estén
en pleno uso de sus derechos políticos.

   La ley reconocerá y el Estado facilitará el ejercicio del dere-
cho de sufragio a los españoles que se encuentren fuera del
territorio de España.

   6. Las elecciones tendrán lugar entre los treinta días y se-
senta días desde la terminación del mandato. El Congreso
electo deberá ser convocado dentro de los veinticinco días
siguientes a la celebración de las elecciones.$c81$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 69', 3, 3, md5('Artículo 69'))
    returning id into v_node_ids[82];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[82], v_user_id, 'original', $c82$1. El Senado es la Cámara de representación territorial.
   2. En cada provincia se elegirán cuatro Senadores por sufra-
gio universal, libre, igual, directo y secreto por los votantes de
cada una de ellas, en los términos que señale una ley orgánica.
   3. En las provincias insulares, cada isla o agrupación de ellas,
con Cabildo o Consejo Insular, constituirá una circunscripción
a efectos de elección de Senadores, correspondiendo tres a
cada una de las islas mayores –Gran Canaria, Mallorca y Tene-
rife– y uno a cada una de las siguientes islas o agrupaciones:
Ibiza-Formentera, Menorca, Fuerteventura, Gomera, Hierro,
Lanzarote y La Palma.
   4. Las poblaciones de Ceuta y Melilla elegirán cada una de
ellas dos Senadores.
   5. Las Comunidades Autónomas designarán además un Senador
y otro más por cada millón de habitantes de su respectivo territo-
rio. La designación corresponderá a la Asamblea legislativa o, en su
defecto, al órgano colegiado superior de la Comunidad Autónoma,
de acuerdo con lo que establezcan los Estatutos, que asegurarán,
en todo caso, la adecuada representación proporcional.
   6. El Senado es elegido por cuatro años. El mandato de los
Senadores termina cuatro años después de su elección o el día
de la disolución de la Cámara.$c82$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 70', 4, 3, md5('Artículo 70'))
    returning id into v_node_ids[83];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[83], v_user_id, 'original', $c83$1. La ley electoral determinará las causas de inelegibilidad e
incompatibilidad de los Diputados y Senadores, que compren-
derán, en todo caso:

26
     a)	A los componentes del Tribunal Constitucional.
     b)	A los altos cargos de la Administración del Estado que

         determine la ley, con la excepción de los miembros del
         Gobierno.
     c)	Al Defensor del Pueblo.
     d)	A los Magistrados, Jueces y Fiscales en activo.
     e)	A los militares profesionales y miembros de las Fuerzas
         y Cuerpos de Seguridad y Policía en activo.
     f)	A los miembros de las Juntas Electorales.

   2. La validez de las actas y credenciales de los miembros de
ambas Cámaras estará sometida al control judicial, en los tér-
minos que establezca la ley electoral.$c83$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 71', 5, 3, md5('Artículo 71'))
    returning id into v_node_ids[84];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[84], v_user_id, 'original', $c84$1. Los Diputados y Senadores gozarán de inviolabilidad por
las opiniones manifestadas en el ejercicio de sus funciones.

   2. Durante el período de su mandato los Diputados y Sena-
dores gozarán asimismo de inmunidad y sólo podrán ser de-
tenidos en caso de flagrante delito. No podrán ser inculpados
ni procesados sin la previa autorización de la Cámara respec-
tiva.

   3. En las causas contra Diputados y Senadores será compe-
tente la Sala de lo Penal del Tribunal Supremo.

   4. Los Diputados y Senadores percibirán una asignación que
será fijada por las respectivas Cámaras.$c84$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 72', 6, 3, md5('Artículo 72'))
    returning id into v_node_ids[85];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[85], v_user_id, 'original', $c85$1. Las Cámaras establecen sus propios Reglamentos, aprue-
ban autónomamente sus presupuestos y, de común acuerdo,
regulan el Estatuto del Personal de las Cortes Generales. Los
Reglamentos y su reforma serán sometidos a una votación fi-
nal sobre su totalidad, que requerirá la mayoría absoluta.

   2. Las Cámaras eligen sus respectivos Presidentes y los de-
más miembros de sus Mesas. Las sesiones conjuntas serán
presididas por el Presidente del Congreso y se regirán por un
Reglamento de las Cortes Generales aprobado por mayoría
absoluta de cada Cámara.

   3. Los Presidentes de las Cámaras ejercen en nombre de las
mismas todos los poderes administrativos y facultades de po-
licía en el interior de sus respectivas sedes.

                                                                                                     27$c85$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 73', 7, 3, md5('Artículo 73'))
    returning id into v_node_ids[86];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[86], v_user_id, 'original', $c86$1. Las Cámaras se reunirán anualmente en dos períodos or-
dinarios de sesiones: el primero, de septiembre a diciembre, y
el segundo, de febrero a junio.

   2. Las Cámaras podrán reunirse en sesiones extraordinarias
a petición del Gobierno, de la Diputación Permanente o de la
mayoría absoluta de los miembros de cualquiera de las Cáma-
ras. Las sesiones extraordinarias deberán convocarse sobre un
orden del día determinado y serán clausuradas una vez que
éste haya sido agotado.$c86$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 74', 8, 3, md5('Artículo 74'))
    returning id into v_node_ids[87];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[87], v_user_id, 'original', $c87$1. Las Cámaras se reunirán en sesión conjunta para ejercer
las competencias no legislativas que el Título II atribuye expre-
samente a las Cortes Generales.

   2. Las decisiones de las Cortes Generales previstas en los artí-
culos 94, 1, 145, 2 y 158, 2, se adoptarán por mayoría de cada una
de las Cámaras. En el primer caso, el procedimiento se iniciará
por el Congreso, y en los otros dos, por el Senado. En ambos
casos, si no hubiera acuerdo entre Senado y Congreso, se inten-
tará obtener por una Comisión Mixta compuesta de igual núme-
ro de Diputados y Senadores. La Comisión presentará un texto
que será votado por ambas Cámaras. Si no se aprueba en la forma
establecida, decidirá el Congreso por mayoría absoluta.$c87$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 75', 9, 3, md5('Artículo 75'))
    returning id into v_node_ids[88];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[88], v_user_id, 'original', $c88$1. Las Cámaras funcionarán en Pleno y por Comisiones.
   2. Las Cámaras podrán delegar en las Comisiones Legislati-
vas Permanentes la aprobación de proyectos o proposiciones
de ley. El Pleno podrá, no obstante, recabar en cualquier mo-
mento el debate y votación de cualquier proyecto o proposi-
ción de ley que haya sido objeto de esta delegación.
   3. Quedan exceptuados de lo dispuesto en el apartado an-
terior la reforma constitucional, las cuestiones internacionales,
las leyes orgánicas y de bases y los Presupuestos Generales del
Estado.$c88$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 76', 10, 3, md5('Artículo 76'))
    returning id into v_node_ids[89];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[89], v_user_id, 'original', $c89$1. El Congreso y el Senado, y, en su caso, ambas Cámaras
conjuntamente, podrán nombrar Comisiones de investigación

28
sobre cualquier asunto de interés público. Sus conclusiones no
serán vinculantes para los Tribunales, ni afectarán a las resolu-
ciones judiciales, sin perjuicio de que el resultado de la inves-
tigación sea comunicado al Ministerio Fiscal para el ejercicio,
cuando proceda, de las acciones oportunas.

   2. Será obligatorio comparecer a requerimiento de las Cá-
maras. La ley regulará las sanciones que puedan imponerse
por incumplimiento de esta obligación.$c89$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 77', 11, 3, md5('Artículo 77'))
    returning id into v_node_ids[90];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[90], v_user_id, 'original', $c90$1. Las Cámaras pueden recibir peticiones individuales y co-
lectivas, siempre por escrito, quedando prohibida la presenta-
ción directa por manifestaciones ciudadanas.

   2. Las Cámaras pueden remitir al Gobierno las peticiones
que reciban. El Gobierno está obligado a explicarse sobre su
contenido, siempre que las Cámaras lo exijan.$c90$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 78', 12, 3, md5('Artículo 78'))
    returning id into v_node_ids[91];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[91], v_user_id, 'original', $c91$1. En cada Cámara habrá una Diputación Permanente com-
puesta por un mínimo de veintiún miembros, que representa-
rán a los grupos parlamentarios, en proporción a su importan-
cia numérica.

   2. Las Diputaciones Permanentes estarán presididas por el
Presidente de la Cámara respectiva y tendrán como funciones
la prevista en el artículo 73, la de asumir las facultades que
correspondan a las Cámaras, de acuerdo con los artículos 86
y 116, en caso de que éstas hubieren sido disueltas o hubiere
expirado su mandato y la de velar por los poderes de las Cá-
maras cuando éstas no estén reunidas.

   3. Expirado el mandato o en caso de disolución, las Diputa-
ciones Permanentes seguirán ejerciendo sus funciones hasta
la constitución de las nuevas Cortes Generales.

   4. Reunida la Cámara correspondiente, la Diputación Per-
manente dará cuenta de los asuntos tratados y de sus decisio-
nes.$c91$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 79', 13, 3, md5('Artículo 79'))
    returning id into v_node_ids[92];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[92], v_user_id, 'original', $c92$1. Para adoptar acuerdos, las Cámaras deben estar reunidas
reglamentariamente y con asistencia de la mayoría de sus
miembros.

                                                                                                     29
   2. Dichos acuerdos, para ser válidos, deberán ser aprobados
por la mayoría de los miembros presentes, sin perjuicio de las
mayorías especiales que establezcan la Constitución o las le-
yes orgánicas y las que para elección de personas establezcan
los Reglamentos de las Cámaras.

   3. El voto de Senadores y Diputados es personal e indelega-
ble.$c92$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[78], 'Artículo 80', 14, 3, md5('Artículo 80'))
    returning id into v_node_ids[93];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[93], v_user_id, 'original', $c93$Las sesiones plenarias de las Cámaras serán públicas, salvo
acuerdo en contrario de cada Cámara, adoptado por mayoría
absoluta o con arreglo al Reglamento.$c93$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[77], 'CAPÍTULO SEGUNDO', 1, 2, md5('CAPÍTULO SEGUNDO'))
    returning id into v_node_ids[94];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 81', 0, 3, md5('Artículo 81'))
    returning id into v_node_ids[95];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[95], v_user_id, 'original', $c95$1. Son leyes orgánicas las relativas al desarrollo de los dere-
chos fundamentales y de las libertades públicas, las que aprue-
ben los Estatutos de Autonomía y el régimen electoral general
y las demás previstas en la Constitución.

   2. La aprobación, modificación o derogación de las leyes
orgánicas exigirá mayoría absoluta del Congreso, en una vota-
ción final sobre el conjunto del proyecto.$c95$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 82', 1, 3, md5('Artículo 82'))
    returning id into v_node_ids[96];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[96], v_user_id, 'original', $c96$1. Las Cortes Generales podrán delegar en el Gobierno la

potestad de dictar normas con rango de ley sobre materias
determinadas no incluidas en el artículo anterior.

   2. La delegación legislativa deberá otorgarse mediante una
ley de bases cuando su objeto sea la formación de textos arti-
culados o por una ley ordinaria cuando se trate de refundir
varios textos legales en uno solo.

   3. La delegación legislativa habrá de otorgarse al Gobierno de
forma expresa para materia concreta y con fijación del plazo
para su ejercicio. La delegación se agota por el uso que de ella
haga el Gobierno mediante la publicación de la norma corres-
pondiente. No podrá entenderse concedida de modo implícito
o por tiempo indeterminado. Tampoco podrá permitir la subde-
legación a autoridades distintas del propio Gobierno.

30
   4. Las leyes de bases delimitarán con precisión el objeto y
alcance de la delegación legislativa y los principios y criterios
que han de seguirse en su ejercicio.

   5. La autorización para refundir textos legales determinará el
ámbito normativo a que se refiere el contenido de la delega-
ción, especificando si se circunscribe a la mera formulación de
un texto único o si se incluye la de regularizar, aclarar y armo-
nizar los textos legales que han de ser refundidos.

   6. Sin perjuicio de la competencia propia de los Tribunales,
las leyes de delegación podrán establecer en cada caso fór-
mulas adicionales de control.$c96$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 83', 2, 3, md5('Artículo 83'))
    returning id into v_node_ids[97];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[97], v_user_id, 'original', $c97$Las leyes de bases no podrán en ningún caso:

   a) Autorizar la modificación de la propia ley de bases.
   b) Facultar para dictar normas con carácter retroactivo.$c97$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 84', 3, 3, md5('Artículo 84'))
    returning id into v_node_ids[98];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[98], v_user_id, 'original', $c98$Cuando una proposición de ley o una enmienda fuere con-
traria a una delegación legislativa en vigor, el Gobierno está
facultado para oponerse a su tramitación. En tal supuesto,
podrá presentarse una proposición de ley para la derogación
total o parcial de la ley de delegación.$c98$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 85', 4, 3, md5('Artículo 85'))
    returning id into v_node_ids[99];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[99], v_user_id, 'original', $c99$Las disposiciones del Gobierno que contengan legislación
delegada recibirán el título de Decretos Legislativos.$c99$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 86', 5, 3, md5('Artículo 86'))
    returning id into v_node_ids[100];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[100], v_user_id, 'original', $c100$1. En caso de extraordinaria y urgente necesidad, el Gobier-
no podrá dictar disposiciones legislativas provisionales que
tomarán la forma de Decretos-leyes y que no podrán afectar
al ordenamiento de las instituciones básicas del Estado, a los
derechos, deberes y libertades de los ciudadanos regulados en
el Título I, al régimen de las Comunidades Autónomas ni al
Derecho electoral general.

   2. Los Decretos-leyes deberán ser inmediatamente someti-
dos a debate y votación de totalidad al Congreso de los Dipu-
tados, convocado al efecto si no estuviere reunido, en el plazo
de los treinta días siguientes a su promulgación. El Congreso

                                                                                                     31
habrá de pronunciarse expresamente dentro de dicho plazo
sobre su convalidación o derogación, para lo cual el Regla-
mento establecerá un procedimiento especial y sumario.

   3. Durante el plazo establecido en el apartado anterior, las
Cortes podrán tramitarlos como proyectos de ley por el pro-
cedimiento de urgencia.$c100$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 87', 6, 3, md5('Artículo 87'))
    returning id into v_node_ids[101];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[101], v_user_id, 'original', $c101$1. La iniciativa legislativa corresponde al Gobierno, al Con-
greso y al Senado, de acuerdo con la Constitución y los Regla-
mentos de las Cámaras.

   2. Las Asambleas de las Comunidades Autónomas podrán
solicitar del Gobierno la adopción de un proyecto de ley o
remitir a la Mesa del Congreso una proposición de ley, dele-
gando ante dicha Cámara un máximo de tres miembros de la
Asamblea encargados de su defensa.

   3. Una ley orgánica regulará las formas de ejercicio y requi-
sitos de la iniciativa popular para la presentación de proposi-
ciones de ley. En todo caso se exigirán no menos de 500.000
firmas acreditadas. No procederá dicha iniciativa en materias
propias de ley orgánica, tributarias o de carácter internacional,
ni en lo relativo a la prerrogativa de gracia.$c101$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 88', 7, 3, md5('Artículo 88'))
    returning id into v_node_ids[102];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[102], v_user_id, 'original', $c102$Los proyectos de ley serán aprobados en Consejo de Minis-
tros, que los someterá al Congreso, acompañados de una ex-
posición de motivos y de los antecedentes necesarios para
pronunciarse sobre ellos.$c102$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 89', 8, 3, md5('Artículo 89'))
    returning id into v_node_ids[103];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[103], v_user_id, 'original', $c103$1. La tramitación de las proposiciones de ley se regulará por
los Reglamentos de las Cámaras, sin que la prioridad debida a
los proyectos de ley impida el ejercicio de la iniciativa legisla-
tiva en los términos regulados por el artículo 87.

   2. Las proposiciones de ley que, de acuerdo con el artículo
87, tome en consideración el Senado, se remitirán al Congreso
para su trámite en éste como tal proposición.$c103$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 90', 9, 3, md5('Artículo 90'))
    returning id into v_node_ids[104];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[104], v_user_id, 'original', $c104$1. Aprobado un proyecto de ley ordinaria u orgánica por el
Congreso de los Diputados, su Presidente dará inmediata

32
cuenta del mismo al Presidente del Senado, el cual lo somete-
rá a la deliberación de éste.

   2. El Senado en el plazo de dos meses, a partir del día de la
recepción del texto, puede, mediante mensaje motivado, opo-
ner su veto o introducir enmiendas al mismo. El veto deberá
ser aprobado por mayoría absoluta. El proyecto no podrá ser
sometido al Rey para sanción sin que el Congreso ratifique por
mayoría absoluta, en caso de veto, el texto inicial, o por ma-
yoría simple, una vez transcurridos dos meses desde la inter-
posición del mismo, o se pronuncie sobre las enmiendas,
aceptándolas o no por mayoría simple.

   3. El plazo de dos meses de que el Senado dispone para
vetar o enmendar el proyecto se reducirá al de veinte días na-
turales en los proyectos declarados urgentes por el Gobierno
o por el Congreso de los Diputados.$c104$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 91', 10, 3, md5('Artículo 91'))
    returning id into v_node_ids[105];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[105], v_user_id, 'original', $c105$El Rey sancionará en el plazo de quince días las leyes apro-
badas por las Cortes Generales, y las promulgará y ordenará su
inmediata publicación.$c105$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[94], 'Artículo 92', 11, 3, md5('Artículo 92'))
    returning id into v_node_ids[106];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[106], v_user_id, 'original', $c106$1. Las decisiones políticas de especial trascendencia podrán
ser sometidas a referéndum consultivo de todos los ciudada-
nos.

   2. El referéndum será convocado por el Rey, mediante pro-
puesta del Presidente del Gobierno, previamente autorizada
por el Congreso de los Diputados.

   3. Una ley orgánica regulará las condiciones y el procedi-
miento de las distintas modalidades de referéndum previstas
en esta Constitución.$c106$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[77], 'CAPÍTULO TERCERO', 2, 2, md5('CAPÍTULO TERCERO'))
    returning id into v_node_ids[107];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[107], 'Artículo 93', 0, 3, md5('Artículo 93'))
    returning id into v_node_ids[108];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[108], v_user_id, 'original', $c108$Mediante ley orgánica se podrá autorizar la celebración de
tratados por los que se atribuya a una organización o institu-
ción internacional el ejercicio de competencias derivadas de la
Constitución. Corresponde a las Cortes Generales o al Gobier-

                                                                                                     33
no, según los casos, la garantía del cumplimiento de estos
tratados y de las resoluciones emanadas de los organismos
internacionales o supranacionales titulares de la cesión.$c108$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[107], 'Artículo 94', 1, 3, md5('Artículo 94'))
    returning id into v_node_ids[109];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[109], v_user_id, 'original', $c109$1. La prestación del consentimiento del Estado para obligar-
se por medio de tratados o convenios requerirá la previa auto-
rización de las Cortes Generales, en los siguientes casos:

     a)	Tratados de carácter político.
     b)	T ratados o convenios de carácter militar.
     c)	T ratados o convenios que afecten a la integridad terri-

         torial del Estado o a los derechos y deberes fundamen-
         tales establecidos en el Título I.
     d)	T ratados o convenios que impliquen obligaciones fi-
         nancieras para la Hacienda Pública.
     e)	T ratados o convenios que supongan modificación o
         derogación de alguna ley o exijan medidas legislativas
         para su ejecución.

   2. El Congreso y el Senado serán inmediatamente informa-
dos de la conclusión de los restantes tratados o convenios.$c109$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[107], 'Artículo 95', 2, 3, md5('Artículo 95'))
    returning id into v_node_ids[110];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[110], v_user_id, 'original', $c110$1. La celebración de un tratado internacional que contenga
estipulaciones contrarias a la Constitución exigirá la previa re-
visión constitucional.

   2. El Gobierno o cualquiera de las Cámaras puede requerir
al Tribunal Constitucional para que declare si existe o no esa
contradicción.$c110$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[107], 'Artículo 96', 3, 3, md5('Artículo 96'))
    returning id into v_node_ids[111];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[111], v_user_id, 'original', $c111$1. Los tratados internacionales válidamente celebrados, una
vez publicados oficialmente en España, formarán parte del or-
denamiento interno. Sus disposiciones sólo podrán ser dero-
gadas, modificadas o suspendidas en la forma prevista en los
propios tratados o de acuerdo con las normas generales del
Derecho internacional.

   2. Para la denuncia de los tratados y convenios internacio-
nales se utilizará el mismo procedimiento previsto para su
aprobación en el artículo 94.

34$c111$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO IV', 5, 1, md5('TÍTULO IV'))
    returning id into v_node_ids[112];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 97', 0, 2, md5('Artículo 97'))
    returning id into v_node_ids[113];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[113], v_user_id, 'original', $c113$El Gobierno dirige la política interior y exterior, la Adminis-
tración civil y militar y la defensa del Estado. Ejerce la función
ejecutiva y la potestad reglamentaria de acuerdo con la Cons-
titución y las leyes.$c113$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 98', 1, 2, md5('Artículo 98'))
    returning id into v_node_ids[114];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[114], v_user_id, 'original', $c114$1. El Gobierno se compone del Presidente, de los Vicepresi-
dentes, en su caso, de los Ministros y de los demás miembros
que establezca la ley.

   2. El Presidente dirige la acción del Gobierno y coordina las
funciones de los demás miembros del mismo, sin perjuicio de la
competencia y responsabilidad directa de éstos en su gestión.

   3. Los miembros del Gobierno no podrán ejercer otras fun-
ciones representativas que las propias del mandato parlamen-
tario, ni cualquier otra función pública que no derive de su
cargo, ni actividad profesional o mercantil alguna.

   4. La ley regulará el estatuto e incompatibilidades de los
miembros del Gobierno.$c114$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 99', 2, 2, md5('Artículo 99'))
    returning id into v_node_ids[115];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[115], v_user_id, 'original', $c115$1. Después de cada renovación del Congreso de los Diputa-
dos, y en los demás supuestos constitucionales en que así
proceda, el Rey, previa consulta con los representantes desig-
nados por los Grupos políticos con representación parlamen-
taria, y a través del Presidente del Congreso, propondrá un
candidato a la Presidencia del Gobierno.

   2. El candidato propuesto conforme a lo previsto en el apar-
tado anterior expondrá ante el Congreso de los Diputados el
programa político del Gobierno que pretenda formar y solici-
tará la confianza de la Cámara.

   3. Si el Congreso de los Diputados, por el voto de la mayoría
absoluta de sus miembros, otorgare su confianza a dicho can-
didato, el Rey le nombrará Presidente. De no alcanzarse dicha
mayoría, se someterá la misma propuesta a nueva votación
cuarenta y ocho horas después de la anterior, y la confianza se
entenderá otorgada si obtuviere la mayoría simple.

                                                                                                     35
   4. Si efectuadas las citadas votaciones no se otorgase la
confianza para la investidura, se tramitarán sucesivas propues-
tas en la forma prevista en los apartados anteriores.

   5. Si transcurrido el plazo de dos meses, a partir de la prime-
ra votación de investidura, ningún candidato hubiere obtenido
la confianza del Congreso, el Rey disolverá ambas Cámaras y
convocará nuevas elecciones con el refrendo del Presidente
del Congreso.$c115$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 100', 3, 2, md5('Artículo 100'))
    returning id into v_node_ids[116];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[116], v_user_id, 'original', $c116$Los demás miembros del Gobierno serán nombrados y se-
parados por el Rey, a propuesta de su Presidente.$c116$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 101', 4, 2, md5('Artículo 101'))
    returning id into v_node_ids[117];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[117], v_user_id, 'original', $c117$1. El Gobierno cesa tras la celebración de elecciones gene-
rales, en los casos de pérdida de la confianza parlamentaria
previstos en la Constitución, o por dimisión o fallecimiento de
su Presidente.

   2. El Gobierno cesante continuará en funciones hasta la
toma de posesión del nuevo Gobierno.$c117$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 102', 5, 2, md5('Artículo 102'))
    returning id into v_node_ids[118];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[118], v_user_id, 'original', $c118$1. La responsabilidad criminal del Presidente y los demás
miembros del Gobierno será exigible, en su caso, ante la Sala
de lo Penal del Tribunal Supremo.

   2. Si la acusación fuere por traición o por cualquier delito
contra la seguridad del Estado en el ejercicio de sus funciones,
sólo podrá ser planteada por iniciativa de la cuarta parte de los
miembros del Congreso, y con la aprobación de la mayoría
absoluta del mismo.

   3. La prerrogativa real de gracia no será aplicable a ninguno
de los supuestos del presente artículo.$c118$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 103', 6, 2, md5('Artículo 103'))
    returning id into v_node_ids[119];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[119], v_user_id, 'original', $c119$1. La Administración Pública sirve con objetividad los intere-
ses generales y actúa de acuerdo con los principios de eficacia,
jerarquía, descentralización, desconcentración y coordinación,
con sometimiento pleno a la ley y al Derecho.

   2. Los órganos de la Administración del Estado son creados,
regidos y coordinados de acuerdo con la ley.

36
   3. La ley regulará el estatuto de los funcionarios públicos,
el acceso a la función pública de acuerdo con los principios
de mérito y capacidad, las peculiaridades del ejercicio de su
derecho a sindicación, el sistema de incompatibilidades y
las garantías para la imparcialidad en el ejercicio de sus fun-
ciones.$c119$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 104', 7, 2, md5('Artículo 104'))
    returning id into v_node_ids[120];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[120], v_user_id, 'original', $c120$1. Las Fuerzas y Cuerpos de seguridad, bajo la dependencia
del Gobierno, tendrán como misión proteger el libre ejercicio
de los derechos y libertades y garantizar la seguridad ciudadana.

   2. Una ley orgánica determinará las funciones, principios
básicos de actuación y estatutos de las Fuerzas y Cuerpos de
seguridad.$c120$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 105', 8, 2, md5('Artículo 105'))
    returning id into v_node_ids[121];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[121], v_user_id, 'original', $c121$La ley regulará:

   a) La audiencia de los ciudadanos, directamente o a través
      de las organizaciones y asociaciones reconocidas por la
      ley, en el procedimiento de elaboración de las disposicio-
      nes administrativas que les afecten.

   b) El acceso de los ciudadanos a los archivos y registros ad-
      ministrativos, salvo en lo que afecte a la seguridad y de-
      fensa del Estado, la averiguación de los delitos y la intimi-
      dad de las personas.

   c) El procedimiento a través del cual deben producirse los
      actos administrativos, garantizando, cuando proceda, la
      audiencia del interesado.$c121$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 106', 9, 2, md5('Artículo 106'))
    returning id into v_node_ids[122];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[122], v_user_id, 'original', $c122$1. Los Tribunales controlan la potestad reglamentaria y la
legalidad de la actuación administrativa, así como el someti-
miento de ésta a los fines que la justifican.

   2. Los particulares, en los términos establecidos por la ley,
tendrán derecho a ser indemnizados por toda lesión que su-
fran en cualquiera de sus bienes y derechos, salvo en los casos
de fuerza mayor, siempre que la lesión sea consecuencia del
funcionamiento de los servicios públicos.

                                                                                                     37$c122$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[112], 'Artículo 107', 10, 2, md5('Artículo 107'))
    returning id into v_node_ids[123];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[123], v_user_id, 'original', $c123$El Consejo de Estado es el supremo órgano consultivo del

Gobierno. Una ley orgánica regulará su composición y com-
petencia.$c123$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO V', 6, 1, md5('TÍTULO V'))
    returning id into v_node_ids[124];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[124], 'Artículo 108', 0, 2, md5('Artículo 108'))
    returning id into v_node_ids[125];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[125], v_user_id, 'original', $c125$El Gobierno responde solidariamente en su gestión política

ante el Congreso de los Diputados.$c125$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[124], 'Artículo 109', 1, 2, md5('Artículo 109'))
    returning id into v_node_ids[126];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[126], v_user_id, 'original', $c126$Las Cámaras y sus Comisiones podrán recabar, a través de

los Presidentes de aquéllas, la información y ayuda que preci-
sen del Gobierno y de sus Departamentos y de cualesquiera
autoridades del Estado y de las Comunidades Autónomas.$c126$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[124], 'Artículo 110', 2, 2, md5('Artículo 110'))
    returning id into v_node_ids[127];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[127], v_user_id, 'original', $c127$1. Las Cámaras y sus Comisiones pueden reclamar la pre-

sencia de los miembros del Gobierno.
   2. Los miembros del Gobierno tienen acceso a las sesiones

de las Cámaras y a sus Comisiones y la facultad de hacerse oír
en ellas, y podrán solicitar que informen ante las mismas fun-
cionarios de sus Departamentos.$c127$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[124], 'Artículo 111', 3, 2, md5('Artículo 111'))
    returning id into v_node_ids[128];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[128], v_user_id, 'original', $c128$1. El Gobierno y cada uno de sus miembros están sometidos

a las interpelaciones y preguntas que se le formulen en las
Cámaras. Para esta clase de debate los Reglamentos estable-
cerán un tiempo mínimo semanal.

   2. Toda interpelación podrá dar lugar a una moción en la
que la Cámara manifieste su posición.$c128$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[124], 'Artículo 112', 4, 2, md5('Artículo 112'))
    returning id into v_node_ids[129];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[129], v_user_id, 'original', $c129$El Presidente del Gobierno, previa deliberación del Consejo

de Ministros, puede plantear ante el Congreso de los Diputa-
dos la cuestión de confianza sobre su programa o sobre una
declaración de política general. La confianza se entenderá

38
otorgada cuando vote a favor de la misma la mayoría simple
de los Diputados.$c129$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[124], 'Artículo 113', 5, 2, md5('Artículo 113'))
    returning id into v_node_ids[130];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[130], v_user_id, 'original', $c130$1. El Congreso de los Diputados puede exigir la responsabi-
lidad política del Gobierno mediante la adopción por mayoría
absoluta de la moción de censura.

   2. La moción de censura deberá ser propuesta al menos por
la décima parte de los Diputados, y habrá de incluir un candi-
dato a la Presidencia del Gobierno.

   3. La moción de censura no podrá ser votada hasta que
transcurran cinco días desde su presentación. En los dos pri-
meros días de dicho plazo podrán presentarse mociones alter-
nativas.

   4. Si la moción de censura no fuere aprobada por el Con-
greso, sus signatarios no podrán presentar otra durante el mis-
mo período de sesiones.$c130$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[124], 'Artículo 114', 6, 2, md5('Artículo 114'))
    returning id into v_node_ids[131];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[131], v_user_id, 'original', $c131$1. Si el Congreso niega su confianza al Gobierno, éste pre-
sentará su dimisión al Rey, procediéndose a continuación a la
designación de Presidente del Gobierno, según lo dispuesto en
el artículo 99.

   2. Si el Congreso adopta una moción de censura, el Gobier-
no presentará su dimisión al Rey y el candidato incluido en
aquélla se entenderá investido de la confianza de la Cámara a
los efectos previstos en el artículo 99. El Rey le nombrará Pre-
sidente del Gobierno.$c131$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[124], 'Artículo 115', 7, 2, md5('Artículo 115'))
    returning id into v_node_ids[132];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[132], v_user_id, 'original', $c132$1. El Presidente del Gobierno, previa deliberación del Con-
sejo de Ministros, y bajo su exclusiva responsabilidad, podrá
proponer la disolución del Congreso, del Senado o de las Cor-
tes Generales, que será decretada por el Rey. El decreto de
disolución fijará la fecha de las elecciones.

   2. La propuesta de disolución no podrá presentarse cuando
esté en trámite una moción de censura.

   3. No procederá nueva disolución antes de que transcurra
un año desde la anterior, salvo lo dispuesto en el artículo 99,
apartado 5.

                                                                                                     39$c132$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[124], 'Artículo 116', 8, 2, md5('Artículo 116'))
    returning id into v_node_ids[133];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[133], v_user_id, 'original', $c133$1. Una ley orgánica regulará los estados de alarma, de ex-
cepción y de sitio, y las competencias y limitaciones corres-
pondientes.

   2. El estado de alarma será declarado por el Gobierno me-
diante decreto acordado en Consejo de Ministros por un plazo
máximo de quince días, dando cuenta al Congreso de los Di-
putados, reunido inmediatamente al efecto y sin cuya autori-
zación no podrá ser prorrogado dicho plazo. El decreto deter-
minará el ámbito territorial a que se extienden los efectos de
la declaración.

   3. El estado de excepción será declarado por el Gobierno
mediante decreto acordado en Consejo de Ministros, previa
autorización del Congreso de los Diputados. La autorización y
proclamación del estado de excepción deberá determinar ex-
presamente los efectos del mismo, el ámbito territorial a que
se extiende y su duración, que no podrá exceder de treinta
días, prorrogables por otro plazo igual, con los mismos requi-
sitos.

   4. El estado de sitio será declarado por la mayoría absoluta
del Congreso de los Diputados, a propuesta exclusiva del Go-
bierno. El Congreso determinará su ámbito territorial, duración
y condiciones.

   5. No podrá procederse a la disolución del Congreso mien-
tras estén declarados algunos de los estados comprendidos en
el presente artículo, quedando automáticamente convocadas
las Cámaras si no estuvieren en período de sesiones. Su fun-
cionamiento, así como el de los demás poderes constitucio-
nales del Estado, no podrán interrumpirse durante la vigencia
de estos estados.

   Disuelto el Congreso o expirado su mandato, si se produje-
re alguna de las situaciones que dan lugar a cualquiera de di-
chos estados, las competencias del Congreso serán asumidas
por su Diputación Permanente.

   6. La declaración de los estados de alarma, de excepción y
de sitio no modificarán el principio de responsabilidad del Go-
bierno y de sus agentes reconocidos en la Constitución y en
las leyes.

40$c133$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO VI', 7, 1, md5('TÍTULO VI'))
    returning id into v_node_ids[134];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 117', 0, 2, md5('Artículo 117'))
    returning id into v_node_ids[135];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[135], v_user_id, 'original', $c135$1. La justicia emana del pueblo y se administra en nombre
del Rey por Jueces y Magistrados integrantes del poder judi-
cial, independientes, inamovibles, responsables y sometidos
únicamente al imperio de la ley.

   2. Los Jueces y Magistrados no podrán ser separados, sus-
pendidos, trasladados ni jubilados, sino por alguna de las cau-
sas y con las garantías previstas en la ley.

   3. El ejercicio de la potestad jurisdiccional en todo tipo de
procesos, juzgando y haciendo ejecutar lo juzgado, corres-
ponde exclusivamente a los Juzgados y Tribunales determina-
dos por las leyes, según las normas de competencia y proce-
dimiento que las mismas establezcan.

   4. Los Juzgados y Tribunales no ejercerán más funciones que
las señaladas en el apartado anterior y las que expresamente les
sean atribuidas por ley en garantía de cualquier derecho.

   5. El principio de unidad jurisdiccional es la base de la orga-
nización y funcionamiento de los Tribunales. La ley regulará el
ejercicio de la jurisdicción militar en el ámbito estrictamente
castrense y en los supuestos de estado de sitio, de acuerdo
con los principios de la Constitución.

   6. Se prohíben los Tribunales de excepción.$c135$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 118', 1, 2, md5('Artículo 118'))
    returning id into v_node_ids[136];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[136], v_user_id, 'original', $c136$Es obligado cumplir las sentencias y demás resoluciones
firmes de los Jueces y Tribunales, así como prestar la colabo-
ración requerida por éstos en el curso del proceso y en la eje-
cución de lo resuelto.$c136$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 119', 2, 2, md5('Artículo 119'))
    returning id into v_node_ids[137];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[137], v_user_id, 'original', $c137$La justicia será gratuita cuando así lo disponga la ley y, en
todo caso, respecto de quienes acrediten insuficiencia de re-
cursos para litigar.$c137$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 120', 3, 2, md5('Artículo 120'))
    returning id into v_node_ids[138];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[138], v_user_id, 'original', $c138$1. Las actuaciones judiciales serán públicas, con las excep-
ciones que prevean las leyes de procedimiento.

                                                                                                     41
   2. El procedimiento será predominantemente oral, sobre
todo en materia criminal.

   3. Las sentencias serán siempre motivadas y se pronunciarán
en audiencia pública.$c138$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 121', 4, 2, md5('Artículo 121'))
    returning id into v_node_ids[139];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[139], v_user_id, 'original', $c139$Los daños causados por error judicial, así como los que sean
consecuencia del funcionamiento anormal de la Administra-
ción de Justicia, darán derecho a una indemnización a cargo
del Estado, conforme a la ley.$c139$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 122', 5, 2, md5('Artículo 122'))
    returning id into v_node_ids[140];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[140], v_user_id, 'original', $c140$1. La ley orgánica del poder judicial determinará la constitu-
ción, funcionamiento y gobierno de los Juzgados y Tribunales,
así como el estatuto jurídico de los Jueces y Magistrados de
carrera, que formarán un Cuerpo único, y del personal al ser-
vicio de la Administración de Justicia.

   2. El Consejo General del Poder Judicial es el órgano de go-
bierno del mismo. La ley orgánica establecerá su estatuto y el
régimen de incompatibilidades de sus miembros y sus funcio-
nes, en particular en materia de nombramientos, ascensos,
inspección y régimen disciplinario.

   3. El Consejo General del Poder Judicial estará integrado
por el Presidente del Tribunal Supremo, que lo presidirá, y por
veinte miembros nombrados por el Rey por un período de cin-
co años. De éstos, doce entre Jueces y Magistrados de todas
las categorías judiciales, en los términos que establezca la ley
orgánica; cuatro a propuesta del Congreso de los Diputados, y
cuatro a propuesta del Senado, elegidos en ambos casos por
mayoría de tres quintos de sus miembros, entre abogados y
otros juristas, todos ellos de reconocida competencia y con
más de quince años de ejercicio en su profesión.$c140$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 123', 6, 2, md5('Artículo 123'))
    returning id into v_node_ids[141];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[141], v_user_id, 'original', $c141$1. El Tribunal Supremo, con jurisdicción en toda España, es
el órgano jurisdiccional superior en todos los órdenes, salvo lo
dispuesto en materia de garantías constitucionales.

   2. El Presidente del Tribunal Supremo será nombrado por el
Rey, a propuesta del Consejo General del Poder Judicial, en la
forma que determine la ley.

42$c141$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 124', 7, 2, md5('Artículo 124'))
    returning id into v_node_ids[142];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[142], v_user_id, 'original', $c142$1. El Ministerio Fiscal, sin perjuicio de las funciones enco-
mendadas a otros órganos, tiene por misión promover la ac-
ción de la justicia en defensa de la legalidad, de los derechos
de los ciudadanos y del interés público tutelado por la ley, de
oficio o a petición de los interesados, así como velar por la
independencia de los Tribunales y procurar ante éstos la satis-
facción del interés social.

   2. El Ministerio Fiscal ejerce sus funciones por medio de ór-
ganos propios conforme a los principios de unidad de actua-
ción y dependencia jerárquica y con sujeción, en todo caso, a
los de legalidad e imparcialidad.

   3. La ley regulará el estatuto orgánico del Ministerio Fiscal.
   4. El Fiscal General del Estado será nombrado por el Rey, a
propuesta del Gobierno, oído el Consejo General del Poder
Judicial.$c142$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 125', 8, 2, md5('Artículo 125'))
    returning id into v_node_ids[143];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[143], v_user_id, 'original', $c143$Los ciudadanos podrán ejercer la acción popular y participar
en la Administración de Justicia mediante la institución del
Jurado, en la forma y con respecto a aquellos procesos pena-
les que la ley determine, así como en los Tribunales consuetu-
dinarios y tradicionales.$c143$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 126', 9, 2, md5('Artículo 126'))
    returning id into v_node_ids[144];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[144], v_user_id, 'original', $c144$La policía judicial depende de los Jueces, de los Tribunales y
del Ministerio Fiscal en sus funciones de averiguación del de-
lito y descubrimiento y aseguramiento del delincuente, en los
términos que la ley establezca.$c144$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[134], 'Artículo 127', 10, 2, md5('Artículo 127'))
    returning id into v_node_ids[145];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[145], v_user_id, 'original', $c145$1. Los Jueces y Magistrados así como los Fiscales, mientras
se hallen en activo, no podrán desempeñar otros cargos públi-
cos, ni pertenecer a partidos políticos o sindicatos. La ley es-
tablecerá el sistema y modalidades de asociación profesional
de los Jueces, Magistrados y Fiscales.

   2. La ley establecerá el régimen de incompatibilidades de los
miembros del poder judicial, que deberá asegurar la total inde-
pendencia de los mismos.

                                                                                                     43$c145$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO VII', 8, 1, md5('TÍTULO VII'))
    returning id into v_node_ids[146];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[146], 'Artículo 128', 0, 2, md5('Artículo 128'))
    returning id into v_node_ids[147];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[147], v_user_id, 'original', $c147$1. Toda la riqueza del país en sus distintas formas y sea cual
fuere su titularidad está subordinada al interés general.

   2. Se reconoce la iniciativa pública en la actividad económi-
ca. Mediante ley se podrá reservar al sector público recursos o
servicios esenciales, especialmente en caso de monopolio y
asimismo acordar la intervención de empresas cuando así lo
exigiere el interés general.$c147$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[146], 'Artículo 129', 1, 2, md5('Artículo 129'))
    returning id into v_node_ids[148];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[148], v_user_id, 'original', $c148$1. La ley establecerá las formas de participación de los inte-
resados en la Seguridad Social y en la actividad de los organis-
mos públicos cuya función afecte directamente a la calidad de
la vida o al bienestar general.

   2. Los poderes públicos promoverán eficazmente las diver-
sas formas de participación en la empresa y fomentarán, me-
diante una legislación adecuada, las sociedades cooperativas.
También establecerán los medios que faciliten el acceso de los
trabajadores a la propiedad de los medios de producción.$c148$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[146], 'Artículo 130', 2, 2, md5('Artículo 130'))
    returning id into v_node_ids[149];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[149], v_user_id, 'original', $c149$1. Los poderes públicos atenderán a la modernización y de-
sarrollo de todos los sectores económicos y, en particular, de
la agricultura, de la ganadería, de la pesca y de la artesanía, a
fin de equiparar el nivel de vida de todos los españoles.

   2. Con el mismo fin, se dispensará un tratamiento especial a
las zonas de montaña.$c149$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[146], 'Artículo 131', 3, 2, md5('Artículo 131'))
    returning id into v_node_ids[150];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[150], v_user_id, 'original', $c150$1. El Estado, mediante ley, podrá planificar la actividad econó-
mica general para atender a las necesidades colectivas, equilibrar
y armonizar el desarrollo regional y sectorial y estimular el creci-
miento de la renta y de la riqueza y su más justa distribución.

   2. El Gobierno elaborará los proyectos de planificación, de
acuerdo con las previsiones que le sean suministradas por las
Comunidades Autónomas y el asesoramiento y colaboración
de los sindicatos y otras organizaciones profesionales, empre-

44
sariales y económicas. A tal fin se constituirá un Consejo, cuya
composición y funciones se desarrollarán por ley.$c150$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[146], 'Artículo 132', 4, 2, md5('Artículo 132'))
    returning id into v_node_ids[151];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[151], v_user_id, 'original', $c151$1. La ley regulará el régimen jurídico de los bienes de domi-
nio público y de los comunales, inspirándose en los principios
de inalienabilidad, imprescriptibilidad e inembargabilidad, así
como su desafectación.

   2. Son bienes de dominio público estatal los que determine
la ley y, en todo caso, la zona marítimo-terrestre, las playas, el
mar territorial y los recursos naturales de la zona económica y
la plataforma continental.

   3. Por ley se regularán el Patrimonio del Estado y el Patrimo-
nio Nacional, su administración, defensa y conservación.$c151$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[146], 'Artículo 133', 5, 2, md5('Artículo 133'))
    returning id into v_node_ids[152];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[152], v_user_id, 'original', $c152$1. La potestad originaria para establecer los tributos corres-
ponde exclusivamente al Estado, mediante ley.

   2. Las Comunidades Autónomas y las Corporaciones locales
podrán establecer y exigir tributos, de acuerdo con la Consti-
tución y las leyes.

   3. Todo beneficio fiscal que afecte a los tributos del Estado
deberá establecerse en virtud de ley.

   4. Las administraciones públicas sólo podrán contraer obli-
gaciones financieras y realizar gastos de acuerdo con las leyes.$c152$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[146], 'Artículo 134', 6, 2, md5('Artículo 134'))
    returning id into v_node_ids[153];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[153], v_user_id, 'original', $c153$1. Corresponde al Gobierno la elaboración de los Presu-
puestos Generales del Estado y a las Cortes Generales, su exa-
men, enmienda y aprobación.

   2. Los Presupuestos Generales del Estado tendrán carácter
anual, incluirán la totalidad de los gastos e ingresos del sector
público estatal y en ellos se consignará el importe de los be-
neficios fiscales que afecten a los tributos del Estado.

   3. El Gobierno deberá presentar ante el Congreso de los Di-
putados los Presupuestos Generales del Estado al menos tres
meses antes de la expiración de los del año anterior.

   4. Si la Ley de Presupuestos no se aprobara antes del primer
día del ejercicio económico correspondiente, se considerarán
automáticamente prorrogados los Presupuestos del ejercicio
anterior hasta la aprobación de los nuevos.

                                                                                                     45
   5. Aprobados los Presupuestos Generales del Estado, el Go-
bierno podrá presentar proyectos de ley que impliquen au-
mento del gasto público o disminución de los ingresos corres-
pondientes al mismo ejercicio presupuestario.

   6. Toda proposición o enmienda que suponga aumento de
los créditos o disminución de los ingresos presupuestarios re-
querirá la conformidad del Gobierno para su tramitación.

   7. La Ley de Presupuestos no puede crear tributos. Podrá
modificarlos cuando una ley tributaria sustantiva así lo prevea.$c153$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[146], 'Artículo 135', 7, 2, md5('Artículo 135'))
    returning id into v_node_ids[154];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[154], v_user_id, 'original', $c154$1. Todas las Administraciones Públicas adecuarán sus actua-
ciones al principio de estabilidad presupuestaria.

   2. El Estado y las Comunidades Autónomas no podrán incu-
rrir en un déficit estructural que supere los márgenes estable-
cidos, en su caso, por la Unión Europea para sus Estados
Miembros.

   Una ley orgánica fijará el déficit estructural máximo permiti-
do al Estado y a las Comunidades Autónomas, en relación con
su producto interior bruto. Las Entidades Locales deberán pre-
sentar equilibrio presupuestario.

   3. El Estado y las Comunidades Autónomas habrán de estar
autorizados por ley para emitir deuda pública o contraer cré-
dito.

   Los créditos para satisfacer los intereses y el capital de la
deuda pública de las Administraciones se entenderán siempre
incluidos en el estado de gastos de sus presupuestos y su pago
gozará de prioridad absoluta. Estos créditos no podrán ser ob-
jeto de enmienda o modificación, mientras se ajusten a las
condiciones de la ley de emisión.

   El volumen de deuda pública del conjunto de las Adminis-
traciones Públicas en relación con el producto interior bruto
del Estado no podrá superar el valor de referencia establecido
en el Tratado de Funcionamiento de la Unión Europea.

   4. Los límites de déficit estructural y de volumen de deuda
pública sólo podrán superarse en caso de catástrofes natura-
les, recesión económica o situaciones de emergencia extraor-
dinaria que escapen al control del Estado y perjudiquen consi-
derablemente la situación financiera o la sostenibilidad
económica o social del Estado, apreciadas por la mayoría ab-
soluta de los miembros del Congreso de los Diputados.

46
   5. Una ley orgánica desarrollará los principios a que se refie-
re este artículo, así como la participación, en los procedimien-
tos respectivos, de los órganos de coordinación institucional
entre las Administraciones Públicas en materia de política fiscal
y financiera. En todo caso, regulará:

     a)	La distribución de los límites de déficit y de deuda entre
         las distintas Administraciones Públicas, los supuestos
         excepcionales de superación de los mismos y la forma
         y plazo de corrección de las desviaciones que sobre
         uno y otro pudieran producirse.

     b)	L a metodología y el procedimiento para el cálculo del
         déficit estructural.

     c)	L a responsabilidad de cada Administración Pública en
         caso de incumplimiento de los objetivos de estabilidad
         presupuestaria.

   6. Las Comunidades Autónomas, de acuerdo con sus res-
pectivos Estatutos y dentro de los límites a que se refiere este
artículo, adoptarán las disposiciones que procedan para la
aplicación efectiva del principio de estabilidad en sus normas
y decisiones presupuestarias.$c154$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[146], 'Artículo 136', 8, 2, md5('Artículo 136'))
    returning id into v_node_ids[155];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[155], v_user_id, 'original', $c155$1. El Tribunal de Cuentas es el supremo órgano fiscalizador
de las cuentas y de la gestión económica de Estado, así como
del sector público.

   Dependerá directamente de las Cortes Generales y ejercerá
sus funciones por delegación de ellas en el examen y compro-
bación de la Cuenta General del Estado.

   2. Las cuentas del Estado y del sector público estatal se ren-
dirán al Tribunal de Cuentas y serán censuradas por éste.

   El Tribunal de Cuentas, sin perjuicio de su propia jurisdic-
ción, remitirá a las Cortes Generales un informe anual en el
que, cuando proceda, comunicará las infracciones o respon-
sabilidades en que, a su juicio, se hubiere incurrido.

   3. Los miembros del Tribunal de Cuentas gozarán de la mis-
ma independencia e inamovilidad y estarán sometidos a las
mismas incompatibilidades que los Jueces.

   4. Una ley orgánica regulará la composición, organización y
funciones del Tribunal de Cuentas.

                                                                                                     47$c155$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO VIII', 9, 1, md5('TÍTULO VIII'))
    returning id into v_node_ids[156];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[156], 'CAPÍTULO PRIMERO', 0, 2, md5('CAPÍTULO PRIMERO'))
    returning id into v_node_ids[157];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[157], 'Artículo 137', 0, 3, md5('Artículo 137'))
    returning id into v_node_ids[158];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[158], v_user_id, 'original', $c158$El Estado se organiza territorialmente en municipios, en pro-

vincias y en las Comunidades Autónomas que se constituyan.
Todas estas entidades gozan de autonomía para la gestión de
sus respectivos intereses.$c158$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[157], 'Artículo 138', 1, 3, md5('Artículo 138'))
    returning id into v_node_ids[159];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[159], v_user_id, 'original', $c159$1. El Estado garantiza la realización efectiva del principio de

solidaridad consagrado en el artículo 2 de la Constitución,
velando por el establecimiento de un equilibrio económico,
adecuado y justo entre las diversas partes del territorio espa-
ñol, y atendiendo en particular a las circunstancias del hecho
insular.

   2. Las diferencias entre los Estatutos de las distintas Comu-
nidades Autónomas no podrán implicar, en ningún caso, privi-
legios económicos o sociales.$c159$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[157], 'Artículo 139', 2, 3, md5('Artículo 139'))
    returning id into v_node_ids[160];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[160], v_user_id, 'original', $c160$1. Todos los españoles tienen los mismos derechos y obliga-

ciones en cualquier parte del territorio del Estado.
   2. Ninguna autoridad podrá adoptar medidas que directa o

indirectamente obstaculicen la libertad de circulación y esta-
blecimiento de las personas y la libre circulación de bienes en
todo el territorio español.$c160$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[156], 'CAPÍTULO SEGUNDO', 1, 2, md5('CAPÍTULO SEGUNDO'))
    returning id into v_node_ids[161];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[161], 'Artículo 140', 0, 3, md5('Artículo 140'))
    returning id into v_node_ids[162];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[162], v_user_id, 'original', $c162$La Constitución garantiza la autonomía de los municipios.

Estos gozarán de personalidad jurídica plena. Su gobierno y
administración corresponde a sus respectivos Ayuntamientos,

48
integrados por los Alcaldes y los Concejales. Los Concejales
serán elegidos por los vecinos del municipio mediante sufragio
universal, igual, libre, directo y secreto, en la forma establecida
por la ley. Los Alcaldes serán elegidos por los Concejales o por
los vecinos. La ley regulará las condiciones en las que proceda
el régimen del concejo abierto.$c162$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[161], 'Artículo 141', 1, 3, md5('Artículo 141'))
    returning id into v_node_ids[163];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[163], v_user_id, 'original', $c163$1. La provincia es una entidad local con personalidad jurídica
propia, determinada por la agrupación de municipios y división
territorial para el cumplimiento de las actividades del Estado.
Cualquier alteración de los límites provinciales habrá de ser
aprobada por las Cortes Generales mediante ley orgánica.

   2. El gobierno y la administración autónoma de las provin-
cias estarán encomendados a Diputaciones u otras Corpora-
ciones de carácter representativo.

   3. Se podrán crear agrupaciones de municipios diferentes de
la provincia.

   4. En los archipiélagos, las islas tendrán además su adminis-
tración propia en forma de Cabildos o Consejos.$c163$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[161], 'Artículo 142', 2, 3, md5('Artículo 142'))
    returning id into v_node_ids[164];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[164], v_user_id, 'original', $c164$Las Haciendas locales deberán disponer de los medios sufi-
cientes para el desempeño de las funciones que la ley atribuye
a las Corporaciones respectivas y se nutrirán fundamental-
mente de tributos propios y de participación en los del Estado
y de las Comunidades Autónomas.$c164$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[156], 'CAPÍTULO TERCERO', 2, 2, md5('CAPÍTULO TERCERO'))
    returning id into v_node_ids[165];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 143', 0, 3, md5('Artículo 143'))
    returning id into v_node_ids[166];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[166], v_user_id, 'original', $c166$1. En el ejercicio del derecho a la autonomía reconocido en
el artículo 2 de la Constitución, las provincias limítrofes con
características históricas, culturales y económicas comunes,
los territorios insulares y las provincias con entidad regional
histórica podrán acceder a su autogobierno y constituirse en
Comunidades Autónomas con arreglo a lo previsto en este
Título y en los respectivos Estatutos.

                                                                                                     49
   2. La iniciativa del proceso autonómico corresponde a todas
las Diputaciones interesadas o al órgano interinsular correspon-
diente y a las dos terceras partes de los municipios cuya pobla-
ción represente, al menos, la mayoría del censo electoral de
cada provincia o isla. Estos requisitos deberán ser cumplidos en
el plazo de seis meses desde el primer acuerdo adoptado al
respecto por alguna de las Corporaciones locales interesadas.

   3. La iniciativa, en caso de no prosperar, solamente podrá
reiterarse pasados cinco años.$c166$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 144', 1, 3, md5('Artículo 144'))
    returning id into v_node_ids[167];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[167], v_user_id, 'original', $c167$Las Cortes Generales, mediante ley orgánica, podrán, por
motivos de interés nacional:

   a) Autorizar la constitución de una comunidad autónoma
      cuando su ámbito territorial no supere el de una provincia
      y no reúna las condiciones del apartado 1 del artículo 143.

   b) Autorizar o acordar, en su caso, un Estatuto de autonomía
      para territorios que no estén integrados en la organiza-
      ción provincial.

   c) Sustituir la iniciativa de las Corporaciones locales a que se
      refiere el apartado 2 del artículo 143.$c167$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 145', 2, 3, md5('Artículo 145'))
    returning id into v_node_ids[168];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[168], v_user_id, 'original', $c168$1. En ningún caso se admitirá la federación de Comunidades
Autónomas.

   2. Los Estatutos podrán prever los supuestos, requisitos y
términos en que las Comunidades Autónomas podrán celebrar
convenios entre sí para la gestión y prestación de servicios
propios de las mismas, así como el carácter y efectos de la
correspondiente comunicación a las Cortes Generales. En los
demás supuestos, los acuerdos de cooperación entre las Co-
munidades Autónomas necesitarán la autorización de las Cor-
tes Generales.$c168$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 146', 3, 3, md5('Artículo 146'))
    returning id into v_node_ids[169];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[169], v_user_id, 'original', $c169$El proyecto de Estatuto será elaborado por una asamblea
compuesta por los miembros de la Diputación u órgano inter­
insular de las provincias afectadas y por los Diputados y Sena-
dores elegidos en ellas y será elevado a las Cortes Generales
para su tramitación como ley.

50$c169$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 147', 4, 3, md5('Artículo 147'))
    returning id into v_node_ids[170];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[170], v_user_id, 'original', $c170$1. Dentro de los términos de la presente Constitución, los
Estatutos serán la norma institucional básica de cada Comuni-
dad Autónoma y el Estado los reconocerá y amparará como
parte integrante de su ordenamiento jurídico.

   2. Los Estatutos de autonomía deberán contener:

     a)	La denominación de la Comunidad que mejor corres-
         ponda a su identidad histórica.

     b)	L a delimitación de su territorio.
     c)	La denominación, organización y sede de las institucio-

         nes autónomas propias.
     d)	L as competencias asumidas dentro del marco estable-

         cido en la Constitución y las bases para el traspaso de
         los servicios correspondientes a las mismas.

   3. La reforma de los Estatutos se ajustará al procedimiento
establecido en los mismos y requerirá, en todo caso, la apro-
bación por las Cortes Generales, mediante ley orgánica.$c170$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 148', 5, 3, md5('Artículo 148'))
    returning id into v_node_ids[171];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[171], v_user_id, 'original', $c171$1. Las Comunidades Autónomas podrán asumir competen-
cias en las siguientes materias:

   1.ª Organización de sus instituciones de autogobierno.
   2.ª Las alteraciones de los términos municipales compren-
didos en su territorio y, en general, las funciones que corres-
pondan a la Administración del Estado sobre las Corporaciones
locales y cuya transferencia autorice la legislación sobre Régi-
men Local.
   3.ª Ordenación del territorio, urbanismo y vivienda.
   4.ª Las obras públicas de interés de la Comunidad Autóno-
ma en su propio territorio.
   5.ª Los ferrocarriles y carreteras cuyo itinerario se desarrolle
íntegramente en el territorio de la Comunidad Autónoma y, en
los mismos términos, el transporte desarrollado por estos me-
dios o por cable.
   6.ª Los puertos de refugio, los puertos y aeropuertos depor-
tivos y, en general, los que no desarrollen actividades comer-
ciales.
   7.ª La agricultura y ganadería, de acuerdo con la ordenación
general de la economía.

                                                                                                     51
   8.ª Los montes y aprovechamientos forestales.
   9.ª La gestión en materia de protección del medio ambiente.
   10.ª Los proyectos, construcción y explotación de los apro-
vechamientos hidráulicos, canales y regadíos de interés de la
Comunidad Autónoma; las aguas minerales y termales.
   11.ª La pesca en aguas interiores, el marisqueo y la acuicul-
tura, la caza y la pesca fluvial.
   12.ª Ferias interiores.
   13.ª El fomento del desarrollo económico de la Comunidad
Autónoma dentro de los objetivos marcados por la política
económica nacional.
   14.ª La artesanía.
   15.ª Museos, bibliotecas y conservatorios de música de inte-
rés para la Comunidad Autónoma.
   16.ª Patrimonio monumental de interés de la Comunidad
Autónoma.
   17.ª El fomento de la cultura, de la investigación y, en su
caso, de la enseñanza de la lengua de la Comunidad Autóno-
ma.
   18.ª Promoción y ordenación del turismo en su ámbito te-
rritorial.
   19.ª Promoción del deporte y de la adecuada utilización del
ocio.
   20.ª Asistencia social.
   21.ª Sanidad e higiene.
   22.ª La vigilancia y protección de sus edificios e instalacio-
nes. La coordinación y demás facultades en relación con las
policías locales en los términos que establezca una ley orgáni-
ca.

   2. Transcurridos cinco años, y mediante la reforma de sus
Estatutos, las Comunidades Autónomas podrán ampliar suce-
sivamente sus competencias dentro del marco establecido en
el artículo 149.$c171$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 149', 6, 3, md5('Artículo 149'))
    returning id into v_node_ids[172];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[172], v_user_id, 'original', $c172$1. El Estado tiene competencia exclusiva sobre las siguientes
materias:

   1.ª La regulación de las condiciones básicas que garanticen
la igualdad de todos los españoles en el ejercicio de los dere-
chos y en el cumplimiento de los deberes constitucionales.

52
   2.ª Nacionalidad, inmigración, emigración, extranjería y de-
recho de asilo.

   3.ª Relaciones internacionales.
   4.ª Defensa y Fuerzas Armadas.
   5.ª Administración de Justicia.
   6.ª Legislación mercantil, penal y penitenciaria; legislación
procesal, sin perjuicio de las necesarias especialidades que en
este orden se deriven de las particularidades del derecho sus-
tantivo de las Comunidades Autónomas.
   7.ª Legislación laboral; sin perjuicio de su ejecución por los
órganos de las Comunidades Autónomas.
   8.ª Legislación civil, sin perjuicio de la conservación, modi-
ficación y desarrollo por las Comunidades Autónomas de los
derechos civiles, forales o especiales, allí donde existan. En
todo caso, las reglas relativas a la aplicación y eficacia de las
normas jurídicas, relaciones jurídico-civiles relativas a las for-
mas de matrimonio, ordenación de los registros e instrumen-
tos públicos, bases de las obligaciones contractuales, normas
para resolver los conflictos de leyes y determinación de las
fuentes del Derecho, con respeto, en este último caso, a las
normas de derecho foral o especial.
   9.ª Legislación sobre propiedad intelectual e industrial.
   10.ª Régimen aduanero y arancelario; comercio exterior.
   11.ª Sistema monetario: divisas, cambio y convertibilidad;
bases de la ordenación de crédito, banca y seguros.
   12.ª Legislación sobre pesas y medidas, determinación de la
hora oficial.
   13.ª Bases y coordinación de la planificación general de la
actividad económica.
   14.ª Hacienda general y Deuda del Estado.
   15.ª Fomento y coordinación general de la investigación
científica y técnica.
   16.ª Sanidad exterior. Bases y coordinación general de la
sanidad. Legislación sobre productos farmacéuticos.
   17.ª Legislación básica y régimen económico de la Seguridad
Social, sin perjuicio de la ejecución de sus servicios por las
Comunidades Autónomas.
   18.ª Las bases del régimen jurídico de las Administraciones
públicas y del régimen estatutario de sus funcionarios que, en
todo caso, garantizarán a los administrados un tratamiento
común ante ellas; el procedimiento administrativo común, sin

                                                                                                     53
perjuicio de las especialidades derivadas de la organización
propia de las Comunidades Autónomas; legislación sobre ex-
propiación forzosa; legislación básica sobre contratos y con-
cesiones administrativas y el sistema de responsabilidad de
todas las Administraciones públicas.

   19.ª Pesca marítima, sin perjuicio de las competencias que
en la ordenación del sector se atribuyan a las Comunidades
Autónomas.

   20.ª Marina mercante y abanderamiento de buques; ilumi-
nación de costas y señales marítimas; puertos de interés gene-
ral; aeropuertos de interés general; control del espacio aéreo,
tránsito y transporte aéreo, servicio meteorológico y matricu-
lación de aeronaves.

   21.ª Ferrocarriles y transportes terrestres que transcurran por
el territorio de más de una Comunidad Autónoma; régimen
general de comunicaciones; tráfico y circulación de vehículos
a motor; correos y telecomunicaciones; cables aéreos, sub-
marinos y radiocomunicación.

   22.ª La legislación, ordenación y concesión de recursos y apro-
vechamientos hidráulicos cuando las aguas discurran por más de
una Comunidad Autónoma, y la autorización de las instalaciones
eléctricas cuando su aprovechamiento afecte a otra Comunidad
o el transporte de energía salga de su ámbito territorial.

   23.ª Legislación básica sobre protección del medio ambien-
te, sin perjuicio de las facultades de las Comunidades Autóno-
mas de establecer normas adicionales de protección. La legis-
lación básica sobre montes, aprovechamientos forestales y
vías pecuarias.

   24.ª Obras públicas de interés general o cuya realización
afecte a más de una Comunidad Autónoma.

   25.ª Bases de régimen minero y energético.
   26.ª Régimen de producción, comercio, tenencia y uso de
armas y explosivos.
   27.ª Normas básicas del régimen de prensa, radio y televi-
sión y, en general, de todos los medios de comunicación so-
cial, sin perjuicio de las facultades que en su desarrollo y eje-
cución correspondan a las Comunidades Autónomas.
   28.ª Defensa del patrimonio cultural, artístico y monumental
español contra la exportación y la expoliación; museos, biblio-
tecas y archivos de titularidad estatal, sin perjuicio de su ges-
tión por parte de las Comunidades Autónomas.

54
   29.ª Seguridad pública, sin perjuicio de la posibilidad de
creación de policías por las Comunidades Autónomas en la
forma que se establezca en los respectivos Estatutos en el
marco de lo que disponga una ley orgánica.

   30.ª Regulación de las condiciones de obtención, expedi-
ción y homologación de títulos académicos y profesionales y
normas básicas para el desarrollo del artículo 27 de la Consti-
tución, a fin de garantizar el cumplimiento de las obligaciones
de los poderes públicos en esta materia.

   31.ª Estadística para fines estatales.
   32.ª Autorización para la convocatoria de consultas popula-
res por vía de referéndum.

   2. Sin perjuicio de las competencias que podrán asumir las
Comunidades Autónomas, el Estado considerará el servicio de
la cultura como deber y atribución esencial y facilitará la co-
municación cultural entre las Comunidades Autónomas, de
acuerdo con ellas.

   3. Las materias no atribuidas expresamente al Estado por
esta Constitución podrán corresponder a las Comunidades
Autónomas, en virtud de sus respectivos Estatutos. La compe-
tencia sobre las materias que no se hayan asumido por los
Estatutos de Autonomía corresponderá al Estado, cuyas nor-
mas prevalecerán, en caso de conflicto, sobre las de las Co-
munidades Autónomas en todo lo que no esté atribuido a la
exclusiva competencia de éstas. El derecho estatal será, en
todo caso, supletorio del derecho de las Comunidades Autó-
nomas.$c172$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 150', 7, 3, md5('Artículo 150'))
    returning id into v_node_ids[173];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[173], v_user_id, 'original', $c173$1. Las Cortes Generales, en materias de competencia estatal,
podrán atribuir a todas o a alguna de las Comunidades Autó-
nomas la facultad de dictar, para sí mismas, normas legislativas
en el marco de los principios, bases y directrices fijados por
una ley estatal. Sin perjuicio de la competencia de los Tribuna-
les, en cada ley marco se establecerá la modalidad del control
de las Cortes Generales sobre estas normas legislativas de las
Comunidades Autónomas.

   2. El Estado podrá transferir o delegar en las Comunidades
Autónomas, mediante ley orgánica, facultades correspondien-
tes a materia de titularidad estatal que por su propia naturaleza

                                                                                                     55
sean susceptibles de transferencia o delegación. La ley preve-
rá en cada caso la correspondiente transferencia de medios
financieros, así como las formas de control que se reserve el
Estado.

   3. El Estado podrá dictar leyes que establezcan los principios
necesarios para armonizar las disposiciones normativas de las
Comunidades Autónomas, aun en el caso de materias atribui-
das a la competencia de éstas, cuando así lo exija el interés
general. Corresponde a las Cortes Generales, por mayoría ab-
soluta de cada Cámara, la apreciación de esta necesidad.$c173$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 151', 8, 3, md5('Artículo 151'))
    returning id into v_node_ids[174];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[174], v_user_id, 'original', $c174$1. No será preciso dejar transcurrir el plazo de cinco años, a
que se refiere el apartado 2 del artículo 148, cuando la inicia-
tiva del proceso autonómico sea acordada dentro del plazo
del artículo 143.2, además de por las Diputaciones o los órga-
nos interinsulares correspondientes, por las tres cuartas partes
de los municipios de cada una de las provincias afectadas que
representen, al menos, la mayoría del censo electoral de cada
una de ellas y dicha iniciativa sea ratificada mediante referén-
dum por el voto afirmativo de la mayoría absoluta de los elec-
tores de cada provincia en los términos que establezca una ley
orgánica.

   2. En el supuesto previsto en el apartado anterior, el proce-
dimiento para la elaboración del Estatuto será el siguiente:

   1.º El Gobierno convocará a todos los Diputados y Senado-
res elegidos en las circunscripciones comprendidas en el ám-
bito territorial que pretenda acceder al autogobierno, para que
se constituyan en Asamblea, a los solos efectos de elaborar el
correspondiente proyecto de Estatuto de autonomía, median-
te el acuerdo de la mayoría absoluta de sus miembros.

   2.º Aprobado el proyecto de Estatuto por la Asamblea de
Parlamentarios, se remitirá a la Comisión Constitucional del
Congreso, la cual, dentro del plazo de dos meses, lo examina-
rá con el concurso y asistencia de una delegación de la Asam-
blea proponente para determinar de común acuerdo su for-
mulación definitiva.

   3.º Si se alcanzare dicho acuerdo, el texto resultante será
sometido a referéndum del cuerpo electoral de las provincias
comprendidas en el ámbito territorial del proyectado Estatuto.

56
   4.º Si el proyecto de Estatuto es aprobado en cada provincia
por la mayoría de los votos válidamente emitidos, será elevado
a las Cortes Generales. Los plenos de ambas Cámaras decidi-
rán sobre el texto mediante un voto de ratificación. Aprobado
el Estatuto, el Rey lo sancionará y lo promulgará como ley.

   5.º De no alcanzarse el acuerdo a que se refiere el apartado
2 de este número, el proyecto de Estatuto será tramitado
como proyecto de ley ante las Cortes Generales. El texto apro-
bado por éstas será sometido a referéndum del cuerpo elec-
toral de las provincias comprendidas en el ámbito territorial del
proyectado Estatuto. En caso de ser aprobado por la mayoría
de los votos válidamente emitidos en cada provincia, procede-
rá su promulgación en los términos del párrafo anterior.

   3. En los casos de los párrafos 4.º y 5.º del apartado anterior,
la no aprobación del proyecto de Estatuto por una o varias
provincias no impedirá la constitución entre las restantes de la
Comunidad Autónoma proyectada, en la forma que establezca
la ley orgánica prevista en el apartado 1 de este artículo.$c174$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 152', 9, 3, md5('Artículo 152'))
    returning id into v_node_ids[175];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[175], v_user_id, 'original', $c175$1. En los Estatutos aprobados por el procedimiento a que se
refiere el artículo anterior, la organización institucional auto-
nómica se basará en una Asamblea Legislativa, elegida por
sufragio universal, con arreglo a un sistema de representación
proporcional que asegure, además, la representación de las
diversas zonas del territorio; un Consejo de Gobierno con fun-
ciones ejecutivas y administrativas y un Presidente, elegido por
la Asamblea, de entre sus miembros, y nombrado por el Rey, al
que corresponde la dirección del Consejo de Gobierno, la su-
prema representación de la respectiva Comunidad y la ordina-
ria del Estado en aquélla. El Presidente y los miembros del
Consejo de Gobierno serán políticamente responsables ante la
Asamblea.

   Un Tribunal Superior de Justicia, sin perjuicio de la jurisdic-
ción que corresponde al Tribunal Supremo, culminará la orga-
nización judicial en el ámbito territorial de la Comunidad Au-
tónoma. En los Estatutos de las Comunidades Autónomas
podrán establecerse los supuestos y las formas de participa-
ción de aquéllas en la organización de las demarcaciones ju-
diciales del territorio. Todo ello de conformidad con lo previs-

                                                                                                     57
to en la ley orgánica del poder judicial y dentro de la unidad e
independencia de éste.

   Sin perjuicio de lo dispuesto en el artículo 123, las sucesivas
instancias procesales, en su caso, se agotarán ante órganos
judiciales radicados en el mismo territorio de la Comunidad
Autónoma en que esté el órgano competente en primera ins-
tancia.

   2. Una vez sancionados y promulgados los respectivos Esta-
tutos, solamente podrán ser modificados mediante los proce-
dimientos en ellos establecidos y con referéndum entre los
electores inscritos en los censos correspondientes.

   3. Mediante la agrupación de municipios limítrofes, los Esta-
tutos podrán establecer circunscripciones territoriales propias,
que gozarán de plena personalidad jurídica.$c175$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 153', 10, 3, md5('Artículo 153'))
    returning id into v_node_ids[176];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[176], v_user_id, 'original', $c176$El control de la actividad de los órganos de las Comunidades
Autónomas se ejercerá:

   a) Por el Tribunal Constitucional, el relativo a la constitucio-
      nalidad de sus disposiciones normativas con fuerza de ley.

   b) Por el Gobierno, previo dictamen del Consejo de Estado,
      el del ejercicio de funciones delegadas a que se refiere el
      apartado 2 del artículo 150.

   c) Por la jurisdicción contencioso-administrativa, el de la
      administración autónoma y sus normas reglamentarias.

   d) Por el Tribunal de Cuentas, el económico y presupuestario.$c176$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 154', 11, 3, md5('Artículo 154'))
    returning id into v_node_ids[177];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[177], v_user_id, 'original', $c177$Un Delegado nombrado por el Gobierno dirigirá la Adminis-
tración del Estado en el territorio de la Comunidad Autónoma
y la coordinará, cuando proceda, con la administración propia
de la Comunidad.$c177$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 155', 12, 3, md5('Artículo 155'))
    returning id into v_node_ids[178];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[178], v_user_id, 'original', $c178$1. Si una Comunidad Autónoma no cumpliere las obligacio-
nes que la Constitución u otras leyes le impongan, o actuare
de forma que atente gravemente al interés general de España,
el Gobierno, previo requerimiento al Presidente de la Comuni-
dad Autónoma y, en el caso de no ser atendido, con la apro-
bación por mayoría absoluta del Senado, podrá adoptar las

58
medidas necesarias para obligar a aquélla al cumplimiento
forzoso de dichas obligaciones o para la protección del men-
cionado interés general.

   2. Para la ejecución de las medidas previstas en el apartado
anterior, el Gobierno podrá dar instrucciones a todas las auto-
ridades de las Comunidades Autónomas.$c178$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 156', 13, 3, md5('Artículo 156'))
    returning id into v_node_ids[179];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[179], v_user_id, 'original', $c179$1. Las Comunidades Autónomas gozarán de autonomía fi-
nanciera para el desarrollo y ejecución de sus competencias
con arreglo a los principios de coordinación con la Hacienda
estatal y de solidaridad entre todos los españoles.

   2. Las Comunidades Autónomas podrán actuar como dele-
gados o colaboradores del Estado para la recaudación, la ges-
tión y la liquidación de los recursos tributarios de aquél, de
acuerdo con las leyes y los Estatutos.$c179$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 157', 14, 3, md5('Artículo 157'))
    returning id into v_node_ids[180];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[180], v_user_id, 'original', $c180$1. Los recursos de las Comunidades Autónomas estarán
constituidos por:

     a)	Impuestos cedidos total o parcialmente por el Estado;
         recargos sobre impuestos estatales y otras participacio-
         nes en los ingresos del Estado.

     b)	S us propios impuestos, tasas y contribuciones especia-
         les.

     c)	T ransferencias de un Fondo de Compensación interte-
         rritorial y otras asignaciones con cargo a los Presupues-
         tos Generales del Estado.

     d)	Rendimientos procedentes de su patrimonio e ingresos
         de derecho privado.

     e)	El producto de las operaciones de crédito.

   2. Las Comunidades Autónomas no podrán en ningún caso
adoptar medidas tributarias sobre bienes situados fuera de su
territorio o que supongan obstáculo para la libre circulación de
mercancías o servicios.

   3. Mediante ley orgánica podrá regularse el ejercicio de las
competencias financieras enumeradas en el precedente apar-
tado 1, las normas para resolver los conflictos que pudieran
surgir y las posibles formas de colaboración financiera entre
las Comunidades Autónomas y el Estado.

                                                                                                     59$c180$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[165], 'Artículo 158', 15, 3, md5('Artículo 158'))
    returning id into v_node_ids[181];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[181], v_user_id, 'original', $c181$1. En los Presupuestos Generales del Estado podrá estable-
cerse una asignación a las Comunidades Autónomas en fun-
ción del volumen de los servicios y actividades estatales que
hayan asumido y de la garantía de un nivel mínimo en la pres-
tación de los servicios públicos fundamentales en todo el te-
rritorio español.

   2. Con el fin de corregir desequilibrios económicos interterri-
toriales y hacer efectivo el principio de solidaridad, se constitui-
rá un Fondo de Compensación con destino a gastos de inver-
sión, cuyos recursos serán distribuidos por las Cortes Generales
entre las Comunidades Autónomas y provincias, en su caso.$c181$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO IX', 10, 1, md5('TÍTULO IX'))
    returning id into v_node_ids[182];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[182], 'Artículo 159', 0, 2, md5('Artículo 159'))
    returning id into v_node_ids[183];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[183], v_user_id, 'original', $c183$1. El Tribunal Constitucional se compone de 12 miembros
nombrados por el Rey; de ellos, cuatro a propuesta del Con-
greso por mayoría de tres quintos de sus miembros; cuatro a
propuesta del Senado, con idéntica mayoría; dos a propuesta
del Gobierno, y dos a propuesta del Consejo General del Poder
Judicial.

   2. Los miembros del Tribunal Constitucional deberán ser
nombrados entre Magistrados y Fiscales, Profesores de Univer-
sidad, funcionarios públicos y Abogados, todos ellos juristas de
reconocida competencia con más de quince años de ejercicio
profesional.

   3. Los miembros del Tribunal Constitucional serán designa-
dos por un período de nueve años y se renovarán por terceras
partes cada tres.

   4. La condición de miembro del Tribunal Constitucional es
incompatible: con todo mandato representativo; con los cargos
políticos o administrativos; con el desempeño de funciones di-
rectivas en un partido político o en un sindicato y con el empleo
al servicio de los mismos; con el ejercicio de las carreras judicial
y fiscal, y con cualquier actividad profesional o mercantil.

   En lo demás los miembros del Tribunal Constitucional ten-
drán las incompatibilidades propias de los miembros del poder
judicial.

60
   5. Los miembros del Tribunal Constitucional serán indepen-
dientes e inamovibles en el ejercicio de su mandato.$c183$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[182], 'Artículo 160', 1, 2, md5('Artículo 160'))
    returning id into v_node_ids[184];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[184], v_user_id, 'original', $c184$El Presidente del Tribunal Constitucional será nombrado en-
tre sus miembros por el Rey, a propuesta del mismo Tribunal
en pleno y por un período de tres años.$c184$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[182], 'Artículo 161', 2, 2, md5('Artículo 161'))
    returning id into v_node_ids[185];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[185], v_user_id, 'original', $c185$1. El Tribunal Constitucional tiene jurisdicción en todo el te-
rritorio español y es competente para conocer:

     a)	Del recurso de inconstitucionalidad contra leyes y dis-
         posiciones normativas con fuerza de ley. La declaración
         de inconstitucionalidad de una norma jurídica con ran-
         go de ley, interpretada por la jurisprudencia, afectará a
         ésta, si bien la sentencia o sentencias recaídas no per-
         derán el valor de cosa juzgada.

     b)	D el recurso de amparo por violación de los derechos y
         libertades referidos en el artículo 53, 2, de esta Consti-
         tución, en los casos y formas que la ley establezca.

     c)	D e los conflictos de competencia entre el Estado y las
         Comunidades Autónomas o de los de éstas entre sí.

     d)	D e las demás materias que le atribuyan la Constitución
         o las leyes orgánicas.

   2. El Gobierno podrá impugnar ante el Tribunal Constitucio-
nal las disposiciones y resoluciones adoptadas por los órganos
de las Comunidades Autónomas. La impugnación producirá la
suspensión de la disposición o resolución recurrida, pero el
Tribunal, en su caso, deberá ratificarla o levantarla en un plazo
no superior a cinco meses.$c185$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[182], 'Artículo 162', 3, 2, md5('Artículo 162'))
    returning id into v_node_ids[186];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[186], v_user_id, 'original', $c186$1. Están legitimados:

      a)	Para interponer el recurso de inconstitucionalidad, el
          Presidente del Gobierno, el Defensor del Pueblo, 50
          Diputados, 50 Senadores, los órganos colegiados eje-
          cutivos de las Comunidades Autónomas y, en su caso,
          las Asambleas de las mismas.

                                                                                                     61
      b)	Para interponer el recurso de amparo, toda persona
          natural o jurídica que invoque un interés legítimo, así
          como el Defensor del Pueblo y el Ministerio Fiscal.

   2. En los demás casos, la ley orgánica determinará las per-
sonas y órganos legitimados.$c186$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[182], 'Artículo 163', 4, 2, md5('Artículo 163'))
    returning id into v_node_ids[187];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[187], v_user_id, 'original', $c187$Cuando un órgano judicial considere, en algún proceso, que

una norma con rango de ley, aplicable al caso, de cuya validez
dependa el fallo, pueda ser contraria a la Constitución, plan-
teará la cuestión ante el Tribunal Constitucional en los supues-
tos, en la forma y con los efectos que establezca la ley, que en
ningún caso serán suspensivos.$c187$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[182], 'Artículo 164', 5, 2, md5('Artículo 164'))
    returning id into v_node_ids[188];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[188], v_user_id, 'original', $c188$1. Las sentencias del Tribunal Constitucional se publicarán

en el boletín oficial del Estado con los votos particulares, si los
hubiere. Tienen el valor de cosa juzgada a partir del día si-
guiente de su publicación y no cabe recurso alguno contra
ellas. Las que declaren la inconstitucionalidad de una ley o de
una norma con fuerza de ley y todas las que no se limiten a la
estimación subjetiva de un derecho, tienen plenos efectos
frente a todos.

   2. Salvo que en el fallo se disponga otra cosa, subsistirá la
vigencia de la ley en la parte no afectada por la inconstitucio-
nalidad.$c188$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[182], 'Artículo 165', 6, 2, md5('Artículo 165'))
    returning id into v_node_ids[189];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[189], v_user_id, 'original', $c189$Una ley orgánica regulará el funcionamiento del Tribunal

Constitucional, el estatuto de sus miembros, el procedimiento
ante el mismo y las condiciones para el ejercicio de las accio-
nes.$c189$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, 'TÍTULO X', 11, 1, md5('TÍTULO X'))
    returning id into v_node_ids[190];
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[190], 'Artículo 166', 0, 2, md5('Artículo 166'))
    returning id into v_node_ids[191];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[191], v_user_id, 'original', $c191$La iniciativa de reforma constitucional se ejercerá en los tér-

minos previstos en los apartados 1 y 2 del artículo 87.

62$c191$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[190], 'Artículo 167', 1, 2, md5('Artículo 167'))
    returning id into v_node_ids[192];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[192], v_user_id, 'original', $c192$1. Los proyectos de reforma constitucional deberán ser
aprobados por una mayoría de tres quintos de cada una de las
Cámaras. Si no hubiera acuerdo entre ambas, se intentará ob-
tenerlo mediante la creación de una Comisión de composición
paritaria de Diputados y Senadores, que presentará un texto
que será votado por el Congreso y el Senado.

   2. De no lograrse la aprobación mediante el procedimiento
del apartado anterior, y siempre que el texto hubiere obtenido
el voto favorable de la mayoría absoluta del Senado, el Con-
greso, por mayoría de dos tercios, podrá aprobar la reforma.

   3. Aprobada la reforma por las Cortes Generales, será some-
tida a referéndum para su ratificación cuando así lo soliciten,
dentro de los quince días siguientes a su aprobación, una dé-
cima parte de los miembros de cualquiera de las Cámaras.$c192$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[190], 'Artículo 168', 2, 2, md5('Artículo 168'))
    returning id into v_node_ids[193];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[193], v_user_id, 'original', $c193$1. Cuando se propusiere la revisión total de la Constitución
o una parcial que afecte al Título preliminar, al Capítulo segun-
do, Sección primera del Título I, o al Título II, se procederá a la
aprobación del principio por mayoría de dos tercios de cada
Cámara, y a la disolución inmediata de las Cortes.

   2. Las Cámaras elegidas deberán ratificar la decisión y pro-
ceder al estudio del nuevo texto constitucional, que deberá ser
aprobado por mayoría de dos tercios de ambas Cámaras.

   3. Aprobada la reforma por las Cortes Generales, será some-
tida a referéndum para su ratificación.$c193$);
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_node_ids[190], 'Artículo 169', 3, 2, md5('Artículo 169'))
    returning id into v_node_ids[194];
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_node_ids[194], v_user_id, 'original', $c194$No podrá iniciarse la reforma constitucional en tiempo de
guerra o de vigencia de alguno de los estados previstos en el
artículo 116.

ς  Disposición adicional primera

   La Constitución ampara y respeta los derechos históricos de
los territorios forales.

   La actualización general de dicho régimen foral se llevará a
cabo, en su caso, en el marco de la Constitución y de los Es-
tatutos de Autonomía.

                                                                                                     63
ς  Disposición adicional segunda
   La declaración de mayoría de edad contenida en el artículo

12 de esta Constitución no perjudica las situaciones ampara-
das por los derechos forales en el ámbito del Derecho privado.

ς  Disposición adicional tercera
   La modificación del régimen económico y fiscal del archi-

piélago canario requerirá informe previo de la Comunidad
Autónoma o, en su caso, del órgano provisional autonómico.

ς  Disposición adicional cuarta
   En las Comunidades Autónomas donde tengan su sede más

de una Audiencia Territorial, los Estatutos de Autonomía res-
pectivos podrán mantener las existentes, distribuyendo las
competencias entre ellas, siempre de conformidad con lo pre-
visto en la ley orgánica del poder judicial y dentro de la unidad
e independencia de éste.

ς  Disposición transitoria primera

   En los territorios dotados de un régimen provisional de au-
tonomía, sus órganos colegiados superiores, mediante acuer-
do adoptado por la mayoría absoluta de sus miembros, podrán
sustituir la iniciativa que en el apartado 2 del artículo 143 atri-
buye a las Diputaciones Provinciales o a los órganos interinsu-
lares correspondientes.

ς  Disposición transitoria segunda

   Los territorios que en el pasado hubiesen plebiscitado afir-
mativamente proyectos de Estatuto de autonomía y cuenten,
al tiempo de promulgarse esta Constitución, con regímenes
provisionales de autonomía podrán proceder inmediatamente
en la forma que se prevé en el apartado 2 del artículo 148,
cuando así lo acordaren, por mayoría absoluta, sus órganos
preautonómicos colegiados superiores, comunicándolo al
Gobierno. El proyecto de Estatuto será elaborado de acuerdo
con lo establecido en el artículo 151, número 2, a convocatoria
del órgano colegiado preautonómico.

ς  Disposición transitoria tercera

   La iniciativa del proceso autonómico por parte de las Cor-
poraciones locales o de sus miembros, prevista en el apartado

64
2 del artículo 143, se entiende diferida, con todos sus efectos,
hasta la celebración de las primeras elecciones locales una vez
vigente la Constitución.

ς  Disposición transitoria cuarta

   1. En el caso de Navarra, y a efectos de su incorporación al
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
plazo mínimo que establece el artículo 143.

ς  Disposición transitoria quinta

   Las ciudades de Ceuta y Melilla podrán constituirse en Comu-
nidades Autónomas si así lo deciden sus respectivos Ayunta-
mientos, mediante acuerdo adoptado por la mayoría absoluta de
sus miembros y así lo autorizan las Cortes Generales, mediante
una ley orgánica, en los términos previstos en el artículo 144.

ς  Disposición transitoria sexta
   Cuando se remitieran a la Comisión Constitucional del Con-

greso varios proyectos de Estatuto, se dictaminarán por el
orden de entrada en aquélla, y el plazo de dos meses a que se
refiere el artículo 151 empezará a contar desde que la Comi-
sión termine el estudio del proyecto o proyectos de que suce-
sivamente haya conocido.

ς  Disposición transitoria séptima
   Los organismos provisionales autonómicos se considerarán

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
      tres años.

ς  Disposición transitoria octava

   1. Las Cámaras que han aprobado la presente Constitución
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
edad para el voto y lo establecido en el artículo 69,3.

ς  Disposición transitoria novena

   A los tres años de la elección por vez primera de los miem-
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
a lo establecido en el número 3 del artículo 159.

ς  Disposición derogatoria
   1. Queda derogada la Ley 1/1977, de 4 de enero, para la Re-

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
opongan a lo establecido en esta Constitución.

ς  Disposición final
   Esta Constitución entrará en vigor el mismo día de la publi-

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

68$c194$);
  end;

  -- 6) Marcar subject como listo.
  update public.subjects
  set index_status = 'ready', index_error = null
  where id = v_subject_id;

  raise notice '[0089] subject marcado como ready';
end $$;
