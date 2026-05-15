-- ============================================================================
-- 0007 · Rate limiting para Edge Functions sensibles
-- ----------------------------------------------------------------------------
-- Tabla + función SQL para limitar la frecuencia de invocaciones a las Edge
-- Functions (`delete-account`, `mfa-recovery`, `webauthn`).
--
-- ¿Por qué en BD y no en memoria?
--   Las Edge Functions son stateless: cada invocación puede correr en una
--   instancia distinta. Necesitamos un contador compartido entre ellas. La
--   BD es el lugar natural (y barato — son muy pocas filas).
--
-- Modelo: sliding window. Cada operación inserta una fila con el `bucket_key`
-- (combinación acción + usuario/IP). La función `check_rate_limit` cuenta
-- las filas en la ventana reciente: si supera el `limit`, devuelve `false`
-- (la Edge Function responde 429); si no, inserta y devuelve `true`.
--
-- RLS bloqueada por completo: solo accesible vía service_role.
-- ============================================================================

create table if not exists public.edge_rate_limits (
  id          uuid primary key default gen_random_uuid(),
  bucket_key  text not null,
  used_at     timestamptz not null default now()
);

-- Índice compuesto para que el "count en los últimos N segundos" sea barato.
create index if not exists edge_rate_limits_bucket_time_idx
  on public.edge_rate_limits (bucket_key, used_at desc);

alter table public.edge_rate_limits enable row level security;
-- Sin policies → bloqueada para usuarios; la service_role la usa libremente.

-- Función atómica: cuenta usos recientes y, si no se ha pasado del límite,
-- registra esta invocación. Devuelve `true` cuando se permite la llamada,
-- `false` cuando hay que rechazarla.
create or replace function public.check_rate_limit(
  p_bucket_key      text,
  p_limit           int,
  p_window_seconds  int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  select count(*) into v_count
  from public.edge_rate_limits
  where bucket_key = p_bucket_key
    and used_at > now() - make_interval(secs => p_window_seconds);

  if v_count >= p_limit then
    return false;
  end if;

  insert into public.edge_rate_limits (bucket_key) values (p_bucket_key);
  return true;
end;
$$;

-- Limpieza periódica (manual o vía pg_cron si está disponible). Elimina
-- entradas con más de 7 días — más allá no sirven para ninguna ventana.
create or replace function public.cleanup_edge_rate_limits()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.edge_rate_limits
  where used_at < now() - interval '7 days';
$$;
