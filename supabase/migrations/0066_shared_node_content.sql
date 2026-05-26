-- ============================================================================
-- 0066_shared_node_content.sql · Vistas (explicado/resumen) GLOBALes por hash
-- ----------------------------------------------------------------------------
-- Igual que `question_bank` reutiliza preguntas por `content_hash`, aquí
-- reutilizamos las vistas didácticas generadas (explicado / resumen) de una
-- sección: si dos secciones tienen el MISMO texto (mismo hash), comparten la
-- misma explicación y resumen, sin volver a gastar IA.
--
-- `generate-views` consulta esta tabla ANTES de llamar al modelo; si encuentra
-- la vista, la copia a la `node_content` del usuario (0 tokens). Cuando genera
-- una nueva y el temario es de material libre (`subjects.shareable`), la
-- aporta aquí.
--
-- Lectura: cualquier usuario autenticado. Escritura: solo service_role (EF).
-- ============================================================================

create table if not exists public.shared_node_content (
  content_hash text not null,
  kind         text not null check (kind in ('explained', 'summary')),
  content      text not null,
  lang         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (content_hash, kind)
);

create index if not exists shared_node_content_hash_idx
  on public.shared_node_content (content_hash);

drop trigger if exists shared_node_content_set_updated_at
  on public.shared_node_content;
create trigger shared_node_content_set_updated_at
  before update on public.shared_node_content
  for each row execute function public.set_updated_at();

alter table public.shared_node_content enable row level security;

drop policy if exists "shared_node_content_read_all" on public.shared_node_content;
create policy "shared_node_content_read_all"
  on public.shared_node_content for select
  using (auth.uid() is not null);

-- Sin políticas de escritura: solo service_role (Edge Function) escribe.
