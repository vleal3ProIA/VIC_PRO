// ============================================================================
// Edge Function: generate-tf · Banco GLOBAL de Verdadero/Falso por contenido
// ----------------------------------------------------------------------------
// Hermana de `generate-exam` pero genera afirmaciones BINARIAS (V/F) en lugar
// de preguntas de opción múltiple. Misma arquitectura: por SECCIÓN, con
// reutilización por hash del texto (`content_hash` en `index_nodes`), guardadas
// en el banco COMPARTIDO `tf_bank` (RLS read-all, write solo service_role).
//
// Como las afirmaciones T/F son más cortas que las preguntas tipo test, el
// objetivo por sección sube a un máximo de 40 (vs 25 en `generate-exam`).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
import { AiGatewayError, runCompletion } from "../_shared/ai/gateway.ts";
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

interface RawTf {
  statement?: unknown;
  is_true?: unknown;
  explanation?: unknown;
}

interface ParsedTf {
  statement: string;
  is_true: boolean;
  explanation: string | null;
}

function parseItems(text: string): ParsedTf[] {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    const obj = JSON.parse(t) as { items?: unknown };
    const arr = Array.isArray(obj.items) ? obj.items as RawTf[] : [];
    const out: ParsedTf[] = [];
    for (const q of arr) {
      if (!q || typeof q.statement !== "string") continue;
      if (typeof q.is_true !== "boolean") continue;
      const statement = (q.statement as string).slice(0, 500).trim();
      if (statement.length === 0) continue;
      out.push({
        statement,
        is_true: q.is_true,
        explanation: typeof q.explanation === "string"
          ? (q.explanation as string).slice(0, 800).trim()
          : null,
      });
    }
    return out;
  } catch {
    return [];
  }
}

function normText(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, " ");
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(s),
  );
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

interface NodeRow {
  id: string;
  title: string;
}

Deno.serve(withSentry("generate-tf", async (req) => {
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
  const force = body?.force === true;
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
    bucketKey: `tf:${user.id}`,
    limit: 12,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // Secciones objetivo: las elegidas (node_ids) o todas las del temario.
  let nodes: NodeRow[] = [];
  {
    const { data } = await admin
      .from("index_nodes")
      .select("id, title")
      .eq("subject_id", subjectId)
      .order("depth")
      .order("position")
      .limit(400);
    nodes = (data ?? []) as NodeRow[];
  }
  if (nodeIds.length > 0) {
    const set = new Set(nodeIds);
    nodes = nodes.filter((n) => set.has(n.id));
  }
  if (nodes.length === 0) return json({ error: "no_sections" }, 409);

  // Texto original de cada sección (solo las que tienen contenido propio).
  const ids = nodes.map((n) => n.id);
  const textByNode = new Map<string, string>();
  for (let i = 0; i < ids.length; i += 100) {
    const chunk = ids.slice(i, i + 100);
    const { data: contents } = await admin
      .from("node_content")
      .select("node_id, content")
      .eq("kind", "original")
      .in("node_id", chunk);
    for (
      const c of ((contents ?? []) as Array<
        { node_id: string; content: string | null }
      >)
    ) {
      if (c.content && c.content.trim().length >= 40) {
        textByNode.set(c.node_id, c.content);
      }
    }
  }
  const sections = nodes.filter((n) => textByNode.has(n.id));
  if (sections.length === 0) return json({ error: "no_ready_documents" }, 409);

  const lang = subject.language && subject.language.length > 0
    ? `Write in this language (ISO code): ${subject.language}.`
    : "Write in the SAME language as the section.";

  const startedAt = Date.now();
  const timeBudgetMs = 95_000;
  let generated = 0;
  let reused = 0;
  let pending = 0;
  let total = 0;
  let lastError: string | null = null;

  for (const sec of sections) {
    const text = textByNode.get(sec.id)!;
    const hash = await sha256Hex(normText(text).slice(0, 100_000));

    // Guarda el hash en el nodo (para que el cliente mapee nodo -> preguntas).
    await admin
      .from("index_nodes")
      .update({ content_hash: hash })
      .eq("id", sec.id);

    // ¿Ya hay afirmaciones para este contenido (de cualquiera)?
    const { data: ex } = await admin
      .from("tf_bank")
      .select("statement")
      .eq("content_hash", hash);
    const existing = ((ex ?? []) as Array<{ statement: string }>)
      .map((r) => r.statement);
    total += existing.length;

    // Cuántas queremos para esta sección, según su longitud (más texto => más
    // afirmaciones), acotado a [10, 40]. Las T/F son más cortas que MC.
    const targetForSection = Math.min(
      40,
      Math.max(10, Math.round(text.length / 400)),
    );
    if (!force && existing.length >= targetForSection) {
      reused++;
      continue;
    }
    if (Date.now() - startedAt > timeBudgetMs) {
      pending++;
      continue;
    }
    const need = force
      ? targetForSection
      : (targetForSection - existing.length);

    const avoid = existing.length > 0
      ? "\n\nDo NOT repeat or rephrase any of these existing statements:\n" +
        existing.slice(-40).map((q) => `- ${q}`).join("\n")
      : "";
    // System prompt entrenado contra el estilo de oposiciones (banco de
    // 4000 preguntas tipo test sobre la Constitucion Espanola). Reglas:
    //   - Tono formal-juridico, no escolar.
    //   - Mezcla de TIPOS de afirmaciones: cita literal del articulo,
    //     dato cuantitativo (fechas/numeros/plazos), inferencia normativa,
    //     comparativa entre conceptos.
    //   - Distractores plausibles: la version FALSA debe cambiar un
    //     detalle especifico que un opositor mediocre pasaria por alto
    //     (cambio de articulo, plazo, mayoria, organo, fecha).
    //   - Explanation con cita al articulo/seccion concreta.
    const system =
      "You create EXAM-grade TRUE/FALSE statements for Spanish competitive " +
      "exams (\"oposiciones\") from ONE section of study material. Return " +
      "ONLY minified JSON: " +
      '{"items":[{"statement":"...","is_true":true,"explanation":"..."}]}.' +
      "\n\n" +
      "QUALITY (mandatory):\n" +
      "- Formal legal/administrative tone, NOT classroom-level. Use the " +
      "exact terminology of the source (e.g. \"Cortes Generales\", " +
      "\"mayoria absoluta\", \"ley organica\", \"refrendo\").\n" +
      "- Mix STATEMENT TYPES roughly evenly: (a) literal/paraphrased " +
      "citation of the article, (b) quantitative fact (dates, numbers, " +
      "ages, deadlines, majorities), (c) normative inference (\"X requires " +
      "Y to be valid\"), (d) comparison between concepts/articles, (e) " +
      "negative formulation (\"no podra\", \"esta prohibido\").\n" +
      "- FALSE statements must be PLAUSIBLE: change ONE specific detail an " +
      "average student would miss (wrong article number, wrong majority, " +
      "wrong deadline, wrong body/organ, swapped subject vs object). NEVER " +
      "trivial negation of an obvious truth.\n" +
      "- Each statement is unambiguous and grounded ONLY in the section " +
      "text. Do NOT invent facts beyond the source.\n" +
      "- Mix true/false roughly 50/50.\n" +
      "- `explanation` must (1) state why it's true/false in 1-2 sentences " +
      "and (2) cite the exact article/apartado from the section (e.g. " +
      "\"Articulo 99.2 establece...\", \"segun el Titulo III, Capitulo II\").\n" +
      "\n" +
      "COVERAGE:\n" +
      "- Produce up to " +
      `${need} distinct, NON-overlapping statements covering this section ` +
      "thoroughly; if the section is too short for that many, return fewer. " +
      "Cover MULTIPLE aspects of the section (not just the most obvious).\n" +
      "\n" +
      `${lang}${avoid} No commentary, no preamble, JSON ONLY.`;

    try {
      const result = await runCompletion(admin, {
        task: "tf",
        system,
        messages: [{
          role: "user",
          content: `Section: ${sec.title}\n\n${text.slice(0, 60_000)}`,
        }],
        maxOutputTokens: 8192,
        temperature: 0.5,
        userId: subject.user_id,
        subjectId: subject.id,
      });
      const seen = new Set(existing.map(normText));
      const rows: Array<Record<string, unknown>> = [];
      for (const q of parseItems(result.text)) {
        const key = normText(q.statement);
        if (key.length === 0 || seen.has(key)) continue;
        seen.add(key);
        rows.push({
          content_hash: hash,
          statement: q.statement,
          is_true: q.is_true,
          explanation: q.explanation,
          lang: subject.language,
        });
      }
      if (rows.length > 0) {
        await admin.from("tf_bank").insert(rows);
        generated += rows.length;
        total += rows.length;
      }
    } catch (e) {
      lastError = e instanceof AiGatewayError
        ? e.message
        : (e as Error).message;
    }
  }

  if (total === 0) {
    // Si todo fallo, reportamos al pipeline admin antes de devolver
    // `generic_error`. El cliente NO ve `lastError` (puede contener
    // mensajes del proveedor IA).
    const errorId = await reportError(admin, {
      userId: user.id,
      fn: "generate-tf",
      error: lastError ?? "empty_result",
      errorCode: "generation_failed",
      context: { subject_id: subject.id, node_ids: nodeIds, sections: sections.length },
      severity: "high",
    });
    return json(
      { ok: false, error_code: "generic_error", error_id: errorId },
      200,
    );
  }

  return json({
    ok: true,
    generated,
    reused,
    pending,
    total,
    sections: sections.length,
  }, 200);
}));
