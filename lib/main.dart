import 'dart:async';
import 'dart:ui' show DisplayFeatureType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'capture.dart';
import 'editor.dart';
import 'store.dart';
import 'watch_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JotApp());
}

class JotApp extends StatelessWidget {
  const JotApp({super.key});
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff3b5bdb),
          brightness: brightness,
        ).copyWith(
          primary: Color(dark ? 0xff8ea2ff : 0xff3b5bdb),
          primaryContainer: Color(dark ? 0xff232c55 : 0xffe3e9ff),
          surface: Color(dark ? 0xff181c24 : 0xffffffff),
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Lexend',
      colorScheme: colors,
      brightness: brightness,
      scaffoldBackgroundColor: Color(dark ? 0xff101319 : 0xfff7f8fa),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Color(dark ? 0xff101319 : 0xfff7f8fa),
        scrolledUnderElevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Jot',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    home: const Desk(),
  );
}

const destinations = ['Today', 'Plan', 'Subjects', 'Insights'];
const icons = [
  Icons.wb_sunny_outlined,
  Icons.calendar_month_outlined,
  Icons.bookmarks_outlined,
  Icons.bar_chart,
];
const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String dayLabel(DateTime d) =>
    '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';

class Desk extends StatefulWidget {
  const Desk({super.key});
  @override
  State<Desk> createState() => _DeskState();
}

class _DeskState extends State<Desk> with WidgetsBindingObserver {
  final db = JotStore.local();
  final bridge = WatchBridge();
  List<Homework> tasks = [];
  bool loading = true, refreshing = false, refreshAgain = false;
  int tab = 0, weekOffset = 0;
  int? selected;
  String? failure;
  Timer? midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bridge.listen(refresh);
    refresh();
    scheduleMidnight();
  }

  void scheduleMidnight() {
    midnight?.cancel();
    final now = DateTime.now();
    midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        if (mounted) {
          setState(() {});
          scheduleMidnight();
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      scheduleMidnight();
    }
  }

  @override
  void dispose() {
    midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    bridge.dispose();
    db.close();
    super.dispose();
  }

  Future<void> refresh() async {
    if (refreshing) {
      refreshAgain = true;
      return;
    }
    refreshing = true;
    try {
      do {
        refreshAgain = false;
        // Local UI must work on devices without a paired watch or Play Services.
        final local = await db.tasks();
        if (!mounted) return;
        setState(() {
          tasks = local;
          loading = false;
          failure = null;
        });
        if (bridge.supported) {
          try {
            await bridge.receive(db);
            final updated = await db.tasks();
            if (!mounted) return;
            setState(() => tasks = updated);
            await bridge.publish(updated);
          } on PlatformException {
            /* The next resume retries the durable watch inbox. */
          }
        }
      } while (mounted && refreshAgain);
    } catch (_) {
      if (mounted)
        setState(() {
          failure = 'Your homework could not be loaded.';
          loading = false;
        });
    } finally {
      refreshing = false;
    }
  }

  Future<void> change(Future<void> Function() operation) async {
    try {
      await operation();
      final updated = await db.tasks();
      if (!mounted) return;
      setState(() => tasks = updated);
      unawaited(refresh());
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')),
        );
    }
  }

  Future<void> edit([Homework? item]) async {
    final draft = await Navigator.push<CaptureDraft>(
      context,
      MaterialPageRoute(builder: (_) => TaskEditor(initial: item?.draft)),
    );
    if (draft != null && mounted) await change(() => db.save(draft, item?.id));
  }

  Future<void> remove(Homework task, {required bool sheet}) async {
    try {
      await db.remove(task.id);
      if (!mounted) return;
      if (sheet) Navigator.of(context).pop();
      if (selected == task.id) setState(() => selected = null);
      await refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Homework deleted.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => change(() => db.restore(task)),
          ),
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete. Please try again.')),
        );
    }
  }

  Future<void> toggle(Homework item) =>
      change(() => db.complete(item.id, !item.done));
  void open(Homework item, bool split) {
    if (split) {
      setState(() => selected = item.id);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .82,
        child: StatefulBuilder(
          builder: (context, update) {
            final current =
                tasks.where((t) => t.id == item.id).firstOrNull ?? item;
            return details(
              current,
              after: () {
                if (context.mounted) update(() {});
              },
            );
          },
        ),
      ),
    );
  }

  Widget details(Homework task, {VoidCallback? after}) {
    Future<void> run(Future<void> Function() operation) async {
      await operation();
      after?.call();
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          task.draft.subject ?? 'Unassigned',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Text(
          task.draft.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(task.meta),
        if (task.draft.priority == 'high')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('High priority'),
          ),
        if (task.draft.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(task.draft.notes),
          ),
        if (task.draft.subtasks.isNotEmpty) section('Steps'),
        for (final step in task.draft.subtasks)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(step),
            value: task.checked.contains(step),
            onChanged: (v) =>
                run(() => change(() => db.check(task.id, step, v!))),
          ),
        if (task.draft.afterCompletion.isNotEmpty) section('After finishing'),
        for (final step in task.draft.afterCompletion)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(step),
            value: task.acknowledged.contains(step),
            onChanged: task.done
                ? (v) => run(
                    () => change(
                      () => db.check(task.id, step, v!, followUp: true),
                    ),
                  )
                : null,
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => run(() => toggle(task)),
          icon: Icon(task.done ? Icons.undo : Icons.check),
          label: Text(task.done ? 'Reopen homework' : 'Mark complete'),
        ),
        TextButton(
          onPressed: () => run(() => edit(task)),
          child: const Text('Edit homework'),
        ),
        TextButton(
          onPressed: () => remove(task, sheet: after != null),
          child: const Text('Delete homework'),
        ),
      ],
    );
  }

  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
  Widget row(Homework task, bool split) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 4),
    child: ListTile(
      selected: split && selected == task.id,
      leading: IconButton(
        tooltip: task.done ? 'Reopen homework' : 'Mark complete',
        icon: Icon(
          task.done ? Icons.check_circle : Icons.radio_button_unchecked,
        ),
        onPressed: () => toggle(task),
      ),
      title: Text(task.draft.title),
      subtitle: Text(task.meta),
      onTap: () => open(task, split),
    ),
  );
  List<Widget> group(String title, Iterable<Homework> items, bool split) =>
      items.isEmpty ? [] : [section(title), ...items.map((t) => row(t, split))];
  List<Widget> today(bool split) {
    final now = DateTime.now(), openTasks = tasks.where((t) => !t.done);
    final day = dateKey(now),
        upcoming = dateKey(DateTime(now.year, now.month, now.day + 3));
    final next = openTasks.firstOrNull;
    return [
      Text(dayLabel(now), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.near_me_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Next action',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                next?.draft.title ?? 'Nothing due. Enjoy the space.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (next != null) ...[
                const SizedBox(height: 8),
                Text(next.meta),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => open(next, split),
                  child: const Text('Open homework'),
                ),
              ],
            ],
          ),
        ),
      ),
      if (tasks.any((t) => t.pending.isNotEmpty)) section('After finishing'),
      for (final task in tasks)
        for (final item in task.pending)
          CheckboxListTile(
            value: false,
            title: Text(item),
            subtitle: Text(task.draft.title),
            onChanged: (_) =>
                change(() => db.check(task.id, item, true, followUp: true)),
          ),
      ...group(
        'Due today',
        openTasks.where((t) => t.draft.dueDate == day),
        split,
      ),
      ...group(
        'Needs a new date',
        openTasks.where((t) => (t.draft.dueDate ?? day).compareTo(day) < 0),
        split,
      ),
      ...group(
        'Coming up',
        openTasks.where(
          (t) =>
              t.draft.dueDate != null &&
              t.draft.dueDate!.compareTo(day) > 0 &&
              t.draft.dueDate!.compareTo(upcoming) <= 0,
        ),
        split,
      ),
      ...group(
        'Later',
        openTasks.where(
          (t) =>
              t.draft.dueDate != null &&
              t.draft.dueDate!.compareTo(upcoming) > 0,
        ),
        split,
      ),
      ...group(
        'Unscheduled',
        openTasks.where((t) => t.draft.dueDate == null),
        split,
      ),
      ...group('Completed', tasks.where((t) => t.done), split),
    ];
  }

  List<Widget> plan(bool split) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day - now.weekday + 1 + weekOffset * 7,
    );
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              'Week of ${dayLabel(start)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Previous week',
            onPressed: () => setState(() => weekOffset--),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Next week',
            onPressed: () => setState(() => weekOffset++),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      for (int i = 0; i < 7; i++)
        ...dayPlan(DateTime(start.year, start.month, start.day + i), split),
    ];
  }

  List<Widget> dayPlan(DateTime date, bool split) {
    final items = tasks.where((t) => t.draft.dueDate == dateKey(date));
    return [
      section(dayLabel(date)),
      if (items.isEmpty)
        const Text('Nothing scheduled.')
      else
        ...items.map((t) => row(t, split)),
    ];
  }

  Widget content(bool split) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (failure != null)
      return Center(
        child: TextButton(onPressed: refresh, child: Text('$failure Retry')),
      );
    final subjects =
        tasks.map((t) => t.draft.subject ?? 'Unassigned').toSet().toList()
          ..sort();
    final widgets = switch (tab) {
      0 => today(split),
      1 => plan(split),
      2 => [
        if (subjects.isEmpty)
          const Text('Add a subject when you capture your first homework.'),
        for (final s in subjects)
          ...group(
            s,
            tasks.where((t) => (t.draft.subject ?? 'Unassigned') == s),
            split,
          ),
      ],
      _ => [
        section('Homework overview'),
        for (final entry in {
          'Open': tasks.where((t) => !t.done).length,
          'Completed': tasks.where((t) => t.done).length,
          'Follow-ups remaining': tasks.fold<int>(
            0,
            (v, t) => v + t.pending.length,
          ),
        }.entries)
          ListTile(
            title: Text(entry.key),
            trailing: Text(
              '${entry.value}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
      ],
    };
    return ListView(
      key: PageStorageKey(tab),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      children: widgets,
    );
  }

  Widget layout(double width, Rect? hinge) {
    final rail = width >= 600,
        extended = width >= 1080,
        split =
            rail &&
            (hinge == null || hinge.left >= 300 && width - hinge.right >= 240);
    final current = tasks.where((t) => t.id == selected).firstOrNull;
    final side = current == null
        ? const Center(child: Text('Select homework to see its details.'))
        : details(current);
    final panel = split
        ? (hinge == null
              ? Row(
                  children: [
                    Expanded(flex: 3, child: content(true)),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 2, child: side),
                  ],
                )
              : Row(
                  children: [
                    SizedBox(
                      width: (hinge.left - (extended ? 200 : 72))
                          .clamp(0, width)
                          .toDouble(),
                      child: content(true),
                    ),
                    SizedBox(width: hinge.width),
                    Expanded(child: side),
                  ],
                ))
        : content(false);
    return Scaffold(
      appBar: AppBar(
        title: Text(destinations[tab]),
        actions: [
          if (rail)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: () => edit(),
                icon: const Icon(Icons.add),
                label: const Text('Capture'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            if (rail)
              NavigationRail(
                minWidth: 72,
                minExtendedWidth: 200,
                extended: extended,
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                destinations: [
                  for (int i = 0; i < 4; i++)
                    NavigationRailDestination(
                      icon: Icon(icons[i]),
                      label: Text(destinations[i]),
                    ),
                ],
              ),
            Expanded(child: panel),
          ],
        ),
      ),
      floatingActionButton: rail
          ? null
          : FloatingActionButton.extended(
              onPressed: () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('Capture'),
            ),
      bottomNavigationBar: rail
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [
                for (int i = 0; i < 4; i++)
                  NavigationDestination(
                    icon: Icon(icons[i]),
                    label: destinations[i],
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hinge = MediaQuery.displayFeaturesOf(context)
        .where(
          (f) =>
              f.type == DisplayFeatureType.hinge ||
              f.type == DisplayFeatureType.fold,
        )
        .firstOrNull;
    final vertical = hinge != null && hinge.bounds.height > hinge.bounds.width;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            edit(),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            edit(),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, box) {
            if (vertical &&
                hinge.bounds.left >= 300 &&
                box.maxWidth - hinge.bounds.right >= 240) {
              return layout(box.maxWidth, hinge.bounds);
            }
            return DisplayFeatureSubScreen(
              anchorPoint: Offset.zero,
              child: LayoutBuilder(
                builder: (context, available) =>
                    layout(available.maxWidth, null),
              ),
            );
          },
        ),
      ),
    );
  }
}
