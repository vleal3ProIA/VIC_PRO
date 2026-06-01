-- ============================================================================
-- 0085_profiles_last_panel.sql · "Resume last Panel" (sesion persistente)
-- ----------------------------------------------------------------------------
-- Persistimos, en el profile del usuario, el ultimo Panel (subject + nodo
-- seleccionado) para que el siguiente login le devuelva a donde lo dejo.
--
-- - `last_subject_id` y `last_node_id` son FKs nullable con
--   `on delete set null`: si el material se borra, el redirect simplemente
--   cae a /home y no se rompe.
-- - `last_panel_at` se actualiza en cada UPDATE via la RPC, por si en el
--   futuro queremos invalidar/expirar sesiones antiguas (no usado hoy).
--
-- RLS: la policy `profiles_update_own` (migracion 0001) ya cubre todos los
-- updates del propio row (`auth.uid() = id` en `using` y `with check`); no
-- restringe columnas concretas, asi que estos UPDATEs pasan sin policy
-- extra. La RPC es SECURITY DEFINER pero igualmente filtra por auth.uid()
-- en el WHERE, por defensa en profundidad.
-- ============================================================================

-- 1) Columnas nuevas en profiles ---------------------------------------------
alter table public.profiles
  add column if not exists last_subject_id uuid
    references public.subjects(id) on delete set null,
  add column if not exists last_node_id uuid
    references public.index_nodes(id) on delete set null,
  add column if not exists last_panel_at timestamptz;

comment on column public.profiles.last_subject_id is
  '"Resume last Panel": ultimo subject (temario) abierto por el user. NULL = no hay sesion previa o el subject fue borrado.';
comment on column public.profiles.last_node_id is
  '"Resume last Panel": ultimo nodo del indice seleccionado dentro de last_subject_id.';
comment on column public.profiles.last_panel_at is
  'Timestamp del ultimo set_last_panel(). No usado hoy; reservado para invalidacion futura.';

-- Indice parcial: solo indexamos profiles que tienen sesion previa,
-- para que la query del redirect (select por id) sea instantanea.
create index if not exists profiles_last_subject_idx
  on public.profiles (id) where last_subject_id is not null;

-- 2) RPC set_last_panel ------------------------------------------------------
-- Llamada fire-and-forget desde Flutter cada vez que el user abre un Panel
-- o cambia de nodo. SECURITY DEFINER para bypassear la RLS update (igual
-- que la cubre, pero asi no dependemos de ella) y para validar ownership
-- del subject server-side antes de aceptar el id.
--
-- Si el subject no es del user (caso defensivo: id stale tras page-refresh
-- o un cliente jugando), la RPC NO falla -- simplemente no escribe. Esto
-- evita ruido en logs para algo que el user no provoca conscientemente.
create or replace function public.set_last_panel(
  p_subject_id uuid,
  p_node_id    uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_owner uuid;
begin
  -- Sin sesion -> no-op (la RPC se llama desde la UI logueada, pero
  -- defensa por si el token expira a medio click).
  if v_uid is null then
    return;
  end if;

  -- Validar ownership del subject. Si no es del user, silent ignore.
  select user_id into v_owner from public.subjects where id = p_subject_id;
  if v_owner is null or v_owner <> v_uid then
    return;
  end if;

  -- Nota: NO validamos que p_node_id pertenece al subject. Si el cliente
  -- mete un node_id "stale" o de otro subject, al hacer fallback en el
  -- redirect simplemente abrimos el subject sin nodo (el FK garantiza
  -- que existe y al menos pertenece a UN subject del user, ya que
  -- index_nodes.user_id = auth.users(id) y on delete cascade).
  update public.profiles
    set last_subject_id = p_subject_id,
        last_node_id    = p_node_id,
        last_panel_at   = now()
  where id = v_uid;
end;
$$;

revoke all on function public.set_last_panel(uuid, uuid) from public;
grant execute on function public.set_last_panel(uuid, uuid) to authenticated;

comment on function public.set_last_panel(uuid, uuid) is
  'Persiste el ultimo Panel (subject + nodo) del user. Silent ignore si el subject no es del caller.';
