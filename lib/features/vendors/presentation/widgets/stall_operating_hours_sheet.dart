import 'package:flutter/material.dart';
import 'package:palengkego/core/theme/app_theme.dart';
import 'package:palengkego/features/vendors/domain/closing_time.dart';
import 'package:palengkego/features/vendors/domain/day_schedule.dart';

/// Modal bottom sheet presenting the weekly operating schedule of a stall,
/// highlighting today's hours, next opening time, and pre-order fulfillment notes.
class StallOperatingHoursSheet extends StatelessWidget {
  final String stallName;
  final List<DaySchedule> schedule;
  final bool isCurrentlyOpen;
  final NextOpeningTime? nextOpening;

  const StallOperatingHoursSheet({
    super.key,
    required this.stallName,
    required this.schedule,
    required this.isCurrentlyOpen,
    this.nextOpening,
  });

  static Future<void> show(
    BuildContext context, {
    required String stallName,
    required List<DaySchedule> schedule,
    required bool isCurrentlyOpen,
    NextOpeningTime? nextOpening,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StallOperatingHoursSheet(
        stallName: stallName,
        schedule: schedule,
        isCurrentlyOpen: isCurrentlyOpen,
        nextOpening: nextOpening,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const daysOrder = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    // Philippine time day of week
    final nowPh = DateTime.now().toUtc().add(const Duration(hours: 8));
    final todayDayName = daysOrder[nowPh.weekday - 1];

    final scheduleMap = <String, DaySchedule>{};
    for (final day in schedule) {
      scheduleMap[day.name.trim().toLowerCase()] = day;
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stallName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Store Operating Hours',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 22),
                color: const Color(0xFF64748B),
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Next opening / current status highlight banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isCurrentlyOpen
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCurrentlyOpen
                    ? const Color(0xFFA7F3D0)
                    : const Color(0xFFFDE68A),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isCurrentlyOpen
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  size: 22,
                  color: isCurrentlyOpen
                      ? const Color(0xFF059669)
                      : const Color(0xFFD97706),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCurrentlyOpen
                            ? 'Open Now for Direct Orders'
                            : (nextOpening != null
                                ? nextOpening!.fullText
                                : 'Currently Closed for Orders'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isCurrentlyOpen
                              ? const Color(0xFF065F46)
                              : const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isCurrentlyOpen
                            ? 'The stall holder is active and preparing orders.'
                            : 'You can place pre-orders now. Your order will be confirmed and prepared once the stall opens.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isCurrentlyOpen
                              ? const Color(0xFF047857)
                              : const Color(0xFFB45309),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 7-Day Schedule table
          const Text(
            'Weekly Schedule',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                children: [
                  for (int i = 0; i < daysOrder.length; i++) ...[
                    _buildDayRow(
                      dayName: daysOrder[i],
                      daySchedule:
                          scheduleMap[daysOrder[i].trim().toLowerCase()],
                      isToday: daysOrder[i].toLowerCase() ==
                          todayDayName.toLowerCase(),
                    ),
                    if (i < daysOrder.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFE2E8F0),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Close button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Got It',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayRow({
    required String dayName,
    required DaySchedule? daySchedule,
    required bool isToday,
  }) {
    final isOpen = daySchedule?.isOpen ?? false;
    final openTime = daySchedule?.openTime ?? '';
    final closeTime = daySchedule?.closeTime ?? '';

    String hoursText;
    if (!isOpen || openTime.isEmpty || closeTime.isEmpty) {
      hoursText = 'Closed';
    } else {
      hoursText =
          '${formatTime12Hour(openTime)} - ${formatTime12Hour(closeTime)}';
    }

    return Container(
      color: isToday ? const Color(0xFFF0FDF4) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dayName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                  color: isToday
                      ? const Color(0xFF166534)
                      : const Color(0xFF334155),
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF166534),
                    ),
                  ),
                ),
              ],
            ],
          ),
          Text(
            hoursText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isOpen
                  ? (isToday
                      ? const Color(0xFF166534)
                      : const Color(0xFF0F172A))
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
