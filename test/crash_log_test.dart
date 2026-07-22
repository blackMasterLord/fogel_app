import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fogel_app/utils/crash_log.dart';

void main() {
  group('crash_log', () {
    tearDown(() {
      final f = crashLogFile;
      if (f.existsSync()) f.deleteSync();
    });

    test('crashLogFile path ends with fogel_crash.log', () {
      expect(crashLogFile.path, endsWith('fogel_crash.log'));
    });

    test('crashLogFile is in system temp', () {
      expect(crashLogFile.path, contains('Temp'));
    });

    test('crashLogName matches constant', () {
      expect(crashLogName, equals('fogel_crash.log'));
    });

    test('write and read works', () {
      crashLogFile.writeAsStringSync('test entry');
      expect(crashLogFile.existsSync(), isTrue);
      expect(crashLogFile.readAsStringSync(), contains('test entry'));
    });

    test('append does not overwrite', () {
      crashLogFile.writeAsStringSync('first\n');
      crashLogFile.writeAsStringSync('second\n', mode: FileMode.append);
      final content = crashLogFile.readAsStringSync();
      expect(content, contains('first'));
      expect(content, contains('second'));
      expect(content.indexOf('first'), lessThan(content.indexOf('second')));
    });
  });
}
