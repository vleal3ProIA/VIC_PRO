// ============================================================================
// Helper compartido: cliente VirusTotal API v3 (PR-C)
// ----------------------------------------------------------------------------
// Wrapper minimo sobre la REST API de VirusTotal v3 para escanear los
// uploads del bucket. Lo usa la Edge Function `scan-upload`.
//
// **Free tier limits**:
//   - 4 requests / minuto.
//   - 500 lookups / dia.
//   - 32 MB max por archivo subido.
//
// **Estrategia de bajo coste**:
//   1. Primero hacemos `GET /files/{sha256}` (lookup por hash). Esto NO
//      consume cuota de uploads y devuelve resultado inmediato si VT ya
//      ha visto el archivo antes (caso comun -- la mayoria de PDFs,
//      imagenes y docs estandar estan en su BD).
//   2. Si el lookup devuelve 404, subimos el archivo con
//      `POST /files` (sube el binario, devuelve analysis id).
//   3. Polleamos `GET /analyses/{id}` hasta que `attributes.status ===
//      'completed'` o timeout. Backoff: 3s -> 5s -> 8s -> 13s -> 21s.
//
// **Variables de entorno**:
//   - VIRUSTOTAL_API_KEY  (obligatoria; sin esta, el helper devuelve
//     status='skipped' con motivo `vt_not_configured`).
// ============================================================================

const VT_BASE = "https://www.virustotal.com/api/v3";
const VT_MAX_FILE_BYTES = 32 * 1024 * 1024; // 32 MB free tier
const POLL_TIMEOUT_MS = 90 * 1000; // 90s total
const POLL_DELAYS_MS = [3000, 5000, 8000, 13000, 21000, 21000, 21000];

export type VtScanStatus = "clean" | "suspicious" | "error" | "skipped";

export interface VtScanResult {
  status: VtScanStatus;
  /// Detalle estructurado que se persiste en `uploads.virus_scan_result`.
  /// Para 'clean'/'suspicious' incluye stats; para 'error'/'skipped'
  /// incluye motivo + detalle.
  result: Record<string, unknown>;
}

/// Punto de entrada principal. Recibe sha256 (hex 64 chars) + bytes
/// opcionales (necesarios solo si VT no conoce el hash) + filename y
/// mime para el upload. Devuelve un `VtScanResult` listo para escribir
/// a la BD.
///
/// **Idempotente**: llamar varias veces con el mismo hash NO consume
/// upload de cuota -- el lookup va siempre primero.
export async function scanFileVirusTotal({
  sha256,
  bytes,
  filename,
  mimeType,
}: {
  sha256: string;
  bytes: Uint8Array | null; // null si no podemos volver a descargarlo
  filename: string;
  mimeType: string;
}): Promise<VtScanResult> {
  const apiKey = Deno.env.get("VIRUSTOTAL_API_KEY");
  if (!apiKey) {
    return {
      status: "skipped",
      result: {
        reason: "vt_not_configured",
        note: "VIRUSTOTAL_API_KEY no esta seteado en Supabase secrets.",
      },
    };
  }

  // 1) Lookup por hash. Free, no consume cuota de uploads.
  const lookupRes = await fetch(`${VT_BASE}/files/${sha256}`, {
    headers: { "x-apikey": apiKey },
  });

  if (lookupRes.status === 200) {
    const data = await lookupRes.json();
    return _interpretFileObject(data, sha256);
  }
  if (lookupRes.status === 401) {
    return {
      status: "error",
      result: {
        reason: "vt_unauthorized",
        note: "API key invalida o revocada.",
      },
    };
  }
  if (lookupRes.status === 429) {
    return {
      status: "error",
      result: {
        reason: "vt_rate_limited",
        note: "Free tier excedido (4 req/min o 500/dia).",
      },
    };
  }
  // 404 = VT no conoce el hash. Subimos.
  if (lookupRes.status !== 404) {
    return {
      status: "error",
      result: {
        reason: "vt_lookup_unexpected_status",
        status_code: lookupRes.status,
      },
    };
  }

  // 2) No conocido -> subir. Pero solo si tenemos los bytes y caben.
  if (!bytes) {
    return {
      status: "skipped",
      result: {
        reason: "vt_unknown_hash_no_bytes",
        note: "VT no conoce el hash y no tenemos bytes para subir.",
      },
    };
  }
  if (bytes.byteLength > VT_MAX_FILE_BYTES) {
    return {
      status: "skipped",
      result: {
        reason: "vt_file_too_large",
        note: `Free tier acepta hasta ${VT_MAX_FILE_BYTES} bytes; archivo es ${bytes.byteLength}.`,
      },
    };
  }

  // Crear multipart manualmente. La SDK de fetch en Deno acepta FormData
  // pero queremos control total sobre boundary y headers.
  const form = new FormData();
  form.append(
    "file",
    new Blob([bytes], { type: mimeType }),
    filename,
  );
  const uploadRes = await fetch(`${VT_BASE}/files`, {
    method: "POST",
    headers: { "x-apikey": apiKey },
    body: form,
  });
  if (uploadRes.status === 429) {
    return {
      status: "error",
      result: { reason: "vt_rate_limited_upload" },
    };
  }
  if (uploadRes.status !== 200) {
    const body = await _safeJson(uploadRes);
    return {
      status: "error",
      result: {
        reason: "vt_upload_failed",
        status_code: uploadRes.status,
        body,
      },
    };
  }
  const uploadData = await uploadRes.json();
  const analysisId = uploadData?.data?.id as string | undefined;
  if (!analysisId) {
    return {
      status: "error",
      result: { reason: "vt_upload_no_analysis_id" },
    };
  }

  // 3) Poll del analysis hasta completed o timeout.
  const start = Date.now();
  let attempt = 0;
  while (Date.now() - start < POLL_TIMEOUT_MS) {
    const delay = POLL_DELAYS_MS[Math.min(attempt, POLL_DELAYS_MS.length - 1)];
    await new Promise((r) => setTimeout(r, delay));
    attempt++;

    const pollRes = await fetch(
      `${VT_BASE}/analyses/${analysisId}`,
      { headers: { "x-apikey": apiKey } },
    );
    if (pollRes.status !== 200) continue;
    const pollData = await pollRes.json();
    const status = pollData?.data?.attributes?.status as string | undefined;
    if (status === "completed") {
      // Tras completed, vamos a /files/{sha256} para obtener el resumen
      // unificado (el analysis devuelve por-engine pero queremos los
      // stats agregados).
      const finalLookup = await fetch(
        `${VT_BASE}/files/${sha256}`,
        { headers: { "x-apikey": apiKey } },
      );
      if (finalLookup.status === 200) {
        const finalData = await finalLookup.json();
        return _interpretFileObject(finalData, sha256);
      }
      // Si no llega el /files (raro), interpretamos el analysis directo.
      return _interpretAnalysisObject(pollData, sha256);
    }
    // Si esta queued / in-progress, seguimos esperando.
  }

  return {
    status: "error",
    result: {
      reason: "vt_poll_timeout",
      analysis_id: analysisId,
      note: "Excedimos 90s sin que VT completara el analisis. Reintenta manual.",
    },
  };
}

// ─────────────── Interpretacion de respuestas de VT ───────────────

/// Lee `data.attributes.last_analysis_stats` de la respuesta de
/// `/files/{hash}` y decide clean vs suspicious.
function _interpretFileObject(
  data: any,
  sha256: string,
): VtScanResult {
  const attrs = data?.data?.attributes ?? {};
  const stats = attrs.last_analysis_stats ?? {};
  const malicious = (stats.malicious ?? 0) as number;
  const suspicious = (stats.suspicious ?? 0) as number;
  const harmless = (stats.harmless ?? 0) as number;
  const undetected = (stats.undetected ?? 0) as number;
  const total = malicious + suspicious + harmless + undetected;

  // Umbral: si CUALQUIER motor flagea como malicious -> suspicious.
  // `suspicious` solo (sin malicious) lo dejamos pasar como clean --
  // muchos motores marcan packers / installers legitimos como
  // "suspicious" generando falsos positivos. `malicious` es mas fuerte.
  const isSuspicious = malicious > 0;

  return {
    status: isSuspicious ? "suspicious" : "clean",
    result: {
      provider: "virustotal",
      sha256,
      stats: { malicious, suspicious, harmless, undetected, total },
      // Solo los motores que flagearon, para no inflar el JSONB.
      flagged_engines: _extractFlaggedEngines(attrs.last_analysis_results),
      // Link publico al reporte (admin lo abre para revisar).
      report_url: `https://www.virustotal.com/gui/file/${sha256}/detection`,
      last_analysis_date: attrs.last_analysis_date,
      type_description: attrs.type_description,
      checked_at: new Date().toISOString(),
    },
  };
}

/// Fallback cuando solo tenemos el `/analyses/{id}` (sin el /files).
function _interpretAnalysisObject(
  data: any,
  sha256: string,
): VtScanResult {
  const attrs = data?.data?.attributes ?? {};
  const stats = attrs.stats ?? {};
  const malicious = (stats.malicious ?? 0) as number;
  const suspicious = (stats.suspicious ?? 0) as number;
  const harmless = (stats.harmless ?? 0) as number;
  const undetected = (stats.undetected ?? 0) as number;
  const total = malicious + suspicious + harmless + undetected;
  const isSuspicious = malicious > 0;

  return {
    status: isSuspicious ? "suspicious" : "clean",
    result: {
      provider: "virustotal",
      sha256,
      stats: { malicious, suspicious, harmless, undetected, total },
      flagged_engines: _extractFlaggedEngines(attrs.results),
      report_url: `https://www.virustotal.com/gui/file/${sha256}/detection`,
      analysis_only: true,
      checked_at: new Date().toISOString(),
    },
  };
}

/// Filtra el dict de resultados por motor para quedarnos solo con los
/// que marcaron malicious/suspicious. Reduce el size del JSONB.
function _extractFlaggedEngines(
  results: Record<string, any> | undefined,
): Array<{ engine: string; category: string; result: string | null }> {
  if (!results) return [];
  const out: Array<{
    engine: string;
    category: string;
    result: string | null;
  }> = [];
  for (const [engine, info] of Object.entries(results)) {
    const category = info?.category as string | undefined;
    if (category === "malicious" || category === "suspicious") {
      out.push({
        engine,
        category,
        result: (info?.result as string | null) ?? null,
      });
    }
  }
  return out;
}

async function _safeJson(res: Response): Promise<unknown> {
  try {
    return await res.json();
  } catch {
    return null;
  }
}
