#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Clasifica las 3498 preguntas "raiz" de la Constitucion (sin
article/title/chapter_match) consultando a Groq llama-3.3-70b-versatile,
que conoce la Constitucion Espanola al detalle.

Genera:
  * tools/classified_questions.json  (cache de respuestas IA, resumible)
  * supabase/migrations/0097_reclassify_question_bank.sql
      UPDATE content_hash de las preguntas clasificadas con confidence
      HIGH a md5("Articulo N"). Las MEDIUM/LOW se quedan en la raiz para
      no introducir errores.

Uso (Windows PowerShell):
    $env:GROQ_API_KEY = "gsk_..."
    python tools/classify_with_groq.py

El script es IDEMPOTENTE: si lo interrumpes, al volver a lanzar reutiliza
classified_questions.json y continua desde donde lo dejo.

Coste estimado:
  - 3498 preguntas / 25 por lote = ~140 lotes.
  - llama-3.3-70b free tier: 1000 req/dia. Necesita ~140 -> margen amplio.
  - Tiempo: ~10-20 minutos.
"""

from __future__ import annotations
import hashlib
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path
from typing import Any

INPUT_JSON = Path(r"C:/VIC_PRO/myapp/tools/4000_questions.json")
CACHE_JSON = Path(r"C:/VIC_PRO/myapp/tools/classified_questions.json")
OUTPUT_SQL = Path(
    r"C:/VIC_PRO/myapp/supabase/migrations/0097_reclassify_question_bank.sql"
)

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL = "llama-3.3-70b-versatile"
BATCH_SIZE = 25  # Equilibrio entre tokens y throughput.
MAX_RETRIES = 3
SLEEP_BETWEEN_BATCHES_SEC = 1.0

SYSTEM_PROMPT = (
    "Eres un experto en la Constitucion Espanola de 1978 (TEXTO CONSOLIDADO, "
    "BOE-A-1978-31229). Te paso preguntas de oposicion con 4 opciones y la "
    "letra correcta. Para cada una IDENTIFICA el ARTICULO concreto (numero "
    "1-169) que regula la materia de la respuesta correcta. Si la pregunta "
    "es claramente del PREAMBULO, una DISPOSICION (adicional/transitoria/"
    "derogatoria/final) o NO se basa en un articulo unico, usa null.\n\n"
    "Devuelve SIEMPRE JSON minificado con esta forma exacta:\n"
    '{"items":[{"idx":0,"article":14,"confidence":"high"},'
    '{"idx":1,"article":null,"confidence":"low"}]}\n\n'
    "REGLAS:\n"
    " - `idx` corresponde al indice 0-based del item dentro del lote.\n"
    " - `article` es entero 1..169 o null.\n"
    " - `confidence`: 'high' si tienes certeza absoluta del articulo; "
    "'medium' si crees pero podria ser otro; 'low' si dudas o es transversal.\n"
    " - NO incluyas explicaciones, solo el JSON.\n"
)


def md5(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def sql_escape(s: str) -> str:
    return s.replace("'", "''")


def is_root_question(q: dict) -> bool:
    """Pregunta sin referencia a Articulo / Titulo / Capitulo (raiz)."""
    return (
        not q.get("article_match")
        and not q.get("title_match")
        and not q.get("chapter_match")
    )


def build_user_msg(batch: list[dict]) -> str:
    parts = ["Lote de preguntas:\n"]
    for i, q in enumerate(batch):
        opts = q["options"]
        parts.append(
            f"\n[idx={i}] Correcta: {q['correct']}\n"
            f"P: {q['question']}\n"
            f"  A) {opts.get('a','')}\n"
            f"  B) {opts.get('b','')}\n"
            f"  C) {opts.get('c','')}\n"
            f"  D) {opts.get('d','')}\n"
        )
    parts.append("\nDevuelve solo el JSON.")
    return "".join(parts)


def call_groq(api_key: str, user_msg: str) -> str:
    body = json.dumps({
        "model": GROQ_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_msg},
        ],
        "temperature": 0.0,
        "max_tokens": 2048,
        "response_format": {"type": "json_object"},
    }).encode("utf-8")
    req = urllib.request.Request(
        GROQ_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data["choices"][0]["message"]["content"]


def parse_response(text: str) -> list[dict]:
    """Extrae items del JSON devuelto. Resistente a basura alrededor."""
    # Buscar el primer { y el ultimo } por seguridad.
    m = re.search(r"\{.*\}", text, re.DOTALL)
    raw = m.group(0) if m else text
    obj = json.loads(raw)
    items = obj.get("items", [])
    out = []
    for it in items:
        if not isinstance(it, dict):
            continue
        idx = it.get("idx")
        art = it.get("article")
        conf = it.get("confidence", "low")
        if not isinstance(idx, int):
            continue
        if art is not None:
            try:
                art = int(art)
            except (TypeError, ValueError):
                art = None
            if art is not None and not (1 <= art <= 169):
                art = None
        out.append({"idx": idx, "article": art, "confidence": conf})
    return out


def call_with_retries(api_key: str, batch: list[dict]) -> list[dict]:
    last_err: Exception | None = None
    for attempt in range(MAX_RETRIES):
        try:
            text = call_groq(api_key, build_user_msg(batch))
            return parse_response(text)
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code == 429:
                wait = 5 * (attempt + 1)
                print(f"  rate limit, esperando {wait}s...", file=sys.stderr)
                time.sleep(wait)
            else:
                time.sleep(2 ** attempt)
        except Exception as e:
            last_err = e
            time.sleep(2 ** attempt)
    raise RuntimeError(f"Groq fallo tras {MAX_RETRIES} intentos: {last_err}")


def main() -> None:
    api_key = os.environ.get("GROQ_API_KEY", "").strip()
    if not api_key:
        print(
            "ERROR: define la variable de entorno GROQ_API_KEY con tu key de "
            "Groq (https://console.groq.com/keys) antes de ejecutar.",
            file=sys.stderr,
        )
        sys.exit(2)

    data = json.loads(INPUT_JSON.read_text(encoding="utf-8"))
    root = [q for q in data if is_root_question(q)]
    print(f"Preguntas raiz a clasificar: {len(root)}")

    # Cache resumible: { "<question_text>": {"article": int|null,
    # "confidence": "high|medium|low"} }
    cache: dict[str, dict[str, Any]] = {}
    if CACHE_JSON.exists():
        try:
            cache = json.loads(CACHE_JSON.read_text(encoding="utf-8"))
            print(f"Cache previo: {len(cache)} entradas reutilizables")
        except Exception:
            cache = {}

    pending = [q for q in root if q["question"] not in cache]
    print(f"Pendientes: {len(pending)}")

    n_batches = (len(pending) + BATCH_SIZE - 1) // BATCH_SIZE
    for bi in range(0, len(pending), BATCH_SIZE):
        batch = pending[bi: bi + BATCH_SIZE]
        idx_n = bi // BATCH_SIZE + 1
        print(f"Lote {idx_n}/{n_batches} ({len(batch)} items)...", flush=True)
        try:
            answers = call_with_retries(api_key, batch)
        except Exception as e:
            print(f"  ERROR irrecuperable: {e}", file=sys.stderr)
            # Persistir lo que tengamos.
            CACHE_JSON.write_text(
                json.dumps(cache, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            sys.exit(3)

        by_idx = {a["idx"]: a for a in answers}
        for i, q in enumerate(batch):
            a = by_idx.get(i)
            if a is None:
                cache[q["question"]] = {"article": None, "confidence": "low"}
                continue
            cache[q["question"]] = {
                "article": a.get("article"),
                "confidence": a.get("confidence", "low"),
            }
        # Persistir tras cada lote (idempotencia).
        CACHE_JSON.write_text(
            json.dumps(cache, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        time.sleep(SLEEP_BETWEEN_BATCHES_SEC)

    # Stats finales y generacion de SQL.
    print("\n=== Stats clasificacion ===")
    high = sum(1 for v in cache.values() if v["confidence"] == "high"
               and v["article"] is not None)
    medium = sum(1 for v in cache.values() if v["confidence"] == "medium"
                 and v["article"] is not None)
    low = sum(1 for v in cache.values() if v["confidence"] == "low"
              or v["article"] is None)
    print(f"  HIGH (re-clasificables):   {high}")
    print(f"  MEDIUM (revisar manual):   {medium}")
    print(f"  LOW / null (en raiz):      {low}")

    # Distribucion por articulo (solo HIGH).
    from collections import Counter
    art_counts: Counter = Counter()
    for v in cache.values():
        if v["confidence"] == "high" and v["article"] is not None:
            art_counts[v["article"]] += 1
    print(f"\n  Top 10 articulos asignados:")
    for art, c in art_counts.most_common(10):
        print(f"    Art {art}: +{c}")

    # ---- Generar SQL ----
    print(f"\nGenerando {OUTPUT_SQL.name}...")
    lines = ["""-- ========================================================================
-- 0097 · Re-clasificar 3498 preguntas "raiz" via Groq llama-3.3-70b
-- ------------------------------------------------------------------------
-- El parser original del PDF solo detectaba 'Art X' literal en el texto:
-- 87.8% de las preguntas (3498) quedaron en la raiz porque no citan
-- articulo, aunque semanticamente SI pertenezcan a un articulo concreto.
--
-- Este SQL aplica los UPDATES generados por Groq (solo confidence='high')
-- para mover esas preguntas al nodo Articulo N correcto, de forma que al
-- fallar una pregunta el usuario pueda navegar al sitio del temario donde
-- se explica.
-- ========================================================================

do $$
declare
  v_subject_id uuid := '942f19b7-e60c-4e58-bde4-629ded718b96';
  v_updated int := 0;
  v_inserted_temp int;
begin
  -- Tabla temporal con (identity_hash, target_hash) para hacer un UPDATE
  -- masivo por md5(texto normalizado) sin importar variaciones de spacing.
  create temporary table tmp_classify (
    identity_hash text not null,
    target_hash   text not null
  ) on commit drop;

  insert into tmp_classify (identity_hash, target_hash) values
"""]

    rows: list[tuple[str, str]] = []
    norm_re = re.compile(r"\s+")
    for q_text, info in cache.items():
        if info["confidence"] != "high" or info["article"] is None:
            continue
        identity = md5(norm_re.sub(" ", q_text.strip()))
        target = md5(f"Artículo {info['article']}")
        rows.append((identity, target))

    if not rows:
        lines.append("    ('00000000000000000000000000000000', '00000000000000000000000000000000')\n")
        lines.append("  ;\n  -- (sin filas a actualizar)\n")
    else:
        lines.append(
            ",\n".join(f"    ('{i}', '{t}')" for i, t in rows)
        )
        lines.append("\n  ;\n")

    lines.append("""
  get diagnostics v_inserted_temp = row_count;
  raise notice '[0097] entradas a clasificar: %', v_inserted_temp;

  update public.question_bank qb
  set content_hash = t.target_hash
  from tmp_classify t
  where md5(regexp_replace(trim(qb.question), '\\s+', ' ', 'g'))
        = t.identity_hash
    and qb.content_hash <> t.target_hash;
  get diagnostics v_updated = row_count;
  raise notice '[0097] question_bank rows updated: %', v_updated;
end $$;
""")
    OUTPUT_SQL.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_SQL.write_text("".join(lines), encoding="utf-8")
    print(f"SQL escrito: {OUTPUT_SQL}")
    print(f"Tamano: {OUTPUT_SQL.stat().st_size / 1024:.1f} KB")
    print(f"Filas update propuestas: {len(rows)}")


if __name__ == "__main__":
    main()
