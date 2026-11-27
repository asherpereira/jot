import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'store.dart';

class WatchBridge {
  final _channel = const MethodChannel('jot/watch');
  bool get supported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  void listen(Future<void> Function() refresh) {
    if (supported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') await refresh();
      });
    }
  }

  void dispose() {
    if (supported) _channel.setMethodCallHandler(null);
  }

  Future<void> receive(JotStore store) async {
    if (!supported) return;
    final inbox =
        await _channel.invokeMapMethod<String, String?>('pending') ?? {};
    for (final entry in inbox.entries) {
      try {
        final action = jsonDecode(entry.value ?? '');
        if (action is! Map<String, dynamic> || action['id'] != entry.key) {
          throw const FormatException('Invalid watch envelope');
        }
        await store.applyWatch(action);
      } on FormatException {
        // Retrying an invalid payload would block the rest of the inbox.
      }
      // Acknowledge by transport ID. Database and channel failures still retry.
      await _channel.invokeMethod<void>('ack', entry.key);
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
