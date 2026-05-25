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
  title: string;
  index_locked?: boolean;
}

interface IndexNode {
  title?: unknown;
  anchor?: unknown;
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
    .select("id, user_id, title, index_locked")
    .eq("id", subjectId)
    .maybeSingle();
  if (sErr) return json({ error: "db_error", detail: sErr.message }, 500);
  if (!subj) return json({ error: "subject_not_found" }, 404);
  if ((subj as SubjectRow).user_id !== user.id) {
    return json({ error: "forbidden" }, 403);
  }
  const subject = subj as SubjectRow;

  // Índice validado por el usuario: ya no se puede regenerar.
  if (subject.index_locked === true) {
    return json({ error: "index_locked" }, 409);
  }

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
    .update({ index_status: "generating", index_error: null })
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

/// Nodo del árbol interno con su rango [start,end) dentro del texto completo.
/// `start` = posición de su cabecera; `end` = posición de la siguiente cabecera
/// en orden de documento (pre-orden). `found` = si se localizó su anchor.
interface PNode {
  title: string;
  anchor: string | null;
  children: PNode[];
  start: number;
  end: number;
  found: boolean;
}

function toPTree(raw: IndexNode[]): PNode[] {
  const out: PNode[] = [];
  for (const r of raw) {
    if (!r || typeof r.title !== "string" || r.title.trim().length === 0) {
      continue;
    }
    const children = Array.isArray(r.children)
      ? toPTree(r.children as IndexNode[])
      : [] as PNode[];
    out.push({
      title: (r.title as string).slice(0, 300),
      anchor: typeof r.anchor === "string" ? r.anchor as string : null,
      children,
      start: 0,
      end: 0,
      found: false,
    });
  }
  return out;
}

/// Aplana el árbol en PRE-ORDEN (cada carpeta antes que sus hijos), que es el
/// orden en que aparecen las cabeceras en el documento.
function flattenPreOrder(nodes: PNode[], acc: PNode[]): void {
  for (const n of nodes) {
    acc.push(n);
    flattenPreOrder(n.children, acc);
  }
}

/// Localiza la cabecera de CADA nodo por su anchor (texto verbatim), con cursor
/// monótono, y fija su rango PROPIO [start, end): desde su cabecera hasta la
/// cabecera del siguiente nodo en el documento. Así el texto propio de una HOJA
/// es su sección completa, y el de una CARPETA es solo su intro (lo que hay
/// entre su cabecera y su primer subapartado).
function assignRanges(flat: PNode[], fullText: string): void {
  let cursor = 0;
  for (const n of flat) {
    const probe = (n.anchor ?? n.title).trim();
    let pos = -1;
    if (probe.length >= 3) {
      pos = fullText.indexOf(probe, cursor);
      if (pos < 0) pos = fullText.indexOf(probe.slice(0, 40), cursor);
    }
    n.found = pos >= 0;
    n.start = pos < 0 ? cursor : pos;
    cursor = n.start + 1;
  }
  for (let i = 0; i < flat.length; i++) {
    flat[i].end = i + 1 < flat.length ? flat[i + 1].start : fullText.length;
  }
}

// deno-lint-ignore no-explicit-any
async function storeContent(
  admin: any,
  subject: SubjectRow,
  nodeId: string,
  kind: string,
  text: string,
): Promise<void> {
  const content = text.trim();
  if (content.length === 0) return;
  await admin.from("node_content").insert({
    node_id: nodeId,
    user_id: subject.user_id,
    kind,
    content,
  });
}

// deno-lint-ignore no-explicit-any
async function buildIndex(admin: any, subject: SubjectRow): Promise<void> {
  try {
    const { data: docs } = await admin
      .from("documents")
      .select("extracted_text")
      .eq("subject_id", subject.id)
      .eq("status", "ready");
    const fullText = ((docs ?? []) as Array<{ extracted_text: string | null }>)
      .map((d) => d.extracted_text ?? "")
      .filter((t) => t.length > 0)
      .join("\n\n");
    const system =
      "You build a hierarchical table of contents (index) for study material. " +
      "Cover it from start to end: every chapter/topic and the FINEST unit as " +
      "the deepest leaves (e.g. for laws: título > capítulo > ARTÍCULO). " +
      "Return ONLY minified JSON: " +
      '{"nodes":[{"title":"...","anchor":"...","children":[...]}]}. EVERY node ' +
      "(folders AND leaves) MUST include `anchor`: the exact verbatim text of " +
      "the first line/heading of that section/chapter/article, copied literally " +
      "from the material (max ~80 chars), so it can be located in the text. " +
      "Titles concise and in the SAME language as the material. No commentary.";

    // El índice SIEMPRE se construye leyendo el documento (visión del PDF +
    // texto de .txt) para que salga COMPLETO. El troceo del original usa el
    // texto guardado (unpdf) si lo hay.
    const mat = await gatherMaterial(admin, subject.id);
    console.log(
      "[generate-index] material:",
      JSON.stringify({
        textChars: mat.textContext.length,
        attachments: mat.attachments.length,
        fullTextChars: fullText.length,
      }),
    );
    // Para el índice preferimos el TEXTO extraído (fullText / extracted_text):
    // así lo puede generar CUALQUIER proveedor con fallback, no solo los de
    // visión (Gemini/Anthropic), que pueden fallar por credenciales. Solo
    // usamos visión (adjunto) si NO hay nada de texto.
    const aiText = fullText.trim().length > 0
      ? fullText.slice(0, 200000)
      : mat.textContext;
    const useVision = aiText.trim().length === 0 && mat.attachments.length > 0;
    if (aiText.trim().length === 0 && !useVision) {
      throw new Error("no_ready_documents");
    }

    const result = await runCompletion(admin, {
      task: "index",
      system,
      messages: [{
        role: "user",
        content: aiText.trim().length > 0
          ? "Material:\n\n" + aiText
          : "Build the index from the attached document(s).",
      }],
      attachments: useVision ? mat.attachments : undefined,
      maxOutputTokens: 8192,
      temperature: 0.2,
      userId: subject.user_id,
      subjectId: subject.id,
    });

    const raw = parseNodes(result.text);
    if (raw.length === 0) throw new Error("empty_index");

    // Troceo (best-effort) con el texto guardado, si lo hay. Cada nodo recibe
    // SOLO su texto propio: las hojas su sección, las carpetas su intro.
    const hasFullText = fullText.trim().length > 0;
    const tree = toPTree(raw);
    const flat: PNode[] = [];
    if (hasFullText) {
      flattenPreOrder(tree, flat);
      assignRanges(flat, fullText);
    }

    // Nodo raíz = nombre del temario, con el ORIGINAL completo.
    const { data: rootRow, error: rootErr } = await admin
      .from("index_nodes")
      .insert({
        subject_id: subject.id,
        user_id: subject.user_id,
        parent_id: null,
        title: subject.title.slice(0, 300),
        position: 0,
        depth: 0,
      })
      .select("id")
      .single();
    if (rootErr || !rootRow) throw new Error("root_insert_failed");
    // "Intro" del raíz = preámbulo del documento (lo que haya antes del primer
    // apartado). No guardamos el texto completo como 'original' del raíz.
    if (hasFullText && flat.length > 0) {
      const preamble = fullText.slice(0, flat[0].start).trim();
      if (preamble.length >= 40) {
        await storeContent(
          admin,
          subject,
          rootRow.id as string,
          "intro",
          preamble,
        );
      }
    }
    await insertTree(admin, subject, tree, rootRow.id as string, 1, fullText);

    await admin.from("subjects")
      .update({ index_status: "ready", index_error: null })
      .eq("id", subject.id);
  } catch (e) {
    const msg = e instanceof AiGatewayError ? e.message : (e as Error).message;
    // Log explícito para que el motivo salga en los logs de la Edge Function
    // (captureError va a Sentry y NO aparece en estos logs).
    console.error("[generate-index] failed:", msg);
    await admin.from("subjects")
      .update({ index_status: "failed", index_error: msg.slice(0, 500) })
      .eq("id", subject.id);
    captureError(e, { fn: "generate-index", subject: subject.id, detail: msg });
  }
}

// deno-lint-ignore no-explicit-any
async function insertTree(
  admin: any,
  subject: SubjectRow,
  nodes: PNode[],
  parentId: string,
  depth: number,
  fullText: string,
): Promise<void> {
  let position = 0;
  for (const n of nodes) {
    const { data: row, error } = await admin
      .from("index_nodes")
      .insert({
        subject_id: subject.id,
        user_id: subject.user_id,
        parent_id: parentId,
        title: n.title,
        position: position++,
        depth,
      })
      .select("id")
      .single();
    if (error || !row) continue;
    const nodeId = row.id as string;
    const isLeaf = n.children.length === 0;
    if (isLeaf) {
      // Hoja: su sección COMPLETA como 'original'.
      if (n.end > n.start) {
        await storeContent(
          admin,
          subject,
          nodeId,
          "original",
          fullText.slice(n.start, n.end),
        );
      }
    } else if (n.found && n.end > n.start) {
      // Carpeta: SOLO su intro (lo que hay entre su cabecera y el primer
      // subapartado), quitando la línea de la cabecera. Solo si hay intro real.
      const own = fullText.slice(n.start, n.end);
      const nl = own.indexOf("\n");
      const body = (nl >= 0 ? own.slice(nl + 1) : "").trim();
      if (body.length >= 40) {
        await storeContent(admin, subject, nodeId, "intro", body);
      }
    }
    if (n.children.length > 0 && depth < 6) {
      await insertTree(admin, subject, n.children, nodeId, depth + 1, fullText);
    }
  }
}
