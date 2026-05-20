// ============================================================================
// Helper compartido: capability check server-side (PR-Super-A3)
// ----------------------------------------------------------------------------
// El sistema de capabilities (migracion 0044) define 13 permisos
// granulares que el super admin concede/revoca por admin. La UI
// (PR-Super-A2) ya filtra el menu y bloquea rutas segun las
// capabilities -- pero eso es solo la PRIMERA capa.
//
// **El gap que cierra A3**: un admin con `role='admin'` pero SIN la
// capability `manage_users` podia, hasta ahora, llamar directamente a
// la Edge Function `admin-users` (via curl / DevTools) saltandose el
// filtro de UI. Las EFs solo comprobaban `role === 'admin'`, no la
// capability concreta.
//
// Este helper anyade esa segunda capa: cada EF admin re-valida la
// capability que le corresponde ANTES de actuar. Defensa en
// profundidad: UI filtra -> router redirige -> **EF re-valida**.
//
// **Por que `p_user_id` explicito**: las EFs admin usan dos patrones
// para el client (unas un `userClient` con el JWT, otras el `admin`
// service_role). Pasando `p_user_id` siempre funciona en ambos casos
// -- `has_capability` no depende de `auth.uid()` cuando le das el id.
// La RPC esta GRANTed a `authenticated` Y `service_role` (0044).
//
// **El super admin pasa siempre**: `has_capability` devuelve true
// automaticamente si el user es super (lo gestiona la propia RPC).
// ============================================================================

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/// Verifica que `userId` tenga `capability`. Devuelve `null` si OK, o un
/// codigo de error (string) si falta la capability o el check falla.
///
/// Uso tipico en una EF, justo despues del check `role === 'admin'`:
/// ```ts
/// const capErr = await checkCapability(admin, user.id, "manage_users");
/// if (capErr) return json({ error: capErr }, 403);
/// ```
export async function checkCapability(
  client: SupabaseClient,
  userId: string,
  capability: string,
): Promise<string | null> {
  const { data, error } = await client.rpc("has_capability", {
    p_capability: capability,
    p_user_id: userId,
  });
  // Defensa: ante CUALQUIER error (red, RPC ausente, BD), denegar.
  // Nunca abrir la puerta por un fallo de infraestructura.
  if (error) return "capability_check_failed";
  if (data !== true) return "missing_capability";
  return null;
}
