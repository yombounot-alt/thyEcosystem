import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../data/dashboard_models.dart';

const _weekdayInitials = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Minimal bar chart of daily revenue; the last bar (today) is highlighted. Long-press a bar for its value.
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({super.key, required this.points, required this.currency});

  final List<SalesChartPoint> points;
  final String currency;

  static const _barAreaHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final maxRevenue = points.fold(0.0, (max, p) => math.max(max, p.revenue));

    return SizedBox(
      height: _barAreaHeight + 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < points.length; i++)
            Expanded(
              child: Tooltip(
                message:
                    '${formatDay(points[i].date)} : ${formatMoney(points[i].revenue, currency: currency)}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height:
                          maxRevenue <= 0
                              ? 3
                              : math.max(3, _barAreaHeight * points[i].revenue / maxRevenue),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color:
                            i == points.length - 1
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.35),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _weekdayInitials[points[i].date.weekday - 1],
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
