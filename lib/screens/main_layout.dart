import 'package:flutter/material.dart';
import '../widgets/lightning_icon.dart';
import '../widgets/connection_status_header.dart';
import '../widgets/connection_status_dot.dart';
import '../tabs/can_analyzer_tab.dart';
import '../tabs/monitoring_control_tab.dart';
import '../services/fogel_adapter_service.dart';
import '../models/fogel_settings.dart';
import 'settings_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late PageController _pageController;
  FogelConnectionState _lastStatus = FogelConnectionState.disconnected;

  final List<Widget> _tabs = [
    const CanAnalyzerTab(),
    const MonitoringControlTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _currentIndex);
    _lastStatus = globalSettings.value.connectionStatus;
    globalSettings.addListener(_onGlobalSettingsChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    globalSettings.removeListener(_onGlobalSettingsChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // Prevent health-timer-driven "connection lost" snackbar while backgrounded.
      // Must be set BEFORE the timer fires on resume — inactive fires first.
      FogelAdapterService().isAutoReconnecting = true;
    } else if (state == AppLifecycleState.resumed) {
      _restoreConnectionIfNeeded();
    }
  }

  Future<void> _restoreConnectionIfNeeded() async {
    final service = FogelAdapterService();
    // TICK flows via UDP — if the UDP socket survived backgrounding,
    // data is already arriving and status stays 'connected'. Nothing to do.
    // If UDP died too, the health timer will transition to 'disconnected'.
    try {
      if (service.canReconnect && service.isConnectionStale) {
        debugPrint('[MainLayout] UDP stale after resume, reconnecting...');
        globalSettings.value = globalSettings.value.copyWith(connectionStatus: FogelConnectionState.reconnecting);
        service.markReconnecting();

        final ok = await service.reconnect().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('[MainLayout] Reconnect timeout');
            return false;
          },
        );

        if (!ok && mounted) {
          globalSettings.value = globalSettings.value.copyWith(
            connectionStatus: FogelConnectionState.disconnected,
            connectionError: 'Таймаут переподключения к адаптеру',
          );
        }
      }
    } finally {
      service.isAutoReconnecting = false;
    }
  }

  void _onGlobalSettingsChanged() {
    final currentStatus = globalSettings.value.connectionStatus;
    if (_lastStatus == FogelConnectionState.connected && currentStatus == FogelConnectionState.disconnected) {
      if (!FogelAdapterService().isManualDisconnect && !FogelAdapterService().isAutoReconnecting) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Связь с адаптером потеряна'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    _lastStatus = currentStatus;

    final error = globalSettings.value.connectionError;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
      );
      globalSettings.value = globalSettings.value.copyWith(connectionError: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LightningIconWithParticles(),
            SizedBox(width: 6),
            Text(
              'FogelApp',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
            ),
            SizedBox(width: 8),
            ConnectionStatusDot(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Настройки',
            onPressed: () {
              Navigator.push(context, PageRouteBuilder(
                opaque: false,
                pageBuilder: (context, animation, secondaryAnimation) => const SettingsScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  child: child,
                ),
              ));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const ConnectionStatusHeader(),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              children: _tabs,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        //backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        currentIndex: _currentIndex,
        selectedFontSize: 12.0,
        unselectedFontSize: 12.0,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        onTap: (index) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            activeIcon: Icon(Icons.analytics),
            label: 'CAN-анализатор',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_customize_outlined),
            activeIcon: Icon(Icons.dashboard_customize),
            label: 'Мониторинг и управление',
          ),
        ],
      ),
    );
  }
}