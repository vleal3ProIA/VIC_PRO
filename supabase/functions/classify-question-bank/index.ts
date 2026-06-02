// ============================================================================
// Edge Function: classify-question-bank
// ----------------------------------------------------------------------------
// Re-clasifica preguntas del `question_bank` que estan asignadas al nodo
// RAIZ de un subject (porque el parser original no detecto referencia
// explicita a articulo) y las mueve al nodo `Articulo N` correcto,
// consultando al LLM via ai-gateway (Gemini con fallback Groq).
//
// Caso de uso: las 3498 preguntas "genericas" sobre la Constitucion que
// quedaron sin enlace al temario. Tras clasificarlas, al fallar una
// pregunta el usuario puede pulsar "Ver en temario" y navegar al
// articulo donde esta la respuesta.
//
// Gate: capability `manage_ai` (super_admin la tiene siempre).
//
// Body: { subject_id: uuid, limit?: number (default 30) }
// Respuesta:
//   {
//     ok: true,
//     processed: N,           // preguntas a las que la IA respondio
//     classified_high: N,     // movidas a un articulo (confidence=high)
//     classified_other: N,    // respuesta con medium/low -> dejadas en raiz
//     errors: N,              // respuestas que no se pudieron parsear
//     remaining: N            // pendientes en raiz tras este batch
//   }
//
// Es resumible: llamar repetidamente hasta `remaining = 0`.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
import { checkCapability } from "../_shared/capability.ts";
import { AiGatewayError, runCompletion } from "../_shared/ai/gateway.ts";

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

interface Question {
  id: string;
  question: string;
  options: unknown;
  correct_index: number;
}

interface Classification {
  idx: number;
  article: number | null;
  confidence: "high" | "medium" | "low";
}

const SYSTEM_PROMPT = (
  "Eres un experto en la Constitucion Espanola de 1978 (TEXTO CONSOLIDADO, " +
  "BOE-A-1978-31229). Te paso preguntas de oposicion con 4 opciones y la " +
  "letra correcta. Para cada una IDENTIFICA el ARTICULO concreto (numero " +
  "1-169) que regula la materia de la respuesta correcta. Si la pregunta " +
  "es claramente del PREAMBULO, una DISPOSICION (adicional/transitoria/" +
  "derogatoria/final) o NO se basa en un articulo unico, usa null.\n\n" +
  "Devuelve SIEMPRE JSON minificado con esta forma exacta:\n" +
  '{"items":[{"idx":0,"article":14,"confidence":"high"},' +
  '{"idx":1,"article":null,"confidence":"low"}]}\n\n' +
  "REGLAS:\n" +
  " - `idx` corresponde al indice 0-based del item dentro del lote.\n" +
  " - `article` es entero 1..169 o null.\n" +
  " - `confidence`: 'high' si tienes certeza absoluta del articulo; " +
  "'medium' si crees pero podria ser otro; 'low' si dudas o es transversal.\n" +
  " - NO incluyas explicaciones, solo el JSON.\n"
);

const LETTERS = ["A", "B", "C", "D"];

function buildUserMessage(batch: Question[]): string {
  const parts: string[] = ["Lote de preguntas:\n"];
  for (let i = 0; i < batch.length; i++) {
    const q = batch[i];
    const opts = (Array.isArray(q.options) ? q.options : []) as unknown[];
    const correctLetter = LETTERS[q.correct_index] ?? "?";
    parts.push(
      `\n[idx=${i}] Correcta: ${correctLetter}\n` +
        `P: ${q.question}\n` +
        `  A) ${String(opts[0] ?? "")}\n` +
        `  B) ${String(opts[1] ?? "")}\n` +
        `  C) ${String(opts[2] ?? "")}\n` +
        `  D) ${String(opts[3] ?? "")}\n`,
    );
  }
  parts.push("\nDevuelve solo el JSON.");
  return parts.join("");
}

function parseClassifications(text: string): Classification[] {
  // Extrae el primer JSON valido. El gateway puede envolver con texto, etc.
  const m = text.match(/\{[\s\S]*\}/);
  const raw = m ? m[0] : text;
  let obj: unknown;
  try {
    obj = JSON.parse(raw);
  } catch {
    return [];
  }
  if (!obj || typeof obj !== "object") return [];
  const items = (obj as { items?: unknown }).items;
  if (!Array.isArray(items)) return [];
  const out: Classification[] = [];
  for (const it of items) {
    if (!it || typeof it !== "object") continue;
    const o = it as Record<string, unknown>;
    const idx = typeof o.idx === "number" ? o.idx : null;
    if (idx === null) continue;
    let article: number | null = null;
    if (typeof o.article === "number" && Number.isInteger(o.article)) {
      if (o.article >= 1 && o.article <= 169) article = o.article;
    }
    const confRaw = String(o.confidence ?? "low").toLowerCase();
    const confidence: Classification["confidence"] =
      confRaw === "high" ? "high" : confRaw === "medium" ? "medium" : "low";
    out.push({ idx, article, confidence });
  }
  return out;
}

Deno.serve(withSentry("classify-question-bank", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // ─── Auth + capability gate ───
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);
  const capErr = await checkCapability(userClient, user.id, "manage_ai");
  if (capErr) return json({ error: capErr }, 403);

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // ─── Body ───
  const body = await req.json().catch(() => null) as
    | Record<string, unknown>
    | null;
  const subjectId = body?.subject_id;
  if (typeof subjectId !== "string") {
    return json({ error: "missing_subject_id" }, 400);
  }
  const limitRaw = body?.limit;
  const limit = typeof limitRaw === "number" && limitRaw > 0
    ? Math.min(300, Math.floor(limitRaw))
    : 30;

  // ─── Localiza nodo raiz + indice de articulos ───
  const { data: rootNode } = await admin
    .from("index_nodes")
    .select("id, content_hash, title")
    .eq("subject_id", subjectId)
    .is("parent_id", null)
    .maybeSingle();
  if (!rootNode) return json({ error: "subject_root_not_found" }, 404);
  const rootHash = (rootNode as { content_hash: string }).content_hash;

  // Mapa "Articulo N" -> content_hash (md5(title) por convencion seedeada).
  const { data: nodes } = await admin
    .from("index_nodes")
    .select("title, content_hash")
    .eq("subject_id", subjectId);
  const articleHash = new Map<number, string>();
  for (
    const n of ((nodes ?? []) as Array<
      { title: string; content_hash: string | null }
    >)
  ) {
    const m = n.title.match(/^Art[ií]culo\s+(\d+)\s*$/i);
    if (m && n.content_hash) {
      articleHash.set(parseInt(m[1], 10), n.content_hash);
    }
  }

  // ─── Trae el lote de preguntas raiz ───
  const { data: qs } = await admin
    .from("question_bank")
    .select("id, question, options, correct_index")
    .eq("content_hash", rootHash)
    .order("id", { ascending: true })
    .limit(limit);
  const batch = ((qs ?? []) as Question[]);

  if (batch.length === 0) {
    return json({
      ok: true,
      processed: 0,
      classified_high: 0,
      classified_other: 0,
      errors: 0,
      remaining: 0,
      message: "no_more_root_questions",
    }, 200);
  }

  // ─── Llamada IA ───
  let answers: Classification[] = [];
  try {
    const result = await runCompletion(admin, {
      task: "classify",
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: buildUserMessage(batch) }],
      maxOutputTokens: 4096,
      temperature: 0,
      userId: user.id,
      subjectId,
    });
    answers = parseClassifications(result.text ?? "");
  } catch (e) {
    const msg = e instanceof AiGatewayError ? e.message : (e as Error).message;
    return json({ ok: false, error: "ai_failed", detail: msg }, 502);
  }

  const byIdx = new Map<number, Classification>();
  for (const a of answers) byIdx.set(a.idx, a);

  // ─── Aplica updates ───
  let classifiedHigh = 0;
  let classifiedOther = 0;
  let errors = 0;

  for (let i = 0; i < batch.length; i++) {
    const a = byIdx.get(i);
    if (!a) {
      errors++;
      continue;
    }
    if (a.confidence !== "high" || a.article === null) {
      classifiedOther++;
      continue;
    }
    const targetHash = articleHash.get(a.article);
    if (!targetHash) {
      // Articulo respondido por el LLM pero no existe nodo (raro).
      classifiedOther++;
      continue;
    }
    const upd = await admin
      .from("question_bank")
      .update({ content_hash: targetHash })
      .eq("id", batch[i].id);
    if (upd.error) {
      errors++;
    } else {
      classifiedHigh++;
    }
  }

  // ─── Recuento pendientes ───
  const { count: remaining } = await admin
    .from("question_bank")
    .select("id", { count: "exact", head: true })
    .eq("content_hash", rootHash);

  return json({
    ok: true,
    processed: batch.length,
    classified_high: classifiedHigh,
    classified_other: classifiedOther,
    errors,
    remaining: remaining ?? 0,
  }, 200);
}));
