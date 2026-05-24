-- ============================================================================
-- 0056_chat_messages.sql · Historial del chat por temario (Fase 3)
-- ----------------------------------------------------------------------------
-- Guarda la conversación del chat de cada temario para que NO se pierda al
-- recargar. `role` = 'user' | 'assistant'. Todo RLS por propietario; la Edge
-- Function de chat NO escribe aquí (lo hace el cliente, que ya tiene RLS).
-- ============================================================================

create table if not exists public.chat_messages (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null check (role in ('user', 'assistant')),
  content    text not null,
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_subject_idx
  on public.chat_messages (subject_id, created_at);

alter table public.chat_messages enable row level security;

drop policy if exists "chat_messages_owner_all" on public.chat_messages;
create policy "chat_messages_owner_all"
  on public.chat_messages for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
