// ============================================================================
// Edge Function: validate-index · Bloquea (valida) el índice y, SOLO entonces,
// contribuye a la biblioteca global si el material es libre.
// ----------------------------------------------------------------------------
// Antes el índice se volcaba al pool en CADA generación, así que un índice malo
// o incompleto (truncado, etc.) quedaba cacheado y se clonaba para siempre. Lo
// correcto: contribuir SOLO cuando el usuario VALIDA — esa es la señal humana de
// que el índice está bien. Aquí:
//   1. Marca subjects.index_locked = true (validado).
//   2. Si el temario es `shareable`, en segundo plano: vuelca secciones al pool
//      (shared_sections + embeddings), guarda el árbol clonable (shared_indexes)
//      y deja el registro de cesión (shared_contributions).
// El bloqueo responde de inmediato; la contribución va en background.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
import { docFingerprint } from "../_shared/ai/hash.ts";
import {
  recordContribution,
  writeSharedIndex,
  writeSubjectToPool,
} from "../_shared/ai/pool.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

interface SubjectRow {
  id: string;
  user_id: string;
  title: string;
  language: string | null;
  shareable: boolean | null;
}

// deno-lint-ignore no-explicit-any
async function contributeToPool(admin: any, subject: SubjectRow): Promise<void> {
  try {
    await writeSubjectToPool(admin, {
      id: subject.id,
      shareable: subject.shareable,
      language: subject.language,
    });
    const { data: docs } = await admin
      .from("documents")
      .select("extracted_text")
      .eq("subject_id", subject.id)
      .eq("status", "ready");
    const fullText =
      ((docs ?? []) as Array<{ extracted_text: string | null }>)
        .map((d) => d.extracted_text ?? "")
        .filter((t) => t.length > 0)
        .join("\n\n");
    if (fullText.trim().length > 0) {
      const fp = await docFingerprint(fullText);
      await writeSharedIndex(admin, {
        subjectId: subject.id,
        fingerprint: fp,
        title: subject.title,
        lang: subject.language,
      });
    }
    await recordContribution(admin, {
      subjectId: subject.id,
      userId: subject.user_id,
      title: subject.title,
      sectionsCount: 0,
    });
  } catch (e) {
    console.error("[validate-index] contribute_failed:", (e as Error).message);
  }
}

Deno.serve(withSentry("validate-index", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey);

  const body = await req.json().catch(() => null) as
    | Record<string, unknown>
    | null;
  const subjectId = body?.subject_id;
  if (typeof subjectId !== "string") {
    return json({ error: "missing_subject_id" }, 400);
  }

  const { data: subj } = await admin
    .from("subjects")
    .select("id, user_id, title, language, shareable")
    .eq("id", subjectId)
    .maybeSingle();
  if (!subj) return json({ error: "subject_not_found" }, 404);
  const subject = subj as SubjectRow;
  if (subject.user_id !== user.id) return json({ error: "forbidden" }, 403);

  // 1) Bloquear (validar) el índice.
  const { error: lockErr } = await admin
    .from("subjects")
    .update({
      index_locked: true,
      index_locked_at: new Date().toISOString(),
    })
    .eq("id", subjectId);
  if (lockErr) return json({ error: "lock_failed", detail: lockErr.message }, 500);

  // 2) Contribuir al pool en BACKGROUND solo si es material libre.
  if (subject.shareable === true) {
    // deno-lint-ignore no-explicit-any
    const waitUntil = (globalThis as any).EdgeRuntime?.waitUntil?.bind(
      // deno-lint-ignore no-explicit-any
      (globalThis as any).EdgeRuntime,
    );
    if (typeof waitUntil === "function") {
      waitUntil(contributeToPool(admin, subject));
    } else {
      await contributeToPool(admin, subject);
    }
  }

  return json({ ok: true }, 200);
}));
