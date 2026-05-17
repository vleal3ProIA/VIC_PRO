# Deployment checklist

Este archivo es **tu única lista de pasos manuales** para desplegar el
proyecto a producción (o a un dominio nuevo). Yo (Claude) lo voy
actualizando en cada PR que añada algo que requiera configuración
externa.

> **TL;DR mientras trabajamos en local:** no tienes que hacer ningún
> paso de esta lista. La app funciona en local sin SMTP, sin Stripe
> live, sin Auth Hook, sin hosting. Esta lista es **únicamente** para
> el día que decidas subir a producción.

---

## Orden recomendado

Hazlos en este orden — algunos pasos asumen que los anteriores ya están
hechos.

### 1. Cuentas externas a tener listas

Antes de tocar código de despliegue, necesitas:

- [ ] **Cuenta Supabase** — proyecto creado, URL y anon key copiados,
      service_role key guardado en un sitio seguro (NUNCA en el repo).
- [ ] **Cuenta Stripe** — modo test activo para empezar. Cuando estés
      listo para cobros reales, harás el switch a live (paso aparte
      al final).
- [ ] **Dominio en Dondominio** — apuntando a tu hosting compartido,
      con SSL activado (Let's Encrypt o el SSL del panel).
- [ ] **Cuenta de email en Dondominio** — por ejemplo
      `no-reply@tudominio.com`. Anota host SMTP, puerto y password.
- [ ] **(Opcional) Cuenta Sentry** — para tracking de errores en
      producción. Sin esto, los errores siguen logueándose en consola
      pero no agregan en un dashboard.

### 2. Aplicar migraciones a Supabase

Desde la raíz del repo, con `supabase` CLI instalado y logueado:

```bash
supabase link --project-ref <tu-project-ref>
supabase db push
```

Esto aplica todas las migraciones `0001_*` hasta `0029_*` en orden.
Si alguna falla, las anteriores ya están aplicadas — corrige y vuelve
a correr (las migraciones son idempotentes salvo errores).

### 3. Variables de entorno

**a) `.env` del cliente Flutter** (copia desde `.env.example` y rellena):

| Variable | Valor |
|---|---|
| `APP_NAME` | nombre interno del proyecto (no es el comercial — ese se configura via UI) |
| `SUPABASE_URL` | la URL de tu proyecto Supabase |
| `SUPABASE_ANON_KEY` | la "anon public" key |
| `SENTRY_DSN` | tu DSN de Sentry (vacío para deshabilitar) |
| `OTP_CODE_LENGTH` | 6 (debe coincidir con Supabase Dashboard → Auth) |

**b) Secrets de Edge Functions** (Dashboard Supabase → Project Settings → Edge Functions → Secrets):

| Variable | Para qué |
|---|---|
| `SMTP_HOST` | `smtp.dondominio.com` (o el host de tu proveedor) |
| `SMTP_PORT` | `465` (SSL) o `587` (STARTTLS) |
| `SMTP_USER` | `no-reply@tudominio.com` |
| `SMTP_PASSWORD` | password de la cuenta de email |
| `SMTP_FROM` | `no-reply@tudominio.com` (el From: visible) |
| `SMTP_FROM_NAME` | nombre comercial (ej. `myapp`) |
| `SMTP_USE_TLS` | `true` para puerto 465, `false` para 587 |
| `SITE_URL` | `https://tudominio.com` — sin slash final |
| `AUTH_HOOK_SECRET` | se genera en el siguiente paso (Auth Hook) |
| `STRIPE_SECRET_KEY` | `sk_test_...` para empezar |
| `STRIPE_WEBHOOK_SECRET` | se genera al crear el webhook en Stripe |
| `STRIPE_PUBLISHABLE_KEY` | `pk_test_...` |
| `SENTRY_DSN` | (opcional) el mismo del cliente |

### 4. Desplegar Edge Functions

```bash
supabase functions deploy --no-verify-jwt auth-email-hook
supabase functions deploy send-email
supabase functions deploy stripe-webhook --no-verify-jwt
supabase functions deploy webhook-dispatch
supabase functions deploy create-pat
supabase functions deploy upload-file
supabase functions deploy admin-users
supabase functions deploy broadcast-dispatch
# ... (todas las que están en supabase/functions/)
```

`--no-verify-jwt` solo en las que reciben llamadas externas sin JWT:
`stripe-webhook` (Stripe nos llama) y `auth-email-hook` (Supabase nos
llama).

Alternativa rápida: `supabase functions deploy` sin argumento despliega
todas — pero pierdes el control de `--no-verify-jwt`. Mejor una a una
si es la primera vez.

### 5. Activar el Send Email Hook de Supabase

Para que los emails de auth (signup, recovery, magic link, etc.) salgan
en el idioma del user con nuestro branding en vez de los templates
default de Supabase:

1. Supabase Dashboard → **Authentication** → **Hooks**
2. Sección "Send email hook" → toggle **Enable hook**
3. Hook type: **HTTPS**
4. URL: `https://<tu-project-ref>.supabase.co/functions/v1/auth-email-hook`
5. Click "**Generate secret**" → copia el valor (empieza por `v1,whsec_...`)
6. Guardar
7. Pegar el secret en Edge Functions → Secrets como `AUTH_HOOK_SECRET`
   (lo dejaste pendiente en el paso 3)

Detalles completos: `supabase/functions/auth-email-hook/README.md`

### 6. Configurar Stripe webhook

1. Dashboard Stripe → **Developers** → **Webhooks** → **Add endpoint**
2. URL: `https://<tu-project-ref>.supabase.co/functions/v1/stripe-webhook`
3. Eventos a suscribir:
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `checkout.session.completed`
   - `invoice.paid`
   - `invoice.payment_failed`
4. Guardar → copia el **Signing secret** (empieza por `whsec_...`)
5. Pegarlo en Supabase Edge Functions → Secrets como `STRIPE_WEBHOOK_SECRET`
6. **Repetir todo el bloque para Stripe live** cuando hagas el switch
   (los webhooks son por modo)

### 7. Build de Flutter Web y subida a Dondominio

```bash
flutter build web --release --dart-define=APP_VERSION=1.0.0
```

Esto genera `build/web/` con los archivos estáticos. Súbelos al
`public_html/` de tu hosting via FTP/SFTP (Dondominio tiene panel con
File Manager).

**Archivos críticos:**
- `build/web/index.html` — punto de entrada
- `build/web/main.dart.js` — el bundle compilado
- `build/web/assets/` — recursos
- `build/web/canvaskit/` — engine de renderizado

**Configuración Apache (`.htaccess`)** — pendiente de generar en una
PR futura (la PR final de "deploy"). Sin esto, las rutas `/login`,
`/admin/users`, etc. devolverán 404 al refrescar — porque Flutter Web
es SPA y necesita que TODAS las rutas sirvan `index.html` y dejen
que el JS resuelva la ruta.

### 8. Wizard de primera vez en producción

Una vez subido:

1. Entras a `https://tudominio.com/` → te redirige automáticamente a
   `/setup` (porque `setup_completed = false` en `app_branding`).
2. Rellenas los 3 pasos:
   - **Marca**: nombre comercial, tagline, email soporte
   - **Visual**: paleta de colores, URLs de logo/favicon
   - **Primer admin**: tu email + password → este será el admin del
     proyecto
3. Al pulsar Finish: tu cuenta se promociona a admin automáticamente y
   `setup_completed = true`. No volverás a ver `/setup`.

A partir de aquí, todo se gestiona desde la UI.

### 9. Verificación end-to-end

- [ ] `/admin/email-log` → "Send test" → debe llegar el email a tu
      bandeja en menos de 30 segundos
- [ ] `/admin/app-branding` → cambia el nombre comercial → recarga
      cualquier página y verifica que el AppBar y la pestaña del
      navegador lo reflejan
- [ ] `/status` → debe ser accesible sin login
- [ ] Registro de un user de prueba con `registration_enabled=true` →
      verifica que recibe el email de confirmación con NUESTRO template
      (no el default de Supabase)
- [ ] Comprar un plan en modo test (tarjeta `4242 4242 4242 4242`) →
      verifica que llega el email `plan_changed` a tu bandeja
- [ ] Recovery password → verifica email con nuestro template

### 10. (Opcional) Switch a Stripe Live cuando estés listo

1. En Stripe Dashboard cambia a modo Live (toggle arriba a la derecha)
2. Repite el paso 6 (webhook) en modo live → te dará un nuevo signing
   secret
3. En Supabase Edge Functions → Secrets, sustituye:
   - `STRIPE_SECRET_KEY` por `sk_live_...`
   - `STRIPE_PUBLISHABLE_KEY` por `pk_live_...`
   - `STRIPE_WEBHOOK_SECRET` por el del webhook live
4. **No tocas código** — el switch es solo cambiar las env vars y
   redeployar functions:
   ```bash
   supabase functions deploy stripe-webhook
   ```
5. Considera abrir registro pública (`/admin/app-branding` → toggle
   "Registration enabled") cuando estés listo para usuarios reales

---

## Cambios pendientes hasta ahora (acumulado por PR)

| PR | Pasos manuales que aportó |
|---|---|
| 3.L Branding | Wizard `/setup` se ejecuta solo la primera vez. No requiere acción manual. |
| 3.M Emails | Pasos 3.b (SMTP secrets), 5 (Auth Hook), 7 fila SMTP, 9 verify email log |
| 3.N Admin Users | Desplegar Edge Function `admin-users` (paso 4). Sin pasos extra. |
| 3.O Admin Metrics | Migración 0031. Sin pasos extra. |
| 3.P Broadcasts | Migración 0032 + desplegar Edge Function `broadcast-dispatch` (paso 4). Sin pasos extra. |

> En cada PR nueva, este archivo se actualiza. **Antes de desplegar,
> relee la lista completa**, no solo lo que es "nuevo".

---

## Cosas que NO están en esta lista (porque las haré yo en futuras PRs)

- `.htaccess` con SPA rewriting + security headers (PR final de deploy)
- Pipeline GitHub Actions con FTP automático a Dondominio (PR final)
- `robots.txt` + `sitemap.xml` + meta tags SEO (PR de SEO)
- Pre-render de páginas públicas para indexación (PR de SEO)

Cuando estas PRs estén mergeadas, este archivo tendrá la lista
completa actualizada.

---

## En caso de duda

Si despliegas y algo no funciona:
1. Mira `/admin/email-log` — si los emails están en `failed` con
   `smtp_not_configured`, falta configurar SMTP
2. Mira Supabase Dashboard → Logs → Edge Functions para ver errores
   de runtime
3. Mira la consola del navegador con DevTools abierto
4. Si todo lo anterior está bien y aún falla, abre una conversación
   nueva conmigo con el error específico
