-- ============================================================================
-- 0028 · App Branding + Setup state + Registration gate
-- ----------------------------------------------------------------------------
-- Hace que este SaaS sea **multi-marca**: el mismo codigo se puede
-- desplegar en N dominios y cada uno lleva su nombre comercial, logo,
-- favicon, paleta de colores, etc. configurados desde la UI -- sin
-- recompilar.
--
-- Tres pilares:
--
--   1) `app_branding`: tabla singleton (un solo row) con la config
--      visual y comercial del despliegue. Lectura PUBLICA porque el
--      AppBar/welcome la necesita antes de cualquier login. Escritura
--      admin-only via RLS.
--
--   2) `setup_completed` flag DENTRO de app_branding: a primera carga
--      el cliente lo lee y si es false redirige a `/setup` (wizard
--      de primera vez). Lo flippea a true al final del wizard.
--
--   3) `registration_enabled` flag DENTRO de app_branding: gate global
--      del `/register`. Permite cerrar el registro al subir a produccion
--      y abrirlo cuando todo este listo, sin tocar codigo.
--
-- Tambien anyadimos `commercial_name` y derivados que se inyectan en
-- emails (cuando los construyamos), en el title de la pestaña, etc.
--
-- **Por que un solo row** y no multi-tenant:
-- La tabla representa al PROYECTO (deployment), no al tenant. Cada
-- despliegue es un proyecto Supabase distinto -> una BD distinta ->
-- una sola fila. Si en el futuro quisieras white-label multi-tenant
-- por subdominio, eso seria otra tabla aparte.
--
-- Aplicar:
--   - supabase db push
-- ============================================================================

-- ─────────────────────────── Tabla ───────────────────────────
-- Truco para forzar un solo row: PK = boolean fijo `true` + check.
-- Cualquier intento de insertar un segundo row dispara unique violation.

create table if not exists public.app_branding (
  id                      boolean primary key default true check (id),

  -- Identidad comercial
  commercial_name         text not null default 'myapp'
                          check (char_length(commercial_name) between 1 and 80),
  tagline                 text
                          check (tagline is null or char_length(tagline) <= 160),
  support_email           text
                          check (support_email is null
                                 or support_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  -- URL "homepage" para footers y emails
  website_url             text
                          check (website_url is null or website_url ~* '^https?://'),

  -- Recursos visuales (URLs publicas — Supabase Storage o externas)
  logo_url                text
                          check (logo_url is null or logo_url ~* '^https?://'),
  logo_dark_url           text  -- variante para tema oscuro (opcional)
                          check (logo_dark_url is null or logo_dark_url ~* '^https?://'),
  favicon_url             text
                          check (favicon_url is null or favicon_url ~* '^https?://'),
  og_image_url            text  -- para previsualizaciones en redes (OG)
                          check (og_image_url is null or og_image_url ~* '^https?://'),

  -- Paleta: slug que mapea a uno de los presets hardcoded en Flutter
  -- ('blue', 'green', 'purple', 'orange', 'mono'). Si se introduce
  -- otro valor, el cliente cae al default 'blue'.
  color_palette           text not null default 'blue'
                          check (char_length(color_palette) between 1 and 30),

  -- Flags de estado del proyecto
  setup_completed         boolean not null default false,
  registration_enabled    boolean not null default false,

  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- Insertar el unico row si no existe.
insert into public.app_branding (id) values (true)
on conflict (id) do nothing;

-- Trigger touch updated_at.
create or replace function public.app_branding_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists app_branding_touch on public.app_branding;
create trigger app_branding_touch
  before update on public.app_branding
  for each row execute function public.app_branding_touch_updated_at();

-- ─────────────────────────── RLS ───────────────────────────
-- Lectura: cualquier (incluido anon) porque el AppBar/welcome
-- necesita pintarse antes del login. Sin secretos en la tabla.
-- Escritura: solo admin via helper public.is_admin().

alter table public.app_branding enable row level security;

drop policy if exists "app_branding_select_public" on public.app_branding;
create policy "app_branding_select_public"
  on public.app_branding for select
  to anon, authenticated
  using (true);

drop policy if exists "app_branding_admin_update" on public.app_branding;
create policy "app_branding_admin_update"
  on public.app_branding for update
  using (public.is_admin())
  with check (public.is_admin());

-- NO INSERT ni DELETE policies -- la fila ya existe y debe permanecer.

-- ────── Extender trigger anti-escalada para permitir bootstrap ──────
-- El trigger original (migracion 0005) bloquea cualquier cambio de
-- role que no venga de un admin. Lo extendemos para que respete un
-- flag de sesion `app.bootstrap_first_admin` que la RPC de abajo
-- setea TEMPORALMENTE (is_local = true => se limpia al finalizar la
-- transaccion). Asi mantenemos la defensa contra escalation en
-- updates normales, pero permitimos el caso legitimo de bootstrap.

create or replace function public.prevent_role_self_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and auth.uid() is not null
     and current_setting('app.bootstrap_first_admin', true)
         is distinct from 'true'
     and not public.is_admin() then
    new.role := old.role;
  end if;
  return new;
end;
$$;

-- ─────────────── RPC: bootstrap_first_admin ───────────────
-- Convierte al user llamante en admin SI Y SOLO SI no hay ningun
-- admin todavia en la BD. Idempotente y segura: una vez que existe
-- un admin (creado por este RPC o por SQL manual), la llamada es no-op.
--
-- Esto es lo que hace /setup tras pedir email + password y registrar
-- al user via auth.signUp. Sin esto, no podrias bootstrappear el primer
-- admin sin tocar SQL manualmente.
--
-- Tambien marca app_branding.setup_completed = true para que las
-- siguientes cargas no vuelvan al wizard.

create or replace function public.bootstrap_first_admin()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_admin boolean;
  v_uid       uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'auth.uid() is null -- must be called by an authenticated user';
  end if;

  -- Comprobacion atomica: si ya existe un admin, no hacemos nada.
  -- (race condition window mitigada por el setup_completed flag que
  --  /setup chequea antes de llamar, y por el hecho de que solo el
  --  PRIMER usuario en condiciones de race podria llegar aqui.)
  select exists(
    select 1 from public.profiles where role = 'admin'
  ) into v_has_admin;

  if v_has_admin then
    return false;
  end if;

  -- Set local flag para que el trigger nos deje promocionarnos.
  -- Se limpia automaticamente al terminar la transaccion (is_local=true).
  perform set_config('app.bootstrap_first_admin', 'true', true);

  -- Promovemos al user actual a admin.
  update public.profiles
    set role = 'admin'
    where id = v_uid;

  -- Marcamos setup_completed = true para cerrar el wizard.
  update public.app_branding
    set setup_completed = true
    where id = true;

  return true;
end;
$$;

revoke all on function public.bootstrap_first_admin() from public;
grant execute on function public.bootstrap_first_admin() to authenticated;
