import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/fogel_settings.dart';
import 'screens/main_layout.dart';
import 'services/fogel_adapter_service.dart';
import 'services/wifi_channel.dart';
import 'utils/crash_log.dart';

Future<void> _writeCrashLog(String text) async {
  try {
    final timestamp = DateTime.now().toIso8601String();
    await crashLogFile.writeAsString('[$timestamp]\n$text\n\n', mode: FileMode.append);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch unhandled errors in release builds, write to crash log
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _writeCrashLog(details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _writeCrashLog('$error\n$stack');
    return true; // handled
  };

  final prefs = await SharedPreferences.getInstance();
  final savedThemeStr = prefs.getString('app_theme') ?? 'system';
  
  AppThemeSetting savedTheme = AppThemeSetting.system;
  if (savedThemeStr == 'light') {
    savedTheme = AppThemeSetting.light;
  } else if (savedThemeStr == 'dark') {
    savedTheme = AppThemeSetting.dark;
  }

  globalSettings.value = globalSettings.value.copyWith(
    themeSetting: savedTheme,
  );

  await FogelAdapterService.loadSavedDevices();

  // Precache logo so About page shows it instantly on first visit
  try { await rootBundle.load('assets/logo.webp'); } catch (_) {}

  // Eager-init DHCP EventChannel so native sink is ready before any connectToWifi call
  WiFiChannel.onDhcpReady;

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(const FogelApp());
  });
}

class FogelApp extends StatelessWidget {
  const FogelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FogelSettings>(
      valueListenable: globalSettings,
      builder: (context, settings, child) {
        ThemeMode themeMode;
        switch (settings.themeSetting) {
          case AppThemeSetting.light:
            themeMode = ThemeMode.light;
            break;
          case AppThemeSetting.dark:
            themeMode = ThemeMode.dark;
            break;
          case AppThemeSetting.system:
            themeMode = ThemeMode.system;
            break;
        }

        const Color brandColor = Color(0xFFFF850C);
        const Color secondaryColor = Color(0xFF54595F);

        return MaterialApp(
          title: 'FogelApp',
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: const ColorScheme.light(
              primary: brandColor,
              secondary: secondaryColor,
              surface: Colors.white,
              onPrimary: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: brandColor,
              foregroundColor: Colors.white,
              elevation: 2,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              selectedItemColor: brandColor,
              unselectedItemColor: secondaryColor,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: const ColorScheme.dark(
              primary: brandColor,
              secondary: secondaryColor,
              onPrimary: Colors.white,
              surface: Color(0xFF1C1C1E),
              surfaceContainerLow: Color(0xFF2C2C2E),
              surfaceContainer: Color(0xFF3A3A3C),
              surfaceContainerHigh: Color(0xFF48484A),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: brandColor,
              foregroundColor: Colors.white,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              selectedItemColor: brandColor,
              unselectedItemColor: Colors.grey,
            ),
          ),
          home: const MainLayout(),
        );
      },
    );
  }
}