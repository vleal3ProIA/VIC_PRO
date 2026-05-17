-- ============================================================================
-- 0025 · Outgoing Webhooks
-- ----------------------------------------------------------------------------
-- Sistema de webhooks SALIENTES: cuando algo pasa dentro de la app
-- (user creado, suscripcion renovada, archivo subido, lo que sea),
-- POSTeamos un JSON a las URLs que los tenants hayan configurado.
-- Es el contrato standard para integraciones tipo Stripe, GitHub,
-- Linear: ellos hacen el push, el cliente no tiene que pollear.
--
-- **Modelo**:
--   - `webhook_endpoints`: configuracion (URL + secret HMAC + events
--     suscritos + active flag).
--   - `webhook_deliveries`: log de cada intento de POST con status,
--     response code, attempts, next_retry_at.
--
-- **Eventos suscritos** (text[] en endpoints):
--   - 'user.created'           - registro de un user (post-onboarding)
--   - 'user.deleted'           - borrado de cuenta
--   - 'subscription.created'   - alta de plan de pago
--   - 'subscription.updated'   - cambio de plan / cantidad
--   - 'subscription.canceled'  - downgrade a free / cancelacion
--   - 'invoice.paid'           - pago confirmado
--   - 'invoice.failed'         - pago rechazado (dunning)
--   - '*'                      - comodin = todos los eventos
--
-- **Seguridad**:
--   - Cada endpoint tiene su propio `secret` random de 32 bytes.
--   - Cada POST lleva header `X-Webhook-Signature: sha256=<hmac_hex>`
--     calculado sobre el body crudo con ese secret.
--   - El cliente VERIFICA esa firma antes de procesar (estilo Stripe).
--   - El secret se devuelve UNA SOLA VEZ al crear, igual que los PAT.
--
-- **Reintentos** (en el dispatcher):
--   - 5xx o timeout -> reintentamos con backoff exponencial: 1m, 5m,
--     30m, 2h, 12h. Tras 5 fallos, marca delivery como 'failed' y
--     deshabilita el endpoint si su `consecutive_failures >= 10`.
--   - 2xx -> delivered_at = now(), reset consecutive_failures = 0.
--   - 4xx -> sin reintentos (el endpoint dijo "esto no me interesa"
--     o "URL inexistente"), pero suma a consecutive_failures.
-- ============================================================================

create table if not exists public.webhook_endpoints (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  url           text not null check (url ~* '^https?://'),
  description   text,
  secret_hash   text not null,    -- SHA-256 del secret (el secret se
                                  -- devuelve raw 1 vez y luego no se
                                  -- guarda; el HMAC lo computa la
                                  -- Edge Function leyendo el secret
                                  -- desde una tabla pivote `webhook_secrets`).
  events        text[] not null default array['*']::text[],
  active        boolean not null default true,
  consecutive_failures int not null default 0,
  disabled_reason text,           -- 'too_many_failures' | 'manual'
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists webhook_endpoints_tenant_idx
  on public.webhook_endpoints(tenant_id, created_at desc);
create index if not exists webhook_endpoints_user_idx
  on public.webhook_endpoints(user_id, created_at desc);
create index if not exists webhook_endpoints_active_idx
  on public.webhook_endpoints(active) where active = true;

-- ─────────────────────────────────────────────────────────────────────
-- Tabla pivote con el secret EN CLARO. La separamos para que se pueda
-- conceder lectura SOLO al service_role (no a authenticated): asi el
-- secret raw nunca se filtra por RLS aunque el endpoint sea visible.
-- ─────────────────────────────────────────────────────────────────────
create table if not exists public.webhook_secrets (
  endpoint_id   uuid primary key references public.webhook_endpoints(id) on delete cascade,
  secret        text not null
);

-- ─────────────────────────────────────────────────────────────────────
-- Tabla de deliveries (log de intentos). Se llena por el dispatcher
-- en cada POST exitoso o fallido. Sirve para:
--   - Dashboard "ultimos webhooks enviados" con success/fail.
--   - Reintentos del cron que mira `next_retry_at <= now()`.
--   - Debug del cliente que dice "no me llegan los webhooks".
-- ─────────────────────────────────────────────────────────────────────
create table if not exists public.webhook_deliveries (
  id            uuid primary key default gen_random_uuid(),
  endpoint_id   uuid not null references public.webhook_endpoints(id) on delete cascade,
  event_type    text not null,
  payload       jsonb not null,
  status        text not null check (status in ('pending', 'success', 'failed', 'retry')),
  http_status   int,
  response_body text,             -- truncado a 2 KB
  error         text,             -- timeout / dns_error / etc.
  attempt       int not null default 1,
  next_retry_at timestamptz,      -- null si ya no se reintenta
  created_at    timestamptz not null default now(),
  delivered_at  timestamptz,
  failed_at     timestamptz
);

create index if not exists webhook_deliveries_endpoint_idx
  on public.webhook_deliveries(endpoint_id, created_at desc);

-- Query caliente del cron de reintentos: pendientes con next_retry_at
-- vencido.
create index if not exists webhook_deliveries_retry_idx
  on public.webhook_deliveries(next_retry_at)
  where status = 'retry';

-- ─────────────────────────── RLS ───────────────────────────
-- El user ve los endpoints/deliveries de sus tenants. El secret_hash
-- esta en webhook_endpoints (no es el secret raw -- es su hash, util
-- solo para el dispatcher que sabe el raw).

alter table public.webhook_endpoints   enable row level security;
alter table public.webhook_deliveries  enable row level security;
alter table public.webhook_secrets     enable row level security;

drop policy if exists "wh_endpoints_select_own" on public.webhook_endpoints;
create policy "wh_endpoints_select_own"
  on public.webhook_endpoints for select
  using (
    user_id = auth.uid()
    or (
      tenant_id is not null
      and exists (
        select 1
        from public.tenant_members tm
        where tm.tenant_id = webhook_endpoints.tenant_id
          and tm.user_id   = auth.uid()
      )
    )
  );

drop policy if exists "wh_endpoints_update_own" on public.webhook_endpoints;
create policy "wh_endpoints_update_own"
  on public.webhook_endpoints for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "wh_endpoints_delete_own" on public.webhook_endpoints;
create policy "wh_endpoints_delete_own"
  on public.webhook_endpoints for delete
  using (user_id = auth.uid());

-- INSERT solo via Edge Function (genera el secret + lo hashea +
-- inserta en webhook_secrets atomicamente).
-- webhook_secrets NUNCA expone via RLS (sin policy SELECT/UPDATE/etc).

drop policy if exists "wh_deliveries_select_own" on public.webhook_deliveries;
create policy "wh_deliveries_select_own"
  on public.webhook_deliveries for select
  using (
    exists (
      select 1
      from public.webhook_endpoints e
      where e.id = webhook_deliveries.endpoint_id
        and (
          e.user_id = auth.uid()
          or (
            e.tenant_id is not null
            and exists (
              select 1
              from public.tenant_members tm
              where tm.tenant_id = e.tenant_id
                and tm.user_id   = auth.uid()
            )
          )
        )
    )
  );

-- ─────────────────────────── RPCs ───────────────────────────

-- Toggle activo del endpoint. El user puede pausar/reanudar sus webhooks.
create or replace function public.set_webhook_endpoint_active(
  p_id uuid,
  p_active boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
begin
  update public.webhook_endpoints
    set active = p_active,
        consecutive_failures = case when p_active then 0
                                    else consecutive_failures end,
        disabled_reason = case when p_active then null
                               else coalesce(disabled_reason, 'manual') end,
        updated_at = now()
    where id = p_id
      and user_id = auth.uid();
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

revoke all on function public.set_webhook_endpoint_active(uuid, boolean) from public;
grant execute on function public.set_webhook_endpoint_active(uuid, boolean) to authenticated;

-- Marca delivery exitoso. Para uso del dispatcher (service_role).
create or replace function public.record_webhook_success(
  p_delivery_id uuid,
  p_http_status int,
  p_response_body text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_endpoint uuid;
begin
  update public.webhook_deliveries
    set status        = 'success',
        http_status   = p_http_status,
        response_body = left(coalesce(p_response_body, ''), 2048),
        delivered_at  = now(),
        next_retry_at = null
    where id = p_delivery_id
    returning endpoint_id into v_endpoint;

  if v_endpoint is not null then
    update public.webhook_endpoints
      set consecutive_failures = 0,
          updated_at = now()
      where id = v_endpoint;
  end if;
end;
$$;

revoke all on function public.record_webhook_success(uuid, int, text) from public;

-- Marca delivery con fallo + reschedule o final. Para uso del dispatcher.
create or replace function public.record_webhook_failure(
  p_delivery_id uuid,
  p_http_status int,
  p_error text,
  p_next_retry_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_endpoint uuid;
  v_fails    int;
begin
  update public.webhook_deliveries
    set status        = case when p_next_retry_at is null then 'failed' else 'retry' end,
        http_status   = p_http_status,
        error         = left(coalesce(p_error, ''), 500),
        attempt       = attempt + 1,
        next_retry_at = p_next_retry_at,
        failed_at     = case when p_next_retry_at is null then now() else null end
    where id = p_delivery_id
    returning endpoint_id into v_endpoint;

  if v_endpoint is not null then
    update public.webhook_endpoints
      set consecutive_failures = consecutive_failures + 1,
          updated_at = now()
      where id = v_endpoint
      returning consecutive_failures into v_fails;

    -- Auto-disable tras 10 fallos consecutivos. Le ahorra al cliente
    -- una avalancha de POSTs a una URL que ya no existe.
    if v_fails >= 10 then
      update public.webhook_endpoints
        set active = false,
            disabled_reason = 'too_many_failures',
            updated_at = now()
        where id = v_endpoint;
    end if;
  end if;
end;
$$;

revoke all on function public.record_webhook_failure(uuid, int, text, timestamptz) from public;

-- ─────────────────────────── Trigger ───────────────────────────
-- Actualiza updated_at en cada UPDATE de endpoint.
create or replace function public.webhook_endpoints_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists webhook_endpoints_touch on public.webhook_endpoints;
create trigger webhook_endpoints_touch
  before update on public.webhook_endpoints
  for each row execute function public.webhook_endpoints_touch_updated_at();
