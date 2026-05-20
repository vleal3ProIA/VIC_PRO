#Requires -Version 7.0
<#
================================================================================
 tool/fix.ps1 - Correcciones AUTOMATICAS y SEGURAS del proyecto Flutter
--------------------------------------------------------------------------------
 SOLO aplica transformaciones OFICIALES y seguras de la toolchain de Dart:
   1. flutter pub get
   2. dart fix --apply   (correcciones basadas en el AST: imports no usados,
                          const, prefer_..., etc. NUNCA por regex.)
   3. dart format        (formato canonico)
 Despues RE-VERIFICA con flutter analyze para garantizar que el proyecto
 sigue limpio tras las correcciones.

 Lo que este script NUNCA hace (a proposito, por seguridad):
   - Borrar "dead code" por heuristica de regex (rompe Riverpod / generado /
     reflexion / uso solo-en-tests).
   - Reescribir pubspec / workflows / arquitectura.
   - Tocar la logica de negocio.

 SEGURIDAD / REVERSIBILIDAD: el control de versiones (git) es el backup. El
 script muestra `git diff --stat` al final para que revises exactamente que
 cambio; revertir es `git checkout -- <archivo>` o `git restore .`.

 Salida: consola + audit_fix_report.txt + resumen OK/WARN/ERROR + exit 0/1.

 Uso:
   pwsh tool/fix.ps1
   pwsh tool/fix.ps1 -AllowDirty   # no avisar aunque el arbol git este sucio
================================================================================
#>
[CmdletBinding()]
param(
  [switch]$AllowDirty
)

$ErrorActionPreference = 'Continue'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot
$Report = Join-Path $ProjectRoot 'audit_fix_report.txt'

@(
  "Flutter project auto-fix report",
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
function Section { param([string]$T)
  Write-Host ""; Write-Host "==== $T ====" -ForegroundColor Cyan
  Add-Content -Path $Report -Value "" -Encoding utf8
  Add-Content -Path $Report -Value "==== $T ====" -Encoding utf8
}
function Invoke-Tool { param([string]$File,[string[]]$Args)
  $out = & $File @Args 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

# ─────────────────────── Pre-flight ───────────────────────
Section "Toolchain"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "Abortando: flutter no esta en PATH." -ForegroundColor Red; exit 1
}
$hasDart = [bool](Get-Command dart -ErrorAction SilentlyContinue)
$hasGit  = [bool](Get-Command git -ErrorAction SilentlyContinue)
Write-Line OK "flutter disponible."
if (-not $hasDart) { Write-Line ERROR "dart no esta en PATH -- no se pueden aplicar fixes." ; }

# Aviso si el arbol git esta sucio (para que el diff de los fixes sea claro).
if ($hasGit) {
  $st = (& git status --porcelain) | Out-String
  if ($st.Trim() -and -not $AllowDirty) {
    Write-Line WARN "El arbol git tiene cambios sin commitear. Los fixes se mezclaran con ellos; revisa el diff antes de commitear (o usa -AllowDirty para silenciar)."
  } elseif (-not $st.Trim()) {
    Write-Line OK "Arbol git limpio (los fixes seran faciles de revisar/revertir)."
  }
} else {
  Write-Line WARN "git no disponible: no hay red de seguridad de VCS. Revisa los cambios manualmente."
}

if (-not $hasDart) {
  Write-Host "Abortando: sin dart no hay fixes seguros." -ForegroundColor Red; exit 1
}

# ─────────────────────── 1) pub get ───────────────────────
Section "1. flutter pub get"
$pg = Invoke-Tool 'flutter' @('pub','get')
if ($pg.Code -eq 0) { Write-Line OK "Dependencias resueltas." }
else { Write-Line ERROR "flutter pub get FALLO (code $($pg.Code))." ; Add-Content $Report $pg.Out }

# ─────────────────────── 2) dart fix --apply ───────────────────────
Section "2. dart fix --apply (correcciones via AST)"
$df = Invoke-Tool 'dart' @('fix','--apply')
Add-Content $Report $df.Out
if ($df.Code -eq 0) {
  if ($df.Out -match 'Nothing to fix') { Write-Line OK "dart fix: nada que corregir." }
  else { Write-Line OK "dart fix aplicado. (Detalle en el reporte.)" }
} else {
  Write-Line WARN "dart fix devolvio code $($df.Code). Revisa el detalle en el reporte."
}

# ─────────────────────── 3) dart format ───────────────────────
Section "3. dart format"
$fm = Invoke-Tool 'dart' @('format','lib','test','tool')
if ($fm.Code -eq 0) {
  $changed = ($fm.Out -split "`n" | Where-Object { $_ -match '^Formatted ' }).Count
  Write-Line OK "dart format ejecutado."
} else {
  Write-Line WARN "dart format devolvio code $($fm.Code)."
}

# ─────────────────────── 4) Re-verificacion ───────────────────────
Section "4. Re-verificacion (flutter analyze)"
$an = Invoke-Tool 'flutter' @('analyze')
if ($an.Code -eq 0) {
  Write-Line OK "flutter analyze sigue limpio tras los fixes."
} else {
  Write-Line ERROR "flutter analyze NO esta limpio tras los fixes. Revisa el diff (git) y el output."
  Add-Content $Report ($an.Out -split "`n" | Select-Object -Last 40)
}

# ─────────────────────── 5) Diff resumen ───────────────────────
Section "5. Cambios aplicados (git diff --stat)"
if ($hasGit) {
  $diff = (& git diff --stat) | Out-String
  if ($diff.Trim()) {
    Add-Content $Report $diff
    Write-Host $diff
    Write-Line OK "Cambios listados arriba. Revisa con 'git diff' y commitea si te convencen."
  } else {
    Write-Line OK "Sin cambios en el arbol (no habia nada que arreglar)."
  }
}

# Sugerencias NO automatizables (informativo; nunca las aplica el script).
Section "Sugerencias (NO auto-aplicadas)"
$suggestions = @(
  "- Strings hardcodeados -> migrar a i18n (.arb) manualmente.",
  "- '!' (null-assertion) excesivos -> refactor manual a null-checks.",
  "- Dead code -> confirmar uso real (Riverpod/generado/tests) antes de borrar.",
  "- Rutas duplicadas -> unificar a mano (puede romper navegacion)."
) -join "`n"
Add-Content -Path $Report -Value $suggestions -Encoding utf8
Write-Line OK "Sugerencias no-automatizables registradas en el reporte."

# ─────────────────────── Resumen ───────────────────────
$result = if ($script:ERR -gt 0) { 'FAIL' } else { 'PASS' }
@(
  "",
  ("=" * 78),
  "TOTAL OK:    $($script:OK)",
  "TOTAL WARN:  $($script:WARN)",
  "TOTAL ERROR: $($script:ERR)",
  "RESULTADO FINAL: $result"
) | ForEach-Object { Add-Content -Path $Report -Value $_ -Encoding utf8 }
Write-Host ""
Write-Host ("=" * 78)
Write-Host "TOTAL OK:    $($script:OK)" -ForegroundColor Green
Write-Host "TOTAL WARN:  $($script:WARN)" -ForegroundColor Yellow
Write-Host "TOTAL ERROR: $($script:ERR)" -ForegroundColor Red
Write-Host "RESULTADO FINAL: $result" -ForegroundColor ($(if ($result -eq 'PASS') { 'Green' } else { 'Red' }))
Write-Host "Reporte: $Report"

if ($result -eq 'PASS') { exit 0 } else { exit 1 }
