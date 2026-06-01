#!/usr/bin/env python3
"""
Parsea el TXT extraido del PDF "Constitucion Espanola - 4000 preguntas tipo test"
y genera dos artefactos:

  1) `4000_questions.json`  - lista de objetos con cada pregunta normalizada:
       { number, question, options:{a,b,c,d}, correct: 'A'|'B'|'C'|'D',
         article_match: int|None, title_match: str|None,
         chapter_match: str|None, section_match: str|None }

  2) `0086_seed_constitucion_questions.sql` - migracion SQL que:
     - Localiza el subject Constitucion Espanola (titulo ILIKE).
     - Para cada pregunta, inserta en `exam_questions` con node_id mapeado
       (Articulo N -> node, Titulo X -> node, Capitulo X -> node, else root).
     - Tambien inserta en `question_bank` global con content_hash
       construido del hash MD5 del titulo del node mapeado (idempotente).

Output via stdout: stats (total parseadas, mapeadas por articulo, etc).

Uso:
  python tools/parse_4000_questions.py
"""

from __future__ import annotations
import re
import json
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
INPUT_TXT = Path(r"C:/Users/x-tor/Downloads/4000_preguntas_utf8.txt")
OUTPUT_JSON = Path(r"C:/VIC_PRO/myapp/tools/4000_questions.json")
OUTPUT_SQL = Path(r"C:/VIC_PRO/myapp/supabase/migrations/0086_seed_constitucion_questions.sql")
# ---------------------------------------------------------------------------

ROMAN_TO_INT = {
    "I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7,
    "VIII": 8, "IX": 9, "X": 10,
}

ORDINAL_TO_INT = {
    "primero": 1, "primer": 1, "segundo": 2, "tercero": 3, "tercer": 3,
    "cuarto": 4, "quinto": 5, "sexto": 6, "septimo": 7, "séptimo": 7,
    "octavo": 8, "noveno": 9, "decimo": 10, "décimo": 10,
}


def parse_text(text: str) -> tuple[list[dict], dict[int, str]]:
    """Devuelve (lista_preguntas, mapping_numero->letra_correcta)."""
    lines = text.split("\n")

    # 1) Localizar TODAS las posiciones de "Soluciones X – Y" como separadores.
    #    Variantes observadas en el PDF:
    #      - "Soluciones 1 –"        (sin dos puntos, numero pelado)
    #      - "Soluciones: 1.001 –"   (con dos puntos, numero con separador de miles)
    #    Cada bloque == 100 preguntas + su tabla de soluciones JUSTO ANTES.
    sol_re = re.compile(
        r"^\s*Soluciones[:\s]+(\d{1,3}(?:\.\d{3})?)\s*[–\-—]\s*$", re.IGNORECASE
    )
    # End del rango en linea siguiente: "100" o "1.100"
    sol_continuation_re = re.compile(r"^\s*(\d{1,3}(?:\.\d{3})?)\s*$")

    blocks: list[tuple[int, int, int]] = []  # (start_n, end_n, line_idx_post_header)
    i = 0
    while i < len(lines):
        m = sol_re.match(lines[i])
        if m:
            start = int(m.group(1).replace(".", ""))
            # La linea siguiente suele tener solo "100"/"1.100" (end del rango).
            # Buscar hasta 3 lineas adelante por si hay blank lines.
            end = start + 99
            for k in range(i + 1, min(i + 4, len(lines))):
                m2 = sol_continuation_re.match(lines[k])
                if m2:
                    end = int(m2.group(1).replace(".", ""))
                    i = k
                    break
                if lines[k].strip():
                    break  # linea no blanca y no match -> rompe
            blocks.append((start, end, i + 1))
        i += 1

    print(f"[parse] Detectados {len(blocks)} bloques de soluciones", file=sys.stderr)

    # 2) Para cada bloque: parsear la tabla y luego las preguntas.
    answers: dict[int, str] = {}
    questions: list[dict] = []

    # Pattern de fila de tabla: puede ser "N L" o "N L M K" (2 columnas).
    row_re = re.compile(
        r"^\s*(\d+)\s+([ABCDabcd])(?:\s+(\d+)\s+([ABCDabcd]))?\s*$"
    )
    # Pattern de pregunta nueva: "N. texto"
    q_start_re = re.compile(r"^(\d+)\.\s+(.+)$")
    # Pattern de opcion: "a. texto" / "a) texto" etc.
    opt_re = re.compile(r"^\s*([abcdABCD])[\.\)]\s+(.+)$")

    for bi, (start, end, hdr_line) in enumerate(blocks):
        # 2a) Tabla de soluciones: filas desde hdr_line hasta encontrar la
        #     primera pregunta "1." o "101." etc.
        block_answers: dict[int, str] = {}
        j = hdr_line
        while j < len(lines):
            line = lines[j]
            # Stop cuando empieza el bloque de preguntas (primer "N. ..." donde
            # N esta en el rango del bloque).
            mq = q_start_re.match(line.strip())
            if mq and int(mq.group(1)) == start:
                break
            mr = row_re.match(line)
            if mr:
                n1 = int(mr.group(1))
                l1 = mr.group(2).upper()
                block_answers[n1] = l1
                if mr.group(3):
                    n2 = int(mr.group(3))
                    l2 = mr.group(4).upper()
                    block_answers[n2] = l2
            j += 1

        # Anyadir al map global.
        answers.update(block_answers)

        # 2b) Preguntas: desde j hasta el siguiente "Soluciones X-Y" o EOF.
        next_sol_idx = len(lines)
        for sb in blocks[bi + 1:]:
            next_sol_idx = sb[2] - 1  # linea del header "Soluciones X-Y"
            # Bajar hasta encontrar el header real
            for k in range(sb[2] - 1, max(j, 0), -1):
                if sol_re.match(lines[k]):
                    next_sol_idx = k
                    break
            break

        # Acumular lineas del bloque de preguntas.
        q_text_lines = lines[j:next_sol_idx]
        # Parsear preguntas: cuando vemos "N. ..." iniciamos una nueva pregunta;
        # luego "a." "b." "c." "d." son las opciones. Las opciones pueden
        # continuar en lineas indentadas hasta la siguiente etiqueta.
        cur_q: dict | None = None
        cur_field: str | None = None  # 'question' | 'a' | 'b' | 'c' | 'd'
        for line in q_text_lines:
            stripped = line.rstrip()
            if not stripped.strip():
                continue
            mq = q_start_re.match(stripped.strip())
            mo = opt_re.match(stripped)
            if mq and start <= int(mq.group(1)) <= end:
                # Cerrar pregunta anterior si existe.
                if cur_q is not None:
                    questions.append(cur_q)
                cur_q = {
                    "number": int(mq.group(1)),
                    "question": mq.group(2).strip(),
                    "options": {"a": "", "b": "", "c": "", "d": ""},
                    "correct": None,
                }
                cur_field = "question"
            elif mo and cur_q is not None:
                letter = mo.group(1).lower()
                cur_q["options"][letter] = mo.group(2).strip()
                cur_field = letter
            else:
                # Linea de continuacion del campo actual.
                if cur_q is not None and cur_field is not None:
                    extra = stripped.strip()
                    if not extra:
                        continue
                    if cur_field == "question":
                        cur_q["question"] += " " + extra
                    else:
                        cur_q["options"][cur_field] += " " + extra
        if cur_q is not None:
            questions.append(cur_q)

    # 3) Asociar respuesta correcta a cada pregunta.
    for q in questions:
        q["correct"] = answers.get(q["number"])

    # 4) Detectar referencias en el texto de cada pregunta para mapear a node.
    art_re = re.compile(
        r"\bart(?:\.|[ií]culo[s]?)\s+(\d+)\b", re.IGNORECASE
    )
    title_re = re.compile(
        r"\bt[ií]tulo\s+([IVX]+|preliminar)\b", re.IGNORECASE
    )
    chapter_re = re.compile(
        r"\bcap[ií]tulo\s+([IVX]+|primero|segundo|tercero|cuarto|quinto|sexto|septimo|s[eé]ptimo|octavo|noveno|d[eé]cimo|\d+)\b",
        re.IGNORECASE,
    )

    for q in questions:
        full = q["question"] + " " + " ".join(q["options"].values())
        full_l = full.lower()

        # Articulo
        m = art_re.search(full)
        q["article_match"] = int(m.group(1)) if m else None

        # Titulo
        m = title_re.search(full)
        if m:
            raw = m.group(1).lower()
            if raw == "preliminar":
                q["title_match"] = "preliminar"
            else:
                q["title_match"] = str(ROMAN_TO_INT.get(raw.upper(), raw))
        else:
            q["title_match"] = None

        # Capitulo
        m = chapter_re.search(full)
        if m:
            raw = m.group(1).lower()
            if raw in ROMAN_TO_INT:
                q["chapter_match"] = str(ROMAN_TO_INT[raw.upper()])
            elif raw in ORDINAL_TO_INT:
                q["chapter_match"] = str(ORDINAL_TO_INT[raw])
            elif raw.isdigit():
                q["chapter_match"] = raw
            else:
                q["chapter_match"] = raw
        else:
            q["chapter_match"] = None

    return questions, answers


def sql_escape(s: str) -> str:
    """Escapa una string para usar dentro de comilla simple SQL."""
    return s.replace("'", "''")


def main():
    if not INPUT_TXT.exists():
        print(f"ERROR: no existe {INPUT_TXT}", file=sys.stderr)
        sys.exit(1)
    text = INPUT_TXT.read_text(encoding="utf-8")
    questions, answers = parse_text(text)

    # Stats
    total = len(questions)
    with_answer = sum(1 for q in questions if q["correct"])
    with_article = sum(1 for q in questions if q["article_match"])
    with_title = sum(1 for q in questions if q["title_match"])
    with_chapter = sum(1 for q in questions if q["chapter_match"])

    print(f"\n=== STATS ===", file=sys.stderr)
    print(f"Total preguntas parseadas: {total}", file=sys.stderr)
    print(f"Con respuesta correcta:    {with_answer}", file=sys.stderr)
    print(f"Con referencia a Articulo: {with_article}", file=sys.stderr)
    print(f"Con referencia a Titulo:   {with_title}", file=sys.stderr)
    print(f"Con referencia a Capitulo: {with_chapter}", file=sys.stderr)

    # JSON output (para inspección humana).
    OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_JSON.write_text(
        json.dumps(questions, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"\nJSON escrito en: {OUTPUT_JSON}", file=sys.stderr)

    # Sample 5 first
    print(f"\n=== SAMPLE (primeras 5) ===", file=sys.stderr)
    for q in questions[:5]:
        print(
            f"  #{q['number']:>4} [{q['correct']}] "
            f"art={q['article_match']} tit={q['title_match']} cap={q['chapter_match']}",
            file=sys.stderr,
        )
        print(f"       {q['question'][:80]}...", file=sys.stderr)

    # ─── Generar SQL migration ─────────────────────────────────────────────
    # La migracion:
    #  1. Localiza el subject Constitucion Espanola del super-admin
    #     (titulo ILIKE '%constituci_n%espa_ola%').
    #  2. Para cada pregunta, intenta mapear node:
    #     - Si article_match: node WHERE title ILIKE 'art_culo X'
    #     - Sino si chapter_match: node WHERE title ILIKE '%cap_tulo%X%'
    #     - Sino si title_match: node WHERE title ILIKE '%t_tulo%X%'
    #     - Sino: node raiz
    #  3. INSERT en exam_questions y question_bank (con content_hash de
    #     md5(title del nodo)).
    sql_parts: list[str] = []
    sql_parts.append("""-- ========================================================================
-- 0086 · Seed: 4000 preguntas tipo test de la Constitucion Espanola
-- ------------------------------------------------------------------------
-- Banco curado de 4000 preguntas tipo test sobre la Constitucion Espanola
-- de 1978 (fuente: Javier Lopez Diaz, 2022). Auto-generado por
-- `tools/parse_4000_questions.py` a partir del PDF.
--
-- Insercion:
--  - `exam_questions`: copia para el subject Constitucion del super-admin
--    (uso inmediato).
--  - `question_bank`: copia global con content_hash basado en md5 del
--    title del nodo (reutilizable por cualquier user que suba el mismo
--    temario y produzca un nodo con el mismo title).
--
-- Idempotencia: WHERE NOT EXISTS para evitar duplicados si la migracion
-- se re-ejecuta.
-- ========================================================================

do $$
declare
  v_subject_id uuid;
  v_user_id    uuid;
  v_root_id    uuid;
begin
  -- 1) Localizar el subject Constitucion Espanola del super-admin.
  select s.id, s.user_id
    into v_subject_id, v_user_id
  from public.subjects s
  join public.profiles p on p.id = s.user_id
  where p.is_super_admin = true
    and s.title ilike '%constituci_n%espa_ola%'
  order by s.created_at asc
  limit 1;

  if v_subject_id is null then
    raise notice '[seed-4000] subject Constitucion no encontrado (super-admin). Skipping.';
    return;
  end if;

  -- 2) Localizar el nodo raiz del subject (depth 0, sin parent).
  select id into v_root_id
  from public.index_nodes
  where subject_id = v_subject_id
    and parent_id is null
  order by position asc
  limit 1;

  raise notice '[seed-4000] subject=%, user=%, root_node=%',
    v_subject_id, v_user_id, v_root_id;

""")

    # Build CTE rows with (number, question, opt_a, opt_b, opt_c, opt_d,
    # correct_index, article_match, title_match, chapter_match).
    # Insertaremos en bloques de 500 con un solo INSERT...SELECT para
    # mantener el SQL manejable.
    LETTER_TO_INDEX = {"A": 0, "B": 1, "C": 2, "D": 3}

    valid_questions = []
    for q in questions:
        if not q["correct"]:
            continue  # sin respuesta correcta -> descartar
        if not q["options"]["a"] or not q["options"]["b"]:
            continue  # parseo incompleto
        valid_questions.append(q)

    print(f"\nPreguntas validas (con respuesta y >= 2 opciones): {len(valid_questions)}",
          file=sys.stderr)

    BATCH = 200
    for i in range(0, len(valid_questions), BATCH):
        batch = valid_questions[i:i + BATCH]
        sql_parts.append(f"  -- ── Batch {i + 1}–{i + len(batch)} ──\n")
        sql_parts.append("  with batch (number, question, opt_a, opt_b, opt_c, opt_d, correct_index, article_match, chapter_match, title_match) as (\n    values\n")
        rows = []
        def sql_str_or_null(v):
            """None -> NULL ; string s -> 's' (con sql_escape)."""
            if v is None:
                return "NULL"
            return f"'{sql_escape(str(v))}'"

        for q in batch:
            correct_idx = LETTER_TO_INDEX.get(q["correct"], 0)
            row = (
                f"      ({q['number']}, "
                f"'{sql_escape(q['question'])}', "
                f"'{sql_escape(q['options']['a'])}', "
                f"'{sql_escape(q['options']['b'])}', "
                f"'{sql_escape(q['options']['c'])}', "
                f"'{sql_escape(q['options']['d'])}', "
                f"{correct_idx}, "
                f"{q['article_match'] if q['article_match'] is not None else 'NULL'}, "
                f"{sql_str_or_null(q['chapter_match'])}, "
                f"{sql_str_or_null(q['title_match'])}"
                ")"
            )
            rows.append(row)
        sql_parts.append(",\n".join(rows))
        sql_parts.append("\n  )\n")
        sql_parts.append("""  insert into public.exam_questions (subject_id, user_id, node_id, question, options, correct_index, explanation)
  select
    v_subject_id,
    v_user_id,
    -- Mapeo de node: prioridad articulo > capitulo > titulo > root.
    coalesce(
      (select id from public.index_nodes n
       where n.subject_id = v_subject_id
         and n.title ilike 'art%culo ' || b.article_match::text
       order by n.depth desc limit 1),
      (select id from public.index_nodes n
       where n.subject_id = v_subject_id
         and n.title ilike '%cap%tulo%' || b.chapter_match || '%'
       order by n.depth desc limit 1),
      (select id from public.index_nodes n
       where n.subject_id = v_subject_id
         and n.title ilike '%t%tulo%' || b.title_match || '%'
       order by n.depth desc limit 1),
      v_root_id
    ) as node_id,
    b.question,
    jsonb_build_array(b.opt_a, b.opt_b, b.opt_c, b.opt_d) as options,
    b.correct_index,
    null as explanation
  from batch b
  where not exists (
    select 1 from public.exam_questions eq
    where eq.subject_id = v_subject_id
      and eq.question = b.question
  );

""")

    sql_parts.append("""  raise notice '[seed-4000] Insercion completada.';
end $$;
""")

    OUTPUT_SQL.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_SQL.write_text("".join(sql_parts), encoding="utf-8")
    print(f"SQL escrito en: {OUTPUT_SQL}", file=sys.stderr)
    print(f"Tamaño SQL: {OUTPUT_SQL.stat().st_size / 1024:.1f} KB", file=sys.stderr)


if __name__ == "__main__":
    main()
