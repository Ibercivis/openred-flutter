import 'package:flutter/material.dart';

import '../../app_locale.dart';
import '../../app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  bool _isSpanish(BuildContext context) {
    return Localizations.localeOf(context).languageCode.toLowerCase() == 'es';
  }

  @override
  Widget build(BuildContext context) {
    final isEs = _isSpanish(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEs ? 'Ajustes' : 'Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(isEs ? 'Tema' : 'Theme'),
            subtitle: ValueListenableBuilder<ThemeMode>(
              valueListenable: AppTheme.mode,
              builder: (context, mode, _) {
                switch (mode) {
                  case ThemeMode.light:
                    return Text(isEs ? 'Claro' : 'Light');
                  case ThemeMode.dark:
                    return Text(isEs ? 'Oscuro' : 'Dark');
                  case ThemeMode.system:
                    return Text(isEs ? 'Sistema' : 'System');
                }
              },
            ),
            onTap: () async {
              final current = AppTheme.mode.value;
              final selected = await showModalBottomSheet<ThemeMode>(
                context: context,
                builder: (context) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.system,
                          groupValue: current,
                          title: Text(isEs ? 'Sistema' : 'System'),
                          onChanged: (v) => Navigator.pop(context, v),
                        ),
                        const Divider(height: 1),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.light,
                          groupValue: current,
                          title: Text(isEs ? 'Claro' : 'Light'),
                          onChanged: (v) => Navigator.pop(context, v),
                        ),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.dark,
                          groupValue: current,
                          title: Text(isEs ? 'Oscuro' : 'Dark'),
                          onChanged: (v) => Navigator.pop(context, v),
                        ),
                      ],
                    ),
                  );
                },
              );

              if (selected == null) return;
              await AppTheme.set(selected);
            },
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(isEs ? 'Idioma' : 'Language'),
            subtitle: ValueListenableBuilder<Locale?>(
              valueListenable: AppLocale.locale,
              builder: (context, locale, _) {
                final code = locale?.languageCode;
                if (code == null) return Text(isEs ? 'Sistema' : 'System');
                if (code == 'es') return const Text('Español');
                if (code == 'en') return const Text('English');
                return Text(code);
              },
            ),
            onTap: () async {
              final currentCode = AppLocale.locale.value?.languageCode;
              final currentValue = currentCode ?? 'system';
              final selected = await showModalBottomSheet<String>(
                context: context,
                builder: (context) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<String>(
                          value: 'system',
                          groupValue: currentValue,
                          title: Text(isEs ? 'Sistema' : 'System'),
                          onChanged: (v) => Navigator.pop(context, v),
                        ),
                        const Divider(height: 1),
                        RadioListTile<String>(
                          value: 'en',
                          groupValue: currentValue,
                          title: const Text('English'),
                          onChanged: (v) => Navigator.pop(context, v),
                        ),
                        RadioListTile<String>(
                          value: 'es',
                          groupValue: currentValue,
                          title: const Text('Español'),
                          onChanged: (v) => Navigator.pop(context, v),
                        ),
                      ],
                    ),
                  );
                },
              );

              if (selected == null) return;
              if (selected == 'system') {
                await AppLocale.set(null);
              } else {
                await AppLocale.set(Locale(selected));
              }
            },
          ),
        ],
      ),
    );
  }
}
