import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../l10n/app_strings.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);
    return SingleChildScrollView(
      child: PageBody(
        child: AsyncView<DashboardData>(
          value: data,
          onRetry: () => ref.invalidate(dashboardProvider),
          builder: (d) => _Content(d: d),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.d});
  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.navDashboard, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 520 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        Widget tile(Widget child) => SizedBox(width: w, child: child);
        return Wrap(spacing: 12, runSpacing: 12, children: [
          tile(StatCard(label: s.projectsWithStates(d.states), value: '${d.projects}', icon: Icons.folder_copy_outlined)),
          tile(StatCard(
              label: s.resources, value: compact(d.resources), icon: Icons.dns_outlined, color: Palette.of(1))),
          tile(StatCard(
              label: s.versions, value: compact(d.versions), icon: Icons.history, color: Palette.of(4))),
          tile(StatCard(
            label: s.lockedProjects,
            value: '${d.locked}',
            icon: d.locked == 0 ? Icons.lock_open : Icons.lock,
            color: d.lockAlerts > 0
                ? Palette.locked
                : (d.locked > 0 ? Palette.modified : Palette.released),
            subtitle: d.lockAlerts > 0 ? s.lockAlertOver(d.lockAlerts, d.lockThresholdMinutes) : null,
          )),
        ]);
      }),
      const SizedBox(height: 16),
      if (d.locks.isNotEmpty) ...[
        _LocksCard(d: d),
        const SizedBox(height: 16),
      ],
      _TwoCol(
        left: SectionCard(title: s.activityTitle, child: _ActivityChart(d.activity)),
        right: SectionCard(title: s.resourcesByType, child: BarList(d.byType)),
      ),
      const SizedBox(height: 16),
      _TwoCol(
        left: SectionCard(title: s.resourcesByProvider, child: Donut(d.byProvider)),
        right: SectionCard(title: s.resourcesByModule, child: BarList(d.byModule)),
      ),
      const SizedBox(height: 16),
      _TwoCol(
        left: SectionCard(title: s.resourcesByProject, child: BarList(d.byProject)),
        right: SectionCard(
          title: s.terraformVersionsInUse,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in d.terraformVersions.entries)
                Tag(s.versionProjects(e.key, e.value), icon: Icons.terminal, color: Palette.of(0)),
            ]),
            const SizedBox(height: 14),
            Text(s.providersInUse, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in d.providersInUse) Tag(p, icon: Icons.extension_outlined, color: Palette.of(1)),
            ]),
            const SizedBox(height: 6),
            Text(
              s.providerVersionNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: s.recentlyModified,
        child: Column(children: [
          for (final p in d.recent)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(p.label),
              subtitle: Text('${relativeTime(s, p.lastModified)} · serial ${p.serial ?? '—'} · TF ${p.terraformVersion ?? '—'}'),
              trailing: LockBadge(lock: p.lock, dense: true),
              onTap: () => context.go(stateLocation(p.stateRef)),
            ),
        ]),
      ),
    ]);
  }
}

class _TwoCol extends StatelessWidget {
  const _TwoCol({required this.left, required this.right});
  final Widget left;
  final Widget right;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(children: [left, const SizedBox(height: 16), right]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ]);
    });
  }
}

class _LocksCard extends StatelessWidget {
  const _LocksCard({required this.d});
  final DashboardData d;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Card(
      color: d.lockAlerts > 0 ? Palette.locked.withValues(alpha: 0.08) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(d.lockAlerts > 0 ? Icons.warning_amber_rounded : Icons.lock, color: Palette.locked),
            const SizedBox(width: 8),
            Text(s.lockedProjects, style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 8),
          for (final l in d.locks)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(l.alert ? Icons.timer_off_outlined : Icons.lock_clock,
                  color: l.alert ? Palette.locked : Palette.modified),
              title: Text(stateLabel(l.stateRef)),
              subtitle: Text(
                  s.whoSince(l.who, l.operation.replaceFirst('OperationType', ''), relativeTime(s, l.since))),
              trailing: l.alert ? Tag(s.alertTag, color: Palette.locked) : null,
              onTap: () => context.go(stateLocation(l.stateRef, extra: {'tab': 'locks'})),
            ),
        ]),
      ),
    );
  }
}

class _ActivityChart extends StatelessWidget {
  const _ActivityChart(this.data);
  final List<DayActivity> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxY = data.fold<int>(1, (m, e) => [m, e.versions, e.locks].reduce((a, b) => a > b ? a : b));
    LineChartBarData line(List<int> v, Color c) => LineChartBarData(
          spots: [for (var i = 0; i < v.length; i++) FlSpot(i.toDouble(), v[i].toDouble())],
          isCurved: true,
          preventCurveOverShooting: true,
          color: c,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.10)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 200,
        child: LineChart(LineChartData(
          minY: 0,
          maxY: (maxY + 1).toDouble(),
          gridData: FlGridData(
              drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 0.5)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: maxY > 6 ? null : 1)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: (data.length / 5).ceilToDouble().clamp(1, 100),
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= data.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(data[i].day.substring(5), style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            line(data.map((e) => e.versions).toList(), Palette.of(0)),
            line(data.map((e) => e.locks).toList(), Palette.of(3)),
          ],
        )),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Tag(context.s.versions, color: Palette.of(0)),
        const SizedBox(width: 8),
        Tag(context.s.navLocks, color: Palette.of(3)),
      ]),
    ]);
  }
}

/// Sorted horizontal bars (maximum value = 100 %).
class BarList extends StatelessWidget {
  const BarList(this.data, {super.key});
  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return Text(context.s.noData);
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxV = entries.first.value.clamp(1, 1 << 30);
    return Column(children: [
      for (var i = 0; i < entries.length && i < 12; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 150,
              child: Text(entries[i].key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: entries[i].value / maxV,
                  minHeight: 10,
                  color: Palette.of(i),
                  backgroundColor: Palette.of(i).withValues(alpha: 0.10),
                ),
              ),
            ),
            SizedBox(width: 44, child: Text('${entries[i].value}', textAlign: TextAlign.end)),
          ]),
        ),
    ]);
  }
}

class Donut extends StatelessWidget {
  const Donut(this.data, {super.key});
  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return Text(context.s.noData);
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    return Row(children: [
      SizedBox(
        width: 160,
        height: 160,
        child: PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 42,
          sections: [
            for (var i = 0; i < entries.length; i++)
              PieChartSectionData(
                value: entries[i].value.toDouble(),
                color: Palette.of(i),
                radius: 22,
                showTitle: false,
              ),
          ],
        )),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < entries.length && i < 8; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: Palette.of(i), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(entries[i].key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                Text('${(entries[i].value * 100 / total).toStringAsFixed(0)}%'),
              ]),
            ),
        ]),
      ),
    ]);
  }
}
