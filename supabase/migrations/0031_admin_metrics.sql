-- ============================================================================
-- 0031 · Admin metrics / dashboard
-- ----------------------------------------------------------------------------
-- RPCs que devuelven series y agregados para la pagina `/admin/metrics`:
--   - overview KPIs (totales: users, MRR, ARR, active subs, conversion)
--   - signups por dia (serie temporal)
--   - MRR por dia (serie temporal)
--   - distribucion por plan (counts)
--   - conversion funnel (signups -> activated -> paying -> churned)
--
-- Decision de implementacion: on-demand, sin vistas materializadas
-- todavia. Con volumenes bajos (< 100k users) las queries son rapidas;
-- migrar a materializadas + pg_cron sera trivial mas adelante sin
-- cambiar la API que ve el cliente.
--
-- MRR estimado:
--   - Para cada subscription activa, su contribucion mensual es
--     plan.price_monthly_cents si billing_period='monthly', o
--     price_yearly_cents / 12 si 'yearly'.
--   - No descontamos coupons / promociones para no complicar la
--     primera version — se reflejara en una v2 cuando integremos
--     stripe.charges.
-- ============================================================================

-- ─────────────── RPC: admin_metrics_overview ───────────────
-- Cards principales del dashboard. Un solo round-trip a BD.

create or replace function public.admin_metrics_overview()
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

  with mrr_calc as (
    select coalesce(sum(
      case ts.billing_period
        when 'monthly' then coalesce(p.price_monthly_cents, 0)
        when 'yearly'  then coalesce(p.price_yearly_cents, 0) / 12
        else 0
      end
    ), 0)::bigint as mrr_cents
    from public.tenant_subscriptions ts
    join public.plans p on p.id = ts.plan_id
    where ts.status in ('active', 'trialing')
  ),
  user_counts as (
    select
      count(*)::int                                          as total_users,
      count(*) filter (where email_confirmed_at is not null)::int as verified_users,
      count(*) filter (where created_at > now() - interval '30 days')::int as new_30d
    from auth.users
  ),
  sub_counts as (
    select
      count(*) filter (where status in ('active','trialing'))::int as active_subs,
      count(*) filter (where status = 'canceled' and canceled_at > now() - interval '30 days')::int as churned_30d,
      count(distinct tenant_id) filter (
        where status in ('active','trialing')
          and plan_id in (
            select id from public.plans
            where price_monthly_cents > 0 or price_yearly_cents > 0
          )
      )::int as paying_tenants
    from public.tenant_subscriptions
  )
  select jsonb_build_object(
    'total_users',     uc.total_users,
    'verified_users',  uc.verified_users,
    'new_users_30d',   uc.new_30d,
    'active_subs',     sc.active_subs,
    'paying_tenants',  sc.paying_tenants,
    'churned_30d',     sc.churned_30d,
    'mrr_cents',       mc.mrr_cents,
    'arr_cents',       mc.mrr_cents * 12,
    -- Conversion = paying / total_users (proxy; en v2 sera funnel real)
    'conversion_pct',  case
      when uc.total_users = 0 then 0
      else round((sc.paying_tenants::numeric / uc.total_users::numeric) * 100, 1)
    end
  ) into v_result
  from mrr_calc mc, user_counts uc, sub_counts sc;

  return v_result;
end;
$$;

revoke all on function public.admin_metrics_overview() from public;
grant execute on function public.admin_metrics_overview() to authenticated;

-- ─────────────── RPC: admin_metrics_signups ───────────────
-- Serie temporal de signups por dia, ultimos N dias. Para grafico
-- de linea. Rellena ceros para los dias sin signups (generate_series).

create or replace function public.admin_metrics_signups(p_days int default 30)
returns table (day date, count int)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days int := greatest(1, least(coalesce(p_days, 30), 365));
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  return query
  with days as (
    select generate_series(
      current_date - (v_days - 1),
      current_date,
      interval '1 day'
    )::date as day
  ),
  counts as (
    select (created_at at time zone 'UTC')::date as day, count(*)::int as count
    from auth.users
    where created_at >= current_date - (v_days - 1)
    group by 1
  )
  select d.day, coalesce(c.count, 0) as count
  from days d
  left join counts c on c.day = d.day
  order by d.day;
end;
$$;

revoke all on function public.admin_metrics_signups(int) from public;
grant execute on function public.admin_metrics_signups(int) to authenticated;

-- ─────────────── RPC: admin_metrics_mrr ───────────────
-- Serie temporal de MRR por dia, ultimos N dias. Para cada dia,
-- sumamos el MRR de las subscriptions que estaban activas ese dia
-- (created_at <= day AND (canceled_at IS NULL OR canceled_at > day)).
--
-- Ojo: esto es estimado. Reflejara cambios de plan al precio del
-- plan ACTUAL (no historico) — para historico exacto necesitariamos
-- snapshots de stripe.invoices. Suficiente para la primera version.

create or replace function public.admin_metrics_mrr(p_days int default 30)
returns table (day date, mrr_cents bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days int := greatest(1, least(coalesce(p_days, 30), 365));
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  return query
  with days as (
    select generate_series(
      current_date - (v_days - 1),
      current_date,
      interval '1 day'
    )::date as day
  )
  select
    d.day,
    coalesce(sum(
      case ts.billing_period
        when 'monthly' then coalesce(p.price_monthly_cents, 0)
        when 'yearly'  then coalesce(p.price_yearly_cents, 0) / 12
        else 0
      end
    ), 0)::bigint as mrr_cents
  from days d
  left join public.tenant_subscriptions ts on
       ts.created_at <= (d.day + interval '1 day')
   and (ts.canceled_at is null or ts.canceled_at > d.day)
   and ts.status in ('active', 'trialing', 'canceled')
   -- Incluimos 'canceled' porque su canceled_at podria ser POSTERIOR
   -- al day actual -> ese dia aun contaba como MRR. El filtro de
   -- canceled_at > d.day arriba ya excluye los ya cancelados.
  left join public.plans p on p.id = ts.plan_id
  group by d.day
  order by d.day;
end;
$$;

revoke all on function public.admin_metrics_mrr(int) from public;
grant execute on function public.admin_metrics_mrr(int) to authenticated;

-- ─────────────── RPC: admin_metrics_plan_distribution ───────────────
-- Counts por plan slug (solo subs activas). Para grafico de barras.

create or replace function public.admin_metrics_plan_distribution()
returns table (slug text, name text, count int, mrr_cents bigint)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  return query
  select
    coalesce(p.slug, 'unknown')        as slug,
    coalesce(p.name, 'Unknown')        as name,
    count(distinct ts.tenant_id)::int  as count,
    coalesce(sum(
      case ts.billing_period
        when 'monthly' then coalesce(p.price_monthly_cents, 0)
        when 'yearly'  then coalesce(p.price_yearly_cents, 0) / 12
        else 0
      end
    ), 0)::bigint as mrr_cents
  from public.tenant_subscriptions ts
  left join public.plans p on p.id = ts.plan_id
  where ts.status in ('active', 'trialing')
  group by p.slug, p.name, p.position
  order by p.position nulls last, count desc;
end;
$$;

revoke all on function public.admin_metrics_plan_distribution() from public;
grant execute on function public.admin_metrics_plan_distribution() to authenticated;

-- ─────────────── RPC: admin_metrics_funnel ───────────────
-- Conversion funnel: total signups -> verified -> with active sub ->
-- paying. Para mostrar como barras horizontales descendentes.

create or replace function public.admin_metrics_funnel()
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

  with signups as (
    select count(*)::int as cnt from auth.users
  ),
  verified as (
    select count(*)::int as cnt from auth.users
    where email_confirmed_at is not null
  ),
  active_subs_users as (
    -- distinct users with at least one active sub
    select count(distinct tm.user_id)::int as cnt
    from public.tenant_members tm
    join public.tenant_subscriptions ts on ts.tenant_id = tm.tenant_id
    where ts.status in ('active', 'trialing')
  ),
  paying_users as (
    -- users on a paid plan
    select count(distinct tm.user_id)::int as cnt
    from public.tenant_members tm
    join public.tenant_subscriptions ts on ts.tenant_id = tm.tenant_id
    join public.plans p on p.id = ts.plan_id
    where ts.status in ('active', 'trialing')
      and (coalesce(p.price_monthly_cents, 0) > 0
        or coalesce(p.price_yearly_cents, 0)  > 0)
  )
  select jsonb_build_object(
    'signups',         (select cnt from signups),
    'verified',        (select cnt from verified),
    'with_active_sub', (select cnt from active_subs_users),
    'paying',          (select cnt from paying_users)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_metrics_funnel() from public;
grant execute on function public.admin_metrics_funnel() to authenticated;
