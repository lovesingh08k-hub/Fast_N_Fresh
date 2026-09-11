import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/user.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/misc_services.dart';

/// Admin-only. Lets the admin see every staff/manager (and admin) account
/// and change roles between Staff and Manager. Never allows creating or
/// changing an Admin account here — that stays with the existing
/// authentication/seed flow, and the backend independently refuses it too.
class UsersScreen extends StatefulWidget {
  UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> with WidgetsBindingObserver {
  final _service = UserService();
  List<AppUser> _users = [];
  bool _loading = true;
  String? _error;

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
      final users = await _service.list();
      setState(() => _users = users);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load users.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeRole(AppUser user) async {
    final newRole = user.role == 'staff' ? 'manager' : 'staff';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change Role'),
        content: Text('Change ${user.name} from ${user.role} to $newRole?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.changeRole(user.id, newRole);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _editAccount(AppUser user) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditAccountSheet(user: user),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleStatus(AppUser user) async {
    final newStatus = user.status == 'active' ? 'inactive' : 'active';
    try {
      await _service.changeStatus(user.id, newStatus);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _addUser() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddUserSheet(),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Staff & Manager Accounts')),
      floatingActionButton: FloatingActionButton(onPressed: _addUser, child: Icon(Icons.person_add_alt)),
      body: _loading
          ? LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _users.isEmpty
                  ? EmptyState(icon: Icons.people_outline, title: 'No users yet')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 90),
                        itemCount: _users.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10),
                        itemBuilder: (context, i) => _UserTile(
                          user: _users[i],
                          onChangeRole: () => _changeRole(_users[i]),
                          onEditAccount: () => _editAccount(_users[i]),
                          onToggleStatus: () => _toggleStatus(_users[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AppUser user;
  final VoidCallback onChangeRole;
  final VoidCallback onEditAccount;
  final VoidCallback onToggleStatus;
  _UserTile({required this.user, required this.onChangeRole, required this.onEditAccount, required this.onToggleStatus});

  Color get _roleColor {
    if (user.isAdmin) return AppColors.primary;
    if (user.isManager) return AppColors.info;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: _roleColor.withValues(alpha: 0.12),
              child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', style: TextStyle(color: _roleColor, fontWeight: FontWeight.w700)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text(user.phone, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _roleColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(user.role.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _roleColor)),
              ),
              SizedBox(height: 4),
              Text(user.status == 'active' ? 'Active' : 'Inactive', style: TextStyle(fontSize: 11, color: user.status == 'active' ? AppColors.success : AppColors.textMuted)),
            ]),
          ]),
          if (!user.isAdmin) ...[
            SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEditAccount,
                  icon: Icon(Icons.edit_outlined, size: 18),
                  label: Text('Edit Login'),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onChangeRole,
                  child: Text('Role → ${user.role == 'staff' ? 'Manager' : 'Staff'}'),
                ),
              ),
            ]),
            SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                onPressed: onToggleStatus,
                style: OutlinedButton.styleFrom(side: BorderSide(color: user.status == 'active' ? AppColors.danger : AppColors.success)),
                child: Text(
                  user.status == 'active' ? 'Deactivate' : 'Activate',
                  style: TextStyle(color: user.status == 'active' ? AppColors.danger : AppColors.success),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _EditAccountSheet extends StatefulWidget {
  final AppUser user;
  _EditAccountSheet({required this.user});

  @override
  State<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends State<_EditAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _phoneController = TextEditingController(text: widget.user.phone);
    _usernameController = TextEditingController(text: widget.user.username);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await UserService().updateAccount(
        widget.user.id,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login details updated. User must log in again.')),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update account.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)))),
                SizedBox(height: 16),
                Text('Edit Staff / Manager Login', style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: 6),
                Text('Change login ID, password or profile details. Existing sessions will be logged out.', style: Theme.of(context).textTheme.bodySmall),
                SizedBox(height: 16),
                TextFormField(controller: _nameController, decoration: InputDecoration(labelText: 'Name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                SizedBox(height: 12),
                TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                SizedBox(height: 12),
                TextFormField(controller: _usernameController, decoration: InputDecoration(labelText: 'Login ID / Username'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                SizedBox(height: 12),
                TextFormField(controller: _passwordController, obscureText: true, decoration: InputDecoration(labelText: 'New Password', hintText: 'Leave blank to keep current password'), validator: (v) => (v != null && v.isNotEmpty && v.length < 6) ? 'Minimum 6 characters' : null),
                if (_error != null) ...[
                  SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Save Changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddUserSheet extends StatefulWidget {
  _AddUserSheet();

  @override
  State<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends State<_AddUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'staff';
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UserService().create(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        role: _role,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)))),
              SizedBox(height: 16),
              Text('Add Staff or Manager', style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: 16),
              TextFormField(controller: _nameController, decoration: InputDecoration(labelText: 'Name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              SizedBox(height: 12),
              TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              SizedBox(height: 12),
              TextFormField(controller: _usernameController, decoration: InputDecoration(labelText: 'Username'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              SizedBox(height: 12),
              TextFormField(controller: _passwordController, obscureText: true, decoration: InputDecoration(labelText: 'Password'), validator: (v) => (v == null || v.length < 6) ? 'Minimum 6 characters' : null),
              SizedBox(height: 12),
              Row(children: [
                Expanded(child: ChoiceChip(label: Text('Staff'), selected: _role == 'staff', onSelected: (_) => setState(() => _role = 'staff'))),
                SizedBox(width: 10),
                Expanded(child: ChoiceChip(label: Text('Manager'), selected: _role == 'manager', onSelected: (_) => setState(() => _role = 'manager'))),
              ]),
              if (_error != null) ...[
                SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
              SizedBox(height: 18),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
