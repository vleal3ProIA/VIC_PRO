-- ============================================================================
-- 0071_tf_and_essay_banks.sql · Bancos GLOBAL Verdadero/Falso + Desarrollo
-- ----------------------------------------------------------------------------
-- Mismo patrón que `question_bank` (migración 0062): bancos COMPARTIDOS por
-- contenido (indexados por `content_hash`), para no regenerar preguntas que ya
-- existen para una sección con texto idéntico —aunque sea de otro temario u
-- otro usuario—. Dos modalidades nuevas:
--
--  • `tf_bank`    → afirmaciones Verdadero/Falso (binarias) por sección.
--  • `essay_bank` → preguntas a desarrollar (open-ended) con respuesta modelo.
--
-- El hash de cada nodo del índice ya se guarda en `index_nodes.content_hash`
-- (creado por 0062). Aquí solo añadimos las tablas y sus RLS.
--
-- Lectura: cualquier usuario autenticado (banco común). Escritura: solo la
-- Edge Function (`service_role`, que ignora RLS) — el cliente NUNCA inserta.
-- ============================================================================

-- ─── Verdadero / Falso ──────────────────────────────────────────────────────
create table if not exists public.tf_bank (
  id            uuid primary key default gen_random_uuid(),
  content_hash  text not null,
  statement     text not null,         -- la afirmación (frase)
  is_true       boolean not null,      -- si la afirmación es V o F
  explanation   text,
  lang          text,
  created_at    timestamptz not null default now()
);

create index if not exists tf_bank_hash_idx
  on public.tf_bank (content_hash);

alter table public.tf_bank enable row level security;

-- Lectura para cualquier usuario autenticado (banco compartido).
drop policy if exists "tf_bank_read_all" on public.tf_bank;
create policy "tf_bank_read_all"
  on public.tf_bank for select
  using (auth.uid() is not null);

-- Sin políticas de escritura: solo service_role (Edge Function) puede insertar.

-- ─── Preguntas a desarrollar (Essay) ────────────────────────────────────────
create table if not exists public.essay_bank (
  id            uuid primary key default gen_random_uuid(),
  content_hash  text not null,
  question      text not null,         -- pregunta a desarrollar
  answer        text not null,         -- respuesta modelo (puede ser larga)
  lang          text,
  created_at    timestamptz not null default now()
);

create index if not exists essay_bank_hash_idx
  on public.essay_bank (content_hash);

alter table public.essay_bank enable row level security;

-- Lectura para cualquier usuario autenticado (banco compartido).
drop policy if exists "essay_bank_read_all" on public.essay_bank;
create policy "essay_bank_read_all"
  on public.essay_bank for select
  using (auth.uid() is not null);

-- Sin políticas de escritura: solo service_role (Edge Function) puede insertar.
