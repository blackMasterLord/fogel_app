import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../protocol/fogel_protocol.dart';

/// TCP socket lifecycle management.
class TcpTransport {
  Socket? _socket;
  final List<int> _buffer = [];
  final StreamController<List<int>> _dataController = StreamController.broadcast();
  bool needsReconnect = false;
  bool isReconnecting = false;

  bool get isConnected => _socket != null;
  Stream<List<int>> get onData => _dataController.stream;

  Future<void> connect(String host, int port) async {
    _socket = await Socket.connect(host, port);
    _socket!.listen(
      (data) {
        _buffer.addAll(data);
        final frames = extractFrames(_buffer);
        for (final f in frames) {
          _dataController.add([f.type, ...f.payload]);
        }
      },
      onDone: _onDone,
      onError: _onError,
    );
  }

  void send(Uint8List data) {
    if (_socket == null) return;
    try {
      _socket!.add(data);
    } catch (e) {
      // ignore — will be caught by onError
    }
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
    _buffer.clear();
    needsReconnect = false;
  }

  void _onDone() {
    _socket?.close();
    _socket = null;
    needsReconnect = true;
  }

  void _onError(dynamic e) {
    _socket?.close();
    _socket = null;
    needsReconnect = true;
  }

  void dispose() {
    disconnect();
    _dataController.close();
  }
}
