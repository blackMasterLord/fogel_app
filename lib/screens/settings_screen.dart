import 'dart:async';
import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';
import '../services/fogel_adapter_service.dart';
import '../services/wifi_channel.dart';
import 'about_page.dart';
import 'adapter_connect_page.dart';
import 'theme_page.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _wifiSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkWifiState();
    _wifiSub = WiFiChannel.onWifiChanged.listen((_) {
      _checkWifiState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wifiSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkWifiState();
    }
  }

  Future<void> _checkWifiState() async {
    final enabled = await FogelAdapterService().isWifiEnabled();
    if (mounted && globalSettings.value.wifiEnabled != enabled) {
      globalSettings.value = globalSettings.value.copyWith(wifiEnabled: enabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([globalSettings, AdapterConnectPage.scanState]),
        builder: (context, child) {
          final settings = globalSettings.value;
          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 16.0,
                bottom: 16.0 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                _buildAdapterCard(settings),
                const SizedBox(height: 8),
                _buildThemeTile(settings),
                const SizedBox(height: 8),
                _buildAboutTile(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdapterCard(FogelSettings settings) {
    final wifiOn = settings.wifiEnabled;
    final status = settings.connectionStatus;
    final isConnected = status == FogelConnectionState.connected;
    final isBusy = settings.isConnecting && !isConnected;

    IconData icon;
    Color iconColor;
    String subtitle;

    if (!wifiOn) {
      icon = Icons.wifi_off;
      iconColor = Colors.red;
      subtitle = 'WIFI выключен';
    } else if (isConnected) {
      icon = Icons.wifi;
      iconColor = Colors.green;
      subtitle = settings.connectedDeviceName;
    } else if (isBusy) {
      icon = Icons.sync;
      iconColor = Colors.orange;
      if (status == FogelConnectionState.connecting) {
        subtitle = 'Подключение к адаптеру...';
      } else if (status == FogelConnectionState.pinging) {
        subtitle = 'Проверка адаптера...';
      } else {
        subtitle = 'Загрузка конфигурации...';
      }
    } else if (adapterPageIsScanning) {
      icon = Icons.wifi_find;
      iconColor = Colors.blue;
      if (adapterPageFoundCount > 0) {
        subtitle = 'Найдено адаптеров: $adapterPageFoundCount';
      } else {
        subtitle = 'Поиск...';
      }
    } else {
      icon = Icons.wifi_off;
      iconColor = Colors.orange;
      subtitle = 'Не подключен';
    }

    final showSpinner = wifiOn && (isBusy || adapterPageIsScanning);

    return Card(
      child: ListTile(
        leading: showSpinner
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: adapterPageIsScanning ? Colors.blue : iconColor,
                ),
              )
            : Icon(icon, color: iconColor),
        title: const Text('Адаптер'),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, animation, secondaryAnimation) => const AdapterConnectPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        )),
        onLongPress: isConnected ? () => _showDisconnectDialog(settings) : null,
      ),
    );
  }

  void _showDisconnectDialog(FogelSettings settings) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                settings.connectedDeviceName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                settings.connectedDeviceName,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.link_off, color: Colors.red),
              title: const Text('Отключить', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                FogelAdapterService().disconnect(manual: true, disconnectWifi: true);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Адаптер отключен')
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeTile(FogelSettings settings) {
    final labels = {
      AppThemeSetting.system: 'Системная',
      AppThemeSetting.light: 'Светлая',
      AppThemeSetting.dark: 'Тёмная',
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.palette),
        title: const Text('Тема'),
        subtitle: Text(labels[settings.themeSetting] ?? 'Системная'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, animation, secondaryAnimation) => const ThemePage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        )),
      ),
    );
  }

  Widget _buildAboutTile() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('О приложении'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, animation, secondaryAnimation) => const AboutPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        )),
      ),
    );
  }
}
