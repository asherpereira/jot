import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jot/capture.dart';
import 'package:jot/store.dart';

void main() {
  const phrase =
      'yo i have maths homework due this friday maybe it will take an hour could u also remind me to upload all my work afterwards';
  test(
    'offline and contract agree on the Friday / one hour / upload example',
    () {
      final fixture = jsonDecode(
        File('contracts/friday.example.json').readAsStringSync(),
      );
      expect(basicCapture(phrase, DateTime(2026, 11, 25)).toJson(), fixture);
      expect(
        CaptureDraft.fromJson(fixture as Map<String, dynamic>).toJson(),
        fixture,
      );
    },
  );
  test(
    'this Friday includes today, next Friday is in the following calendar week',
    () {
      expect(
        basicCapture('Maths due this Friday', DateTime(2026, 11, 27)).dueDate,
        '2026-11-27',
      );
      expect(
        basicCapture('Maths due next Friday', DateTime(2026, 11, 27)).dueDate,
        '2026-12-04',
      );
    },
  );
  test(
    'a retried watch action creates exactly one task with a durable completion reminder',
    () async {
      final db = JotStore(NativeDatabase.memory());
      addTearDown(db.close);
      final event = {
        'id': 'capture-1',
        'kind': 'capture',
        'text': phrase,
        'localDate': '2026-11-25',
      };
      await db.applyWatch(event);
      await db.applyWatch(event);
      final task = (await db.tasks()).single;
      expect(task.pending, isEmpty);
      await db.complete(task.id, true);
      expect((await db.tasks()).single.pending, ['Upload all my work']);
      await db.check(task.id, 'Upload all my work', true, followUp: true);
      expect((await db.tasks()).single.pending, isEmpty);
    },
  );
}
