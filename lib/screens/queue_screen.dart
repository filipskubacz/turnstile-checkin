import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/queue_item.dart';
import '../services/queue_service.dart';
import '../utils/m3_motion.dart';

class QueueScreen extends StatelessWidget {
  final bool showAppBar;

  const QueueScreen({super.key, this.showAppBar = true});

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'N/A';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final queueService = context.watch<QueueService>();
    final items = queueService.items;

    final pendingCount = queueService.pendingCount;
    final failedCount = queueService.failedManualCount;
    final completedCount = queueService.completedCount;

    final content = Column(
      children: [
        // M3 Segmented Tonal Metrics Bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(M3Shape.cornerLarge), // 16dp
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: 'Pending',
                    count: pendingCount,
                    accentColor: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: 'Needs Manual',
                    count: failedCount,
                    accentColor: colorScheme.error,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: 'Completed',
                    count: completedCount,
                    accentColor: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Queue Items List
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.checklist_rounded, size: 64, color: colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          'Check-in queue is empty',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Scanned tickets enqueued for check-in will appear here',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _buildQueueCard(context, item, queueService);
                    },
                  ),
          ),
        ],
      );

    if (!showAppBar) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-In Queue'),
        actions: [
          if (failedCount > 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry All Failed',
              onPressed: () {
                M3Haptics.vibrateAction();
                queueService.retryAllFailed();
              },
            ),
          if (completedCount > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear Completed',
              onPressed: () {
                M3Haptics.vibrateSelection();
                queueService.clearCompleted();
              },
            ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required int count,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(M3Shape.cornerMedium), // 12dp optical inner
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(
    BuildContext context,
    QueueItem item,
    QueueService queueService,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color statusBg;
    Color statusFg;
    Widget statusIcon;
    String statusText;

    switch (item.status) {
      case QueueStatus.pending:
        statusBg = Colors.amber.shade100;
        statusFg = Colors.amber.shade900;
        statusIcon = Icon(Icons.hourglass_empty, size: 14, color: Colors.amber.shade900);
        statusText = 'Pending';
        break;
      case QueueStatus.processing:
        statusBg = colorScheme.primaryContainer;
        statusFg = colorScheme.onPrimaryContainer;
        statusIcon = SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
        );
        statusText = 'Syncing...';
        break;
      case QueueStatus.failedRetrying:
        statusBg = colorScheme.tertiaryContainer;
        statusFg = colorScheme.onTertiaryContainer;
        statusIcon = Icon(Icons.sync, size: 14, color: colorScheme.tertiary);
        statusText = 'Retrying (${item.retryCount}/3)';
        break;
      case QueueStatus.failedManual:
        statusBg = colorScheme.errorContainer;
        statusFg = colorScheme.onErrorContainer;
        statusIcon = Icon(Icons.error_outline, size: 14, color: colorScheme.error);
        statusText = 'Manual Retry';
        break;
      case QueueStatus.completed:
        statusBg = Colors.green.shade100;
        statusFg = Colors.green.shade900;
        statusIcon = const Icon(Icons.check_circle, size: 14, color: Colors.green);
        statusText = 'Completed';
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(M3Shape.cornerMedium), // 12dp
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.attendeeName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.entriesCount > 1) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                          ),
                          child: Text(
                            'Group (${item.entriesProcessed}/${item.entriesCount})',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      statusIcon,
                      const SizedBox(width: 5),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold, // Label Small Emphasized
                          color: statusFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.eventTitle,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Enqueued: ${_formatTime(item.enqueuedAt)}',
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
                if (item.completedAt != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Checked in: ${_formatTime(item.completedAt)}',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
            if (item.lastError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                ),
                child: Text(
                  'Error: ${item.lastError}',
                  style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 11),
                ),
              ),
            ],
            if (item.status == QueueStatus.failedManual) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Dismiss'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      M3Haptics.vibrateSelection();
                      queueService.removeItem(item.id);
                    },
                  ),
                  const SizedBox(width: 8),
                  M3TactilePress(
                    onTap: () {
                      M3Haptics.vibrateAction();
                      queueService.retryItem(item.id);
                    },
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.replay, size: 16),
                      label: const Text(
                        'Retry Now',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        M3Haptics.vibrateAction();
                        queueService.retryItem(item.id);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
