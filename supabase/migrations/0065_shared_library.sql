-- ============================================================================
-- 0065_shared_library.sql · Biblioteca GLOBAL del proyecto + pgvector (Fase 5)
-- ----------------------------------------------------------------------------
-- Todo lo que generamos (índices, contenido, preguntas, flashcards, esquemas)
-- es material del proyecto y queremos REUTILIZARLO entre usuarios/temarios para
-- no gastar tokens. La pieza central es `shared_sections`: un catálogo GLOBAL
-- de "trozos de temario" indexado por el HASH de su contenido (`content_hash`,
-- el mismo que ya usa `question_bank`) y con un EMBEDDING (vector) para detectar
-- secciones "muy parecidas" aunque el texto no sea idéntico.
--
-- Reglas de privacidad / copyright (decisión del producto):
--   * El usuario DECLARA en cada subida si su material es de fuente libre
--     (legislación, dominio público). Solo esos temarios (`subjects.shareable`)
--     ESCRIBEN en el pool y guardan su texto fuente. Los demás NO contribuyen.
--   * LEER del pool lo puede hacer cualquier usuario autenticado: el contenido
--     generado es material del proyecto.
--
-- pgvector: dimensión fija 768 (Gemini text-embedding-004; OpenAI
-- text-embedding-3-small se pide reducido a 768 dims). Índice HNSW coseno.
-- ============================================================================

create extension if not exists vector;

-- ─────────────── Declaración de "material libre" en el temario ───────────────
alter table public.subjects
  add column if not exists shareable boolean not null default false;

-- ─────────────────────────── Catálogo global ────────────────────────────────
create table if not exists public.shared_sections (
  content_hash text primary key,
  title        text,
  lang         text,
  -- Texto fuente de la sección. Solo se guarda para material declarado libre
  -- (`has_text=true`); para material privado el pool no almacena el texto.
  body         text,
  has_text     boolean not null default false,
  embedding    vector(768),
  source_kind  text not null default 'user',
  times_seen   int  not null default 1,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists shared_sections_lang_idx
  on public.shared_sections (lang);

-- Búsqueda por similitud coseno (HNSW). Las filas con embedding NULL se ignoran.
create index if not exists shared_sections_embedding_idx
  on public.shared_sections using hnsw (embedding vector_cosine_ops);

drop trigger if exists shared_sections_set_updated_at on public.shared_sections;
create trigger shared_sections_set_updated_at
  before update on public.shared_sections
  for each row execute function public.set_updated_at();

alter table public.shared_sections enable row level security;

-- Lectura para cualquier usuario autenticado (biblioteca común del proyecto).
drop policy if exists "shared_sections_read_all" on public.shared_sections;
create policy "shared_sections_read_all"
  on public.shared_sections for select
  using (auth.uid() is not null);

-- Sin políticas de escritura: solo service_role (Edge Functions) puede escribir.

-- ─────────────── RPC de similitud (la llaman las Edge Functions) ─────────────
-- Devuelve las secciones del pool más parecidas a `query_embedding` por encima
-- de `match_threshold` (0..1, coseno), como máximo `match_count`.
create or replace function public.match_shared_sections(
  query_embedding vector(768),
  match_threshold double precision,
  match_count int
)
returns table (
  content_hash text,
  title text,
  lang text,
  similarity double precision
)
language sql
stable
as $$
  select
    s.content_hash,
    s.title,
    s.lang,
    1 - (s.embedding <=> query_embedding) as similarity
  from public.shared_sections s
  where s.embedding is not null
    and 1 - (s.embedding <=> query_embedding) > match_threshold
  order by s.embedding <=> query_embedding
  limit greatest(match_count, 1);
$$;
