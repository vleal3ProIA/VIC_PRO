# OAuth — "Continuar con Google"

Guía paso a paso para activar el login con Google. Hay **dos consolas**: Google
Cloud (donde se crea la credencial OAuth) y Supabase (donde se pega esa
credencial). La app **no** necesita ningún secreto en `.env` — solo llama a
`signInWithOAuth`.

---

## 1. Google Cloud Console — crear la credencial OAuth

1. Entra en <https://console.cloud.google.com/>.
2. Arriba, crea un proyecto nuevo (o selecciona uno existente). Nombre: `myapp`.
3. Menú lateral → **APIs y servicios → Pantalla de consentimiento de OAuth**
   (*OAuth consent screen*):
   - Tipo de usuario: **External** → *Create*.
   - App name: `myapp`. Correo de soporte: el tuyo.
   - *Developer contact*: el tuyo. Guarda y continúa.
   - **Scopes**: no añadas nada extra → *Save and continue*.
   - **Test users**: añade tu propio email mientras la app esté en modo
     "Testing" (si no, Google bloquea el login). *Save and continue*.
4. Menú lateral → **APIs y servicios → Credenciales** → *Crear credenciales* →
   **ID de cliente de OAuth**:
   - Tipo de aplicación: **Aplicación web**.
   - Nombre: `myapp-web`.
   - **Orígenes autorizados de JavaScript** (*Authorized JavaScript origins*):
     - `http://localhost:5000` (desarrollo local)
     - `https://<tu-dominio-de-produccion>` (cuando despliegues)
   - **URIs de redirección autorizados** (*Authorized redirect URIs*) — aquí va
     **la URL de Supabase, no la de tu app**:
     - `https://<TU-PROYECTO>.supabase.co/auth/v1/callback`
       (la encuentras en el paso 2 de Supabase, abajo).
   - *Crear*.
5. Google te muestra **Client ID** y **Client Secret**. Cópialos — los pegas en
   Supabase en el siguiente paso.

---

## 2. Supabase Dashboard — activar el proveedor Google

1. Entra en <https://supabase.com/dashboard> → tu proyecto.
2. Menú lateral → **Authentication → Providers** (o *Sign In / Providers*).
3. Localiza **Google** en la lista y actívalo (*Enable*).
4. Pega:
   - **Client ID** → el del paso 1.5
   - **Client Secret** → el del paso 1.5
5. Justo encima verás el campo **Callback URL (for OAuth)** con el valor
   `https://<TU-PROYECTO>.supabase.co/auth/v1/callback`. **Ese** es el que
   tienes que haber puesto en Google Cloud (paso 1.4). Si no coincide, el login
   falla con `redirect_uri_mismatch`.
6. *Save*.

---

## 3. Supabase — Redirect URLs de la app

El login termina volviendo a **tu** app, así que el origen de la app debe estar
permitido:

1. **Authentication → URL Configuration**.
2. En **Redirect URLs**, asegúrate de tener (ya deberían estar de los flujos de
   email):
   - `http://localhost:5000/**`
   - `https://<tu-dominio-de-produccion>/**`

La app redirige a `…/auth/callback?type=oauth`, que encaja con esos patrones.

---

## 4. Cómo funciona en la app (resumen técnico)

- El botón **"Continuar con Google"** (login y registro) llama a
  `AuthRepository.signInWithGoogle()`.
- Eso ejecuta `signInWithOAuth(OAuthProvider.google, redirectTo: …/auth/callback?type=oauth)`.
- En web es un **redirect de página completa**: el navegador va a Google, el
  usuario acepta, y Google devuelve a Supabase, que a su vez devuelve a la app
  en `/auth/callback?type=oauth` con la sesión en el fragmento de la URL.
- `AuthCallbackPage` detecta `type=oauth`, espera a que el SDK ponga la sesión
  y redirige a `/home`.
- Como es un redirect completo, `OAuthNotifier` solo gestiona el caso de
  **error al iniciar** el redirect (no hay "resultado" que esperar en la misma
  pestaña).

---

## 5. Verificación

1. `flutter run -d chrome --web-port 5000`.
2. En `/login` pulsa **"Continuar con Google"**.
3. Elige tu cuenta de Google (debe estar en *Test users* si la app está en
   modo Testing).
4. Deberías acabar en `/home` con la sesión iniciada.

### Errores típicos

| Error                          | Causa                                                                 |
|--------------------------------|-----------------------------------------------------------------------|
| `redirect_uri_mismatch`        | La *Authorized redirect URI* de Google no es exactamente la Callback URL de Supabase. |
| `Acceso bloqueado` / `403`     | Tu email no está en *Test users* y la app sigue en modo Testing.      |
| Vuelve a `/login` sin sesión   | El origen de la app no está en *Redirect URLs* de Supabase.           |
| `provider is not enabled`      | El proveedor Google no está activado en Supabase.                     |

---

## 6. Pasar a producción

- En la **pantalla de consentimiento** de Google Cloud, pulsa *Publish app*
  para salir del modo Testing (entonces cualquier usuario de Google puede
  entrar, no solo los *Test users*).
- Añade el dominio de producción tanto en **Authorized JavaScript origins**
  (Google) como en **Redirect URLs** (Supabase).
- Para apps con datos sensibles Google puede pedir verificación; con los scopes
  básicos (email + perfil) normalmente no hace falta.
