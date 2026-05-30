-- ============================================================================
-- 0079 · public_domain_sources + is_public_domain_subject + storage policy
-- ----------------------------------------------------------------------------
-- Objetivo: permitir al SUPER admin descargar (y por tanto leer del bucket
-- privado `temarios`) los documentos ORIGINALES de los subjects que sean de
-- "dominio publico", entendiendo por tales:
--
--   1) Los que el usuario marco explicitamente como `shareable = true` al
--      subir (ya existente; check-box de "material libre").
--   2) Los que provienen de alguna fuente publica reconocida (BOE, .gov,
--      wikipedia.org, etc.) — gestionado por la nueva tabla
--      `public_domain_sources` (whitelist de patterns case-insensitive).
--
-- CRITICAL — IP / GDPR: el super admin NO puede leer arbitrariamente
-- ningun fichero del bucket. La policy de storage exige que el `subject`
-- al que pertenece el documento sea de dominio publico (funcion
-- `is_public_domain_subject`). La UI puede mentir; la storage policy es la
-- fuente de verdad.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1) Tabla public_domain_sources
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.public_domain_sources (
  id uuid primary key default gen_random_uuid(),
  -- Patron de matching contra el `file_name` o un campo origen. Usamos
  -- pattern matching simple: si el upload tiene en el nombre o en una
  -- columna nueva `source_url` algo que contenga este pattern (case-
  -- insensitive), se considera del dominio publico.
  pattern text not null check (length(pattern) between 2 and 200),
  -- Etiqueta legible: "BOE", "Wikipedia", "Dominios .gov", etc.
  label text not null,
  -- Tipo de match: 'domain' (busca en source_url), 'filename' (busca
  -- en file_name), 'extension' (busca en mime/extension).
  match_type text not null default 'domain'
    check (match_type in ('domain', 'filename', 'extension')),
  -- Si esta inactivo, no filtra (pero queda en BD para auditoria).
  enabled boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create index if not exists public_domain_sources_enabled_idx
  on public.public_domain_sources (enabled) where enabled = true;

alter table public.public_domain_sources enable row level security;

-- Lectura: cualquier autenticado (para que la UI muestre el chip "Libre"
-- al user). Si esto resulta arriesgado, sustituirlo por
-- "authenticated AND has_capability('manage_app_branding')" — el user
-- normal no necesita ver los patterns, solo si su upload cae en uno.
drop policy if exists "public_domain_sources_read_all" on public.public_domain_sources;
create policy "public_domain_sources_read_all"
  on public.public_domain_sources for select to authenticated using (true);

-- Escritura: solo super_admin.
drop policy if exists "public_domain_sources_super_write" on public.public_domain_sources;
create policy "public_domain_sources_super_write"
  on public.public_domain_sources for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

-- ────────────────────────────────────────────────────────────────────────────
-- 2) Columna source_url en documents (opcional al subir)
-- ────────────────────────────────────────────────────────────────────────────
alter table public.documents
  add column if not exists source_url text;

-- ────────────────────────────────────────────────────────────────────────────
-- 3) Seeds basicos (idempotente con on conflict do nothing por (pattern))
--    No hay UNIQUE en pattern para permitir patrones repetidos con distintos
--    `match_type` (poco probable). El "on conflict do nothing" depende de
--    una constraint UNIQUE; en su ausencia, hacemos un insert guardado por
--    NOT EXISTS para que el re-run no duplique.
-- ────────────────────────────────────────────────────────────────────────────
insert into public.public_domain_sources (pattern, label, match_type, notes)
select v.pattern, v.label, v.match_type, v.notes
from (values
  ('boe.es',        'BOE (Boletin Oficial del Estado)',
   'domain', 'Contenido oficial del Estado espanol — dominio publico por Art 13 LPI.'),
  ('.gov',          'Dominios .gov',
   'domain', 'Publicaciones de gobiernos — generalmente dominio publico.'),
  ('wikipedia.org', 'Wikipedia',
   'domain', 'CC BY-SA — atribucion requerida pero accesible libremente.'),
  ('unesco.org',    'UNESCO',
   'domain', null::text),
  ('europa.eu',     'Union Europea (.europa.eu)',
   'domain', null::text)
) as v(pattern, label, match_type, notes)
where not exists (
  select 1 from public.public_domain_sources p
   where p.pattern = v.pattern and p.match_type = v.match_type
);

-- ────────────────────────────────────────────────────────────────────────────
-- 4) Funcion is_public_domain_subject(uuid) -> boolean
--    SECURITY DEFINER: porque se usa dentro de policies de storage donde el
--    caller puede ser un user sin permisos directos sobre la tabla.
--    STABLE: misma input dentro de la query devuelve mismo output.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.is_public_domain_subject(p_subject_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    -- Caso 1: shareable explicito.
    select 1 from public.subjects s
    where s.id = p_subject_id and s.shareable = true
  ) or exists (
    -- Caso 2: algun documento del subject coincide con un pattern activo.
    select 1
    from public.documents d
    join public.public_domain_sources p on (
      p.enabled = true
      and (
        (p.match_type = 'domain' and d.source_url is not null
         and position(lower(p.pattern) in lower(d.source_url)) > 0)
        or (p.match_type = 'filename' and d.file_name is not null
         and position(lower(p.pattern) in lower(d.file_name)) > 0)
        or (p.match_type = 'extension'
         and (d.file_name ilike '%.' || p.pattern
              or d.mime_type ilike '%' || p.pattern || '%'))
      )
    )
    where d.subject_id = p_subject_id
  );
$$;

revoke all on function public.is_public_domain_subject(uuid) from public;
grant execute on function public.is_public_domain_subject(uuid) to authenticated;

comment on function public.is_public_domain_subject(uuid) is
  'TRUE si el subject es shareable=true o algun documento casa con un '
  'pattern activo de public_domain_sources. SECURITY DEFINER para uso en '
  'policies RLS de otros roles (storage).';

-- ────────────────────────────────────────────────────────────────────────────
-- 5) Storage policy: super admin puede SELECT (descargar) objetos del bucket
--    `temarios` SOLO si su subject es de dominio publico.
-- ────────────────────────────────────────────────────────────────────────────
drop policy if exists "temarios_super_read_public_domain" on storage.objects;
create policy "temarios_super_read_public_domain"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'temarios'
    and public.is_super_admin()
    and exists (
      select 1 from public.documents d
      join public.subjects s on s.id = d.subject_id
      where d.storage_path = storage.objects.name
        and public.is_public_domain_subject(s.id)
    )
  );

-- ────────────────────────────────────────────────────────────────────────────
-- 6) Re-create admin_list_subjects para anyadir `is_public_domain boolean`
--    + filtro opcional `p_only_public_domain boolean`.
--    Postgres exige DROP previo si la firma cambia (anyadimos parametro).
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.admin_list_subjects(
  text, uuid, text, text, timestamptz, timestamptz, integer, integer
);

create or replace function public.admin_list_subjects(
  p_language              text default null,
  p_owner_user_id         uuid default null,
  p_index_status          text default null,
  p_title_search          text default null,
  p_from_date             timestamptz default null,
  p_to_date               timestamptz default null,
  p_limit                 integer default 50,
  p_offset                integer default 0,
  p_only_public_domain    boolean default false
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
  nodes_count     bigint,
  is_public_domain boolean
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
      and (p_only_public_domain is not true
           or public.is_public_domain_subject(s.id))
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
    coalesce((select count(*) from public.index_nodes  n where n.subject_id = s.id), 0) as nodes_count,
    public.is_public_domain_subject(s.id)        as is_public_domain
  from subj s
  left join auth.users      u on u.id = s.user_id
  left join public.profiles p on p.id = s.user_id;
end;
$$;

revoke all on function public.admin_list_subjects(
  text, uuid, text, text, timestamptz, timestamptz, integer, integer, boolean
) from public;
grant execute on function public.admin_list_subjects(
  text, uuid, text, text, timestamptz, timestamptz, integer, integer, boolean
) to authenticated;

comment on function public.admin_list_subjects(
  text, uuid, text, text, timestamptz, timestamptz, integer, integer, boolean
) is
  'Super-admin only. Lista TODOS los subjects con datos del owner, contadores '
  '(docs/nodes) y flag is_public_domain. Soporta filtro extra p_only_public_domain.';

-- ────────────────────────────────────────────────────────────────────────────
-- 7) Re-create admin_get_subject para devolver tambien `is_public_domain`.
--    No anyadimos parametros nuevos, solo un campo al return type — pero
--    Postgres tampoco permite cambiar el return type sin DROP.
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.admin_get_subject(uuid);

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
  nodes_count     bigint,
  is_public_domain boolean
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
    coalesce((select count(*) from public.index_nodes  n where n.subject_id = s.id), 0) as nodes_count,
    public.is_public_domain_subject(s.id)        as is_public_domain
  from public.subjects s
  left join auth.users      u on u.id = s.user_id
  left join public.profiles p on p.id = s.user_id
  where s.id = p_subject_id;
end;
$$;

revoke all on function public.admin_get_subject(uuid) from public;
grant execute on function public.admin_get_subject(uuid) to authenticated;

comment on function public.admin_get_subject(uuid) is
  'Super-admin only. Devuelve un subject + datos del owner + contadores + '
  'is_public_domain. Para la vista read-only /admin/material-library/:id.';
