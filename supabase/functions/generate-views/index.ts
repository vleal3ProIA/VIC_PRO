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
    ? `Write the output in this language (ISO code): ${language}.`
    : "Write in the SAME language as the material.";
  switch (kind) {
    case "original":
      // ABSOLUTE SCOPE RULE: el modelo recibe el material entero y debe
      // extraer SOLO la seccion pedida. Sin esta regla, un title como
      // "Articulo 10" puede provocar que extraiga 100, 101, 102, etc. por
      // prefijo numerico.
      return [
        "You extract content from study material. Return, verbatim and " +
        "complete, only the text of the REQUESTED section (keep its headings " +
        "and structure). Do not summarize, do not add commentary.",
        "",
        "ABSOLUTE SCOPE RULE -- EXACT TITLE MATCH:",
        "- The user gives you ONE section title between >>> <<< delimiters.",
        "- Extract ONLY that exact section. NEVER include sibling sections.",
        "- Numbers are EXACT NUMERIC MATCHES, NOT prefixes. If the title is " +
        "\"Articulo 10\", you extract ONLY Articulo 10 -- NEVER Articulo 100, " +
        "101, 102, 103, 104, 105, 106, 107, 108, 109. If the title is " +
        "\"Articulo 4\", you extract ONLY Articulo 4 -- NEVER Articulo 40, 41, 42, etc.",
        "- If the material contains additional sections beyond the requested " +
        "one, IGNORE them completely.",
        "- Return the section's text from its heading to JUST BEFORE the next " +
        "heading of the same or higher level.",
      ].join("\n");

    case "explained":
      // System prompt entrenado contra el PDF "Constitucion Espanola - Lectura
      // Facil" (Univ. Rey Juan Carlos + Fundacion Esfera). Reglas:
      //   - frases cortas (1 idea por frase).
      //   - vocabulario sencillo + explicacion inline con "es decir,..."
      //     "porque...", "que es...", "que significa..."
      //   - structural roman/ordinal (Titulo, Capitulo, Seccion) -> ANYadir
      //     "se lee primero/tercero/..." despues del numeral.
      //   - preservar TODA la estructura (articulos, apartados, sub-apartados).
      //   - glosario para conceptos clave via blockquote Markdown.
      //   - NO inventar, NO opinar.
      return [
        "You are an expert tutor who transforms study material into an " +
        "EASY-READING version (\"lectura facil\"), so ANY reader -- including " +
        "people with reading difficulties or second-language learners -- can " +
        "understand it with no prior knowledge.",
        "",
        "STYLE -- mandatory:",
        "1. Short sentences. ONE idea per sentence. Active voice, present tense.",
        "2. Common, everyday vocabulary.",
        "3. The FIRST time a technical term, foreign word, abbreviation, " +
        "Latinism, or legal/specialist concept appears, EXPLAIN IT INLINE " +
        "right after, using one of these connectors: \"es decir, ...\", " +
        "\"porque ...\", \"que es ...\", \"que significa ...\" (or the " +
        "exact equivalent in the target language). Example (Spanish): " +
        "\"ratificado, es decir, ha validado\". Example (Spanish): " +
        "\"ideologia, es decir, cada partido tiene su propio conjunto de ideas\".",
        "4. For STRUCTURAL Roman or ordinal numerals attached to top-level " +
        "items (Titulo, Capitulo, Seccion -- NOT individual Articulo numbers), " +
        "APPEND how to read them aloud right after the numeral. Examples: " +
        "\"Titulo III se lee tercero\", \"Capitulo primero\", \"Seccion 1.a " +
        "se lee primera\".",
        "5. Bullet lists with \"-\" for enumerations. Numbered lists when the " +
        "original uses numbering (1., 2., 3., a), b), c)).",
        "6. **Bold** key concepts on FIRST appearance. *Italic* for foreign " +
        "terms.",
        "7. For glossary-worthy concepts (e.g. \"ordenamiento juridico\", " +
        "\"soberania\", \"mayoria absoluta\", \"extradicion\"), add a Markdown " +
        "blockquote \"> ...\" immediately after the first mention with a " +
        "short, neutral, general-knowledge definition.",
        "8. Use connectors that explain the WHY: \"...porque ...\", " +
        "\"...para que ...\", \"...con el objetivo de ...\".",
        "",
        "STRUCTURE -- mandatory:",
        "1. PRESERVE the section structure EXACTLY: same articles, same " +
        "numbering of apartados (1., 2., 3.) and sub-apartados (a, b, c). " +
        "DO NOT skip any apartado.",
        "2. Use \"## Articulo X\" headings per article and \"### Capitulo ...\" " +
        "for chapters.",
        "3. If the section opens with a structural element (Titulo, Capitulo, " +
        "Seccion), start with a 1-2-line intro explaining what that element is.",
        "",
        "FAITHFULNESS -- hard constraints:",
        "- Do NOT invent facts, do NOT add opinions or commentary.",
        "- Do NOT add information that is not in the source. The goal is to " +
        "REPHRASE for clarity, not extend.",
        "- Inline definitions of generic terms come from neutral general " +
        "knowledge.",
        "- If the source is ambiguous, keep the ambiguity.",
        "",
        "ABSOLUTE SCOPE RULE -- EXACT TITLE MATCH:",
        "- The user gives you ONE section title between >>> <<< delimiters.",
        "- Generate the explained view for THAT ONE SECTION ONLY. NEVER " +
        "include sibling sections in the same response.",
        "- Numbers are EXACT NUMERIC MATCHES, NOT prefixes. If the title is " +
        "\"Articulo 10\", you produce ONLY Articulo 10 -- NEVER Articulo 100, " +
        "101, 102, 103, 104, 105, 106, 107, 108, 109. If the title is " +
        "\"Articulo 4\", you produce ONLY Articulo 4 -- NEVER 40, 41, 42, etc.",
        "- If the material contains additional sections beyond the requested " +
        "one, IGNORE them.",
        "- DO NOT generate multiple consecutive sections in one response.",
        "",
        `OUTPUT: Markdown only. No preamble. No closing remarks. ${lang}`,
      ].join("\n");

    case "summary":
      // Resumen en estilo "lectura facil": ESENCIA del articulo en bullets
      // cortos, vocabulario sencillo, inline definitions cuando haga falta.
      return [
        "You produce an EASY-READING summary of the requested section.",
        "",
        "STYLE -- mandatory:",
        "- Short sentences. One idea per bullet.",
        "- Common, everyday vocabulary.",
        "- The FIRST time a technical term appears, explain it INLINE with " +
        "\"es decir, ...\" / \"que es ...\" (or the equivalent in the target " +
        "language).",
        "- Bullet list with \"-\". 5-12 bullets max.",
        "- Keep ONLY the essential points. No commentary, no opinions.",
        "",
        "FAITHFULNESS:",
        "- Faithful to the source. Do not invent.",
        "- Preserve the apartado numbering if the source has it (1., 2., 3.).",
        "",
        "ABSOLUTE SCOPE RULE -- EXACT TITLE MATCH:",
        "- The user gives you ONE section title between >>> <<< delimiters.",
        "- Summarize ONLY that section. Numbers are EXACT NUMERIC MATCHES. " +
        "If the title is \"Articulo 10\", summarize ONLY Articulo 10 -- " +
        "NEVER 100, 101, 102, etc. If the title is \"Articulo 4\", summarize " +
        "ONLY Articulo 4 -- NEVER 40, 41, 42.",
        "- Do NOT summarize multiple sections in one response.",
        "",
        `OUTPUT: Markdown only. No preamble. ${lang}`,
      ].join("\n");

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
    // Destacamos el title con delimitadores >>> <<< para que el modelo lo
    // identifique sin ambiguedad. Sin esto, "Articulo 10" se puede confundir
    // con "Articulo 100" si el material contiene ambos.
    const userMsgWithMaterial =
      `Generate the view for THIS SECTION ONLY, with EXACT title match:\n\n` +
      `>>> ${node.title} <<<\n\n` +
      `CRITICAL: Generate content for the EXACT title above. Do NOT include ` +
      `sibling sections in the same response. Numbers are EXACT NUMERIC ` +
      `MATCHES (not prefixes). If the title is "Articulo 10", produce ONLY ` +
      `Articulo 10 -- not 100, 101, 102, etc.\n\n` +
      `Material (may contain other sections; IGNORE them):\n\n${textContext}`;
    const userMsgAttachments =
      `Generate the view for THIS SECTION ONLY, with EXACT title match:\n\n` +
      `>>> ${node.title} <<<\n\n` +
      `CRITICAL: Generate content for the EXACT title above. Do NOT include ` +
      `sibling sections. Numbers are EXACT NUMERIC MATCHES (not prefixes). ` +
      `Use the attached document(s); ignore any section that is not the one ` +
      `requested.`;
    const result = await runCompletion(admin, {
      task: `view:${k}`,
      system: systemFor(k, language),
      messages: [{
        role: "user",
        content: textContext ? userMsgWithMaterial : userMsgAttachments,
      }],
      attachments: attachments.length > 0 ? attachments : undefined,
      maxOutputTokens: k === "summary" ? 2048 : 8192,
      temperature: k === "original" ? 0 : 0.3,
      userId: node.user_id,
      subjectId: node.subject_id,
    });

    // Defensa: el modelo (o el gateway) puede devolver string vacia (refusal,
    // safety filter, parsing fallido, etc.). Si guardamos vacio, la cache
    // queda envenenada: las siguientes peticiones devuelven "" sin reintentar.
    // Mejor lanzar error explicito para que la UI lo muestre y el siguiente
    // intento regenere.
    const generatedText = (result.text ?? "").trim();
    if (generatedText.length === 0) {
      throw new AiGatewayError(
        `Model returned empty content for ${k} of "${node.title}". ` +
        `The section may not be present in the material, or the AI provider ` +
        `refused. Try regenerating, or check the material.`,
      );
    }

    await admin.from("node_content").upsert({
      node_id: node.id,
      user_id: node.user_id,
      kind: k,
      content: result.text,
    }, { onConflict: "node_id,kind" });

    // 3) Aportar a la biblioteca global si el material es libre.
    if (sectionHash && shareable && k !== "original") {
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
