-- ============================================================================
-- 0057_study_guides.sql · Guía de estudio por temario (Fase 3)
-- ----------------------------------------------------------------------------
-- Guía/esquema estructurado (Markdown) del temario completo, generado por IA y
-- cacheado (1 por temario). Todo RLS por propietario; la Edge Function de
-- generación usa service_role.
-- ============================================================================

create table if not exists public.study_guides (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  content    text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (subject_id)
);

drop trigger if exists study_guides_set_updated_at on public.study_guides;
create trigger study_guides_set_updated_at
  before update on public.study_guides
  for each row execute function public.set_updated_at();

alter table public.study_guides enable row level security;

drop policy if exists "study_guides_owner_all" on public.study_guides;
create policy "study_guides_owner_all"
  on public.study_guides for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
