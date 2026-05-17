import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/uploaded_file.dart';

/// Acceso al sistema de uploads. Las subidas pasan por la Edge Function
/// `upload-file` que valida cuota + mime ANTES de tocar Storage. La
/// lectura de la lista usa la tabla `uploads` directamente vía RLS.
class UploadsDataSource {
  const UploadsDataSource(this._client);

  final SupabaseClient _client;

  /// Sube un archivo al bucket. Devuelve el `UploadedFile` con
  /// `signedUrl` válido por 1 hora.
  ///
  /// Throws `UploadException` con código (`quota_exceeded`,
  /// `file_too_large`, `unsupported_mime`, etc.) si algo falla.
  Future<UploadedFile> upload({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    String? tenantId,
  }) async {
    final payload = await _invoke({
      'action': 'upload',
      if (tenantId != null) 'tenant_id': tenantId,
      'filename': filename,
      'mime_type': mimeType,
      'data_base64': base64Encode(bytes),
    });
    return UploadedFile(
      id: payload['upload_id'] as String,
      userId: _client.auth.currentUser!.id,
      tenantId: tenantId,
      bucket: 'user-uploads',
      path: payload['path'] as String,
      filename: payload['filename'] as String,
      mimeType: payload['mime_type'] as String,
      sizeBytes: (payload['size_bytes'] as num).toInt(),
      createdAt: DateTime.now(),
      signedUrl: payload['signed_url'] as String?,
    );
  }

  /// Lista de uploads visibles para el usuario actual (los suyos +
  /// los del tenant indicado). Sin signedUrl — pedir por separado.
  Future<List<UploadedFile>> list({String? tenantId, int limit = 100}) async {
    var query = _client
        .from('uploads')
        .select(
          'id, user_id, tenant_id, bucket, path, filename, '
          'mime_type, size_bytes, created_at',
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

  /// Pide una signed URL nueva para [uploadId]. TTL 1h.
  Future<String?> getSignedUrl(String uploadId) async {
    final payload = await _invoke({
      'action': 'get_signed_url',
      'upload_id': uploadId,
    });
    return payload['signed_url'] as String?;
  }

  /// Soft-delete: marca `deleted_at = now()`. El object de Storage
  /// se purga en cron posterior.
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
