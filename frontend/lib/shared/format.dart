String _two(int n) => n.toString().padLeft(2, '0');

DateTime? parseIso(String? s) => (s == null || s.isEmpty) ? null : DateTime.tryParse(s)?.toLocal();

String shortDateTime(String? iso) {
  final d = parseIso(iso);
  if (d == null) return '—';
  return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// "hace 5 min", "hace 3 h", "hace 2 d".
String relativeTime(String? iso, {DateTime? now}) {
  final d = parseIso(iso);
  if (d == null) return '—';
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.inSeconds < 60) return 'hace instantes';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 48) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} d';
}

String formatDuration(int? seconds) {
  if (seconds == null) return '—';
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  if (h < 48) return '$h h ${m % 60} min';
  return '${h ~/ 24} d ${h % 24} h';
}

String shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

String compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}
