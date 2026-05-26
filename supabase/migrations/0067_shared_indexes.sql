-- ============================================================================
-- 0067_shared_indexes.sql · Índices clonables + registro legal de cesión
-- ----------------------------------------------------------------------------
-- `shared_indexes`: el ÁRBOL del índice ya generado de un temario, indexado por
-- la HUELLA del documento (`doc_fingerprint`). Si otro usuario (o el mismo, tras
-- borrar) sube un documento idéntico, se CLONA este árbol sin volver a gastar
-- IA (el texto de cada hoja se recupera de `shared_sections`).
--
-- `shared_contributions`: registro PERMANENTE de quién declaró un temario como
-- material libre (email + fecha/hora), como protección ante reclamaciones de
-- copyright. Sobrevive al borrado de la cuenta: `user_id` se pone a NULL pero el
-- `user_email` queda como snapshot. Solo el backend (service_role) lo lee.
-- ============================================================================

create table if not exists public.shared_indexes (
  doc_fingerprint text primary key,
  title         text,
  lang          text,
  -- Árbol serializado: array de nodos en orden (padres antes que hijos), cada
  -- uno { i, parent, title, depth, position, leaf, hash }.
  nodes         jsonb not null,
  times_reused  int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

drop trigger if exists shared_indexes_set_updated_at on public.shared_indexes;
create trigger shared_indexes_set_updated_at
  before update on public.shared_indexes
  for each row execute function public.set_updated_at();

alter table public.shared_indexes enable row level security;
-- Sin políticas: solo service_role (Edge Functions). El cliente nunca lo lee.

-- ─────────────────── Registro legal de cesión (compliance) ───────────────────
create table if not exists public.shared_contributions (
  id             uuid primary key default gen_random_uuid(),
  -- Sin FK dura al temario: puede borrarse y el registro debe permanecer.
  subject_id     uuid,
  -- Al borrar la cuenta se pone a NULL, pero el email (snapshot) permanece.
  user_id        uuid references auth.users(id) on delete set null,
  user_email     text not null,
  subject_title  text,
  sections_count int  not null default 0,
  declared_at    timestamptz not null default now()
);

create unique index if not exists shared_contributions_subject_uidx
  on public.shared_contributions (subject_id)
  where subject_id is not null;
create index if not exists shared_contributions_user_idx
  on public.shared_contributions (user_id);

alter table public.shared_contributions enable row level security;
-- Sin políticas: log interno, solo service_role escribe/lee.
