import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'capture.dart';

class Homework {
  Homework(this.id, this.draft, this.done, this.checked, this.acknowledged);
  final int id;
  final CaptureDraft draft;
  final bool done;
  final Set<String> checked, acknowledged;
  List<String> get pending => done
      ? draft.afterCompletion.where((s) => !acknowledged.contains(s)).toList()
      : [];
  String get meta => [
    draft.subject ?? 'Unassigned',
    if (draft.dueDate != null)
      '${draft.dueDate}${draft.dueTime == null ? '' : ' ${draft.dueTime}'}',
    if (draft.estimateMinutes != null) '${draft.estimateMinutes} min',
  ].join(' · ');
}

class JotStore extends GeneratedDatabase {
  JotStore(super.executor);
  factory JotStore.local() => JotStore(
    LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return NativeDatabase.createInBackground(
        File(path.join(dir.path, 'jot.sqlite')),
      );
    }),
  );
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement("""CREATE TABLE homework (
      id INTEGER PRIMARY KEY AUTOINCREMENT, draft TEXT NOT NULL,
      done INTEGER NOT NULL DEFAULT 0, checked TEXT NOT NULL DEFAULT '[]',
      acknowledged TEXT NOT NULL DEFAULT '[]')""");
      await customStatement('CREATE TABLE watch_receipt (id TEXT PRIMARY KEY)');
    },
  );

  Future<List<Homework>> tasks() async {
    final rows = await customSelect('SELECT * FROM homework ORDER BY id').get();
    final items = rows
        .map(
          (r) => Homework(
            r.read<int>('id'),
            CaptureDraft.fromJson(
              jsonDecode(r.read<String>('draft')) as Map<String, dynamic>,
            ),
            r.read<int>('done') == 1,
            Set<String>.from(jsonDecode(r.read<String>('checked')) as List),
            Set<String>.from(
              jsonDecode(r.read<String>('acknowledged')) as List,
            ),
          ),
        )
        .toList();
    items.sort((a, b) {
      final byDate = (a.draft.dueDate ?? '9999').compareTo(
        b.draft.dueDate ?? '9999',
      );
      if (byDate != 0) return byDate;
      final byPriority = (a.draft.priority == 'high' ? 0 : 1).compareTo(
        b.draft.priority == 'high' ? 0 : 1,
      );
      if (byPriority != 0) return byPriority;
      final byTime = (a.draft.dueTime ?? '24:00').compareTo(
        b.draft.dueTime ?? '24:00',
      );
      return byTime == 0 ? a.id.compareTo(b.id) : byTime;
    });
    return items;
  }

  Future<void> save(CaptureDraft draft, [int? id]) async {
    final payload = jsonEncode(CaptureDraft.fromJson(draft.toJson()).toJson());
    if (id == null) {
      await customStatement('INSERT INTO homework(draft) VALUES (?)', [
        payload,
      ]);
    } else {
      await customStatement('UPDATE homework SET draft = ? WHERE id = ?', [
        payload,
        id,
      ]);
    }
  }

  Future<void> remove(int id) =>
      customStatement('DELETE FROM homework WHERE id = ?', [id]);
  Future<void> restore(Homework task) => customStatement(
    'INSERT INTO homework(id,draft,done,checked,acknowledged) VALUES(?,?,?,?,?)',
    [
      task.id,
      jsonEncode(task.draft.toJson()),
      task.done ? 1 : 0,
      jsonEncode(task.checked.toList()),
      jsonEncode(task.acknowledged.toList()),
    ],
  );

  Future<void> complete(int id, bool done) => customStatement(
    "UPDATE homework SET done = ?, acknowledged = CASE WHEN ? = 0 THEN '[]' ELSE acknowledged END WHERE id = ?",
    [done ? 1 : 0, done ? 1 : 0, id],
  );

  Future<void> check(
    int id,
    String item,
    bool selected, {
    bool followUp = false,
  }) => transaction(() async {
    final column = followUp ? 'acknowledged' : 'checked';
    final row = await customSelect(
      'SELECT $column AS items FROM homework WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).getSingle();
    final values = Set<String>.from(
      jsonDecode(row.read<String>('items')) as List,
    );
    if (selected) {
      values.add(item);
    } else {
      values.remove(item);
    }
    await customStatement('UPDATE homework SET $column = ? WHERE id = ?', [
      jsonEncode(values.toList()),
      id,
    ]);
  });

  Future<void> applyWatch(Map<String, dynamic> action) => transaction(() async {
    final id = action['id'];
    if (id is! String || id.isEmpty)
      throw const FormatException('Missing watch action ID');
    final receipt = await customSelect(
      'SELECT id FROM watch_receipt WHERE id = ?',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();
    if (receipt != null) return;
    if (action['kind'] == 'capture') {
      final text = action['text'];
      if (text is! String || text.trim().isEmpty || text.length > 2000)
        throw const FormatException('Invalid watch capture');
      final day =
          DateTime.tryParse(action['localDate'] as String? ?? '') ??
          DateTime.now();
      await save(basicCapture(text, day));
    } else if (action['kind'] == 'complete') {
      final taskId = action['taskId'];
      if (taskId is! int) throw const FormatException('Invalid watch task ID');
      await complete(taskId, true);
    } else {
      throw const FormatException('Unknown watch action');
    }
    await customStatement('INSERT INTO watch_receipt(id) VALUES (?)', [id]);
  });
}
