// ============================================================================
// _shared/error_reporter.ts · Insert one row into `error_reports` (NEVER throws)
// ----------------------------------------------------------------------------
// Sister of `_shared/sentry.ts` for backend errors that should appear in the
// in-app admin tool `/admin/errors`. Sentry catches "anything that escapes",
// this writes a STRUCTURED row to Postgres so the admin can browse, filter,
// resolve and (later) ask an AI to diagnose the error.
//
// Contract:
//   - NEVER throws. The caller is already in a catch block; we cannot afford
//     to mask the original error or convert a 500 into a different 500.
//   - Returns the new row id on success, `null` on failure (the caller still
//     responds to the client with `{ok:false, error_code:'generic_error',
//     error_id:null}` and the user sees the generic message).
//   - Truncates `error_message` to 4000 chars: the column is unbounded but
//     we keep it sane for the admin UI.
//
// Usage from an Edge Function:
//
//   try { ... }
//   catch (e) {
//     const errorId = await reportError(admin, {
//       userId: user?.id,
//       fn: "generate-views",
//       error: e,
//       context: { node_id: nodeId, kind, subject_id: node?.subject_id },
//       severity: "high",
//     });
//     return json({ ok: false, error_code: "generic_error", error_id: errorId }, 200);
//   }
//
// NOTE: this is intentionally additive -- Sentry capture still works through
// `withSentry`, so we keep BOTH (Sentry for ops monitoring, error_reports for
// in-app admin troubleshooting).
// ============================================================================

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type ErrorSeverity = "low" | "medium" | "high" | "critical";

export interface ErrorReportPayload {
  /// Caller user id (auth.users.id). `null` if the request had no auth.
  userId?: string | null;

  /// Short identifier of the failing function (e.g. "generate-views",
  /// "ingest-document"). Used by the admin UI for the per-function filter.
  fn: string;

  /// Short, machine-friendly code that classifies the failure. Free-form;
  /// suggested values: "rate_limited", "model_empty", "db_error",
  /// "ingest_failed", "no_ready_documents", etc. Defaults to null.
  errorCode?: string;

  /// The thrown value. Can be an `Error` (stack + name preserved), a string,
  /// or an arbitrary object (serialized to JSON for `error_details`).
  error: unknown;

  /// Optional free-form bag of "what was the EF doing": node_id, subject_id,
  /// kind, body shape, etc. Stored verbatim as jsonb.
  context?: Record<string, unknown>;

  /// Defaults to "medium". Use "high" for "blocks the user flow" and
  /// "critical" for "data loss / security risk".
  severity?: ErrorSeverity;
}

/// Inserts one row into `error_reports` using the provided service_role
/// client and returns the new id. NEVER throws.
export async function reportError(
  admin: SupabaseClient,
  payload: ErrorReportPayload,
): Promise<string | null> {
  try {
    const errMsg = payload.error instanceof Error
      ? payload.error.message
      : typeof payload.error === "string"
      ? payload.error
      : (() => {
        try {
          return JSON.stringify(payload.error);
        } catch {
          return String(payload.error);
        }
      })();

    const errDetails: unknown = payload.error instanceof Error
      ? { name: payload.error.name, stack: payload.error.stack }
      : payload.error;

    const { data, error } = await admin.from("error_reports").insert({
      user_id: payload.userId ?? null,
      fn: payload.fn,
      error_code: payload.errorCode ?? null,
      error_message: (errMsg ?? "").slice(0, 4000),
      error_details: errDetails ?? null,
      context: payload.context ?? null,
      severity: payload.severity ?? "medium",
    }).select("id").single();

    if (error || !data) {
      console.warn("[reportError] insert failed:", error?.message);
      return null;
    }
    return (data as { id: string }).id;
  } catch (e) {
    // Defensa final: el insert mismo puede tirar (red, RLS mal configurada,
    // etc.). NO propagamos: el cliente ya esta en su propio catch.
    console.warn("[reportError] exception:", (e as Error).message);
    return null;
  }
}
