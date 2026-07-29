import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';
import '../screens/adapter_connect_page.dart';

class ConnectionStatusHeader extends StatefulWidget {
  const ConnectionStatusHeader({super.key});

  @override
  State<ConnectionStatusHeader> createState() => _ConnectionStatusHeaderState();
}

class _ConnectionStatusHeaderState extends State<ConnectionStatusHeader> {
  bool _isNavigating = false;

  void _openAdapterPage() {
    if (_isNavigating) return;
    _isNavigating = true;
    Navigator.push(context, PageRouteBuilder(
      opaque: false,
      pageBuilder: (context, animation, secondaryAnimation) => const AdapterConnectPage(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    )).then((_) { if (mounted) _isNavigating = false; });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FogelSettings>(
      valueListenable: globalSettings,
      builder: (context, settings, child) {
        final isConnected = settings.connectionStatus == FogelConnectionState.connected;
        final isReconnecting = settings.connectionStatus == FogelConnectionState.reconnecting;
        final showBanner = !isConnected;

        return AnimatedAlign(
          alignment: Alignment.topCenter,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          heightFactor: showBanner ? 1.0 : 0.0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: showBanner ? 1.0 : 0.0,
            child: ClipRect(
              child: InkWell(
                onTap: isConnected ? null : _openAdapterPage,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  color: isReconnecting
                      ? Colors.orange.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      if (isReconnecting)
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: SizedBox(
                            child: Icon(Icons.wifi_off, color: Colors.red),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          isReconnecting ? 'Переподключение...' : 'Адаптер не подключен',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isReconnecting ? Colors.orange : Colors.red,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: isReconnecting ? Colors.orange : Colors.red,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
