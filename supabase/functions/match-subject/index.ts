// ============================================================================
// Edge Function: match-subject · ¿Qué material reutilizable hay para este tema?
// ----------------------------------------------------------------------------
// Para cada sección (hoja con texto) del temario calcula su `content_hash` y
// comprueba, contra la biblioteca GLOBAL, cuánto material ya está generado y se
// reutilizará SIN gastar tokens:
//   * exact     -> secciones cuyo texto idéntico ya está en `shared_sections`.
//   * questions -> nº de preguntas disponibles en `question_bank` (por hash).
//   * views     -> secciones con explicado/resumen en `shared_node_content`.
//
// Es de SOLO lectura y por hash (rápido, sin IA): la UI lo llama al abrir el
// temario para avisar "ya tienes material listo". La reutilización real ocurre
// sola al abrir secciones (generate-views) o generar tests (generate-exam).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
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

Deno.serve(withSentry("match-subject", async (req) => {
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
  // `deep` añade detección de secciones MUY parecidas (embeddings). Cuesta IA,
  // así que solo se pide en momentos puntuales (p. ej. el asistente de subida),
  // no en cada apertura del temario.
  const deep = body?.deep === true;
  if (typeof subjectId !== "string") {
    return json({ error: "missing_subject_id" }, 400);
  }

  const { data: subj } = await admin
    .from("subjects")
    .select("id, user_id")
    .eq("id", subjectId)
    .maybeSingle();
  if (!subj) return json({ error: "subject_not_found" }, 404);
  if ((subj as { user_id: string }).user_id !== user.id) {
    return json({ error: "forbidden" }, 403);
  }

  // 1) Hojas con texto propio -> {hash, texto} por sección + longitud total.
  const { data: nodeRows } = await admin
    .from("index_nodes")
    .select("id")
    .eq("subject_id", subjectId)
    .limit(3000);
  const ids = ((nodeRows ?? []) as Array<{ id: string }>).map((n) => n.id);
  const sections: Array<{ hash: string; text: string }> = [];
  let totalChars = 0;
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
      if (t.length >= 40) {
        sections.push({ hash: await contentHash(t), text: t });
        totalChars += t.length;
      }
    }
  }
  const totalSections = sections.length;
  // Temario "escaso": pocas secciones o muy poco texto -> candidato a ampliar.
  const poor = totalSections > 0 && (totalSections < 5 || totalChars < 2000);
  if (totalSections === 0) {
    return json({
      ok: true,
      totalSections: 0,
      exact: 0,
      similar: 0,
      questions: 0,
      flashcards: 0,
      views: 0,
      poor: false,
    }, 200);
  }

  const uniqueHashes = [...new Set(sections.map((s) => s.hash))];

  // 2) Consultas por hash contra la biblioteca global (rápidas, sin IA).
  const exactSet = new Set<string>();
  const viewsSet = new Set<string>();
  let questions = 0;
  let flashcards = 0;
  for (let i = 0; i < uniqueHashes.length; i += 100) {
    const chunk = uniqueHashes.slice(i, i + 100);
    const [sec, qb, snc, sf] = await Promise.all([
      admin.from("shared_sections").select("content_hash").in("content_hash", chunk),
      admin.from("question_bank").select("content_hash").in("content_hash", chunk),
      admin.from("shared_node_content").select("content_hash").in("content_hash", chunk),
      admin.from("shared_flashcards").select("content_hash").in("content_hash", chunk),
    ]);
    for (
      const r of (sec.data ?? []) as Array<{ content_hash: string }>
    ) exactSet.add(r.content_hash);
    questions += ((qb.data ?? []) as unknown[]).length;
    flashcards += ((sf.data ?? []) as unknown[]).length;
    for (
      const r of (snc.data ?? []) as Array<{ content_hash: string }>
    ) viewsSet.add(r.content_hash);
  }

  // Contamos SECCIONES (nodos), no hashes: varias secciones pueden compartir.
  const exact = sections.filter((s) => exactSet.has(s.hash)).length;
  const views = sections.filter((s) => viewsSet.has(s.hash)).length;

  // 3) Análisis profundo (a petición): secciones NO idénticas pero MUY parecidas
  // a algo del pool (embeddings). Acotado a 25 para no abusar de la IA.
  let similar = 0;
  if (deep) {
    const nonExact = sections.filter((s) => !exactSet.has(s.hash)).slice(0, 25);
    for (const s of nonExact) {
      const sim = await findSimilarHash(admin, s.text, 0.85);
      if (sim) similar++;
    }
  }

  return json({
    ok: true,
    totalSections,
    exact,
    similar,
    questions,
    flashcards,
    views,
    poor,
  }, 200);
}));
