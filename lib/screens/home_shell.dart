import 'package:flutter/material.dart';

import '../theme.dart';
import 'add_transaction_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

/// Bottom navigation: Home · Reports · (+) · History · Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _add() => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddTransactionScreen()));

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onSeeAll: () => setState(() => _index = 2)),
      const ReportsScreen(),
      const HistoryScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: KColors.navy,
          shape: BoxShape.circle,
          border: Border.all(color: KColors.offWhite, width: 5),
          boxShadow: [BoxShadow(color: KColors.navy.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: IconButton(onPressed: _add, icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: KColors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        padding: EdgeInsets.zero,
        height: 70,
        child: Row(
          children: [
            _item(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
            _item(1, Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Reports'),
            const Expanded(child: SizedBox()),
            _item(2, Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'History'),
            _item(3, Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
          ],
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, IconData active, String label) {
    final sel = _index == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _index = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sel ? active : icon, color: sel ? KColors.navy : KColors.faint, size: 24),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w600, color: sel ? KColors.navy : KColors.faint)),
          ],
        ),
      ),
    );
  }
}
