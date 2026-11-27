import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jot/capture.dart';
import 'package:jot/editor.dart';

void main() {
  testWidgets('capture, review, edit and save from the phone editor', (tester) async {
    CaptureDraft? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(body: TextButton(
        onPressed: () async {
          result = await Navigator.of(context).push<CaptureDraft>(
            MaterialPageRoute(builder: (_) => const TaskEditor()),
          );
        }, child: const Text('Capture homework'),
      ));
    })));
    await tester.tap(find.text('Capture homework'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first,
        'I have maths homework due this Friday, an hour, remind me to upload my work afterwards');
    await tester.tap(find.text('Review local draft'));
    await tester.pumpAndSettle();
    final title = find.widgetWithText(TextField, 'Homework');
    await tester.enterText(title, 'Finish maths exercises');
    final save = find.text('Save homework');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    for (int i = 0; i < 12 && save.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save.hitTestable());
    await tester.pumpAndSettle();
    expect(result?.title, 'Finish maths exercises');
    expect(result?.subject, 'Maths');
    expect(result?.estimateMinutes, 60);
    expect(result?.afterCompletion, ['Upload my work']);
  });

}
