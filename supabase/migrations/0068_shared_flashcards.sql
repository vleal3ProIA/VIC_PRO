-- ============================================================================
-- 0068_shared_flashcards.sql · Flashcards GLOBALes por content_hash (Fase 5)
-- ----------------------------------------------------------------------------
-- Como `question_bank` y `shared_node_content`, reutilizamos las flashcards
-- generadas de una sección por el hash de su texto: misma sección (mismo o muy
-- parecido texto) -> mismas tarjetas, sin volver a gastar IA.
--
-- Solo aplica al generar flashcards de UNA sección (con texto propio). El lote
-- "de todo el temario" no tiene un único hash, así que no se cachea aquí.
--
-- Lectura: cualquier usuario autenticado. Escritura: solo service_role (EF).
-- ============================================================================

create table if not exists public.shared_flashcards (
  id           uuid primary key default gen_random_uuid(),
  content_hash text not null,
  front        text not null,
  back         text not null,
  lang         text,
  created_at   timestamptz not null default now()
);

create index if not exists shared_flashcards_hash_idx
  on public.shared_flashcards (content_hash);

alter table public.shared_flashcards enable row level security;

drop policy if exists "shared_flashcards_read_all" on public.shared_flashcards;
create policy "shared_flashcards_read_all"
  on public.shared_flashcards for select
  using (auth.uid() is not null);

-- Sin políticas de escritura: solo service_role (Edge Function) escribe.
