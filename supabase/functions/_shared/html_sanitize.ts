// ============================================================================
// Helper compartido: sanitizacion HTML para broadcast emails (PR-E)
// ----------------------------------------------------------------------------
// Defensa contra XSS / phishing en broadcasts. El admin escribe `body_html`
// libremente en /admin/broadcasts/new; sin sanitize, un admin con cookie
// robada (o un admin malicioso) puede inyectar <script>, <style>,
// <iframe>, atributos `on*`, links `javascript:` ... y mandarselo a toda
// la base de users via email. Algunos clientes de email modernos
// (Gmail web, Apple Mail) ejecutan JS en contextos limitados, y aunque
// la mayoria stripea <script>, hay vectores con <style>, <svg onload>,
// links con javascript:, etc.
//
// **Estrategia: whitelist estricta**.
//   - Tags permitidos: solo los necesarios para formato basico de mail.
//   - Atributos permitidos: SOLO `href` en `<a>`. Todo lo demas se strip.
//   - Esquemas permitidos en href: http, https, mailto. NO javascript:,
//     NO data:, NO vbscript:.
//   - Force `rel="noopener noreferrer"` + `target="_blank"` en TODOS
//     los links (defensa contra tabnabbing + leakage de referer).
//   - Tags fuera del whitelist: eliminados completamente CON su contenido
//     (drop) si son peligrosos (<script>, <style>, <iframe>, <svg>);
//     conservando el contenido (unwrap) si son benignos (<div>, <span>).
//
// **No usamos sanitize-html de npm**: pesa ~200 KB con deps, anyade
// segundos al cold start de la Edge Function. Una whitelist estricta como
// la nuestra cabe en 150 lineas y no tiene superficie de ataque.
//
// **Limitaciones conocidas**:
//   - Si el body contiene HTML invalido (tags mal anidados, etc.), el
//     parser greedy puede dejar caracteres sueltos. No es un riesgo de
//     seguridad -- el peor caso es un email feo, no un email peligroso.
//   - No detectamos polyglots HTML+JS embedded en CSS de tags
//     legitimos. Pero como NO permitimos `style=`, `<style>`, ni
//     `<link>`, la superficie es minima.
//   - Tampoco intentamos parsear y "completar" tags abiertos sin
//     cerrar. El cliente de email se encarga.
// ============================================================================

// ──────────────────────── Configuracion del whitelist ────────────────────────

// Tags permitidos en el body de un broadcast. Cualquier otro tag se
// procesa segun `DANGEROUS_TAGS` (drop) o se unwrap (mantener
// contenido, quitar tag).
const ALLOWED_TAGS = new Set<string>([
  // Estructura basica
  "p",
  "br",
  "hr",
  "blockquote",
  // Encabezados (4 niveles bastan para un email; h5/h6 raros)
  "h1",
  "h2",
  "h3",
  "h4",
  // Enfasis
  "strong",
  "em",
  "b",
  "i",
  "u",
  // Listas
  "ul",
  "ol",
  "li",
  // Enlaces (atributo href + rel + target gestionados manualmente)
  "a",
]);

// Tags peligrosos: se eliminan COMPLETOS con su contenido. Drop, no
// unwrap. Si el body trae `<script>alert(1)</script>` queda en cadena
// vacia, no en `alert(1)` suelto.
const DANGEROUS_TAGS = new Set<string>([
  "script",
  "style",
  "iframe",
  "frame",
  "frameset",
  "object",
  "embed",
  "applet",
  "form",
  "input",
  "button",
  "select",
  "textarea",
  "option",
  "link",
  "meta",
  "base",
  "svg",
  "math",
  "noscript",
  "template",
  "xml",
  // Tag custom de HTML5 (web components) - sin necesidad legitima en email
  "slot",
]);

// Esquemas permitidos en `href`. NO incluye javascript:, vbscript:, data:.
const ALLOWED_HREF_SCHEMES = new Set<string>([
  "http",
  "https",
  "mailto",
]);

// ────────────────────────────── Tokenizer ──────────────────────────────

// Estado del parser: leemos el input char-by-char y emitimos tokens.
// No usamos DOMParser (no disponible en Deno sin deps). Una maquina de
// estados manual es suficiente porque NO necesitamos reconstruir el
// arbol DOM -- solo decidir tag-por-tag si emit, drop, o unwrap.

type Token =
  | { kind: "text"; value: string }
  | {
    kind: "tag";
    tagName: string;
    isClosing: boolean;
    isSelfClosing: boolean;
    attrs: Record<string, string>;
    raw: string;
  }
  | { kind: "comment"; value: string };

// Tokeniza un fragmento HTML en tags + texto + comentarios. Sin parser
// completo: para nuestro caso (sanitize) basta ver tags uno a uno.
function tokenize(html: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  const len = html.length;

  while (i < len) {
    if (html[i] === "<") {
      // Comentario: <!-- ... -->
      if (html.substr(i, 4) === "<!--") {
        const end = html.indexOf("-->", i + 4);
        if (end === -1) {
          // Comentario sin cerrar: tratamos el resto como comentario y paramos.
          tokens.push({ kind: "comment", value: html.substr(i + 4) });
          i = len;
        } else {
          tokens.push({ kind: "comment", value: html.substring(i + 4, end) });
          i = end + 3;
        }
        continue;
      }

      // Tag normal: <tag> o </tag> o <tag/>
      const end = html.indexOf(">", i);
      if (end === -1) {
        // Tag sin cerrar: tratamos el resto como texto crudo.
        tokens.push({ kind: "text", value: html.substr(i) });
        i = len;
        break;
      }

      const tagContent = html.substring(i + 1, end);
      const isClosing = tagContent.startsWith("/");
      const inner = isClosing ? tagContent.substring(1) : tagContent;
      const isSelfClosing = inner.endsWith("/");
      const tagBody = isSelfClosing
        ? inner.substring(0, inner.length - 1)
        : inner;

      // Extraer tag name (primera palabra hasta espacio o fin).
      const nameMatch = tagBody.match(/^\s*([a-zA-Z][a-zA-Z0-9]*)/);
      if (!nameMatch) {
        // Bracket suelto que no es tag valido (ej. "a < b"): tratar
        // como texto literal.
        tokens.push({ kind: "text", value: html.substring(i, end + 1) });
        i = end + 1;
        continue;
      }
      const tagName = nameMatch[1].toLowerCase();
      const attrsRaw = tagBody.substring(nameMatch[0].length);
      const attrs = parseAttrs(attrsRaw);

      tokens.push({
        kind: "tag",
        tagName,
        isClosing,
        isSelfClosing,
        attrs,
        raw: html.substring(i, end + 1),
      });
      i = end + 1;
    } else {
      // Texto hasta el proximo '<'.
      const next = html.indexOf("<", i);
      if (next === -1) {
        tokens.push({ kind: "text", value: html.substring(i) });
        i = len;
      } else {
        tokens.push({ kind: "text", value: html.substring(i, next) });
        i = next;
      }
    }
  }
  return tokens;
}

// Parsea atributos de un fragmento como `href="..." target="_blank" disabled`.
// Devuelve map name->value (value vacio si attr sin valor).
function parseAttrs(raw: string): Record<string, string> {
  const result: Record<string, string> = {};
  // Regex que matchea: name="value" | name='value' | name=value | name
  // Tolerante a espacios.
  const re =
    /([a-zA-Z_:][a-zA-Z0-9_.:-]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(raw)) !== null) {
    const name = m[1].toLowerCase();
    const value = m[2] ?? m[3] ?? m[4] ?? "";
    result[name] = value;
  }
  return result;
}

// ───────────────────────────── Sanitizer ─────────────────────────────

// Escapa los 5 caracteres significativos de HTML para evitar
// reinyeccion al imprimir texto.
function escapeText(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Escapa un valor de atributo (solo `&` y `"` necesarios porque
// emitimos con comillas dobles).
function escapeAttr(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/"/g, "&quot;");
}

// Strip whitespace + caracteres de control para evitar bypasses tipo
// `java<newline>script:alert(1)` que algunos parsers tolerarian. Usamos
// la clase \s (whitespace) y el rango de control chars + DEL.
//
// Construimos el regex via `new RegExp` con la cadena explicita en lugar
// de literal `/.../g` para que los `\x00`-style escapes los interprete
// JavaScript en runtime y NO el editor de codigo (que en algunos
// pipelines convierte el escape en byte literal). Resultado funcional:
// strip de \t \n \r \v \f espacio + chars 0x00-0x1F + 0x7F.
const CONTROL_CHARS_RE = new RegExp(
  "[\\s\\u0000-\\u001F\\u007F]",
  "g",
);

// Decide si un href es seguro segun los esquemas permitidos. Quitamos
// whitespace + control chars antes de chequear esquema para evitar
// bypasses con caracteres invisibles. Luego comparamos el scheme en
// lowercase para que "JavaScript:" tambien quede bloqueado.
function isSafeHref(raw: string): boolean {
  const cleaned = raw.replace(CONTROL_CHARS_RE, "").trim();
  if (cleaned === "") return false;

  // URLs relativas (sin scheme) son seguras -- mismo origen.
  if (cleaned.startsWith("/") || cleaned.startsWith("#")) return true;
  if (cleaned.startsWith("./") || cleaned.startsWith("../")) return true;

  // Con scheme: comprobar esquema.
  const schemeMatch = cleaned.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):/);
  if (!schemeMatch) {
    // Sin esquema y no empieza por / ni # ni .  ->  ambiguo, lo rechazamos.
    // (URLs como "google.com" deberian llevar http:// explicito.)
    return false;
  }
  return ALLOWED_HREF_SCHEMES.has(schemeMatch[1].toLowerCase());
}

// Sanitiza HTML segun el whitelist. Devuelve HTML "limpio" listo para
// embed en un email. Nunca lanza -- entrada invalida produce salida
// degradada (text sin formato).
export function sanitizeBroadcastHtml(input: string): string {
  const tokens = tokenize(input);
  const out: string[] = [];

  for (const tok of tokens) {
    if (tok.kind === "text") {
      out.push(escapeText(tok.value));
      continue;
    }
    if (tok.kind === "comment") {
      // Comentarios: drop. Pueden contener `<!--[if IE]>` etc. con vectores.
      continue;
    }
    // tok.kind === "tag"
    if (DANGEROUS_TAGS.has(tok.tagName)) {
      // Drop completo. El pase previo `stripDangerousBlocks` ya elimino
      // bloques enteros; si llegan aqui es porque vinieron desemparejados.
      // Defensa-en-profundidad: tambien los ignoramos individualmente.
      continue;
    }
    if (!ALLOWED_TAGS.has(tok.tagName)) {
      // Tag no peligroso pero no whitelisted: unwrap (saltamos el tag,
      // dejamos contenido). Como tokenize emite tag de apertura y cierre
      // por separado, basta con no escribir nada -- el contenido (text
      // tokens entre medias) ya lo vamos a procesar igual.
      continue;
    }

    // Tag permitido. Reconstruimos con atributos saneados.
    if (tok.isClosing) {
      out.push(`</${tok.tagName}>`);
      continue;
    }

    const safeAttrs: string[] = [];
    if (tok.tagName === "a") {
      const href = tok.attrs["href"];
      if (href && isSafeHref(href)) {
        safeAttrs.push(`href="${escapeAttr(href)}"`);
        // Defensa contra tabnabbing + leakage de Referer.
        safeAttrs.push(`rel="noopener noreferrer"`);
        safeAttrs.push(`target="_blank"`);
      }
      // Si href no es seguro o no existe, emitimos <a> sin href.
      // El texto del link sigue visible pero no clickable.
    }

    // Tags void (br, hr) no llevan cierre.
    const isVoid = tok.tagName === "br" || tok.tagName === "hr";
    const attrStr = safeAttrs.length ? " " + safeAttrs.join(" ") : "";
    out.push(`<${tok.tagName}${attrStr}${isVoid ? " /" : ""}>`);
  }

  return out.join("");
}

// Pre-paso: elimina bloques completos de tags peligrosos (incluido su
// contenido). El tokenizer principal solo decide tag-a-tag y unwrap-ea
// el contenido entre `<script>` y `</script>` por defecto -- pero en
// `<script>alert(1)</script>` el contenido `alert(1)` no debe quedar
// visible.
//
// Estrategia: regex que matchea `<TAG ...>...</TAG>` para cada tag
// peligroso, case-insensitive, multiline. Reemplaza por "".
function stripDangerousBlocks(input: string): string {
  let result = input;
  for (const tag of DANGEROUS_TAGS) {
    // <tag ...> hasta </tag>, no greedy. Cubre tags self-closing y con
    // contenido. Si hay un tag mal cerrado, la regex no matchea y dejamos
    // que el tokenizer lo procese (drop el tag de apertura).
    const re = new RegExp(
      `<\\s*${tag}\\b[^>]*>[\\s\\S]*?<\\s*/\\s*${tag}\\s*>`,
      "gi",
    );
    result = result.replace(re, "");
    // Tambien self-closing del propio tag: <tag .../> o <tag>.
    // Cubre <link rel=stylesheet>, <meta>, etc.
    const reSelf = new RegExp(`<\\s*${tag}\\b[^>]*/?\\s*>`, "gi");
    result = result.replace(reSelf, "");
  }
  return result;
}

// API principal: combina stripDangerousBlocks (para eliminar bloques
// peligrosos enteros) + sanitizeBroadcastHtml (whitelist tag-por-tag).
export function cleanBroadcastHtml(input: string): string {
  if (!input) return "";
  // Limite de tamanyo: el check del schema ya impone <= 5000 chars,
  // pero defensivamente truncamos a 100 KB por si la migracion cambia.
  // 100 KB es ~ 25 paginas de texto -- mas de eso es atipico para mail.
  const MAX_INPUT_BYTES = 100 * 1024;
  const truncated = input.length > MAX_INPUT_BYTES
    ? input.substring(0, MAX_INPUT_BYTES)
    : input;
  return sanitizeBroadcastHtml(stripDangerousBlocks(truncated));
}
