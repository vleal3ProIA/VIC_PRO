-- ============================================================================
-- 0034 · Fix admin_list_users: cast enum subscription_status a text
-- ----------------------------------------------------------------------------
-- Bug detectado al abrir /admin/users como administrador:
--   PostgrestException 22P02 (invalid_text_representation) en
--   `select * from admin_list_users(...)`.
--
-- Causa raiz: la migracion 0030 escribe
--   coalesce(asub.sub_status, 'free') as subscription_status
--
-- donde `asub.sub_status` viene de `tenant_subscriptions.status` que es
-- de tipo enum `public.subscription_status` (valores: trialing, active,
-- past_due, canceled, incomplete). Cuando un user NO tiene sub activa,
-- el LEFT JOIN devuelve null y `coalesce` intenta unificar tipos
-- castando el literal 'free' al enum -> fallo, porque 'free' no es
-- miembro del enum.
--
-- Sintomas: la pagina /admin/users muestra "no se pudieron cargar los
-- usuarios" en cuanto hay aunque sea UN user sin sub activa (caso
-- tipico de cualquier proyecto recien instalado).
--
-- Fix: castear `asub.sub_status` a text ANTES del coalesce. Como el
-- tipo de retorno (`admin_user_row.subscription_status`) ya es text,
-- esto es lo correcto y mantiene el contrato de la RPC.
-- ============================================================================

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
    select distinct on (tm.user_id)
      tm.user_id,
      p.slug as plan_slug,
      p.name as plan_name,
      ts.status::text as sub_status,  -- cast a text para que el coalesce
                                       -- con 'free' (literal text) funcione.
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
