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

## 3 · Plantilla del email "Confirm signup"

**Dashboard → Authentication → Email Templates → Confirm signup**

1. **Subject**: cambiar a → `Verify your account · myapp`
2. **Message body (HTML)**: borrar el contenido por defecto y pegar el de
   `supabase/templates/email/confirm_signup.html`.
3. (Opcional) Cambiar **Sender name** a `myapp` en *Project Settings →
   Auth → SMTP Settings* (con SMTP custom; el SMTP por defecto de Supabase
   tiene rate limit de **3 emails/hora** — suficiente para desarrollo).

Click **Save**.

---

## 4 · Rate limits (opcional pero recomendado)

**Dashboard → Authentication → Rate Limits**

Valores por defecto razonables para empezar (luego los apretamos más):
- **Sign-ups per hour**: `10` (por IP)
- **Email OTPs per hour**: `5`
- **Token refreshes per 5 min**: `30`

---

## 5 · Verificar el flujo

1. Arranca la app:
   ```powershell
   cd C:\VIC_PRO\myapp
   flutter run -d chrome --web-port=5000 --dart-define=ENV=development
   ```
2. Welcome → 🔑 (entrar) → "Create one" → pantalla de **Registro**.
3. Rellena: username (≥3 chars), email, contraseña fuerte (8+ con
   mayúscula/minúscula/dígito/especial), repetir, checkbox términos →
   **Create account**.
4. Debe navegar a **"Check your inbox"** mostrando tu email.
5. Abre tu inbox → email **"Verify your account · myapp"** con botón azul.
6. Click → vuelves a la app en `/auth/callback` → spinner → **"Account
   verified!"** → botón **Sign in** → vuelves al login.

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

Cuando todo lo anterior funcione, abriremos la siguiente iteración:
- Login real (email+password) sobre la misma estructura de card fija.
- Recuperar contraseña + plantilla `reset_password.html`.
- Cambio de email + cambio de password en el panel privado.
- Magic Link → OTP → MFA → OAuth Google/Apple.
