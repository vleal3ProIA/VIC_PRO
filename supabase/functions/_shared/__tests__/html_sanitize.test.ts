// ============================================================================
// Tests Deno: html_sanitize.ts (PR-D)
// ----------------------------------------------------------------------------
// Cobertura del sanitizer HTML que protege contra XSS en broadcasts
// (PR-E). Sin estos tests, un refactor que aflojara el whitelist o que
// permitiera javascript: en hrefs no se detectaria hasta que algun
// cliente de email lo ejecutara.
//
// Como ejecutar:
//   cd supabase/functions
//   deno test --allow-read _shared/__tests__/html_sanitize.test.ts
// ============================================================================

import {
  assertEquals,
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  cleanBroadcastHtml,
  sanitizeBroadcastHtml,
} from "../html_sanitize.ts";

// ─────────────────────── Whitelist de tags ───────────────────────

Deno.test("acepta tags whitelisted (p, strong, em, h1-h4, a, br, hr, ul, ol, li, blockquote)", () => {
  const input =
    "<p>Hola <strong>mundo</strong> <em>cursiva</em></p>"
    + "<h1>Titulo</h1><h2>Sub</h2><h3>Sub2</h3><h4>Sub3</h4>"
    + "<ul><li>A</li><li>B</li></ul>"
    + "<ol><li>1</li></ol>"
    + "<blockquote>Cita</blockquote>"
    + "<br><hr>";
  const out = cleanBroadcastHtml(input);
  // Cada tag whitelist debe estar presente en la salida (o cierto en
  // su forma void).
  for (const tag of ["p", "strong", "em", "h1", "h2", "h3", "h4",
                     "ul", "ol", "li", "blockquote"]) {
    assertStringIncludes(out, `<${tag}`);
    assertStringIncludes(out, `</${tag}>`);
  }
  // Tags void
  assertStringIncludes(out, "<br");
  assertStringIncludes(out, "<hr");
});

Deno.test("preserva texto basico sin tags", () => {
  const out = cleanBroadcastHtml("Hola mundo, sin tags.");
  assertEquals(out, "Hola mundo, sin tags.");
});

// ─────────────────────── Tags peligrosos eliminados ───────────────────────

Deno.test("ELIMINA <script> completo con su contenido", () => {
  const input = "<p>Antes</p><script>alert(1)</script><p>Despues</p>";
  const out = cleanBroadcastHtml(input);
  assert(!out.includes("script"));
  assert(!out.includes("alert"));
  assertStringIncludes(out, "Antes");
  assertStringIncludes(out, "Despues");
});

Deno.test("ELIMINA <style> con su CSS interno", () => {
  const input = "Hola<style>body{display:none}</style>mundo";
  const out = cleanBroadcastHtml(input);
  assert(!out.includes("style"));
  assert(!out.includes("display"));
  assertStringIncludes(out, "Hola");
  assertStringIncludes(out, "mundo");
});

Deno.test("ELIMINA <iframe>, <object>, <embed>, <link>", () => {
  const cases = [
    `<iframe src="evil.com"></iframe>`,
    `<object data="evil.swf"></object>`,
    `<embed src="evil.swf">`,
    `<link rel="stylesheet" href="evil.css">`,
  ];
  for (const html of cases) {
    const out = cleanBroadcastHtml(html);
    assert(
      !out.toLowerCase().includes("iframe")
        && !out.toLowerCase().includes("object")
        && !out.toLowerCase().includes("embed")
        && !out.toLowerCase().includes("link"),
      `Tag peligroso encontrado en salida: ${out}`,
    );
  }
});

Deno.test("ELIMINA <svg> (vector XSS clasico via <svg onload>)", () => {
  const input = `<svg onload="alert(1)"><rect/></svg>Texto`;
  const out = cleanBroadcastHtml(input);
  assert(!out.toLowerCase().includes("svg"));
  assert(!out.includes("onload"));
  assert(!out.includes("alert"));
  assertStringIncludes(out, "Texto");
});

Deno.test("ELIMINA form / input / button", () => {
  const input = `<form action="evil.com"><input name="x"><button>Send</button></form>`;
  const out = cleanBroadcastHtml(input);
  assert(!out.toLowerCase().includes("form"));
  assert(!out.toLowerCase().includes("input"));
  assert(!out.toLowerCase().includes("button"));
});

// ─────────────────────── href schemes ───────────────────────

Deno.test("ACEPTA href https con rel y target forzados", () => {
  const out = cleanBroadcastHtml(
    '<a href="https://example.com">Click</a>',
  );
  assertStringIncludes(out, 'href="https://example.com"');
  assertStringIncludes(out, 'rel="noopener noreferrer"');
  assertStringIncludes(out, 'target="_blank"');
});

Deno.test("ACEPTA href http", () => {
  const out = cleanBroadcastHtml(
    '<a href="http://example.com">Click</a>',
  );
  assertStringIncludes(out, 'href="http://example.com"');
});

Deno.test("ACEPTA href mailto", () => {
  const out = cleanBroadcastHtml(
    '<a href="mailto:user@example.com">Mail</a>',
  );
  assertStringIncludes(out, 'href="mailto:user@example.com"');
});

Deno.test("RECHAZA href javascript:", () => {
  const out = cleanBroadcastHtml(
    '<a href="javascript:alert(1)">Click</a>',
  );
  assert(!out.toLowerCase().includes("javascript"));
  // El tag <a> SIN href se conserva -- el texto sigue visible pero no
  // es clickable.
  assertStringIncludes(out, "Click");
});

Deno.test("RECHAZA href data:", () => {
  const out = cleanBroadcastHtml(
    '<a href="data:text/html,<script>alert(1)</script>">X</a>',
  );
  assertEquals(out.includes('href="data:'), false);
});

Deno.test("RECHAZA href vbscript:", () => {
  const out = cleanBroadcastHtml(
    '<a href="vbscript:msgbox(1)">X</a>',
  );
  assert(!out.toLowerCase().includes("vbscript"));
});

Deno.test("RECHAZA bypass javascript con whitespace y control chars", () => {
  // java\nscript:alert(1) -- algunos parsers eliminan los \n.
  const sneaky = `<a href="java\nscript:alert(1)">X</a>`;
  const out = cleanBroadcastHtml(sneaky);
  assert(!out.toLowerCase().includes("javascript"));
  assert(!out.includes("alert"));
});

Deno.test("RECHAZA bypass con mayusculas (JavaScript:)", () => {
  const out = cleanBroadcastHtml(
    '<a href="JavaScript:alert(1)">X</a>',
  );
  assert(!out.toLowerCase().includes("javascript:"));
});

Deno.test("ACEPTA URLs relativas (mismo origen)", () => {
  const cases = [
    `<a href="/page">Internal</a>`,
    `<a href="#section">Anchor</a>`,
    `<a href="./relative">Rel</a>`,
    `<a href="../up">Up</a>`,
  ];
  for (const html of cases) {
    const out = cleanBroadcastHtml(html);
    assertStringIncludes(out, "<a href=");
    assertStringIncludes(out, 'rel="noopener noreferrer"');
  }
});

// ─────────────────────── Atributos peligrosos ───────────────────────

Deno.test("ELIMINA atributo style", () => {
  const out = cleanBroadcastHtml(
    `<p style="display:none">Texto</p>`,
  );
  assert(!out.includes("style"));
  assert(!out.includes("display"));
  assertStringIncludes(out, "Texto");
});

Deno.test("ELIMINA atributos on* (onclick, onerror, onload)", () => {
  const cases = [
    `<p onclick="alert(1)">x</p>`,
    `<p onerror="alert(1)">x</p>`,
    `<a href="https://x.com" onmouseover="alert(1)">x</a>`,
  ];
  for (const html of cases) {
    const out = cleanBroadcastHtml(html);
    assert(!out.toLowerCase().includes("onclick"));
    assert(!out.toLowerCase().includes("onerror"));
    assert(!out.toLowerCase().includes("onmouseover"));
    assert(!out.includes("alert"));
  }
});

Deno.test("ELIMINA <img onerror=...> (img no esta en whitelist tampoco)", () => {
  const out = cleanBroadcastHtml(
    `<img src="x" onerror="alert(1)">`,
  );
  assert(!out.toLowerCase().includes("img"));
  assert(!out.includes("onerror"));
});

// ─────────────────────── Unwrap tags benignos no whitelisted ───────────────────────

Deno.test("UNWRAP <div>, <span>, <table> (no peligrosos, no whitelisted)", () => {
  const input = "<div>Hola <span>mundo</span></div>";
  const out = cleanBroadcastHtml(input);
  // El contenido se conserva, las etiquetas div/span se quitan.
  assert(!out.includes("<div>"));
  assert(!out.includes("</div>"));
  assert(!out.includes("<span>"));
  assert(!out.includes("</span>"));
  assertStringIncludes(out, "Hola");
  assertStringIncludes(out, "mundo");
});

// ─────────────────────── Escape de texto ───────────────────────

Deno.test("ESCAPA caracteres < > & en texto plano", () => {
  const out = cleanBroadcastHtml(
    "a < b && c > d",
  );
  // & se escapa a &amp;, < a &lt;, etc. NO debe aparecer un < literal
  // (excepto como parte de "&lt;" / "&amp;lt;" ya escapado).
  assertEquals(
    out,
    "a &lt; b &amp;&amp; c &gt; d",
  );
});

Deno.test("comentarios HTML <!-- ... --> se eliminan", () => {
  const input = "<p>Antes</p><!-- [if IE]><script>x</script><![endif] --><p>Despues</p>";
  const out = cleanBroadcastHtml(input);
  assert(!out.includes("<!--"));
  assert(!out.includes("script"));
  assertStringIncludes(out, "Antes");
  assertStringIncludes(out, "Despues");
});

// ─────────────────────── Robustness ───────────────────────

Deno.test("entrada vacia devuelve string vacio", () => {
  assertEquals(cleanBroadcastHtml(""), "");
});

Deno.test("entrada solo <script>...</script> -> string vacio", () => {
  const out = cleanBroadcastHtml("<script>alert(1)</script>");
  // Despues de strip + sanitize no queda nada.
  assertEquals(out.trim(), "");
});

Deno.test("tag mal cerrado se procesa sin crash", () => {
  // <p sin cerrar
  const out = cleanBroadcastHtml("<p>Texto sin cerrar");
  // No debe lanzar; el resultado puede ser feo pero presente.
  assertStringIncludes(out, "Texto sin cerrar");
});

Deno.test("entrada extremadamente larga se trunca a 100 KB", () => {
  // Construimos 200 KB de texto.
  const huge = "a".repeat(200 * 1024);
  const out = cleanBroadcastHtml(huge);
  // Output debe ser <= 100 KB (porque truncamos antes de sanitizar).
  assert(out.length <= 100 * 1024);
});
