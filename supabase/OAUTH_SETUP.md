# OAuth — login social (Google y Apple)

Guía paso a paso para activar el login social. Para cada proveedor hay **dos
consolas**: la del proveedor (donde se crea la credencial OAuth) y Supabase
(donde se pega esa credencial). La app **no** necesita ningún secreto en
`.env` — solo llama a `signInWithOAuth`.

- **Google** → secciones 1–6 (gratis).
- **Apple** → sección 7 (requiere **Apple Developer Program**, 99 USD/año).

---

# GOOGLE

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

---

# APPLE

> ⚠️ **Requiere el Apple Developer Program (99 USD/año).** El código de la app
> ya está listo (botón "Continuar con Apple"), pero el login fallará con
> `provider is not enabled` hasta que completes esta sección. Puedes dejarlo
> para más adelante sin tocar nada de código.

## 7. Configurar "Sign in with Apple"

Necesitas crear **3 cosas** en <https://developer.apple.com/account/> y pegar el
resultado en Supabase.

### 7.1 — App ID

1. **Certificates, Identifiers & Profiles → Identifiers** → botón **+**.
2. Tipo: **App IDs** → *Continue* → tipo **App**.
3. *Description*: `myapp`. *Bundle ID*: `com.tudominio.myapp` (explicit).
4. En la lista de *Capabilities*, marca **Sign In with Apple**.
5. *Continue* → *Register*.

### 7.2 — Services ID (es el "Client ID" que usará Supabase)

1. **Identifiers** → **+** → tipo **Services IDs** → *Continue*.
2. *Description*: `myapp web`. *Identifier*: `com.tudominio.myapp.web`.
   → **este identifier es el `Client ID`** que pegarás en Supabase.
3. *Continue* → *Register*.
4. Vuelve a abrir el Services ID recién creado → marca **Sign In with Apple**
   → botón **Configure**:
   - *Primary App ID*: el del paso 7.1.
   - **Domains and Subdomains**: `jzgtghddqofxewzmpmbx.supabase.co`
   - **Return URLs**: `https://jzgtghddqofxewzmpmbx.supabase.co/auth/v1/callback`
   - *Next* → *Done* → *Continue* → *Save*.

### 7.3 — Key (sirve para generar el "Client Secret")

1. **Keys** → **+**.
2. *Key Name*: `myapp signin`. Marca **Sign In with Apple** → **Configure** →
   elige el *Primary App ID* del paso 7.1 → *Save*.
3. *Continue* → *Register*.
4. **Descarga el archivo `.p8`** (solo se puede descargar una vez) y anota:
   - **Key ID** (10 caracteres, lo muestra la página de la key).
   - **Team ID** (10 caracteres, arriba a la derecha de la cuenta de
     desarrollador, en *Membership*).

### 7.4 — Generar el Client Secret (JWT)

Apple no da un "secret" fijo: hay que generar un **JWT firmado con el `.p8`**.
La forma más cómoda es la utilidad oficial de Supabase:

- Ve a **Supabase Dashboard → Authentication → Providers → Apple**.
- Supabase tiene un campo **"Secret Key (for OAuth)"** con un asistente: pega el
  contenido del `.p8`, el **Team ID**, el **Key ID** y el **Services ID**
  (`com.tudominio.myapp.web`) y te genera/renueva el secret automáticamente.
- Si tu versión del dashboard no trae el asistente, genera el JWT con un script
  (Apple permite una caducidad máxima de 6 meses → habrá que renovarlo).

### 7.5 — Activar el proveedor en Supabase

1. **Authentication → Providers → Apple** → *Enable*.
2. **Client IDs**: `com.tudominio.myapp.web` (el Services ID del paso 7.2).
3. **Secret Key (for OAuth)**: el JWT del paso 7.4.
4. Comprueba que la **Callback URL** mostrada es
   `https://jzgtghddqofxewzmpmbx.supabase.co/auth/v1/callback` (la misma que
   pusiste en *Return URLs* en 7.2).
5. *Save*.

### 7.6 — Redirect URLs de la app

Igual que con Google: en **Authentication → URL Configuration → Redirect URLs**
debe estar `http://localhost:5000/**` (y el dominio de producción cuando lo
tengas). El callback de Apple también vuelve a `…/auth/callback?type=oauth`.

## 8. Verificación (Apple)

1. `flutter run -d chrome --web-port 5000`.
2. En `/login` pulsa **"Continuar con Apple"**.
3. Inicia sesión con tu Apple ID → deberías acabar en `/home`.

### Errores típicos (Apple)

| Error                       | Causa                                                                       |
|-----------------------------|-----------------------------------------------------------------------------|
| `provider is not enabled`   | El proveedor Apple no está activado/guardado en Supabase.                   |
| `invalid_client`            | El Services ID o el Client Secret (JWT) no coinciden / el JWT caducó.       |
| `invalid redirect`          | La *Return URL* del Services ID no es exactamente la Callback de Supabase.  |
| Vuelve a `/login` sin sesión| Falta el origen de la app en *Redirect URLs* de Supabase.                   |

> 🔁 **Mantenimiento**: el Client Secret de Apple **caduca como máximo a los 6
> meses**. Hay que regenerarlo antes de que expire (con el asistente de Supabase
> o el script) o el login con Apple dejará de funcionar.
