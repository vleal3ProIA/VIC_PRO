// ============================================================================
// Edge Function: generate-index · Genera el índice jerárquico de un temario (Fase 2)
// ----------------------------------------------------------------------------
// Lee el `extracted_text` de los documentos 'ready' del temario y pide al
// modelo (vía gateway) un índice jerárquico de SOLO TÍTULOS (salida compacta,
// sin riesgo de truncado en temarios largos). Inserta el árbol en
// `index_nodes` y marca `subjects.index_status='ready'`.
//
// Las vistas por nodo (original/explained/summary) las generará
// `generate-views` bajo demanda. Flujo: status='generating' -> 202 -> proceso
// en background (la UI hace polling de `index_status`).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { captureError, withSentry } from "../_shared/sentry.ts";
import { AiGatewayError, runCompletion } from "../_shared/ai/gateway.ts";
import { gatherMaterial } from "../_shared/ai/material.ts";

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
}

interface IndexNode {
  title?: unknown;
  children?: unknown;
}

function parseNodes(text: string): IndexNode[] {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    const obj = JSON.parse(t) as { nodes?: unknown };
    return Array.isArray(obj.nodes) ? obj.nodes as IndexNode[] : [];
  } catch {
    return [];
  }
}

Deno.serve(withSentry("generate-index", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

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

  const { data: subj, error: sErr } = await admin
    .from("subjects")
    .select("id, user_id")
    .eq("id", subjectId)
    .maybeSingle();
  if (sErr) return json({ error: "db_error", detail: sErr.message }, 500);
  if (!subj) return json({ error: "subject_not_found" }, 404);
  if ((subj as SubjectRow).user_id !== user.id) {
    return json({ error: "forbidden" }, 403);
  }
  const subject = subj as SubjectRow;

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `generate-index:${user.id}`,
    limit: 10,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // Regeneración limpia: borramos el índice anterior (cascade limpia
  // node_content) y marcamos 'generating'.
  await admin.from("index_nodes").delete().eq("subject_id", subject.id);
  await admin.from("subjects")
    .update({ index_status: "generating" })
    .eq("id", subject.id);

  // deno-lint-ignore no-explicit-any
  const waitUntil = (globalThis as any).EdgeRuntime?.waitUntil?.bind(
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime,
  );
  if (typeof waitUntil === "function") {
    waitUntil(buildIndex(admin, subject));
  } else {
    await buildIndex(admin, subject);
  }

  return json({ ok: true, subject_id: subject.id, status: "generating" }, 202);
}));

// deno-lint-ignore no-explicit-any
async function buildIndex(admin: any, subject: SubjectRow): Promise<void> {
  try {
    // Material completo: PDF/imagen como adjunto (visión, lee el documento
    // entero) + texto de los .txt. Evita el truncado del texto extraído.
    const { textContext, attachments } = await gatherMaterial(admin, subject.id);
    if (!textContext && attachments.length === 0) {
      throw new Error("no_ready_documents");
    }

    const system =
      "You build a hierarchical table of contents (index) for study material. " +
      "Cover the ENTIRE document from the first page to the LAST one: every " +
      "chapter, topic, theme and section — not just the first ones. Return " +
      "ONLY minified JSON of the form " +
      '{"nodes":[{"title":"...","children":[{"title":"..."}]}]} with 1 to 3 ' +
      "levels of depth. Titles must be concise and in the SAME language as the " +
      "material. Do NOT include any content, only titles. No commentary.";

    const result = await runCompletion(admin, {
      task: "index",
      system,
      messages: [{
        role: "user",
        content: textContext
          ? "Material:\n\n" + textContext
          : "Build the index from the attached document(s).",
      }],
      attachments: attachments.length > 0 ? attachments : undefined,
      maxOutputTokens: 8192,
      temperature: 0.2,
      userId: subject.user_id,
      subjectId: subject.id,
    });

    const nodes = parseNodes(result.text);
    if (nodes.length === 0) throw new Error("empty_index");

    await insertNodes(admin, subject, nodes, null, 0);

    await admin.from("subjects")
      .update({ index_status: "ready" })
      .eq("id", subject.id);
  } catch (e) {
    const msg = e instanceof AiGatewayError ? e.message : (e as Error).message;
    await admin.from("subjects")
      .update({ index_status: "failed" })
      .eq("id", subject.id);
    captureError(e, { fn: "generate-index", subject: subject.id, detail: msg });
  }
}

// deno-lint-ignore no-explicit-any
async function insertNodes(
  admin: any,
  subject: SubjectRow,
  nodes: IndexNode[],
  parentId: string | null,
  depth: number,
): Promise<void> {
  let position = 0;
  for (const n of nodes) {
    if (!n || typeof n.title !== "string" || n.title.trim().length === 0) {
      continue;
    }
    const { data: row, error } = await admin
      .from("index_nodes")
      .insert({
        subject_id: subject.id,
        user_id: subject.user_id,
        parent_id: parentId,
        title: (n.title as string).slice(0, 300),
        position: position++,
        depth,
      })
      .select("id")
      .single();
    if (error || !row) continue;
    if (Array.isArray(n.children) && n.children.length > 0 && depth < 4) {
      await insertNodes(
        admin,
        subject,
        n.children as IndexNode[],
        row.id as string,
        depth + 1,
      );
    }
  }
}
