# Borrado de cuenta — despliegue de la Edge Function

El borrado de cuenta (derecho de supresión / "derecho al olvido" del GDPR)
necesita una **Edge Function** llamada `delete-account`, porque eliminar un
usuario de `auth.users` requiere la `service_role` key, que **nunca** puede
estar en la app cliente.

El código ya está en el repo: `supabase/functions/delete-account/index.ts`.
Solo tienes que desplegarlo. Es **gratis** en el free tier de Supabase.

---

## Opción A — Supabase CLI (recomendado)

### A.1 — Instalar la CLI (una sola vez)

Windows (PowerShell, con [Scoop](https://scoop.sh/)):

```powershell
scoop install supabase
```

O descarga el binario desde <https://github.com/supabase/cli/releases>.

Comprueba que funciona:

```powershell
supabase --version
```

### A.2 — Vincular el proyecto (una sola vez)

Desde la raíz del repo (`C:\VIC_PRO\myapp`):

```powershell
supabase login
supabase link --project-ref jzgtghddqofxewzmpmbx
```

`supabase login` abre el navegador para autenticarte. El `project-ref` es el
identificador de tu proyecto (lo ves en la URL del dashboard).

### A.3 — Desplegar la función

```powershell
supabase functions deploy delete-account
```

Eso es todo. **No hace falta configurar secretos**: `SUPABASE_URL`,
`SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase
automáticamente en todas las Edge Functions.

Para re-desplegar tras un cambio, repite solo A.3.

---

## Opción B — Dashboard (sin CLI)

1. Dashboard de Supabase → tu proyecto → menú lateral **Edge Functions**.
2. **Create a new function** → nombre exacto: `delete-account`.
3. Pega el contenido de `supabase/functions/delete-account/index.ts` en el
   editor del dashboard.
4. **Deploy**.

---

## Verificación

1. `flutter run -d chrome --web-port 5000`.
2. Inicia sesión con un usuario de prueba (que tenga contraseña).
3. **Ajustes → Seguridad → Eliminar cuenta**.
4. Introduce la contraseña, marca la casilla de confirmación y confirma en el
   diálogo.
5. Deberías volver a la pantalla de bienvenida con la sesión cerrada.
6. En el dashboard → **Authentication → Users**: el usuario ya no aparece.
   En **Table Editor → profiles**: su fila tampoco (se fue por `cascade`).

### Errores típicos

| Error en la app | Causa |
|---|---|
| "Contraseña actual incorrecta" | La reautenticación falló: contraseña mal escrita. |
| Error genérico tras confirmar | La función no está desplegada o el nombre no es exactamente `delete-account`. |
| `CORS` en consola del navegador | La función no incluye los headers CORS — usa el `index.ts` del repo tal cual. |

---

## Notas

- **Usuarios solo-OAuth (Google/Apple sin contraseña)**: el flujo actual pide
  la contraseña para reautenticar. Un usuario que se registró solo con Google
  no tiene contraseña; para esos casos habría que añadir más adelante un flujo
  alternativo (p. ej. confirmar escribiendo el email). De momento, la mayoría
  de cuentas son de email + contraseña.
- **Seguridad**: la función solo borra al usuario dueño del JWT con el que se
  invoca. Nadie puede borrar la cuenta de otro. Además la app reautentica con
  contraseña antes de llamarla.
- **Auditoría**: si más adelante quieres registrar las bajas (sin datos
  personales), se puede añadir una tabla `account_deletions` que la función
  rellene con la fecha y un hash del id. No se incluye ahora para no almacenar
  datos de cuentas ya borradas.
