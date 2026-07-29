import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';

class ThemePickerPage extends StatelessWidget {
  final AppThemeSetting current;
  const ThemePickerPage({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final labels = {AppThemeSetting.system: 'Системная', AppThemeSetting.light: 'Светлая', AppThemeSetting.dark: 'Тёмная'};

    return Scaffold(
      appBar: AppBar(title: const Text('Тема')),
      body: RadioGroup<AppThemeSetting>(
        groupValue: current,
        onChanged: (v) => globalSettings.value = globalSettings.value.copyWith(themeSetting: v),
        child: ListView(
          children: AppThemeSetting.values.map((t) => RadioListTile<AppThemeSetting>(
            title: Text(labels[t] ?? ''),
            subtitle: t == AppThemeSetting.system ? const Text('Следует настройкам устройства') : null,
            value: t,
          )).toList(),
        ),
      ),
    );
  }
}
