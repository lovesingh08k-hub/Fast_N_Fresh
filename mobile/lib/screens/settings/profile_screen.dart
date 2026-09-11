import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import 'change_password_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : '?', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 24)),
                ),
                SizedBox(height: 12),
                Text(user?.name ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                SizedBox(height: 2),
                Text('Staff', style: TextStyle(color: AppColors.textMuted)),
              ],
            ),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(4),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Column(
              children: [
                ListTile(leading: Icon(Icons.phone_outlined), title: Text('Phone'), subtitle: Text(user?.phone ?? '')),
                Divider(height: 1),
                ListTile(leading: Icon(Icons.person_outline), title: Text('Username'), subtitle: Text(user?.username ?? '')),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Change Password'),
                  trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChangePasswordScreen())),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => context.read<AuthProvider>().logout(),
            icon: Icon(Icons.logout, color: AppColors.danger, size: 18),
            label: Text('Logout', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
