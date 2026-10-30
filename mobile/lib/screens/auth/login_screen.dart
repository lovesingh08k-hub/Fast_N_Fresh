import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessController = TextEditingController();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  static const _lastBusinessKey = 'last_business_code';

  @override
  void initState() {
    super.initState();
    _restoreBusinessCode();
  }

  /// Staff of one cafe always type the same business code; remember it.
  Future<void> _restoreBusinessCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_lastBusinessKey);
      if (saved != null && mounted && _businessController.text.isEmpty) {
        _businessController.text = saved;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _businessController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    final auth = context.read<AuthProvider>();

    final businessCode = _businessController.text.trim().toLowerCase();
    final ok = await auth.login(
      businessCode,
      _identifierController.text.trim(),
      _passwordController.text,
    );
    if (!ok) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastBusinessKey, businessCode);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final height = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Brand band behind the top of the form.
          Container(
            height: (height * .42).clamp(260, 420).toDouble(),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF8257), Color(0xFFF2643D), Color(0xFFD9482A)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
                          ),
                          child: Image.asset('assets/images/app_icon.png'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'PWP POS',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.3),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Billing • Orders • Tables • Reports',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 30, offset: const Offset(0, 12))],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Welcome back 👋', style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 4),
                              Text('Log in to start billing', style: Theme.of(context).textTheme.bodyMedium),
                              const SizedBox(height: 22),
                              // Business code: which cafe/restaurant this login belongs to.
                              TextFormField(
                                controller: _businessController,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Business code',
                                  hintText: 'Given by your POS provider',
                                  prefixIcon: Icon(Icons.storefront_outlined),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Username / Phone
                              TextFormField(
                                controller: _identifierController,
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Username or phone',
                                  prefixIcon: Icon(
                                    Icons.person_outline,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Enter your username or phone';
                                  }

                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              // Password
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Enter your password';
                                  }

                                  return null;
                                },
                              ),

                              // Error Message
                              if (auth.errorMessage != null) ...[
                                const SizedBox(height: 14),

                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: AppColors.danger,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          auth.errorMessage!,
                                          style: TextStyle(
                                            color: AppColors.danger,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 22),

                              // Login Button
                              ElevatedButton(
                                onPressed: auth.isLoading ? null : _submit,
                                child: auth.isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Log In',
                                      ),
                              ),

                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Made in India 🇮🇳  •  Powered by PWP',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
