#Requires -Version 7.0
<#
================================================================================
 tool/audit.ps1 - Auditoria read-only del proyecto Flutter (dev / CI)
--------------------------------------------------------------------------------
 Filosofia: NO reimplementamos analisis de Dart con regex (fragil y con falsos
 positivos). Envolvemos las herramientas OFICIALES (`flutter analyze`,
 `dart format`, `dart fix`, `flutter test`, `flutter pub outdated`) + un puñado
 de checks de seguridad/higiene que esas herramientas no cubren (secretos en
 fuente, assets gigantes, http://, sanity de .gitignore/CI).

 SOLO LECTURA: este script NUNCA modifica el codigo. Para correcciones seguras
 usa `tool/fix.ps1` (que solo invoca `dart fix --apply` + `dart format`).

 Salida:
   - Consola con progreso coloreado.
   - audit_report.txt en la raiz del proyecto.
   - Resumen TOTAL OK/WARN/ERROR + RESULTADO FINAL PASS/FAIL.
   - Exit code 0 (PASS) / 1 (FAIL).

 FAIL (exit 1) si: `flutter pub get` falla, `flutter analyze` tiene errores,
 los tests fallan, o se detecta un secreto de alta confianza en el fuente.
 Los WARN (deps desactualizadas, formato pendiente, assets grandes, etc.) NO
 hacen fallar el build -- son informativos.

 Uso:
   pwsh tool/audit.ps1
   pwsh tool/audit.ps1 -SkipTests            # mas rapido, sin flutter test
   pwsh tool/audit.ps1 -AssetMaxKB 2048
================================================================================
#>
[CmdletBinding()]
param(
  [int]$AssetMaxKB = 1024,
  [int]$DartFileMaxLines = 600,
  [switch]$SkipTests
)

$ErrorActionPreference = 'Continue'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot
$Report = Join-Path $ProjectRoot 'audit_report.txt'

# Reset del reporte con cabecera.
@(
  "Flutter project audit report",
  "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')",
  "Root: $ProjectRoot",
  ("=" * 78)
) | Set-Content -Path $Report -Encoding utf8

$script:OK = 0; $script:WARN = 0; $script:ERR = 0

function Write-Line {
  param([ValidateSet('OK','WARN','ERROR')] [string]$Level, [string]$Msg)
  $line = "[$Level] $Msg"
  switch ($Level) {
    'OK'    { $script:OK++;   Write-Host $line -ForegroundColor Green }
    'WARN'  { $script:WARN++; Write-Host $line -ForegroundColor Yellow }
    'ERROR' { $script:ERR++;  Write-Host $line -ForegroundColor Red }
  }
  Add-Content -Path $Report -Value $line -Encoding utf8
}

function Section {
  param([string]$Title)
  $bar = "==== $Title ===="
  Write-Host ""
  Write-Host $bar -ForegroundColor Cyan
  Add-Content -Path $Report -Value "" -Encoding utf8
  Add-Content -Path $Report -Value $bar -Encoding utf8
}

function Invoke-Tool {
  # Ejecuta un comando y devuelve [pscustomobject]@{ Code; Out }.
  param([string]$File, [string[]]$Args)
  $out = & $File @Args 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

# ─────────────────────── Pre-flight: herramientas ───────────────────────
Section "Toolchain"
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
$dart    = Get-Command dart -ErrorAction SilentlyContinue
if (-not $flutter) { Write-Line ERROR "flutter no esta en PATH -- no se puede auditar." }
else { Write-Line OK "flutter disponible: $($flutter.Source)" }
if (-not $dart) { Write-Line WARN "dart no esta en PATH (algunos checks se saltaran)." }
else { Write-Line OK "dart disponible: $($dart.Source)" }
if (-not $flutter) {
  Write-Host "Abortando: sin flutter no hay auditoria." -ForegroundColor Red
  exit 1
}

# ─────────────────────── BLOQUE 1 - Estructura ───────────────────────
Section "1. Estructura de proyecto"
foreach ($d in @('lib','test','web','supabase')) {
  if (Test-Path (Join-Path $ProjectRoot $d)) { Write-Line OK "Existe carpeta: $d/" }
  else { Write-Line WARN "Falta carpeta esperada: $d/" }
}
# .dart "sueltos": flaggeamos solo los que NO esten en carpetas de codigo
# fuente propio (allowed) ni en carpetas generadas / de plataforma / build
# (ignored). Asi evitamos falsos positivos con plugin registrants, copias
# en build/ y .dart_tool/, y runners de plataforma.
$allowedDirs = @('lib','test','tool','integration_test','scripts')
$ignoredDirs = @('build','.dart_tool','windows','linux','macos','android','ios','.git','.idea')
$strayDart = Get-ChildItem -Path $ProjectRoot -Recurse -Filter *.dart -File -ErrorAction SilentlyContinue |
  Where-Object {
    $rel = $_.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')
    $top = ($rel -split '[\\/]')[0]
    ($top -notin $allowedDirs) -and ($top -notin $ignoredDirs)
  }
if ($strayDart) {
  foreach ($f in $strayDart) { Write-Line WARN "Dart fuera de lib/test/tool: $($f.Name)" }
} else { Write-Line OK "Sin .dart sueltos fuera de las carpetas convencionales." }

# ─────────────────────── BLOQUE 2 - Dependencias ───────────────────────
Section "2. Dependencias (pub get / outdated)"
$pg = Invoke-Tool 'flutter' @('pub','get')
if ($pg.Code -eq 0) { Write-Line OK "flutter pub get OK." }
else { Write-Line ERROR "flutter pub get FALLO (code $($pg.Code))." ; Add-Content $Report $pg.Out }

$od = Invoke-Tool 'flutter' @('pub','outdated')
# Contamos lineas de paquetes desactualizados (heuristica suave; informativo).
$odLines = ($od.Out -split "`n") | Where-Object { $_ -match '\*?\d+\.\d+\.\d+' }
if ($odLines.Count -gt 0) {
  Write-Line WARN "Hay dependencias desactualizadas (revisa 'flutter pub outdated'). No bloquea."
} else {
  Write-Line OK "Sin dependencias desactualizadas relevantes."
}

# ─────────────────────── BLOQUE 3 - Analisis estatico ───────────────────────
Section "3. Analisis estatico (flutter analyze)"
$an = Invoke-Tool 'flutter' @('analyze')
$anLines = $an.Out -split "`n"
$errN  = ($anLines | Where-Object { $_ -match '(?i)^\s*error\s*[-•]' }).Count
$warnN = ($anLines | Where-Object { $_ -match '(?i)^\s*warning\s*[-•]' }).Count
$infoN = ($anLines | Where-Object { $_ -match '(?i)^\s*info\s*[-•]' }).Count
if ($an.Code -eq 0 -and ($errN + $warnN + $infoN) -eq 0) {
  Write-Line OK "flutter analyze: No issues found."
} else {
  if ($errN  -gt 0) { Write-Line ERROR "flutter analyze: $errN error(es)." }
  if ($warnN -gt 0) { Write-Line WARN  "flutter analyze: $warnN warning(s)." }
  if ($infoN -gt 0) { Write-Line WARN  "flutter analyze: $infoN info(s)." }
  if (($errN + $warnN + $infoN) -eq 0 -and $an.Code -ne 0) {
    Write-Line ERROR "flutter analyze fallo (code $($an.Code))."
  }
  Add-Content $Report $an.Out
}

# ─────────────────────── BLOQUE 4 - Formato ───────────────────────
Section "4. Formato (dart format --set-exit-if-changed)"
if ($dart) {
  $fmt = Invoke-Tool 'dart' @('format','--output=none','--set-exit-if-changed','lib','test','tool')
  if ($fmt.Code -eq 0) { Write-Line OK "Codigo correctamente formateado." }
  else { Write-Line WARN "Hay ficheros sin formatear. Corrige con: tool/fix.ps1 (dart format)." }
} else { Write-Line WARN "dart no disponible: salto check de formato." }

# ─────────────────────── BLOQUE 5 - Auto-fixables ───────────────────────
Section "5. Issues auto-corregibles (dart fix --dry-run)"
# Informativo: `flutter analyze` (bloque 3) es el gate REAL de lints. Lo que
# `dart fix` sugiera de mas suele ser ruido en codigo generado (l10n) que se
# resuelve solo con tool/fix.ps1. Por eso NO es un WARN bloqueante.
if ($dart) {
  $df = Invoke-Tool 'dart' @('fix','--dry-run')
  if ($df.Out -match 'Nothing to fix' -or $df.Out -match 'computed 0 fixes') {
    Write-Line OK "dart fix: nada que corregir."
  } else {
    Write-Line OK "dart fix sugiere correcciones (informativo; ejecuta tool/fix.ps1 si quieres aplicarlas)."
    Add-Content $Report $df.Out
  }
} else { Write-Line OK "dart no disponible: salto dart fix --dry-run (informativo)." }

# ─────────────────────── BLOQUE 6 - Tests ───────────────────────
Section "6. Tests (flutter test)"
if ($SkipTests) {
  # Omitir tests es una eleccion explicita del usuario (-SkipTests), no un
  # defecto -> informativo, no WARN. La auditoria completa SI los corre.
  Write-Line OK "Tests OMITIDOS por -SkipTests (informativo; ejecuta sin el flag para correrlos)."
} else {
  $ts = Invoke-Tool 'flutter' @('test','--no-pub')
  if ($ts.Code -eq 0) { Write-Line OK "flutter test: todos los tests pasan." }
  else { Write-Line ERROR "flutter test FALLO (code $($ts.Code))." ; Add-Content $Report ($ts.Out -split "`n" | Select-Object -Last 30) }
}

# ─────────────────────── BLOQUE 7 - Secretos en fuente ───────────────────────
Section "7. Secretos / credenciales en codigo fuente"
# Escaneamos fuente (NO test/, NO *.example, NO *.md). Patrones de ALTA
# confianza -> ERROR. Es read-only: solo reporta file:line para revision.
$scanDirs = @('lib','supabase','scripts','web') | Where-Object { Test-Path (Join-Path $ProjectRoot $_) }
$secretPatterns = @(
  @{ Name = 'Stripe live secret'; Rx = 'sk_live_[0-9A-Za-z]{10,}' },
  @{ Name = 'GitHub PAT';         Rx = '(ghp|gho|ghu|ghs|ghr)_[0-9A-Za-z]{20,}' },
  @{ Name = 'GitHub fine PAT';    Rx = 'github_pat_[0-9A-Za-z_]{20,}' },
  @{ Name = 'AWS access key';     Rx = 'AKIA[0-9A-Z]{16}' },
  @{ Name = 'Private key block';  Rx = '-----BEGIN [A-Z ]*PRIVATE KEY-----' }
)
$secretsFound = 0
foreach ($dir in $scanDirs) {
  $files = Get-ChildItem -Path (Join-Path $ProjectRoot $dir) -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -notin @('.md','.png','.jpg','.jpeg','.gif','.webp','.svg','.lock') -and $_.Name -notlike '*.example' }
  foreach ($f in $files) {
    $content = Get-Content -Path $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    foreach ($p in $secretPatterns) {
      if ($content -match $p.Rx) {
        $secretsFound++
        $rel = $f.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')
        Write-Line ERROR "Posible secreto ($($p.Name)) en: $rel"
      }
    }
  }
}
if ($secretsFound -eq 0) { Write-Line OK "Sin secretos de alta confianza en el fuente." }

# ─────────────────────── BLOQUE 8 - http:// inseguro ───────────────────────
Section "8. URLs http:// (deberian ser https://)"
$httpHits = 0
foreach ($dir in @('lib','supabase')) {
  $p = Join-Path $ProjectRoot $dir
  if (-not (Test-Path $p)) { continue }
  $files = Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Extension -in @('.dart','.ts') -and
      $_.FullName -notmatch '[\\/]generated[\\/]' -and
      $_.FullName -notmatch '[\\/]__tests__[\\/]' -and
      $_.Name -notmatch '_test\.(dart|ts)$'
    }
  foreach ($f in $files) {
    $ln = 0
    foreach ($line in (Get-Content $f.FullName -ErrorAction SilentlyContinue)) {
      $ln++
      $t = $line.TrimStart()
      # Saltar comentarios (// ... , * ... , # ...).
      if ($t -match '^(//|\*|#|/\*)') { continue }
      # Flaggear http:// SOLO si va seguido de un host real -- NO si es un
      # literal entrecomillado ('http://' / "http://", usado en validaciones
      # tipo startsWith) ni dominios conocidos seguros.
      if ($line -match "http://(?!localhost|127\.0\.0\.1|schemas\.|www\.w3\.org|['""])") {
        $httpHits++
        $rel = $f.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')
        Write-Line WARN "http:// en $rel : $ln"
      }
    }
  }
}
if ($httpHits -eq 0) { Write-Line OK "Sin URLs http:// inseguras en lib/supabase." }

# ─────────────────────── BLOQUE 9 - Assets grandes ───────────────────────
Section "9. Assets grandes (> $AssetMaxKB KB)"
$assetsDir = Join-Path $ProjectRoot 'assets'
if (Test-Path $assetsDir) {
  $big = Get-ChildItem -Path $assetsDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt ($AssetMaxKB * 1024) }
  if ($big) {
    foreach ($f in $big) { Write-Line WARN ("Asset grande {0} KB: {1}" -f [int]($f.Length/1024), $f.Name) }
  } else { Write-Line OK "Sin assets por encima del umbral." }
} else { Write-Line OK "No hay carpeta assets/ (nada que revisar)." }

# ─────────────────────── BLOQUE 10 - Ficheros Dart enormes ───────────────────────
Section "10. Ficheros Dart muy largos (> $DartFileMaxLines lineas)"
$libDir = Join-Path $ProjectRoot 'lib'
# Excluimos codigo GENERADO (l10n, *.g.dart, *.freezed.dart): su tamaño no
# es deuda tecnica -- lo produce build_runner / gen-l10n.
$bigDart = Get-ChildItem -Path $libDir -Recurse -Filter *.dart -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '[\\/]generated[\\/]' -and $_.Name -notmatch '\.(g|freezed)\.dart$' } |
  ForEach-Object {
    $n = (Get-Content $_.FullName -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
    [pscustomobject]@{ File = $_; Lines = $n }
  } | Where-Object { $_.Lines -gt $DartFileMaxLines }
# Metrica INFORMATIVA (no es un defecto): listamos los ficheros grandes en
# el reporte pero NO como WARN. Dividir es refactor opcional, no obligatorio.
if ($bigDart) {
  foreach ($x in $bigDart) {
    $rel = $x.File.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')
    Add-Content -Path $Report -Value ("    - {0} lineas: {1}" -f $x.Lines, $rel) -Encoding utf8
  }
  Write-Line OK "$($bigDart.Count) fichero(s) > $DartFileMaxLines lineas (informativo; ver detalle en el reporte)."
} else { Write-Line OK "Sin ficheros Dart por encima del umbral." }

# ─────────────────────── BLOQUE 11 - Configuracion ───────────────────────
Section "11. Configuracion (.gitignore / pubspec / analysis_options)"
foreach ($f in @('pubspec.yaml','analysis_options.yaml','.gitignore')) {
  if (Test-Path (Join-Path $ProjectRoot $f)) { Write-Line OK "Existe: $f" }
  else { Write-Line WARN "Falta: $f" }
}
$gi = Get-Content (Join-Path $ProjectRoot '.gitignore') -Raw -ErrorAction SilentlyContinue
foreach ($must in @('.env','build/','*.bak')) {
  if ($gi -and ($gi -match [regex]::Escape($must))) { Write-Line OK ".gitignore cubre: $must" }
  else { Write-Line WARN ".gitignore NO cubre: $must" }
}

# ─────────────────────── BLOQUE 12 - CI/CD ───────────────────────
Section "12. CI/CD (.github/workflows)"
$wfDir = Join-Path $ProjectRoot '.github/workflows'
if (Test-Path $wfDir) {
  $wf = Get-ChildItem -Path $wfDir -Filter *.yml -File -ErrorAction SilentlyContinue
  if ($wf) {
    Write-Line OK "$($wf.Count) workflow(s) de GitHub Actions."
    $allText = ($wf | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
    if ($allText -match 'flutter analyze') { Write-Line OK "CI ejecuta flutter analyze." } else { Write-Line WARN "Ningun workflow ejecuta flutter analyze." }
    if ($allText -match 'flutter test')    { Write-Line OK "CI ejecuta flutter test." }    else { Write-Line WARN "Ningun workflow ejecuta flutter test." }
    if ($allText -match 'flutter build')   { Write-Line OK "CI hace flutter build." }       else { Write-Line WARN "Ningun workflow hace flutter build." }
  } else { Write-Line WARN "Carpeta de workflows vacia." }
} else { Write-Line WARN "Sin .github/workflows (no hay CI)." }

# ─────────────────────── BLOQUE 13 - Higiene (TODO/FIXME) ───────────────────────
Section "13. Higiene de codigo (TODO / FIXME)"
$dartFiles = Get-ChildItem -Path $libDir -Recurse -File -Filter *.dart -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '[\\/]generated[\\/]' }
$todo = $dartFiles | Select-String -Pattern '\b(TODO|FIXME|HACK|XXX)\b' -ErrorAction SilentlyContinue
# Metrica INFORMATIVA: los TODO/FIXME son parte normal del desarrollo, no un
# defecto. Reportamos el conteo como [OK], no como WARN.
if ($todo) { Write-Line OK "$($todo.Count) marcador(es) TODO/FIXME/HACK en lib/ (informativo)." }
else { Write-Line OK "Sin marcadores TODO/FIXME en lib/." }

# ─────────────────────── Resumen ───────────────────────
$result = if ($script:ERR -gt 0) { 'FAIL' } else { 'PASS' }
$summary = @(
  "",
  ("=" * 78),
  "TOTAL OK:    $($script:OK)",
  "TOTAL WARN:  $($script:WARN)",
  "TOTAL ERROR: $($script:ERR)",
  "RESULTADO FINAL: $result"
)
$summary | ForEach-Object { Add-Content -Path $Report -Value $_ -Encoding utf8 }
Write-Host ""
Write-Host ("=" * 78)
Write-Host "TOTAL OK:    $($script:OK)" -ForegroundColor Green
Write-Host "TOTAL WARN:  $($script:WARN)" -ForegroundColor Yellow
Write-Host "TOTAL ERROR: $($script:ERR)" -ForegroundColor Red
Write-Host "RESULTADO FINAL: $result" -ForegroundColor ($(if ($result -eq 'PASS') { 'Green' } else { 'Red' }))
Write-Host "Reporte: $Report"

if ($result -eq 'PASS') { exit 0 } else { exit 1 }
