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

interface SubjectRow {
  id: string;
  user_id: string;
  title: string;
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
    .select("id, user_id, title")
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

/// Nodo del árbol interno con su rango [start,end) dentro del texto completo.
interface PNode {
  title: string;
  anchor: string | null;
  children: PNode[];
  start: number;
  end: number;
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
    });
  }
  return out;
}

function collectLeaves(nodes: PNode[], acc: PNode[]): void {
  for (const n of nodes) {
    if (n.children.length === 0) {
      acc.push(n);
    } else {
      collectLeaves(n.children, acc);
    }
  }
}

/// Localiza cada hoja por su anchor (texto verbatim de su cabecera) dentro del
/// texto completo, con cursor monótono. Cada hoja va desde su posición hasta la
/// de la siguiente.
function assignLeafRanges(leaves: PNode[], fullText: string): void {
  let cursor = 0;
  for (const leaf of leaves) {
    const probe = (leaf.anchor ?? leaf.title).trim();
    let pos = -1;
    if (probe.length >= 3) {
      pos = fullText.indexOf(probe, cursor);
      if (pos < 0) pos = fullText.indexOf(probe.slice(0, 40), cursor);
    }
    leaf.start = pos < 0 ? cursor : pos;
    cursor = leaf.start + 1;
  }
  for (let i = 0; i < leaves.length; i++) {
    leaves[i].end = i + 1 < leaves.length
      ? leaves[i + 1].start
      : fullText.length;
  }
}

/// Rango de una carpeta = abarca a todas sus hojas descendientes.
function rollupFolders(nodes: PNode[]): void {
  for (const n of nodes) {
    if (n.children.length > 0) {
      rollupFolders(n.children);
      const acc: PNode[] = [];
      collectLeaves([n], acc);
      if (acc.length > 0) {
        n.start = Math.min(...acc.map((l) => l.start));
        n.end = Math.max(...acc.map((l) => l.end));
      }
    }
  }
}

// deno-lint-ignore no-explicit-any
async function storeOriginal(
  admin: any,
  subject: SubjectRow,
  nodeId: string,
  text: string,
): Promise<void> {
  const content = text.trim();
  if (content.length === 0) return;
  await admin.from("node_content").insert({
    node_id: nodeId,
    user_id: subject.user_id,
    kind: "original",
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
    // Texto completo (unpdf) si lo hay. Si es corto (p.ej. aún no re-ingerido),
    // construimos el índice adjuntando el PDF por visión para que salga
    // COMPLETO igualmente; el troceo del original solo se hace si hay texto.
    const useText = fullText.trim().length > 1000;
    const forModel = fullText.length > 300000
      ? fullText.slice(0, 300000)
      : fullText;

    const system =
      "You build a hierarchical table of contents (index) for study material. " +
      "Cover it from start to end: every chapter/topic and the FINEST unit as " +
      "the deepest leaves (e.g. for laws: título > capítulo > ARTÍCULO). " +
      "Return ONLY minified JSON: " +
      '{"nodes":[{"title":"...","anchor":"...","children":[...]}]}. For LEAF ' +
      "nodes (no children), `anchor` MUST be the exact verbatim text of the " +
      "first line/heading of that section, copied literally from the material " +
      "(max ~80 chars), so it can be located. Folders need only `title`. " +
      "Titles concise and in the SAME language as the material. No commentary.";

    let messages: Array<{ role: "user"; content: string }>;
    let attachments: AiAttachment[] | undefined;
    if (useText) {
      messages = [{ role: "user", content: "Material:\n\n" + forModel }];
      attachments = undefined;
    } else {
      const mat = await gatherMaterial(admin, subject.id);
      if (!mat.textContext && mat.attachments.length === 0) {
        throw new Error("no_ready_documents");
      }
      messages = [{
        role: "user",
        content: mat.textContext
          ? "Material:\n\n" + mat.textContext
          : "Build the index from the attached document(s).",
      }];
      attachments = mat.attachments.length > 0 ? mat.attachments : undefined;
    }

    const result = await runCompletion(admin, {
      task: "index",
      system,
      messages,
      attachments,
      maxOutputTokens: 8192,
      temperature: 0.2,
      userId: subject.user_id,
      subjectId: subject.id,
    });

    const raw = parseNodes(result.text);
    if (raw.length === 0) throw new Error("empty_index");

    // Árbol interno. Solo troceamos el original si tenemos el texto completo.
    const tree = toPTree(raw);
    if (useText) {
      const leaves: PNode[] = [];
      collectLeaves(tree, leaves);
      assignLeafRanges(leaves, fullText);
      rollupFolders(tree);
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
    if (useText) {
      await storeOriginal(admin, subject, rootRow.id as string, fullText);
    }
    await insertTree(admin, subject, tree, rootRow.id as string, 1, fullText);

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
    if (n.end > n.start) {
      await storeOriginal(admin, subject, nodeId, fullText.slice(n.start, n.end));
    }
    if (n.children.length > 0 && depth < 6) {
      await insertTree(admin, subject, n.children, nodeId, depth + 1, fullText);
    }
  }
}
