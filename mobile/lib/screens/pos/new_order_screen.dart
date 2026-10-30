import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../providers/auth_provider.dart';
import '../tables/tables_screen.dart';
import 'counter_slots_screen.dart';

/// Entry point for starting any new order.
///
/// Dine-In -> Table selection
/// Takeaway -> Counters (T1, T2...) -> menu
/// Delivery -> Counters (D1, D2...) -> menu
class NewOrderScreen extends StatelessWidget {
  const NewOrderScreen({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final outlet = context.watch<AuthProvider>().currentOutlet?.name;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            FreshHeader(
              title: 'New Order',
              subtitle: outlet ?? 'How is this customer being served?',
              showBack: Navigator.of(context).canPop(),
            ),
            const SizedBox(height: 18),

            // Dine-in: the main, highlighted choice.
            _HeroChoice(
              title: 'Dine-In',
              subtitle: 'Customer is seated at a table.\nPick a table, send KOT, bill later.',
              emoji: '🍽️',
              onTap: () => _open(context, const TablesScreen()),
            ),
            const SizedBox(height: 14),
            // Side by side on phones, stacked when the screen is very narrow.
            LayoutBuilder(
              builder: (context, constraints) {
                final takeaway = _ChoiceTile(
                      title: 'Takeaway',
                      subtitle: 'Parcel at the counter',
                      emoji: '🛍️',
                      color: const Color(0xFF3B82F6),
                      onTap: () => _open(context, const CounterSlotsScreen(orderType: 'takeaway')),
                    );
                final delivery = _ChoiceTile(
                      title: 'Delivery',
                      subtitle: 'Home delivery / Swiggy, Zomato',
                      emoji: '🛵',
                      color: const Color(0xFF8B5CF6),
                      onTap: () => _open(context, const CounterSlotsScreen(orderType: 'delivery')),
                    );
                if (constraints.maxWidth < 380) {
                  return Column(children: [takeaway, const SizedBox(height: 14), delivery]);
                }
                return Row(
                  children: [
                    Expanded(child: takeaway),
                    const SizedBox(width: 14),
                    Expanded(child: delivery),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: FreshUi.card(),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.tips_and_updates_outlined, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tip: keep several customers running on T1, T2… and bill each one when they leave.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChoice extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final VoidCallback onTap;

  const _HeroChoice({required this.title, required this.subtitle, required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF8257), Color(0xFFF2643D), Color(0xFFE2522E)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: const Color(0xFFF2643D).withValues(alpha: .28), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(subtitle, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35)),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: Text('Choose table', overflow: TextOverflow.ellipsis, style: TextStyle(color: Color(0xFFE2522E), fontWeight: FontWeight.w800, fontSize: 13))),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFFE2522E)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), shape: BoxShape.circle),
                child: Text(emoji, style: const TextStyle(fontSize: 36)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final Color color;
  final VoidCallback onTap;

  const _ChoiceTile({required this.title, required this.subtitle, required this.emoji, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: FreshUi.card(radius: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(18)),
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(height: 14),
              Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 3),
              // Two lines always, so tiles side by side have the same height.
              SizedBox(
                height: 34,
                child: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Start', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
