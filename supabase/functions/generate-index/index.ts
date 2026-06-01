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
import { cloneIndexFromPool } from "../_shared/ai/pool.ts";
import { docFingerprint } from "../_shared/ai/hash.ts";
import { reportError } from "../_shared/error_reporter.ts";

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
  shareable?: boolean;
  language?: string | null;
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
  const candidate = start >= 0 && end > start ? t.slice(start, end + 1) : t;
  // 1) Intento estricto.
  try {
    const obj = JSON.parse(candidate) as { nodes?: unknown };
    if (Array.isArray(obj.nodes)) return obj.nodes as IndexNode[];
  } catch {
    // sigue al rescate
  }
  // 2) Rescate de JSON TRUNCADO: si la respuesta se cortó (índice grande que
  // supera el tope de salida), extraemos todos los objetos COMPLETOS del array
  // "nodes" (con sus hijos) y descartamos el último a medias. Mejor un índice
  // parcial que un fallo total.
  return salvageNodes(t);
}

function salvageNodes(t: string): IndexNode[] {
  const key = t.indexOf('"nodes"');
  if (key < 0) return [];
  const arrStart = t.indexOf("[", key);
  if (arrStart < 0) return [];
  const objects: string[] = [];
  let depth = 0;
  let inStr = false;
  let esc = false;
  let objStart = -1;
  for (let i = arrStart + 1; i < t.length; i++) {
    const c = t[i];
    if (inStr) {
      if (esc) esc = false;
      else if (c === "\\") esc = true;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') inStr = true;
    else if (c === "{") {
      if (depth === 0) objStart = i;
      depth++;
    } else if (c === "}") {
      depth--;
      if (depth === 0 && objStart >= 0) {
        objects.push(t.slice(objStart, i + 1));
        objStart = -1;
      }
    } else if (c === "]" && depth === 0) {
      break;
    }
  }
  const out: IndexNode[] = [];
  for (const o of objects) {
    try {
      out.push(JSON.parse(o) as IndexNode);
    } catch {
      // objeto incompleto: ignorar
    }
  }
  return out;
}

/// Cuenta TODOS los nodos del árbol (recursivo). Solo para diagnóstico/logs.
function countNodes(nodes: IndexNode[]): number {
  let n = 0;
  for (const node of nodes) {
    n++;
    if (Array.isArray(node.children)) {
      n += countNodes(node.children as IndexNode[]);
    }
  }
  return n;
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
    .select("id, user_id, title, index_locked, shareable, language")
    .eq("id", subjectId)
    .maybeSingle();
  if (sErr) {
    const errorId = await reportError(admin, {
      userId: user.id,
      fn: "generate-index",
      error: sErr,
      errorCode: "db_error",
      context: { subject_id: subjectId, op: "select_subject" },
      severity: "high",
    });
    return json(
      { ok: false, error_code: "generic_error", error_id: errorId },
      200,
    );
  }
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

    // Reutilización: si ya existe el índice de un documento IDÉNTICO (misma
    // huella), lo clonamos del pool sin gastar IA y terminamos.
    const fingerprint = fullText.trim().length > 0
      ? await docFingerprint(fullText)
      : null;
    if (fingerprint) {
      const cloned = await cloneIndexFromPool(admin, {
        subjectId: subject.id,
        userId: subject.user_id,
        fingerprint,
      });
      if (cloned) {
        await admin.from("subjects")
          .update({ index_status: "ready", index_error: null })
          .eq("id", subject.id);
        // La contribución al pool (y el registro de cesión) ocurre al VALIDAR
        // (validate-index), no al generar/clonar.
        console.log("[generate-index] reused index from pool (identical doc)");
        return;
      }
    }

    const system =
      "You build a hierarchical table of contents (index) for study material. " +
      "Cover it from start to end: every chapter/topic and the FINEST unit as " +
      "the deepest leaves (e.g. for laws: título > capítulo > ARTÍCULO). " +
      "Return ONLY minified JSON: " +
      '{"nodes":[{"title":"...","anchor":"...","children":[...]}]}. EVERY node ' +
      "(folders AND leaves) MUST include `anchor`: the exact verbatim text of " +
      "the first line/heading of that section/chapter/article, copied literally " +
      "from the material (max ~80 chars), so it can be located in the text. " +
      "Do NOT wrap everything under a single root node named after the whole " +
      "document/law; list the top-level sections (e.g. títulos) DIRECTLY in " +
      "`nodes`. Titles concise and in the SAME language as the material. " +
      "No commentary.";

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
    // Cap alto para cubrir temarios largos COMPLETOS (antes 200k recortaba a la
    // mitad los temarios grandes -> índice incompleto). Gemini 2.5 (1M de
    // contexto) y Claude (200k) admiten de sobra este tamaño.
    const aiText = fullText.trim().length > 0
      ? fullText.slice(0, 600000)
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
      // Tope alto para que quepa un índice grande. OJO: el modelo lo acota a SU
      // máximo: gemini-1.5-flash = 8192 (trunca índices medianos!), gemini-2.5-
      // flash = 65536. Por eso conviene usar 2.5-flash. Si aún se trunca, el
      // parser de rescate recupera lo completo.
      maxOutputTokens: 65536,
      temperature: 0.2,
      // El índice es la tarea más exigente: si hay un proveedor de PAGO activo
      // (p. ej. Claude), se prefiere por su mejor seguimiento de "lista TODO";
      // si no, cae a los gratuitos (Gemini). Reordena, no exige pago.
      preferTier: "paid",
      userId: subject.user_id,
      subjectId: subject.id,
    });

    // Diagnóstico: qué modelo respondió, cuánto texto devolvió y si la salida
    // llegó al tope (señal de TRUNCADO = índice incompleto).
    console.log(
      "[generate-index] ai-output:",
      JSON.stringify({
        provider: result.providerSlug,
        model: result.model,
        outputChars: result.text.length,
        outputTokens: result.outputTokens,
      }),
    );

    const raw = parseNodes(result.text);
    if (raw.length === 0) throw new Error("empty_index");
    console.log(
      "[generate-index] parsed:",
      JSON.stringify({ topLevelNodes: raw.length, totalNodes: countNodes(raw) }),
    );

    // Troceo (best-effort) con el texto guardado, si lo hay. Cada nodo recibe
    // SOLO su texto propio: las hojas su sección, las carpetas su intro.
    const hasFullText = fullText.trim().length > 0;
    let tree = toPTree(raw);
    // Si la IA envolvió TODO bajo un único nodo con el nombre del temario
    // (raíz duplicada), lo desempaquetamos: sus hijos pasan al primer nivel.
    if (tree.length === 1 && tree[0].children.length > 0) {
      const wrapper = normText(tree[0].title);
      const subj = normText(subject.title);
      if (wrapper === subj || wrapper.includes(subj) || subj.includes(wrapper)) {
        tree = tree[0].children;
      }
    }
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
    // La contribución a la biblioteca global (secciones + árbol clonable +
    // registro de cesión) ocurre al VALIDAR el índice (validate-index), no al
    // generar: así solo se cachean índices que el usuario ha aprobado.
  } catch (e) {
    const msg = e instanceof AiGatewayError ? e.message : (e as Error).message;
    // Log explícito para que el motivo salga en los logs de la Edge Function
    // (captureError va a Sentry y NO aparece en estos logs).
    console.error("[generate-index] failed:", msg);
    await admin.from("subjects")
      .update({ index_status: "failed", index_error: msg.slice(0, 500) })
      .eq("id", subject.id);
    captureError(e, { fn: "generate-index", subject: subject.id, detail: msg });
    // Y ademas al pipeline in-app de errores (admin /admin/errors).
    await reportError(admin, {
      userId: subject.user_id,
      fn: "generate-index",
      error: e,
      errorCode: e instanceof AiGatewayError ? "ai_gateway" : "index_failed",
      context: { subject_id: subject.id },
      severity: "high",
    });
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
