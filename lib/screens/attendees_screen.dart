import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/queue_item.dart';
import '../models/registration.dart';
import '../providers/attendees_provider.dart';
import '../providers/settings_provider.dart';
import '../services/queue_service.dart';
import '../utils/m3_motion.dart';
import '../widgets/admission_dialogs.dart';
import 'queue_screen.dart';

class AttendeesScreen extends StatefulWidget {
  final int initialTabIndex;

  const AttendeesScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AttendeesScreen> createState() => AttendeesScreenState();
}

class AttendeesScreenState extends State<AttendeesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final SearchController _searchController = SearchController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void switchToQueueTab() {
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  void switchToAttendeesTab() {
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$d.$mo.$y $h:$mi:$s';
  }

  String _formatRelativeTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$d.$mo $h:$mi';
  }

  void _showRegistrationDetails(EventRegistration reg) {
    M3Haptics.vibrateSelection();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = reg.user;
    final queueService = context.read<QueueService>();
    final activeItem = queueService.getActiveItem(reg.id);
    final pendingEntries = queueService.getPendingEntriesCount(reg.id);
    final effectiveRemaining = (reg.remainingEntries - pendingEntries).clamp(0, reg.totalPartySize);
    int selectedCount = reg.isPartyTicket ? (effectiveRemaining > 0 ? effectiveRemaining : 1) : 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(M3Shape.cornerExtraLarge), // 28dp M3 Modal Bottom Sheet
        ),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // M3 Drag Handle
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: Text(
                        (user?.displayName.isNotEmpty ?? false)
                            ? user!.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'Anonymous Attendee',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold, // Title Large Emphasized
                            ),
                          ),
                          if (user?.email != null && user!.email!.isNotEmpty)
                            Text(
                              user.email!,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (reg.isPaymentIncomplete) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                      border: Border.all(color: colorScheme.error, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: colorScheme.onErrorContainer, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PAYMENT NOT COMPLETED',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onErrorContainer,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                reg.paymentErrorMessage,
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _buildDetail(context, 'Ticket UUID', reg.id, isMono: true),
                _buildDetail(context, 'Event', reg.event?.title ?? 'Event'),
                _buildDetail(
                  context,
                  'Payment',
                  reg.isPaymentIncomplete ? 'UNPAID / INCOMPLETE' : 'Completed',
                ),
                _buildDetail(
                  context,
                  'Status',
                  reg.didAttend ? 'Checked In' : (reg.isPaymentIncomplete ? 'Unpaid (Pending Check-In)' : 'Registered (Pending Check-In)'),
                ),
                if (reg.checkInTime != null)
                  _buildDetail(
                    context,
                    'Check-In Time',
                    DateTime.tryParse(reg.checkInTime!) != null
                        ? _formatDateTime(DateTime.parse(reg.checkInTime!))
                        : reg.checkInTime!,
                  ),
                _buildDetail(
                  context,
                  'Group Size',
                  reg.isPartyTicket
                      ? '${reg.totalPartySize} person(s) (1 holder + ${reg.guestCount} guest${reg.guestCount > 1 ? 's' : ''}, ${reg.remainingEntries} left)'
                      : '1 person',
                ),
                if (user?.esnCardNumber != null)
                  _buildDetail(context, 'ESN Card', user!.esnCardNumber!),
                if (user != null && user.phone != null && user.phone!.isNotEmpty)
                  _buildDetail(context, 'Phone', user.phone!),

                const SizedBox(height: 16),
                if (activeItem != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: activeItem.status == QueueStatus.failedManual
                          ? colorScheme.errorContainer
                          : colorScheme.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                      border: Border.all(
                        color: activeItem.status == QueueStatus.failedManual
                            ? colorScheme.error
                            : colorScheme.primary.withValues(alpha: 0.4),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (activeItem.status == QueueStatus.processing)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: colorScheme.primary),
                          )
                        else if (activeItem.status == QueueStatus.failedManual)
                          Icon(Icons.error_outline_rounded, color: colorScheme.onErrorContainer, size: 22)
                        else
                          Icon(Icons.hourglass_top_rounded, color: colorScheme.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            activeItem.status == QueueStatus.processing
                                ? 'Check-in is syncing to server (${activeItem.entriesProcessed}/${activeItem.entriesCount} confirmed)...'
                                : (activeItem.status == QueueStatus.failedManual
                                    ? (activeItem.lastError ?? 'Check-in sync failed.')
                                    : 'Check-in pending sync in background (${activeItem.entriesCount} ${activeItem.entriesCount == 1 ? 'entry' : 'entries'}).'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: activeItem.status == QueueStatus.failedManual
                                  ? colorScheme.onErrorContainer
                                  : colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                () {
                  final settings = context.read<SettingsProvider>().settings;
                  final activeEvents = settings.activeEventIds;
                  final isEventMatched = activeEvents.isEmpty || (reg.event?.id != null && activeEvents.contains(reg.event!.id));
                  final isExpertMode = settings.isExpertMode;

                  if (effectiveRemaining <= 0) return const SizedBox.shrink();

                  // Manual check-in from roster is strictly locked behind Expert Mode — show warning notice if disabled
                  if (!isExpertMode) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Manual roster check-in is locked (enable Expert Mode in Settings to override)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (reg.isPartyTicket && effectiveRemaining > 1) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Party Check-In Count',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '$selectedCount of $effectiveRemaining left',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton.filledTonal(
                                    key: const Key('attendee-group-decrement'),
                                    icon: const Icon(Icons.remove_rounded),
                                    iconSize: 20,
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                                      ),
                                    ),
                                    onPressed: selectedCount > 1
                                        ? () {
                                            M3Haptics.vibrateSelection();
                                            setModalState(() => selectedCount--);
                                          }
                                        : null,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: Text(
                                      '$selectedCount',
                                      style: theme.textTheme.headlineMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  IconButton.filledTonal(
                                    key: const Key('attendee-group-increment'),
                                    icon: const Icon(Icons.add_rounded),
                                    iconSize: 20,
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                                      ),
                                    ),
                                    onPressed: selectedCount < effectiveRemaining
                                        ? () {
                                            M3Haptics.vibrateSelection();
                                            setModalState(() => selectedCount++);
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  OutlinedButton(
                                    key: const Key('attendee-group-quick-one'),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      shape: const StadiumBorder(),
                                      backgroundColor: selectedCount == 1 ? colorScheme.secondaryContainer : null,
                                      foregroundColor: selectedCount == 1 ? colorScheme.onSecondaryContainer : colorScheme.onSurface,
                                    ),
                                    onPressed: () {
                                      M3Haptics.vibrateSelection();
                                      setModalState(() => selectedCount = 1);
                                    },
                                    child: const Text('1 person', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    key: const Key('attendee-group-quick-all'),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      shape: const StadiumBorder(),
                                      backgroundColor: selectedCount == effectiveRemaining ? colorScheme.secondaryContainer : null,
                                      foregroundColor: selectedCount == effectiveRemaining ? colorScheme.onSecondaryContainer : colorScheme.onSurface,
                                    ),
                                    onPressed: () {
                                      M3Haptics.vibrateSelection();
                                      setModalState(() => selectedCount = effectiveRemaining);
                                    },
                                    child: Text('All ($effectiveRemaining)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
                            disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
                            backgroundColor: reg.isPaymentIncomplete ? colorScheme.error : null,
                            foregroundColor: reg.isPaymentIncomplete ? colorScheme.onError : null,
                          ),
                          onPressed: !isEventMatched
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final queueService = context.read<QueueService>();
                                  final attendeesProvider = context.read<AttendeesProvider>();
                                  final nav = Navigator.of(ctx);

                                  if (reg.isPaymentIncomplete) {
                                    final confirmed = await showAdmissionConfirmationDialog(
                                      context: ctx,
                                      reg: reg,
                                      count: selectedCount,
                                    );
                                    if (confirmed != true) return;
                                  }

                                  try {
                                    M3Haptics.vibrateAction();
                                    nav.pop();
                                    await queueService.enqueueRegistration(
                                      reg,
                                      count: selectedCount,
                                      manual: true,
                                    );
                                    await attendeesProvider.storageService.updateCachedRegistrationCheckIn(
                                      reg.id,
                                      true,
                                      DateTime.now(),
                                      count: selectedCount,
                                    );
                                    await attendeesProvider.reloadFromStorage();

                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Enqueued check-in for ${user?.displayName} ($selectedCount ${selectedCount == 1 ? 'entry' : 'entries'}) [Expert Mode]'),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  } catch (e) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Failed to enqueue check-in: $e'),
                                        backgroundColor: colorScheme.error,
                                      ),
                                    );
                                  }
                                },
                          icon: Icon(
                            !isEventMatched
                                ? Icons.block_rounded
                                : (reg.isPaymentIncomplete ? Icons.point_of_sale_rounded : Icons.check_circle_outline),
                          ),
                          label: Text(
                            !isEventMatched
                                ? 'Event Mismatch — Check-In Disabled'
                                : (reg.isPaymentIncomplete
                                    ? (reg.isPartyTicket
                                        ? (selectedCount == effectiveRemaining
                                            ? 'Admit Unpaid Group ($selectedCount left) [Expert]'
                                            : 'Admit Unpaid Group ($selectedCount of $effectiveRemaining) [Expert]')
                                        : 'Admit Unpaid Attendee [Expert]')
                                    : (reg.isPartyTicket
                                        ? (selectedCount == effectiveRemaining
                                            ? 'Check In Group ($selectedCount left) [Expert]'
                                            : 'Check In Group ($selectedCount of $effectiveRemaining) [Expert]')
                                        : 'Check In Attendee [Expert]')),
                          ),
                        ),
                      ),
                    ],
                  );
                }(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAttendeeDetails(QueueItem record) {
    M3Haptics.vibrateSelection();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final esnCard = record.rawRegistration?['user']?['esnCardNumber']?.toString();
    final isSynced = record.status == QueueStatus.completed;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(M3Shape.cornerExtraLarge), // 28dp M3 Modal Bottom Sheet
        ),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: Text(
                    record.attendeeName.isNotEmpty
                        ? record.attendeeName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                      Text(
                        record.attendeeName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        record.eventTitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _buildDetail(context, 'Registration ID', record.registrationId, isMono: true),
            _buildDetail(context, 'Checked-in Time', _formatDateTime(record.completedAt ?? record.enqueuedAt)),
            _buildDetail(context, 'Group Size', '${record.entriesCount} person(s)'),
            if (esnCard != null)
              _buildDetail(context, 'ESN Card', esnCard),
            _buildDetail(
              context,
              'Online Sync',
              isSynced ? 'Synced to backend database' : 'Recorded locally (Offline / Queue)',
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, String label, String value, {bool isMono = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: isMono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final attendeesProvider = context.watch<AttendeesProvider>();
    final queueService = context.watch<QueueService>();
    final settings = context.watch<SettingsProvider>().settings;
    final hasEventRegistrations = attendeesProvider.registrations.isNotEmpty || attendeesProvider.currentEvent != null;

    final registrations = attendeesProvider.registrations;
    final sessionAttendees = attendeesProvider.sessionAttendees;
    final pendingCount = queueService.pendingCount;
    final failedCount = queueService.failedManualCount;
    final completedCount = queueService.completedCount;
    final isQueueTab = _tabController.index == 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isQueueTab
              ? 'Check-In Queue'
              : (attendeesProvider.currentEvent?.title ?? 'Attendee List'),
          overflow: TextOverflow.ellipsis,
        ),
        actions: isQueueTab
            ? [
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
              ]
            : [
                if (attendeesProvider.isRefreshing)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh',
                    onPressed: () {
                      M3Haptics.vibrateAction();
                      attendeesProvider.refreshAttendees(force: true);
                    },
                  ),
              ],
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 3, // Primary tab active indicator height: 3dp per M3
          tabs: [
            Tab(
              icon: const Icon(Icons.people_outline),
              text: 'Attendees (${hasEventRegistrations ? registrations.length : sessionAttendees.length})',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: pendingCount > 0 || failedCount > 0,
                label: Text('${pendingCount + failedCount}'),
                backgroundColor: failedCount > 0 ? Colors.red : Colors.amber.shade900,
                child: const Icon(Icons.checklist_rtl_outlined),
              ),
              text: 'Sync Queue',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 0: Attendee List & Search
          RefreshIndicator(
            onRefresh: () => attendeesProvider.refreshAttendees(force: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 1. M3 Expressive Header Status Card (scrolls away)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(M3Shape.cornerLarge),
                      border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              attendeesProvider.isRefreshing
                                  ? Icons.sync
                                  : Icons.cloud_done_rounded,
                              size: 18,
                              color: attendeesProvider.isRefreshing
                                  ? colorScheme.primary
                                  : Colors.teal.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                attendeesProvider.isRefreshing
                                    ? 'Syncing with server...'
                                    : 'Last refreshed: ${_formatRelativeTime(attendeesProvider.lastRefreshedAt)} • Auto-fetch ${settings.autoRefreshMinutes}m',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (attendeesProvider.refreshError != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: colorScheme.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Server busy/offline • Using cached attendee list',
                                  style: TextStyle(fontSize: 11, color: colorScheme.error, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Check-in Progress: ${attendeesProvider.attendedCount} / ${attendeesProvider.totalRegisteredCount}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                              ),
                              child: Text(
                                attendeesProvider.totalRegisteredCount > 0
                                    ? '${((attendeesProvider.attendedCount / attendeesProvider.totalRegisteredCount) * 100).toInt()}%'
                                    : '0%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. M3 SearchBar Component (scrolls away)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SearchBar(
                      controller: _searchController,
                      hintText: 'Search attendee name, email, ticket UUID...',
                      elevation: const WidgetStatePropertyAll(0),
                      backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainerHigh),
                      shape: const WidgetStatePropertyAll(StadiumBorder()),
                      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
                      leading: const Icon(Icons.search),
                      trailing: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              M3Haptics.vibrateSelection();
                              _searchController.clear();
                              attendeesProvider.setSearchQuery('');
                            },
                          ),
                      ],
                      onChanged: (q) => attendeesProvider.setSearchQuery(q),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 6)),

                // 3. Attendee Items List or Empty State
                if (hasEventRegistrations) ...[
                  if (registrations.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_search_rounded, size: 64, color: colorScheme.outline),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'No registrations found for this event'
                                  : 'No matching attendees found',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      sliver: SliverList.separated(
                        itemCount: registrations.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final reg = registrations[index];
                          final user = reg.user;
                          final name = user?.displayName ?? 'Anonymous Attendee';
                          final isAttended = reg.didAttend;
                          final pendingEntries = queueService.getPendingEntriesCount(reg.id);
                          final effectiveRemaining = (reg.remainingEntries - pendingEntries).clamp(0, reg.totalPartySize);

                          return Material(
                            color: colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                              side: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              onTap: () => _showRegistrationDetails(reg),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: isAttended
                                    ? Colors.teal.withValues(alpha: 0.2)
                                    : colorScheme.primaryContainer,
                                foregroundColor: isAttended
                                    ? Colors.teal.shade800
                                    : colorScheme.onPrimaryContainer,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        decoration: isAttended ? TextDecoration.lineThrough : null,
                                        color: isAttended
                                            ? colorScheme.onSurface.withValues(alpha: 0.6)
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (reg.isPartyTicket)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.tertiaryContainer,
                                        borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                                      ),
                                      child: Text(
                                        'PARTY (${reg.totalPartySize})',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onTertiaryContainer,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (user?.email != null && user!.email!.isNotEmpty)
                                    Text(
                                      user.email!,
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                    ),
                                  if (reg.isPartyTicket)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Remaining entries: $effectiveRemaining of ${reg.totalPartySize}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: effectiveRemaining > 0 ? Colors.amber.shade900 : Colors.teal.shade800,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: () {
                                final activeItem = queueService.getActiveItem(reg.id);
                                if (activeItem != null) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                                      border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.8,
                                            color: colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          activeItem.status == QueueStatus.processing
                                              ? 'Syncing (${activeItem.entriesProcessed}/${activeItem.entriesCount})'
                                              : (activeItem.status == QueueStatus.failedManual
                                                  ? 'Sync Failed'
                                                  : 'Syncing (${activeItem.entriesCount})'),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final pendingEntries = queueService.getPendingEntriesCount(reg.id);
                                final effectiveRemaining = (reg.remainingEntries - pendingEntries).clamp(0, reg.totalPartySize);
                                final isFullyAttended = effectiveRemaining <= 0;
                                final isPartiallyAttended = effectiveRemaining > 0 && effectiveRemaining < reg.totalPartySize;
                                final Color bg;
                                final Color fg;
                                final IconData icon;
                                final String label;

                                if (isFullyAttended) {
                                  bg = Colors.teal.withValues(alpha: 0.15);
                                  fg = Colors.teal.shade800;
                                  icon = Icons.check_circle;
                                  label = 'Attended';
                                } else if (reg.isPaymentIncomplete) {
                                  bg = colorScheme.errorContainer;
                                  fg = colorScheme.onErrorContainer;
                                  icon = Icons.error_outline_rounded;
                                  label = reg.isPartyTicket
                                      ? (isPartiallyAttended
                                          ? 'Unpaid ($effectiveRemaining Left)'
                                          : 'Unpaid (${reg.totalPartySize})')
                                      : 'Unpaid';
                                } else if (isPartiallyAttended) {
                                  bg = Colors.amber.withValues(alpha: 0.25);
                                  fg = Colors.amber.shade900;
                                  icon = Icons.group_outlined;
                                  label = '$effectiveRemaining Left';
                                } else {
                                  bg = colorScheme.surfaceContainerHighest;
                                  fg = colorScheme.onSurfaceVariant;
                                  icon = Icons.hourglass_empty_rounded;
                                  label = 'Waiting';
                                }

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                                    border: Border.all(color: fg.withValues(alpha: 0.3), width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon, size: 14, color: fg),
                                      const SizedBox(width: 4),
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: fg,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }(),
                            ),
                          );
                        },
                      ),
                    ),
                ] else ...[
                  if (sessionAttendees.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: colorScheme.outline),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'No attendee records cached yet'
                                  : 'No matching attendees found',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Configure an Event ID in Settings to load the event list',
                              style: TextStyle(fontSize: 12, color: colorScheme.outline),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      sliver: SliverList.separated(
                        itemCount: sessionAttendees.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final record = sessionAttendees[index];
                          return Material(
                            color: colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                              side: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              onTap: () => _showAttendeeDetails(record),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: colorScheme.primaryContainer,
                                foregroundColor: colorScheme.onPrimaryContainer,
                                child: Text(
                                  record.attendeeName.isNotEmpty ? record.attendeeName[0].toUpperCase() : '?',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                record.attendeeName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              subtitle: Text(
                                '${record.eventTitle} • ${_formatDateTime(record.completedAt ?? record.enqueuedAt)}',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              ),
                              trailing: Icon(
                                record.status == QueueStatus.completed ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                                color: record.status == QueueStatus.completed ? Colors.green.shade700 : colorScheme.outline,
                                size: 22,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
      // Tab 1: Embedded Sync Queue
      const QueueScreen(showAppBar: false),
    ],
  ),
);
}
}
