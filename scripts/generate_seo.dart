// ============================================================================
// scripts/generate_seo.dart
// ----------------------------------------------------------------------------
// Sustituye los placeholders `__SEO_*__` en `web/index.html`,
// `web/robots.txt` y `web/sitemap.xml` con los valores reales del
// proyecto (commercial name, dominio, descripción, OG image).
//
// Se llama ANTES de `flutter build web` para que los archivos
// estaticos servidos por Apache (robots.txt, sitemap.xml) tengan el
// dominio correcto, y para que la index.html tenga title/description
// reales (no los placeholders) — esto es lo que ve un crawler que
// no ejecuta JS.
//
// Uso:
//
//   # Lee defaults de .env y los inyecta:
//   dart run scripts/generate_seo.dart
//
//   # O argumentos CLI:
//   dart run scripts/generate_seo.dart \
//     --site-url=https://tudominio.com \
//     --site-name="My SaaS" \
//     --description="The simplest way to manage X" \
//     --og-image=https://tudominio.com/og.png
//
// **Importante**: este script MUTA los archivos en `web/`. En CI/CD
// los archivos se restauran tras el build (git checkout). En local,
// recuerda hacer `git checkout web/` despues de inspeccionar el
// resultado para no commitear los valores especificos del despliegue.
// ============================================================================

import 'dart:io';

const _files = [
  'web/index.html',
  'web/robots.txt',
  'web/sitemap.xml',
];

void main(List<String> args) {
  final cli = _parseArgs(args);

  // Resolver valores: CLI > .env > defaults.
  final env = _readEnv();
  final siteUrl =
      _normalizeUrl(cli['site-url'] ?? env['SITE_URL'] ?? 'https://example.com');
  final siteName =
      cli['site-name'] ?? env['APP_NAME'] ?? 'myapp';
  final description = cli['description'] ??
      env['SEO_DESCRIPTION'] ??
      'A modern Flutter Web SaaS — auth, billing, multi-tenant, '
          'and everything you need to launch.';
  final keywords = cli['keywords'] ??
      env['SEO_KEYWORDS'] ??
      'saas, flutter, web app, multi-tenant, supabase, stripe';
  final ogImage = cli['og-image'] ??
      env['SEO_OG_IMAGE'] ??
      '$siteUrl/icons/Icon-512.png';

  final lastMod = DateTime.now().toUtc().toIso8601String().split('T').first;
  // Canonical = site URL sin slash final (para homepage; rutas concretas
  // usan el title runtime de meta_tags_sync.dart).
  final canonical = siteUrl;

  final replacements = <String, String>{
    '__SEO_TITLE__': '$siteName — $description'.length > 60
        ? siteName
        : '$siteName — $description',
    '__SEO_SITE_NAME__': siteName,
    '__SEO_DESCRIPTION__': description,
    '__SEO_KEYWORDS__': keywords,
    '__SEO_CANONICAL__': canonical,
    '__SEO_SITE_URL__': siteUrl,
    '__SEO_OG_IMAGE__': ogImage,
    '__SEO_LASTMOD__': lastMod,
  };

  for (final path in _files) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('⚠  skipping $path — not found');
      continue;
    }
    var content = file.readAsStringSync();
    var replaced = 0;
    for (final entry in replacements.entries) {
      final before = content;
      content = content.replaceAll(entry.key, _xmlEscape(entry.value));
      if (before != content) replaced++;
    }
    file.writeAsStringSync(content);
    stdout.writeln(
      '✓ $path  (${replaced.toString().padLeft(2)} placeholder(s) replaced)',
    );
  }

  stdout.writeln('\nDone. Now run: flutter build web --release');
}

Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final eq = arg.indexOf('=');
    if (eq < 0) continue;
    out[arg.substring(2, eq)] = arg.substring(eq + 1);
  }
  return out;
}

/// Minimal .env reader — solo busca claves al inicio de línea, soporta
/// comentarios con `#` y quotes opcionales. No es un parser completo de
/// dotenv pero cubre el formato del .env.example del proyecto.
Map<String, String> _readEnv() {
  final file = File('.env');
  if (!file.existsSync()) return const {};
  final out = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    out[key] = value;
  }
  return out;
}

String _normalizeUrl(String url) {
  var s = url.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Escapa caracteres que pueden romper HTML/XML cuando aparecen en
/// atributos. Es el mínimo viable — no escapamos < > para no romper
/// HTML/XML válido que pudiera venir en la descripción.
String _xmlEscape(String s) {
  return s.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
}
