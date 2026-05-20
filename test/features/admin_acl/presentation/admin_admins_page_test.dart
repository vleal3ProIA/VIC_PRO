import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/admin_acl/application/admin_acl_providers.dart';
import 'package:myapp/features/admin_acl/domain/admin_row.dart';
import 'package:myapp/features/admin_acl/presentation/pages/admin_admins_page.dart';

import '../../../helpers/pump_widget.dart';

AdminRow _superRow() => AdminRow(
      userId: 'super-1',
      email: 'vleal3@gmail.com',
      displayName: 'Victor',
      isSuperAdmin: true,
      capabilities: const {'manage_users', 'manage_plans'},
      createdAt: DateTime.utc(2026, 5, 15),
    );

AdminRow _normalAdminRow() => AdminRow(
      userId: 'admin-2',
      email: 'admin2@example.com',
      displayName: null,
      isSuperAdmin: false,
      capabilities: const {'manage_users'},
      createdAt: DateTime.utc(2026, 5, 16),
    );

void main() {
  group('AdminAdminsPage', () {
    testWidgets('estado loading muestra spinner', (tester) async {
      await pumpForTest(
        tester,
        child: const AdminAdminsPage(),
        overrides: [
          // Future que nunca resuelve → estado loading permanente.
          adminsListProvider.overrideWith(
            (ref) => Completer<List<AdminRow>>().future,
          ),
        ],
      );
      await tester.pump(); // un frame, sin settle (no resolveria nunca)
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('estado error muestra el mensaje de carga fallida',
        (tester) async {
      await pumpForTest(
        tester,
        child: const AdminAdminsPage(),
        overrides: [
          adminsListProvider.overrideWith(
            (ref) async => throw Exception('boom'),
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the admins list."), findsOneWidget);
    });

    testWidgets('estado data renderiza admins + CTA de promote',
        (tester) async {
      await pumpForTest(
        tester,
        child: const AdminAdminsPage(),
        overrides: [
          adminsListProvider.overrideWith(
            (ref) async => [_superRow(), _normalAdminRow()],
          ),
        ],
      );
      await tester.pumpAndSettle();

      // El email del super y del admin normal aparecen.
      expect(find.text('vleal3@gmail.com'), findsWidgets);
      expect(find.text('admin2@example.com'), findsWidgets);
      // CTA para promover usuarios.
      expect(find.text('Promote user to admin'), findsOneWidget);
      // Badge "Super admin" para el super.
      expect(find.text('Super admin'), findsWidgets);
      // Hay switches de capability (al menos uno por admin).
      expect(find.byType(Switch), findsWidgets);
    });

    testWidgets('el super NO muestra boton de revoke; el admin normal SI',
        (tester) async {
      await pumpForTest(
        tester,
        child: const AdminAdminsPage(),
        overrides: [
          adminsListProvider.overrideWith(
            (ref) async => [_superRow(), _normalAdminRow()],
          ),
        ],
      );
      await tester.pumpAndSettle();
      // "Revoke admin role" aparece solo para el admin normal (1 vez).
      expect(find.text('Revoke admin role'), findsOneWidget);
    });
  });
}
