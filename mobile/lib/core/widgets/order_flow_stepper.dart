import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Service workflow used by the dine-in table screen.
///
/// Simple order/payment workflow. The staff KDS is no longer part of this flow.
class OrderFlowStepper extends StatelessWidget {
  final int currentStep;
  final bool tableServiceFlow;

  const OrderFlowStepper({
    super.key,
    required this.currentStep,
    this.tableServiceFlow = false,
  });

  static const _defaultSteps = <({String label, IconData icon})>[
    (label: 'Table', icon: Icons.table_restaurant_outlined),
    (label: 'Order', icon: Icons.receipt_long_outlined),
    (label: 'Pay', icon: Icons.payments_outlined),
    (label: 'Bill', icon: Icons.check_circle_outline),
  ];

  static const _tableSteps = <({String label, IconData icon})>[
    (label: 'Table', icon: Icons.table_restaurant_outlined),
    (label: 'Order', icon: Icons.receipt_long_outlined),
    (label: 'Bill', icon: Icons.payments_outlined),
    (label: 'Complete', icon: Icons.check_circle_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final steps = tableServiceFlow ? _tableSteps : _defaultSteps;
    final safeStep = currentStep.clamp(0, steps.length - 1);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 13),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: .30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final completed = index ~/ 2 < safeStep;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 24),
                color: completed ? AppColors.primary : AppColors.border,
              ),
            );
          }

          final stepIndex = index ~/ 2;
          final active = stepIndex == safeStep;
          final completed = stepIndex < safeStep;
          final step = steps[stepIndex];

          return Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: tableServiceFlow ? 48 : 30,
                  height: tableServiceFlow ? 48 : 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: completed || active ? AppColors.primary : Colors.white,
                    border: Border.all(
                      color: completed || active ? AppColors.primary : AppColors.border,
                      width: 1.4,
                    ),
                  ),
                  child: Icon(
                    completed ? Icons.check : step.icon,
                    size: tableServiceFlow ? 23 : 16,
                    color: completed || active ? Colors.white : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  step.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: tableServiceFlow ? 11.5 : 9.5,
                    height: 1.15,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active || completed ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
