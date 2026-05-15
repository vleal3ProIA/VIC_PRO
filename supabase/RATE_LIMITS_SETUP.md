# Rate limiting de Edge Functions

Las Edge Functions sensibles (`delete-account`, `mfa-recovery`, `webauthn`)
incorporan rate limiting basado en una **ventana deslizante** almacenada en
BD. Sin esto, un atacante podría:

- Hacer fuerza bruta sobre códigos de recuperación de MFA o passkeys.
- Spam de generación de challenges para saturar la BD/Edge.
- Re-intentos masivos de borrado de cuenta (poco peligroso pero feo).

---

## 1. Aplicar la migración

Dashboard de Supabase → **SQL Editor** → **New query** → pega el contenido de
`supabase/migrations/0007_rate_limits.sql` → **Run**.

Crea la tabla `edge_rate_limits` (cuenta los usos), la función SQL
`check_rate_limit(bucket, limit, window_seconds)` que las Edge Functions
llaman por RPC, y `cleanup_edge_rate_limits()` para purgar entradas viejas.

---

## 2. Re-desplegar las Edge Functions

Las Edge Functions ahora importan un helper compartido
(`supabase/functions/_shared/rate_limit.ts`). En **cada función** sustituye
el contenido por el del repo y vuelve a desplegar:

- `delete-account` → pega `supabase/functions/delete-account/index.ts`.
- `mfa-recovery` → pega `supabase/functions/mfa-recovery/index.ts`.
- `webauthn` → pega `supabase/functions/webauthn/index.ts`.

> ⚠️ Si despliegas desde el **dashboard**, en cada función tendrás que pegar
> el contenido COMPLETO del nuevo `index.ts` (el dashboard no tiene el
> archivo compartido `_shared/rate_limit.ts` — Supabase mira la carpeta
> al desplegar vía CLI, pero el editor web solo ve UN archivo).
>
> Workaround: pega el contenido del helper inline al principio del `index.ts`
> antes del `Deno.serve(...)`. La estructura del helper es pequeña y aislada.
>
> **Vía CLI** (mejor, lo respeta tal cual):
> ```powershell
> supabase functions deploy delete-account
> supabase functions deploy mfa-recovery
> supabase functions deploy webauthn
> ```

---

## 3. Límites configurados

| Función / acción            | Scope     | Límite          | Ventana    | Por qué |
|-----------------------------|-----------|-----------------|------------|---------|
| `delete-account`            | user      | 3               | 1 hora     | Destructivo e infrecuente. |
| `mfa-recovery/generate`     | user      | 5               | 1 hora     | Solo al activar MFA o regenerar. |
| `mfa-recovery/verify`       | user      | 10              | 15 min     | Anti-fuerza bruta de códigos. |
| `webauthn/register-options` | user      | 20              | 1 hora     | Registrar passkey es raro. |
| `webauthn/register-verify`  | user      | 20              | 1 hora     | Idem. |
| `webauthn/auth-options`     | IP        | 30              | 1 min      | Anti-DoS — no hay user previo. |
| `webauthn/auth-verify`      | IP        | 10              | 15 min     | Anti-fuerza bruta — la mayor protección. |

Si el límite se supera la función responde **HTTP 429** con
`{"error":"rate_limited"}`. La app lo mapea a `AuthRateLimited` y muestra
"Demasiados intentos. Inténtalo más tarde." al usuario.

---

## 4. Tuning y mantenimiento

- **Subir/bajar un límite**: cambia los valores directamente en el
  `index.ts` correspondiente y vuelve a desplegar. No hace falta migración.
- **Reset rápido para tests**: borra las filas del `bucket_key` afectado:
  ```sql
  delete from public.edge_rate_limits
    where bucket_key like 'mfa-recovery-verify:user:%';
  ```
- **Cleanup periódico** (opcional): si tienes pg_cron habilitado, programa
  `cleanup_edge_rate_limits()` para correr una vez al día. Si no, ejecútala
  a mano cada cierto tiempo desde el SQL Editor:
  ```sql
  select public.cleanup_edge_rate_limits();
  ```
- **Política de fallo**: si la RPC `check_rate_limit` falla (BD caída,
  permisos), el helper devuelve `true` (permite la llamada). Preferimos
  fail-open: bloquear a usuarios legítimos por un fallo del backend de
  rate limiting es peor que no rate-limitar puntualmente.

---

## 5. Verificación

1. Aplica la migración y re-despliega las 3 funciones.
2. `flutter run -d chrome --web-port 5000`. Inicia sesión con un usuario.
3. **Test rápido**: ve a Ajustes → Eliminar cuenta y haz 3 intentos
   (escribiendo mal la contraseña). Al 4º deberías ver el mensaje de
   "demasiados intentos".
4. Verifica en el dashboard → **Table Editor → edge_rate_limits**: las
   filas con `bucket_key = 'delete-account:user:<tu-id>'` están ahí.
5. Espera 1 hora o borra esas filas manualmente para resetear.
