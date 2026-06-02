#!/usr/bin/env python3
"""
Regenera question_bank completamente para la Constitucion:
  1. DELETE de las preguntas actuales que correspondan a Constitucion (por
     hash del texto normalizado).
  2. INSERT de las 3985 desde el JSON con content_hash CORRECTO segun el
     article_match/title_match/chapter_match que tenian al parsear.

Esto reemplaza 0092/0093/0094 con datos limpios y consistentes.
"""

from __future__ import annotations
import json
import hashlib
import re
from pathlib import Path

INPUT_JSON = Path(r"C:/VIC_PRO/myapp/tools/4000_questions.json")
OUTPUT_SQL = Path(r"C:/VIC_PRO/myapp/supabase/migrations/0095_regenerate_question_bank.sql")

ROMAN_MAP = {"1":"I","2":"II","3":"III","4":"IV","5":"V","6":"VI","7":"VII","8":"VIII","9":"IX","10":"X"}


def md5_hex(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def sql_escape(s: str) -> str:
    return s.replace("'", "''")


def normalize(s: str) -> str:
    """Normaliza para match: trim + collapse whitespace."""
    return re.sub(r"\s+", " ", s.strip())


def main():
    data = json.loads(INPUT_JSON.read_text(encoding="utf-8"))

    LETTER_TO_INDEX = {"A": 0, "B": 1, "C": 2, "D": 3}
    rows = []
    for q in data:
        if not q["correct"] or not q["options"]["a"]:
            continue
        # content_hash destino
        if q.get("article_match"):
            label = f"Artículo {q['article_match']}"
        elif q.get("chapter_match"):
            raw = q["chapter_match"].lower()
            if raw in ("i","ii","iii","iv","v","vi","vii","viii","ix","x"):
                label = f"CAPÍTULO {raw.upper()}"
            else:
                label = "Constitución Española"
        elif q.get("title_match"):
            raw = q["title_match"]
            if raw == "preliminar":
                label = "TÍTULO PRELIMINAR"
            elif raw in ROMAN_MAP:
                label = f"TÍTULO {ROMAN_MAP[raw]}"
            else:
                label = "Constitución Española"
        else:
            label = "Constitución Española"

        target_hash = md5_hex(label)
        identity_hash = md5_hex(normalize(q["question"]))
        rows.append({
            "question": q["question"],
            "options": q["options"],
            "correct_index": LETTER_TO_INDEX.get(q["correct"], 0),
            "content_hash": target_hash,
            "identity_hash": identity_hash,
        })

    print(f"Preguntas a insertar: {len(rows)}")
    by_label = {}
    for r in rows:
        # We don't store label directly; recompute for stats
        pass

    parts = ["""-- ========================================================================
-- 0095 · Regenerar question_bank de la Constitucion (limpieza definitiva)
-- ------------------------------------------------------------------------
-- Borra las preguntas del banco que correspondan a la Constitucion
-- (matching por md5(texto normalizado)) y las re-inserta desde el JSON
-- original con content_hash correcto segun article_match/title_match/
-- chapter_match.
--
-- Las preguntas "originales" del banco (96 generadas por IA previa) NO
-- se tocan porque su hash de identidad no coincide con ninguna del JSON.
-- ========================================================================

do $$
declare
  v_subject_id uuid := '942f19b7-e60c-4e58-bde4-629ded718b96';
  v_deleted int;
  v_inserted int;
begin
  -- 1) Borrar las que coinciden por identity hash.
  -- identity_hash = md5(regexp_replace(trim(question), '\\s+', ' ', 'g'))
  with target_hashes (h) as (values
"""]
    # Group identity hashes
    seen_identity = set()
    unique_rows = []
    for r in rows:
        if r["identity_hash"] in seen_identity:
            continue
        seen_identity.add(r["identity_hash"])
        unique_rows.append(r)

    parts.append(",\n".join(f"    ('{r['identity_hash']}')" for r in unique_rows))
    parts.append("\n  )\n  delete from public.question_bank\n")
    parts.append("  where md5(regexp_replace(trim(question), '\\s+', ' ', 'g'))\n")
    parts.append("    in (select h from target_hashes);\n\n")
    parts.append("  get diagnostics v_deleted = row_count;\n")
    parts.append("  raise notice '[0095] preguntas borradas: %', v_deleted;\n\n")

    # 2) INSERT en batches
    parts.append("  -- 2) INSERT las 3985 con content_hash correcto.\n")
    BATCH = 200
    for i in range(0, len(unique_rows), BATCH):
        batch = unique_rows[i:i + BATCH]
        parts.append(f"  -- Batch {i+1}-{i+len(batch)}\n")
        parts.append("  insert into public.question_bank (content_hash, question, options, correct_index, lang)\n  values\n")
        items = []
        for r in batch:
            q_esc = sql_escape(r["question"])
            opts_json = json.dumps(
                [r["options"]["a"], r["options"]["b"], r["options"]["c"], r["options"]["d"]],
                ensure_ascii=False,
            )
            opts_esc = sql_escape(opts_json)
            items.append(
                f"    ('{r['content_hash']}', '{q_esc}', '{opts_esc}'::jsonb, {r['correct_index']}, 'es')"
            )
        parts.append(",\n".join(items))
        parts.append(";\n\n")

    parts.append("  raise notice '[0095] preguntas insertadas: %', " + str(len(unique_rows)) + ";\nend $$;\n")

    OUTPUT_SQL.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_SQL.write_text("".join(parts), encoding="utf-8")
    print(f"\nSQL escrito en: {OUTPUT_SQL}")
    print(f"Tamano: {OUTPUT_SQL.stat().st_size / 1024:.1f} KB")
    print(f"Preguntas unicas: {len(unique_rows)}")


if __name__ == "__main__":
    main()
