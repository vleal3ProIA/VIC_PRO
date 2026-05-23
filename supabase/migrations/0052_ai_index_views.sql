-- ============================================================================
-- 0052_ai_index_views.sql · Índice + 3 vistas + anotaciones (Fase 2)
-- ----------------------------------------------------------------------------
-- `index_nodes`  -> índice jerárquico del temario (árbol con parent_id).
-- `node_content` -> las 3 vistas por nodo: original / explained / summary.
--                   'original' se llena al generar el índice; 'explained' y
--                   'summary' se generan bajo demanda y se cachean (1 fila por
--                   (node_id, kind)).
-- `annotations`  -> notas del usuario, opcionalmente ligadas a un nodo.
--
-- `subjects.index_status` rastrea la generación del índice (none/generating/
-- ready/failed) para que la UI muestre estado + polling.
--
-- Todo RLS por propietario. La Edge Function de generación usa service_role.
-- ============================================================================

-- Estado de generación del índice en el temario.
alter table public.subjects
  add column if not exists index_status text not null default 'none';
-- (CHECK aparte para que `add column if not exists` no falle si ya existía.)
alter table public.subjects
  drop constraint if exists subjects_index_status_check;
alter table public.subjects
  add constraint subjects_index_status_check
  check (index_status in ('none', 'generating', 'ready', 'failed'));

-- ─────────────────────────── index_nodes ─────────────────────────────────────
create table if not exists public.index_nodes (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  parent_id  uuid references public.index_nodes(id) on delete cascade,
  title      text not null,
  position   int not null default 0,  -- orden entre hermanos
  depth      int not null default 0,  -- 0 = nivel superior
  created_at timestamptz not null default now()
);
create index if not exists index_nodes_subject_idx on public.index_nodes (subject_id);
create index if not exists index_nodes_parent_idx on public.index_nodes (parent_id);

-- ─────────────────────────── node_content ────────────────────────────────────
create table if not exists public.node_content (
  id         uuid primary key default gen_random_uuid(),
  node_id    uuid not null references public.index_nodes(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('original', 'explained', 'summary')),
  content    text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (node_id, kind)
);
create index if not exists node_content_node_idx on public.node_content (node_id);

drop trigger if exists node_content_set_updated_at on public.node_content;
create trigger node_content_set_updated_at
  before update on public.node_content
  for each row execute function public.set_updated_at();

-- ─────────────────────────── annotations ─────────────────────────────────────
create table if not exists public.annotations (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  node_id    uuid references public.index_nodes(id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists annotations_subject_idx on public.annotations (subject_id);

drop trigger if exists annotations_set_updated_at on public.annotations;
create trigger annotations_set_updated_at
  before update on public.annotations
  for each row execute function public.set_updated_at();

-- ─────────────────────────────── RLS ─────────────────────────────────────────
alter table public.index_nodes  enable row level security;
alter table public.node_content enable row level security;
alter table public.annotations  enable row level security;

drop policy if exists "index_nodes_owner_all" on public.index_nodes;
create policy "index_nodes_owner_all"
  on public.index_nodes for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "node_content_owner_all" on public.node_content;
create policy "node_content_owner_all"
  on public.node_content for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "annotations_owner_all" on public.annotations;
create policy "annotations_owner_all"
  on public.annotations for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
