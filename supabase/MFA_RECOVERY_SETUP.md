# Códigos de recuperación de MFA — despliegue

Los códigos de recuperación permiten recuperar el acceso si pierdes la app
autenticadora (Google Authenticator, Authy…). Necesitan **dos cosas** en
Supabase:

1. La **migración `0003`** — crea la tabla donde se guardan los códigos (solo
   su hash).
2. La **Edge Function `mfa-recovery`** — genera y verifica los códigos con la
   `service_role` key del lado servidor.

Todo gratis en el free tier.

---

## 1. Aplicar la migración

Dashboard de Supabase → **SQL Editor** → **New query** → pega el contenido de
`supabase/migrations/0003_mfa_recovery_codes.sql` → **Run**.

Comprueba: **Table Editor** → debe aparecer `mfa_recovery_codes`.

---

## 2. Desplegar la Edge Function

### Opción A — Dashboard (sin instalar nada)

1. Dashboard → menú lateral **Edge Functions** → **Create a new function**.
2. Nombre **exacto**: `mfa-recovery`
3. Borra el código de ejemplo y pega el contenido de
   `supabase/functions/mfa-recovery/index.ts`.
4. **Deploy function**.

### Opción B — CLI

```powershell
supabase functions deploy mfa-recovery
```

No hay que configurar secretos: `SUPABASE_URL`, `SUPABASE_ANON_KEY` y
`SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase automáticamente.

---

## 3. Cómo funciona

- **Al activar MFA**: tras verificar el código del autenticador, la app llama
  a `mfa-recovery` con `action: "generate"`. La función exige que el usuario
  esté a **AAL2** (acaba de pasar el 2FA) — si no, sería un bypass del segundo
  factor. Genera 10 códigos, guarda solo el hash y devuelve los 10 en claro
  **una única vez**. La app los muestra para que el usuario los guarde.

- **Al iniciar sesión sin el autenticador**: en la pantalla de desafío MFA hay
  un enlace "Usar un código de recuperación". El usuario introduce uno; la app
  llama a `mfa-recovery` con `action: "verify"`. Si es válido:
  - se marca como usado (cada código sirve una sola vez),
  - se **eliminan los factores TOTP** del usuario → deja de requerirse AAL2,
  - la app refresca la sesión y entra a `/home`.
  - El usuario debería **volver a configurar MFA** desde Ajustes.

---

## 4. Verificación

1. `flutter run -d chrome --web-port 5000`.
2. Inicia sesión con un usuario de prueba y activa MFA (Ajustes → Seguridad →
   Activar 2FA). Tras verificar el código, verás los **10 códigos de
   recuperación** — cópialos.
3. Cierra sesión e inicia sesión otra vez: te pedirá el código MFA.
4. Pulsa **"Usar un código de recuperación"**, mete uno de los 10.
5. Deberías entrar a `/home`. En **Table Editor → mfa_recovery_codes** ese
   código aparece con `used_at` relleno; los factores del usuario en
   **Authentication → Users** han desaparecido.

### Errores típicos

| Error | Causa |
|---|---|
| Error genérico al activar MFA | La función no está desplegada o el nombre no es `mfa-recovery`. |
| `aal2_required` | Se intentó generar códigos sin haber pasado el 2FA primero. |
| "Código incorrecto" siempre | La migración 0003 no se aplicó, o el código se introdujo mal. |
| `CORS` en consola | El `index.ts` desplegado no es el del repo. |

---

## 5. Notas

- Los códigos se guardan **solo como hash SHA-256**. Ni Supabase ni la app
  pueden recuperarlos: si el usuario los pierde, debe regenerarlos (volviendo
  a activar MFA).
- Cada código es de **un solo uso**.
- Usar un código de recuperación **desactiva el MFA** del usuario. Es el
  comportamiento estándar: el código te saca del bloqueo, y vuelves a
  configurar el 2FA cuando tengas de nuevo tu autenticador.
