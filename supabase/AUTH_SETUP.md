# Supabase Auth setup (Fase 2)

Pasos manuales en el dashboard de Supabase para que el registro funcione
end-to-end con tu app local.

> **Proyecto**: `myapp-dev` · ref `jzgtghddqofxewzmpmbx`

---

## 1 · URL Configuration

**Dashboard → Authentication → URL Configuration**

| Campo | Valor |
|---|---|
| **Site URL** | `http://localhost:5000` |
| **Redirect URLs** (añadir todas) | `http://localhost:5000/**`<br>`http://localhost:5000/auth/callback`<br>*(en producción añadiremos `https://tu-dominio/**`)* |

> El SDK de Flutter calcula `redirectTo` dinámicamente con `Uri.base`. El
> patrón con `/**` admite cualquier path debajo de `localhost:5000`, así no
> hay que retocar nada cada vez que añadimos rutas.

Click **Save**.

---

## 2 · Confirm email habilitado

**Dashboard → Authentication → Providers → Email**

- ✅ **Enable Email Provider** debe estar ON.
- ✅ **Confirm email** debe estar ON (es lo que dispara el envío del email
  de verificación tras `signUp`).
- ⚠️ **Secure email change** ON (recomendado para Fase de cambio de email).
- ⚠️ **Secure password change** ON.

Click **Save**.

---

## 3 · Plantillas de email

### 3.1 · Confirm signup

**Dashboard → Authentication → Email Templates → Confirm signup**

1. **Subject**: cambiar a → `Verify your account · myapp`
2. **Message body (HTML)**: borrar el contenido por defecto y pegar el de
   `supabase/templates/email/confirm_signup.html`.

### 3.2 · Reset password

**Dashboard → Authentication → Email Templates → Reset password**

1. **Subject**: cambiar a → `Reset your password · myapp`
2. **Message body (HTML)**: pegar el de
   `supabase/templates/email/reset_password.html`.

### 3.3 · Magic Link

**Dashboard → Authentication → Email Templates → Magic Link**

1. **Subject**: cambiar a → `Your sign-in link · myapp`
2. **Message body (HTML)**: pegar el de
   `supabase/templates/email/magic_link.html`.

> (Opcional) Cambiar **Sender name** a `myapp` en *Project Settings →
> Auth → SMTP Settings* (con SMTP custom; el SMTP por defecto de Supabase
> tiene rate limit de **3 emails/hora** — suficiente para desarrollo).

Click **Save** en cada plantilla.

---

## 4 · Rate limits (opcional pero recomendado)

**Dashboard → Authentication → Rate Limits**

Valores por defecto razonables para empezar (luego los apretamos más):
- **Sign-ups per hour**: `10` (por IP)
- **Email OTPs per hour**: `5`
- **Token refreshes per 5 min**: `30`

---

## 5 · Verificar los flujos

```powershell
cd C:\VIC_PRO\myapp
flutter run -d chrome --web-port=5000 --dart-define=ENV=development
```

### 5.1 · Registro + verificación

1. Welcome → 🔑 → "Create one" → **Registro**.
2. Rellena los 4 campos + acepta términos → **Create account**.
3. → **"Check your inbox"** con tu email.
4. Abre el email → click en el botón azul.
5. → `/auth/callback?type=signup` → spinner → **"Account verified!"** →
   **Sign in** → vuelves al login.

### 5.2 · Login

1. En la pantalla de login mete el email + password verificados.
2. **Sign in** → el guard del router te lleva a `/home`.
3. En `/home` debes ver: avatar + "Bienvenido, {username}" + tu email +
   botón de **Sign out** en la app bar.
4. Sign out → vuelves a `/welcome`.

### 5.3 · Recuperar contraseña

1. Login → **"Forgot password?"** → introduce tu email → **Send reset link**.
2. → **"Check your inbox"**.
3. Abre el email **"Reset your password · myapp"** → botón **Reset my password**.
4. → `/auth/callback?type=recovery` → spinner → **"Choose a new password"**.
5. Introduce contraseña nueva + confirmar → **Update password**.
6. → **"Password updated"** → **Sign in** → entra con la nueva contraseña.

### 5.4 · Magic Link (passwordless)

1. Login → **"Sign in with magic link"** → introduce tu email → **Send magic link**.
2. → **"Check your inbox"**.
3. Abre el email **"Your sign-in link · myapp"** → botón **Sign in to myapp**.
4. → `/auth/callback?type=magiclink` → spinner → directamente a **`/home`**
   (sin pasar por login, la sesión ya está activa).

> Si el email aún no estaba registrado, el magic link **lo crea
> automáticamente** y abre sesión. Es signup + login en un mismo flujo.

### Si algo falla

- **No llega el email**: revisa spam. Si sigues sin recibirlo, el SMTP
  built-in de Supabase puede haber agotado tu cuota (3/h). Espera o
  configura SMTP propio.
- **El link da error**: comprueba que la URL de tu navegador está en la
  lista de **Redirect URLs** del paso 1.
- **"Email rate limit exceeded"**: espera o cambia de email de prueba
  (puedes usar alias tipo `tu+test1@gmail.com`).

---

## 6 · Próximos pasos automáticos

- OTP (código de 6 dígitos por email) — comparte backend con Magic Link.
- MFA (TOTP con Google Authenticator/Authy).
- OAuth Google + Apple.
- WebAuthn / Passkeys (la "biometría" del web).
- Panel privado completo (settings: idioma + tema persistente en
  `profiles.locale` y `profiles.theme_mode`).
- Cambio de email desde el panel privado.
- GDPR: borrado de cuenta + export de datos.
