-- ============================================================================
-- 0053_index_lock.sql · Validación / bloqueo del índice (Fase 2)
-- ----------------------------------------------------------------------------
-- Una vez el usuario VALIDA el índice generado, no se podrá volver a regenerar.
-- `subjects.index_locked` lo marca; la Edge Function `generate-index` lo respeta
-- (rechaza regenerar si está bloqueado) y la UI oculta el botón de regenerar.
--
-- Antes de validar, el usuario aún puede regenerar (por si el índice salió mal).
-- RLS de subjects (propietario) ya cubre el UPDATE desde el cliente.
-- ============================================================================

alter table public.subjects
  add column if not exists index_locked boolean not null default false;

alter table public.subjects
  add column if not exists index_locked_at timestamptz;
