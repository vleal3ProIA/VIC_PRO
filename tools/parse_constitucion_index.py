#!/usr/bin/env python3
"""
Parsea el texto extraido del PDF de la Constitucion Espanola y genera una
migracion SQL que:
  1. Hace UPSERT del document (extracted_text + status='ready') asociado al
     subject Constitucion del super-admin.
  2. Borra (si existe) los index_nodes/node_content del subject (clean slate).
  3. Crea la jerarquia completa: subject_root -> Titulos -> Capitulos ->
     Secciones -> Articulos + Preambulo + Disposiciones.
  4. Inserta node_content kind='original' por cada articulo (texto literal).
  5. Asigna content_hash = md5(title) para cada nodo (compatible con el
     subject viejo donde se usaba este fallback).
  6. Update subjects.index_status='ready'.

Por que md5(title): el banco global (question_bank) sigue conteniendo 3696
preguntas enlazadas a content_hash del subject viejo. Como aquel subject
usaba md5(title) como fallback (ej. md5("Articulo 9")), si nuestro nuevo
parser asigna el mismo hash, las preguntas se enlazan automaticamente.
"""

from __future__ import annotations
import re
import sys
import hashlib
from pathlib import Path

INPUT_TXT = Path(r"C:/Users/x-tor/Downloads/constitucion_text.txt")
OUTPUT_SQL = Path(r"C:/VIC_PRO/myapp/supabase/migrations/0090_seed_constitucion_create_full.sql")

ROMAN_TO_INT = {
    "I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7,
    "VIII": 8, "IX": 9, "X": 10,
}
ROMAN_NAMES = {
    "I": "I", "II": "II", "III": "III", "IV": "IV", "V": "V",
    "VI": "VI", "VII": "VII", "VIII": "VIII", "IX": "IX", "X": "X",
}


def md5_hex(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def sql_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "''")


def parse_constitucion(text: str) -> dict:
    """
    Devuelve un dict con:
      - extracted_text: el texto entero del PDF (para documents.extracted_text).
      - structure: lista de bloques estructurales con su jerarquia y posiciones.
    """
    # Solo procesamos a partir de "TEXTO CONSOLIDADO" (linea 67 aprox).
    # El indice antes de esa linea no es contenido.
    idx_start = text.find("TEXTO CONSOLIDADO")
    if idx_start < 0:
        idx_start = 0
    body = text[idx_start:]

    # Patrones:
    title_re = re.compile(
        r"^\s+TÍTULO\s+(PRELIMINAR|[IVX]+)\s*$", re.MULTILINE
    )
    chapter_re = re.compile(
        r"^\s+CAPÍTULO\s+(PRIMERO|SEGUNDO|TERCERO|CUARTO|QUINTO|SEXTO|SÉPTIMO|OCTAVO|NOVENO|DÉCIMO)\s*$",
        re.MULTILINE,
    )
    section_re = re.compile(
        r"^\s*Sección\s+(\d+)\.[aª]\s+(.+?)$", re.MULTILINE
    )
    # "ς  Artículo N" o similar. La linea es CORTA y solo contiene
    # "<dingbat>? espacios Artículo N". Aceptamos hasta 5 chars no-blank
    # antes de "Artículo".
    article_re = re.compile(
        r"^\s*\S{0,3}\s*Artículo\s+(\d+)\s*$", re.MULTILINE
    )
    preamble_re = re.compile(r"^\s*PREÁMBULO\s*$", re.MULTILINE)
    # Disposiciones: aceptamos "Disposiciones adicionales" / "Disposicion adicional X" etc.
    disp_section_re = re.compile(
        r"^\s*Disposiciones?\s+(adicionales?|transitorias?|derogatoria|final)\s*$",
        re.MULTILINE | re.IGNORECASE,
    )

    markers = []

    # Recolectar TODOS los matches y ordenar por posicion.
    for m in title_re.finditer(body):
        markers.append(("title", m.start(), m.group(1).strip(), m.group(0).strip()))
    for m in chapter_re.finditer(body):
        markers.append(("chapter", m.start(), m.group(1).strip(), m.group(0).strip()))
    for m in section_re.finditer(body):
        section_num = m.group(1).strip()
        section_label = m.group(2).strip()
        markers.append(("section", m.start(), section_num, f"Sección {section_num}.ª {section_label}"))
    for m in article_re.finditer(body):
        markers.append(("article", m.start(), m.group(1).strip(), f"Artículo {m.group(1).strip()}"))
    for m in preamble_re.finditer(body):
        markers.append(("preamble", m.start(), "", "Preámbulo"))
    for m in disp_section_re.finditer(body):
        kind_word = m.group(1).strip().lower()
        # Normalizar
        if "adicional" in kind_word:
            label = "Disposiciones adicionales"
        elif "transitoria" in kind_word:
            label = "Disposiciones transitorias"
        elif "derogatoria" in kind_word:
            label = "Disposición derogatoria"
        elif "final" in kind_word:
            label = "Disposición final"
        else:
            label = m.group(0).strip()
        markers.append(("disposition", m.start(), kind_word, label))

    markers.sort(key=lambda x: x[1])

    # Asignar `end` a cada marker = start del siguiente.
    enriched = []
    for i, mk in enumerate(markers):
        kind, start, raw, label = mk
        end = markers[i + 1][1] if i + 1 < len(markers) else len(body)
        enriched.append({
            "kind": kind,
            "start": start,
            "end": end,
            "raw": raw,
            "label": label,
        })

    # Eliminar duplicados (a veces el indice de inicio del PDF se cuela como
    # marker). Si vemos 2 articulos N consecutivos sin contenido entre ellos,
    # tomamos el segundo (que es el real, no la entrada del indice).
    # Pero en realidad ya filtramos en `text[idx_start:]` con TEXTO CONSOLIDADO.

    return {
        "extracted_text": text,
        "structure": enriched,
        "body": body,
        "body_offset": idx_start,
    }


def build_hierarchy(structure: list[dict], body: str) -> list[dict]:
    """
    Construye una jerarquia padre-hijo:
      Subject (root) -> Preambulo / Titulos / Disposiciones
      Titulos -> Capitulos
      Capitulos -> Secciones (solo en Capitulo Segundo del Titulo I)
      Capitulos/Secciones -> Articulos
    Devuelve la estructura plana con campos: kind, label, parent_idx, depth,
    position, content (texto de la seccion sin la cabecera).
    """
    nodes = []
    stack = []  # pilas de indices por depth

    def push_node(node: dict):
        nodes.append(node)
        return len(nodes) - 1

    # Definimos niveles:
    # depth 1: title (Preambulo, Titulo X, Disposicion X)
    # depth 2: chapter
    # depth 3: section
    # depth 4: article

    current_title = None  # idx del titulo actual
    current_chapter = None
    current_section = None

    for mk in structure:
        kind = mk["kind"]
        content_text = body[mk["start"]:mk["end"]].strip()
        # Quitar la primera linea (cabecera) del content.
        first_nl = content_text.find("\n")
        if first_nl > 0:
            content_text = content_text[first_nl + 1:].strip()

        if kind == "preamble":
            node = {
                "kind": "preamble",
                "label": "Preámbulo",
                "parent_idx": None,
                "depth": 1,
                "position": 0,
                "content": content_text,
            }
            current_title = push_node(node)
            current_chapter = None
            current_section = None
        elif kind == "title":
            label_part = mk["raw"]
            if label_part == "PRELIMINAR":
                label = "TÍTULO PRELIMINAR"
            else:
                label = f"TÍTULO {label_part}"
            node = {
                "kind": "title",
                "label": label,
                "parent_idx": None,
                "depth": 1,
                "position": 0,
                "content": "",  # no content directo, los hijos tienen.
            }
            current_title = push_node(node)
            current_chapter = None
            current_section = None
        elif kind == "chapter":
            label = f"CAPÍTULO {mk['raw']}"
            node = {
                "kind": "chapter",
                "label": label,
                "parent_idx": current_title,
                "depth": 2,
                "position": 0,
                "content": "",
            }
            current_chapter = push_node(node)
            current_section = None
        elif kind == "section":
            node = {
                "kind": "section",
                "label": mk["label"],
                "parent_idx": current_chapter if current_chapter is not None else current_title,
                "depth": 3,
                "position": 0,
                "content": "",
            }
            current_section = push_node(node)
        elif kind == "article":
            parent = (
                current_section if current_section is not None
                else (current_chapter if current_chapter is not None else current_title)
            )
            node = {
                "kind": "article",
                "label": f"Artículo {mk['raw']}",
                "parent_idx": parent,
                "depth": parent_depth(parent, nodes) + 1 if parent is not None else 1,
                "position": 0,
                "content": content_text,
            }
            push_node(node)
        elif kind == "disposition":
            node = {
                "kind": "disposition",
                "label": mk["label"],
                "parent_idx": None,
                "depth": 1,
                "position": 0,
                "content": content_text,
            }
            current_title = push_node(node)
            current_chapter = None
            current_section = None

    # Calcular position (orden de hermanos dentro del padre).
    sibling_counter: dict[int | None, int] = {}
    for i, n in enumerate(nodes):
        parent = n["parent_idx"]
        sibling_counter.setdefault(parent, 0)
        n["position"] = sibling_counter[parent]
        sibling_counter[parent] += 1

    return nodes


def parent_depth(parent_idx, nodes):
    if parent_idx is None:
        return 0
    return nodes[parent_idx]["depth"]


def generate_sql(nodes: list[dict], extracted_text: str) -> str:
    parts = []
    parts.append("""-- ========================================================================
-- 0089 · Seed Constitucion: estructura completa SIN llamar a IA
-- ------------------------------------------------------------------------
-- Parser local (tools/parse_constitucion_index.py) extrajo el texto del PDF
-- y la jerarquia Titulo > Capitulo > Seccion > Articulo. Esta migracion:
--
--   1. Localiza el subject Constitucion del super-admin.
--   2. UPSERT document con extracted_text completo + status='ready'.
--   3. Borra index_nodes y node_content existentes del subject (clean slate).
--   4. Crea root node + jerarquia completa.
--   5. INSERT node_content kind='original' por cada Articulo.
--   6. content_hash = md5(label) para cada nodo (compatible con subject viejo,
--      donde se usaba este fallback -> las 3696 preguntas en question_bank se
--      enlazan automaticamente).
--   7. subjects.index_status='ready'.
--
-- Resultado: el cliente puede generar Test del Articulo X sin gastar tokens
-- (las preguntas estan en question_bank). Los "Explicado" / "Resumen" / V-F
-- siguen llamando a IA pero con Groq disponible como fallback de Gemini.
-- ========================================================================
""")

    parts.append("""do $$
declare
  v_subject_id uuid;
  v_user_id    uuid;
  v_root_id    uuid;
  v_doc_id     uuid;
  v_storage_path text;
begin
  -- 1) Localizar (o crear) subject Constitucion del super-admin.
  -- Localizar primero el user_id del super-admin.
  select id into v_user_id
  from public.profiles
  where is_super_admin = true
  order by created_at asc
  limit 1;

  if v_user_id is null then
    raise exception '[0090] no super-admin encontrado, no puedo crear subject';
  end if;

  -- Buscar subject existente.
  select s.id into v_subject_id
  from public.subjects s
  where s.user_id = v_user_id
    and s.title ilike '%constituci%espa%'
  order by s.created_at desc
  limit 1;

  if v_subject_id is null then
    -- Crearlo.
    insert into public.subjects (user_id, title, language, shareable)
    values (v_user_id, 'Constitución Española', 'es', true)
    returning id into v_subject_id;
    raise notice '[0090] subject CREADO: %', v_subject_id;
  else
    raise notice '[0090] subject existente: %', v_subject_id;
  end if;

  raise notice '[0090] subject=%, user=%', v_subject_id, v_user_id;

  -- 2) UPSERT document. Buscamos el ultimo doc del subject (si hay) y lo
  -- updateamos. Si no, insertamos uno nuevo.
""")

    # ---- Extracted text como literal ----
    # Para evitar escape hell, escribimos el texto en bloque con dollar-quoting
    # Postgres: $body$...$body$. ESO permite cualquier contenido sin escape.
    parts.append("  select d.id, d.storage_path into v_doc_id, v_storage_path\n")
    parts.append("  from public.documents d\n")
    parts.append("  where d.subject_id = v_subject_id\n")
    parts.append("  order by d.created_at desc nulls last\n")
    parts.append("  limit 1;\n\n")
    parts.append("  if v_doc_id is not null then\n")
    parts.append("    update public.documents set\n")
    parts.append("      status = 'ready',\n")
    parts.append("      extracted_text = $body$" + extracted_text + "$body$,\n")
    parts.append("      error = null\n")
    parts.append("    where id = v_doc_id;\n")
    parts.append("    raise notice '[0089] document actualizado: %', v_doc_id;\n")
    parts.append("  else\n")
    parts.append("    insert into public.documents (subject_id, user_id, storage_path, file_name, mime_type, status, extracted_text)\n")
    parts.append("    values (v_subject_id, v_user_id, v_subject_id::text || '/manual-constitucion.pdf', 'CONSTITUCIÓN ESPAÑOLA 2025.pdf', 'application/pdf', 'ready', $body$" + extracted_text + "$body$)\n")
    parts.append("    returning id into v_doc_id;\n")
    parts.append("    raise notice '[0089] document creado: %', v_doc_id;\n")
    parts.append("  end if;\n\n")

    # ---- Borrar index_nodes existentes (cascade borra node_content) ----
    parts.append("""  -- 3) Limpiar index_nodes existentes (cascade borra node_content).
  delete from public.index_nodes where subject_id = v_subject_id;

  -- 4) Crear nodo raiz.
  insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
  values (
    v_subject_id, v_user_id, null,
    'Constitución Española',
    0, 0,
    $1$ + chr(36) + 'Constitución Española' + chr(36) + $1$  -- placeholder
  )
  returning id into v_root_id;
""")
    # FIX: usar md5() directamente
    parts[-1] = parts[-1].replace(
        "$1$ + chr(36) + 'Constitución Española' + chr(36) + $1$  -- placeholder",
        "md5('Constitución Española')"
    )

    # ---- Insertar nodos con un CTE recursivo o iterativo ----
    # Estrategia: insertar via VALUES + variables CTE. Necesitamos resolver
    # parent_id por orden -> usamos un array temporal de uuids generados con
    # gen_random_uuid().

    parts.append("\n  raise notice '[0089] root=%', v_root_id;\n\n")
    parts.append("  -- 5) Insertar jerarquia completa via CTEs encadenadas.\n")
    parts.append("  -- Para preservar relaciones padre-hijo, generamos un uuid por nodo y\n")
    parts.append("  -- referenciamos por indice. Hacemos un INSERT por NIVEL (depth 1 -> 2 -> 3 -> 4)\n")
    parts.append("  -- para no tener problemas de orden de FK.\n")

    # ---- Group nodes by depth and emit batches ----
    # Necesitamos asignar uuid temporal a cada nodo y mantener mapping idx -> uuid.
    # En SQL puro, lo hacemos via WITH RECURSIVE o multiples INSERTs ordenados.

    # Mas simple: hacer un INSERT por cada nodo individualmente usando un
    # array TEMPORAL para tracking. PL/pgSQL lo permite.

    # Inicializamos el array con array_fill para evitar "out of bounds" en
    # PL/pgSQL al asignar v_node_ids[N] := uuid.
    parts.append(f"\n  declare\n    v_node_ids uuid[] := array_fill(null::uuid, ARRAY[{len(nodes) + 10}]);\n  begin\n")

    # Now insert one by one with proper parent resolution
    for i, n in enumerate(nodes):
        parent_idx = n["parent_idx"]
        if parent_idx is None:
            parent_sql = "v_root_id"
        else:
            parent_sql = f"v_node_ids[{parent_idx + 1}]"

        label_esc = sql_escape(n["label"])
        # depth: si parent_idx is None, depth = 1. Sino, depth = parent.depth + 1.
        depth = n["depth"]
        position = n["position"]

        parts.append(
            f"    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)\n"
            f"    values (v_subject_id, v_user_id, {parent_sql}, '{label_esc}', {position}, {depth}, md5('{label_esc}'))\n"
            f"    returning id into v_node_ids[{i + 1}];\n"
        )

        # Si tiene content (article, preamble, disposition con texto), insertar node_content kind='original'
        if n["content"] and len(n["content"].strip()) > 20:
            # Usamos dollar-quoting $c{i}$ con tag UNICO por nodo para evitar
            # colisiones internas si el texto del articulo contiene literalmente
            # algun otro tag dollar-quoted. Tag corto pero unico.
            tag = f"c{i + 1}"
            # Asegurar que el tag no aparezca dentro del content (extremadamente
            # improbable en un texto legal).
            safe_content = n["content"].replace(f"${tag}$", f"$ {tag} $")
            parts.append(
                f"    insert into public.node_content (node_id, user_id, kind, content)\n"
                f"    values (v_node_ids[{i + 1}], v_user_id, 'original', ${tag}${safe_content}${tag}$);\n"
            )

    parts.append("  end;\n\n")

    parts.append("""  -- 6) Marcar subject como listo.
  update public.subjects
  set index_status = 'ready', index_error = null
  where id = v_subject_id;

  raise notice '[0089] subject marcado como ready';
end $$;
""")

    return "".join(parts)


def main():
    if not INPUT_TXT.exists():
        print(f"ERROR: no existe {INPUT_TXT}", file=sys.stderr)
        sys.exit(1)
    text = INPUT_TXT.read_text(encoding="utf-8")
    parsed = parse_constitucion(text)
    nodes = build_hierarchy(parsed["structure"], parsed["body"])

    counts = {}
    for n in nodes:
        counts[n["kind"]] = counts.get(n["kind"], 0) + 1
    print(f"\nNodos por tipo: {counts}", file=sys.stderr)
    print(f"Total nodos: {len(nodes)}", file=sys.stderr)
    print(f"Articulos con texto: {sum(1 for n in nodes if n['kind']=='article' and len(n['content']) > 20)}", file=sys.stderr)

    sql = generate_sql(nodes, parsed["extracted_text"])
    OUTPUT_SQL.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_SQL.write_text(sql, encoding="utf-8")
    print(f"\nSQL escrito en: {OUTPUT_SQL}", file=sys.stderr)
    print(f"Tamano: {OUTPUT_SQL.stat().st_size / 1024:.1f} KB", file=sys.stderr)


if __name__ == "__main__":
    main()
