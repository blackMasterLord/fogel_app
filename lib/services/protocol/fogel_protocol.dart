import 'dart:typed_data';

/// Binary protocol constants (mirrors settings.h on ESP32)
const int tcpPort = 8888;
const int udpPort = 8889;

// Client → ESP32 message types
const int msgPing = 0x01;
const int msgTickOk = 0x02;
const int msgGetConfig = 0x03;
const int msgGetProtocol = 0x04;
const int msgSetCanSpeed = 0x05;
const int msgSetProtocol = 0x06;
const int msgCmd = 0x07;
const int msgUdpReg = 0x08;
const int msgCanClear = 0x09;
const int msgDeviceInfo = 0x0A; // Stage 9: adapter identity request

// ESP32 → Client message types
const int msgPong = 0x81;
const int msgOk = 0x82;
const int msgFail = 0x83;
const int msgConfig = 0x84;
const int msgProtocolDtl = 0x85;
const int msgSpeedResult = 0x86;
const int msgProtoResult = 0x87;
const int msgTick = 0x88;
const int msgBusy = 0x8A;
const int msgDeviceInfoResp = 0x8B; // Stage 9: adapter identity response

// UDP packet type prefixes (mirrors main.cpp)
const int udpTypeCan = 0x01;
const int udpTypeTick = 0x02;

Uint8List buildFrame(int type, [List<int>? payload]) {
  final data = payload;
  final dataLen = data?.length ?? 0;
  final len = 1 + dataLen;
  final buf = Uint8List(2 + len); // LEN(2) + TYPE(1) + DATA
  buf[0] = (len >> 8) & 0xFF;
  buf[1] = len & 0xFF;
  buf[2] = type;
  if (data != null && dataLen > 0) {
    buf.setRange(3, 3 + dataLen, data);
  }
  return buf;
}

int readInt16(List<int> data, int pos) => (data[pos] << 8) | data[pos + 1];

int readUint32(List<int> data, int pos) =>
    ((data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3]);

double? readNullableDouble(List<int> data, int pos, int scale, {int nullSentinel = 0x7FFF}) {
  final raw = readInt16(data, pos);
  if (raw == nullSentinel) return null;
  return raw / scale;
}

class RawFrame {
  final int type;
  final List<int> payload;
  const RawFrame(this.type, this.payload);
}

/// Extract complete frames from buffer. Leftover stays in buffer.
List<RawFrame> extractFrames(List<int> buffer) {
  final frames = <RawFrame>[];
  int pos = 0;
  while (pos + 3 <= buffer.length) {
    final len = (buffer[pos] << 8) | buffer[pos + 1];
    final frameEnd = pos + 2 + len;
    if (frameEnd > buffer.length) break;
    frames.add(RawFrame(buffer[pos + 2], buffer.sublist(pos + 3, frameEnd)));
    pos = frameEnd;
  }
  if (pos > 0) buffer.removeRange(0, pos);
  return frames;
}
