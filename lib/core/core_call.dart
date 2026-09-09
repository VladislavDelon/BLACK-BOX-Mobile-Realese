import 'dart:convert';
import 'package:flutter/services.dart';

const _channel = MethodChannel('bb/core');

/// Вызов метода Python-ядра. Возвращает Map, декодированный из JSON.
Future<Map<String, dynamic>> coreCall(String method,
    [Map<String, dynamic> args = const {}]) async {
  final String out = await _channel.invokeMethod<String>(
        method,
        {'argsJson': jsonEncode(args)},
      ) ??
      '{"ok": false, "error": "no result"}';
  return jsonDecode(out) as Map<String, dynamic>;
}
