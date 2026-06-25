-- ============================================================================
-- 0100 · CHECK constraint: saved_tests.title entre 1 y 200 caracteres
-- ----------------------------------------------------------------------------
-- Hasta ahora `title` era TEXT sin limite. Si el usuario lo renombrara con
-- 50KB de texto pegado, romperia el layout de la lista en la UI y costaria
-- mas a cada SELECT. Anyadimos un CHECK basico (el cliente ya pone
-- maxLength: 120 en el rename dialog, pero la BD es la fuente de verdad).
-- ============================================================================

alter table public.saved_tests
  drop constraint if exists saved_tests_title_len_check;

alter table public.saved_tests
  add constraint saved_tests_title_len_check
  check (char_length(title) between 1 and 200);
