import 'package:flutter/material.dart';
import '../models/queue_item.dart';
import '../models/registration.dart';
import '../providers/scanner_provider.dart';
import '../utils/m3_motion.dart';
import 'admission_dialogs.dart';
import 'm3_shimmer.dart';

class TicketPreviewSheet extends StatefulWidget {
  final EventRegistration registration;
  final ScannerProvider scannerProvider;
  final VoidCallback onDismiss;

  const TicketPreviewSheet({
    super.key,
    required this.registration,
    required this.scannerProvider,
    required this.onDismiss,
  });

  @override
  State<TicketPreviewSheet> createState() => _TicketPreviewSheetState();
}

class _TicketPreviewSheetState extends State<TicketPreviewSheet> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late int _selectedCount;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedCount = widget.registration.remainingEntries > 0
        ? widget.registration.remainingEntries
        : 1;

    _animController = AnimationController(
      vsync: this,
      duration: M3Motion.durationFastSpatial,
    );

    // M3 Expressive Fast Spatial spring curve for snappy bottom sheet entrance
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: M3Motion.expressiveFastSpatial,
      ),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: M3Motion.expressiveDefaultEffects,
      ),
    );

    _animController.forward();
  }

  @override
  void didUpdateWidget(covariant TicketPreviewSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registration.id != widget.registration.id ||
        oldWidget.registration.remainingEntries != widget.registration.remainingEntries) {
      setState(() {
        _selectedCount = widget.registration.remainingEntries > 0
            ? widget.registration.remainingEntries
            : 1;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return 'N/A';
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$d.$mo.$y $h:$mi:$s';
  }

  Future<void> _handleCheckInPressed(BuildContext context) async {
    // If event does not match active event, check-in is strictly disabled
    if (!widget.scannerProvider.isEventMatched) {
      M3Haptics.vibrateScanError();
      return;
    }

    final reg = widget.scannerProvider.currentRegistration ?? widget.registration;
    final pendingCount = widget.scannerProvider.queueService.getPendingEntriesCount(reg.id);
    final effectiveRemaining = (reg.remainingEntries - pendingCount).clamp(0, reg.totalPartySize);

    // If ticket has already been fully used, check-in is strictly impossible (no force check-in)
    if (effectiveRemaining <= 0) {
      M3Haptics.vibrateScanError();
      return;
    }

    final isPaymentIncomplete = reg.isPaymentIncomplete;
    final countToAdmit = _selectedCount.clamp(1, effectiveRemaining);

    // If pending verification / unpaid: require swipe left-to-right confirmation dialog
    if (isPaymentIncomplete) {
      final confirmed = await showAdmissionConfirmationDialog(
        context: context,
        reg: reg,
        count: countToAdmit,
      );

      if (confirmed != true) return;
    }

    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      M3Haptics.vibrateAction();
      await widget.scannerProvider.checkInCurrentTicket(count: countToAdmit);
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      widget.onDismiss();
    } catch (e, st) {
      debugPrint('Error during check-in: $e\n$st');
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during check-in: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.scannerProvider,
        widget.scannerProvider.queueService,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final reg = widget.scannerProvider.currentRegistration ?? widget.registration;
        final user = reg.user;
        final event = reg.event;
        final activeQueueItem = widget.scannerProvider.queueService.getActiveItem(reg.id);
        final isPendingSync = activeQueueItem != null;
        final pendingCount = widget.scannerProvider.queueService.getPendingEntriesCount(reg.id);
        final effectiveRemaining = (reg.remainingEntries - pendingCount).clamp(0, reg.totalPartySize);
        final hasSessionCheckIn = widget.scannerProvider.lastCheckedInCount != null;
        final isAlreadyAttended = effectiveRemaining <= 0 && !hasSessionCheckIn;
        final isEventMatched = widget.scannerProvider.isEventMatched;
        final currentCount = _selectedCount.clamp(1, effectiveRemaining > 0 ? effectiveRemaining : 1);

        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(M3Shape.cornerExtraLarge), // 28dp M3 Bottom Sheet
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // M3 Accessible Drag Handle (48dp hit area, 32x4dp pill)
                      Center(
                        child: Semantics(
                          label: 'Drag handle',
                          button: true,
                          child: InkWell(
                            onTap: widget.onDismiss,
                            borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                            child: Container(
                              width: 48,
                              height: 24,
                              alignment: Alignment.center,
                              child: Container(
                                width: 32,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Online Background Verification Notice
                      if (widget.scannerProvider.isOnlineVerifying) ...[
                        M3Shimmer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.2),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Verifying ticket online in background...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // M3 Warning & Status Banners with Optical Roundness (inner = 28dp - 16dp = 12dp)
                      if (isPendingSync) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: activeQueueItem.status == QueueStatus.failedManual
                                ? colorScheme.errorContainer
                                : colorScheme.primaryContainer.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                            border: Border.all(
                              color: activeQueueItem.status == QueueStatus.failedManual
                                  ? colorScheme.error
                                  : colorScheme.primary.withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (activeQueueItem.status == QueueStatus.processing)
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: colorScheme.primary,
                                      ),
                                    )
                                  else if (activeQueueItem.status == QueueStatus.failedManual)
                                    Icon(Icons.error_outline_rounded, color: colorScheme.onErrorContainer, size: 26)
                                  else
                                    Icon(Icons.hourglass_top_rounded, color: colorScheme.primary, size: 26),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          activeQueueItem.status == QueueStatus.processing
                                              ? 'SYNCING CHECK-IN TO SERVER'
                                              : (activeQueueItem.status == QueueStatus.failedManual
                                                  ? 'SYNC REQUIRES RETRY'
                                                  : 'CHECK-IN PENDING SYNC'),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: activeQueueItem.status == QueueStatus.failedManual
                                                ? colorScheme.onErrorContainer
                                                : colorScheme.primary,
                                            fontSize: 14,
                                            letterSpacing: 0.1,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          activeQueueItem.status == QueueStatus.processing
                                              ? 'Syncing with backend database (${activeQueueItem.entriesProcessed} of ${activeQueueItem.entriesCount} confirmed)...'
                                              : (activeQueueItem.status == QueueStatus.failedManual
                                                  ? (activeQueueItem.lastError ?? 'Check-in sync failed.')
                                                  : '${activeQueueItem.entriesCount} ${activeQueueItem.entriesCount == 1 ? 'admission' : 'admissions'} enqueued for background sync.'),
                                          style: TextStyle(
                                            color: activeQueueItem.status == QueueStatus.failedManual
                                                ? colorScheme.onErrorContainer
                                                : colorScheme.onSurfaceVariant,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (activeQueueItem.entriesCount > 1 && activeQueueItem.status == QueueStatus.processing) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                                  child: LinearProgressIndicator(
                                    value: activeQueueItem.entriesProcessed / activeQueueItem.entriesCount,
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else if (hasSessionCheckIn) ...[
                        // Positive Success Confirmation after checking in entries
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: effectiveRemaining <= 0
                                ? Colors.green.shade50
                                : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                            border: Border.all(
                              color: effectiveRemaining <= 0
                                  ? Colors.green.shade700
                                  : Colors.teal.shade600,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                effectiveRemaining <= 0
                                    ? Icons.check_circle_rounded
                                    : Icons.group_add_rounded,
                                color: effectiveRemaining <= 0
                                    ? Colors.green.shade800
                                    : Colors.teal.shade800,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      effectiveRemaining <= 0
                                          ? 'CHECK-IN COMPLETE'
                                          : 'ADMISSION CONFIRMED',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: effectiveRemaining <= 0
                                            ? Colors.green.shade900
                                            : Colors.teal.shade900,
                                        fontSize: 14,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    Text(
                                      effectiveRemaining <= 0
                                          ? 'Admitted ${widget.scannerProvider.lastCheckedInCount} ${reg.isPartyTicket ? "person(s)" : "attendee"}. All ${reg.totalPartySize} entries checked in.'
                                          : 'Admitted ${widget.scannerProvider.lastCheckedInCount} ${widget.scannerProvider.lastCheckedInCount == 1 ? "person" : "people"}. $effectiveRemaining of ${reg.totalPartySize} entries remaining.',
                                      style: TextStyle(
                                        color: effectiveRemaining <= 0
                                            ? Colors.green.shade900
                                            : Colors.teal.shade900,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else if (isAlreadyAttended) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                            border: Border.all(color: colorScheme.error, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: colorScheme.onErrorContainer, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ALL ENTRIES USED',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onErrorContainer,
                                        fontSize: 14,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    if (reg.checkInTime != null)
                                      Text(
                                        'Previous entry: ${_formatDateTime(reg.checkInTime)}',
                                        style: TextStyle(
                                          color: colorScheme.onErrorContainer,
                                          fontSize: 12,
                                        ),
                                      ),
                                    Text(
                                      'All ${reg.totalPartySize} entries have already been checked in.',
                                      style: TextStyle(
                                        color: colorScheme.onErrorContainer,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else if (reg.isPartiallyAttended) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                            border: Border.all(color: Colors.amber.shade600, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.group_outlined, color: Colors.amber.shade900, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'PARTIALLY CHECKED IN',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.amber.shade900,
                                        fontSize: 14,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    Text(
                                      '$effectiveRemaining of ${reg.totalPartySize} group entries remaining. The accompanying guest can be checked in now.',
                                      style: TextStyle(
                                        color: Colors.amber.shade900,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                  if (reg.isPaymentIncomplete) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                        border: Border.all(color: colorScheme.error, width: 1.4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: colorScheme.onErrorContainer,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'PAYMENT NOT COMPLETED',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: colorScheme.onErrorContainer,
                                        fontSize: 14,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Server indicates payment for this ticket has NOT been completed (Status: ${reg.status}${reg.transactions.isNotEmpty && reg.transactions.first.stripePaymentStatus != null ? ' · Stripe: ${reg.transactions.first.stripePaymentStatus}' : ''}).',
                                      style: TextStyle(
                                        color: colorScheme.onErrorContainer,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (reg.isPartyTicket) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colorScheme.onErrorContainer.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                                border: Border.all(
                                  color: colorScheme.onErrorContainer.withValues(alpha: 0.25),
                                  width: 1.0,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.groups_outlined, size: 18, color: colorScheme.onErrorContainer),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Group Ticket (${reg.totalPartySize} total admissions)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onErrorContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Includes 1 main ticket holder + ${reg.guestCount} accompanying guest(s).\nAdmission for all $effectiveRemaining remaining group entries is pending payment.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onErrorContainer,
                                    ),
                                  ),
                                  if (reg.guestUnitPrice != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Guest Price: €${reg.guestUnitPrice}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],

                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (!isEventMatched && widget.scannerProvider.eventMatchMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                        border: Border.all(color: colorScheme.tertiary, width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_busy, color: colorScheme.onTertiaryContainer, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EVENT MISMATCH',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onTertiaryContainer,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  widget.scannerProvider.eventMatchMessage!,
                                  style: TextStyle(
                                    color: colorScheme.onTertiaryContainer,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Offline Ticket Notice with Retry Action
                  if (widget.scannerProvider.isOfflineFallback) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.5), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_rounded, color: colorScheme.onSecondaryContainer, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'OFFLINE TICKET',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSecondaryContainer,
                                    fontSize: 13,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Server is unreachable. Ticket status might be out of date.',
                                  style: TextStyle(
                                    color: colorScheme.onSecondaryContainer,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              foregroundColor: colorScheme.onSecondaryContainer,
                              side: BorderSide(color: colorScheme.onSecondaryContainer.withValues(alpha: 0.6)),
                            ),
                            onPressed: () {
                              M3Haptics.vibrateSelection();
                              widget.scannerProvider.retryOnline();
                            },
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],


                  // Attendee Card Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.onPrimaryContainer,
                        child: Text(
                          user?.fullName?.isNotEmpty == true
                              ? user!.fullName![0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? 'Guest Attendee',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold, // Title Large Emphasized
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: reg.isPaymentIncomplete
                                        ? colorScheme.errorContainer
                                        : (reg.isSuccessful
                                            ? Colors.green.shade100
                                            : colorScheme.surfaceContainerHighest),
                                    borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                                    border: reg.isPaymentIncomplete
                                        ? Border.all(color: colorScheme.error, width: 1.0)
                                        : null,
                                  ),
                                  child: Text(
                                    reg.isPaymentIncomplete ? 'UNPAID' : reg.status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold, // Label Small Emphasized
                                      color: reg.isPaymentIncomplete
                                          ? colorScheme.onErrorContainer
                                          : (reg.isSuccessful
                                              ? Colors.green.shade900
                                              : colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                                if (reg.totalPartySize > 1) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                                    ),
                                    child: Text(
                                      'Party ($effectiveRemaining/${reg.totalPartySize})',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                                  ),
                                  child: Text(
                                    reg.type,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 28),

                  // Event & Ticket Details
                  _buildDetailRow(
                    context,
                    icon: Icons.confirmation_number_outlined,
                    label: 'Event',
                    value: event?.title ?? 'N/A',
                  ),
                  const SizedBox(height: 10),
                  _buildDetailRow(
                    context,
                    icon: Icons.payments_outlined,
                    label: 'Payment',
                    value: reg.isPaymentIncomplete
                        ? 'UNPAID (Pending/Incomplete)'
                        : 'Completed',
                  ),
                  const SizedBox(height: 10),
                  _buildDetailRow(
                    context,
                    icon: Icons.people_outline,
                    label: 'Group Size',
                    value: reg.isPartyTicket
                        ? '${reg.totalPartySize} person(s) (1 holder + ${reg.guestCount} guest${reg.guestCount > 1 ? 's' : ''}, $effectiveRemaining remaining)'
                        : '1 person (Single attendee)',
                  ),
                  if (user?.esnCardNumber != null) ...[
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      context,
                      icon: Icons.badge_outlined,
                      label: 'ESN Card',
                      value: '${user!.esnCardNumber} (Valid: ${user.esnCardValidUntil ?? 'Unknown'})',
                    ),
                  ],
                  const SizedBox(height: 10),
                  _buildDetailRow(
                    context,
                    icon: Icons.fingerprint,
                    label: 'UUID',
                    value: reg.id,
                    isMonospace: true,
                  ),

                  // Group Check-in Quantity Selector (1 to N people)
                  if (!isPendingSync && reg.isPartyTicket && effectiveRemaining > 1)
                    _buildQuantitySelector(context, effectiveRemaining, reg, currentCount),

                  const SizedBox(height: 26),

                  // M3 Expressive Action Buttons (56dp height, CornerFull)
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () {
                                  M3Haptics.vibrateSelection();
                                  widget.onDismiss();
                                },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56), // M3 ButtonMedium height
                            shape: const StadiumBorder(),
                            side: BorderSide(color: colorScheme.outline, width: 1.0),
                          ),
                          child: Text(
                            isPendingSync
                                ? 'Scan Next'
                                : (effectiveRemaining <= 0 ? 'Close' : 'Cancel'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: isPendingSync
                            ? FilledButton.icon(
                                onPressed: () {
                                  M3Haptics.vibrateSelection();
                                  if (activeQueueItem.status == QueueStatus.failedManual) {
                                    widget.scannerProvider.queueService.retryItem(activeQueueItem.id);
                                  } else {
                                    widget.onDismiss();
                                  }
                                },
                                icon: activeQueueItem.status == QueueStatus.processing
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colorScheme.onPrimary,
                                        ),
                                      )
                                    : (activeQueueItem.status == QueueStatus.failedManual
                                        ? const Icon(Icons.refresh, size: 20)
                                        : const Icon(Icons.check_circle_outline, size: 22)),
                                label: Text(
                                  activeQueueItem.status == QueueStatus.processing
                                      ? 'Syncing (${activeQueueItem.entriesProcessed}/${activeQueueItem.entriesCount})...'
                                      : (activeQueueItem.status == QueueStatus.failedManual
                                          ? 'Retry Sync'
                                          : 'Done (Pending Sync)'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold, // Label Large Emphasized
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(56), // M3 ButtonMedium height
                                  backgroundColor: activeQueueItem.status == QueueStatus.failedManual
                                      ? colorScheme.error
                                      : colorScheme.primary,
                                  foregroundColor: activeQueueItem.status == QueueStatus.failedManual
                                      ? colorScheme.onError
                                      : colorScheme.onPrimary,
                                  shape: const StadiumBorder(),
                                  elevation: 2,
                                ),
                              )
                            : (effectiveRemaining <= 0)
                                ? FilledButton.icon(
                                    onPressed: () {
                                      M3Haptics.vibrateSelection();
                                      widget.onDismiss();
                                    },
                                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                                    label: const Text(
                                      'Scan Next',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold, // Label Large Emphasized
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(56),
                                      backgroundColor: hasSessionCheckIn
                                          ? Colors.green.shade700
                                          : colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: const StadiumBorder(),
                                      elevation: 2,
                                    ),
                                  )
                                : FilledButton.icon(
                                    onPressed: (_isSubmitting || !isEventMatched)
                                        ? null
                                        : () => _handleCheckInPressed(context),
                                    icon: _isSubmitting
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              color: reg.isPaymentIncomplete
                                                  ? colorScheme.onError
                                                  : colorScheme.onPrimary,
                                            ),
                                          )
                                        : Icon(
                                            !isEventMatched
                                                ? Icons.block_rounded
                                                : (reg.isPaymentIncomplete
                                                    ? Icons.point_of_sale_rounded
                                                    : Icons.check_circle_outline),
                                            size: 22,
                                          ),
                                    label: Text(
                                      _isSubmitting
                                          ? 'Checking In...'
                                          : _getButtonLabel(
                                              reg: reg,
                                              effectiveRemaining: effectiveRemaining,
                                              selectedCount: currentCount,
                                              isEventMatched: isEventMatched,
                                              isAlreadyAttended: isAlreadyAttended,
                                              hasSessionCheckIn: hasSessionCheckIn,
                                            ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(56),
                                      disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
                                      disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
                                      backgroundColor: reg.isPaymentIncomplete
                                          ? colorScheme.error
                                          : colorScheme.primary,
                                      foregroundColor: reg.isPaymentIncomplete
                                          ? colorScheme.onError
                                          : colorScheme.onPrimary,
                                      shape: const StadiumBorder(),
                                    ),
                                  ),
                      ),
                    ],
                  ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  }

  String _getButtonLabel({
    required EventRegistration reg,
    required int effectiveRemaining,
    required int selectedCount,
    required bool isEventMatched,
    required bool isAlreadyAttended,
    required bool hasSessionCheckIn,
  }) {
    if (!isEventMatched) {
      return 'Event Mismatch — Check-In Disabled';
    }
    if (hasSessionCheckIn && effectiveRemaining <= 0) {
      return 'Scan Next (Completed)';
    }
    if (effectiveRemaining <= 0) {
      return 'All Entries Used';
    }

    final isOffline = widget.scannerProvider.isOfflineFallback;
    final offlineSuffix = isOffline ? ' [Offline]' : '';

    if (reg.isPaymentIncomplete) {
      if (reg.isPartyTicket) {
        if (selectedCount == effectiveRemaining) {
          return reg.isPartiallyAttended
              ? 'Admit Unpaid Guest ($effectiveRemaining left)'
              : 'Admit Unpaid Group ($effectiveRemaining left)';
        } else {
          return 'Admit $selectedCount Unpaid (${effectiveRemaining - selectedCount} left)';
        }
      }
      return 'Admit Unpaid Attendee';
    }

    // Fully paid
    if (reg.isPartyTicket) {
      if (reg.isPartiallyAttended) {
        if (selectedCount == effectiveRemaining) {
          return 'Check In Guest ($effectiveRemaining left)$offlineSuffix';
        } else {
          return 'Check In $selectedCount Guest${selectedCount > 1 ? "s" : ""} (${effectiveRemaining - selectedCount} left)$offlineSuffix';
        }
      } else {
        if (selectedCount == reg.totalPartySize) {
          return 'Check In Group (${reg.totalPartySize} entries)$offlineSuffix';
        } else if (selectedCount == 1) {
          return 'Check In 1 Person (${effectiveRemaining - 1} left)$offlineSuffix';
        } else {
          return 'Check In $selectedCount People (${effectiveRemaining - selectedCount} left)$offlineSuffix';
        }
      }
    }

    return isOffline ? 'Check In (Offline)' : 'Check In';
  }

  String _getBreakdownText(EventRegistration reg, int count) {
    final remaining = reg.remainingEntries - count;
    if (!reg.didAttend) {
      if (count == 1) {
        return 'Admitting ticket holder only ($remaining guest${remaining == 1 ? '' : 's'} remaining)';
      } else {
        final guests = count - 1;
        return 'Admitting ticket holder + $guests guest${guests == 1 ? '' : 's'} ($remaining remaining)';
      }
    } else {
      return 'Admitting $count guest${count == 1 ? '' : 's'} ($remaining remaining)';
    }
  }

  Widget _buildQuantitySelector(BuildContext context, int maxEntries, EventRegistration reg, int currentCount) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.people_alt_outlined, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Group Check-In',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                ),
                child: Text(
                  '$maxEntries available',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                key: const Key('group-checkin-decrement'),
                icon: const Icon(Icons.remove_rounded),
                iconSize: 20,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                  ),
                ),
                onPressed: currentCount > 1
                    ? () {
                        M3Haptics.vibrateSelection();
                        setState(() => _selectedCount = currentCount - 1);
                      }
                    : null,
              ),
              const SizedBox(width: 24),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$currentCount',
                    key: const Key('group-checkin-count'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  Text(
                    currentCount == 1 ? 'person' : 'people',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              IconButton.filledTonal(
                key: const Key('group-checkin-increment'),
                icon: const Icon(Icons.add_rounded),
                iconSize: 20,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                  ),
                ),
                onPressed: currentCount < maxEntries
                    ? () {
                        M3Haptics.vibrateSelection();
                        setState(() => _selectedCount = currentCount + 1);
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                key: const Key('group-checkin-quick-one'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: const StadiumBorder(),
                  backgroundColor: currentCount == 1 ? colorScheme.secondaryContainer : null,
                  foregroundColor: currentCount == 1 ? colorScheme.onSecondaryContainer : colorScheme.onSurface,
                ),
                onPressed: () {
                  M3Haptics.vibrateSelection();
                  setState(() => _selectedCount = 1);
                },
                child: const Text('1 person', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('group-checkin-quick-all'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: const StadiumBorder(),
                  backgroundColor: currentCount == maxEntries ? colorScheme.secondaryContainer : null,
                  foregroundColor: currentCount == maxEntries ? colorScheme.onSecondaryContainer : colorScheme.onSurface,
                ),
                onPressed: () {
                  M3Haptics.vibrateSelection();
                  setState(() => _selectedCount = maxEntries);
                },
                child: Text('All ($maxEntries)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _getBreakdownText(reg, currentCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }


  Widget _buildDetailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool isMonospace = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: isMonospace
                ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                : theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
