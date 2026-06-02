#!/usr/bin/env python3
"""
Re-asigna content_hash a las preguntas en question_bank basandose en el
JSON original que tiene el article_match correcto (extraido al parsear
el PDF de 4000 preguntas).

Algoritmo:
  1. Lee `tools/4000_questions.json` (3985 preguntas con article/title/chapter
     match correctos).
  2. Por cada pregunta, calcular el content_hash CORRECTO:
       - Si article_match: md5("Artículo N")
       - Sino si title_match: md5("TÍTULO X") - normalizar a roman.
       - Sino si chapter_match: md5("CAPÍTULO ...")
       - Sino: md5("Constitución Española") (raiz)
  3. Generar UPDATE SQL que para cada pregunta del banco actualice su
     content_hash al correcto, identificando por el TEXTO de la pregunta
     (que es identico).
"""

from __future__ import annotations
import json
import hashlib
from pathlib import Path

INPUT_JSON = Path(r"C:/VIC_PRO/myapp/tools/4000_questions.json")
OUTPUT_SQL = Path(r"C:/VIC_PRO/myapp/supabase/migrations/0092_fix_question_bank_hashes.sql")

ROMAN_MAP = {
    "1": "I", "2": "II", "3": "III", "4": "IV", "5": "V",
    "6": "VI", "7": "VII", "8": "VIII", "9": "IX", "10": "X",
}


def md5_hex(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def sql_escape(s: str) -> str:
    return s.replace("'", "''")


def main():
    data = json.loads(INPUT_JSON.read_text(encoding="utf-8"))
    # Construir mapping: pregunta_text -> content_hash correcto.
    mapping: list[tuple[str, str, str]] = []  # (question, label, hash)
    for q in data:
        label = None
        if q.get("article_match"):
            label = f"Artículo {q['article_match']}"
        elif q.get("chapter_match"):
            # Capitulo: convertir a "CAPÍTULO X"
            raw = q["chapter_match"]
            # Si es un romano i, ii, iii -> upper
            if raw.lower() in ("i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"):
                label = f"CAPÍTULO {raw.upper()}"
            else:
                label = None  # no podemos mapear nombrado
        elif q.get("title_match"):
            raw = q["title_match"]
            if raw == "preliminar":
                label = "TÍTULO PRELIMINAR"
            elif raw in ROMAN_MAP:
                label = f"TÍTULO {ROMAN_MAP[raw]}"
            else:
                label = None
        # Default: nodo raíz
        if label is None:
            label = "Constitución Española"
        target_hash = md5_hex(label)
        mapping.append((q["question"], label, target_hash))

    print(f"Preguntas mapeadas: {len(mapping)}")
    # Stats
    by_target = {}
    for _, label, _ in mapping:
        by_target[label] = by_target.get(label, 0) + 1
    print("\nPor destino:")
    for label, count in sorted(by_target.items(), key=lambda x: -x[1])[:15]:
        print(f"  {count:5}  {label}")

    # Generar SQL: usar VALUES + UPDATE.
    parts = ["""-- ========================================================================
-- 0092 · Reasignar content_hash en question_bank con article_match correcto
-- ------------------------------------------------------------------------
-- Las 3985 preguntas en question_bank tenian content_hash basado en
-- md5(content del nodo viejo). Ese subject ya no existe, y los nodos
-- del nuevo subject usan md5(title), por lo que muchas preguntas quedaron
-- huerfanas (Art 2-9 con 0 preguntas, etc).
--
-- Este SQL re-asigna content_hash a md5(title del nodo destino) usando
-- el article_match / title_match / chapter_match que detectamos al
-- parsear el PDF original (4000_questions.json).
--
-- IDENTIFICACION: por TEXTO de la pregunta (es identico al insertado).
-- ========================================================================

do $$
declare
  v_updated int := 0;
  v_total int;
begin
"""]

    parts.append("  -- Limpiar previo update destructivo: restaurar al raíz primero.\n")
    parts.append(f"  update public.question_bank set content_hash = '{md5_hex('Constitución Española')}'\n")
    parts.append(f"  where content_hash != '{md5_hex('Constitución Española')}'\n")
    parts.append("    and not exists (\n")
    parts.append("      select 1 from public.index_nodes n\n")
    parts.append("      where n.content_hash = question_bank.content_hash\n")
    parts.append("    );\n\n")
    parts.append("  raise notice '[0092] preguntas huerfanas movidas a raíz';\n\n")

    parts.append("  -- Re-asignar content_hash en batches de 500.\n")

    BATCH = 200
    for i in range(0, len(mapping), BATCH):
        batch = mapping[i:i + BATCH]
        parts.append(f"  -- Batch {i + 1}-{i + len(batch)}\n")
        parts.append("  with mapped (q, h) as (values\n")
        rows = []
        for question, label, target_hash in batch:
            q_esc = sql_escape(question)
            rows.append(f"    ('{q_esc}', '{target_hash}')")
        parts.append(",\n".join(rows))
        parts.append("\n  )\n")
        parts.append("  update public.question_bank qb\n")
        parts.append("  set content_hash = m.h\n")
        parts.append("  from mapped m\n")
        parts.append("  where qb.question = m.q\n")
        parts.append("    and qb.content_hash != m.h;\n\n")

    parts.append("  raise notice '[0092] content_hash re-asignados';\nend $$;\n")

    OUTPUT_SQL.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_SQL.write_text("".join(parts), encoding="utf-8")
    print(f"\nSQL escrito en: {OUTPUT_SQL}")
    print(f"Tamano: {OUTPUT_SQL.stat().st_size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
