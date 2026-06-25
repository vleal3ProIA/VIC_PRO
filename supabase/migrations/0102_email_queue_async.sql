-- ============================================================================
-- 0102 · Email queue asincrono (anti cuello de botella en signup)
-- ----------------------------------------------------------------------------
-- Hasta ahora `auth-email-hook` enviaba el email SINCRONAMENTE dentro de la
-- transaccion del signup: abre conexion SMTP, espera la respuesta del
-- servidor de correo, cierra. Con SMTP de Dondominio (5-20 conexiones
-- simultaneas max) y cientos de signups paralelos, el hook se atascaba ->
-- 500 -> Supabase devolvia "Database error saving new user" al user.
--
-- Solucion: el hook ahora SOLO encola el email en `email_log` con
-- status='queued' y devuelve 200 inmediato. Un drainer (EF `email-drain`,
-- llamado por pg_cron cada minuto) procesa la cola con concurrencia
-- limitada, reusa conexiones SMTP y marca sent/failed.
--
-- Para ello necesitamos guardar EL CUERPO del email en email_log (antes solo
-- guardabamos el asunto): el drainer se ejecuta despues, sin el contexto
-- que tenia el hook. Anyadimos `html_body`, `text_body`, `attempts` (para
-- limitar reintentos) y `last_error` (debug). El cuerpo se vacia tras
-- enviar OK -> ahorra espacio. La purga periodica elimina filas sent > 30d.
-- ============================================================================

alter table public.email_log
  add column if not exists html_body  text,
  add column if not exists text_body  text,
  add column if not exists attempts   int  not null default 0,
  add column if not exists last_error text,
  add column if not exists next_try_at timestamptz;

-- Indice parcial para que el drainer encuentre rapido los emails queued
-- sin escanear toda la tabla (que crece sin limite con sent/failed).
create index if not exists email_log_queue_idx
  on public.email_log (created_at)
  where status = 'queued';

comment on column public.email_log.html_body is
  'Cuerpo HTML del email. Se rellena al encolar y se VACIA tras envio OK para ahorrar espacio.';
comment on column public.email_log.text_body is
  'Cuerpo plano del email. Se vacia tras envio OK.';
comment on column public.email_log.attempts is
  'Numero de intentos de envio SMTP. El drainer reintenta hasta 3 antes de marcar failed permanente.';
comment on column public.email_log.next_try_at is
  'Si esta seteado y > now(), el drainer salta este email (backoff exponencial entre reintentos).';
