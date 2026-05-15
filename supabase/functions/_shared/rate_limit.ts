// ============================================================================
// Helper compartido: rate limiting para Edge Functions
// ----------------------------------------------------------------------------
// Llama a la función SQL `check_rate_limit` con un `bucket_key` (combinación
// acción + scope). Devuelve `true` si la llamada está permitida, `false`
// si hay que responder 429.
//
// Política de fallo: si la RPC falla (BD caída, etc.) devolvemos `true` —
// preferimos no bloquear a usuarios legítimos por un error del backend de
// rate limiting. Los logs servidor lo registran igualmente.
// ============================================================================

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface RateLimit {
  /// Identificador único de la ventana de rate limiting. Convención:
  /// `"<action>:<scope>:<id>"` — p. ej. `"verify:user:abc-123"`.
  bucketKey: string;
  /// Nº máximo de invocaciones permitidas dentro de la ventana.
  limit: number;
  /// Tamaño de la ventana en segundos.
  windowSeconds: number;
}

export async function checkRateLimit(
  admin: SupabaseClient,
  rl: RateLimit,
): Promise<boolean> {
  const { data, error } = await admin.rpc("check_rate_limit", {
    p_bucket_key: rl.bucketKey,
    p_limit: rl.limit,
    p_window_seconds: rl.windowSeconds,
  });
  if (error) {
    // Fail-open: si la RPC falla, no bloqueamos. El error queda en logs.
    console.error("check_rate_limit RPC failed:", error.message);
    return true;
  }
  return data === true;
}

/// Extrae la IP del cliente intentando con varios headers en orden de
/// confianza. En Deno Deploy / Supabase, `x-forwarded-for` suele ser
/// fiable. Si no encontramos nada, devolvemos `"unknown"` — el bucket por
/// IP sigue funcionando, pero compartido entre clientes sin IP detectable.
export function getClientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return req.headers.get("x-real-ip")
    ?? req.headers.get("cf-connecting-ip")
    ?? "unknown";
}
