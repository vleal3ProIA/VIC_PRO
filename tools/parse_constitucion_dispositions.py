#!/usr/bin/env python3
"""
Parser incremental: extrae solo las disposiciones del PDF de la Constitucion
y genera migracion 0091 que las anyade al subject existente como nodos
hermanos de los Titulos (parent = root, depth=1).

NO altera nada de lo que ya esta en 0090. Solo INSERT de los 15 nodos
disposicion + su node_content original.
"""

from __future__ import annotations
import re
from pathlib import Path

INPUT_TXT = Path(r"C:/Users/x-tor/Downloads/constitucion_text.txt")
OUTPUT_SQL = Path(r"C:/VIC_PRO/myapp/supabase/migrations/0091_seed_constitucion_dispositions.sql")


def sql_escape(s: str) -> str:
    return s.replace("'", "''")


def main():
    text = INPUT_TXT.read_text(encoding="utf-8")
    # Solo desde TEXTO CONSOLIDADO
    idx = text.find("TEXTO CONSOLIDADO")
    body = text[idx:] if idx >= 0 else text

    # Regex que matchea las disposiciones individuales. "ς  Disposición ..."
    # el primer caracter no-blank puede ser cualquier dingbat (1-3 chars).
    disp_re = re.compile(
        r"^\s*\S{0,3}\s*"
        r"(Disposición\s+(adicional|transitoria|derogatoria|final)"
        r"(?:\s+(primera|segunda|tercera|cuarta|quinta|sexta|s[eé]ptima|octava|novena))?)"
        r"\s*$",
        re.MULTILINE | re.IGNORECASE,
    )

    matches = list(disp_re.finditer(body))
    print(f"Disposiciones encontradas: {len(matches)}")

    dispositions = []
    for i, m in enumerate(matches):
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(body)
        content = body[start:end].strip()
        # Normalizar el title sin trailing dots.
        kind = m.group(2).lower()
        ordinal = m.group(3).lower() if m.group(3) else None
        if ordinal:
            # Capitalize: "primera" -> "Primera"
            ordinal_disp = ordinal.replace("e", "é") if ordinal == "septima" else ordinal
            title = f"Disposición {kind} {ordinal_disp}".replace(
                " primera", " primera"
            )
            # Capitalizar primera letra
            title = title[0].upper() + title[1:]
        else:
            title = f"Disposición {kind}"
            title = title[0].upper() + title[1:]
        dispositions.append({"title": title, "content": content})
        print(f"  [{i}] {title} ({len(content)} chars)")

    # Generar SQL
    parts = [f"""-- ========================================================================
-- 0091 · Anyadir disposiciones de la Constitucion al subject existente
-- ------------------------------------------------------------------------
-- La 0090 omitio las 15 disposiciones (4 adicionales + 9 transitorias +
-- 1 derogatoria + 1 final) por bug en el regex. Esta migracion las
-- anyade como hermanos de los Titulos (parent = root, depth=1).
--
-- content_hash = md5(title) -> si el subject viejo tenia las mismas
-- disposiciones con md5(title), las preguntas en question_bank se
-- enlazan automaticamente.
-- ========================================================================

do $$
declare
  v_subject_id uuid;
  v_user_id    uuid;
  v_root_id    uuid;
  v_tmp_id     uuid;
  v_position   int;
begin
  -- Localizar subject Constitucion.
  select s.id, s.user_id into v_subject_id, v_user_id
  from public.subjects s
  join public.profiles p on p.id = s.user_id
  where p.is_super_admin = true
    and s.title ilike '%constituci%espa%'
  order by s.created_at desc
  limit 1;

  if v_subject_id is null then
    raise notice '[0091] subject no encontrado, skipping';
    return;
  end if;

  -- Localizar nodo raiz.
  select id into v_root_id
  from public.index_nodes
  where subject_id = v_subject_id and parent_id is null
  limit 1;

  if v_root_id is null then
    raise notice '[0091] root no encontrado, skipping';
    return;
  end if;

  -- Calcular position siguiente (despues del ultimo Titulo).
  select coalesce(max(position), -1) + 1 into v_position
  from public.index_nodes
  where parent_id = v_root_id;

  raise notice '[0091] anyadiendo disposiciones desde position=%', v_position;

"""]

    for i, d in enumerate(dispositions):
        title_esc = sql_escape(d["title"])
        content_esc = d["content"]
        # Usar dollar-quoting unico por disposicion para evitar problemas.
        tag = f"d{i + 1}"
        safe_content = content_esc.replace(f"${tag}$", f"$ {tag} $")
        position = i  # Se sumara a v_position al insertar
        parts.append(
            f"""
  -- Disposicion {i + 1}: {d['title']}
  if not exists (
    select 1 from public.index_nodes
    where subject_id = v_subject_id and title = '{title_esc}'
  ) then
    insert into public.index_nodes (subject_id, user_id, parent_id, title, position, depth, content_hash)
    values (v_subject_id, v_user_id, v_root_id, '{title_esc}', v_position + {i}, 1, md5('{title_esc}'))
    returning id into v_tmp_id;
    insert into public.node_content (node_id, user_id, kind, content)
    values (v_tmp_id, v_user_id, 'original', ${tag}${safe_content}${tag}$);
  end if;
"""
        )

    parts.append("""
  raise notice '[0091] disposiciones anyadidas';
end $$;
""")

    OUTPUT_SQL.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_SQL.write_text("".join(parts), encoding="utf-8")
    print(f"\nSQL escrito en: {OUTPUT_SQL}")
    print(f"Tamano: {OUTPUT_SQL.stat().st_size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
