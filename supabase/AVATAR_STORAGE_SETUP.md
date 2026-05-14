# Avatares — configuración de Supabase Storage

La subida de avatar necesita un **bucket de Storage** llamado `avatars` con sus
políticas. Hay dos formas: aplicar la migración SQL (rápido) o hacerlo a mano
en el dashboard.

---

## Opción A — Migración SQL (recomendada)

Dashboard de Supabase → **SQL Editor** → **New query** → pega el contenido de
`supabase/migrations/0004_avatars_storage.sql` → **Run**.

Eso crea el bucket `avatars` (público) y las 4 políticas RLS de una vez.

Comprueba: menú **Storage** → debe aparecer el bucket **`avatars`**.

---

## Opción B — Dashboard a mano

1. Menú **Storage** → **New bucket**.
   - Name: `avatars`
   - **Public bucket**: ✅ activado
   - **Create bucket**.
2. Entra en el bucket → pestaña **Policies** → y crea estas 4 políticas
   (plantilla "For full customization"):
   - **SELECT** (lectura): `bucket_id = 'avatars'` — para todos.
   - **INSERT**: rol `authenticated`,
     `bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text`
   - **UPDATE**: igual que INSERT (en `using` y `with check`).
   - **DELETE**: igual que INSERT (en `using`).

> La opción A hace exactamente esto, pero de una sola vez.

---

## Cómo funciona

- La app sube la imagen a `avatars/{user_id}/avatar` (un archivo por usuario;
  cada subida sobrescribe el anterior con `upsert`).
- Las políticas garantizan que **cada usuario solo escribe en su carpeta**
  (`{user_id}/...`); leer es público.
- La URL pública del archivo se guarda en `public.profiles.avatar_url` con un
  sufijo `?v=<timestamp>` para que el navegador no muestre la imagen cacheada
  tras un cambio.
- Al borrar la cuenta, el avatar **no** se elimina automáticamente del Storage
  (el `ON DELETE CASCADE` solo afecta a tablas). Es una mejora futura menor;
  los archivos huérfanos no son accesibles sin la URL.

---

## Verificación

1. `flutter run -d chrome --web-port 5000`.
2. Inicia sesión → **Ajustes → Perfil** → pulsa el avatar (o el icono de
   cámara) → elige una imagen.
3. La imagen debería subirse y aparecer al instante en Ajustes y en el menú de
   avatar de la cabecera.
4. En el dashboard → **Storage → avatars** → debe aparecer la carpeta con tu
   `user_id` y el archivo `avatar` dentro.

### Errores típicos

| Error | Causa |
|---|---|
| "No se pudo subir el avatar" / 403 | El bucket no existe o faltan las políticas (aplica la migración 0004). |
| La imagen sube pero no se ve | El bucket no es **público**. |
| Se ve la imagen vieja tras cambiarla | Caché del navegador — el `?v=timestamp` lo evita; refresca con Ctrl+F5 si hiciste pruebas antes del fix. |
