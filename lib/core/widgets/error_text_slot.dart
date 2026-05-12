import 'package:flutter/material.dart';

import 'package:myapp/core/constants/app_constants.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

/// Espacio vertical RESERVADO para mostrar el mensaje de error de un input.
/// El alto es fijo: aunque no haya error, el espacio sigue ocupado para que
/// la card no se mueva al aparecer/desaparecer el mensaje.
class ErrorTextSlot extends StatelessWidget {
  const ErrorTextSlot({
    super.key,
    this.message,
    this.height = AppConstants.inputErrorSlotHeight,
  });

  final String? message;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: AppConstants.defaultAnimation,
        child: (message == null || message!.isEmpty)
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : Padding(
                key: const ValueKey('err'),
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  message!,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Equivalente al [ErrorTextSlot] pero con más altura para errores generales
/// (entre el último input y los botones). Tamaño fijo igual.
class GeneralErrorSlot extends StatelessWidget {
  const GeneralErrorSlot({
    super.key,
    this.message,
    this.height = AppConstants.generalErrorSlotHeight,
  });

  final String? message;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: AppConstants.defaultAnimation,
        child: (message == null || message!.isEmpty)
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : Container(
                key: const ValueKey('err'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.colors.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: context.colors.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onErrorContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
