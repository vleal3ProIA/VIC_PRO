-- ============================================================================
-- 0063_index_error.sql · Motivo del fallo al generar el índice
-- ----------------------------------------------------------------------------
-- Hasta ahora, si la generación del índice fallaba solo quedaba
-- `index_status = 'failed'` sin explicación visible para el usuario. Guardamos
-- el motivo real (mensaje del proveedor de IA, "empty_index", etc.) para
-- mostrarlo en el asistente y poder diagnosticar.
-- ============================================================================

alter table public.subjects
  add column if not exists index_error text;
