// ============================================================================
// Edge Function: generate-flashcards · Tarjetas de estudio (Fase 3)
// ----------------------------------------------------------------------------
// Genera N flashcards (pregunta/respuesta) de un temario o de una sección del
// índice. Usa el TEXTO ya disponible (el 'original' guardado del nodo, o el
// texto completo del temario; visión del PDF solo como último recurso) para que
// cualquier proveedor del gateway pueda generarlas.
//
// Reemplaza el lote anterior del mismo ámbito (subject + node) para no acumular
// duplicados al regenerar. Síncrono: la UI espera con spinner.
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

interface Card {
  front?: unknown;
  back?: unknown;
}

/// Extrae {cards:[{front,back}]} tolerando fences y texto alrededor.
function parseCards(text: string): Array<{ front: string; back: string }> {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    const obj = JSON.parse(t) as { cards?: unknown };
    const arr = Array.isArray(obj.cards) ? obj.cards as Card[] : [];
    const out: Array<{ front: string; back: string }> = [];
    for (const c of arr) {
      if (
        c && typeof c.front === "string" && typeof c.back === "string" &&
        c.front.trim().length > 0 && c.back.trim().length > 0
      ) {
        out.push({
          front: (c.front as string).slice(0, 500).trim(),
          back: (c.back as string).slice(0, 1500).trim(),
        });
      }
    }
    return out;
  } catch {
    return [];
  }
}

interface NodeRow {
  id: string;
  subject_id: string;
  user_id: string;
}

Deno.serve(withSentry("generate-flashcards", async (req) => {
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
  const nodeId = typeof body?.node_id === "string" ? body.node_id : null;
  const count = Math.max(
    4,
    Math.min(30, typeof body?.count === "number" ? body.count : 12),
  );
  if (typeof subjectId !== "string") {
    return json({ error: "missing_subject_id" }, 400);
  }

  // Propiedad del temario.
  const { data: subj } = await admin
    .from("subjects")
    .select("id, user_id, language")
    .eq("id", subjectId)
    .maybeSingle();
  if (!subj) return json({ error: "subject_not_found" }, 404);
  const subject = subj as { id: string; user_id: string; language: string | null };
  if (subject.user_id !== user.id) return json({ error: "forbidden" }, 403);

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `generate-flashcards:${user.id}`,
    limit: 20,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // Material: preferimos el texto de la sección (si hay node), luego el texto
  // completo del temario; visión del PDF como último recurso.
  let textContext = "";
  let attachments: AiAttachment[] = [];
  if (nodeId) {
    const { data: nodeRow } = await admin
      .from("index_nodes")
      .select("id, subject_id, user_id")
      .eq("id", nodeId)
      .maybeSingle();
    const node = nodeRow as NodeRow | null;
    if (node && node.user_id === user.id) {
      const { data: orig } = await admin
        .from("node_content")
        .select("content")
        .eq("node_id", node.id)
        .eq("kind", "original")
        .maybeSingle();
      textContext =
        ((orig as { content: string | null } | null)?.content ?? "").trim();
    }
  }
  if (textContext.length < 20) {
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

  const lang = subject.language && subject.language.length > 0
    ? `Write the cards in this language (ISO code): ${subject.language}.`
    : "Write the cards in the SAME language as the material.";
  const system =
    "You create study flashcards from the provided material. Return ONLY " +
    'minified JSON: {"cards":[{"front":"...","back":"..."}]}. Each `front` is ' +
    "a concise question or term; each `back` is a clear, correct and complete " +
    "answer/definition grounded ONLY in the material (do not invent). Cover the " +
    `most important facts, definitions and rules. Produce about ${count} cards. ` +
    `${lang} No commentary.`;

  try {
    const result = await runCompletion(admin, {
      task: "flashcards",
      system,
      messages: [{
        role: "user",
        content: textContext
          ? "Material:\n\n" + textContext
          : "Use the attached document(s).",
      }],
      attachments: attachments.length > 0 ? attachments : undefined,
      maxOutputTokens: 4096,
      temperature: 0.3,
      userId: subject.user_id,
      subjectId: subject.id,
    });

    const cards = parseCards(result.text);
    if (cards.length === 0) {
      return json({ ok: false, error: "empty_result" }, 200);
    }

    // Reemplaza el lote anterior del mismo ámbito (subject + node).
    let del = admin.from("flashcards").delete().eq("subject_id", subject.id);
    del = nodeId ? del.eq("node_id", nodeId) : del.is("node_id", null);
    await del;

    const rows = cards.map((c) => ({
      subject_id: subject.id,
      user_id: subject.user_id,
      node_id: nodeId,
      front: c.front,
      back: c.back,
    }));
    await admin.from("flashcards").insert(rows);

    return json({ ok: true, count: rows.length }, 200);
  } catch (e) {
    const detail = e instanceof AiGatewayError
      ? e.message
      : (e as Error).message;
    return json({ ok: false, error: "generation_failed", detail }, 200);
  }
}));
