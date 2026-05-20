import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

/// Confirmación tras actualizar contraseña vía recovery. Cerramos sesión
/// activa (la que abrió el code exchange) para que el usuario inicie sesión
/// limpiamente con sus nuevas credenciales.
class PasswordUpdatedPage extends ConsumerStatefulWidget {
  const PasswordUpdatedPage({super.key});

  @override
  ConsumerState<PasswordUpdatedPage> createState() =>
      _PasswordUpdatedPageState();
}

class _PasswordUpdatedPageState extends ConsumerState<PasswordUpdatedPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Cerrar la sesión temporal del recovery. Best effort.
      ref.read(authRepositoryProvider).signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: 480,
          icon: Icons.check_circle_outline,
          title: l.passwordUpdatedTitle,
          subtitle: l.passwordUpdatedSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.goNamed(RouteNames.login),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(l.actionSignIn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
