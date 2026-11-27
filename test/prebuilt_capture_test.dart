import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jot/capture.dart';
import 'package:jot/store.dart';

void main() {
  test('a completion reminder survives closing the database and goes away when acknowledged', () async {
    final folder = await Directory.systemTemp.createTemp('jot-storage-test-');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/jot.sqlite');
    var store = JotStore(NativeDatabase(file));
    try {
      await store.save(const CaptureDraft(title: 'Maths', afterCompletion: ['Upload work']));
      final id = (await store.tasks()).single.id;
      await store.complete(id, true);
      await store.close();
      store = JotStore(NativeDatabase(file));
      expect((await store.tasks()).single.pending, ['Upload work']);
      await store.check(id, 'Upload work', true, followUp: true);
      await store.close();
      store = JotStore(NativeDatabase(file));
      expect((await store.tasks()).single.pending, isEmpty);
    } finally {
      await store.close();
    }
  });

  test('a prebuilt client uses a session relay and rejects an invalid reply', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const fixture = CaptureDraft(title: 'Maths', estimateMinutes: 60, afterCompletion: ['Upload']);
    final requests = <Map<String, dynamic>>[];
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join());
      requests.add({'path': request.uri.path, 'auth': request.headers.value('authorization'), 'body': payload});
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(requests.length == 1 ? fixture.toJson() : {'title':'broken'}));
      await request.response.close();
    });
    expect(() => configureRelay('http://school.example', 'token'), throwsFormatException);
    configureRelay('http://127.0.0.1:${server.port}', 'test-token');
    final task = await cloudCapture('maths, one hour, upload afterwards', DateTime(2026,11,25));
    expect(task.toJson(), fixture.toJson());
    expect(requests.single['auth'], 'Bearer test-token');
    expect(requests.single['path'], '/v1/capture');
    expect(requests.single['body']['localDate'], '2026-11-25');
    await expectLater(cloudCapture('another task', DateTime(2026,11,25)), throwsFormatException);
  });
}
