import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';

class ConnectionStatusDot extends StatefulWidget {
  const ConnectionStatusDot({super.key});

  @override
  State<ConnectionStatusDot> createState() => _ConnectionStatusDotState();
}

class _ConnectionStatusDotState extends State<ConnectionStatusDot> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  bool _shouldBlink = false;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Listen to connection status changes and manage animation separately
    // from build() — avoids side effects in a pure rendering function.
    globalSettings.addListener(_onConnectionStatusChanged);
    _syncBlink(globalSettings.value.connectionStatus);
  }

  void _onConnectionStatusChanged() {
    _syncBlink(globalSettings.value.connectionStatus);
  }

  void _syncBlink(String status) {
    final shouldBlink = status == 'searching' || status == 'connecting' || status == 'reconnecting';
    _shouldBlink = shouldBlink;
    if (shouldBlink && !_blinkController.isAnimating) {
      _blinkController.repeat(reverse: true);
    } else if (!shouldBlink && _blinkController.isAnimating) {
      _blinkController.stop();
      _blinkController.value = 1.0;
    }
  }

  @override
  void dispose() {
    globalSettings.removeListener(_onConnectionStatusChanged);
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FogelSettings>(
      valueListenable: globalSettings,
      builder: (context, settings, child) {
        Color dotColor;

        switch (settings.connectionStatus) {
          case 'connected':
            dotColor = Colors.greenAccent;
            break;
          case 'searching':
          case 'connecting':
          case 'reconnecting':
            dotColor = Colors.amberAccent;
            break;
          default:
            dotColor = Colors.redAccent;
            break;
        }

        Widget dot = Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: dotColor.withValues(alpha: 0.6),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );

        if (_shouldBlink) {
          return FadeTransition(
            opacity: _blinkController,
            child: dot,
          );
        }

        return dot;
      },
    );
  }
}
