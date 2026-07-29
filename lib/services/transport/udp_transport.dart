import 'dart:async';
import 'dart:io';
import '../protocol/fogel_protocol.dart';

/// RawDatagramSocket lifecycle management.
class UdpTransport {
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  final StreamController<List<int>> _dataController = StreamController.broadcast();

  Stream<List<int>> get onData => _dataController.stream;

  Future<void> bind(int port) async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _subscription = _socket!.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          try {
            final packet = _socket!.receive();
            if (packet != null && packet.data.isNotEmpty) {
              _dataController.add(packet.data);
            }
          } catch (_) {}
        }
      },
      onError: (e) => _onError(e),
      onDone: _onDone,
    );
  }

  Future<void> rebind(int port) async {
    disconnect();
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _subscription = _socket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final packet = _socket!.receive();
            if (packet != null && packet.data.isNotEmpty) {
              _dataController.add(packet.data);
            }
          }
        },
        onError: (e) => _onError(e),
        onDone: _onDone,
      );
    } catch (_) {}
  }

  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }

  void _onError(dynamic e) {
    disconnect();
    rebind(udpPort);
  }

  void _onDone() {
    disconnect();
    rebind(udpPort);
  }

  void dispose() {
    disconnect();
    _dataController.close();
  }
}
