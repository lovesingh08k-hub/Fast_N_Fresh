import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

/// Shown when the business's POS subscription is suspended or expired (or
/// the user's outlet was turned off) by the POS provider. Nothing else can
/// be used until the provider re-activates it.
class LicenceBlockedScreen extends StatefulWidget {
  const LicenceBlockedScreen({super.key});

  @override
  State<LicenceBlockedScreen> createState() => _LicenceBlockedScreenState();
}

class _LicenceBlockedScreenState extends State<LicenceBlockedScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    setState(() => _checking = true);
    await context.read<AuthProvider>().recheckLicence();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final business = auth.session?.name;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: .14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock_clock_outlined, size: 38, color: AppColors.warning),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Subscription not active',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (business != null && business.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(business, style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    auth.licenceMessage ?? 'Please contact your POS provider.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your data is safe. Everything works again as soon as the subscription is renewed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _retry,
                      icon: _checking
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _checking ? null : () => context.read<AuthProvider>().logout(),
                    child: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
