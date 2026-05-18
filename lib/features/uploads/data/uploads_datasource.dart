import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/uploaded_file.dart';

/// Acceso al sistema de uploads (PR-A hardening).
///
/// Flow nuevo en DOS PASOS para que archivos grandes no choquen con el
/// limite de payload de Edge Functions (~6 MB):
///
///   1. `requestUploadUrl()` -> Edge Function valida mime + cuota + size,
///      reserva fila en `uploads` con confirmed_at=null y devuelve una
///      signed upload URL.
///   2. PUT del archivo crudo directamente al bucket via signed URL.
///   3. `confirmUpload()` -> Edge Function descarga el object, valida
///      magic bytes server-side, calcula sha256 y marca la fila como
///      confirmed.
///
/// La API publica `upload()` encapsula los tres pasos -- el caller no
/// se entera. Si algun paso falla, lanza `UploadException` con codigo
/// suficiente para que la UI muestre mensaje accionable.
class UploadsDataSource {
  const UploadsDataSource(this._client);

  final SupabaseClient _client;

  /// Limite duro alineado con `upload-file/index.ts` MAX_FILE_BYTES.
  /// El servidor lo re-valida; este chequeo client-side es solo para
  /// no malgastar bandwidth subiendo algo que va a rebotar.
  static const int maxFileBytes = 50 * 1024 * 1024; // 50 MB

  /// Sube un archivo al bucket en TRES pasos (request -> PUT -> confirm).
  /// Devuelve el `UploadedFile` con `signedUrl` valido por 1 hora.
  ///
  /// Throws `UploadException` con codigo (`quota_exceeded`,
  /// `file_too_large`, `unsupported_mime`, `magic_bytes_mismatch`, etc.)
  /// si algo falla.
  Future<UploadedFile> upload({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    String? tenantId,
  }) async {
    // Pre-flight client-side. El servidor revalida todo.
    if (bytes.isEmpty) {
      throw const UploadException('file_too_small');
    }
    if (bytes.length > maxFileBytes) {
      throw const UploadException('file_too_large');
    }

    // PASO 1: pedir signed upload URL.
    final reqPayload = await _invoke({
      'action': 'request_upload_url',
      if (tenantId != null) 'tenant_id': tenantId,
      'filename': filename,
      'mime_type': mimeType,
      'size_bytes': bytes.length,
    });
    final uploadId = reqPayload['upload_id'] as String;
    final signedUploadUrl = reqPayload['signed_upload_url'] as String;

    // PASO 2: PUT directo al bucket. Si falla aqui (network, 4xx, etc.)
    // la fila pending quedara huerfana hasta que el cron la purgue --
    // RLS la oculta de la lista del cliente, asi que no se ve.
    await _putToSignedUrl(
      url: signedUploadUrl,
      bytes: bytes,
      mimeType: mimeType,
    );

    // PASO 3: confirmar. El server valida magic bytes + hash.
    final confPayload = await _invoke({
      'action': 'confirm_upload',
      'upload_id': uploadId,
    });

    return UploadedFile(
      id: uploadId,
      userId: _client.auth.currentUser!.id,
      tenantId: tenantId,
      bucket: 'user-uploads',
      path: reqPayload['path'] as String,
      filename: filename,
      mimeType: mimeType,
      sizeBytes: (confPayload['size_bytes'] as num?)?.toInt() ?? bytes.length,
      createdAt: DateTime.now(),
      signedUrl: confPayload['signed_url'] as String?,
    );
  }

  /// Lista de uploads visibles para el usuario actual (los suyos +
  /// los del tenant indicado). RLS oculta automaticamente las filas
  /// pending (confirmed_at=null). Sin signedUrl -- pedir por separado.
  Future<List<UploadedFile>> list({String? tenantId, int limit = 100}) async {
    var query = _client
        .from('uploads')
        .select(
          'id, user_id, tenant_id, bucket, path, filename, '
          'mime_type, size_bytes, created_at, virus_scan_status',
        )
        .filter('deleted_at', 'is', null);
    if (tenantId != null) {
      query = query.eq('tenant_id', tenantId);
    }
    final data = await query.order('created_at', ascending: false).limit(limit);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(UploadedFile.fromMap)
        .toList(growable: false);
  }

  /// Pide una signed URL nueva para [uploadId] (descarga). TTL 1h.
  /// La URL incluye `?download=` (Content-Disposition: attachment).
  Future<String?> getSignedUrl(String uploadId) async {
    final payload = await _invoke({
      'action': 'get_signed_url',
      'upload_id': uploadId,
    });
    return payload['signed_url'] as String?;
  }

  /// Soft-delete: marca `deleted_at = now()`. El object de Storage se
  /// purga en cron posterior tras 30 dias.
  Future<void> delete(String uploadId) async {
    await _invoke({'action': 'delete', 'upload_id': uploadId});
  }

  /// Consulta cuota actual del tenant. Si `quotaBytes < 0` = ilimitada.
  Future<StorageQuota> quota(String tenantId) async {
    final payload = await _invoke({
      'action': 'quota',
      'tenant_id': tenantId,
    });
    return StorageQuota.fromMap(payload);
  }

  // ───────────────────────── helpers privados ─────────────────────────

  /// PUT directo al signed upload URL de Supabase Storage. NO usamos
  /// el SDK porque `client.storage.uploadToSignedUrl()` no expone el
  /// token de la misma forma en todas las versiones; un PUT crudo es
  /// portable y simple.
  Future<void> _putToSignedUrl({
    required String url,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final res = await http.put(
      Uri.parse(url),
      headers: {
        'content-type': mimeType,
        // Cache-Control para que Supabase Storage marque el object
        // como cacheable por la CDN, igual que hace el SDK por defecto.
        'cache-control': 'max-age=3600',
        // x-upsert: false -- no sobreescribir si el path existiera.
        'x-upsert': 'false',
      },
      body: bytes,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw UploadException(
        'put_failed',
        detail: 'http_${res.statusCode}',
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('upload-file', body: body);
      final data = res.data;
      if (data is! Map) {
        throw const UploadException('empty_response');
      }
      final payload = data.cast<String, dynamic>();
      if (payload['error'] != null) {
        throw UploadException(
          payload['error'] as String,
          detail: payload['detail'] as String?,
        );
      }
      return payload;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        final m = details.cast<String, dynamic>();
        final code = m['error'] as String?;
        if (code != null) {
          throw UploadException(code, detail: m['detail'] as String?);
        }
      }
      throw UploadException('http_${e.status}');
    }
  }
}

class UploadException implements Exception {
  const UploadException(this.code, {this.detail});
  final String code;
  final String? detail;
  @override
  String toString() => detail == null
      ? 'UploadException($code)'
      : 'UploadException($code: $detail)';
}
