import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'register_screen.dart';

/// Feature 1 & 2: Login ID + password, show/hide password, fingerprint.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _show = false;
  bool _busy = false;
  bool _bioEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final last = await AuthService.instance.lastLoginId();
    final bioUser = await AuthService.instance.biometricUser();
    final available = await AuthService.instance.biometricAvailable();
    if (!mounted) return;
    setState(() {
      if (last != null) _id.text = last;
      _bioEnabled = bioUser != null && available;
    });
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.login(_id.text, _pw.text);
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bio() async {
    try {
      await AuthService.instance.loginWithBiometric();
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KColors.white,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 272,
              decoration: const BoxDecoration(
                color: KColors.navy,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: -60,
                    bottom: -80,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: KColors.navyMid, width: 34)),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: KColors.white,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 12))],
                          ),
                          child: const Icon(Icons.menu_book_rounded, size: 44, color: KColors.navy),
                        ),
                        const SizedBox(height: 18),
                        const Text('Khaata Book', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: KColors.white, letterSpacing: -0.5)),
                        const SizedBox(height: 4),
                        const Text('Your daily expenses, in one place', style: TextStyle(fontSize: 13, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Welcome back', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(height: 4),
                  const Text('Sign in to continue', style: TextStyle(fontSize: 14, color: KColors.muted, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 16),
                  KTextField(controller: _id, label: 'Login ID', hint: 'Email or username', icon: Icons.person_outline, capitalization: TextCapitalization.none),
                  const SizedBox(height: 14),
                  KTextField(
                    controller: _pw,
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: Icons.lock_outline,
                    obscure: !_show,
                    capitalization: TextCapitalization.none,
                    suffix: IconButton(
                      icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: KColors.faint),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Text('Sign in'),
                  ),
                  if (_bioEnabled) ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      const Expanded(child: Divider()),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KColors.faint))),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _bio,
                      icon: const Icon(Icons.fingerprint_rounded, size: 24),
                      label: const Text('Sign in with fingerprint'),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Center(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        const Text('New user?', style: TextStyle(fontSize: 14, color: KColors.muted, fontWeight: FontWeight.w500)),
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                          child: const Text('Create an account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KColors.navy)),
                        ),
                      ],
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
