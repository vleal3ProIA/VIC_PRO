-- ============================================================================
-- 0030 · Admin: gestion de usuarios
-- ----------------------------------------------------------------------------
-- RPCs para que el admin de la app pueda listar, filtrar, ver detalle
-- y cambiar planes (a free) de cualquier user del proyecto. Las
-- acciones que requieren modificar `auth.users` (bloquear, desactivar)
-- viven en la Edge Function `admin-users` porque necesitan llamar a
-- `supabase.auth.admin.*` con service_role — un RPC no puede hacerlo
-- de forma limpia (auth schema esta protegido y los triggers de
-- auth.users no son nuestros).
--
-- Estrategia "estado del user":
--   - Bloqueado temporalmente -> `auth.users.banned_until > now()`
--   - Desactivado (perma)     -> `auth.users.banned_until > '2099-01-01'`
--   - Activo                  -> `banned_until is null` o `< now()`
--
-- Usar SOLO `banned_until` simplifica: Supabase Auth ya respeta este
-- campo (el user no puede loguearse mientras este puesto al futuro).
-- La distincion blocked vs deactivated es UX — la BD ve un unico flag.
--
-- Diferencia importante con RLS:
--   - Las queries del admin pasan por estas RPCs SECURITY DEFINER que
--     verifican is_admin() manualmente. No exponemos auth.users via
--     PostgREST (lo bloquea Supabase por defecto) ni damos al admin
--     un grant directo sobre profiles que bypasea RLS por error.
-- ============================================================================

-- ─────────────────────────── Helper interno ───────────────────────────
-- Devuelve el estado computado del user a partir de auth.users.banned_until.

create or replace function public._user_status_label(p_banned_until timestamptz)
returns text
language sql
immutable
as $$
  select case
    when p_banned_until is null                       then 'active'
    when p_banned_until < now()                       then 'active'
    when p_banned_until > timestamptz '2099-01-01'    then 'deactivated'
    else 'blocked'
  end;
$$;

-- ─────────────── RPC: admin_users_kpis ───────────────
-- Devuelve un jsonb compacto con los KPIs del header de /admin/users.
-- Incluye counts por estado, distribucion por plan slug, signups
-- recientes. Es UN solo round-trip a BD → cards rapidas.

create or replace function public.admin_users_kpis()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  with status_counts as (
    select
      _user_status_label(u.banned_until) as status,
      count(*)::int as cnt
    from auth.users u
    group by 1
  ),
  plan_counts as (
    select
      coalesce(p.slug, 'free') as plan_slug,
      coalesce(p.name, 'Free') as plan_name,
      count(distinct ts.tenant_id)::int as cnt
    from public.tenant_subscriptions ts
    left join public.plans p on p.id = ts.plan_id
    where ts.status in ('active', 'trialing')
    group by 1, 2
  ),
  signups as (
    select
      count(*) filter (where u.created_at > now() - interval '7 days')::int  as last_7d,
      count(*) filter (where u.created_at > now() - interval '30 days')::int as last_30d,
      count(*)::int as total
    from auth.users u
  )
  select jsonb_build_object(
    'total_users',  (select total from signups),
    'signups_7d',   (select last_7d from signups),
    'signups_30d',  (select last_30d from signups),
    'by_status',    coalesce(
      (select jsonb_object_agg(status, cnt) from status_counts),
      '{}'::jsonb
    ),
    'by_plan',      coalesce(
      (select jsonb_agg(jsonb_build_object(
        'slug', plan_slug,
        'name', plan_name,
        'count', cnt
      ) order by cnt desc)
       from plan_counts),
      '[]'::jsonb
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_users_kpis() from public;
grant execute on function public.admin_users_kpis() to authenticated;

-- ─────────────── RPC: admin_list_users ───────────────
-- Lista paginada de users con search + filtros. Devuelve `setof
-- composite type` con todos los campos que la tabla del admin necesita.
-- El frontend hace el paginado pidiendo limit/offset.
--
-- Search: case-insensitive sobre email, username, first_name, last_name.
-- Filter status: 'all' | 'active' | 'blocked' | 'deactivated'.
-- Filter plan_slug: 'all' | slug concreto (incluido 'free' para los sin
--                   suscripcion activa).

-- Tipo para devolver fila por user.
do $$
begin
  -- Drop si existe para poder editar columnas en re-ejecucion.
  drop type if exists public.admin_user_row cascade;
exception
  when dependent_objects_still_exist then
    -- Si hay alguna dependencia (vista, etc.) ignoramos — al menos en
    -- BD limpia la primera vez funciona.
    null;
end $$;

create type public.admin_user_row as (
  id                  uuid,
  email               text,
  email_confirmed_at  timestamptz,
  username            text,
  display_name        text,
  first_name          text,
  last_name           text,
  avatar_url          text,
  locale              text,
  role                text,
  status              text,
  banned_until        timestamptz,
  current_plan_slug   text,
  current_plan_name   text,
  subscription_status text,
  current_period_end  timestamptz,
  signed_up_at        timestamptz,
  last_sign_in_at     timestamptz,
  total_count         bigint   -- repetido en cada row -> el cliente lo lee de la primera
);

create or replace function public.admin_list_users(
  p_search       text default null,
  p_status       text default 'all',
  p_plan_slug    text default 'all',
  p_limit        int  default 50,
  p_offset       int  default 0
)
returns setof public.admin_user_row
language plpgsql
security definer
set search_path = public
as $$
declare
  v_search_pattern text;
  v_limit int := greatest(1, least(coalesce(p_limit, 50), 200));
  v_offset int := greatest(0, coalesce(p_offset, 0));
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  v_search_pattern := case
    when p_search is null or btrim(p_search) = '' then null
    else '%' || lower(btrim(p_search)) || '%'
  end;

  return query
  with active_sub as (
    -- Para cada tenant_id, su sub activa (la primera por priority).
    -- Como un user puede ser miembro de varios tenants, escogemos el
    -- "personal" (tenant que tiene mismo nombre que el user_id o
    -- es el creado en signup). Si no podemos distinguir, cogemos
    -- cualquier con prioridad de orden por created_at.
    select distinct on (tm.user_id)
      tm.user_id,
      p.slug as plan_slug,
      p.name as plan_name,
      ts.status as sub_status,
      ts.current_period_end as period_end
    from public.tenant_members tm
    join public.tenant_subscriptions ts on ts.tenant_id = tm.tenant_id
    left join public.plans p on p.id = ts.plan_id
    where ts.status in ('active', 'trialing', 'past_due')
    order by tm.user_id, ts.created_at desc
  ),
  base as (
    select
      u.id,
      u.email,
      u.email_confirmed_at,
      pf.username,
      pf.display_name,
      pf.first_name,
      pf.last_name,
      pf.avatar_url,
      pf.locale,
      pf.role,
      public._user_status_label(u.banned_until) as status,
      u.banned_until,
      coalesce(asub.plan_slug, 'free')          as current_plan_slug,
      coalesce(asub.plan_name, 'Free')          as current_plan_name,
      coalesce(asub.sub_status, 'free')         as subscription_status,
      asub.period_end                            as current_period_end,
      u.created_at                               as signed_up_at,
      u.last_sign_in_at
    from auth.users u
    left join public.profiles pf on pf.id = u.id
    left join active_sub asub    on asub.user_id = u.id
  ),
  filtered as (
    select * from base
    where
      (v_search_pattern is null
        or lower(coalesce(email, ''))        like v_search_pattern
        or lower(coalesce(username, ''))     like v_search_pattern
        or lower(coalesce(first_name, ''))   like v_search_pattern
        or lower(coalesce(last_name, ''))    like v_search_pattern
        or lower(coalesce(display_name, '')) like v_search_pattern)
      and (p_status = 'all' or status = p_status)
      and (p_plan_slug = 'all' or current_plan_slug = p_plan_slug)
  ),
  with_count as (
    select *, count(*) over () as total_count
    from filtered
  )
  select
    id, email, email_confirmed_at, username, display_name,
    first_name, last_name, avatar_url, locale, role,
    status, banned_until,
    current_plan_slug, current_plan_name, subscription_status,
    current_period_end, signed_up_at, last_sign_in_at,
    total_count
  from with_count
  order by signed_up_at desc nulls last
  limit v_limit
  offset v_offset;
end;
$$;

revoke all on function public.admin_list_users(text, text, text, int, int)
  from public;
grant execute on function public.admin_list_users(text, text, text, int, int)
  to authenticated;

-- ─────────────── RPC: admin_get_user_detail ───────────────
-- Devuelve detalle COMPLETO de un user para `/admin/users/<id>`:
--   - Profile + estado computed
--   - Sub activa con plan_slug/name + period_end
--   - Sessions count + last_sign_in_at
--   - Tenants en los que es miembro (count + ids)
--   - Tokens API activos count
--   - Emails enviados count
--
-- Una sola RPC -> un solo round-trip para llenar el detalle.

create or replace function public.admin_get_user_detail(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  select jsonb_build_object(
    'id',                  u.id,
    'email',               u.email,
    'email_confirmed_at',  u.email_confirmed_at,
    'phone',               u.phone,
    'created_at',          u.created_at,
    'last_sign_in_at',     u.last_sign_in_at,
    'banned_until',        u.banned_until,
    'status',              public._user_status_label(u.banned_until),
    'profile', jsonb_build_object(
      'username',     pf.username,
      'display_name', pf.display_name,
      'first_name',   pf.first_name,
      'last_name',    pf.last_name,
      'avatar_url',   pf.avatar_url,
      'locale',       pf.locale,
      'theme_mode',   pf.theme_mode,
      'role',         pf.role,
      'country',      pf.country,
      'city',         pf.city
    ),
    'subscription', (
      select to_jsonb(s.*) from (
        select
          ts.id,
          coalesce(p.slug, 'free') as plan_slug,
          coalesce(p.name, 'Free') as plan_name,
          ts.status,
          ts.billing_period,
          ts.current_period_start,
          ts.current_period_end,
          ts.cancel_at_period_end,
          ts.canceled_at,
          ts.stripe_customer_id,
          ts.stripe_subscription_id
        from public.tenant_members tm
        join public.tenant_subscriptions ts on ts.tenant_id = tm.tenant_id
        left join public.plans p on p.id = ts.plan_id
        where tm.user_id = p_user_id
          and ts.status in ('active', 'trialing', 'past_due')
        order by ts.created_at desc
        limit 1
      ) s
    ),
    'tenants_count',       (
      select count(*)::int from public.tenant_members
      where user_id = p_user_id
    ),
    'sessions_count',      (
      -- auth.sessions tiene RLS pero esta funcion es SECURITY DEFINER.
      select count(*)::int from auth.sessions
      where user_id = p_user_id
    ),
    'active_tokens_count', (
      select count(*)::int from public.personal_access_tokens
      where user_id = p_user_id and revoked_at is null
    ),
    'emails_sent_count',   (
      select count(*)::int from public.email_log
      where to_user_id = p_user_id
    )
  ) into v_result
  from auth.users u
  left join public.profiles pf on pf.id = u.id
  where u.id = p_user_id;

  if v_result is null then
    raise exception 'user not found';
  end if;
  return v_result;
end;
$$;

revoke all on function public.admin_get_user_detail(uuid) from public;
grant execute on function public.admin_get_user_detail(uuid) to authenticated;

-- ─────────────── RPC: admin_change_user_plan_free ───────────────
-- Cambia al user a un plan FREE (sin Stripe). Para upgrades a planes
-- de pago: hacer desde Stripe Dashboard (crear subscription manual)
-- o que el user lo haga via /billing/plans. Esto previene desincronizar
-- BD con Stripe accidentalmente.
--
-- El plan destino DEBE no tener stripe_price_id_monthly ni _yearly
-- configurado (i.e. ser realmente free). Si tiene precios → error.

create or replace function public.admin_change_user_plan_free(
  p_user_id  uuid,
  p_plan_id  uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan record;
  v_tenant uuid;
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  -- Verificar plan existe y es free.
  select id, stripe_price_id_monthly, stripe_price_id_yearly
    into v_plan
  from public.plans
  where id = p_plan_id;
  if not found then
    raise exception 'plan_not_found';
  end if;
  if v_plan.stripe_price_id_monthly is not null
     or v_plan.stripe_price_id_yearly is not null then
    raise exception 'plan_is_paid: use Stripe Dashboard for paid plan changes';
  end if;

  -- Encontrar tenant "personal" del user: el primero del que es
  -- miembro y donde tiene cualquier sub. Asumimos signup crea un
  -- tenant personal por user (patron del proyecto).
  select tm.tenant_id into v_tenant
  from public.tenant_members tm
  where tm.user_id = p_user_id
  order by tm.created_at asc
  limit 1;

  if v_tenant is null then
    raise exception 'no_tenant_for_user';
  end if;

  -- Cancelar subs activas anteriores (para que el unique parcial no
  -- bloquee — mismo patron que stripe-webhook).
  update public.tenant_subscriptions
    set status = 'canceled',
        canceled_at = now()
    where tenant_id = v_tenant
      and status in ('trialing', 'active', 'past_due', 'incomplete');

  -- Insertar sub free.
  insert into public.tenant_subscriptions (
    tenant_id, plan_id, status, billing_period
  )
  values (v_tenant, p_plan_id, 'active', 'monthly');
end;
$$;

revoke all on function public.admin_change_user_plan_free(uuid, uuid) from public;
grant execute on function public.admin_change_user_plan_free(uuid, uuid)
  to authenticated;
