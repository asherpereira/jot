import 'dart:convert';
import 'dart:io';

String dateKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

class CaptureDraft {
  const CaptureDraft({
    required this.title,
    this.subject,
    this.dueDate,
    this.dueTime,
    this.estimateMinutes,
    this.priority = 'normal',
    this.notes = '',
    this.subtasks = const [],
    this.afterCompletion = const [],
  });

  final String title, priority, notes;
  final String? subject, dueDate, dueTime;
  final int? estimateMinutes;
  final List<String> subtasks, afterCompletion;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'title': title,
    'subject': subject,
    'dueDate': dueDate,
    'dueTime': dueTime,
    'estimateMinutes': estimateMinutes,
    'priority': priority,
    'notes': notes,
    'subtasks': subtasks,
    'afterCompletion': afterCompletion,
  };

  factory CaptureDraft.fromJson(Map<String, dynamic> value) {
    const fields = {
      'version',
      'title',
      'subject',
      'dueDate',
      'dueTime',
      'estimateMinutes',
      'priority',
      'notes',
      'subtasks',
      'afterCompletion',
    };
    Never invalid(String field) =>
        throw FormatException('Check the $field field.');
    if (value.length != fields.length ||
        !value.keys.toSet().containsAll(fields) ||
        value['version'] != 1) {
      invalid('capture version');
    }
    String string(String k, int max, {bool empty = false}) {
      final v = value[k];
      if (v is! String ||
          (!empty && v.trim().isEmpty) ||
          v.runes.length > max) {
        invalid(k);
      }
      return v.trim();
    }

    List<String> list(String k, int max) {
      final v = value[k];
      if (v is! List ||
          v.length > max ||
          v.any(
            (s) => s is! String || s.trim().isEmpty || s.runes.length > 160,
          )) {
        invalid(k);
      }
      return List<String>.from(v.map((s) => (s as String).trim()));
    }

    final date = value['dueDate'];
    if (date != null &&
        (date is! String ||
            !RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(date) ||
            DateTime.tryParse(date) == null ||
            dateKey(DateTime.parse(date)) != date)) {
      invalid('due date');
    }
    final time = value['dueTime'];
    if (time != null &&
        (date == null ||
            time is! String ||
            !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time))) {
      invalid('due time');
    }
    final minutes = value['estimateMinutes'];
    if (minutes != null && (minutes is! int || minutes < 5 || minutes > 240)) {
      invalid('estimate (5–240 minutes)');
    }
    if (!['normal', 'high'].contains(value['priority'])) invalid('priority');
    return CaptureDraft(
      title: string('title', 160),
      subject: value['subject'] == null ? null : string('subject', 80),
      dueDate: date as String?,
      dueTime: time as String?,
      estimateMinutes: minutes as int?,
      priority: value['priority'] as String,
      notes: string('notes', 1600, empty: true),
      subtasks: list('subtasks', 12),
      afterCompletion: list('afterCompletion', 8),
    );
  }
}

const _subjects = [
  'Maths',
  'Mathematics',
  'Biology',
  'English',
  'History',
  'Science',
  'Japanese',
  'Art',
  'Physics',
  'Chemistry',
  'Geography',
  'Computing',
];
const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

// JSON Schema string limits count Unicode code points.
String _limit(String text, int max) =>
    String.fromCharCodes(text.runes.take(max));

CaptureDraft basicCapture(String input, DateTime now) {
  final text = input.trim();
  final reminder = RegExp(
    r'\b(?:(?:could|can) (?:u|you) (?:also )?|also )?remind me to\s+(.+?)\s+(?:afterwards?|afterward|after (?:that|finishing|completion)|when (?:i.m|i am) done)\b',
    caseSensitive: false,
  ).firstMatch(text);
  final work = reminder == null
      ? text
      : (text.substring(0, reminder.start) + text.substring(reminder.end))
            .trim();
  final lower = work.toLowerCase();
  final subject = _subjects
      .where((s) => RegExp('\\b${s.toLowerCase()}\\b').hasMatch(lower))
      .firstOrNull;
  final dayMatch = RegExp(
    r'\b(?:(this|next)\s+)?(mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b',
  ).firstMatch(lower);
  DateTime? due;
  DateTime offset(int days) => DateTime(now.year, now.month, now.day + days);
  final inDays = RegExp(r'\bin (\d{1,3}) days?\b').firstMatch(lower);
  if (lower.contains('tomorrow')) {
    due = offset(1);
  } else if (RegExp(r'\btoday\b').hasMatch(lower)) {
    due = offset(0);
  } else if (inDays != null) {
    due = offset(int.parse(inDays[1]!));
  } else if (dayMatch != null) {
    final weekday = _weekdays.indexOf(dayMatch[2]!.substring(0, 3)) + 1;
    due = offset(
      dayMatch[1] == 'next'
          ? 7 - now.weekday + weekday
          : (weekday - now.weekday) % 7,
    );
  }
  final duration = RegExp(
    r'\b(\d+|an?|one|half an?)\s*(hours?|hrs?|minutes?|mins?)\b',
  ).firstMatch(lower);
  int? minutes;
  if (duration != null) {
    final n =
        num.tryParse(duration[1]!) ??
        (duration[1]!.startsWith('half') ? 0.5 : 1);
    final number = (n * (duration[2]!.startsWith('h') ? 60 : 1)).round();
    if (number >= 5 && number <= 240) minutes = number;
  }
  var title = work
      .replaceFirst(
        RegExp(
          r'^(?:yo\s*[,!]?[ ]*)?(?:i have(?: to)?|i need to)\s+',
          caseSensitive: false,
        ),
        '',
      )
      .split(
        RegExp(
          r'\s+(?:due\b|maybe it will take\b|it will take\b)',
          caseSensitive: false,
        ),
      )
      .first
      .trim();
  if (title.isEmpty) title = text;
  title = title.replaceFirst(RegExp(r'[,.;\s]+$'), '');
  if (title.isEmpty) title = 'Homework';
  title = title[0].toUpperCase() + title.substring(1);
  final follow = reminder?[1]?.trim();
  return CaptureDraft(
    title: _limit(title, 160),
    subject: subject,
    dueDate: due == null ? null : dateKey(due),
    estimateMinutes: minutes,
    notes: text.runes.length > 160 ? _limit(text, 1600) : '',
    afterCompletion: follow == null || follow.isEmpty
        ? []
        : [_limit(follow[0].toUpperCase() + follow.substring(1), 160)],
  );
}

String relayAddress = const String.fromEnvironment('JOT_RELAY_URL');
String _relayToken = const String.fromEnvironment('JOT_ACCESS_TOKEN');

bool get cloudConfigured => relayAddress.isNotEmpty && _relayToken.isNotEmpty;

Uri _relayEndpoint(String address) {
  final uri = Uri.tryParse(address);
  const loopback = {'localhost', '127.0.0.1', '10.0.2.2', '::1'};
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      !(uri.scheme == 'https' ||
          (uri.scheme == 'http' && loopback.contains(uri.host)))) {
    throw const FormatException(
      'Enter the HTTPS address of your relay, or a local loopback address.',
    );
  }
  return uri.resolve('/v1/capture');
}

void configureRelay(String address, String token) {
  _relayEndpoint(address.trim());
  if (token.trim().isEmpty || token.contains(RegExp(r'[\r\n]'))) {
    throw const FormatException('Enter the access token from your relay.');
  }
  relayAddress = address.trim();
  _relayToken = token.trim();
}

Future<CaptureDraft> cloudCapture(String input, DateTime day) async {
  final uri = _relayEndpoint(relayAddress);
  final token = _relayToken;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  Future<CaptureDraft> send() async {
    final req = await client.postUrl(uri);
    req.followRedirects = false;
    req.headers.contentType = ContentType.json;
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    req.write(jsonEncode({'text': input, 'localDate': dateKey(day)}));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('Capture relay returned ${res.statusCode}.');
    }
    final bytes = <int>[];
    await for (final part in res) {
      bytes.addAll(part);
      if (bytes.length > 65536) {
        throw const FormatException('Capture too large.');
      }
    }
    final draft = jsonDecode(utf8.decode(bytes));
    if (draft is! Map<String, dynamic>) {
      throw const FormatException('Expected a homework draft.');
    }
    return CaptureDraft.fromJson(draft);
  }

  try {
    return await send().timeout(const Duration(seconds: 25));
  } finally {
    client.close(force: true);
  }
}
