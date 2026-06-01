#!/usr/bin/env python3
"""
Verifica que las respuestas correctas asignadas a cada pregunta en el JSON
coinciden EXACTAMENTE con las tablas de soluciones del PDF original.

Estrategia: re-parsea SOLO las tablas (no las preguntas) de forma
independiente al parser principal, construye un dict {N: letra}, y lo
cruza contra el JSON. Reporta:
  - Preguntas con respuesta INCORRECTA (mismatch).
  - Preguntas en JSON con respuesta NULL.
  - Numeros de la tabla NO presentes en el JSON.
  - Numeros del JSON NO presentes en la tabla.

Uso:
  python tools/verify_answers.py
"""

from __future__ import annotations
import re
import json
import sys
from pathlib import Path

INPUT_TXT = Path(r"C:/Users/x-tor/Downloads/4000_preguntas_utf8.txt")
INPUT_JSON = Path(r"C:/VIC_PRO/myapp/tools/4000_questions.json")


def extract_all_answers(text: str) -> dict[int, str]:
    """
    Re-parsea SOLO las filas de tablas de soluciones del PDF.
    Captura cualquier linea con uno o dos pares "N letra".
    """
    answers: dict[int, str] = {}
    # Una fila de tabla puede tener: "N L" o "N L M K".
    # Permitimos numeros con o sin punto separador de miles ("1001" o "1.001").
    # Numero: 1-3 digitos OPCIONAL "." + 3 digitos (formato espanol miles)
    # O 4 digitos sin punto. Aceptamos ambos.
    NUM = r"(?:\d{1,3}(?:\.\d{3})?|\d{4})"
    row_re = re.compile(
        r"^\s*"
        rf"({NUM})\s+([ABCDabcd])"
        rf"(?:\s+({NUM})\s+([ABCDabcd]))?"
        r"\s*$"
    )
    # Pero CUIDADO: una pregunta tambien empieza con "N." (con punto).
    # Filtramos: solo si NO termina en ".", solo si la longitud de la linea
    # es corta (filas de tabla son cortas).
    # Mejor: aplicar row_re y excluir lineas que sean inicio de pregunta.

    for line in text.split("\n"):
        # Las preguntas tienen formato "N. texto" (numero, punto, espacio, texto)
        # mientras que las tablas tienen "N letra" o "N letra M letra".
        # Excluir si la linea contiene texto largo despues del numero.
        if "." in line.split()[0:1] and len(line) > 20:
            # Es probablemente una pregunta, no tabla.
            continue
        m = row_re.match(line)
        if not m:
            continue
        # Guardar par 1
        n1 = int(m.group(1).replace(".", ""))
        if 1 <= n1 <= 4000:
            letter1 = m.group(2).upper()
            answers[n1] = letter1
        # Guardar par 2 si existe
        if m.group(3):
            n2 = int(m.group(3).replace(".", ""))
            if 1 <= n2 <= 4000:
                letter2 = m.group(4).upper()
                answers[n2] = letter2
    return answers


def main():
    if not INPUT_TXT.exists():
        print(f"ERROR: no existe {INPUT_TXT}", file=sys.stderr)
        sys.exit(1)
    if not INPUT_JSON.exists():
        print(f"ERROR: no existe {INPUT_JSON}", file=sys.stderr)
        sys.exit(1)

    text = INPUT_TXT.read_text(encoding="utf-8")
    answers = extract_all_answers(text)
    print(f"Respuestas extraidas de las tablas: {len(answers)}")
    print(f"Esperadas: 4000")
    missing_in_table = [n for n in range(1, 4001) if n not in answers]
    print(f"Numeros 1-4000 NO encontrados en tablas: {len(missing_in_table)}")
    if missing_in_table:
        print(f"  Primeros: {missing_in_table[:20]}")

    # Comparar con el JSON.
    json_data = json.loads(INPUT_JSON.read_text(encoding="utf-8"))
    json_by_num = {q["number"]: q for q in json_data}

    mismatches = []
    null_in_json = []
    json_missing_in_table = []
    table_missing_in_json = []

    for n in range(1, 4001):
        in_table = n in answers
        in_json = n in json_by_num
        if not in_table and not in_json:
            continue
        if in_table and not in_json:
            table_missing_in_json.append(n)
            continue
        if in_json and not in_table:
            json_missing_in_table.append(n)
            continue
        # Ambos presentes -> comparar.
        json_correct = json_by_num[n]["correct"]
        table_correct = answers[n]
        if json_correct is None:
            null_in_json.append(n)
        elif json_correct != table_correct:
            mismatches.append((n, json_correct, table_correct))

    print(f"\n=== RESULTADOS ===")
    print(f"Preguntas en JSON con respuesta NULL:    {len(null_in_json)}")
    if null_in_json:
        print(f"  Numeros: {null_in_json[:20]}")
    print(f"Mismatches (JSON != PDF):                {len(mismatches)}")
    if mismatches:
        print(f"  Primeros: {mismatches[:20]}")
    print(f"En JSON pero NO en tabla del PDF:        {len(json_missing_in_table)}")
    if json_missing_in_table:
        print(f"  Numeros: {json_missing_in_table[:20]}")
    print(f"En tabla del PDF pero NO en JSON:        {len(table_missing_in_json)}")
    if table_missing_in_json:
        print(f"  Numeros: {table_missing_in_json[:20]}")

    # Veredicto final
    print(f"\n=== VEREDICTO ===")
    if not mismatches and not null_in_json:
        print(f"OK: Todas las preguntas en el JSON tienen la respuesta correcta")
        print(f"    segun la tabla del PDF. {len(json_missing_in_table)} preguntas no")
        print(f"    estan en el JSON (parseo de pregunta fallido, no de respuesta).")
    else:
        print(f"WARNING: hay {len(mismatches)} mismatches y {len(null_in_json)} NULLs.")
        print(f"Hay que arreglar el parser.")


if __name__ == "__main__":
    main()
