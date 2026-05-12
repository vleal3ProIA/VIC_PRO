import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/constants/supported_locales.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/locale_provider.dart';

class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effective = ref.watch(effectiveLocaleProvider);
    final code = effective.languageCode;

    return PopupMenuButton<Locale>(
      tooltip: context.l10n.languageSelectorTooltip,
      offset: const Offset(0, 48),
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language_outlined),
          const SizedBox(width: 6),
          Text(
            code.toUpperCase(),
            style: context.textTheme.labelLarge,
          ),
        ],
      ),
      itemBuilder: (_) => [
        for (final locale in AppLocales.all)
          PopupMenuItem<Locale>(
            value: locale,
            child: Row(
              children: [
                Text(
                  AppLocales.flag[locale.languageCode] ?? '🏳️',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocales.nativeName[locale.languageCode] ??
                        locale.languageCode,
                  ),
                ),
                if (locale.languageCode == code)
                  Icon(Icons.check, size: 18, color: context.colors.primary),
              ],
            ),
          ),
      ],
      onSelected: (locale) =>
          ref.read(localeNotifierProvider.notifier).setLocale(locale),
    );
  }
}
