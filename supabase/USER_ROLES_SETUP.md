# Roles de usuario — configuración

La app tiene tres roles:

- **admin** — acceso al área de administración (`/admin`) y a componentes
  protegidos.
- **user** — usuario autenticado normal (rol por defecto al registrarse).
- **guest** — estado de la app cuando NO hay sesión. No se guarda en BD.

`admin` y `user` viven en la columna `profiles.role`.

---

## 1. Aplicar la migración

Dashboard de Supabase → **SQL Editor** → **New query** → pega el contenido de
`supabase/migrations/0005_user_roles.sql` → **Run**.

Eso añade la columna `role` (default `'user'`), la función `is_admin()` y un
trigger que impide que un usuario se ascienda a sí mismo a admin.

---

## 2. Nombrar a un administrador

No hay (todavía) pantalla para gestionar roles, así que el primer admin se
asigna a mano. Dashboard → **SQL Editor** → **New query**:

```sql
update public.profiles set role = 'admin'
where id = (select id from auth.users where email = 'TU_EMAIL_AQUI');
```

Sustituye `TU_EMAIL_AQUI` por el email de la cuenta que quieres hacer admin.

> Funciona porque el SQL Editor corre como `service_role`: el trigger
> anti-escalada solo bloquea cambios de rol hechos por usuarios autenticados
> normales desde la app, no los del backend.

Para revertir: el mismo `update` con `role = 'user'`.

---

## 3. Cómo funciona

- **Protección de rutas**: el guard del router redirige a `/home` cualquier
  ruta solo-admin (`/admin`) si el usuario no es admin.
- **Protección de componentes**: el widget `RoleGate` muestra su contenido
  solo si el rol coincide (`RoleGate.admin(child: ...)`).
- **Navegación**: el destino "Admin" del menú lateral solo aparece para
  admins.
- **Seguridad de datos**: aunque alguien fuerce la ruta o manipule el cliente,
  el trigger `profiles_guard_role` impide que se cambie su propio rol, y el
  área `/admin` de momento no expone datos sensibles. Cuando `/admin` maneje
  datos reales, esas tablas deberán tener su propia RLS basada en
  `public.is_admin()`.

---

## 4. Verificación

1. Aplica la migración y hazte admin con el SQL del punto 2.
2. `flutter run -d chrome --web-port 5000`, inicia sesión.
3. En el menú lateral debería aparecer **"Admin"**. Ábrelo → ves el área de
   administración y tu rol (`admin`).
4. Con una cuenta normal (rol `user`): el destino "Admin" NO aparece, y si
   escribes `/admin` en la URL te redirige a `/home`.
