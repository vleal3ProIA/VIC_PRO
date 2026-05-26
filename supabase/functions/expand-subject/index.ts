// ============================================================================
// Edge Function: expand-subject · Ampliar un temario escaso con la biblioteca
// ----------------------------------------------------------------------------
// Cuando el temario del usuario es pobre, busca en el pool un temario SIMILAR
// pero MÁS COMPLETO y le AÑADE las secciones que le faltan (con su texto), bajo
// una carpeta "Material adicional". Las vistas/preguntas/flashcards de esas
// secciones se reutilizan solas (mismo content_hash), así que no gasta IA.
//
// Solo se ejecuta si el usuario lo ACEPTA explícitamente (lo decide la UI).
// Algoritmo:
//   1. Calcula los hashes del temario + el hash de pool más cercano de cada
//      sección (embeddings) -> conjunto "lo que ya tiene".
//   2. Busca el `shared_index` con más solapamiento y más secciones totales.
//   3. Añade sus hojas que NO tiene (y de las que hay texto en shared_sections).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { contentHash } from "../_shared/ai/hash.ts";
import { findSimilarHash } from "../_shared/ai/pool.ts";

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

interface SiNode {
  title: string;
  depth: number;
  position: number;
  leaf: boolean;
  hash: string | null;
}
interface SiRow {
  doc_fingerprint: string;
  title: string | null;
  nodes: SiNode[];
}

Deno.serve(withSentry("expand-subject", async (req) => {
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
  const folderTitle =
    (typeof body?.folder_title === "string" && body.folder_title.trim().length > 0
      ? (body.folder_title as string)
      : "Material adicional").slice(0, 200);

  const { data: subj } = await admin
    .from("subjects")
    .select("id, user_id")
    .eq("id", subjectId)
    .maybeSingle();
  if (!subj) return json({ error: "subject_not_found" }, 404);
  if ((subj as { user_id: string }).user_id !== user.id) {
    return json({ error: "forbidden" }, 403);
  }

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `expand-subject:${user.id}`,
    limit: 6,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // 1) Secciones del usuario -> {hash, texto}.
  const { data: nodeRows } = await admin
    .from("index_nodes")
    .select("id")
    .eq("subject_id", subjectId)
    .limit(3000);
  const ids = ((nodeRows ?? []) as Array<{ id: string }>).map((n) => n.id);
  const userSections: Array<{ hash: string; text: string }> = [];
  for (let i = 0; i < ids.length; i += 100) {
    const chunk = ids.slice(i, i + 100);
    const { data: contents } = await admin
      .from("node_content")
      .select("content")
      .eq("kind", "original")
      .in("node_id", chunk);
    for (
      const c of (contents ?? []) as Array<{ content: string | null }>
    ) {
      const t = (c.content ?? "").trim();
      if (t.length >= 40) userSections.push({ hash: await contentHash(t), text: t });
    }
  }
  if (userSections.length === 0) return json({ ok: true, added: 0 }, 200);

  // "Lo que ya tiene": hashes propios + el hash de pool más cercano de cada uno.
  const knownHashes = new Set<string>(userSections.map((s) => s.hash));
  for (const s of userSections.slice(0, 40)) {
    const sim = await findSimilarHash(admin, s.text, 0.9);
    if (sim) knownHashes.add(sim.hash);
  }

  // 2) Mejor candidato: el shared_index con más solapamiento y más secciones.
  // Acotamos con el índice GIN (`leaf_hashes && {conocidos}`): solo traemos los
  // que comparten alguna sección con el usuario, no toda la biblioteca.
  const knownArr = [...knownHashes];
  const { data: idxRows } = await admin
    .from("shared_indexes")
    .select("doc_fingerprint, title, nodes")
    .overlaps("leaf_hashes", knownArr)
    .limit(50);
  let best: { row: SiRow; matched: number; missing: Array<{ title: string; hash: string }> } | null = null;
  const minOverlap = Math.max(2, Math.floor(userSections.length * 0.3));
  for (const row of (idxRows ?? []) as SiRow[]) {
    const leaves = (row.nodes ?? []).filter((n) => n.leaf && n.hash);
    if (leaves.length <= userSections.length) continue;
    let matched = 0;
    const missing: Array<{ title: string; hash: string }> = [];
    for (const lf of leaves) {
      if (knownHashes.has(lf.hash as string)) matched++;
      else missing.push({ title: lf.title, hash: lf.hash as string });
    }
    if (matched < minOverlap || missing.length === 0) continue;
    if (!best || matched > best.matched) best = { row, matched, missing };
  }
  if (!best) return json({ ok: true, added: 0 }, 200);

  // 3) Texto de las secciones que faltan (solo las que existen en el pool).
  const missHashes = [...new Set(best.missing.map((m) => m.hash))].slice(0, 300);
  const bodyByHash = new Map<string, string>();
  for (let i = 0; i < missHashes.length; i += 100) {
    const chunk = missHashes.slice(i, i + 100);
    const { data } = await admin
      .from("shared_sections")
      .select("content_hash, body")
      .eq("has_text", true)
      .in("content_hash", chunk);
    for (
      const r of (data ?? []) as Array<{ content_hash: string; body: string | null }>
    ) {
      if (r.body) bodyByHash.set(r.content_hash, r.body);
    }
  }
  const toAdd = best.missing.filter((m) => bodyByHash.has(m.hash));
  if (toAdd.length === 0) return json({ ok: true, added: 0 }, 200);

  // 4) Carpeta "Material adicional" colgando del raíz + las hojas que faltan.
  const { data: roots } = await admin
    .from("index_nodes")
    .select("id")
    .eq("subject_id", subjectId)
    .is("parent_id", null)
    .order("position")
    .limit(1);
  const rootId = (roots?.[0] as { id: string } | undefined)?.id ?? null;
  const folderDepth = rootId ? 1 : 0;
  let maxPos = -1;
  {
    let q = admin.from("index_nodes").select("position").eq("subject_id", subjectId);
    q = rootId ? q.eq("parent_id", rootId) : q.is("parent_id", null);
    const { data } = await q.order("position", { ascending: false }).limit(1);
    maxPos = ((data?.[0] as { position: number } | undefined)?.position ?? -1);
  }
  const { data: folderRow, error: folderErr } = await admin
    .from("index_nodes")
    .insert({
      subject_id: subjectId,
      user_id: user.id,
      parent_id: rootId,
      title: folderTitle,
      position: maxPos + 1,
      depth: folderDepth,
    })
    .select("id")
    .single();
  if (folderErr || !folderRow) {
    return json({ error: "insert_failed", detail: folderErr?.message }, 500);
  }
  const folderId = (folderRow as { id: string }).id;

  let added = 0;
  let pos = 0;
  for (const m of toAdd) {
    const { data: leafRow } = await admin
      .from("index_nodes")
      .insert({
        subject_id: subjectId,
        user_id: user.id,
        parent_id: folderId,
        title: m.title.slice(0, 300),
        position: pos++,
        depth: folderDepth + 1,
        content_hash: m.hash,
      })
      .select("id")
      .single();
    if (!leafRow) continue;
    await admin.from("node_content").insert({
      node_id: (leafRow as { id: string }).id,
      user_id: user.id,
      kind: "original",
      content: bodyByHash.get(m.hash),
    });
    added++;
  }

  console.log(`[expand-subject] added ${added} sections to ${subjectId}`);
  return json({ ok: true, added, source: best.row.title }, 200);
}));
