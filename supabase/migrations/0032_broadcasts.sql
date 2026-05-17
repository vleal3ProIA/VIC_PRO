-- ============================================================================
-- 0032 · Broadcasts (emails masivos del admin)
-- ----------------------------------------------------------------------------
-- Sistema para que el admin envie emails a grupos de users:
-- anuncios, promociones, newsletters. Se envia EN EL IDIOMA del
-- receptor (cada user recibe el email con su locale).
--
-- **Modelo**:
--   - `subject` / `body_html`: mismo contenido para todos los users
--     (rendererizado con template 'broadcast' del email_templates.ts
--     que ya tenemos).
--   - `target_type` + `target_value`: define la audiencia.
--     * 'all'       -> todos los users (no filtra)
--     * 'plan'      -> users con plan slug = target_value['slug']
--     * 'language'  -> users con locale = target_value['code']
--     * 'status'    -> 'active' | 'blocked' | 'deactivated'
--   - `status`: ciclo de vida.
--     * 'draft'     -> guardado, no enviado
--     * 'sending'   -> en proceso (la Edge Function lo cambio aqui
--                      antes de empezar)
--     * 'sent'      -> 100% procesado
--     * 'failed'    -> error catastrofico (raro; los fallos por user
--                      individual NO mueven a 'failed')
--   - `recipients_total`: cuantos users objetivo se calcularon al
--     iniciar el envio. Snapshot — si se anyade un user despues, NO
--     se le manda.
--   - `sent_count` / `failed_count`: progreso. La UI los muestra
--     vivos polleando.
--   - `processed_offset`: cursor — la Edge Function procesa por
--     batches y guarda hasta donde llegó. Permite resumir si se
--     interrumpe.
--
-- Sin `schedule_at` por ahora — envio inmediato o draft. Programado
-- requeriria pg_cron y es v2.
-- ============================================================================

create table if not exists public.broadcasts (
  id              uuid primary key default gen_random_uuid(),
  subject         text not null check (char_length(subject) between 1 and 200),
  body_html       text not null check (char_length(body_html) between 1 and 5000),
  target_type     text not null
                  check (target_type in ('all', 'plan', 'language', 'status')),
  target_value    jsonb not null default '{}'::jsonb,
  status          text not null default 'draft'
                  check (status in ('draft', 'sending', 'sent', 'failed')),
  recipients_total int default 0,
  sent_count      int not null default 0,
  failed_count    int not null default 0,
  processed_offset int not null default 0,
  created_by      uuid not null references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  started_at      timestamptz,
  finished_at     timestamptz,
  last_error      text
);

create index if not exists broadcasts_created_idx
  on public.broadcasts(created_at desc);
create index if not exists broadcasts_status_idx
  on public.broadcasts(status);

-- Touch updated_at en cada UPDATE.
create or replace function public.broadcasts_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists broadcasts_touch on public.broadcasts;
create trigger broadcasts_touch
  before update on public.broadcasts
  for each row execute function public.broadcasts_touch_updated_at();

-- ─────────────────────────── RLS ───────────────────────────
-- Admin only para todo. RLS por defecto sin policies = bloqueado.

alter table public.broadcasts enable row level security;

drop policy if exists "broadcasts_admin_all" on public.broadcasts;
create policy "broadcasts_admin_all"
  on public.broadcasts for all
  using (public.is_admin())
  with check (public.is_admin());

-- ─────────────── RPC: admin_broadcast_estimate ───────────────
-- Cuenta cuántos users RECIBIRAN un broadcast con esos filtros, ANTES
-- de enviar. Sirve para mostrar "se enviara a N usuarios" en el form
-- y para asustar al admin si N es muy grande.
--
-- Devuelve jsonb { count, by_locale: { es: 100, en: 50, ... } } para
-- que la UI pueda mostrar tambien la distribucion por idioma (util
-- porque cada user recibira en su idioma).

create or replace function public.admin_broadcast_estimate(
  p_target_type  text,
  p_target_value jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count   int;
  v_by_loc  jsonb;
  v_slug    text;
  v_lang    text;
  v_status  text;
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  if p_target_type not in ('all', 'plan', 'language', 'status') then
    raise exception 'invalid_target_type';
  end if;

  -- Base query: todos los users + su locale + su sub activa.
  -- Filtramos segun target_type.
  with audience as (
    select
      u.id,
      coalesce(pf.locale, 'en') as locale
    from auth.users u
    left join public.profiles pf on pf.id = u.id
    left join lateral (
      -- sub activa del tenant del user
      select coalesce(p.slug, 'free') as plan_slug
      from public.tenant_members tm
      join public.tenant_subscriptions ts on ts.tenant_id = tm.tenant_id
      left join public.plans p on p.id = ts.plan_id
      where tm.user_id = u.id
        and ts.status in ('active', 'trialing')
      limit 1
    ) sub on true
    where
      case p_target_type
        when 'all'      then true
        when 'plan'     then coalesce(sub.plan_slug, 'free')
                              = coalesce(p_target_value->>'slug', 'free')
        when 'language' then coalesce(pf.locale, 'en')
                              = coalesce(p_target_value->>'code', 'en')
        when 'status'   then public._user_status_label(u.banned_until)
                              = coalesce(p_target_value->>'status', 'active')
      end
      -- Email obligatorio para que sirva mandar.
      and u.email is not null
  )
  select
    count(*)::int,
    coalesce(
      (select jsonb_object_agg(locale, cnt) from (
        select locale, count(*)::int as cnt
        from audience
        group by locale
      ) s),
      '{}'::jsonb
    )
  into v_count, v_by_loc
  from audience;

  return jsonb_build_object(
    'count',     v_count,
    'by_locale', v_by_loc
  );
end;
$$;

revoke all on function public.admin_broadcast_estimate(text, jsonb)
  from public;
grant execute on function public.admin_broadcast_estimate(text, jsonb)
  to authenticated;

-- ─────────────── RPC: admin_broadcast_recipients_batch ───────────────
-- Devuelve N users (con su email + locale) que coinciden con el
-- target del broadcast dado, ordenados estable por id y empezando en
-- offset. La Edge Function `broadcast-dispatch` lo invoca en bucle
-- para procesar por lotes.

create or replace function public.admin_broadcast_recipients_batch(
  p_broadcast_id uuid,
  p_offset       int default 0,
  p_limit        int default 50
)
returns table (user_id uuid, email text, locale text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_b record;
  v_offset int := greatest(0, coalesce(p_offset, 0));
  v_limit  int := greatest(1, least(coalesce(p_limit, 50), 200));
begin
  if not public.is_admin() then
    -- service_role tambien pasa (la Edge Function corre con
    -- service_role, que NO entra en is_admin pero pasa porque bypasa
    -- RLS al ser service_role). Para llamadas desde JWT del admin
    -- tambien valida.
    if current_setting('request.jwt.claims', true)::jsonb->>'role'
       <> 'service_role' then
      raise exception 'admin or service_role only';
    end if;
  end if;

  select * into v_b from public.broadcasts where id = p_broadcast_id;
  if not found then
    raise exception 'broadcast_not_found';
  end if;

  return query
  with audience as (
    select
      u.id as user_id,
      u.email,
      coalesce(pf.locale, 'en') as locale
    from auth.users u
    left join public.profiles pf on pf.id = u.id
    left join lateral (
      select coalesce(p.slug, 'free') as plan_slug
      from public.tenant_members tm
      join public.tenant_subscriptions ts on ts.tenant_id = tm.tenant_id
      left join public.plans p on p.id = ts.plan_id
      where tm.user_id = u.id
        and ts.status in ('active', 'trialing')
      limit 1
    ) sub on true
    where
      case v_b.target_type
        when 'all'      then true
        when 'plan'     then coalesce(sub.plan_slug, 'free')
                              = coalesce(v_b.target_value->>'slug', 'free')
        when 'language' then coalesce(pf.locale, 'en')
                              = coalesce(v_b.target_value->>'code', 'en')
        when 'status'   then public._user_status_label(u.banned_until)
                              = coalesce(v_b.target_value->>'status', 'active')
      end
      and u.email is not null
    order by u.id
  )
  select user_id, email, locale
  from audience
  offset v_offset
  limit v_limit;
end;
$$;

revoke all on function public.admin_broadcast_recipients_batch(uuid, int, int)
  from public;
grant execute on function public.admin_broadcast_recipients_batch(uuid, int, int)
  to authenticated;
