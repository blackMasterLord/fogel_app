import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';

class ConnectionStatusDot extends StatefulWidget {
  const ConnectionStatusDot({super.key});

  @override
  State<ConnectionStatusDot> createState() => _ConnectionStatusDotState();
}

class _ConnectionStatusDotState extends State<ConnectionStatusDot> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FogelSettings>(
      valueListenable: globalSettings,
      builder: (context, settings, child) {
        final status = settings.connectionStatus;
        final shouldBlink = status == FogelConnectionState.connecting || status == FogelConnectionState.reconnecting;

        if (shouldBlink && !_blinkController.isAnimating) {
          _blinkController.repeat(reverse: true);
        } else if (!shouldBlink && _blinkController.isAnimating) {
          _blinkController.stop();
          _blinkController.value = 1.0;
        }

        Color dotColor;
        switch (status) {
          case FogelConnectionState.connected:
            dotColor = Colors.greenAccent;
          case FogelConnectionState.connecting:
          case FogelConnectionState.pinging:
          case FogelConnectionState.loadingConfig:
          case FogelConnectionState.reconnecting:
            dotColor = Colors.amberAccent;
          case FogelConnectionState.disconnected:
            dotColor = Colors.redAccent;
        }

        Widget dot = Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: dotColor, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.6), blurRadius: 4, spreadRadius: 1)],
          ),
        );

        if (shouldBlink) return FadeTransition(opacity: _blinkController, child: dot);
        return dot;
      },
    );
  }
}
