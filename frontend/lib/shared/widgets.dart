import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/models.dart';
import 'theme.dart';
import '../l10n/app_strings.dart';

/// Renders an AsyncValue with loading, error (with retry) and data.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorView(error: e, onRetry: onRetry),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is ApiException ? (error as ApiException).detail : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.s.retry),
            ),
          ],
        ]),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.padding});
  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ?trailing,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: c),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Lock status badge: locked / released / no locking detected.
class LockBadge extends StatelessWidget {
  const LockBadge({super.key, required this.lock, this.dense = false});
  final LockInfo lock;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final (IconData icon, Color color, String text) = switch (lock.status) {
      'locked' => (
          lock.alert ? Icons.warning_amber_rounded : Icons.lock,
          Palette.locked,
          lock.alert ? s.lockLockedAlert : s.lockLocked
        ),
      'released' => (Icons.lock_open, Palette.released, s.lockReleased),
      _ => (Icons.help_outline, Palette.unknown, s.lockNoneDetected),
    };
    return Tooltip(
      message: lock.noneDetected
          ? s.lockTipNoneDetected
          : lock.isLocked
              ? '${lock.who} · ${lock.operation}'
              : s.lockTipReleased,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: lock.alert ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: lock.alert ? 0.9 : 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: dense ? 13 : 15, color: color),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: dense ? 11 : 12, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

/// Counts: +added −removed ~modified.
class ChangeCounts extends StatelessWidget {
  const ChangeCounts({super.key, required this.added, required this.removed, required this.modified});
  final int added;
  final int removed;
  final int modified;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, children: [
      Tag('+$added', color: Palette.added),
      Tag('−$removed', color: Palette.removed),
      Tag('~$modified', color: Palette.modified),
    ]);
  }
}

/// Mini bar chart (daily activity).
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 28, this.width = 84});
  final List<int> values;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparkPainter(values, Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    final w = size.width / values.length;
    final paint = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] == 0 ? 2.0 : (values[i] / maxV) * size.height;
      paint.color = color.withValues(alpha: values[i] == 0 ? 0.25 : 1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * w + 1, size.height - h, w - 2, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

/// Centered container with a maximum width for pages.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 1280});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    );
  }
}
