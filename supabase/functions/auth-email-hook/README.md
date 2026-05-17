# auth-email-hook

Edge Function que reemplaza los emails de Supabase Auth con
nuestros templates i18n + branding.

## Cómo activarlo (UNA VEZ por proyecto Supabase)

1. **Desplegar la function:**
   ```bash
   supabase functions deploy auth-email-hook --no-verify-jwt
   ```
   `--no-verify-jwt` es obligatorio: Supabase llama al hook sin JWT,
   la autenticación se hace via firma HMAC del `Webhook-Signature`
   header (verificado dentro de `index.ts`).

2. **Configurar SMTP** (las vars del proyecto, no del cliente):
   - Dashboard → Project Settings → Edge Functions → Secrets
   - Añadir: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`,
     `SMTP_FROM`, `SMTP_FROM_NAME`, `SMTP_USE_TLS`
   - Ver `.env.example` para valores de Dondominio.

3. **Activar el Send Email Hook:**
   - Dashboard → Authentication → Hooks → "Send email hook"
   - Toggle "Enable hook"
   - Hook type: **HTTPS**
   - URL: `https://<project-ref>.supabase.co/functions/v1/auth-email-hook`
   - Click "Generate secret" → copia el valor que muestra (empieza por
     `v1,whsec_...`)
   - Save

4. **Pegar el secret en las env vars de la function:**
   - Dashboard → Project Settings → Edge Functions → Secrets
   - Añadir: `AUTH_HOOK_SECRET=v1,whsec_...` (el valor del paso 3)

5. **Verificar:**
   - Crea una cuenta nueva de prueba en `/register` (con el flag
     `registration_enabled = true`)
   - Deberías recibir un email de confirmación con nuestro template,
     no el default de Supabase (que es texto plano sin branding)
   - El envío se registra en `/admin/email-log`

## Si el hook falla

Si nuestra Edge Function devuelve un error (4xx/5xx), Supabase usa
su template default como fallback. Esto es deliberado: garantiza
que el user siempre reciba algún email aunque nuestro SMTP esté
caído.

Para diagnosticar:
- `/admin/email-log` lista todos los envíos (con `status='failed'` y
  el error si SMTP rechazó)
- Supabase Dashboard → Logs → Edge Functions → auth-email-hook

## Para developement local

Si trabajas con `supabase start` localmente, el Auth Hook no se
ejecuta — Supabase local manda los emails default a Inbucket
(http://localhost:54324). El hook solo aplica al proyecto remoto.
