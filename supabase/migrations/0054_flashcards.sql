-- ============================================================================
-- 0054_flashcards.sql · Flashcards con repaso espaciado (Fase 3)
-- ----------------------------------------------------------------------------
-- Tarjetas pregunta/respuesta generadas por IA a partir del temario (o de una
-- sección). Incluye campos de repaso espaciado tipo SM-2 (ease/intervalo/due)
-- que se actualizan en cada repaso para ordenar "lo que toca estudiar".
--
-- `node_id` nulo = tarjeta del temario completo; si apunta a un nodo, es de esa
-- sección. Todo RLS por propietario. La Edge Function de generación usa
-- service_role.
-- ============================================================================

create table if not exists public.flashcards (
  id               uuid primary key default gen_random_uuid(),
  subject_id       uuid not null references public.subjects(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  node_id          uuid references public.index_nodes(id) on delete set null,
  front            text not null,
  back             text not null,
  -- Repaso espaciado (SM-2 lite).
  ease             real not null default 2.5,
  interval_days    int  not null default 0,
  reps             int  not null default 0,
  lapses           int  not null default 0,
  due_at           timestamptz not null default now(),
  last_reviewed_at timestamptz,
  created_at       timestamptz not null default now()
);

create index if not exists flashcards_subject_idx on public.flashcards (subject_id);
create index if not exists flashcards_due_idx on public.flashcards (user_id, due_at);

alter table public.flashcards enable row level security;

drop policy if exists "flashcards_owner_all" on public.flashcards;
create policy "flashcards_owner_all"
  on public.flashcards for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
