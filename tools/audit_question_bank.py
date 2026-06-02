#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Auditoria 1-a-1 de las 3985 preguntas del banco (Constitucion).

Lee `tools/4000_questions.json` (resultado del parser del PDF) y, para cada
pregunta, calcula a que nodo del indice queda asignada con la convencion
actual:
   - article_match  -> "Articulo N"        (la mayoria)
   - chapter_match  -> "CAPITULO X"        (cuando solo hay capitulo)
   - title_match    -> "TITULO X"          (cuando solo hay titulo)
   - sino           -> "Constitucion Espanola" (raiz; ambigua)

Cruza con la lista de nodos esperados (1 raiz + 11 titulos + 11 capitulos
+ 2 secciones + 169 articulos + 15 disposiciones = 209 nodos) y produce
un reporte con:
   1) Total y conteo por categoria.
   2) Articulos 1..169 con su numero de preguntas (top/bottom/0).
   3) Preguntas asignadas a nodos genericos (Titulo/Capitulo) -> indica
      donde la IA tendria que rellenar mas adelante.
   4) Preguntas en raiz (las realmente ambiguas).
   5) Re-aplicacion de un regex mejorado a las "huerfanas" (raiz) para ver
      si el parser anterior se perdio referencias a articulos.

NO escribe SQL. Solo imprime el reporte por stdout.
"""

from __future__ import annotations
import json
import re
import hashlib
from collections import Counter, defaultdict
from pathlib import Path

INPUT_JSON = Path(r"C:/VIC_PRO/myapp/tools/4000_questions.json")

ROMAN = {"1":"I","2":"II","3":"III","4":"IV","5":"V","6":"VI","7":"VII","8":"VIII","9":"IX","10":"X"}


def md5(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def label_for(q: dict) -> tuple[str, str]:
    """Devuelve (categoria, label_normalizado)."""
    if q.get("article_match"):
        return "articulo", f"Articulo {q['article_match']}"
    if q.get("chapter_match"):
        raw = str(q["chapter_match"]).lower()
        if raw in ("i","ii","iii","iv","v","vi","vii","viii","ix","x"):
            return "capitulo", f"CAPITULO {raw.upper()}"
        return "capitulo", f"CAPITULO {raw}"
    if q.get("title_match"):
        raw = str(q["title_match"]).lower()
        if raw == "preliminar":
            return "titulo", "TITULO PRELIMINAR"
        if raw in ROMAN:
            return "titulo", f"TITULO {ROMAN[raw]}"
        return "titulo", f"TITULO {raw}"
    return "raiz", "Constitucion Espanola"


# Regex mejorado para re-buscar referencias a articulo en las raiz.
# Captura: "art. N", "articulo N", "articulos N y M", "del articulo N".
ART_RE = re.compile(
    r"art(?:\.|[ií]culo[s]?)\s+(\d{1,3})",
    re.IGNORECASE,
)


def main() -> None:
    data = json.loads(INPUT_JSON.read_text(encoding="utf-8"))

    print(f"=== Auditoria 1-a-1 de question_bank (Constitucion) ===")
    print(f"Total preguntas en JSON: {len(data)}\n")

    by_cat: Counter[str] = Counter()
    by_label: Counter[str] = Counter()
    raiz_items: list[dict] = []
    art_items: dict[int, list[dict]] = defaultdict(list)

    skipped_no_correct = 0
    skipped_no_options = 0
    for q in data:
        if not q.get("correct"):
            skipped_no_correct += 1
            continue
        if not q.get("options", {}).get("a"):
            skipped_no_options += 1
            continue
        cat, label = label_for(q)
        by_cat[cat] += 1
        by_label[label] += 1
        if cat == "raiz":
            raiz_items.append(q)
        elif cat == "articulo":
            try:
                art_items[int(q["article_match"])].append(q)
            except (TypeError, ValueError):
                pass

    valid = sum(by_cat.values())
    print(f"Preguntas validas (con respuesta + 4 opciones): {valid}")
    print(f"  - sin 'correct':       {skipped_no_correct}")
    print(f"  - sin opciones a-d:    {skipped_no_options}\n")

    print("=== 1) Distribucion por categoria ===")
    for cat, n in by_cat.most_common():
        print(f"  {cat:<10}  {n:5}   ({n*100/valid:5.1f}%)")
    print()

    # ---------- 2) Articulos 1..169 con su numero de preguntas ----------
    print("=== 2) Preguntas por Articulo (1..169) ===")
    counts_by_art = {a: len(qs) for a, qs in art_items.items()}
    arts_zero = [a for a in range(1, 170) if a not in counts_by_art]
    print(f"  Articulos cubiertos:        {169 - len(arts_zero)} / 169")
    print(f"  Articulos con 0 preguntas:  {len(arts_zero)} -> {arts_zero}")
    if counts_by_art:
        sorted_arts = sorted(counts_by_art.items(), key=lambda x: -x[1])
        print(f"\n  Top 15 articulos mas cubiertos:")
        for a, n in sorted_arts[:15]:
            print(f"    Art {a:>3}: {n:3} preguntas")
        print(f"\n  Bottom 15 articulos (>=1):")
        for a, n in sorted_arts[-15:]:
            print(f"    Art {a:>3}: {n:3} preguntas")

    avg = sum(counts_by_art.values()) / max(1, len(counts_by_art))
    print(f"\n  Media por articulo cubierto: {avg:.1f} preguntas\n")

    # ---------- 3) Genericos (Titulo / Capitulo) ----------
    print("=== 3) Preguntas en nodos genericos (Titulo / Capitulo) ===")
    generics = sorted(
        ((lbl, n) for lbl, n in by_label.items()
         if lbl.startswith(("TITULO ", "CAPITULO "))),
        key=lambda x: -x[1],
    )
    if generics:
        for lbl, n in generics:
            print(f"  {lbl:<25}  {n:4}")
    else:
        print("  (ninguna)")
    print()

    # ---------- 4) Raiz: huerfanas ambiguas ----------
    print("=== 4) Preguntas en raiz (sin referencia identificada) ===")
    print(f"  Total en raiz: {len(raiz_items)}\n")

    # ---------- 5) Re-aplicar regex mejorado a las raiz ----------
    print("=== 5) Re-busqueda con regex en las raiz (RESCATE) ===")
    rescatables: list[tuple[dict, int]] = []
    no_match = 0
    for q in raiz_items:
        # Concatenar pregunta + opciones
        haystack = q["question"]
        for k in ("a", "b", "c", "d"):
            v = q.get("options", {}).get(k)
            if v:
                haystack += " " + v
        m = ART_RE.search(haystack)
        if m:
            num = int(m.group(1))
            if 1 <= num <= 169:
                rescatables.append((q, num))
            else:
                no_match += 1
        else:
            no_match += 1

    print(f"  Rescatables (mencionan Art N): {len(rescatables)}")
    print(f"  No rescatables (genericas):     {no_match}")
    if rescatables:
        # Cuantas por articulo
        rescue_by_art: Counter[int] = Counter()
        for _, n in rescatables:
            rescue_by_art[n] += 1
        print(f"\n  Top 10 articulos a los que se moverian:")
        for n, c in rescue_by_art.most_common(10):
            print(f"    Art {n:>3}: +{c} preguntas (actualmente: {counts_by_art.get(n, 0)})")

    # Sample de no-rescatables (las verdaderamente genericas)
    print(f"\n  Muestra de 5 'no rescatables' (genericas reales):")
    truly_generic = [q for q in raiz_items
                     if not ART_RE.search(q["question"] + " " +
                                          " ".join(q.get("options", {}).values()))]
    for q in truly_generic[:5]:
        print(f"    > {q['question'][:120]}...")

    print("\n=== FIN ===")


if __name__ == "__main__":
    main()
