import 'dart:io';

const crashLogName = 'fogel_crash.log';

File get crashLogFile => File('${Directory.systemTemp.path}/$crashLogName');
