-- ============================================================================
-- 0029 · Email log + delivery tracking
-- ----------------------------------------------------------------------------
-- Tabla de auditoria para TODOS los emails que la app envia: auth
-- (signup / recovery / magic-link / etc.), transaccionales (plan
-- changed, invoice paid, account deleted), broadcasts del admin.
--
-- Tres motivos para tenerla:
--   1) Debug ("le llegó el email al user X?")
--   2) Compliance (GDPR — registro de envios automatizados)
--   3) Soporte ("reenviame el email de bienvenida"): es facil de
--      reconstruir si tenemos el row con todos los inputs.
--
-- **Modelo**:
--   - `type`        : enum logico ('signup', 'recovery', 'magic_link',
--                     'change_email', 'invite', 'plan_changed', 'broadcast',
--                     'test')
--   - `to_email`    : destinatario (no FK a auth.users -- el email
--                     puede no estar en la tabla todavia, ej. en
--                     invites a nuevos users)
--   - `to_user_id`  : opcional, FK a auth.users si lo conocemos
--   - `locale`      : idioma del template que se renderizo
--   - `subject`     : asunto exacto enviado
--   - `status`      : 'sent' | 'failed' | 'queued'
--   - `error`       : truncado a 500 chars si falla
--   - `provider`    : 'smtp' por ahora; permitira migrar a Resend etc.
--   - `meta`        : jsonb con datos especificos del tipo (plan_slug,
--                     invoice_url, etc.) para debug.
-- ============================================================================

create table if not exists public.email_log (
  id           uuid primary key default gen_random_uuid(),
  type         text not null check (char_length(type) between 1 and 40),
  to_email     text not null check (to_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  to_user_id   uuid references auth.users(id) on delete set null,
  locale       text not null default 'en',
  subject      text not null,
  status       text not null default 'queued'
               check (status in ('queued', 'sent', 'failed')),
  error        text,
  provider     text not null default 'smtp',
  meta         jsonb not null default '{}'::jsonb,
  sent_at      timestamptz,
  created_at   timestamptz not null default now()
);

-- Query caliente del admin /admin/email-log: ordenado por fecha desc.
create index if not exists email_log_created_idx
  on public.email_log(created_at desc);

-- Lookup por destinatario (soporte: "le llego algo a user@x.com?").
create index if not exists email_log_to_email_idx
  on public.email_log(to_email, created_at desc);

-- Lookup por user (en /admin/users → detalle de un user veremos sus
-- emails enviados).
create index if not exists email_log_to_user_idx
  on public.email_log(to_user_id, created_at desc)
  where to_user_id is not null;

-- Filtro por tipo (para metrics: "cuantos plan_changed en el ultimo
-- mes").
create index if not exists email_log_type_idx
  on public.email_log(type, created_at desc);

-- ─────────────────────────── RLS ───────────────────────────
-- Lectura: SOLO admin. Los emails pueden contener PII (tokens, links
-- one-time, etc.). El user normal no necesita ver su propio log;
-- si necesita ayuda, abre ticket de soporte y el admin lo busca.
-- Escritura: SOLO service_role (Edge Functions). No hay policies de
-- INSERT/UPDATE/DELETE -- al estar RLS enabled sin policies, queda
-- todo bloqueado salvo service_role.

alter table public.email_log enable row level security;

drop policy if exists "email_log_select_admin" on public.email_log;
create policy "email_log_select_admin"
  on public.email_log for select
  using (public.is_admin());

-- ─────────────── RPC: get_user_email_log (admin) ───────────────
-- Helper para que el detalle de un user en /admin/users<id> pueda
-- mostrar los ultimos N emails enviados a ese user. Mas barato que
-- exponer la tabla via PostgREST y filtrar client-side.

create or replace function public.get_user_email_log(
  p_user_id uuid,
  p_limit int default 50
)
returns setof public.email_log
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;
  return query
    select * from public.email_log
    where to_user_id = p_user_id
       or to_email = (select email from auth.users where id = p_user_id)
    order by created_at desc
    limit greatest(1, least(p_limit, 200));
end;
$$;

revoke all on function public.get_user_email_log(uuid, int) from public;
grant execute on function public.get_user_email_log(uuid, int) to authenticated;
