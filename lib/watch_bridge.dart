import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'store.dart';

class WatchBridge {
  final _channel = const MethodChannel('jot/watch');
  bool get supported => Platform.isIOS || Platform.isAndroid;
  void listen(Future<void> Function() refresh) {
    if (supported)
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') await refresh();
      });
  }

  void dispose() {
    if (supported) _channel.setMethodCallHandler(null);
  }

  Future<void> receive(JotStore store) async {
    if (!supported) return;
    final values = await _channel.invokeListMethod<String>('pending') ?? [];
    for (final json in values) {
      final action = jsonDecode(json) as Map<String, dynamic>;
      await store.applyWatch(action);
      await _channel.invokeMethod<void>('ack', action['id']);
    }
  }

  Future<void> publish(List<Homework> tasks) async {
    if (!supported) return;
    final next = tasks
        .where((t) => !t.done)
        .take(8)
        .map((t) => {'id': t.id, 'title': t.draft.title, 'meta': t.meta});
    await _channel.invokeMethod<void>('publish', jsonEncode(next.toList()));
  }
}
