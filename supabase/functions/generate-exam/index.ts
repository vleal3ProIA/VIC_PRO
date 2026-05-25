// ============================================================================
// Edge Function: generate-exam · Banco de preguntas de examen (Fase 4)
// ----------------------------------------------------------------------------
// Genera N preguntas MCQ de las SECCIONES elegidas del índice (o de todo el
// temario), etiquetando cada una con la sección a la que pertenece (node_id),
// con explicación. Reemplaza el banco `exam_questions` del temario.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
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

interface RawQ {
  question?: unknown;
  options?: unknown;
  correct_index?: unknown;
  explanation?: unknown;
  section?: unknown;
}

interface ParsedQ {
  question: string;
  options: string[];
  correct_index: number;
  explanation: string | null;
  section: string | null;
}

function parseQuestions(text: string): ParsedQ[] {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    const obj = JSON.parse(t) as { questions?: unknown };
    const arr = Array.isArray(obj.questions) ? obj.questions as RawQ[] : [];
    const out: ParsedQ[] = [];
    for (const q of arr) {
      if (!q || typeof q.question !== "string") continue;
      const opts = Array.isArray(q.options)
        ? (q.options as unknown[])
          .filter((o): o is string => typeof o === "string" && o.trim().length > 0)
          .map((o) => o.slice(0, 300).trim())
        : [];
      if (opts.length < 2 || opts.length > 6) continue;
      const ci = typeof q.correct_index === "number"
        ? Math.trunc(q.correct_index)
        : 0;
      if (ci < 0 || ci >= opts.length) continue;
      out.push({
        question: (q.question as string).slice(0, 500).trim(),
        options: opts,
        correct_index: ci,
        explanation: typeof q.explanation === "string"
          ? (q.explanation as string).slice(0, 800).trim()
          : null,
        section: typeof q.section === "string"
          ? (q.section as string).trim()
          : null,
      });
    }
    return out;
  } catch {
    return [];
  }
}

interface NodeRow {
  id: string;
  title: string;
}

Deno.serve(withSentry("generate-exam", async (req) => {
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
  const nodeIds = Array.isArray(body?.node_ids)
    ? (body!.node_ids as unknown[]).filter((x): x is string =>
      typeof x === "string"
    )
    : [];
  // `count` <= 0 significa "TODAS": generamos tantas como el material permita,
  // hasta un tope duro. Si no, lo acotamos a [3, 100].
  const rawCount = typeof body?.count === "number" ? body.count : 10;
  const allMode = rawCount <= 0;
  const target = allMode
    ? 100
    : Math.max(3, Math.min(100, Math.trunc(rawCount)));
  if (typeof subjectId !== "string") {
    return json({ error: "missing_subject_id" }, 400);
  }

  const { data: subj } = await admin
    .from("subjects")
    .select("id, user_id, language")
    .eq("id", subjectId)
    .maybeSingle();
  if (!subj) return json({ error: "subject_not_found" }, 404);
  const subject = subj as {
    id: string;
    user_id: string;
    language: string | null;
  };
  if (subject.user_id !== user.id) return json({ error: "forbidden" }, 403);

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `generate-exam:${user.id}`,
    limit: 12,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // Secciones (para etiquetar y para el texto): si hay node_ids, esas; si no,
  // el índice del temario (acotado).
  let sections: NodeRow[] = [];
  if (nodeIds.length > 0) {
    const { data } = await admin
      .from("index_nodes")
      .select("id, title")
      .eq("subject_id", subjectId)
      .in("id", nodeIds);
    sections = ((data ?? []) as NodeRow[]);
  } else {
    const { data } = await admin
      .from("index_nodes")
      .select("id, title")
      .eq("subject_id", subjectId)
      .order("depth")
      .order("position")
      .limit(150);
    sections = ((data ?? []) as NodeRow[]);
  }

  // Material: SIEMPRE preferimos el texto 'original' ya guardado de las
  // secciones implicadas (las elegidas, o todas las del índice cuando es "todo
  // el temario"). Al ser TEXTO, el gateway puede usar cualquier proveedor con
  // fallback (gratis→pago); si tirásemos del documento como adjunto de visión
  // quedaríamos atados a Gemini/Anthropic y fallaría al saturarse.
  let textContext = "";
  let attachments: AiAttachment[] = [];
  const sectionIds = sections.map((s) => s.id);
  if (sectionIds.length > 0) {
    const { data: contents } = await admin
      .from("node_content")
      .select("node_id, content")
      .eq("kind", "original")
      .in("node_id", sectionIds);
    const byNode = new Map<string, string>();
    for (const c of ((contents ?? []) as Array<{ node_id: string; content: string | null }>)) {
      if (c.content) byNode.set(c.node_id, c.content);
    }
    const parts: string[] = [];
    for (const s of sections) {
      const txt = byNode.get(s.id);
      if (txt && txt.trim().length > 0) parts.push(`## ${s.title}\n${txt}`);
    }
    textContext = parts.join("\n\n").slice(0, 200000);
  }
  // Respaldo: si las secciones no tienen 'original' guardado, recurrimos al
  // material completo del temario (texto extraído o, en último caso, visión).
  if (textContext.length < 50) {
    const mat = await gatherMaterial(admin, subjectId);
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

  const titles = sections.map((s) => s.title).filter((t) => t && t.length > 0);
  const sectionsBlock = titles.length > 0
    ? "\n\nSections (use one EXACT title from this list as `section`):\n" +
      titles.map((t) => `- ${t}`).join("\n")
    : "";
  const lang = subject.language && subject.language.length > 0
    ? `Write in this language (ISO code): ${subject.language}.`
    : "Write in the SAME language as the material.";

  // System prompt de una tanda de `n` preguntas NUEVAS, evitando repetir las
  // ya generadas (para poder acumular hasta el objetivo en varias llamadas).
  function buildSystem(n: number, existing: string[]): string {
    const avoid = existing.length > 0
      ? "\n\nDo NOT repeat or rephrase any of these already-created questions:\n" +
        existing.slice(-120).map((q) => `- ${q}`).join("\n")
      : "";
    return "You create a multiple-choice EXAM from the material. Return ONLY " +
      'minified JSON: {"questions":[{"question":"...","options":["...","...",' +
      '"...","..."],"correct_index":0,"explanation":"...","section":"..."}]}. ' +
      "Exactly 4 plausible options, ONLY ONE correct, grounded ONLY in the " +
      "material (do not invent). `correct_index` is the 0-based index of the " +
      "right option. `explanation` briefly says why it is correct. `section` " +
      "is the EXACT title of the section the question belongs to (copied from " +
      `the list). Produce up to ${n} NEW distinct questions, spread across the ` +
      "sections. If the material does not support more distinct, grounded " +
      'questions, return {"questions":[]}. ' + lang + sectionsBlock + avoid +
      " No commentary.";
  }

  const userContent = textContext
    ? "Material:\n\n" + textContext
    : "Use the attached document(s).";
  const usingAttachments = attachments.length > 0;

  function normQ(q: string): string {
    return q.trim().toLowerCase().replace(/\s+/g, " ");
  }

  // Resuelve section -> node_id (igualdad/contiene, sin mayúsculas).
  function resolveNode(section: string | null): string | null {
    if (!section) return null;
    const s = section.trim().toLowerCase();
    for (const n of sections) {
      const t = n.title.trim().toLowerCase();
      if (t.length > 0 && (t === s || t.includes(s) || s.includes(t))) {
        return n.id;
      }
    }
    return null;
  }

  try {
    // Generamos por lotes acumulando preguntas distintas hasta alcanzar el
    // objetivo. Cada lote va en SU PROPIO try: si un proveedor falla en un
    // lote no se pierde lo ya generado. Paramos si dos lotes seguidos no
    // aportan nada (el material no da para más) o si nos acercamos al límite
    // de tiempo del Edge Function (devolvemos lo conseguido en vez de morir
    // por timeout). Con visión hacemos una sola llamada (reenviar el adjunto
    // por lote sería caro y los proveedores con visión están limitados).
    const collected: ParsedQ[] = [];
    const seen = new Set<string>();
    const batchSize = 25;
    const maxBatches = usingAttachments ? 1 : 8;
    const startedAt = Date.now();
    const timeBudgetMs = 95_000;
    let stalls = 0;
    let lastError: string | null = null;

    for (let b = 0; b < maxBatches; b++) {
      if (collected.length >= target) break;
      if (Date.now() - startedAt > timeBudgetMs) break;
      const n = Math.min(batchSize, target - collected.length);
      let added = 0;
      try {
        const result = await runCompletion(admin, {
          task: "exam",
          system: buildSystem(n, collected.map((q) => q.question)),
          messages: [{ role: "user", content: userContent }],
          attachments: usingAttachments ? attachments : undefined,
          maxOutputTokens: 8192,
          temperature: 0.4,
          userId: subject.user_id,
          subjectId: subject.id,
        });
        for (const q of parseQuestions(result.text)) {
          const key = normQ(q.question);
          if (key.length === 0 || seen.has(key)) continue;
          seen.add(key);
          collected.push(q);
          added++;
          if (collected.length >= target) break;
        }
      } catch (e) {
        lastError = e instanceof AiGatewayError
          ? e.message
          : (e as Error).message;
      }
      if (added === 0) {
        if (++stalls >= 2) break;
      } else {
        stalls = 0;
      }
    }

    if (collected.length === 0) {
      return json(
        {
          ok: false,
          error: "generation_failed",
          detail: lastError ?? "empty_result",
        },
        200,
      );
    }

    await admin.from("exam_questions").delete().eq("subject_id", subject.id);
    const rows = collected.map((q) => ({
      subject_id: subject.id,
      user_id: subject.user_id,
      node_id: resolveNode(q.section),
      question: q.question,
      options: q.options,
      correct_index: q.correct_index,
      explanation: q.explanation,
    }));
    await admin.from("exam_questions").insert(rows);

    return json({ ok: true, count: rows.length }, 200);
  } catch (e) {
    const detail = e instanceof AiGatewayError
      ? e.message
      : (e as Error).message;
    return json({ ok: false, error: "generation_failed", detail }, 200);
  }
}));
