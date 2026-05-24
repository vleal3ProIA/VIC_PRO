-- ============================================================================
-- 0058_exam.sql · Fecha de examen + chuleta "modo pánico" (Fase 3)
-- ----------------------------------------------------------------------------
-- `subjects.exam_date` permite una cuenta atrás y calcular el ritmo de estudio.
-- `cram_sheets` cachea una chuleta ultra-condensada (lo imprescindible) por
-- temario, generada por IA bajo demanda. Todo RLS por propietario.
-- ============================================================================

alter table public.subjects
  add column if not exists exam_date date;

create table if not exists public.cram_sheets (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  content    text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (subject_id)
);

drop trigger if exists cram_sheets_set_updated_at on public.cram_sheets;
create trigger cram_sheets_set_updated_at
  before update on public.cram_sheets
  for each row execute function public.set_updated_at();

alter table public.cram_sheets enable row level security;

drop policy if exists "cram_sheets_owner_all" on public.cram_sheets;
create policy "cram_sheets_owner_all"
  on public.cram_sheets for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
