// ============================================================================
// subjects · SavedTestPickerDialog
// ----------------------------------------------------------------------------
// Modal que lista los tests guardados (`saved_tests`) de un temario y permite
// al usuario elegir UNO (para realizarlo) o VARIOS (para combinarlos en uno
// nuevo y realizar el combinado).
//
// Devuelve a traves del Navigator:
//   - [SavedTestPickResult.single(id)]    -> realizar ese test.
//   - [SavedTestPickResult.combine(ids)]  -> combinar y realizar el resultado.
//   - null si el usuario cancela.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';

import '../../../application/subjects_providers.dart';
import '../../../domain/subject.dart';

/// Resultado del picker: o un id concreto, o una lista a combinar.
class SavedTestPickResult {
  const SavedTestPickResult.single(this.singleId) : combineIds = const [];
  const SavedTestPickResult.combine(this.combineIds) : singleId = null;

  final String? singleId;
  final List<String> combineIds;

  bool get isSingle => singleId != null;
  bool get isCombine => combineIds.isNotEmpty;
}

Future<SavedTestPickResult?> showSavedTestPicker(
  BuildContext context, {
  required String subjectId,
}) {
  return showDialog<SavedTestPickResult>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _SavedTestPickerDialog(subjectId: subjectId),
  );
}

class _SavedTestPickerDialog extends ConsumerStatefulWidget {
  const _SavedTestPickerDialog({required this.subjectId});
  final String subjectId;

  @override
  ConsumerState<_SavedTestPickerDialog> createState() =>
      _SavedTestPickerDialogState();
}

class _SavedTestPickerDialogState
    extends ConsumerState<_SavedTestPickerDialog> {
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(savedTestsProvider(widget.subjectId));
    return AlertDialog(
      title: Text(l.studyTestSavedListTitle),
      content: SizedBox(
        width: 480,
        height: 480,
        child: async.when(
          loading: () => const Center(child: AppLoadingState()),
          error: (e, _) => AppErrorState(message: l.errorGeneric),
          data: (tests) {
            if (tests.isEmpty) {
              return Center(
                child: AppEmptyState(
                  icon: Icons.quiz_outlined,
                  title: l.studyTestSavedListTitle,
                  message: l.studyTestSavedEmpty,
                ),
              );
            }
            return ListView.separated(
              itemCount: tests.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _row(tests[i]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        if (_selected.length >= 2)
          FilledButton.icon(
            onPressed: () => Navigator.of(context)
                .pop(SavedTestPickResult.combine(_selected.toList())),
            icon: const Icon(Icons.merge_type, size: 16),
            label: Text(l.studyTestSavedCombine),
          ),
      ],
    );
  }

  Widget _row(SavedTest t) {
    final l = context.l10n;
    final scheme = context.colors;
    final isSelected = _selected.contains(t.id);
    return InkWell(
      // Tap simple = realizar ese test directamente.
      onTap: () => Navigator.of(context).pop(SavedTestPickResult.single(t.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selected.add(t.id);
                } else {
                  _selected.remove(t.id);
                }
              }),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${l.studyTestSavedQuestionCount(t.questionCount)} · '
                    '${_dateLabel(t.createdAt)}',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
