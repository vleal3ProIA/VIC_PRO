-- ============================================================================
-- 0104 · RPC claim_queued_emails (drainer atomico)
-- ----------------------------------------------------------------------------
-- Soporte para la EF `email-drain` y `processEmailQueue()` en _shared/email.ts
-- (introducidos en M3 / migracion 0102).
--
-- La RPC hace SELECT ... FOR UPDATE SKIP LOCKED + UPDATE en una sola
-- transaccion atomica para que dos drainers concurrentes NUNCA reclamen el
-- mismo email. Marca temporalmente `attempts = attempts + 1` para que un
-- crash del drainer no deje filas locked para siempre (al siguiente paso
-- volveran a estar disponibles cuando el next_try_at se cumpla).
--
-- Comportamiento:
--   - Solo lee filas con status='queued' Y (next_try_at IS NULL OR next_try_at <= now()).
--   - Ordena por created_at ASC para mantener FIFO (fairness en momentos de pico).
--   - SKIP LOCKED garantiza que multiples drainers paralelos NO bloqueen ni
--     procesen el mismo email.
--   - Devuelve las filas reclamadas; el caller (processEmailQueue) las envia
--     via SMTP y marca sent/failed.
-- ============================================================================

create or replace function public.claim_queued_emails(p_batch int default 20)
returns table (
  id         uuid,
  to_email   text,
  subject    text,
  html_body  text,
  text_body  text,
  attempts   int
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    select e.id
    from public.email_log e
    where e.status = 'queued'
      and (e.next_try_at is null or e.next_try_at <= now())
    order by e.created_at asc
    limit greatest(1, least(p_batch, 100))
    for update skip locked
  )
  update public.email_log target
     set attempts = target.attempts + 1
    from claimed
   where target.id = claimed.id
  returning target.id, target.to_email, target.subject,
            target.html_body, target.text_body, target.attempts - 1;
end;
$$;

revoke all on function public.claim_queued_emails(int) from public;
-- Solo service_role la invoca (desde _shared/email.ts).

comment on function public.claim_queued_emails(int) is
  'Reclama atomicamente un lote de emails queued para el drainer (FOR UPDATE SKIP LOCKED). Incrementa attempts.';
