import 'dart:convert';
import 'package:flutter/services.dart';

const _channel = MethodChannel('bb/core');

/// Вызов метода Python-ядра. Возвращает Map, декодированный из JSON.
Future<Map<String, dynamic>> coreCall(String method,
    [Map<String, dynamic> args = const {}]) async {
  final String out = await _channel.invokeMethod<String>(
        'call_json',
        {'method': method, 'argsJson': jsonEncode(args)},
      ) ??
      '{"ok": false, "error": "no result"}';
  return jsonDecode(out) as Map<String, dynamic>;
}

/// Вызов метода Python-ядра с таймаутом. Если за timeout не ответит,
/// возвращает {'ok': false, 'error': 'timeout'}.
Future<Map<String, dynamic>> coreCallTimeout(String method,
    {Map<String, dynamic> args = const {},
    Duration timeout = const Duration(seconds: 6)}) async {
  final result = await Future.any<String>([
    _channel
        .invokeMethod<String>('call_json', {
          'method': method,
          'argsJson': jsonEncode(args),
        })
        .then((s) => s ?? '{"ok": false, "error": "no result"}'),
    Future.delayed(timeout, () => '{"ok": false, "error": "timeout"}'),
  ]);
  return jsonDecode(result) as Map<String, dynamic>;
}

/// Запуск фонового анализа через foreground-сервис Android.
Future<void> startAnalysisService(Map<String, dynamic> args, {double soundThreshold = 1.5}) async {
  await _channel.invokeMethod('start_analysis_service', {
    'args': jsonEncode(args),
    'sound_threshold': soundThreshold,
  });
}

/// Остановка фонового анализа.
Future<void> stopAnalysisService() async {
  await _channel.invokeMethod('stop_analysis_service');
}
