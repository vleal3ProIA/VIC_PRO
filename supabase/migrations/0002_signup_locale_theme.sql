-- ============================================================================
-- 0002 · handle_new_user: capturar idioma y tema en el registro
-- ----------------------------------------------------------------------------
-- Problema: el trigger original creaba el perfil con `locale = 'en'` (el
-- default de la columna), ignorando el idioma que el usuario estaba usando al
-- registrarse. Al iniciar sesión, la app aplicaba ese 'en' y cambiaba el
-- idioma a inglés sin que el usuario lo pidiera.
--
-- Solución: la app ahora envía `locale` y `theme_mode` en el metadata del
-- signUp. Este trigger los lee y los valida contra los valores permitidos
-- (si llega algo inesperado, cae al default para no romper el CHECK).
--
-- Aplicar:
--   - Dashboard: SQL Editor → New query → pegar este archivo → Run.
--   - CLI:       supabase db push
-- ============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_locale text;
  v_theme  text;
begin
  v_locale := new.raw_user_meta_data->>'locale';
  v_theme  := new.raw_user_meta_data->>'theme_mode';

  insert into public.profiles (id, username, display_name, locale, theme_mode)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'username',
      split_part(new.email, '@', 1)
    ),
    coalesce(
      new.raw_user_meta_data->>'display_name',
      new.raw_user_meta_data->>'username'
    ),
    -- Solo aceptamos un idioma soportado; si no, default 'en'.
    coalesce(
      case
        when v_locale in ('es','en','de','fr','it','pt','ru','uk')
        then v_locale
      end,
      'en'
    ),
    -- Solo aceptamos un theme válido; si no, default 'system'.
    coalesce(
      case
        when v_theme in ('system','light','dark')
        then v_theme
      end,
      'system'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- El trigger `on_auth_user_created` (definido en 0001) sigue igual: solo
-- reemplazamos el cuerpo de la función.
