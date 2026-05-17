import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

/// Avatar del usuario: muestra la imagen si hay [avatarUrl], y si no, la
/// inicial del [name] sobre el color primario. Reutilizable en la cabecera,
/// en Ajustes, etc.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.name,
    this.avatarUrl,
    this.radius = 20,
    super.key,
  });

  final String name;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';

    // a11y: el lector de pantalla anuncia "<nombre>, avatar" en vez de
    // "imagen" genérica. `image: true` marca el rol semántico correcto.
    final semanticsLabel =
        trimmed.isNotEmpty ? '$trimmed, avatar' : 'User avatar';

    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: context.colors.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          color: context.colors.onPrimaryContainer,
        ),
      ),
    );

    final url = avatarUrl;
    if (url == null || url.isEmpty) {
      return Semantics(image: true, label: semanticsLabel, child: fallback);
    }

    return Semantics(
      image: true,
      label: semanticsLabel,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: context.colors.primaryContainer,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          ),
        ),
      ),
    );
  }
}
