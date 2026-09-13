import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/notification_service.dart';
import 'services/scheduler.dart';
import 'services/session.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await NotificationService.instance.init();
  runApp(const KhaataBookApp());
}

class KhaataBookApp extends StatelessWidget {
  const KhaataBookApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khaata Book',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _AuthGate(),
    );
  }
}

/// Shows Login until a user is signed in, then the main app.
/// Also runs the date-driven jobs whenever the app comes to the foreground.
class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Session.instance.addListener(_onSession);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Session.instance.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (Session.instance.signedIn) Scheduler.instance.runAll();
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Session.instance.signedIn) {
      Scheduler.instance.runAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Session.instance.signedIn ? const HomeShell() : const LoginScreen();
  }
}
