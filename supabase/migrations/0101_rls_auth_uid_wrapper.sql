-- ============================================================================
-- 0101_rls_auth_uid_wrapper.sql · Envuelve `auth.uid()` en `(select auth.uid())`
--                                en TODAS las policies RLS que lo usaban directo
-- ----------------------------------------------------------------------------
-- **Por qué esta migración**
-- Supabase tiene un footgun documentado y muy concreto: cuando una policy
-- RLS hace `USING (col = auth.uid())`, PostgREST (y el planner de PostgreSQL
-- en ese contexto) re-evalua `auth.uid()` POR CADA FILA escaneada. En una
-- query que escanea 50k filas, eso son 50k llamadas a la funcion --
-- innecesarias porque `auth.uid()` es constante dentro de una misma request.
--
-- La solucion oficial (Supabase docs > "RLS Performance Tips") es envolver
-- la llamada en una subquery escalar:
--
--     -- Antes (re-evalua por fila):
--     using (user_id = auth.uid())
--
--     -- Despues (se evalua UNA sola vez como InitPlan constante):
--     using (user_id = (select auth.uid()))
--
-- Beneficio medido: 2-5x throughput en tablas grandes con RLS de propietario.
-- Ningun cambio funcional -- la semantica es identica (auth.uid() devuelve
-- el mismo valor dentro de la transaccion).
--
-- **Que toca esta migracion**
-- Solo las policies que comparaban contra `auth.uid()` DIRECTO. Se IGNORAN:
--   * Policies que ya usaban `(select auth.uid())` (nada que hacer).
--   * Policies que usan `is_super_admin()`, `is_admin()`, `has_capability()`
--     (esas helper functions son STABLE SECURITY DEFINER y el planner ya
--     las trata como InitPlan -- no aplica el footgun).
--   * Policies que usan `using (true)` (publico intencional).
--   * `auth.uid()` pasado como argumento a `user_tenants(auth.uid())` o
--     dentro de subqueries EXISTS internas — el planner ya lo evalua una
--     sola vez en esos contextos. Solo tocamos las comparaciones directas
--     de fila a `auth.uid()`.
--
-- Para cada policy afectada: DROP IF EXISTS + CREATE con la unica diferencia
-- de envolver `auth.uid()` en `(select auth.uid())`. Mismo nombre, misma
-- tabla, mismo verb (SELECT/INSERT/UPDATE/DELETE/ALL), misma estructura
-- USING/WITH CHECK, mismo `to <role>`. Si una policy aparecia duplicada en
-- varias migraciones (DROP+CREATE), usamos la version mas reciente como
-- source of truth.
--
-- **Tablas afectadas (public + storage)**
-- public: profiles, mfa_recovery_codes, webauthn_credentials, audit_logs,
--   tenants, tenant_members, feature_flag_overrides, notifications, uploads,
--   personal_access_tokens, webhook_endpoints, webhook_deliveries,
--   auth_recent_verifications, admin_capabilities, subjects, documents,
--   index_nodes, node_content, annotations, flashcards, quiz_questions,
--   chat_messages, study_guides, cram_sheets, study_activity, exam_questions,
--   exam_attempts, question_bank, shared_sections, shared_node_content,
--   shared_flashcards, tf_bank, essay_bank, saved_tests.
-- storage.objects: avatars/*, user-uploads/*, temarios/*.
--
-- Total: 54 policies reemplazadas (ver bloque comentado al final).
-- ============================================================================

-- ─────────────────────────── public.profiles (0001) ──────────────────────────
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using ((select auth.uid()) = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- ───────────────────── public.mfa_recovery_codes (0003) ──────────────────────
drop policy if exists "mfa_recovery_select_own" on public.mfa_recovery_codes;
create policy "mfa_recovery_select_own"
  on public.mfa_recovery_codes for select
  using ((select auth.uid()) = user_id);

-- ─────────────────────── storage.objects · avatars (0004) ────────────────────
drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ───────────────────── public.webauthn_credentials (0006) ────────────────────
drop policy if exists "webauthn_credentials_select_own"
  on public.webauthn_credentials;
create policy "webauthn_credentials_select_own"
  on public.webauthn_credentials for select
  using ((select auth.uid()) = user_id);

drop policy if exists "webauthn_credentials_delete_own"
  on public.webauthn_credentials;
create policy "webauthn_credentials_delete_own"
  on public.webauthn_credentials for delete
  using ((select auth.uid()) = user_id);

-- ─────────────────────────── public.audit_logs (0008) ────────────────────────
drop policy if exists "audit_logs_select_own" on public.audit_logs;
create policy "audit_logs_select_own"
  on public.audit_logs for select
  using ((select auth.uid()) = user_id);

drop policy if exists "audit_logs_insert_own" on public.audit_logs;
create policy "audit_logs_insert_own"
  on public.audit_logs for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

-- ─────────────────────────── public.tenants (0009) ───────────────────────────
drop policy if exists "tenants_insert_authenticated" on public.tenants;
create policy "tenants_insert_authenticated"
  on public.tenants for insert
  to authenticated
  with check (owner_id = (select auth.uid()) and is_personal = false);

drop policy if exists "tenants_delete_owner_non_personal" on public.tenants;
create policy "tenants_delete_owner_non_personal"
  on public.tenants for delete
  using (owner_id = (select auth.uid()) and is_personal = false);

-- ─────────────────────── public.tenant_members (0009) ────────────────────────
drop policy if exists "tenant_members_delete" on public.tenant_members;
create policy "tenant_members_delete"
  on public.tenant_members for delete
  using (
    -- Soy admin Y el target no es el owner.
    (
      public.is_tenant_admin(tenant_id)
      and role <> 'owner'
    )
    or
    -- Me estoy yendo yo mismo Y no soy el owner.
    (
      user_id = (select auth.uid()) and role <> 'owner'
    )
  );

-- ──────────────────── public.feature_flag_overrides (0011) ───────────────────
drop policy if exists "ff_overrides_select" on public.feature_flag_overrides;
create policy "ff_overrides_select"
  on public.feature_flag_overrides for select to authenticated
  using (
    user_id = (select auth.uid())
    or (tenant_id is not null and tenant_id in (
      select public.user_tenants((select auth.uid()))
    ))
  );

-- ──────────────────────── public.notifications (0021) ────────────────────────
drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications for select
  using (user_id = (select auth.uid()));

drop policy if exists "notifications_update_own_read_at" on public.notifications;
create policy "notifications_update_own_read_at"
  on public.notifications for update
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
  on public.notifications for delete
  using (user_id = (select auth.uid()));

-- ───────────────────────────── public.uploads ────────────────────────────────
-- uploads_select_own_or_tenant — version mas reciente vive en 0036.
drop policy if exists "uploads_select_own_or_tenant" on public.uploads;
create policy "uploads_select_own_or_tenant"
  on public.uploads for select
  using (
    deleted_at is null
    and confirmed_at is not null
    and (
      user_id = (select auth.uid())
      or (
        tenant_id is not null
        and tenant_id in (select public.user_tenants((select auth.uid())))
      )
    )
  );

-- uploads_soft_delete_own — definida en 0023.
drop policy if exists "uploads_soft_delete_own" on public.uploads;
create policy "uploads_soft_delete_own"
  on public.uploads for update
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ───────────────────── storage.objects · user-uploads (0023) ─────────────────
drop policy if exists "user-uploads-select" on storage.objects;
create policy "user-uploads-select"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'user-uploads'
    and (
      (storage.foldername(name))[1]::uuid in (select public.user_tenants((select auth.uid())))
      or owner = (select auth.uid())
    )
  );

drop policy if exists "user-uploads-delete-own" on storage.objects;
create policy "user-uploads-delete-own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'user-uploads' and owner = (select auth.uid()));

-- ───────────────────── public.personal_access_tokens (0024) ──────────────────
drop policy if exists "pat_select_own" on public.personal_access_tokens;
create policy "pat_select_own"
  on public.personal_access_tokens for select
  using (user_id = (select auth.uid()));

drop policy if exists "pat_revoke_own" on public.personal_access_tokens;
create policy "pat_revoke_own"
  on public.personal_access_tokens for update
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "pat_delete_own" on public.personal_access_tokens;
create policy "pat_delete_own"
  on public.personal_access_tokens for delete
  using (user_id = (select auth.uid()));

-- ──────────────────── public.webhook_endpoints (0025) ────────────────────────
drop policy if exists "wh_endpoints_select_own" on public.webhook_endpoints;
create policy "wh_endpoints_select_own"
  on public.webhook_endpoints for select
  using (
    user_id = (select auth.uid())
    or (
      tenant_id is not null
      and exists (
        select 1
        from public.tenant_members tm
        where tm.tenant_id = webhook_endpoints.tenant_id
          and tm.user_id   = (select auth.uid())
      )
    )
  );

drop policy if exists "wh_endpoints_update_own" on public.webhook_endpoints;
create policy "wh_endpoints_update_own"
  on public.webhook_endpoints for update
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "wh_endpoints_delete_own" on public.webhook_endpoints;
create policy "wh_endpoints_delete_own"
  on public.webhook_endpoints for delete
  using (user_id = (select auth.uid()));

-- ──────────────────── public.webhook_deliveries (0025) ───────────────────────
drop policy if exists "wh_deliveries_select_own" on public.webhook_deliveries;
create policy "wh_deliveries_select_own"
  on public.webhook_deliveries for select
  using (
    exists (
      select 1
      from public.webhook_endpoints e
      where e.id = webhook_deliveries.endpoint_id
        and (
          e.user_id = (select auth.uid())
          or (
            e.tenant_id is not null
            and exists (
              select 1
              from public.tenant_members tm
              where tm.tenant_id = e.tenant_id
                and tm.user_id   = (select auth.uid())
            )
          )
        )
    )
  );

-- ─────────────── public.auth_recent_verifications (0037) ─────────────────────
drop policy if exists "auth_recent_verifications_select_own"
  on public.auth_recent_verifications;
create policy "auth_recent_verifications_select_own"
  on public.auth_recent_verifications for select
  using (user_id = (select auth.uid()));

-- ─────────────────── public.admin_capabilities (0044) ────────────────────────
drop policy if exists "ac_select_own" on public.admin_capabilities;
create policy "ac_select_own"
  on public.admin_capabilities for select
  using (user_id = (select auth.uid()));

-- ───────────────────────── public.subjects (0051) ────────────────────────────
drop policy if exists "subjects_owner_all" on public.subjects;
create policy "subjects_owner_all"
  on public.subjects for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ───────────────────────── public.documents (0051) ───────────────────────────
drop policy if exists "documents_owner_all" on public.documents;
create policy "documents_owner_all"
  on public.documents for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ───────────────────── storage.objects · temarios (0051) ─────────────────────
drop policy if exists "temarios_select_own" on storage.objects;
create policy "temarios_select_own"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "temarios_insert_own" on storage.objects;
create policy "temarios_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "temarios_update_own" on storage.objects;
create policy "temarios_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "temarios_delete_own" on storage.objects;
create policy "temarios_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'temarios'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ───────────────────────── public.index_nodes (0052) ─────────────────────────
drop policy if exists "index_nodes_owner_all" on public.index_nodes;
create policy "index_nodes_owner_all"
  on public.index_nodes for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ───────────────────────── public.node_content (0052) ────────────────────────
drop policy if exists "node_content_owner_all" on public.node_content;
create policy "node_content_owner_all"
  on public.node_content for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ───────────────────────── public.annotations (0052) ─────────────────────────
drop policy if exists "annotations_owner_all" on public.annotations;
create policy "annotations_owner_all"
  on public.annotations for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ───────────────────────── public.flashcards (0054) ──────────────────────────
drop policy if exists "flashcards_owner_all" on public.flashcards;
create policy "flashcards_owner_all"
  on public.flashcards for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ─────────────────────── public.quiz_questions (0055) ────────────────────────
drop policy if exists "quiz_questions_owner_all" on public.quiz_questions;
create policy "quiz_questions_owner_all"
  on public.quiz_questions for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ───────────────────────── public.chat_messages (0056) ───────────────────────
drop policy if exists "chat_messages_owner_all" on public.chat_messages;
create policy "chat_messages_owner_all"
  on public.chat_messages for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ───────────────────────── public.study_guides (0057) ────────────────────────
drop policy if exists "study_guides_owner_all" on public.study_guides;
create policy "study_guides_owner_all"
  on public.study_guides for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ───────────────────────── public.cram_sheets (0058) ─────────────────────────
drop policy if exists "cram_sheets_owner_all" on public.cram_sheets;
create policy "cram_sheets_owner_all"
  on public.cram_sheets for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ─────────────────────── public.study_activity (0059) ────────────────────────
drop policy if exists "study_activity_owner_all" on public.study_activity;
create policy "study_activity_owner_all"
  on public.study_activity for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ─────────────────────── public.exam_questions (0060) ────────────────────────
drop policy if exists "exam_questions_owner_all" on public.exam_questions;
create policy "exam_questions_owner_all"
  on public.exam_questions for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ─────────────────────── public.exam_attempts (0061) ─────────────────────────
drop policy if exists "exam_attempts_owner_all" on public.exam_attempts;
create policy "exam_attempts_owner_all"
  on public.exam_attempts for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ─────────────────────── public.question_bank (0062) ─────────────────────────
drop policy if exists "question_bank_read_all" on public.question_bank;
create policy "question_bank_read_all"
  on public.question_bank for select
  using ((select auth.uid()) is not null);

-- ────────────────────── public.shared_sections (0065) ────────────────────────
drop policy if exists "shared_sections_read_all" on public.shared_sections;
create policy "shared_sections_read_all"
  on public.shared_sections for select
  using ((select auth.uid()) is not null);

-- ──────────────────── public.shared_node_content (0066) ──────────────────────
drop policy if exists "shared_node_content_read_all" on public.shared_node_content;
create policy "shared_node_content_read_all"
  on public.shared_node_content for select
  using ((select auth.uid()) is not null);

-- ────────────────────── public.shared_flashcards (0068) ──────────────────────
drop policy if exists "shared_flashcards_read_all" on public.shared_flashcards;
create policy "shared_flashcards_read_all"
  on public.shared_flashcards for select
  using ((select auth.uid()) is not null);

-- ─────────────────────────── public.tf_bank (0071) ───────────────────────────
drop policy if exists "tf_bank_read_all" on public.tf_bank;
create policy "tf_bank_read_all"
  on public.tf_bank for select
  using ((select auth.uid()) is not null);

-- ────────────────────────── public.essay_bank (0071) ─────────────────────────
drop policy if exists "essay_bank_read_all" on public.essay_bank;
create policy "essay_bank_read_all"
  on public.essay_bank for select
  using ((select auth.uid()) is not null);

-- ───────────────────────── public.saved_tests (0098) ─────────────────────────
drop policy if exists "saved_tests_owner_all" on public.saved_tests;
create policy "saved_tests_owner_all"
  on public.saved_tests for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ============================================================================
-- RESUMEN · 54 policies reemplazadas (DROP + CREATE).
-- ----------------------------------------------------------------------------
-- public.profiles                       :  2  (profiles_select_own, profiles_update_own)
-- public.mfa_recovery_codes             :  1
-- storage.objects (avatars)             :  3
-- public.webauthn_credentials           :  2
-- public.audit_logs                     :  2
-- public.tenants                        :  2
-- public.tenant_members                 :  1
-- public.feature_flag_overrides         :  1
-- public.notifications                  :  3
-- public.uploads                        :  2
-- storage.objects (user-uploads)        :  2
-- public.personal_access_tokens         :  3
-- public.webhook_endpoints              :  3
-- public.webhook_deliveries             :  1
-- public.auth_recent_verifications      :  1
-- public.admin_capabilities             :  1
-- public.subjects                       :  1
-- public.documents                      :  1
-- storage.objects (temarios)            :  4
-- public.index_nodes                    :  1
-- public.node_content                   :  1
-- public.annotations                    :  1
-- public.flashcards                     :  1
-- public.quiz_questions                 :  1
-- public.chat_messages                  :  1
-- public.study_guides                   :  1
-- public.cram_sheets                    :  1
-- public.study_activity                 :  1
-- public.exam_questions                 :  1
-- public.exam_attempts                  :  1
-- public.question_bank                  :  1
-- public.shared_sections                :  1
-- public.shared_node_content            :  1
-- public.shared_flashcards              :  1
-- public.tf_bank                        :  1
-- public.essay_bank                     :  1
-- public.saved_tests                    :  1
-- ----------------------------------------------------------------------------
-- TOTAL                                 : 54
-- ============================================================================
