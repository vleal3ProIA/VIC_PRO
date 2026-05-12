# Supabase workspace

Carpeta versionada de todo lo relativo a Supabase para el proyecto `myapp`:
migraciones SQL, funciones Edge, plantillas de email, seeds.

## Estructura

```
supabase/
├── migrations/        Migraciones SQL numeradas (0001_*, 0002_*, ...)
├── templates/email/   Plantillas HTML para los emails de auth (en construcción)
├── functions/         Edge Functions (en construcción)
└── config.toml        Generado por `supabase init` (opcional)
```

## Aplicar la migración inicial `0001_init_profiles.sql`

### Opción A — Dashboard (lo más rápido, sin CLI)

1. Dashboard de Supabase → tu proyecto `myapp-dev`.
2. Menú lateral → **SQL Editor** → **New query**.
3. Abre `supabase/migrations/0001_init_profiles.sql`, copia su contenido,
   pégalo en el editor y pulsa **Run**.
4. Verifica:
   - Menú **Table Editor** → debe aparecer `profiles`.
   - Menú **Authentication → Policies** → `profiles` con 2 policies activas.

### Opción B — CLI (recomendado para producción)

```powershell
cd C:\VIC_PRO\myapp
supabase login                       # solo la primera vez
supabase link --project-ref jzgtghddqofxewzmpmbx
supabase db push
```

`supabase db push` aplica todas las migraciones de `supabase/migrations/`
que aún no estén en el remoto, en orden alfabético del nombre del archivo.

## Convenciones

- **Numeración**: `NNNN_descripcion.sql` (4 dígitos zero-padded).
- **Una migración = un cambio cohesivo**. Si añades una tabla y un trigger
  relacionado, va junto. Si tocas algo no relacionado, archivo nuevo.
- **Nunca editar una migración ya aplicada**. Si te equivocaste, crea otra
  que arregle. (Razón: `db push` solo aplica las pendientes; editar las
  pasadas no se propaga y rompe la reproducibilidad).
- **RLS siempre activado** en cualquier tabla `public.*` con datos de usuario.
- **`security definer`** solo en funciones que necesiten saltarse RLS de
  forma controlada (como `handle_new_user`); siempre con `set search_path`.

## Plantillas de email (próxima fase)

Mejoraremos las plantillas por defecto de Supabase con HTML responsivo y
soporte multi-idioma. Las dejaremos en `templates/email/` y las copiarás
al dashboard (*Authentication → Email Templates*).
