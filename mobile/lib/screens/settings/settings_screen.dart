import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/misc_models.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/misc_services.dart';
import '../../services/auth_service.dart';
import '../../services/app_update_service.dart';
import '../../providers/theme_provider.dart';
import 'printer_settings_screen.dart';

import '../../core/widgets/theme_reveal.dart';
class SettingsScreen extends StatefulWidget {
  SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final _service = SettingsService();
  BusinessSettings? _settings;
  bool _loading = true;
  String? _error;

  late TextEditingController _cafeNameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _gstController;
  late TextEditingController _upiController;
  late TextEditingController _footerController;
  late TextEditingController _taxPercentController;
  late TextEditingController _defaultDiscountController;
  bool _taxEnabled = false;
  bool _checkingUpdate = false;

  AppLifecycleState? _lastLifecycleState;
  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final connectivity = context.read<ConnectivityProvider>();
    if (!identical(connectivity, _connectivity)) {
      _connectivity?.removeListener(_handleConnectivityChange);
      _connectivity = connectivity;
      _wasOnline = connectivity.isOnline;
      _connectivity!.addListener(_handleConnectivityChange);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.removeListener(_handleConnectivityChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded = _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground = state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground && mounted && _error != null) {
      _load();
    }
  }

  void _handleConnectivityChange() {
    final isOnline = _connectivity?.isOnline ?? true;

    if (isOnline && !_wasOnline && _error != null) {
      _load();
    }

    _wasOnline = isOnline;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _service.get();
      setState(() {
        _settings = settings;
        _cafeNameController = TextEditingController(text: settings.cafeName);
        _phoneController = TextEditingController(text: settings.phone);
        _addressController = TextEditingController(text: settings.address);
        _gstController = TextEditingController(text: settings.gstNumber);
        _upiController = TextEditingController(text: settings.upiId);
        _footerController = TextEditingController(text: settings.receiptFooter);
        _taxPercentController = TextEditingController(text: settings.taxPercent.toString());
        _defaultDiscountController = TextEditingController(text: settings.defaultDiscount.toString());
        _taxEnabled = settings.taxEnabled;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load settings.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await _service.update({
        'cafeName': _cafeNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'gstNumber': _gstController.text.trim(),
        'upiId': _upiController.text.trim(),
        'receiptFooter': _footerController.text.trim(),
        'taxEnabled': _taxEnabled,
        'taxPercent': double.tryParse(_taxPercentController.text) ?? 0,
        'defaultDiscount': double.tryParse(_defaultDiscountController.text) ?? 0,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Settings saved.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);

    try {
      final result = await AppUpdateService.instance.checkForUpdate();
      if (!mounted) return;

      if (!result.hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are already using the latest version.')),
        );
        return;
      }

      final update = result.update!;
      final install = await showDialog<bool>(
        context: context,
        barrierDismissible: !update.forceUpdate,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.system_update_alt_rounded),
              SizedBox(width: 10),
              Expanded(child: Text('New update available')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Version ${update.version} (${update.buildNumber})', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (update.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(update.notes.trim()),
                ],
                const SizedBox(height: 16),
                const Text(
                  'The app will open the secure download page. Android may ask you to confirm the installation.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            if (!update.forceUpdate)
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Later')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Update Now'),
            ),
          ],
        ),
      );

      if (install == true) {
        final opened = await AppUpdateService.instance.openDownload(update.downloadUrl);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the update download link.')),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not check for updates right now.')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _logoutAllDevices() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logout all devices?'),
        content: Text('This will end all active sessions for your account, including this one.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Logout All')),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService().logoutAllDevices();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logged out from all devices. You may need to log in again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: _loading
          ? LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: EdgeInsets.all(16),
                  children: [
                    _sectionTitle('Business Profile'),
                    _field(_cafeNameController, 'Cafe Name'),
                    _field(_phoneController, 'Phone'),
                    _field(_addressController, 'Address'),
                    _field(_gstController, 'GST Number (optional)'),
                    _field(_upiController, 'UPI ID'),
                    SizedBox(height: 20),
                    _sectionTitle('Billing'),
                    _field(_footerController, 'Receipt Footer', maxLines: 2),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Enable Tax'),
                      value: _taxEnabled,
                      onChanged: (v) => setState(() => _taxEnabled = v),
                    ),
                    if (_taxEnabled) _field(_taxPercentController, 'Tax Percent (%)', keyboardType: TextInputType.number),
                    _field(_defaultDiscountController, 'Default Discount (₹)', keyboardType: TextInputType.number),
                    SizedBox(height: 20),
                    ElevatedButton(onPressed: _save, child: Text('Save Settings')),
                    SizedBox(height: 28),
                    _sectionTitle('Printer'),
                    Container(
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                      child: ListTile(
                        leading: Icon(Icons.print_outlined),
                        title: Text('Bluetooth Receipt Printer'),
                        subtitle: Text('58mm / 80mm thermal printer for the billing counter'),
                        trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PrinterSettingsScreen())),
                      ),
                    ),
                    SizedBox(height: 28),
                    _sectionTitle('Security'),
                    Container(
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                      child: ListTile(
                        leading: Icon(Icons.devices_outlined),
                        title: Text('Logout All Devices'),
                        trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
                        onTap: _logoutAllDevices,
                      ),
                    ),
                    SizedBox(height: 28),
                    _sectionTitle('Appearance'),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Consumer<ThemeProvider>(
                        builder: (context, theme, _) => ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                          leading: Icon(
                            theme.mode == AppThemeMode.dark ? Icons.dark_mode_outlined : Icons.brightness_6_outlined,
                            color: AppColors.primary,
                          ),
                          title: Text('Appearance'),
                          subtitle: Text(theme.mode == AppThemeMode.system ? 'Follow device setting' : theme.mode == AppThemeMode.dark ? 'Dark theme' : 'Light theme'),
                          trailing: DropdownButtonHideUnderline(
                            child: DropdownButton<AppThemeMode>(
                              value: theme.mode,
                              items: const [
                                DropdownMenuItem(value: AppThemeMode.system, child: Text('System')),
                                DropdownMenuItem(value: AppThemeMode.light, child: Text('Light')),
                                DropdownMenuItem(value: AppThemeMode.dark, child: Text('Dark')),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  changeThemeWithReveal(context, v, originContext: context);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 28),
                    _sectionTitle('App'),
                    _AppInfoTile(
                      checkingUpdate: _checkingUpdate,
                      onCheckForUpdate: _checkForUpdate,
                    ),
                  ],
                ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _field(TextEditingController controller, String label, {int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: TextField(controller: controller, maxLines: maxLines, keyboardType: keyboardType, decoration: InputDecoration(labelText: label)),
    );
  }
}

class _AppInfoTile extends StatelessWidget {
  final bool checkingUpdate;
  final VoidCallback onCheckForUpdate;

  const _AppInfoTile({
    required this.checkingUpdate,
    required this.onCheckForUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data != null ? '${snapshot.data!.version} (${snapshot.data!.buildNumber})' : '—';
        return Container(
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Column(
            children: [
              ListTile(leading: Icon(Icons.local_cafe_outlined), title: Text('FAST N FRESH CAFE'), subtitle: Text('Cafe Management & POS')),
              Divider(height: 1),
              ListTile(leading: Icon(Icons.info_outline), title: Text('Version'), subtitle: Text(version)),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.system_update_alt_rounded, color: AppColors.primary),
                title: Text('App Updates'),
                subtitle: Text(checkingUpdate ? 'Checking for the latest version…' : 'Check and download the latest APK'),
                trailing: checkingUpdate
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: checkingUpdate ? null : onCheckForUpdate,
              ),
            ],
          ),
        );
      },
    );
  }
}
