-- ============================================================================
-- 0069_shared_indexes_gin.sql · Índice GIN para acotar candidatos de ampliación
-- ----------------------------------------------------------------------------
-- `expand-subject` necesita encontrar los `shared_indexes` que COMPARTEN alguna
-- sección con el temario del usuario. Escanear todas las filas (y su jsonb
-- `nodes`) no escala. Añadimos `leaf_hashes text[]` (los hashes de las hojas) +
-- un índice GIN, de modo que la búsqueda use el operador de solapamiento `&&`
-- (PostgREST `.overlaps`) y solo devuelva candidatos relevantes.
-- ============================================================================

alter table public.shared_indexes
  add column if not exists leaf_hashes text[];

-- Índice GIN para el operador de solapamiento de arrays (`leaf_hashes && {...}`).
create index if not exists shared_indexes_leaf_hashes_gin
  on public.shared_indexes using gin (leaf_hashes);

-- Backfill de filas existentes: extrae de `nodes` los hashes de las hojas.
update public.shared_indexes si
set leaf_hashes = sub.hashes
from (
  select s.doc_fingerprint,
         array_agg(elem->>'hash')
           filter (
             where coalesce((elem->>'leaf')::boolean, false)
               and elem->>'hash' is not null
           ) as hashes
  from public.shared_indexes s,
       lateral jsonb_array_elements(s.nodes) as elem
  group by s.doc_fingerprint
) sub
where si.doc_fingerprint = sub.doc_fingerprint
  and si.leaf_hashes is null;
