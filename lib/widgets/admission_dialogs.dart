import 'package:flutter/material.dart';
import '../models/registration.dart';
import '../utils/m3_motion.dart';
import 'm3_swipe_lock.dart';

Future<bool?> showAdmissionConfirmationDialog({
  required BuildContext context,
  required EventRegistration reg,
  int count = 1,
}) {
  M3Haptics.vibrateScanError();
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final colorScheme = theme.colorScheme;

      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(M3Shape.cornerExtraLarge), // 28dp M3 Dialog
        ),
        backgroundColor: colorScheme.surfaceContainerHigh,
        icon: Icon(
          Icons.lock_outline_rounded,
          color: colorScheme.error,
          size: 36,
        ),
        title: Text(
          reg.isPartyTicket
              ? (count == reg.totalPartySize
                  ? 'Confirm Unpaid Group (${reg.totalPartySize})'
                  : 'Confirm Unpaid Admission ($count of ${reg.totalPartySize})')
              : 'Confirm Unpaid Admission',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Payment for ${reg.user?.fullName ?? 'this attendee'} has NOT been completed.',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              if (reg.isPartyTicket) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                    border: Border.all(color: colorScheme.error.withValues(alpha: 0.35), width: 1.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.groups_outlined, size: 18, color: colorScheme.onErrorContainer),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              count == reg.totalPartySize
                                  ? 'Group of ${reg.totalPartySize} (1 holder + ${reg.guestCount} guest${reg.guestCount > 1 ? 's' : ''})'
                                  : 'Admitting $count of ${reg.totalPartySize} people',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Admitting: $count of ${reg.totalPartySize}. Unpaid remaining after: ${reg.remainingEntries - count}.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onErrorContainer),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                Text(
                  'Please verify payment status before admitting.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 6),
              Text(
                'Swipe right to confirm action:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              M3SwipeLock(
                width: 280,
                label: 'Slide to Confirm Admission',
                confirmColor: colorScheme.error,
                onConfirmed: () {
                  Navigator.of(ctx).pop(true);
                },
              ),
            ],
          ),
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () {
                M3Haptics.vibrateSelection();
                Navigator.of(ctx).pop(false);
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
