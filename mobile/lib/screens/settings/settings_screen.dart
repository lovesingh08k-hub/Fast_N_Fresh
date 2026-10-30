import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';


import 'package:provider/provider.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

import '../../core/network/api_exception.dart';

import '../../core/widgets/state_widgets.dart';


import '../../providers/connectivity_provider.dart';

import '../../services/misc_services.dart';

import '../../services/auth_service.dart';


import '../../services/apk_share_service.dart';

import '../../providers/theme_provider.dart';

import 'printer_settings_screen.dart';

import '../../core/widgets/theme_reveal.dart';

class SettingsScreen extends StatefulWidget {

  const SettingsScreen({super.key});

  @override

  State<SettingsScreen> createState() => _SettingsScreenState();

}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {

  final _service = SettingsService();


  bool _loading = true;

  String? _error;

  final _cafeNameController = TextEditingController();

  final _phoneController = TextEditingController();

  final _addressController = TextEditingController();

  final _gstController = TextEditingController();

  final _upiController = TextEditingController();

  final _footerController = TextEditingController();

  final _taxPercentController = TextEditingController();

  final _defaultDiscountController = TextEditingController();

  bool _taxEnabled = false;

  // Billing & GST (see backend services/billing.js).
  final _fssaiController = TextEditingController();
  final _invoicePrefixController = TextEditingController();
  final _serviceChargeController = TextEditingController();
  final _packagingChargeController = TextEditingController();
  final _deliveryChargeController = TextEditingController();
  final _platformsController = TextEditingController();
  bool _taxInclusive = false;
  String _gstType = 'cgst_sgst';
  bool _roundOff = true;
  Set<String> _serviceChargeOn = {'dine_in'};
  Set<String> _packagingChargeOn = {'takeaway', 'delivery'};

  static const _orderTypeLabels = {'dine_in': 'Dine-in', 'takeaway': 'Takeaway', 'delivery': 'Delivery'};

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

    for (final c in [_cafeNameController, _phoneController, _addressController, _gstController, _upiController, _footerController, _taxPercentController, _defaultDiscountController, _fssaiController, _invoicePrefixController, _serviceChargeController, _packagingChargeController, _deliveryChargeController, _platformsController]) {
      c.dispose();
    }

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

      if (!mounted) return;

      setState(() {


        _cafeNameController.text = settings.cafeName;

        _phoneController.text = settings.phone;

        _addressController.text = settings.address;

        _gstController.text = settings.gstNumber;

        _upiController.text = settings.upiId;

        _footerController.text = settings.receiptFooter;

        _taxPercentController.text = settings.taxPercent.toString();

        _defaultDiscountController.text = settings.defaultDiscount.toString();

        _taxEnabled = settings.taxEnabled;

        _taxInclusive = settings.taxInclusive;
        _gstType = settings.gstType;
        _roundOff = settings.roundOff;
        _fssaiController.text = settings.fssai;
        _invoicePrefixController.text = settings.invoicePrefix;
        _serviceChargeController.text = _number(settings.serviceChargePercent);
        _packagingChargeController.text = _number(settings.packagingCharge);
        _deliveryChargeController.text = _number(settings.deliveryCharge);
        _platformsController.text = settings.onlinePlatforms.join(', ');
        _serviceChargeOn = settings.serviceChargeOn.toSet();
        _packagingChargeOn = settings.packagingChargeOn.toSet();

      });

    } on ApiException catch (e) {

      if (mounted) setState(() => _error = e.message);

    } catch (_) {

      if (mounted) setState(() => _error = 'Could not load settings.');

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
        'taxInclusive': _taxInclusive,
        'gstType': _gstType,
        'roundOff': _roundOff,
        'fssai': _fssaiController.text.trim(),
        'invoicePrefix': _invoicePrefixController.text.trim(),
        'serviceChargePercent': double.tryParse(_serviceChargeController.text) ?? 0,
        'serviceChargeOn': _serviceChargeOn.toList(),
        'packagingCharge': double.tryParse(_packagingChargeController.text) ?? 0,
        'packagingChargeOn': _packagingChargeOn.toList(),
        'deliveryCharge': double.tryParse(_deliveryChargeController.text) ?? 0,
        'onlinePlatforms': _platformsController.text
            .split(',')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList(),

      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));

    } on ApiException catch (e) {

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));

    }

  }

  Future<void> _shareApk() async {

    try {

      await ApkShareService.instance.shareCurrentApk();

    } catch (e) {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          const SnackBar(content: Text('Could not share the APK.')),

        );

      }

    }

  }

  Future<void> _logoutAllDevices() async {

    final confirmed = await showDialog<bool>(

      context: context,

      builder: (context) => AlertDialog(

        title: const Text('Logout all devices?'),

        content: const Text('This will end all active sessions for your account, including this one.'),

        actions: [

          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),

          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout All')),

        ],

      ),

    );

    if (confirmed == true) {

      await AuthService().logoutAllDevices();

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged out from all devices. You may need to log in again.')));

    }

  }

  @override

  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(title: const Text('Settings')),

      body: _loading

          ? const LoadingState()

          : _error != null

              ? ErrorState(message: _error!, onRetry: _load)

              : ListView(

                  padding: const EdgeInsets.all(16),

                  children: [

                    _sectionTitle('Business Profile'),

                    _field(_cafeNameController, 'Cafe Name'),

                    _field(_phoneController, 'Phone'),

                    _field(_addressController, 'Address'),

                    _field(_gstController, 'GSTIN (printed on the bill, optional)'),

                    _field(_fssaiController, 'FSSAI licence no. (optional)'),

                    _field(_upiController, 'UPI ID'),

                    const SizedBox(height: 20),

                    _sectionTitle('Billing'),

                    _field(_footerController, 'Receipt Footer', maxLines: 2),

                    SwitchListTile(

                      contentPadding: EdgeInsets.zero,

                      title: const Text('Enable Tax'),

                      value: _taxEnabled,

                      onChanged: (v) => setState(() => _taxEnabled = v),

                    ),

                    if (_taxEnabled) ...[
                      _field(_taxPercentController, 'Default GST rate (%) — items can have their own', keyboardType: TextInputType.number),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Menu prices include GST'),
                        subtitle: const Text('Off: GST is added on top of the menu price'),
                        value: _taxInclusive,
                        onChanged: (v) => setState(() => _taxInclusive = v),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 'cgst_sgst', label: Text('CGST + SGST')),
                            ButtonSegment(value: 'igst', label: Text('IGST')),
                          ],
                          selected: {_gstType},
                          onSelectionChanged: (v) => setState(() => _gstType = v.first),
                        ),
                      ),
                    ],
                    _field(_invoicePrefixController, 'Invoice number prefix (e.g. INV, FNF)'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Round off bill to nearest ₹1'),
                      value: _roundOff,
                      onChanged: (v) => setState(() => _roundOff = v),
                    ),
                    _field(_serviceChargeController, 'Service charge (%)', keyboardType: TextInputType.number),
                    _orderTypeChips(_serviceChargeOn, (next) => setState(() => _serviceChargeOn = next)),
                    _field(_packagingChargeController, 'Packaging charge per bill (₹)', keyboardType: TextInputType.number),
                    _orderTypeChips(_packagingChargeOn, (next) => setState(() => _packagingChargeOn = next)),
                    _field(_deliveryChargeController, 'Delivery charge per delivery bill (₹)', keyboardType: TextInputType.number),
                    _field(_platformsController, 'Delivery apps for "Online" bills (comma separated)'),

                    _field(_defaultDiscountController, 'Default Discount (₹)', keyboardType: TextInputType.number),

                    const SizedBox(height: 20),

                    ElevatedButton(onPressed: _save, child: const Text('Save Settings')),

                    const SizedBox(height: 28),

                    _sectionTitle('Printer'),

                    Container(

                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),

                      child: ListTile(

                        leading: const Icon(Icons.print_outlined),

                        title: const Text('Bluetooth Receipt Printer'),

                        subtitle: const Text('58mm / 80mm thermal printer for the billing counter'),

                        trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),

                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),

                      ),

                    ),

                    const SizedBox(height: 28),

                    _sectionTitle('Security'),

                    Container(

                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),

                      child: ListTile(

                        leading: const Icon(Icons.devices_outlined),

                        title: const Text('Logout All Devices'),

                        trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),

                        onTap: _logoutAllDevices,

                      ),

                    ),

                    const SizedBox(height: 28),

                    _sectionTitle('Appearance'),

                    Container(

                      decoration: BoxDecoration(

                        color: AppColors.surface,

                        borderRadius: BorderRadius.circular(14),

                        border: Border.all(color: AppColors.border),

                      ),

                      child: Consumer<ThemeProvider>(

                        builder: (context, theme, _) => ListTile(

                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),

                          leading: Icon(

                            theme.mode == AppThemeMode.dark ? Icons.dark_mode_outlined : Icons.brightness_6_outlined,

                            color: AppColors.primary,

                          ),

                          title: const Text('Appearance'),

                          subtitle: Text(theme.mode == AppThemeMode.dark ? 'Dark theme' : 'Light theme'),

                          trailing: DropdownButtonHideUnderline(

                            child: DropdownButton<AppThemeMode>(

                              value: theme.mode,

                              items: const [

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

                    // Sharing the APK only makes sense on Android.
                    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[

                      const SizedBox(height: 12),

                      _ShareApkTile(onShareApk: _shareApk),

                    ],

                    const SizedBox(height: 28),

                    _sectionTitle('About us'),

                    const _AboutUsCard(),

                  ],

                ),

    );

  }

  Widget _sectionTitle(String title) {

    return Padding(

      padding: const EdgeInsets.only(bottom: 10),

      child: Text(title, style: Theme.of(context).textTheme.titleMedium),

    );

  }

  static String _number(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  /// "Applies to" chips: Dine-in / Takeaway / Delivery.
  Widget _orderTypeChips(Set<String> selected, ValueChanged<Set<String>> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        spacing: 8,
        children: [
          for (final entry in _orderTypeLabels.entries)
            FilterChip(
              label: Text(entry.value),
              selected: selected.contains(entry.key),
              onSelected: (on) => onChanged(on ? {...selected, entry.key} : ({...selected}..remove(entry.key))),
            ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, {int maxLines = 1, TextInputType? keyboardType}) {

    return Padding(

      padding: const EdgeInsets.only(bottom: 12),

      child: TextField(controller: controller, maxLines: maxLines, keyboardType: keyboardType, decoration: InputDecoration(labelText: label)),

    );

  }

}

class _ShareApkTile extends StatelessWidget {

  final VoidCallback onShareApk;

  const _ShareApkTile({

    required this.onShareApk,

  });

  @override

  Widget build(BuildContext context) {

    return Container(

      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),

      child: ListTile(

        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),

        leading: Icon(Icons.share_rounded, color: AppColors.primary),

        title: const Text('Share APK'),

        subtitle: const Text('Send this installed app to another phone'),

        trailing: const Icon(Icons.chevron_right),

        onTap: onShareApk,

      ),

    );

  }

}

/// Credits shown at the bottom of Settings.
class _AboutUsCard extends StatelessWidget {

  const _AboutUsCard();

  static final Uri _portfolio = Uri.parse('https://pwp-portfolio-mu.vercel.app/');

  Future<void> _openPortfolio(BuildContext context) async {

    final messenger = ScaffoldMessenger.of(context);

    var opened = false;

    try {

      opened = await launchUrl(_portfolio, mode: LaunchMode.externalApplication);

    } catch (_) {}

    if (!opened) {

      messenger.showSnackBar(const SnackBar(content: Text('Could not open the link.')));

    }

  }

  @override

  Widget build(BuildContext context) {

    return Container(

      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),

      child: Column(

        children: [

          ListTile(

            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),

            leading: Icon(Icons.code_rounded, color: AppColors.primary),

            title: const Text('Developed by Love'),

          ),

          const Divider(height: 1),

          ListTile(

            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),

            leading: Icon(Icons.bolt_rounded, color: AppColors.primary),

            title: const Text('Powered by PWP'),

            subtitle: const Text('Personalize Web Page'),

          ),

          const Divider(height: 1),

          ListTile(

            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),

            leading: Icon(Icons.language_rounded, color: AppColors.primary),

            title: const Text('Visit our portfolio'),

            subtitle: const Text('pwp-portfolio-mu.vercel.app'),

            trailing: const Icon(Icons.open_in_new_rounded, size: 20),

            onTap: () => _openPortfolio(context),

          ),

        ],

      ),

    );

  }

}
