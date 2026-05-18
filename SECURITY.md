# Security — Threat model y plan de endurecimiento

Este documento describe el modelo de amenazas del proyecto, los
controles que ya tenemos implementados y los que faltan por aplicar.
Sirve como referencia única para:

- **Onboarding** de cualquier persona técnica nueva que vaya a tocar
  el código sensible.
- **Auditorías externas** (si en algún momento contratamos una pentest
  o un compliance review).
- **Toma de decisiones** cuando aparece una nueva feature que toca
  datos sensibles ("¿esto entra en mi modelo de amenazas o no?").

> Este es un documento vivo. Cada PR que añada un control o que
> introduzca una nueva superficie de ataque debe actualizarlo.

---

## 1. Resumen ejecutivo

| Tema | Estado |
|---|---|
| Activos protegidos | PII de usuarios, credenciales, datos financieros (Stripe), uploads |
| Atacante asumido | Externo no autenticado + usuario autenticado malicioso + admin malicioso (parcial) |
| Compliance objetivo | GDPR (UE) + buenas prácticas OWASP ASVS Level 1 |
| Capa frontal | Apache (Dondominio) con `.htaccess` security headers |
| Backend | Supabase Postgres + RLS + Edge Functions (Deno) |
| Riesgos críticos abiertos | Upload sin magic-bytes, broadcasts sin sanitize HTML, no re-auth en acciones críticas |
| WAF / DDoS | **Pendiente decidir**: Cloudflare delante de Dondominio o no |
| Antivirus uploads | **Pendiente decidir**: VirusTotal API free vs sin scan |

---

## 2. Activos a proteger (qué es valioso si lo roban / corrompen)

1. **PII de usuarios**: email, nombre, dirección, teléfono, locale,
   preferencias. Almacenado en `auth.users` y `public.profiles`.
2. **Credenciales**: passwords (hashed por Supabase Auth con bcrypt),
   passkeys (WebAuthn), tokens MFA, recovery codes, PATs (`personal_access_tokens`).
3. **Datos financieros**: vinculación a Stripe (`stripe_customer_id`,
   `stripe_subscription_id`), facturación (`billing_info`), histórico
   de pagos. La info sensible (PAN, CVV) NO la tocamos — vive en
   Stripe.
4. **Datos de tenant**: organización del cliente, miembros, invites,
   webhooks configurados con `signing_secret`.
5. **Uploads**: archivos que suben usuarios al bucket `user-uploads`.
   Pueden contener PII, contratos, documentos confidenciales.
6. **Logs de auditoría** (`audit_logs`, `email_log`): si un atacante
   los borra, pierde rastro del compromiso.
7. **Configuración global** (`app_branding`, `app_flags`): tocar esto
   afecta a todos los users — defacement, registro abierto a todos,
   etc.

---

## 3. Atacantes considerados

### 3.1 Externo no autenticado (script kiddie + bot)
- Scanea endpoints públicos buscando SQLi, XSS, IDOR.
- Brute-force de login con listas conocidas.
- Intentos de spam en `/register` (creación masiva de cuentas para
  abusar de invites, créditos free, etc.).
- DDoS volumétrico.

### 3.2 Usuario autenticado malicioso
- Intenta escalar privilegios a admin (cambiar su `role`).
- Lee datos de otros tenants (IDOR via `/api/...`).
- Sube malware al bucket con extensión renombrada para infectar a
  otros usuarios al descargarlo.
- Abusa de invites, broadcasts, webhooks para spam.
- Genera PATs con scope amplio y los publica en internet (accidente
  o malicia).

### 3.3 Admin malicioso (mitigación parcial)
- Cookie del admin robada por phishing → atacante con privilegios full.
- Admin descontento envía broadcast con HTML malicioso a toda la base.
- Admin bajo coacción exfiltra `email_log`.

**Decisión consciente**: NO defendemos al 100% contra admin malicioso.
Las RPCs `SECURITY DEFINER` que aceptan `is_admin()` confían en que el
admin no abusa. Mitigaciones parciales:
- Logging de acciones admin a `audit_logs` (visible al propio admin
  pero también persistido en BD).
- Re-auth requerida para acciones críticas (planned PR-F).
- Sanitización HTML de broadcasts (planned PR-E) — limita el daño si
  alguien fuerza al admin a enviar algo.

### 3.4 Insider con acceso a Supabase Dashboard
**Fuera de scope**. Si alguien tiene la `service_role` key o acceso al
panel de Supabase, controla todo. Mitigación organizativa, no técnica:
2FA obligatorio en cuenta Supabase, lista mínima de personas con
acceso, rotar `service_role` si alguien se va.

---

## 4. Superficie de ataque actual

### 4.1 HTTP público (Apache → Flutter Web SPA)
- `/` y rutas SPA (welcome, login, register, legal pages).
- Recursos estáticos (`/assets/*`, `/icons/*`).
- `.htaccess` ya aplica: HSTS, CSP básico, X-Frame-Options DENY,
  X-Content-Type-Options nosniff, Referrer-Policy strict-origin-when-cross-origin,
  Permissions-Policy restrictiva.

### 4.2 Supabase REST + RPC (PostgREST sobre Postgres)
- `/rest/v1/*` filtrado por RLS.
- `/rest/v1/rpc/*` SECURITY DEFINER (cada función valida permisos
  internamente).

### 4.3 Supabase Edge Functions (Deno serverless)
22 funciones. Las críticas:
- `auth-email-hook` (signup, recovery, magic link, change email).
- `send-email`, `broadcast-dispatch` (envío SMTP).
- `upload-file` (escribe a bucket).
- `admin-users` (bloquear/desactivar usuarios — service_role).
- `stripe-checkout`, `stripe-webhook`, `stripe-portal`,
  `stripe-subscription-update`, `stripe-invoices` (cobros).
- `webauthn` (registro y autenticación de passkeys).
- `create-pat`, `tenant-invitations`, `delete-account`,
  `mfa-recovery`, `webhook-dispatch`.

Todas con CORS configurado, validación de JWT, y `withSentry()` wrapper
para captura de errores.

### 4.4 Supabase Storage (bucket `user-uploads`)
Privado. URLs firmadas con TTL 1h. **Riesgos abiertos**: mime
spoofing, malware sin escaneo, descarga inline de HTML.

### 4.5 Supabase Auth
- Email/password con confirmación obligatoria.
- Magic links.
- OAuth (Google) — opcional, configurable por admin.
- TOTP MFA + recovery codes.
- WebAuthn / passkeys.

### 4.6 Webhooks salientes
- `webhook-dispatch` firma con HMAC-SHA256 usando `signing_secret`
  por endpoint.
- Stripe webhooks entrantes verifican firma con `STRIPE_WEBHOOK_SECRET`.

---

## 5. Controles ya implementados (qué está bien hoy)

### 5.1 Autenticación
- Passwords con check de fortaleza en frontend (`password_strength.dart`).
- MFA TOTP + recovery codes en `mfa_recovery_codes`.
- WebAuthn / passkeys vía `@simplewebauthn`.
- Sesiones revocables (`/account-settings/sessions`).
- Email change con confirmación al email viejo + nuevo.

### 5.2 Autorización
- RLS habilitado en todas las tablas `public.*`.
- Trigger `prevent_role_self_escalation` impide que un user se haga
  admin a sí mismo (incluso si la policy de UPDATE en `profiles` se
  rompiera).
- Helper `is_admin()` SECURITY DEFINER estable.
- Helper `user_tenants(uid)` para checks de membresía.

### 5.3 Rate limiting
- Tabla `public.rate_limits` + helper `check_rate_limit()` en
  `_shared/rate_limit.ts`.
- Aplicado a: login attempts, upload-file (60/h/user), broadcast-dispatch,
  password reset.

### 5.4 Audit logging
- Tabla `audit_logs` con eventos: login, logout, role_change,
  tenant_member_add/remove, password_change, email_change,
  webhook_endpoint_create, etc.
- RLS: user ve sus eventos, admin ve todos.

### 5.5 Email log
- Tabla `email_log`: todo email saliente queda registrado.
- RLS: solo admin lee. Solo `service_role` escribe.

### 5.6 Webhooks salientes
- Firma HMAC-SHA256 con `signing_secret` por endpoint.
- Reintentos con backoff exponencial.
- Endpoint puede revocar el secret y regenerarlo.

### 5.7 Stripe
- Webhook entrante verifica firma.
- `stripe_customer_id` y `stripe_subscription_id` se guardan, NO PAN.
- Cambios de plan / cancelación pasan SIEMPRE por webhook → BD nunca
  diverge.

### 5.8 SPA hardening (`.htaccess`)
- HTTPS redirect obligatorio.
- HSTS con `includeSubDomains; preload`.
- CSP que no permite `unsafe-eval`, restringe `script-src`.
- Cache largo en assets, no-cache en HTML.

### 5.9 Frontend
- Tokens en `flutter_secure_storage` (encrypted localStorage en web).
- Refresh token rotation gestionado por Supabase SDK.
- `meta_tags_sync.dart` evita exponer rutas privadas a crawlers.

---

## 6. Riesgos abiertos y plan de mitigación

Los riesgos están priorizados por **impacto × likelihood** según OWASP
ASVS. Cada uno tiene un PR asignado.

### 🔴 PR-A · Upload de archivos sin validación robusta

**Riesgo**: usuario sube `malware.exe` renombrado a `foto.png` con
header `Content-Type: image/png`. El whitelist actual basa la decisión
solo en el header → pasa. Otro usuario lo descarga, navegador puede
ejecutarlo si Apache no fuerza Content-Disposition.

**Vectores específicos**:
1. **MIME spoofing** trivial.
2. **HTML/SVG en whitelist actual** → si se sube `<script>alert(document.cookie)</script>`
   con extensión `.svg`, al abrirse en el navegador del que lo descarga
   ejecuta JS con el origen de Supabase (donde están las URLs firmadas).
3. **Polyglot files**: archivo que es válido como dos formatos
   simultáneamente (ej. PDF+JS válido). Magic bytes lo mitiga pero no
   lo elimina.
4. **ZIP slip**: ZIPs con paths `../` que se extraen fuera de la
   carpeta destino. **No es riesgo nuestro hoy** porque no extraemos
   ZIPs en server.

**Mitigaciones (PR-A)**:
- Whitelist nueva de **24 MIME types** (text/plain, csv, tsv, md,
  json, xml, yaml, rtf, pdf, doc, docx, xls, xlsx, ppt, pptx, odt,
  ods, odp, epub, png, jpeg, gif, webp, zip, gz, tar, 7z).
- **Fuera del whitelist**: HTML, SVG, JS, EXE, todo lo ejecutable.
- **Magic bytes validation server-side**: leer primeros 16 bytes y
  comparar con signature conocido del MIME declarado.
- **Heurística UTF-8** para tipos texto: si el content-type es
  text/* y los bytes contienen `\x00` o secuencias inválidas UTF-8,
  rechazar.
- **Límites**: 50 MB general, 2 MB avatar.
- **Signed upload URLs** para archivos > 5 MB (evita límite payload
  6 MB de Edge Functions).
- Añadir columnas `sha256`, `magic_validated` a tabla `uploads`.

### ✅ PR-E · Broadcasts sanitización HTML (cerrado 2026-05-18)

**Riesgo original**: admin (o admin con cookie robada) escribe `body_html`
con `<script>` u `<img src=x onerror=...>`. Clientes de email modernos
(Gmail web, Apple Mail) ejecutan JS en el body en algunos contextos.
Aunque la mayoría stripea `<script>`, hay vectores con `<style>`,
`<svg onload>`, eventos en links.

**Implementación**:
- Helper propio `supabase/functions/_shared/html_sanitize.ts` (no usamos
  `sanitize-html` de npm para no inflar cold-start de la Edge Function).
- Tokenizador manual + whitelist estricta:
  - **Tags permitidos**: `p, br, hr, blockquote, h1-h4, strong, em,
    b, i, u, ul, ol, li, a`.
  - **Atributos permitidos**: solo `href` en `<a>`. Resto stripeado.
  - **Esquemas href**: `http, https, mailto` + URLs relativas / fragmentos.
    Bloqueados explícitamente: `javascript:, vbscript:, data:`.
  - **Force**: `rel="noopener noreferrer" target="_blank"` en todos los links.
  - **Tags peligrosos** (`script, style, iframe, svg, math, link, meta,
    object, embed, form, input, etc.`) → eliminados COMPLETOS con su
    contenido (no unwrap).
  - **Tags benignos no whitelisted** (`div, span, table, td, etc.`)
    → unwrap (contenido se conserva, tag se elimina).
- Aplicado en `broadcast-dispatch`:
  - `action=start` → sanitiza antes de persistir en BD. El render del
    loop usa lo ya sanitizado (no doble proceso).
  - `action=test` → sanitiza antes del render para que el preview del
    admin sea fiel al broadcast real.
  - Si tras sanitize queda vacío (admin solo metió `<script>` etc.)
    → error `body_html_empty_after_sanitize` → snack en UI.
- Frontend: `broadcasts_datasource.dart` ahora extrae el código de
  error del body de la respuesta (antes solo veía `http_400`).

### ✅ PR-B · Descargas con Content-Disposition: attachment (cerrado 2026-05-18)

**Riesgo original**: HTML o SVG ya están fuera del whitelist con PR-A, pero
para defense-in-depth, todo download debería ser `attachment`
explícito. Si por algún bug se cuela un HTML, evitamos que el
navegador lo renderice.

**Implementación**:
- Los TRES sitios en `upload-file/index.ts` que generan signed URLs
  ahora pasan `{ download: true }` a `createSignedUrl()`:
  - `confirm_upload` (caso idempotente: fila ya confirmada).
  - `confirm_upload` (caso normal: tras validar magic bytes).
  - `get_signed_url` (cuando el cliente pide URL fresca).
- El query param `?download=` resultante hace que Supabase Storage
  responda con `Content-Disposition: attachment` → el navegador descarga
  al disco, no renderiza inline.
- **Limitación aceptada**: Supabase Storage NO emite
  `X-Content-Type-Options: nosniff` en signed URLs. No podemos
  configurarlo (no es header del object). Mitigado por el
  `Content-Disposition: attachment` que evita rendering inline; un
  atacante que obtenga la signed URL y elimine `?download=` manualmente
  podría hacer sniffing, pero ya tiene acceso al archivo entonces el
  vector no escala.
- Nuestro propio dominio (Flutter Web SPA en Apache) ya emite
  `X-Content-Type-Options: nosniff` via `.htaccess` desde 3.R.
- **Avatares no afectados**: el bucket `avatars` es público y se accede
  via `getPublicUrl` (sin `download:`); las imágenes se muestran como
  `<img>` y deben renderizar inline. La superficie de ataque ahí está
  restringida porque RLS limita a `avatars/<uid>/...`.

### 🟠 PR-F · Acciones críticas sin re-autenticación

**Riesgo**: si una sesión queda activa en un dispositivo compartido o
es secuestrada (XSS cualquiera, robo de cookie), el atacante puede:
- Borrar la cuenta del user.
- Cambiar el email a uno suyo.
- Generar un PAT con scope `write` y exfiltrar datos.

**Mitigación (PR-F)**:
- Tabla `auth_recent_verifications (user_id, action_kind, verified_at)`.
- Endpoint `verify-password` que valida password actual y registra
  verificación con TTL 5 min.
- Frontend: modal con password antes de:
  - `/account-settings/delete-account`
  - `/account-settings/change-email`
  - Crear PAT con cualquier scope distinto de `read`.
  - **Regenerar `signing_secret` de un webhook endpoint** — rotar el
    secret en una sesión robada permite al atacante recibir webhooks
    firmados con un secret que solo él conoce.
  - **Cambiar el `role` de otro user (admin)** — escalada de
    privilegios silenciosa es exactamente lo que más queremos evitar.
- El endpoint destructivo (delete-account, etc.) comprueba que
  existe verificación fresca antes de ejecutar.

### 🟡 PR-C · Sin antivirus en uploads

**Riesgo**: archivo malicioso pasa los chequeos de magic bytes (es
un PDF válido pero contiene exploit, o un docx con macro). Lo
descarga otro user, su antivirus local lo detecta — pero ya estaba en
nuestro Storage.

**Mitigación (PR-C)** (opcional, según decisión sobre VirusTotal):
- Edge Function `scan-upload` async.
- Tras upload exitoso → hash lookup en VirusTotal /files/{sha256}.
- Si no existe, subir archivo (free tier hasta 32 MB).
- Poll status hasta 90s.
- Resultado en `uploads.virus_scan_status` (`pending|clean|suspicious|error`).
- Si `suspicious`: soft-delete automático + email al admin.

**Decisión pendiente**: ¿usamos VirusTotal o aceptamos el riesgo
documentado?

### 🟡 PR-D · Sin audit log específico de uploads ni tests de seguridad

**Mitigación (PR-D)**:
- Eventos nuevos en `audit_logs`: `upload.created`, `upload.deleted`,
  `upload.virus_detected`.
- Tests Deno (unit + integration):
  - Magic bytes (PNG renombrado .pdf → rechazado).
  - HTML/JS/EXE rechazados por whitelist.
  - UTF-8 heuristic en .txt (binario disfrazado rechazado).
  - Quota exhaustion (sub free intenta 1.1 GB → rechazado).
  - Rate limit aplicado (61ª upload en 1h → rechazado).

### 🟢 PR-G · Sin E2E tests de route guards

**Riesgo**: regression silenciosa en `app_router.dart`. Hoy si alguien
toca el `_redirect()` y rompe el gate de admin, no se entera nadie
hasta que un user no-admin acceda a `/admin/users` en producción.

**Mitigación (PR-G)**:
- Tests integration con `flutter_test` + provider override:
  - User no-admin → `/admin/users` → redirected `/home`.
  - Sin sesión → `/home` → `/login`.
  - MFA pendiente → cualquier ruta → `/mfa-challenge`.
  - Onboarding incompleto → `/home` → `/onboarding`.
  - `setup_completed=false` → cualquier ruta → `/setup`.

---

## 7. Decisiones tomadas (y por qué)

### 7.1 No usamos Cloudflare (decidido 2026-05-18)
**Razón**: Dondominio no soporta delegación de DNS limpia a CF sin
mover el dominio. El coste de migrar el dominio > el beneficio
inmediato. Aceptamos:
- Sin WAF a nivel red. Mitigamos con rate limit en Edge Functions.
- Sin DDoS protection enterprise. Apache/Dondominio aguanta hasta un
  cierto umbral.

**Trigger para revisar**: si tenemos > 1000 users activos/mes o si
sufrimos un ataque sostenido, migramos el dominio a Cloudflare o a
otro registrar con DNS delegable.

### 7.2 Antivirus de uploads — VirusTotal API free (decidido 2026-05-18)
- Free tier: 4 req/min, 500 lookups/día, archivos hasta 32 MB.
- Suficiente para proyecto en early stage; coste cero.
- Implementado en **PR-C**, después de PR-A (whitelist + magic bytes)
  y PR-B (content-disposition). Ese orden importa: sin la base
  limpia, escanear archivos que aún podrían ser ejecutables no aporta.
- Archivos > 32 MB se quedan sin scan; el riesgo se mitiga con
  whitelist estricta + magic bytes + content-disposition: attachment.

**Trigger para revisar**: si > 500 uploads/día (techo free tier) o si
añadimos límite > 32 MB para algún MIME, migramos a ClamAV self-hosted
o a Cloud-mersive paid tier.

### 7.5 GDPR data export — fuera del lote actual
El derecho de acceso GDPR requiere que el user pueda descargar un
export completo de sus datos. **No se incluye en este lote de
seguridad** porque es compliance, no defensa contra ataques.

Pendiente como PR separado post-seguridad. Diseño previsto:
- RPC `export_user_data(p_user_id)` SECURITY DEFINER que devuelve
  jsonb con: perfil, sesiones (sin tokens), tenants donde es miembro,
  uploads (paths, no contenidos), audit_logs, email_log filtrado.
- Endpoint que envía un email al user con un link firmado de 24 h
  para descargarlo (evita exponer PII en respuesta HTTP síncrona).
- Rate limit: 1 export por user cada 24 h.

### 7.3 No defendemos contra admin malicioso al 100%
Razón pragmática: proyecto con < 5 admins. Implementar separación de
permisos granular (super-admin vs admin vs ops) tiene un coste alto
y un beneficio bajo a esta escala. Mitigamos con:
- Audit log de toda acción admin.
- Re-auth para acciones críticas (PR-F).
- Limitar quién puede ser admin (manual en BD por ahora).

**Trigger para revisar**: si tenemos > 10 admins o regulación específica.

### 7.4 GDPR — qué cubrimos
- Derecho de acceso: el user descarga sus datos desde `/account-settings`
  (TODO: implementar export JSON completo).
- Derecho de borrado: `/account-settings/delete-account` con grace
  period 30 días.
- Consentimiento explícito al registro (terms + privacy).
- Cookies necesarias solamente. Sin tracking de terceros sin opt-in.
- Notificación de brechas: pendiente protocolo escrito (TODO).

---

## 8. OWASP Top 10 (2021) — mapping

| # | Riesgo | Status proyecto |
|---|---|---|
| A01 | Broken Access Control | ✅ RLS + is_admin + tests. Falta PR-G para E2E. |
| A02 | Cryptographic Failures | ✅ TLS forzado, passwords bcrypt (Supabase), secrets en env. |
| A03 | Injection | ✅ PostgREST + RPCs paramétricas. Sin SQL crudo en frontend. |
| A04 | Insecure Design | 🟡 Re-auth pendiente (PR-F). HTML sanitize ✅ (PR-E). |
| A05 | Security Misconfiguration | ✅ `.htaccess` security headers. RLS default-deny. |
| A06 | Vulnerable Components | 🟡 `flutter pub outdated` + `deno info` manual. CI sin scan. |
| A07 | Identification/Auth Failures | ✅ MFA, passkeys, rate limit en login, session revoke. |
| A08 | Software/Data Integrity Failures | ✅ Stripe webhook firma. Webhooks salientes HMAC. |
| A09 | Logging/Monitoring | ✅ audit_logs + email_log + Sentry. |
| A10 | SSRF | ✅ Webhooks salientes validados (no aceptan IPs privadas). |

---

## 9. Cómo reportar una vulnerabilidad

Si encuentras un problema de seguridad **NO abras un issue público**.
Envía un email a `security@<dominio>` con:

- Descripción del problema.
- Pasos de reproducción.
- Impacto estimado.
- Tu identidad (opcional, pero ayuda a coordinar fix + disclosure).

Tiempo de respuesta objetivo: **48 h** confirmación de recepción,
**14 días** para parchear críticos.

> TODO: configurar `security@` real + `/.well-known/security.txt`
> antes del lanzamiento público.

---

## 10. Apéndice — Configuración de referencia

### 10.1 MIME types permitidos en uploads (tras PR-A)

```
# Texto
text/plain
text/csv
text/tab-separated-values
text/markdown
application/json
application/xml
application/x-yaml
application/rtf

# Documentos
application/pdf
application/msword                                                          # .doc
application/vnd.openxmlformats-officedocument.wordprocessingml.document     # .docx
application/vnd.ms-excel                                                    # .xls
application/vnd.openxmlformats-officedocument.spreadsheetml.sheet           # .xlsx
application/vnd.ms-powerpoint                                               # .ppt
application/vnd.openxmlformats-officedocument.presentationml.presentation   # .pptx
application/vnd.oasis.opendocument.text                                     # .odt
application/vnd.oasis.opendocument.spreadsheet                              # .ods
application/vnd.oasis.opendocument.presentation                             # .odp
application/epub+zip

# Imágenes
image/png
image/jpeg
image/gif
image/webp

# Archivos
application/zip
application/gzip
application/x-tar
application/x-7z-compressed
```

**Fuera del whitelist (rechazados explícitamente)**:
- `text/html` — XSS al renderizar
- `image/svg+xml` — XSS via `<script>` embebido
- `application/javascript`, `application/x-javascript`
- `application/x-msdownload`, `application/x-executable` y similares

### 10.2 Magic bytes por MIME (primeros bytes en hex)

```
image/png       89 50 4E 47 0D 0A 1A 0A
image/jpeg      FF D8 FF (E0|E1|E8|DB)
image/gif       47 49 46 38 (37|39) 61
image/webp      52 49 46 46 .. .. .. .. 57 45 42 50
application/pdf 25 50 44 46 2D
application/zip 50 4B 03 04                                # también .docx/.xlsx/.pptx (son ZIPs)
application/gzip 1F 8B
application/x-tar (offset 257) 75 73 74 61 72             # 'ustar'
application/x-7z-compressed 37 7A BC AF 27 1C
application/rtf 7B 5C 72 74 66 31                          # '{\rtf1'
application/epub+zip 50 4B 03 04                           # ZIP, verificar mimetype interno
```

Para tipos texto (text/*, application/json, application/xml,
application/x-yaml): no hay magic bytes universal. Aplicamos:
- Sin `\x00` (NUL byte) en los primeros 8 KB.
- Decodifica como UTF-8 sin errores en los primeros 8 KB.

### 10.3 Acciones que requieren re-auth fresca (TTL 5 min) — tras PR-F

```
- delete-account
- change-email
- create-pat con scope != 'read'
- cambiar role de otro user (admin → admin promotion / demotion)
- regenerar webhook signing_secret
```

### 10.4 Rate limits actuales

| Acción | Límite | Ventana |
|---|---|---|
| `auth.signInWithPassword` | 5 fallos | 15 min |
| `auth.resetPasswordForEmail` | 3 | 1 h |
| `upload-file` | 60 | 1 h por user |
| `broadcast-dispatch` action=start | 5 | 1 h por admin |
| `webhook-dispatch` reintento | exponential backoff | n/a |

---

## 11. Historial de cambios

| Fecha | Cambio | PR |
|---|---|---|
| 2026-05-18 | Documento inicial + PR-A upload hardening (magic bytes, whitelist 27 MIMEs, signed upload URLs, 50 MB límite, columnas `sha256/magic_validated/confirmed_at` en `uploads`) | PR-A |
| 2026-05-18 | PR-E broadcasts HTML sanitize (whitelist estricta server-side antes de persistir + render) | PR-E |
| 2026-05-18 | PR-B descargas con Content-Disposition: attachment forzado (3 sitios de createSignedUrl con `download:true`) | PR-B |
