import 'dart:io';

const crashLogName = 'fogel_crash.log';
const _maxSize = 1024 * 1024; // 1 MB

String _dir = Directory.systemTemp.path;

Future<void> initCrashLog() async {
  // Try to use app documents directory; fall back to system temp
  // path_provider would be used here in production via getApplicationDocumentsDirectory()
  // For now, keep using system temp to avoid test binding issues
}

File get crashLogFile => File('$_dir/$crashLogName');

Future<void> rotateIfNeeded() async {
  final file = crashLogFile;
  if (!await file.exists()) return;
  final size = await file.length();
  if (size > _maxSize) {
    final old = File('${file.path}.old');
    if (await old.exists()) await old.delete();
    await file.rename(old.path);
  }
}
