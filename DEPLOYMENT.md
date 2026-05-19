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

## Modos de deploy

Tienes dos:

### Modo A — Automatizado con GitHub Actions (recomendado)

Configurado en `.github/workflows/deploy.yml`. Tras hacer la
configuración de **una vez** (sección "Setup inicial" más abajo), cada
`git push` a `main` o cada merge de PR redespliega solo:
1. CI corre tests + analyze
2. Genera meta tags + sitemap con el dominio real
3. Build de Flutter Web con las env vars de producción
4. Sube `build/web/` a Dondominio via FTPS
5. Te avisa por GitHub si algo falla

### Modo B — Manual

Haces los pasos 1-9 de "Setup inicial" + ejecutas localmente:
```bash
dart run scripts/generate_seo.dart
flutter build web --release --dart-define-from-file=production.env
# Sube build/web/* via FTP de cPanel o FileZilla a public_html/
```

---

## Setup inicial (una vez)

Hazlos en este orden — algunos pasos asumen que los anteriores ya están
hechos.

### 1. Cuentas externas a tener listas

- [ ] **Cuenta Supabase** — proyecto creado, URL y anon key copiados,
      service_role key guardado en un sitio seguro (NUNCA en el repo).
- [ ] **Cuenta Stripe** — modo test activo para empezar. Cuando estés
      listo para cobros reales, harás el switch a live (paso aparte
      al final).
- [ ] **Dominio en Dondominio** — apuntando a tu hosting compartido,
      con SSL activado (Let's Encrypt o el SSL del panel).
- [ ] **Cuenta de email en Dondominio** — por ejemplo
      `no-reply@tudominio.com`. Anota host SMTP, puerto y password.
- [ ] **Credenciales FTP** del cPanel: host, usuario, password,
      directorio (`/public_html/` normalmente).
- [ ] **(Opcional) Cuenta Sentry** — para tracking de errores en
      producción. Sin esto, los errores siguen logueándose en consola
      pero no agregan en un dashboard.

### 2. Aplicar migraciones a Supabase

Desde la raíz del repo, con `supabase` CLI instalado y logueado:

```bash
supabase link --project-ref <tu-project-ref>
supabase db push
```

Esto aplica todas las migraciones `0001_*` hasta `0032_*` en orden.

### 3. Variables de entorno

**a) `.env` del cliente Flutter** (copia desde `.env.example` y rellena
para builds locales). En CI los valores los inyectamos via dart-defines
(siguiente subsección).

**b) Secrets de Edge Functions** (Dashboard Supabase → Project Settings → Edge Functions → Secrets):

| Variable | Para qué |
|---|---|
| `SMTP_HOST` | `smtp.dondominio.com` |
| `SMTP_PORT` | `465` (SSL) o `587` (STARTTLS) |
| `SMTP_USER` | `no-reply@tudominio.com` |
| `SMTP_PASSWORD` | password de la cuenta de email |
| `SMTP_FROM` | `no-reply@tudominio.com` |
| `SMTP_FROM_NAME` | nombre comercial (ej. `myapp`) |
| `SMTP_USE_TLS` | `true` para puerto 465, `false` para 587 |
| `SITE_URL` | `https://tudominio.com` — sin slash final |
| `AUTH_HOOK_SECRET` | se genera en el paso 5 (Auth Hook) |
| `STRIPE_SECRET_KEY` | `sk_test_...` para empezar |
| `STRIPE_WEBHOOK_SECRET` | se genera al crear el webhook en Stripe |
| `STRIPE_PUBLISHABLE_KEY` | `pk_test_...` |
| `SENTRY_DSN` | (opcional) el mismo del cliente |

**c) Secrets de GitHub Actions** (Settings → Secrets and variables →
Actions → New repository secret):

| Variable | Para qué |
|---|---|
| `FTP_HOST` | `ftp.tudominio.com` (lo da Dondominio) |
| `FTP_USERNAME` | usuario FTP del cPanel |
| `FTP_PASSWORD` | password FTP |
| `FTP_DIR` | `/public_html/` (o subcarpeta) |
| `SITE_URL` | `https://tudominio.com` |
| `APP_NAME_PROD` | nombre comercial |
| `SEO_DESCRIPTION` | descripción para meta tags |
| `SUPABASE_URL_PROD` | URL del proyecto Supabase |
| `SUPABASE_ANON_KEY_PROD` | anon key del proyecto Supabase |
| `SENTRY_DSN_PROD` | (opcional) DSN de Sentry |

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

### 7. Activar el deploy automático

Una vez configurados los secrets del paso 3.c, simplemente:

```bash
# Cualquier merge a main o push directo a main dispara el deploy.
git checkout main
git merge feat/mi-rama
git push origin main
```

GitHub Actions:
1. Corre tests + analyze (gates)
2. Ejecuta `dart run scripts/generate_seo.dart` con tus secrets
3. Hace `flutter build web --release` con dart-defines de prod
4. Sube `build/web/` via FTPS a Dondominio
5. El sitio se actualiza ~2 min después del push

Para forzar un deploy sin push: Actions → Deploy → Run workflow.

**Primera vez:** crea el environment "production" en Settings →
Environments con "Required reviewers" si quieres approval manual
antes de cada deploy.

### 8. Wizard de primera vez en producción

Una vez subido:

1. Entras a `https://tudominio.com/` → te redirige automáticamente a
   `/setup`
2. Rellenas los 3 pasos:
   - **Marca**: nombre comercial, tagline, email soporte
   - **Visual**: paleta de colores, URLs de logo/favicon
   - **Primer admin**: tu email + password
3. Al pulsar Finish: tu cuenta se promociona a admin automáticamente y
   `setup_completed = true`

### 9. Verificación end-to-end

- [ ] `https://tudominio.com/status` → accesible sin login, ve la
      página, sin certificate warning
- [ ] `https://tudominio.com/robots.txt` → ves el contenido (sin
      placeholders `__SEO_*__`)
- [ ] `https://tudominio.com/sitemap.xml` → ves las 8 URLs con tu
      dominio real
- [ ] DevTools → Network → recarga la home → assets con cache largo
      (`main.dart.js`, `.wasm`); `index.html` sin cache
- [ ] DevTools → Console → sin errores rojos
- [ ] DevTools → Lighthouse → SEO score >90, Best Practices >90
- [ ] [securityheaders.com](https://securityheaders.com/?q=tudominio.com)
      → grade A o B
- [ ] [ssllabs.com](https://www.ssllabs.com/ssltest/) → grade A
- [ ] [opengraph.xyz](https://www.opengraph.xyz/) — pega la URL y
      verifica que la preview se ve con tu logo y descripción
- [ ] `/admin/email-log` → "Send test" → te llega
- [ ] Cambia branding en `/admin/app-branding` → recarga → cambios
      aplicados en AppBar + pestaña del navegador

### 10. (Opcional) Switch a Stripe Live cuando estés listo

1. En Stripe Dashboard cambia a modo Live
2. Repite el paso 6 en modo live → nuevo signing secret
3. En Supabase Edge Functions → Secrets, sustituye:
   - `STRIPE_SECRET_KEY` por `sk_live_...`
   - `STRIPE_PUBLISHABLE_KEY` por `pk_live_...`
   - `STRIPE_WEBHOOK_SECRET` por el del webhook live
4. Hacer commit vacío o `gh workflow run deploy.yml` para redeploy
5. Considera abrir registro público (`/admin/app-branding` → toggle
   "Registration enabled") cuando estés listo para usuarios reales

---

## Cambios pendientes hasta ahora (acumulado por PR)

| PR | Pasos manuales que aportó |
|---|---|
| 3.L Branding | Wizard `/setup` se ejecuta solo la primera vez. Sin pasos extra. |
| 3.M Emails | Pasos 3.b (SMTP secrets), 5 (Auth Hook). |
| 3.N Admin Users | Desplegar Edge Function `admin-users` (paso 4). |
| 3.O Admin Metrics | Migración 0031. Sin pasos extra. |
| 3.P Broadcasts | Migración 0032 + Edge Function `broadcast-dispatch` (paso 4). |
| 3.Q SEO | `dart run scripts/generate_seo.dart` (ahora automático en CI). |
| 3.R Deploy | `.htaccess` + workflow de GitHub Actions. **Activa secrets del paso 3.c**. |
| PR-A Security Uploads | Migración 0036. Re-desplegar Edge Function `upload-file`. Nuevo flow de 2 pasos (signed upload URL) — el cliente sube directo a Storage. Límite subido a 50 MB. Whitelist nueva de 27 MIMEs (sin HTML, sin SVG). Validación de magic bytes server-side. Si tienes Storage CORS configurado, revisa que el bucket `user-uploads` permita `PUT` desde tu dominio (Supabase Dashboard → Storage → bucket → "CORS" tab → añadir tu origin si no estaba). |
| PR-E Broadcasts HTML sanitize | Re-desplegar Edge Function `broadcast-dispatch` (`supabase functions deploy broadcast-dispatch`). Sin migración. Defensiva: sanitiza `body_html` server-side con whitelist estricta antes de persistir y antes de enviar tests. Un admin con cookie robada (o malicioso) ya no puede inyectar `<script>`, `<style>`, `<iframe>` o links `javascript:` en broadcasts. |
| PR-B Content-Disposition attachment | Re-desplegar Edge Function `upload-file` (`supabase functions deploy upload-file`). Sin migración. Sin cambios de UI. Defensiva: todas las signed URLs de descarga llevan `?download=` → fuerza al navegador a descargar el archivo en vez de renderizarlo inline. Sumado a PR-A (whitelist sin HTML/SVG), un usuario no puede explotar la zona de descarga ni con vectores polyglot ni renombrando extensiones. |
| PR-F Re-auth acciones críticas | Migración 0037. Desplegar Edge Function NUEVA `verify-password`: `supabase functions deploy verify-password`. Re-desplegar `delete-account` y `create-pat` (ahora chequean recent verification antes de actuar): `supabase functions deploy delete-account` + `supabase functions deploy create-pat`. Sin nuevos secrets. Pre-existente UX se mantiene; el form de delete-account funciona igual pero el password ahora se valida server-side via `verify-password` en vez de `signInWithPassword` client-side. Para PATs con scope `write`, el dialog ahora pide password antes de crear. |
| PR-G E2E route guards | **Sin pasos manuales**. Solo añade tests Dart unitarios y un refactor interno (extraer la lógica de redirect a `router_guards.dart`). No toca BD ni Edge Functions. Beneficio: si alguien futuro toca el router, los 40 tests pillan regresiones (gate de admin, MFA, onboarding, setup wizard, etc.) ANTES de subir a producción. |
| PR-C VirusTotal antivirus | Migración 0038. Desplegar NUEVA Edge Function `scan-upload`: `supabase functions deploy scan-upload`. Re-desplegar `upload-file` (ahora invoca scan-upload tras confirm): `supabase functions deploy upload-file`. **Nuevo secret**: `VIRUSTOTAL_API_KEY` con la API key de tu cuenta free de virustotal.com → `supabase secrets set VIRUSTOTAL_API_KEY=<tu_key>`. Sin esa key el flow funciona pero marca todos los uploads como `skipped`. Tras configurar: cada upload nuevo se escanea async (no bloquea), si VirusTotal detecta malware el upload queda soft-deleted automáticamente y aparece en `audit_logs` con event `upload.virus_detected`. |
| Audit Center V1 — PR-Audit-1 | Migración 0039 (tabla `audit_reports` + RPCs `admin_audit_reports_list` y `admin_audit_report_detail`). Desplegar NUEVA Edge Function `run-audit`: `supabase functions deploy run-audit`. Sin nuevos secrets. El esqueleto solo permite invocar el endpoint con admin JWT y guardar un report con un placeholder; los 12 checks reales llegan en PR-Audit-2 + UI en PR-Audit-3. **Sin acción inmediata para el user final** hasta que el módulo `/admin/audit` esté desplegado. |
| Audit Center V1 — PR-Audit-2 | Migración 0040 (RPCs helper para `pg_tables`/`pg_policies` y agregados de MFA/email failure rate). Re-desplegar `run-audit`: `supabase functions deploy run-audit` (incluye ahora los 12 checks reales en `_checks/*.ts`). Sin nuevos secrets. Tras este PR el endpoint ya hace audits útiles, pero sin UI todavía — puedes probarlo con curl: `curl -X POST https://<project>.supabase.co/functions/v1/run-audit -H "Authorization: Bearer <ADMIN_JWT>"` y leer el resultado en SQL Editor con `select * from audit_reports order by started_at desc limit 1;`. |
| Audit Center V1 — PR-Audit-3 | UI Flutter (`/admin/audit` + `/admin/audit/:id`). **Sin migración nueva, sin Edge Function nueva**. Solo `flutter build web` + subir `build/web/` al hosting. Tras desplegar, el admin tiene un módulo completo: listado de reports recientes con summary chips por severity, detail page con findings agrupados (critical → info), botón **Run new audit** que dispara la Edge Function (rate-limit 1/min/admin), polling automático mientras el report siga en `status='running'`, export a TXT del informe. **Acción admin**: una vez subido, entra a `/admin/audit` y lanza el primer audit para validar end-to-end (debería terminar en ~10s y mostrar los findings reales del proyecto). |
| Audit Center V1 — PR-Audit-4 | Migración 0041 (RPCs `admin_audit_recover_stuck` + `admin_audit_purge_old`). Re-desplegar `run-audit`: `supabase functions deploy run-audit` (ahora emite Sentry events para findings critical/high). Sin nuevos secrets. **Acción admin**: configura un cron externo (GitHub Actions / Supabase Pro Cron / cron del hosting) que lance las dos RPCs de mantenimiento. Detalles en la sección **Audit Center maintenance** más abajo. La UI de `/admin/audit` ahora muestra un banner discreto si el último audit es de hace ≥ 7 días o falló — sirve de fallback visual si el cron deja de funcionar. |

> En cada PR nueva, este archivo se actualiza. **Antes de desplegar,
> relee la lista completa**, no solo lo que es "nuevo".

---

## Audit Center maintenance

El módulo `/admin/audit` ejecuta auditorías a demanda (1/min/admin
por el rate-limit), pero para que sea útil en producción necesita
operaciones de mantenimiento automáticas. Estas se invocan
**externamente** porque `pg_cron` no está disponible en plan free
de Supabase.

### Operaciones disponibles

| RPC SQL | Qué hace | Frecuencia recomendada |
|---|---|---|
| `select public.admin_audit_recover_stuck();` | Marca como `failed` los audits cuyo `status='running'` lleva > 30 min. Sin esto, si la Edge Function `run-audit` muere a mitad (deploy, OOM, timeout), la row queda *stuck* para siempre y bloquea el rate-limit. Devuelve nº de rows recuperadas. | Cada 30 min. |
| `select public.admin_audit_purge_old('90 days'::interval);` | Borra reports antiguos. Default 90 días, mínimo 7 (floor de seguridad). Devuelve nº de rows borradas. | Diario o semanal. |
| `POST /functions/v1/run-audit` (con admin JWT) | Lanza una auditoría completa. La UI hace esto cuando el admin pulsa "Run new audit". Para auto-scheduling se puede llamar desde un cron externo. | Diario, ej. 04:00 UTC. |

Las dos RPCs son `SECURITY DEFINER` con check `is_admin()` interno —
necesitas una sesión admin (PAT con scope `admin` o JWT de un user
con `role='admin'`) para invocarlas.

### Opción A: GitHub Actions (recomendado para self-hosted)

Crear `.github/workflows/audit-center-maintenance.yml`:

```yaml
name: Audit Center maintenance
on:
  schedule:
    # 04:00 UTC daily: lanza audit, recover stuck, purge >90d.
    - cron: '0 4 * * *'
    # Cada 30 min: solo recover stuck.
    - cron: '*/30 * * * *'
  workflow_dispatch: # manual trigger desde GitHub UI

jobs:
  maintenance:
    runs-on: ubuntu-latest
    steps:
      - name: Recover stuck audits
        run: |
          curl -X POST \
            "${{ secrets.SUPABASE_URL }}/rest/v1/rpc/admin_audit_recover_stuck" \
            -H "Authorization: Bearer ${{ secrets.SUPABASE_ADMIN_JWT }}" \
            -H "apikey: ${{ secrets.SUPABASE_ANON_KEY }}" \
            -H "Content-Type: application/json"
      - name: Run daily audit
        # Solo en la ejecución de las 04:00, no cada 30 min.
        if: github.event.schedule == '0 4 * * *'
        run: |
          curl -X POST \
            "${{ secrets.SUPABASE_URL }}/functions/v1/run-audit" \
            -H "Authorization: Bearer ${{ secrets.SUPABASE_ADMIN_JWT }}" \
            -H "Content-Type: application/json"
      - name: Purge old audits
        # Solo en la ejecución de las 04:00.
        if: github.event.schedule == '0 4 * * *'
        run: |
          curl -X POST \
            "${{ secrets.SUPABASE_URL }}/rest/v1/rpc/admin_audit_purge_old" \
            -H "Authorization: Bearer ${{ secrets.SUPABASE_ADMIN_JWT }}" \
            -H "apikey: ${{ secrets.SUPABASE_ANON_KEY }}" \
            -H "Content-Type: application/json" \
            -d '{"p_older_than": "90 days"}'
```

Secrets necesarios en GitHub repo settings → Secrets and variables:
- `SUPABASE_URL` (ej. `https://abc.supabase.co`)
- `SUPABASE_ANON_KEY` (ya lo tienes en `.env` para la app)
- `SUPABASE_ADMIN_JWT` — JWT de un user con `role='admin'`. **Aviso**:
  los JWT de Supabase Auth caducan en 1h por defecto. Para uso cron
  prolongado usa un **PAT** con scope `admin` (`sb_secret_...`)
  generado desde `/account-settings/tokens` — ese no caduca a menos
  que lo revoques.

### Opción B: Supabase Pro/Team Cron Jobs

Si tienes plan Pro+, abre el dashboard → Database → Cron Jobs →
*Create a new cron job*. Tres jobs:

1. Nombre: `audit-recover-stuck`, schedule `*/30 * * * *`, SQL:
   ```sql
   select public.admin_audit_recover_stuck();
   ```
2. Nombre: `audit-daily-run`, schedule `0 4 * * *`. Lanzar la Edge
   Function via `net.http_post()` o invocar manualmente la lógica
   del `run-audit` (la Edge Function ya hace el INSERT en `running`
   y procesa en background).
3. Nombre: `audit-purge-old`, schedule `30 4 * * *`, SQL:
   ```sql
   select public.admin_audit_purge_old('90 days'::interval);
   ```

### Opción C: Manual / on-demand

Si tu deployment es pequeño y prefieres no automatizar:
- Entra a `/admin/audit` cada día y pulsa **Run new audit**. La UI te
  avisa con un banner si el último audit tiene ≥ 7 días.
- Ejecuta las RPCs de mantenimiento desde el SQL Editor de Supabase
  cuando notes algo raro.

### Sentry alerts (opcional)

Si tienes `SENTRY_DSN` configurado en el secret de Supabase Functions,
`run-audit` emite automáticamente un Sentry event cuando un audit
termina con findings `critical` (level=`error`, dispara notificación
inmediata) o `high` (level=`warning`). El event incluye `report_id`
y los titulos de los findings para que en Sentry puedas hacer click
y abrir directamente `/admin/audit/<id>`.

---

## Troubleshooting común

### "404 al refrescar `/admin/users`" tras subir
- Falta el `.htaccess` en `public_html/`. Verifica que está subido.
- O Apache tiene `AllowOverride None` — pide soporte que active al
  menos `AllowOverride FileInfo Indexes Limit Options`.

### "Mixed content blocked" en la consola
- El `.env` tiene URLs http://. Cambia todo a https://.

### Los emails caen en spam
- Configura SPF / DKIM / DMARC en el panel DNS de Dondominio. Sin
  estos records, los emails desde no-reply@tudominio.com los marca
  Gmail/Outlook como spam.

### El sitio sigue viendo el branding antiguo
- Force-refresh con Ctrl+Shift+R. La cache de `index.html` no debería
  pasar de unos segundos pero el navegador puede agarrar la versión
  anterior si tienes el sitio abierto.

### GitHub Actions falla en "Upload to Dondominio"
- Verifica que el `FTP_HOST` es correcto (Dondominio panel → FTP).
- Algunos hostings limitan IPs externas — puede que tengas que
  permitir las IPs de GitHub Actions (rango público variable).
- Como fallback rápido: descarga `build/web/` del artefacto del job y
  súbelo manualmente con FileZilla.

---

## En caso de duda

1. Mira `/admin/email-log` si los emails no llegan
2. Supabase Dashboard → Logs → Edge Functions para errores de runtime
3. GitHub Actions → último run para fallos de build
4. DevTools en el navegador para errores de cliente
5. Si todo lo anterior está bien y aún falla, abre una conversación
   nueva conmigo con el error específico
