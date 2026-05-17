import 'package:meta/meta.dart';

/// Archivo subido a Storage y registrado en `public.uploads`. Es el
/// "VO maestro": cualquier feature que necesite mostrar un archivo
/// (avatares, adjuntos, etc.) referencia un `UploadedFile.id` en su
/// propia tabla y resuelve el `signedUrl` cuando lo necesita.
@immutable
class UploadedFile {
  const UploadedFile({
    required this.id,
    required this.userId,
    required this.tenantId,
    required this.bucket,
    required this.path,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    this.signedUrl,
  });

  factory UploadedFile.fromMap(Map<String, dynamic> m, {String? signedUrl}) {
    return UploadedFile(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      tenantId: m['tenant_id'] as String?,
      bucket: m['bucket'] as String? ?? 'user-uploads',
      path: m['path'] as String,
      filename: m['filename'] as String,
      mimeType: m['mime_type'] as String,
      sizeBytes: (m['size_bytes'] as num).toInt(),
      createdAt: DateTime.parse(m['created_at'] as String),
      signedUrl: signedUrl ?? m['signed_url'] as String?,
    );
  }

  final String id;
  final String userId;
  final String? tenantId;
  final String bucket;
  final String path;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;

  /// URL firmada temporal (TTL ~1h). Se pide al servidor on-demand
  /// cuando hace falta renderizar el archivo. Puede ser null si la
  /// consulta no la incluyó (lista paginada, por ejemplo).
  final String? signedUrl;

  /// `true` si es una imagen renderizable como `Image.network`.
  bool get isImage => mimeType.startsWith('image/');

  /// `true` si es un PDF.
  bool get isPdf => mimeType == 'application/pdf';

  UploadedFile copyWith({String? signedUrl}) {
    return UploadedFile(
      id: id,
      userId: userId,
      tenantId: tenantId,
      bucket: bucket,
      path: path,
      filename: filename,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      createdAt: createdAt,
      signedUrl: signedUrl ?? this.signedUrl,
    );
  }
}

/// Resultado del endpoint `quota` — el tenant tiene usado X bytes de
/// Y disponibles. `quota` = -1 significa ilimitado (plan Enterprise).
@immutable
class StorageQuota {
  const StorageQuota({required this.usedBytes, required this.quotaBytes});

  factory StorageQuota.fromMap(Map<String, dynamic> m) {
    return StorageQuota(
      usedBytes: (m['used_bytes'] as num).toInt(),
      quotaBytes: (m['quota_bytes'] as num).toInt(),
    );
  }

  final int usedBytes;
  final int quotaBytes;

  bool get isUnlimited => quotaBytes < 0;

  /// `0.0 .. 1.0` — porcentaje de uso. Si es ilimitado, devuelve 0.
  double get fraction {
    if (isUnlimited || quotaBytes == 0) return 0;
    return (usedBytes / quotaBytes).clamp(0.0, 1.0);
  }

  bool get isWarning => !isUnlimited && fraction >= 0.85;
  bool get isFull => !isUnlimited && usedBytes >= quotaBytes;
}
