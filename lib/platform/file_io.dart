import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 把檔案寫到暫存資料夾，再用系統分享選單送出
/// （可存到 Google Drive、檔案、LINE、Email…）。
Future<void> shareTextFiles(Map<String, String> files, {String? text}) async {
  final dir = await getTemporaryDirectory();
  final xfiles = <XFile>[];
  for (final e in files.entries) {
    final f = File('${dir.path}/${e.key}');
    await f.writeAsString(e.value);
    xfiles.add(XFile(f.path));
  }
  await SharePlus.instance.share(ShareParams(files: xfiles, text: text));
}

/// 讓使用者挑一個檔案，回傳文字內容；取消回傳 null。
Future<String?> pickTextFile() async {
  final files = await FilePicker.pickFiles(type: FileType.any);
  if (files.isEmpty) return null;
  return files.first.xFile.readAsString();
}
