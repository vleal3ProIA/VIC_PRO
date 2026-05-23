// ============================================================================
// _shared/ai/types.ts · Tipos del gateway de IA
// ----------------------------------------------------------------------------
// Contratos compartidos entre el router (`gateway.ts`) y los adaptadores por
// proveedor (`providers/*.ts`). Pensado para crecer: en Fase 1 anyadiremos
// partes de contenido para vision (PDF/imagen) en `AiMessage`.
// ============================================================================

export interface AiProviderRow {
  id: string;
  slug: string;
  display_name: string;
  tier: "free" | "paid";
  enabled: boolean;
  priority: number;
  default_model: string | null;
  base_url: string | null;
}

export interface AiCredentialRow {
  id: string;
  provider_id: string;
  api_key: string;
  enabled: boolean;
  cooldown_until: string | null;
  last_used_at: string | null;
}

export interface AiMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

/// Adjunto para visión nativa (PDF o imagen) codificado en base64. Se manda
/// junto al primer mensaje de usuario. Solo lo soportan los proveedores
/// "document-capable" (Gemini, Anthropic); el gateway enruta en consecuencia.
export interface AiAttachment {
  mimeType: string; // 'application/pdf', 'image/png', 'image/jpeg', ...
  dataBase64: string;
}

/// Petición de completion que el resto de Edge Functions pasan al gateway.
export interface AiCompletionRequest {
  task: string; // 'index' | 'views' | 'aids' | 'questions' | 'qa' | 'test'
  system?: string;
  messages: AiMessage[];
  model?: string; // override; si falta usa `default_model` del proveedor
  maxOutputTokens?: number;
  temperature?: number;
  userId?: string | null; // para registrar en ai_usage
  subjectId?: string | null;
  preferTier?: "free" | "paid"; // hint: lo difícil -> 'paid' primero
  onlyProviderSlug?: string; // forzar un proveedor (usado por el "test")
  attachments?: AiAttachment[]; // visión nativa (PDF/imagen) para ingesta
}

export interface AiCompletionResult {
  text: string;
  providerSlug: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
}

/// Lo que devuelve un adaptador (sin coste; el coste lo calcula el gateway).
export interface AdapterResult {
  text: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

/// Parámetros que el gateway pasa a un adaptador ya resueltos (key, modelo,
/// base_url efectiva, mensajes, límites).
export interface AdapterParams {
  apiKey: string;
  model: string;
  baseUrl: string | null;
  system?: string;
  messages: AiMessage[];
  maxOutputTokens: number;
  temperature: number;
  attachments?: AiAttachment[];
}

export type ProviderAdapter = (p: AdapterParams) => Promise<AdapterResult>;

/// Error de un proveedor, clasificado para decidir qué hacer con la credencial:
///  - 'auth'      -> key inválida -> deshabilitar credencial.
///  - 'quota'/'rate' -> agotada/limitada -> cooldown temporal.
///  - 'transient' -> error puntual (5xx) -> probar siguiente, sin penalizar.
///  - 'bad_request' -> error nuestro (prompt) -> no reintentar con otra key.
export class AiProviderError extends Error {
  constructor(
    message: string,
    public kind: "quota" | "auth" | "rate" | "transient" | "bad_request",
    public status?: number,
  ) {
    super(message);
    this.name = "AiProviderError";
  }
}
