import 'package:flutter/material.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/auth_card.dart';
import 'package:myapp/features/auth/presentation/widgets/delete_account_form.dart';

/// Página `/delete-account` — borrado permanente de la cuenta (derecho de
/// supresión del GDPR). Se llega desde Ajustes → Seguridad.
class DeleteAccountPage extends StatelessWidget {
  const DeleteAccountPage({super.key});

  static const double _reservedHeight = 600;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.accountSettings),
        ),
        title: Text(l.deleteAccountTitle),
      ),
      body: SafeArea(
        child: AuthCard(
          reservedHeight: _reservedHeight,
          leading: Icon(
            Icons.delete_forever_outlined,
            size: 56,
            color: context.colors.error,
          ),
          title: l.deleteAccountTitle,
          subtitle: l.deleteAccountSubtitle,
          child: const DeleteAccountForm(),
        ),
      ),
    );
  }
}
