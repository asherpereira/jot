import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jot/store.dart';
import 'package:jot/watch_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a bad watch message cannot hide later captures, and a lost acknowledgement retries once',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final store = JotStore(NativeDatabase.memory());
      addTearDown(store.close);
      const channel = MethodChannel('jot/watch');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final capture = {
        'id': 'valid',
        'kind': 'capture',
        'text': 'Maths homework',
      };
      final inbox = <String, String?>{
        'empty': null,
        'unreadable': '{',
        'wrong-shape': '[]',
        'mismatched': jsonEncode({...capture, 'id': 'another-action'}),
        'bad-date': jsonEncode({...capture, 'id': 'bad-date', 'localDate': 42}),
        'valid': jsonEncode(capture),
      };
      var disconnect = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pending') return Map.of(inbox);
        expect(call.method, 'ack');
        if (call.arguments == 'valid' && disconnect) {
          disconnect = false;
          throw PlatformException(code: 'watch_disconnected');
        }
        inbox.remove(call.arguments);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final bridge = WatchBridge();
      await expectLater(
        bridge.receive(store),
        throwsA(isA<PlatformException>()),
      );
      expect(inbox.keys, ['valid']);
      expect((await store.tasks()).single.draft.title, 'Maths homework');
      await bridge.receive(store);
      expect(inbox, isEmpty);
      expect((await store.tasks()).single.draft.title, 'Maths homework');
    },
  );
}
