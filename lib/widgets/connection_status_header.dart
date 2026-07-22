import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';
import '../screens/adapter_connect_page.dart';

class ConnectionStatusHeader extends StatelessWidget {
  const ConnectionStatusHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FogelSettings>(
      valueListenable: globalSettings,
      builder: (context, settings, child) {
        final isConnected = settings.connectionStatus == 'connected';
        final isReconnecting = settings.connectionStatus == 'reconnecting';
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
                onTap: isConnected
                    ? null
                    : () {
                        Navigator.push(context, PageRouteBuilder(
                          opaque: false,
                          pageBuilder: (context, animation, secondaryAnimation) => const AdapterConnectPage(),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
                            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                            child: child,
                          ),
                        ));
                      },
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
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                          ),
                        )
                      else
                        const Icon(Icons.wifi_off, color: Colors.red),
                      Expanded(
                        child: Text(
                          isReconnecting ? 'Переподключение...' : 'Адаптер не подключен.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isReconnecting ? Colors.orange[800] : Colors.red[800],
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: isReconnecting ? Colors.orange[800] : Colors.red[800],
                        size: 20,
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