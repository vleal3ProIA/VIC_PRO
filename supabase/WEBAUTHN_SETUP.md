# Passkeys / WebAuthn — despliegue

Esta función habilita el login con **passkeys** (Touch ID, Windows Hello,
Face ID, llaves de seguridad…) sin contraseña.

Necesita **dos cosas** en Supabase:

1. La **migración `0006`** — crea las tablas `webauthn_credentials` y
   `webauthn_challenges` con RLS.
2. La **Edge Function `webauthn`** — hace la "ceremonia" WebAuthn del lado
   servidor (genera challenges, verifica firmas) y emite la sesión Supabase
   al validar.

Todo gratis en el free tier.

---

## 1. Aplicar la migración

Dashboard de Supabase → **SQL Editor** → **New query** → pega el contenido de
`supabase/migrations/0006_webauthn.sql` → **Run**.

Comprueba: **Table Editor** → deben aparecer `webauthn_credentials` y
`webauthn_challenges`.

---

## 2. Desplegar la Edge Function

### Opción A — Dashboard

1. Dashboard → **Edge Functions** → **Create a new function**.
2. Nombre **exacto**: `webauthn`
3. Borra el código de ejemplo y pega el contenido de
   `supabase/functions/webauthn/index.ts`.
4. **Deploy function**.

> Esta función importa `@simplewebauthn/server` vía npm. Supabase Edge
> Functions soporta `npm:` specifiers desde hace tiempo — no requiere nada
> adicional.

### Opción B — CLI

```powershell
supabase functions deploy webauthn
```

No hay que configurar secretos: `SUPABASE_URL`, `SUPABASE_ANON_KEY` y
`SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase automáticamente.

---

## 3. Cómo funciona

**Registrar un passkey** (usuario logueado):
1. Ajustes → Seguridad → **Añadir passkey**.
2. La app pide a la función `register-options` un challenge.
3. El navegador llama a `navigator.credentials.create()` → te pide
   biometría / PIN / llave física.
4. La app envía la respuesta a `register-verify` → la función verifica la
   firma, guarda la public key en `webauthn_credentials`.

**Iniciar sesión con passkey** (sin estar logueado):
1. En `/login`, botón **"Entrar con passkey"**.
2. La app pide a `auth-options` un challenge.
3. El navegador llama a `navigator.credentials.get()` → te pide biometría;
   el sistema operativo te muestra los passkeys disponibles para este sitio.
4. La app envía la respuesta a `auth-verify` → la función verifica la firma,
   identifica al usuario por la public key almacenada, y pide a Supabase
   un token de magic link (admin API).
5. La función devuelve `{tokenHash, email}` → la app llama a
   `auth.verifyOTP(token_hash, type=magiclink)` → **sesión Supabase real**.

**rpId dinámico**: la función deriva el dominio (`localhost`, tu dominio
de producción, etc.) del header `Origin` del request. Sin tocar código.

**Importante sobre dominios**: un passkey está atado al `rpId`
(`localhost`, `app.example.com`…). Un passkey registrado en localhost NO
funciona en producción, y viceversa. Cada entorno tiene los suyos.

---

## 4. Verificación

1. `flutter run -d chrome --web-port 5000`.
2. Inicia sesión con email + contraseña.
3. **Ajustes → Seguridad → Añadir passkey** → tu navegador te pedirá
   biometría / Windows Hello / Touch ID.
4. Cierra sesión.
5. En `/login`, pulsa **"Entrar con passkey"** → el navegador te muestra el
   passkey guardado → biometría → entras a `/home` sin contraseña.

En el dashboard → **Table Editor → webauthn_credentials**: debería aparecer
una fila con tu `user_id` y `credential_id`. La `public_key` está guardada
pero NUNCA la private key (esa solo vive en tu dispositivo).

### Errores típicos

| Error | Causa |
|---|---|
| El navegador no muestra el selector de passkey | Tu navegador no soporta WebAuthn (raro en navegadores modernos), o el sitio no es seguro (sin HTTPS y no es `localhost`). |
| "Verification failed" al añadir | El `rpId` cambió entre options y verify (cambio de dominio entre llamadas). |
| "Credential not found" al entrar | Estás intentando entrar en un dominio donde nunca registraste el passkey. |
| `CORS` en consola | El `index.ts` desplegado no es el del repo. |

---

## 5. Soporte de navegadores

WebAuthn está soportado en TODOS los navegadores modernos:

- **Chrome / Edge** — Touch ID (macOS), Windows Hello, Android, llaves USB.
- **Safari** — Touch ID, Face ID, iCloud Keychain (sincroniza entre Apple
  devices).
- **Firefox** — soporte completo desde 2023.

En móvil: Android usa la huella / cara / PIN del dispositivo. iOS Safari usa
Face ID / Touch ID con iCloud Keychain (los passkeys se sincronizan a otros
dispositivos Apple del usuario).
