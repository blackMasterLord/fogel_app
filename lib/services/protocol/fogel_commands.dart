import 'dart:convert';
import '../protocol/fogel_protocol.dart';
import '../transport/tcp_transport.dart';

class FogelCommands {
  final TcpTransport tcp;

  FogelCommands(this.tcp);

  void requestConfiguration() => _send(msgGetConfig);
  void sendClearCan() => _send(msgCanClear);
  void sendPing() => _send(msgPing);
  void requestDeviceInfo() => _send(msgDeviceInfo);

  void sendUdpReg(int port) => _send(msgUdpReg, [(port >> 8) & 0xFF, port & 0xFF]);

  void getProtocol(String name) {
    final bytes = utf8.encode(name);
    _send(msgGetProtocol, [bytes.length, ...bytes]);
  }

  void setSpeed(int speed) {
    _send(msgSetCanSpeed, [(speed >> 24) & 0xFF, (speed >> 16) & 0xFF, (speed >> 8) & 0xFF, speed & 0xFF]);
  }

  void setSpeedAuto() => _send(msgSetCanSpeed, [0xFF, 0xFF, 0xFF, 0xFF]);

  void setProtocol(String? name) {
    if (name == null) {
      _send(msgSetProtocol, [0]);
    } else {
      final bytes = utf8.encode(name);
      _send(msgSetProtocol, [bytes.length, ...bytes]);
    }
  }

  void sendCommand(String type, bool value) {
    final bytes = utf8.encode(type);
    _send(msgCmd, [bytes.length, ...bytes, value ? 1 : 0]);
  }

  void _send(int type, [List<int>? payload]) => tcp.send(buildFrame(type, payload));
}
