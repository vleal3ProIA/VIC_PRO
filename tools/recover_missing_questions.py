#!/usr/bin/env python3
"""
Recupera las 15 preguntas missing del JSON debido a typos en el PDF
(numero de pregunta erroneo en la fuente). Estrategia:

1) Para cada numero N missing, encontrar dos preguntas que SEPAN ser:
   N-1 (la anterior, presente en JSON) y N+1 (la siguiente, presente en JSON).
2) Localizar la "pregunta typo" entre ambas en el TXT (la que NO es ni N-1
   ni N+1).
3) Asignarle como numero canonico N y como letra correcta la de la tabla.

Aplica el resultado anyadiendo las preguntas recuperadas al SQL de seed.
Genera 0086b_seed_constitucion_recovered.sql con esos 15 INSERTs.
"""

from __future__ import annotations
import json
import re
import sys
from pathlib import Path

INPUT_TXT = Path(r"C:/Users/x-tor/Downloads/4000_preguntas_utf8.txt")
INPUT_JSON = Path(r"C:/VIC_PRO/myapp/tools/4000_questions.json")
OUTPUT_SQL = Path(r"C:/VIC_PRO/myapp/supabase/migrations/0087_seed_constitucion_recovered.sql")

MISSING = [170, 380, 463, 536, 849, 1033, 1042, 1446, 1926, 2060,
           3421, 3531, 3542, 3847, 3949]

# Answers de la tabla del PDF para las missing (verificadas manualmente).
ANSWERS_FOR_MISSING = {
    # Las extraemos del verify_answers.py output: el dict answers tiene
    # las respuestas correctas. Las re-extraemos aqui.
}


def extract_answers(text: str) -> dict[int, str]:
    NUM = r"(?:\d{1,3}(?:\.\d{3})?|\d{4})"
    row_re = re.compile(
        rf"^\s*({NUM})\s+([ABCDabcd])(?:\s+({NUM})\s+([ABCDabcd]))?\s*$"
    )
    answers: dict[int, str] = {}
    for line in text.split("\n"):
        if line.strip().startswith(tuple("0123456789")) and "." in line.split()[0:1]:
            # Es pregunta, no tabla
            continue
        m = row_re.match(line)
        if not m:
            continue
        n1 = int(m.group(1).replace(".", ""))
        if 1 <= n1 <= 4000:
            answers[n1] = m.group(2).upper()
        if m.group(3):
            n2 = int(m.group(3).replace(".", ""))
            if 1 <= n2 <= 4000:
                answers[n2] = m.group(4).upper()
    return answers


def find_question_between(
    text_lines: list[str],
    json_by_num: dict[int, dict],
    target_num: int,
) -> dict | None:
    """Localiza la pregunta typo entre target_num-1 y target_num+1.

    Estrategia: buscar el bloque entre la pregunta N-1 y N+1 en el TXT,
    parsear la pregunta typo (cualquier numero) que esta en medio.
    """
    prev_q = json_by_num.get(target_num - 1)
    next_q = json_by_num.get(target_num + 1)
    if prev_q is None or next_q is None:
        return None

    # Buscar las posiciones en el TXT de prev_q y next_q.
    # prev_q.question es la cadena que empieza con "N-1. ..." en el TXT.
    prev_pattern = f"{target_num - 1}. {prev_q['question'][:50]}"
    next_pattern = f"{target_num + 1}. {next_q['question'][:50]}"

    prev_idx = -1
    next_idx = -1
    for i, line in enumerate(text_lines):
        if prev_pattern in line:
            prev_idx = i
        elif prev_idx >= 0 and next_pattern in line:
            next_idx = i
            break
    if prev_idx < 0 or next_idx < 0:
        return None

    # Buscar la pregunta typo entre prev_idx y next_idx.
    # Empieza por "N." donde N != target_num-1 y N != target_num+1.
    q_start_re = re.compile(r"^(\d+)\.\s+(.+)$")
    opt_re = re.compile(r"^\s*([abcdABCD])[\.\)]\s+(.+)$")

    cur_q = None
    cur_field = None
    for j in range(prev_idx + 1, next_idx):
        line = text_lines[j]
        stripped = line.strip()
        if not stripped:
            continue
        mq = q_start_re.match(stripped)
        mo = opt_re.match(line.rstrip())
        if mq:
            # Es el inicio de una pregunta typo (numero "raro").
            cur_q = {
                "number": target_num,  # canonico
                "typo_number": int(mq.group(1)),
                "question": mq.group(2).strip(),
                "options": {"a": "", "b": "", "c": "", "d": ""},
            }
            cur_field = "question"
        elif mo and cur_q is not None:
            letter = mo.group(1).lower()
            cur_q["options"][letter] = mo.group(2).strip()
            cur_field = letter
        else:
            if cur_q is not None and cur_field is not None:
                extra = stripped
                if cur_field == "question":
                    cur_q["question"] += " " + extra
                else:
                    cur_q["options"][cur_field] += " " + extra
    return cur_q


def sql_escape(s: str) -> str:
    return s.replace("'", "''")


def sql_str_or_null(v):
    if v is None:
        return "NULL"
    return f"'{sql_escape(str(v))}'"


def main():
    text = INPUT_TXT.read_text(encoding="utf-8")
    text_lines = text.split("\n")
    answers = extract_answers(text)
    json_data = json.loads(INPUT_JSON.read_text(encoding="utf-8"))
    json_by_num = {q["number"]: q for q in json_data}

    LETTER_TO_INDEX = {"A": 0, "B": 1, "C": 2, "D": 3}

    recovered: list[dict] = []
    failed: list[int] = []

    for n in MISSING:
        q = find_question_between(text_lines, json_by_num, n)
        if q is None or not q["options"]["a"]:
            failed.append(n)
            print(f"  FAIL: {n}", file=sys.stderr)
            continue
        correct = answers.get(n)
        if not correct:
            failed.append(n)
            continue
        q["correct"] = correct
        q["correct_index"] = LETTER_TO_INDEX.get(correct, 0)
        recovered.append(q)
        print(
            f"  OK:   {n} (typo_num={q['typo_number']}, "
            f"correct={correct}): {q['question'][:60]}...",
            file=sys.stderr,
        )

    print(f"\nRecuperadas: {len(recovered)} / {len(MISSING)}", file=sys.stderr)
    if failed:
        print(f"Fallidas: {failed}", file=sys.stderr)

    # Generar SQL migration 0087.
    sql = [f"""-- ========================================================================
-- 0087 · Seed: recuperacion de {len(recovered)} preguntas missing del 0086
-- ------------------------------------------------------------------------
-- En el PDF fuente, 15 preguntas tenian un typo en su numero de pregunta
-- (ej. "170" aparecia como "3670"). El parser principal las descarto por
-- estar fuera del rango del bloque. Aqui las recuperamos manualmente,
-- localizandolas entre las preguntas N-1 y N+1 que SI estaban en el JSON.
--
-- Estas se anyaden al subject Constitucion (mismo patron que 0086).
-- ========================================================================

do $$
declare
  v_subject_id uuid;
  v_user_id    uuid;
  v_root_id    uuid;
begin
  select s.id, s.user_id
    into v_subject_id, v_user_id
  from public.subjects s
  join public.profiles p on p.id = s.user_id
  where p.is_super_admin = true
    and s.title ilike '%constituci_n%espa_ola%'
  order by s.created_at asc
  limit 1;

  if v_subject_id is null then
    raise notice '[seed-recovered] subject Constitucion no encontrado. Skipping.';
    return;
  end if;

  select id into v_root_id
  from public.index_nodes
  where subject_id = v_subject_id and parent_id is null
  order by position asc
  limit 1;

  with batch (number, question, opt_a, opt_b, opt_c, opt_d, correct_index) as (
    values
"""]
    rows = []
    for q in recovered:
        row = (
            f"      ({q['number']}, "
            f"'{sql_escape(q['question'])}', "
            f"'{sql_escape(q['options']['a'])}', "
            f"'{sql_escape(q['options']['b'])}', "
            f"'{sql_escape(q['options']['c'])}', "
            f"'{sql_escape(q['options']['d'])}', "
            f"{q['correct_index']})"
        )
        rows.append(row)
    sql.append(",\n".join(rows))
    sql.append("""
  )
  insert into public.exam_questions (subject_id, user_id, node_id, question, options, correct_index, explanation)
  select
    v_subject_id, v_user_id, v_root_id,
    b.question,
    jsonb_build_array(b.opt_a, b.opt_b, b.opt_c, b.opt_d),
    b.correct_index,
    null
  from batch b
  where not exists (
    select 1 from public.exam_questions eq
    where eq.subject_id = v_subject_id and eq.question = b.question
  );

  raise notice '[seed-recovered] Insercion completada.';
end $$;
""")

    OUTPUT_SQL.write_text("".join(sql), encoding="utf-8")
    print(f"\nSQL escrito en: {OUTPUT_SQL}", file=sys.stderr)


if __name__ == "__main__":
    main()
