import 'package:flutter_test/flutter_test.dart';

/// Replicates _processTcpBuffer guard logic:
/// After dispatching a message that clears the buffer (like MSG_BUSY → disconnect),
/// the guard `pos > 0 && pos <= buffer.length` prevents RangeError on removeRange.

void processTcpBuffer(List<int> buffer, void Function(int type, List<int> payload) dispatch) {
  int pos = 0;
  while (pos + 3 <= buffer.length) {
    final len = (buffer[pos] << 8) | buffer[pos + 1];
    final frameEnd = pos + 2 + len;
    if (frameEnd > buffer.length) break;

    final type = buffer[pos + 2];
    final payload = buffer.sublist(pos + 3, frameEnd);

    dispatch(type, payload);
    pos = frameEnd;
  }

  // THE GUARD — prevents RangeError when dispatch cleared the buffer
  if (pos > 0 && pos <= buffer.length) {
    buffer.removeRange(0, pos);
  }
}

void main() {
  group('_processTcpBuffer guard', () {
    test('normal frame processing', () {
      final buf = [0x00, 0x01, 0x81]; // LEN=1, TYPE=PONG(0x81)
      final dispatched = <int>[];
      processTcpBuffer(buf, (type, payload) {
        dispatched.add(type);
      });
      expect(dispatched, equals([0x81]));
      expect(buf, isEmpty);
    });

    test('dispatch clears buffer — guard prevents RangeError', () {
      // Simulate receiving MSG_BUSY which triggers disconnect → buffer.clear()
      final buf = [0x00, 0x01, 0x8A]; // LEN=1, TYPE=BUSY(0x8A)
      processTcpBuffer(buf, (type, payload) {
        buf.clear(); // simulate disconnect() side effect
      });
      // Should NOT throw — guard prevents RangeError on empty buffer
      expect(buf, isEmpty);
    });

    test('multiple frames in buffer', () {
      final buf = [
        0x00, 0x01, 0x81, // PONG
        0x00, 0x01, 0x82, // OK
      ];
      final dispatched = <int>[];
      processTcpBuffer(buf, (type, payload) {
        dispatched.add(type);
      });
      expect(dispatched, equals([0x81, 0x82]));
      expect(buf, isEmpty);
    });

    test('incomplete frame at end — preserved in buffer', () {
      final buf = [0x00, 0x03, 0x84, 0x01]; // LEN=3, TYPE=CONFIG, but only 1 data byte
      final dispatched = <int>[];
      processTcpBuffer(buf, (type, payload) {
        dispatched.add(type);
      });
      expect(dispatched, isEmpty);
      expect(buf, equals([0x00, 0x03, 0x84, 0x01])); // preserved
    });

    test('POSITIVE: guard with pos=0 does nothing', () {
      final buf = <int>[];
      // pos=0, guard is false — no crash
      processTcpBuffer(buf, (type, payload) {});
      expect(buf, isEmpty);
    });
  });
}
