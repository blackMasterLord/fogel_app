import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fogel_settings.dart';

class ThemePage extends StatefulWidget {
  const ThemePage({super.key});

  @override
  State<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends State<ThemePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Тема')),
      body: ValueListenableBuilder<FogelSettings>(
        valueListenable: globalSettings,
        builder: (context, settings, _) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildThemeCard(
                  title: 'Системная',
                  icon: Icons.brightness_auto,
                  value: AppThemeSetting.system,
                  groupValue: settings.themeSetting,
                ),
                const SizedBox(height: 12),
                _buildThemeCard(
                  title: 'Светлая',
                  icon: Icons.light_mode,
                  value: AppThemeSetting.light,
                  groupValue: settings.themeSetting,
                ),
                const SizedBox(height: 12),
                _buildThemeCard(
                  title: 'Тёмная',
                  icon: Icons.dark_mode,
                  value: AppThemeSetting.dark,
                  groupValue: settings.themeSetting,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildThemeCard({
    required String title,
    required IconData icon,
    required AppThemeSetting value,
    required AppThemeSetting groupValue,
  }) {
    final isSelected = value == groupValue;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () async {
          globalSettings.value = globalSettings.value.copyWith(themeSetting: value);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('app_theme', value.name);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[400],
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
