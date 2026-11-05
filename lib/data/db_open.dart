import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import 'database.dart';

const _keyName = 'money_pet_db_key_v1';

/// 取得資料庫金鑰；第一次啟動時自動產生 32 bytes 亂數金鑰，
/// 存在系統安全儲存區（Android Keystore / iOS Keychain），使用者完全無感。
Future<String> _loadOrCreateKey() async {
  const storage = FlutterSecureStorage();
  final existing = await storage.read(key: _keyName);
  if (existing != null && existing.isNotEmpty) return existing;
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  final key = base64UrlEncode(bytes);
  await storage.write(key: _keyName, value: key);
  return key;
}

/// 開啟以 SQLCipher 加密的正式資料庫。
Future<cipher.Database> openAppDatabase() async {
  final dir = await cipher.getDatabasesPath();
  final path = p.join(dir, databaseFileName);
  return cipher.openDatabase(
    path,
    password: await _loadOrCreateKey(),
    version: schemaVersion,
    onConfigure: onConfigureDatabase,
    onCreate: onCreateDatabase,
    onUpgrade: onUpgradeDatabase,
  );
}
