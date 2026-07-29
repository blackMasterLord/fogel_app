import 'package:flutter_test/flutter_test.dart';
import 'package:fogel_app/services/protocol/fogel_protocol.dart';

void main() {
  group('buildFrame', () {
    test('empty payload', () {
      final frame = buildFrame(msgPing);
      expect(frame[0], 0x00); // len hi
      expect(frame[1], 0x01); // len lo (1 = type only)
      expect(frame[2], msgPing); // type
      expect(frame.length, 3); // 2 len + 1 type
    });

    test('with payload', () {
      final frame = buildFrame(msgCmd, [0xAA, 0xBB]);
      expect(frame[0], 0x00);
      expect(frame[1], 0x03); // len = 1(type) + 2(payload) = 3
      expect(frame[2], msgCmd);
      expect(frame[3], 0xAA);
      expect(frame[4], 0xBB);
      expect(frame.length, 5);
    });

    test('length encoding for 256+ bytes', () {
      final payload = List.filled(300, 0xFF);
      final frame = buildFrame(msgGetConfig, payload);
      const len = 1 + 300; // type + payload
      expect(frame[0], (len >> 8) & 0xFF);
      expect(frame[1], len & 0xFF);
    });
  });

  group('readInt16', () {
    test('positive', () {
      expect(readInt16([0x01, 0x02], 0), 0x0102);
    });

    test('zero', () {
      expect(readInt16([0x00, 0x00], 0), 0);
    });
  });

  group('readUint32', () {
    test('positive', () {
      expect(readUint32([0x01, 0x02, 0x03, 0x04], 0), 0x01020304);
    });
  });

  group('constants', () {
    test('msg types are unique', () {
      final clientMsgs = {msgPing, msgTickOk, msgGetConfig, msgGetProtocol, msgSetCanSpeed, msgSetProtocol, msgCmd, msgUdpReg, msgCanClear, msgDeviceInfo};
      final serverMsgs = {msgPong, msgOk, msgFail, msgConfig, msgProtocolDtl, msgSpeedResult, msgProtoResult, msgTick, msgBusy, msgDeviceInfoResp};
      expect(clientMsgs.length, 10);
      expect(serverMsgs.length, 10);
      expect(clientMsgs.intersection(serverMsgs), isEmpty);
    });
  });
}
