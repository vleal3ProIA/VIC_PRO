-- ============================================================================
-- 0078 · admin_list_subjects: RPC SECURITY DEFINER para que el SUPER admin
-- pueda listar TODOS los temarios del proyecto (saltandose RLS por owner)
-- y verlos en /admin/material-library (vista solo lectura).
-- ----------------------------------------------------------------------------
-- Esta RPC esta cerrada por `is_super_admin()`. Si un user normal o un
-- admin sin super la llama via PostgREST, recibe `permission_denied`.
--
-- Devuelve para cada temario:
--   * Subject completo (id, title, language, index_status, index_locked,
--     index_error, exam_date, created_at, shareable, user_id del owner).
--   * Email + display_name + username del owner (join con auth.users +
--     public.profiles).
--   * docs_count y nodes_count agregados (subselects), para que la tabla
--     admin pueda pintar # docs y # secciones sin llamadas extra.
--
-- Soporta filtros + paginacion para no traer 10k filas:
--   * p_language       : 'es', 'en', ... o null = todos.
--   * p_owner_user_id  : uuid del owner o null.
--   * p_index_status   : 'none' | 'generating' | 'ready' | 'failed'.
--                        Como `subjects.index_status` puede ser null,
--                        mapeamos null → 'none' para que el filtro encaje.
--   * p_title_search   : ILIKE %x% sobre subjects.title (o '' = no filtro).
--   * p_from_date      : created_at >= p_from_date.
--   * p_to_date        : created_at <  p_to_date + interval '1 day' (rango
--                        inclusivo por dia natural).
--   * p_limit          : default 50, max 200 (cap server-side).
--   * p_offset         : default 0.
--
-- Orden: created_at DESC (lo mas reciente primero). Estable, los IDs
-- empatados se ordenan a posteriori en cliente si hace falta.
-- ============================================================================

create or replace function public.admin_list_subjects(
  p_language       text default null,
  p_owner_user_id  uuid default null,
  p_index_status   text default null,
  p_title_search   text default null,
  p_from_date      timestamptz default null,
  p_to_date        timestamptz default null,
  p_limit          integer default 50,
  p_offset         integer default 0
)
returns table (
  id              uuid,
  user_id         uuid,
  title           text,
  language        text,
  index_status    text,
  index_locked    boolean,
  index_error     text,
  exam_date       date,
  shareable       boolean,
  created_at      timestamptz,
  owner_email     text,
  owner_username  text,
  owner_display   text,
  docs_count      bigint,
  nodes_count     bigint
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_limit  integer := least(coalesce(p_limit, 50), 200);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_search text := nullif(trim(coalesce(p_title_search, '')), '');
begin
  -- Gate: SOLO super admin. Otros admins reciben permission_denied
  -- (PostgreSQL convierte el `raise exception` en 42501 que PostgREST
  -- presenta como 403 al cliente). La capa de UI ya filtra el menu
  -- pero NUNCA hay que confiar solo en la UI.
  if not public.is_super_admin() then
    raise exception 'super admin only' using errcode = '42501';
  end if;

  return query
  with subj as (
    select s.*
    from public.subjects s
    where (p_language       is null or s.language = p_language)
      and (p_owner_user_id  is null or s.user_id  = p_owner_user_id)
      and (p_index_status   is null
           or coalesce(s.index_status, 'none') = p_index_status)
      and (v_search         is null or s.title ilike '%' || v_search || '%')
      and (p_from_date      is null or s.created_at >= p_from_date)
      and (p_to_date        is null or s.created_at <  (p_to_date + interval '1 day'))
    order by s.created_at desc
    limit  v_limit
    offset v_offset
  )
  select
    s.id,
    s.user_id,
    s.title,
    s.language,
    s.index_status,
    s.index_locked,
    s.index_error,
    s.exam_date,
    s.shareable,
    s.created_at,
    u.email::text                                as owner_email,
    p.username                                   as owner_username,
    p.display_name                               as owner_display,
    coalesce((select count(*) from public.documents    d where d.subject_id = s.id), 0) as docs_count,
    coalesce((select count(*) from public.index_nodes  n where n.subject_id = s.id), 0) as nodes_count
  from subj s
  left join auth.users      u on u.id = s.user_id
  left join public.profiles p on p.id = s.user_id;
end;
$$;

revoke all on function public.admin_list_subjects(
  text, uuid, text, text, timestamptz, timestamptz, integer, integer
) from public;
grant execute on function public.admin_list_subjects(
  text, uuid, text, text, timestamptz, timestamptz, integer, integer
) to authenticated;

comment on function public.admin_list_subjects(
  text, uuid, text, text, timestamptz, timestamptz, integer, integer
) is
  'Super-admin only. Lista TODOS los subjects (saltando RLS por owner) '
  'con datos del owner (email/username) y contadores (docs/nodes). '
  'Soporta filtros + paginacion (max 200 filas por llamada).';

-- ============================================================================
-- admin_list_subject_owners: RPC auxiliar para el autocomplete del filtro
-- "owner" en /admin/material-library. Lista profiles con al menos 1 subject,
-- buscables por username / display_name / email.
-- ============================================================================

create or replace function public.admin_list_subject_owners(
  p_search text default null,
  p_limit  integer default 20
)
returns table (
  user_id      uuid,
  email        text,
  username     text,
  display_name text,
  subjects_count bigint
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_limit  integer := least(coalesce(p_limit, 20), 100);
  v_search text := nullif(trim(coalesce(p_search, '')), '');
begin
  if not public.is_super_admin() then
    raise exception 'super admin only' using errcode = '42501';
  end if;

  return query
  select
    p.id                       as user_id,
    u.email::text              as email,
    p.username                 as username,
    p.display_name             as display_name,
    coalesce((select count(*) from public.subjects s where s.user_id = p.id), 0)
                               as subjects_count
  from public.profiles p
  left join auth.users u on u.id = p.id
  where exists (select 1 from public.subjects s where s.user_id = p.id)
    and (v_search is null
         or p.username      ilike '%' || v_search || '%'
         or p.display_name  ilike '%' || v_search || '%'
         or u.email::text   ilike '%' || v_search || '%')
  order by subjects_count desc, p.username nulls last, u.email
  limit v_limit;
end;
$$;

revoke all on function public.admin_list_subject_owners(text, integer) from public;
grant execute on function public.admin_list_subject_owners(text, integer) to authenticated;

comment on function public.admin_list_subject_owners(text, integer) is
  'Super-admin only. Autocomplete para el filtro owner del Material Library: '
  'devuelve profiles con >= 1 subject que casen el search.';

-- ============================================================================
-- admin_get_subject: RPC SECURITY DEFINER para el detalle read-only de un
-- subject (saltandose la RLS por owner). Mismo gate (super admin only).
-- ----------------------------------------------------------------------------
-- Devuelve UNA fila con los mismos campos que admin_list_subjects (sin la
-- paginacion). Si el subject no existe → cero filas. La UI debe tratar
-- el caso vacio como "not found".
-- ============================================================================

create or replace function public.admin_get_subject(
  p_subject_id uuid
)
returns table (
  id              uuid,
  user_id         uuid,
  title           text,
  language        text,
  index_status    text,
  index_locked    boolean,
  index_error     text,
  exam_date       date,
  shareable       boolean,
  created_at      timestamptz,
  owner_email     text,
  owner_username  text,
  owner_display   text,
  docs_count      bigint,
  nodes_count     bigint
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'super admin only' using errcode = '42501';
  end if;
  if p_subject_id is null then
    raise exception 'p_subject_id required';
  end if;

  return query
  select
    s.id, s.user_id, s.title, s.language,
    s.index_status, s.index_locked, s.index_error,
    s.exam_date, s.shareable, s.created_at,
    u.email::text                                as owner_email,
    p.username                                   as owner_username,
    p.display_name                               as owner_display,
    coalesce((select count(*) from public.documents    d where d.subject_id = s.id), 0) as docs_count,
    coalesce((select count(*) from public.index_nodes  n where n.subject_id = s.id), 0) as nodes_count
  from public.subjects s
  left join auth.users      u on u.id = s.user_id
  left join public.profiles p on p.id = s.user_id
  where s.id = p_subject_id;
end;
$$;

revoke all on function public.admin_get_subject(uuid) from public;
grant execute on function public.admin_get_subject(uuid) to authenticated;

comment on function public.admin_get_subject(uuid) is
  'Super-admin only. Devuelve un subject + datos del owner + contadores '
  'saltando RLS por owner. Para la vista read-only de /admin/material-library/:id.';

-- ============================================================================
-- Super-admin SELECT policies sobre las tablas que cuelgan de subjects
-- ----------------------------------------------------------------------------
-- La RLS por owner sigue siendo la regla por defecto. Estas policies ADICIONALES
-- (compuestas con OR via Postgres) permiten al super-admin LEER (no escribir)
-- los nodos de indice, contenidos generados, anotaciones, flashcards, tests,
-- chat, guias de estudio, etc. del temario que esta abriendo en
-- /admin/material-library/:id.
--
-- Por que policies y no RPCs: la UI ya esta escrita y consume providers que
-- llaman directamente a las tablas. Anyadir 10 RPCs duplicaria toda la
-- superficie de datos sin valor anyadido. Una policy SELECT permisiva por
-- super-admin es la solucion minima: el resto de mutaciones siguen bloqueadas
-- (los policies existentes son "for all" with owner check; estas SOLO anyaden
-- SELECT). Defensa adicional: la UI del admin view jamas llama a metodos
-- mutadores del datasource.
-- ============================================================================

-- subjects: super lee todos (sin permiso de INSERT/UPDATE/DELETE).
drop policy if exists "subjects_super_select" on public.subjects;
create policy "subjects_super_select"
  on public.subjects for select
  using (public.is_super_admin());

-- documents: para mostrar cuantos archivos hay + sus nombres.
drop policy if exists "documents_super_select" on public.documents;
create policy "documents_super_select"
  on public.documents for select
  using (public.is_super_admin());

-- index_nodes: arbol del indice.
drop policy if exists "index_nodes_super_select" on public.index_nodes;
create policy "index_nodes_super_select"
  on public.index_nodes for select
  using (public.is_super_admin());

-- node_content: vistas generadas (explicado / resumen) por nodo.
drop policy if exists "node_content_super_select" on public.node_content;
create policy "node_content_super_select"
  on public.node_content for select
  using (public.is_super_admin());

-- annotations: notas que el user escribio.
drop policy if exists "annotations_super_select" on public.annotations;
create policy "annotations_super_select"
  on public.annotations for select
  using (public.is_super_admin());

-- flashcards: tarjetas del user.
drop policy if exists "flashcards_super_select" on public.flashcards;
create policy "flashcards_super_select"
  on public.flashcards for select
  using (public.is_super_admin());

-- quiz_questions: cuestionario del user.
drop policy if exists "quiz_questions_super_select" on public.quiz_questions;
create policy "quiz_questions_super_select"
  on public.quiz_questions for select
  using (public.is_super_admin());

-- chat_messages: historial de chat (read-only para super).
drop policy if exists "chat_messages_super_select" on public.chat_messages;
create policy "chat_messages_super_select"
  on public.chat_messages for select
  using (public.is_super_admin());

-- study_guides: guia de estudio cacheada.
drop policy if exists "study_guides_super_select" on public.study_guides;
create policy "study_guides_super_select"
  on public.study_guides for select
  using (public.is_super_admin());

-- cram_sheets: chuleta "modo panico".
drop policy if exists "cram_sheets_super_select" on public.cram_sheets;
create policy "cram_sheets_super_select"
  on public.cram_sheets for select
  using (public.is_super_admin());

-- exam_attempts: historial de tests realizados.
drop policy if exists "exam_attempts_super_select" on public.exam_attempts;
create policy "exam_attempts_super_select"
  on public.exam_attempts for select
  using (public.is_super_admin());

-- Nota: el banco GLOBAL (question_bank, tf_bank, essay_bank) NO es por
-- owner; ya es legible sin estas policies (cualquier user lo lee para
-- reutilizar material). Asi que no anyadimos policy super para ellos.
