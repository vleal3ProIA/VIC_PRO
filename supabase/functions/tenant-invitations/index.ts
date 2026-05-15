// ============================================================================
// Edge Function: tenant-invitations
// ----------------------------------------------------------------------------
// Tres acciones, todas autenticadas:
//
//   { "action": "create", "tenant_id", "email", "role", "expires_days" }
//      Solo admin/owner del tenant. Genera token plaintext (32 bytes b64url)
//      y guarda su SHA-256. Devuelve el token plaintext para que el frontend
//      construya la URL `https://app/invite?token=...` y la envíe por email
//      o se la pase al admin para copiar a mano.
//
//   { "action": "accept", "token" }
//      Cualquier usuario autenticado. Hashea el token y busca la invitación.
//      Si es válida (no expirada, no aceptada, no revocada): inserta el
//      tenant_member + marca accepted_at. Devuelve { tenant_id, role }.
//
//   { "action": "revoke", "invitation_id" }
//      Solo admin/owner del tenant que emitió la invitación. Marca
//      revoked_at = now().
//
// Rate limits (sliding window via SQL function check_rate_limit):
//   - create:  20/hora/usuario  → spam-prevention de invitaciones
//   - accept:  10/15min/usuario → fuerza bruta sobre tokens
//   - revoke:  30/hora/usuario  → operación administrativa normal
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Hex SHA-256 de un string (UTF-8). */
async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Token URL-safe de 32 bytes (256 bits). */
function generateToken(): string {
  const buf = new Uint8Array(32);
  crypto.getRandomValues(buf);
  return btoa(String.fromCharCode(...buf))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

Deno.serve(withSentry("tenant-invitations", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "missing_authorization" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // user_client: respeta RLS, identifica al caller por su JWT.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) {
    return json({ error: "invalid_token" }, 401);
  }

  // admin: bypasea RLS para hacer INSERTs/UPDATEs en flujos cross-tenant.
  const admin = createClient(supabaseUrl, serviceRoleKey);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "invalid_json" }, 400);
  }

  const action = body.action as string | undefined;

  // ───────────────────────────────── CREATE ─────────────────────────────────

  if (action === "create") {
    const rateOk = await checkRateLimit(admin, {
      bucketKey: `tenant-inv:create:user:${user.id}`,
      limit: 20,
      windowSeconds: 3600,
    });
    if (!rateOk) return json({ error: "rate_limited" }, 429);

    const tenantId = body.tenant_id as string | undefined;
    const email = (body.email as string | undefined)?.trim().toLowerCase();
    const role = (body.role as string | undefined) ?? "member";
    const expiresDays = Math.min(
      Math.max(parseInt(String(body.expires_days ?? 7), 10) || 7, 1),
      30,
    );

    if (!tenantId || !email || !email.match(/^[^\s@]+@[^\s@]+\.[^\s@]+$/)) {
      return json({ error: "invalid_input" }, 400);
    }
    if (!["owner", "admin", "member"].includes(role)) {
      return json({ error: "invalid_role" }, 400);
    }
    // Solo owners pueden invitar a otros owners; admin solo puede invitar a
    // admin/member. Comprobamos el role del caller en este tenant.
    const { data: callerMembership } = await admin
      .from("tenant_members")
      .select("role")
      .eq("tenant_id", tenantId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (!callerMembership) {
      return json({ error: "not_member" }, 403);
    }
    if (!["owner", "admin"].includes(callerMembership.role as string)) {
      return json({ error: "not_admin" }, 403);
    }
    if (role === "owner" && callerMembership.role !== "owner") {
      return json({ error: "cannot_invite_owner" }, 403);
    }

    // Ya hay invitación pendiente para este email en este tenant?
    const { data: existing } = await admin
      .from("tenant_invitations")
      .select("id")
      .eq("tenant_id", tenantId)
      .eq("email", email)
      .is("accepted_at", null)
      .is("revoked_at", null)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (existing) {
      return json({ error: "already_invited" }, 409);
    }

    // Nota: NO comprobamos aquí si `email` ya es miembro del tenant. La
    // lista de auth.users requiere `auth.admin.listUsers` paginada, lo que
    // es lento y caro. Si el invitado ya es miembro, el `accept` lo
    // detectará vía ON CONFLICT (idempotente) y devolverá éxito. Solo
    // perdemos un mensaje de error pre-emptivo en la UI, no funcionalidad.

    const token = generateToken();
    const tokenHash = await sha256Hex(token);
    const expiresAt = new Date(
      Date.now() + expiresDays * 24 * 60 * 60 * 1000,
    ).toISOString();

    const { data: inv, error: insErr } = await admin
      .from("tenant_invitations")
      .insert({
        tenant_id: tenantId,
        email,
        role,
        token_hash: tokenHash,
        invited_by: user.id,
        expires_at: expiresAt,
      })
      .select("id, expires_at")
      .single();
    if (insErr) {
      return json({ error: "insert_failed", detail: insErr.message }, 500);
    }

    return json(
      {
        invitation_id: inv.id,
        token, // plaintext — el frontend lo usa para construir la URL.
        expires_at: inv.expires_at,
      },
      200,
    );
  }

  // ───────────────────────────────── ACCEPT ─────────────────────────────────

  if (action === "accept") {
    const rateOk = await checkRateLimit(admin, {
      bucketKey: `tenant-inv:accept:user:${user.id}`,
      limit: 10,
      windowSeconds: 900,
    });
    if (!rateOk) return json({ error: "rate_limited" }, 429);

    const token = body.token as string | undefined;
    if (!token || token.length < 20) {
      return json({ error: "invalid_token_format" }, 400);
    }
    const tokenHash = await sha256Hex(token);

    const { data: inv, error: invErr } = await admin
      .from("tenant_invitations")
      .select("id, tenant_id, role, email, accepted_at, revoked_at, expires_at")
      .eq("token_hash", tokenHash)
      .maybeSingle();
    if (invErr) {
      return json({ error: "lookup_failed", detail: invErr.message }, 500);
    }
    if (!inv) return json({ error: "invitation_not_found" }, 404);
    if (inv.accepted_at) return json({ error: "already_accepted" }, 410);
    if (inv.revoked_at) return json({ error: "revoked" }, 410);
    if (new Date(inv.expires_at) < new Date()) {
      return json({ error: "expired" }, 410);
    }

    // Insertar tenant_member (idempotente con ON CONFLICT — si por alguna
    // razón la membership ya existe, lo tratamos como éxito).
    const { error: memErr } = await admin
      .from("tenant_members")
      .insert({
        tenant_id: inv.tenant_id,
        user_id: user.id,
        role: inv.role,
      });
    // El error 23505 (unique violation) es OK: ya era miembro.
    if (memErr && memErr.code !== "23505") {
      return json({ error: "join_failed", detail: memErr.message }, 500);
    }

    // Marcar la invitación como aceptada.
    await admin
      .from("tenant_invitations")
      .update({ accepted_at: new Date().toISOString(), accepted_by: user.id })
      .eq("id", inv.id);

    return json(
      {
        tenant_id: inv.tenant_id,
        role: inv.role,
      },
      200,
    );
  }

  // ───────────────────────────────── REVOKE ─────────────────────────────────

  if (action === "revoke") {
    const rateOk = await checkRateLimit(admin, {
      bucketKey: `tenant-inv:revoke:user:${user.id}`,
      limit: 30,
      windowSeconds: 3600,
    });
    if (!rateOk) return json({ error: "rate_limited" }, 429);

    const invitationId = body.invitation_id as string | undefined;
    if (!invitationId) {
      return json({ error: "missing_invitation_id" }, 400);
    }

    // Comprobar que el caller es admin del tenant emisor.
    const { data: inv } = await admin
      .from("tenant_invitations")
      .select("tenant_id")
      .eq("id", invitationId)
      .maybeSingle();
    if (!inv) return json({ error: "invitation_not_found" }, 404);

    const { data: callerMembership } = await admin
      .from("tenant_members")
      .select("role")
      .eq("tenant_id", inv.tenant_id)
      .eq("user_id", user.id)
      .maybeSingle();
    if (!callerMembership) return json({ error: "not_member" }, 403);
    if (!["owner", "admin"].includes(callerMembership.role as string)) {
      return json({ error: "not_admin" }, 403);
    }

    await admin
      .from("tenant_invitations")
      .update({ revoked_at: new Date().toISOString() })
      .eq("id", invitationId);
    return json({ success: true }, 200);
  }

  return json({ error: "unknown_action" }, 400);
}));
