// ============================================================================
// Edge Function: generate-views · Vista de un nodo del índice (Fase 2)
// ----------------------------------------------------------------------------
// Genera BAJO DEMANDA una de las 3 vistas de una sección del índice:
//   - 'original'  -> extrae verbatim el texto de esa sección del material.
//   - 'explained' -> explicación detallada y didáctica de esa sección.
//   - 'summary'   -> resumen con lo esencial de esa sección.
// En el idioma del temario. Cachea en `node_content` (unique node_id+kind): si
// ya existe y no se fuerza, lo devuelve sin gastar IA. Síncrono: la UI lo
// espera con spinner (una sección se genera en segundos).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
import { AiGatewayError, runCompletion } from "../_shared/ai/gateway.ts";
import { gatherMaterial } from "../_shared/ai/material.ts";
import { contentHash } from "../_shared/ai/hash.ts";
import { findSimilarHash } from "../_shared/ai/pool.ts";
import type { AiAttachment } from "../_shared/ai/types.ts";

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

const KINDS = new Set(["original", "explained", "summary"]);

interface NodeRow {
  id: string;
  subject_id: string;
  user_id: string;
  title: string;
}

function systemFor(kind: string, language: string | null): string {
  const lang = language && language.length > 0
    ? `Write in this language (ISO code): ${language}.`
    : "Write in the SAME language as the material.";
  switch (kind) {
    case "original":
      return "You extract content from study material. Return, verbatim and " +
        "complete, only the text of the requested section (keep its headings " +
        "and structure). Do not summarize, do not add commentary.";
    case "explained":
      return "You are an expert tutor. Rewrite and explain the requested " +
        "section using EASY-READING principles (lectura fácil): short " +
        "sentences with ONE idea each; simple and common words; active voice; " +
        "explain every difficult or technical term in parentheses; clear " +
        "headings and bullet lists; and a concrete example when it helps. " +
        `Stay faithful to the content, do not invent. ${lang} Use Markdown. ` +
        "No preamble.";
    case "summary":
      return "You summarize study material. Produce a concise summary of the " +
        `key points of the requested section as bullet points. ${lang} ` +
        "Use Markdown. No preamble.";
    default:
      return "Summarize the requested section.";
  }
}

Deno.serve(withSentry("generate-views", async (req) => {
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
  const nodeId = body?.node_id;
  const kind = body?.kind;
  const force = body?.force === true;
  if (typeof nodeId !== "string" || typeof kind !== "string" || !KINDS.has(kind)) {
    return json({ error: "bad_request" }, 400);
  }

  const { data: nodeData, error: nErr } = await admin
    .from("index_nodes")
    .select("id, subject_id, user_id, title")
    .eq("id", nodeId)
    .maybeSingle();
  if (nErr) return json({ error: "db_error", detail: nErr.message }, 500);
  if (!nodeData) return json({ error: "node_not_found" }, 404);
  const node = nodeData as NodeRow;
  if (node.user_id !== user.id) return json({ error: "forbidden" }, 403);

  // Caché: si ya existe y no se fuerza, devolvemos sin gastar IA.
  if (!force) {
    const { data: cached } = await admin
      .from("node_content")
      .select("content")
      .eq("node_id", node.id)
      .eq("kind", kind)
      .maybeSingle();
    if (cached && (cached as { content: string | null }).content) {
      return json({
        ok: true,
        cached: true,
        content: (cached as { content: string }).content,
      }, 200);
    }
  }

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `generate-views:${user.id}`,
    limit: 30,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // Idioma del temario + si es material libre (para aportar a la biblioteca).
  const { data: subj } = await admin
    .from("subjects")
    .select("language, shareable")
    .eq("id", node.subject_id)
    .maybeSingle();
  const subjRow = subj as
    | { language: string | null; shareable: boolean | null }
    | null;
  const language = subjRow?.language ?? null;
  const shareable = subjRow?.shareable === true;

  // Material para la vista. Preferimos el TEXTO de la sección (el 'original'
  // guardado al construir el índice): así CUALQUIER proveedor (incluido Groq)
  // puede generarla y el fallback gratis->pago funciona. Re-adjuntar el PDF por
  // visión limitaría a Gemini/Anthropic (sin fallback si se agota la cuota).
  // Solo si no hay texto en ningún sitio caemos a visión (PDF adjunto).
  const { data: orig } = await admin
    .from("node_content")
    .select("content")
    .eq("node_id", node.id)
    .eq("kind", "original")
    .maybeSingle();
  const origContent =
    ((orig as { content: string | null } | null)?.content ?? "").trim();
  // Hash de la sección (solo si tiene texto propio): clave para reutilizar las
  // vistas ya generadas de la biblioteca global (mismo texto -> misma vista).
  const sectionHash = origContent.length >= 40
    ? await contentHash(origContent)
    : null;
  let textContext = origContent;
  let attachments: AiAttachment[] = [];
  if (textContext.length < 20) {
    const mat = await gatherMaterial(admin, node.subject_id);
    if (mat.textContext.trim().length > 0) {
      textContext = mat.textContext;
    } else {
      textContext = "";
      attachments = mat.attachments;
    }
  }
  if (textContext.length === 0 && attachments.length === 0) {
    return json({ error: "no_ready_documents" }, 409);
  }

  // Genera una vista concreta y la cachea; devuelve el texto. Para 'explained'
  // y 'summary' intenta primero REUTILIZAR de la biblioteca global por hash
  // (0 tokens) y, si genera una nueva con material libre, la aporta al pool.
  const genOne = async (k: string): Promise<string> => {
    // 1) Reutilización por content_hash (solo vistas didácticas, no 'original').
    if (sectionHash && k !== "original") {
      const { data: shared } = await admin
        .from("shared_node_content")
        .select("content")
        .eq("content_hash", sectionHash)
        .eq("kind", k)
        .maybeSingle();
      const sc = (shared as { content: string | null } | null)?.content;
      if (sc && sc.trim().length > 0) {
        await admin.from("node_content").upsert({
          node_id: node.id,
          user_id: node.user_id,
          kind: k,
          content: sc,
        }, { onConflict: "node_id,kind" });
        return sc;
      }
    }

    // 1b) Reutilización por SIMILITUD: sección casi idéntica (otro hash) ya con
    // esta vista en la biblioteca -> la copiamos sin gastar IA.
    if (sectionHash && k !== "original" && origContent.length >= 40) {
      const sim = await findSimilarHash(admin, origContent);
      if (sim && sim.hash !== sectionHash) {
        const { data: shared2 } = await admin
          .from("shared_node_content")
          .select("content")
          .eq("content_hash", sim.hash)
          .eq("kind", k)
          .maybeSingle();
        const sc2 = (shared2 as { content: string | null } | null)?.content;
        if (sc2 && sc2.trim().length > 0) {
          await admin.from("node_content").upsert({
            node_id: node.id,
            user_id: node.user_id,
            kind: k,
            content: sc2,
          }, { onConflict: "node_id,kind" });
          return sc2;
        }
      }
    }

    // 2) Generación con IA.
    const result = await runCompletion(admin, {
      task: `view:${k}`,
      system: systemFor(k, language),
      messages: [{
        role: "user",
        content: textContext
          ? `Section title: ${node.title}\n\nMaterial:\n\n${textContext}`
          : `Section title: ${node.title}\n\nUse the attached document(s).`,
      }],
      attachments: attachments.length > 0 ? attachments : undefined,
      maxOutputTokens: k === "summary" ? 2048 : 8192,
      temperature: k === "original" ? 0 : 0.3,
      userId: node.user_id,
      subjectId: node.subject_id,
    });
    await admin.from("node_content").upsert({
      node_id: node.id,
      user_id: node.user_id,
      kind: k,
      content: result.text,
    }, { onConflict: "node_id,kind" });

    // 3) Aportar a la biblioteca global si el material es libre.
    if (sectionHash && shareable && k !== "original" &&
        result.text.trim().length > 0) {
      await admin.from("shared_node_content").upsert({
        content_hash: sectionHash,
        kind: k,
        content: result.text,
        lang: language,
      }, { onConflict: "content_hash,kind" });
    }
    return result.text;
  };

  try {
    let content: string;
    if (kind === "original") {
      content = await genOne("original");
    } else {
      // Explicado y Resumen se generan a la vez (en la misma petición), pero
      // SECUENCIALMENTE: primero lo que pidió el usuario (y se devuelve), y la
      // otra vista en best-effort. Así evitamos saturar al proveedor gratuito
      // con dos llamadas en paralelo (rate limit) y, si la segunda falla, no
      // tiramos la petición entera: el usuario sí ve lo que pidió.
      content = await genOne(kind);
      const other = kind === "summary" ? "explained" : "summary";
      try {
        await genOne(other);
      } catch (e2) {
        const d = e2 instanceof AiGatewayError ? e2.message : (e2 as Error).message;
        console.error(`generate-views: other view (${other}) failed:`, d);
      }
    }

    return json({ ok: true, cached: false, content }, 200);
  } catch (e) {
    const detail = e instanceof AiGatewayError
      ? e.message
      : (e as Error).message;
    return json({ ok: false, error: "generation_failed", detail }, 200);
  }
}));
