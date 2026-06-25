-- ============================================================================
-- 0105 · AI usage caps por usuario (cuotas diarias por plan + overrides)
-- ----------------------------------------------------------------------------
-- Hoy `ai_usage` registra cada llamada al `ai-gateway` pero NADIE corta cuando
-- un usuario abusa: un user puede generar 500€/noche de Gemini sin parar. Esta
-- migracion anyade:
--
--   * `ai_quotas`           -> limite diario por plan (free/pro/max), editable
--                              desde /admin/ai-quotas.
--   * `ai_user_overrides`   -> excepciones por usuario concreto (VIPs o
--                              castigados), prevalece sobre el limite de plan.
--   * `consume_ai_quota()`  -> RPC atomica que el gateway llama ANTES de cada
--                              llamada real. Si el user supero su cuota, el
--                              gateway lanza `ai_quota_exceeded:N` y aborta SIN
--                              quemar tokens.
--   * `get_my_ai_quota()`   -> RPC publica para que la UI muestre "te quedan X".
--   * `admin_set_ai_quota()`+`admin_set_user_override()` -> RPCs para el panel
--                              admin.
--
-- Resolucion del limite por usuario (en `consume_ai_quota`):
--   1. Si existe fila en `ai_user_overrides` -> ese limite (gana sobre plan).
--   2. Si no, busca el plan activo del tenant del user via
--      `tenant_subscriptions` (mismo patron que `tenant_entitlements`).
--   3. Si no hay plan resuelto (user sin tenant activo) -> usa el limite
--      del plan `free` por defecto.
--
-- Atomicidad: la RPC `consume_ai_quota` corre en una sola transaccion
-- (security definer) y NO inserta en `ai_usage` (lo sigue haciendo el
-- gateway al exito). Solo cuenta + devuelve allow/deny. Asi un fallo del
-- proveedor no consume cuota.
-- ============================================================================

-- 1) Tabla ai_quotas (limite por plan) ─────────────────────────────────────

create table if not exists public.ai_quotas (
  plan_slug         text primary key references public.plans(slug) on delete cascade,
  daily_call_limit  int  not null check (daily_call_limit >= 0),
  updated_at        timestamptz not null default now()
);

drop trigger if exists ai_quotas_set_updated_at on public.ai_quotas;
create trigger ai_quotas_set_updated_at
  before update on public.ai_quotas
  for each row execute function public.set_updated_at();

comment on table public.ai_quotas is
  'Limite diario de llamadas al ai-gateway por slug de plan. 0 = bloqueado total.';

-- Seed: solo inserta para planes que existan ya (free/pro/max). Si el slug
-- no existe en `plans` (p.ej. el seed de 0012 solo trae free/pro/business/
-- enterprise), el ON CONFLICT lo ignora silenciosamente.
insert into public.ai_quotas (plan_slug, daily_call_limit)
select v.slug, v.daily
from (values
  ('free', 30),
  ('pro',  300),
  ('max',  1500)
) as v(slug, daily)
join public.plans p on p.slug = v.slug
on conflict (plan_slug) do nothing;

-- 2) Tabla ai_user_overrides ──────────────────────────────────────────────
-- VIPs (limite alto) o usuarios castigados por abuso (limite 0).
create table if not exists public.ai_user_overrides (
  user_id           uuid primary key references auth.users(id) on delete cascade,
  daily_call_limit  int  not null check (daily_call_limit >= 0),
  reason            text,
  created_by        uuid references auth.users(id) on delete set null,
  updated_at        timestamptz not null default now()
);

drop trigger if exists ai_user_overrides_set_updated_at on public.ai_user_overrides;
create trigger ai_user_overrides_set_updated_at
  before update on public.ai_user_overrides
  for each row execute function public.set_updated_at();

comment on table public.ai_user_overrides is
  'Excepciones de cuota IA por usuario concreto (VIPs / castigados). Prevalece sobre el plan.';

-- 3) RLS ───────────────────────────────────────────────────────────────────

alter table public.ai_quotas          enable row level security;
alter table public.ai_user_overrides  enable row level security;

-- ai_quotas: SELECT abierto a authenticated (cualquiera puede ver su limite,
-- la UI lo necesita para "te quedan X llamadas"). UPDATE/INSERT/DELETE solo
-- admin (las RPCs admin son security definer; esto es defensa en profundidad).
drop policy if exists "ai_quotas_select_authenticated" on public.ai_quotas;
create policy "ai_quotas_select_authenticated"
  on public.ai_quotas for select to authenticated
  using (true);

drop policy if exists "ai_quotas_admin_write" on public.ai_quotas;
create policy "ai_quotas_admin_write"
  on public.ai_quotas for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ai_user_overrides: TODO admin only (lectura+escritura). El user normal no
-- debe poder leer si tiene un override (privacidad: "fulanito es VIP" o
-- "fulanito es un abuser" no es informacion publica).
drop policy if exists "ai_user_overrides_admin_all" on public.ai_user_overrides;
create policy "ai_user_overrides_admin_all"
  on public.ai_user_overrides for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 4) RPC consume_ai_quota(p_user_id) ──────────────────────────────────────
-- Atomica. Resuelve limite -> cuenta usos ultimas 24h -> allow/deny.
-- Se invoca con service_role desde el ai-gateway ANTES de la llamada al
-- proveedor. NO inserta en `ai_usage` (eso lo hace el gateway al exito).
create or replace function public.consume_ai_quota(p_user_id uuid)
returns table (allowed boolean, remaining int, daily_limit int)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_limit  int;
  v_count  int;
  v_slug   text;
begin
  if p_user_id is null then
    -- Sin user_id no podemos cuotar (admin testeando / EF interna).
    -- Devolvemos allow infinito; el caller decide si exigir userId.
    return query select true, 2147483647, 2147483647;
    return;
  end if;

  -- 1) Override por usuario (prevalece).
  select o.daily_call_limit into v_limit
    from public.ai_user_overrides o
    where o.user_id = p_user_id;

  if v_limit is null then
    -- 2) Plan activo del tenant. Usamos el mismo patron que
    --    `tenant_entitlements`: tenant_subscriptions con status in (trialing,
    --    active) + join a plans. Un user puede pertenecer a varios tenants;
    --    cogemos el plan mas alto (mayor daily_call_limit).
    select q.daily_call_limit into v_limit
      from public.tenant_members tm
      join public.tenant_subscriptions s on s.tenant_id = tm.tenant_id
      join public.plans p on p.id = s.plan_id
      join public.ai_quotas q on q.plan_slug = p.slug
      where tm.user_id = p_user_id
        and s.status in ('trialing','active')
      order by q.daily_call_limit desc
      limit 1;
  end if;

  if v_limit is null then
    -- 3) Fallback al plan `free`.
    select q.daily_call_limit into v_limit
      from public.ai_quotas q where q.plan_slug = 'free';
  end if;

  -- Si NI siquiera hay slug 'free' en ai_quotas (caso degenerado: alguien
  -- borro el seed), bloqueamos por defecto. Mejor falsos positivos que
  -- regalar API calls.
  if v_limit is null then
    v_limit := 0;
  end if;

  -- 4) Cuenta usos en las ultimas 24h.
  select count(*)::int into v_count
    from public.ai_usage
    where user_id = p_user_id
      and created_at > now() - interval '24 hours';

  if v_count >= v_limit then
    return query select false, 0, v_limit;
  else
    return query select true, greatest(v_limit - v_count - 1, 0), v_limit;
  end if;
end;
$$;

revoke all on function public.consume_ai_quota(uuid) from public;
grant execute on function public.consume_ai_quota(uuid) to authenticated, service_role;

comment on function public.consume_ai_quota(uuid) is
  'Chequea si p_user_id puede hacer una llamada mas hoy. Devuelve (allowed, remaining, daily_limit). NO inserta en ai_usage.';

-- 5) RPC get_my_ai_quota() ───────────────────────────────────────────────
-- La UI cliente la llama para mostrar "te quedan X de N hoy".
create or replace function public.get_my_ai_quota()
returns table (allowed boolean, remaining int, daily_limit int)
language sql
security definer
set search_path = public, pg_catalog
as $$
  select * from public.consume_ai_quota(auth.uid());
$$;

revoke all on function public.get_my_ai_quota() from public;
grant execute on function public.get_my_ai_quota() to authenticated;

comment on function public.get_my_ai_quota() is
  'Devuelve la cuota IA del caller para la UI. Wrapper de consume_ai_quota(auth.uid()).';

-- 6) RPC admin_set_ai_quota(plan_slug, limit) ────────────────────────────
create or replace function public.admin_set_ai_quota(p_plan_slug text, p_limit int)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if not public.is_admin() then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 0 then
    raise exception 'invalid_limit' using errcode = '22023';
  end if;
  -- Solo permitimos slugs que existan en plans (FK lo enforcearia, pero
  -- damos un error mejor antes).
  if not exists (select 1 from public.plans where slug = p_plan_slug) then
    raise exception 'unknown_plan' using errcode = '23503';
  end if;

  insert into public.ai_quotas (plan_slug, daily_call_limit)
  values (p_plan_slug, p_limit)
  on conflict (plan_slug) do update
    set daily_call_limit = excluded.daily_call_limit,
        updated_at = now();
end;
$$;

revoke all on function public.admin_set_ai_quota(text, int) from public;
grant execute on function public.admin_set_ai_quota(text, int) to authenticated;

comment on function public.admin_set_ai_quota(text, int) is
  'Admin: fija el limite diario de IA del plan p_plan_slug. Crea o actualiza.';

-- 7) RPC admin_set_user_override(user_id, limit, reason) ─────────────────
-- p_limit = -1 -> elimina el override (DELETE).
create or replace function public.admin_set_user_override(
  p_user_id uuid,
  p_limit   int,
  p_reason  text
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if not public.is_admin() then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_user_id is null then
    raise exception 'invalid_user' using errcode = '22023';
  end if;

  if p_limit = -1 then
    delete from public.ai_user_overrides where user_id = p_user_id;
    return;
  end if;

  if p_limit is null or p_limit < 0 then
    raise exception 'invalid_limit' using errcode = '22023';
  end if;

  insert into public.ai_user_overrides (user_id, daily_call_limit, reason, created_by)
  values (p_user_id, p_limit, p_reason, auth.uid())
  on conflict (user_id) do update
    set daily_call_limit = excluded.daily_call_limit,
        reason           = excluded.reason,
        created_by       = excluded.created_by,
        updated_at       = now();
end;
$$;

revoke all on function public.admin_set_user_override(uuid, int, text) from public;
grant execute on function public.admin_set_user_override(uuid, int, text) to authenticated;

comment on function public.admin_set_user_override(uuid, int, text) is
  'Admin: fija o elimina (-1) override de cuota IA para un usuario. Capacities VIP / castigados.';
