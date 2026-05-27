// ============================================================================
// _shared/ai/pool.ts · Escritura en la biblioteca GLOBAL del proyecto
// ----------------------------------------------------------------------------
// Vuelca al pool `shared_sections` las secciones (hojas con texto 'original') de
// un temario, SOLO si el usuario declaró el material como libre (`shareable`).
// Cada sección se guarda indexada por su `content_hash` (la misma clave que el
// banco de preguntas) + un embedding (vector 768) para detectar parecidos.
//
// Es best-effort: cualquier fallo aquí (p. ej. embeddings sin proveedor) NO
// debe romper la generación del índice; se registra y se sigue.
// ============================================================================

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { contentHash } from "./hash.ts";
import { embedTexts } from "./embeddings.ts";

export interface PoolSubject {
  id: string;
  shareable?: boolean;
  language?: string | null;
}

/// Literal de pgvector a partir de un vector JS: "[0.1,0.2,...]".
function toVectorLiteral(v: number[]): string {
  return "[" + v.join(",") + "]";
}

export async function writeSubjectToPool(
  admin: SupabaseClient,
  subject: PoolSubject,
): Promise<void> {
  if (subject.shareable !== true) return;
  try {
    // 1) Títulos de los nodos del temario.
    const { data: nodeRows } = await admin
      .from("index_nodes")
      .select("id, title")
      .eq("subject_id", subject.id)
      .limit(3000);
    const titleById = new Map<string, string>();
    for (const n of (nodeRows ?? []) as Array<{ id: string; title: string }>) {
      titleById.set(n.id, n.title);
    }
    const ids = [...titleById.keys()];
    if (ids.length === 0) return;

    // 2) Texto 'original' de cada hoja -> {hash, title, body}, deduplicado.
    const items: Array<{ hash: string; title: string; body: string }> = [];
    const seen = new Set<string>();
    for (let i = 0; i < ids.length; i += 100) {
      const chunk = ids.slice(i, i + 100);
      const { data: contents } = await admin
        .from("node_content")
        .select("node_id, content")
        .eq("kind", "original")
        .in("node_id", chunk);
      for (
        const c of (contents ?? []) as Array<
          { node_id: string; content: string | null }
        >
      ) {
        const body = (c.content ?? "").trim();
        if (body.length < 40) continue;
        const hash = await contentHash(body);
        if (seen.has(hash)) continue;
        seen.add(hash);
        items.push({ hash, title: titleById.get(c.node_id) ?? "", body });
      }
    }
    if (items.length === 0) return;

    // 3) Saltamos las que ya están en el pool CON embedding.
    const already = new Set<string>();
    const hashes = items.map((it) => it.hash);
    for (let i = 0; i < hashes.length; i += 100) {
      const chunk = hashes.slice(i, i + 100);
      const { data } = await admin
        .from("shared_sections")
        .select("content_hash, embedding")
        .in("content_hash", chunk);
      for (
        const r of (data ?? []) as Array<
          { content_hash: string; embedding: unknown }
        >
      ) {
        if (r.embedding != null) already.add(r.content_hash);
      }
    }
    const todo = items.filter((it) => !already.has(it.hash));
    if (todo.length === 0) return;

    // 4) Embeddings (best-effort).
    let embeddings: number[][];
    try {
      embeddings = await embedTexts(admin, todo.map((t) => t.body));
    } catch (e) {
      console.error("[pool] embed_failed:", (e as Error).message);
      return;
    }

    // 5) Upsert por content_hash.
    const rows = todo.map((t, idx) => ({
      content_hash: t.hash,
      title: t.title.slice(0, 300),
      lang: subject.language ?? null,
      body: t.body.slice(0, 100_000),
      has_text: true,
      embedding: toVectorLiteral(embeddings[idx]),
      source_kind: "user",
    }));
    for (let i = 0; i < rows.length; i += 200) {
      const chunk = rows.slice(i, i + 200);
      const { error } = await admin
        .from("shared_sections")
        .upsert(chunk, { onConflict: "content_hash" });
      if (error) console.error("[pool] upsert_failed:", error.message);
    }
    console.log(`[pool] wrote ${rows.length} shared sections for ${subject.id}`);
  } catch (e) {
    console.error("[pool] write_failed:", (e as Error).message);
  }
}

/// Busca en el pool la sección MÁS PARECIDA a [text] por embedding (coseno).
/// Devuelve su `content_hash` y la similitud si supera [threshold], o `null`.
/// Umbral alto por defecto (0.95): a ese nivel los textos son casi idénticos
/// (p. ej. mismo artículo con diferencias de espacios/OCR), así que el material
/// ya generado es válido. Best-effort: si falla, devuelve `null`.
export async function findSimilarHash(
  admin: SupabaseClient,
  text: string,
  threshold = 0.95,
): Promise<{ hash: string; similarity: number } | null> {
  try {
    const t = text.trim();
    if (t.length < 40) return null;
    const vecs = await embedTexts(admin, [t]);
    const vec = vecs[0];
    if (!vec || vec.length === 0) return null;
    const { data, error } = await admin.rpc("match_shared_sections", {
      query_embedding: "[" + vec.join(",") + "]",
      match_threshold: threshold,
      match_count: 1,
    });
    if (error) {
      console.error("[pool] match_rpc_failed:", error.message);
      return null;
    }
    const rows = (data ?? []) as Array<
      { content_hash: string; similarity: number }
    >;
    if (rows.length === 0) return null;
    return { hash: rows[0].content_hash, similarity: rows[0].similarity };
  } catch (e) {
    console.error("[pool] similar_lookup_failed:", (e as Error).message);
    return null;
  }
}

interface SharedIndexNode {
  i: number;
  parent: number; // índice en el array, o -1 si es raíz
  title: string;
  depth: number;
  position: number;
  leaf: boolean;
  hash: string | null;
}

/// Serializa el árbol del índice de un temario en `shared_indexes`, indexado por
/// la huella del documento, para poder CLONARLO en subidas idénticas sin IA.
/// Best-effort. Solo tiene sentido para material libre (lo decide el llamante).
export async function writeSharedIndex(
  admin: SupabaseClient,
  args: { subjectId: string; fingerprint: string; title: string; lang: string | null },
): Promise<void> {
  try {
    const { data: nodeRows } = await admin
      .from("index_nodes")
      .select("id, parent_id, title, position, depth")
      .eq("subject_id", args.subjectId)
      .order("depth", { ascending: true })
      .order("position", { ascending: true })
      .limit(3000);
    const nodes = (nodeRows ?? []) as Array<{
      id: string;
      parent_id: string | null;
      title: string;
      position: number;
      depth: number;
    }>;
    if (nodes.length === 0) return;

    // Padres (cualquier id que sea parent_id de otro) -> para marcar hojas.
    const parentSet = new Set<string>();
    for (const n of nodes) if (n.parent_id) parentSet.add(n.parent_id);

    // Texto 'original' por nodo, para calcular el hash de cada hoja.
    const ids = nodes.map((n) => n.id);
    const contentByNode = new Map<string, string>();
    for (let i = 0; i < ids.length; i += 100) {
      const chunk = ids.slice(i, i + 100);
      const { data: contents } = await admin
        .from("node_content")
        .select("node_id, content")
        .eq("kind", "original")
        .in("node_id", chunk);
      for (
        const c of (contents ?? []) as Array<
          { node_id: string; content: string | null }
        >
      ) {
        if (c.content) contentByNode.set(c.node_id, c.content);
      }
    }

    const indexById = new Map<string, number>();
    nodes.forEach((n, idx) => indexById.set(n.id, idx));
    const serialized: SharedIndexNode[] = [];
    for (let idx = 0; idx < nodes.length; idx++) {
      const n = nodes[idx];
      const isLeaf = !parentSet.has(n.id);
      const body = (contentByNode.get(n.id) ?? "").trim();
      const hash = isLeaf && body.length >= 40 ? await contentHash(body) : null;
      serialized.push({
        i: idx,
        parent: n.parent_id ? (indexById.get(n.parent_id) ?? -1) : -1,
        title: n.title,
        depth: n.depth,
        position: n.position,
        leaf: isLeaf,
        hash,
      });
    }

    // Hashes de las hojas -> para el índice GIN (acota candidatos en la
    // ampliación sin escanear todo el pool).
    const leafHashes = serialized
      .filter((n) => n.leaf && n.hash)
      .map((n) => n.hash as string);

    const { error } = await admin.from("shared_indexes").upsert({
      doc_fingerprint: args.fingerprint,
      title: args.title.slice(0, 300),
      lang: args.lang,
      nodes: serialized,
      leaf_hashes: leafHashes,
    }, { onConflict: "doc_fingerprint" });
    if (error) console.error("[pool] shared_index_upsert_failed:", error.message);
    else console.log(`[pool] wrote shared index (${serialized.length} nodes)`);
  } catch (e) {
    console.error("[pool] shared_index_failed:", (e as Error).message);
  }
}

/// Deja el registro PERMANENTE de cesión (compliance): quién declaró el material
/// libre (email + fecha/hora). Idempotente por temario. Best-effort.
export async function recordContribution(
  admin: SupabaseClient,
  args: {
    subjectId: string;
    userId: string;
    title: string;
    sectionsCount: number;
  },
): Promise<void> {
  try {
    const { data: existing } = await admin
      .from("shared_contributions")
      .select("id")
      .eq("subject_id", args.subjectId)
      .maybeSingle();
    if (existing) return;
    let email = "unknown";
    try {
      const { data } = await admin.auth.admin.getUserById(args.userId);
      email = data?.user?.email ?? "unknown";
    } catch (_) {
      // si no se puede resolver el email, guardamos 'unknown' (no bloquea)
    }
    await admin.from("shared_contributions").insert({
      subject_id: args.subjectId,
      user_id: args.userId,
      user_email: email,
      subject_title: args.title.slice(0, 300),
      sections_count: args.sectionsCount,
    });
    console.log(`[pool] contribution logged for ${args.subjectId} (${email})`);
  } catch (e) {
    console.error("[pool] contribution_log_failed:", (e as Error).message);
  }
}

/// Intenta CLONAR el índice ya generado de un documento idéntico (misma huella)
/// sin gastar IA: reconstruye `index_nodes` y rellena el texto 'original' de cada
/// hoja desde `shared_sections`. Devuelve `true` si clonó, `false` si no había
/// nada que clonar o falló (el llamante hará el build normal).
export async function cloneIndexFromPool(
  admin: SupabaseClient,
  args: { subjectId: string; userId: string; fingerprint: string },
): Promise<boolean> {
  try {
    const { data: si } = await admin
      .from("shared_indexes")
      .select("nodes")
      .eq("doc_fingerprint", args.fingerprint)
      .maybeSingle();
    const nodes = (si as { nodes: SharedIndexNode[] } | null)?.nodes;
    if (!nodes || nodes.length === 0) return false;

    // 1) Texto 'original' de las hojas desde el pool (por hash) ANTES de insertar
    // nada. Si el índice cacheado no tiene NINGÚN contenido recuperable (p. ej.
    // un índice malo/incompleto que se coló antes), NO clonamos: devolvemos
    // false para que generate-index regenere con la IA. Así un caché envenenado
    // no se sirve eternamente.
    const leafHashes = [
      ...new Set(
        nodes.filter((n) => n.leaf && n.hash).map((n) => n.hash as string),
      ),
    ];
    const bodyByHash = new Map<string, string>();
    for (let i = 0; i < leafHashes.length; i += 100) {
      const chunk = leafHashes.slice(i, i + 100);
      const { data } = await admin
        .from("shared_sections")
        .select("content_hash, body")
        .eq("has_text", true)
        .in("content_hash", chunk);
      for (
        const r of (data ?? []) as Array<
          { content_hash: string; body: string | null }
        >
      ) {
        if (r.body) bodyByHash.set(r.content_hash, r.body);
      }
    }
    if (bodyByHash.size === 0) {
      console.log(
        "[pool] clone skipped: cached index has no recoverable content -> regenerate",
      );
      return false;
    }

    // 2) Inserta los nodos preservando la jerarquía (padres antes que hijos).
    const newIds: string[] = [];
    for (const n of nodes) {
      const parentId = n.parent >= 0 ? (newIds[n.parent] ?? null) : null;
      const { data: row, error } = await admin
        .from("index_nodes")
        .insert({
          subject_id: args.subjectId,
          user_id: args.userId,
          parent_id: parentId,
          title: n.title,
          position: n.position,
          depth: n.depth,
        })
        .select("id")
        .single();
      if (error || !row) throw new Error("clone_node_insert_failed");
      newIds.push(row.id as string);
    }

    // 3) Vuelca el texto 'original' recuperado a las hojas clonadas.
    const contentRows: Array<Record<string, unknown>> = [];
    for (const n of nodes) {
      if (!n.leaf || !n.hash) continue;
      const body = bodyByHash.get(n.hash);
      if (!body) continue;
      contentRows.push({
        node_id: newIds[n.i],
        user_id: args.userId,
        kind: "original",
        content: body,
      });
    }
    for (let i = 0; i < contentRows.length; i += 200) {
      await admin.from("node_content").insert(contentRows.slice(i, i + 200));
    }

    // 3) Métrica (best-effort).
    try {
      const { data: cur } = await admin
        .from("shared_indexes")
        .select("times_reused")
        .eq("doc_fingerprint", args.fingerprint)
        .maybeSingle();
      const n = ((cur as { times_reused: number } | null)?.times_reused ?? 0) + 1;
      await admin.from("shared_indexes")
        .update({ times_reused: n })
        .eq("doc_fingerprint", args.fingerprint);
    } catch (_) { /* no crítico */ }

    console.log(
      `[pool] cloned index (${nodes.length} nodes, ${contentRows.length} bodies)`,
    );
    return true;
  } catch (e) {
    console.error("[pool] clone_failed:", (e as Error).message);
    return false;
  }
}
