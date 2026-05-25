-- ============================================================================
-- 0062_question_bank.sql · Banco de preguntas GLOBAL por contenido (Fase 4+)
-- ----------------------------------------------------------------------------
-- En vez de regenerar las preguntas de cada temario una y otra vez (caro), las
-- guardamos en un banco COMPARTIDO indexado por el HASH del texto de la sección
-- (`content_hash`). Así, dos secciones con el MISMO texto —aunque sean de
-- temarios o usuarios distintos— comparten las mismas preguntas y no se vuelve
-- a gastar IA.
--
-- El hash de cada nodo del índice se guarda en `index_nodes.content_hash` para
-- que el cliente pueda mapear nodo -> preguntas sin re-leer el contenido.
--
-- Lectura: cualquier usuario autenticado (banco común). Escritura: solo la
-- Edge Function (service_role, que ignora RLS) — el cliente NUNCA inserta.
-- ============================================================================

alter table public.index_nodes
  add column if not exists content_hash text;

create index if not exists index_nodes_content_hash_idx
  on public.index_nodes (content_hash);

create table if not exists public.question_bank (
  id            uuid primary key default gen_random_uuid(),
  content_hash  text not null,
  question      text not null,
  options       jsonb not null,
  correct_index int  not null default 0,
  explanation   text,
  lang          text,
  created_at    timestamptz not null default now()
);

create index if not exists question_bank_hash_idx
  on public.question_bank (content_hash);

alter table public.question_bank enable row level security;

-- Lectura para cualquier usuario autenticado (banco compartido).
drop policy if exists "question_bank_read_all" on public.question_bank;
create policy "question_bank_read_all"
  on public.question_bank for select
  using (auth.uid() is not null);

-- Sin políticas de escritura: solo service_role (Edge Function) puede insertar.
