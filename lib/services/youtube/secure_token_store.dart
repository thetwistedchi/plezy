import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart' show CRYPT_INTEGER_BLOB, CryptProtectData, CryptUnprotectData, LocalFree;

/// Stores one secret string. On Windows it is encrypted with DPAPI
/// (CryptProtectData, bound to the Windows user account) and kept in a file
/// in the app's support folder; elsewhere it falls back to shared
/// preferences.
class SecureTokenStore {
  SecureTokenStore(this.name);

  final String name;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name.bin');
  }

  Future<String?> read() async {
    if (!Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('secure_$name');
    }
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final plain = _unprotect(await file.readAsBytes());
      return plain == null ? null : utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String? value) async {
    if (!Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      if (value == null || value.isEmpty) {
        await prefs.remove('secure_$name');
      } else {
        await prefs.setString('secure_$name', value);
      }
      return;
    }
    final file = await _file();
    if (value == null || value.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    final encrypted = _protect(Uint8List.fromList(utf8.encode(value)));
    if (encrypted == null) throw StateError('Windows could not encrypt the token.');
    await file.writeAsBytes(encrypted, flush: true);
  }

  static Uint8List? _protect(Uint8List data) => _crypt(data, protect: true);

  static Uint8List? _unprotect(Uint8List data) => _crypt(data, protect: false);

  static Uint8List? _crypt(Uint8List data, {required bool protect}) {
    final input = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    final buffer = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = buffer;
      final ok = protect
          ? CryptProtectData(input, nullptr, nullptr, nullptr, nullptr, 0, output)
          : CryptUnprotectData(input, nullptr, nullptr, nullptr, nullptr, 0, output);
      if (ok == 0) return null;
      final result = Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      LocalFree(output.ref.pbData);
      return result;
    } finally {
      calloc.free(buffer);
      calloc.free(input);
      calloc.free(output);
    }
  }
}
