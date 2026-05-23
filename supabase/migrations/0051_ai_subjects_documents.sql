-- ============================================================================
-- 0051_ai_subjects_documents.sql · Ingesta de temarios (Fase 1)
-- ----------------------------------------------------------------------------
-- `subjects`  -> un temario del usuario (lo que en NotebookLM seria un
--                "notebook"): titulo, idioma, estado.
-- `documents` -> cada archivo subido a un temario (PDF/imagen/DOCX/texto),
--                su ubicacion en Storage, estado de ingesta y el texto
--                extraido por la IA (visión nativa).
--
-- Bucket de Storage privado `temarios` con convenio de path
-- `{user_id}/{subject_id}/{archivo}` y RLS por carpeta de usuario (mismo
-- patron que `user-uploads`, migracion 0023).
--
-- Copyright/GDPR: el ORIGINAL con copyright NO se conserva a largo plazo. El
-- `extracted_text` y los artefactos generados (índices/resúmenes/preguntas,
-- fases siguientes) sí se conservan anonimizados. `user_id` con ON DELETE
-- CASCADE: al borrar la cuenta se eliminan sus temarios y archivos; los
-- artefactos generados (tablas de fases posteriores) se desvincularán.
-- ============================================================================

-- ─────────────────────────── subjects (temarios) ─────────────────────────────
create table if not exists public.subjects (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  title       text not null,
  description text,
  language    text,                              -- 'es', 'en', ... (idioma del temario)
  status      text not null default 'active'
              check (status in ('active', 'archived')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists subjects_user_idx on public.subjects (user_id);

drop trigger if exists subjects_set_updated_at on public.subjects;
create trigger subjects_set_updated_at
  before update on public.subjects
  for each row execute function public.set_updated_at();

-- ─────────────────────────── documents (archivos) ────────────────────────────
create table if not exists public.documents (
  id             uuid primary key default gen_random_uuid(),
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  -- `user_id` denormalizado (= subjects.user_id) para simplificar RLS y el
  -- convenio de path en Storage. Se rellena en el insert desde el cliente.
  user_id        uuid not null references auth.users(id) on delete cascade,
  storage_path   text not null,                  -- ruta en el bucket 'temarios'
  file_name      text,
  mime_type      text,
  size_bytes     bigint,
  page_count     int,
  status         text not null default 'queued'
                 check (status in ('queued', 'processing', 'ready', 'failed')),
  error          text,                            -- detalle si status='failed'
  extracted_text text,                            -- texto extraido por la IA
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists documents_subject_idx on public.documents (subject_id);
create index if not exists documents_user_idx on public.documents (user_id);

drop trigger if exists documents_set_updated_at on public.documents;
create trigger documents_set_updated_at
  before update on public.documents
  for each row execute function public.set_updated_at();

-- ─────────────────────────────── RLS ─────────────────────────────────────────
-- Propietario gestiona sus temarios y documentos. La Edge Function de ingesta
-- usa service_role y salta RLS. (El navegador de contenido para admins, con
-- capability `view_ai_content`, se anyadira sobre los artefactos GENERADOS en
-- fases posteriores; el ORIGINAL con copyright permanece solo del propietario.)
alter table public.subjects  enable row level security;
alter table public.documents enable row level security;

drop policy if exists "subjects_owner_all" on public.subjects;
create policy "subjects_owner_all"
  on public.subjects for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "documents_owner_all" on public.documents;
create policy "documents_owner_all"
  on public.documents for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ─────────────────── ai_usage.subject_id -> FK a subjects ────────────────────
-- En 0050 quedo como uuid sin FK (subjects aun no existia). Ahora lo atamos.
alter table public.ai_usage
  drop constraint if exists ai_usage_subject_fk;
alter table public.ai_usage
  add constraint ai_usage_subject_fk
  foreign key (subject_id) references public.subjects(id) on delete set null;

-- ─────────────────── Bucket de Storage privado `temarios` ─────────────────────
-- Privado, 50 MB por archivo. Convenio de path: `{user_id}/{subject_id}/...`.
insert into storage.buckets (id, name, public, file_size_limit)
values ('temarios', 'temarios', false, 52428800)
on conflict (id) do nothing;

-- Policies de storage.objects para el bucket 'temarios': cada usuario solo
-- toca archivos dentro de SU carpeta (primer segmento del path = su uid).
drop policy if exists "temarios_select_own" on storage.objects;
create policy "temarios_select_own"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "temarios_insert_own" on storage.objects;
create policy "temarios_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "temarios_update_own" on storage.objects;
create policy "temarios_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "temarios_delete_own" on storage.objects;
create policy "temarios_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
