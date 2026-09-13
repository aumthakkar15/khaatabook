import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';
import '../models/models.dart';
import '../utils/money.dart';
import 'account_service.dart';
import 'card_service.dart';
import 'loan_service.dart';
import 'recurring_service.dart';

/// On-device reminders (no server): credit-card due dates, loan EMIs and
/// recurring postings. Rescheduled every time the app opens.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'khaata_reminders',
    'Reminders',
    channelDescription: 'Card due dates, loan EMIs and recurring transactions',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
    _ready = true;
  }

  Future<void> showNow(int id, String title, String body) async {
    if (!_ready) await init();
    await _plugin.show(id, title, body, const NotificationDetails(android: _channel));
  }

  Future<int> _daysBefore() async =>
      int.tryParse(await AppDb.instance.getSetting('remind_days_before') ?? '3') ?? 3;

  /// Cancels everything and schedules the next 30 days of reminders.
  Future<void> reschedule() async {
    if (!_ready) await init();
    await _plugin.cancelAll();
    var id = 1000;
    final accounts = await AccountService.instance.map();
    final daysBefore = await _daysBefore();
    final today = Dates.today();
    final horizon = today.add(const Duration(days: 30));

    // Credit-card payment due dates.
    for (final cy in await CardService.instance.allDue()) {
      final card = accounts[cy.accountId];
      if (card == null) continue;
      final amt = Money.format(cy.remaining, code: card.currency);
      for (final when in [cy.dueDate.subtract(Duration(days: daysBefore)), cy.dueDate]) {
        if (when.isBefore(today) || when.isAfter(horizon)) continue;
        final isDay = when == cy.dueDate;
        await _schedule(id++, when,
            isDay ? 'Card payment due today' : 'Card payment due in $daysBefore days',
            '${card.name}: $amt due ${Dates.dMy.format(cy.dueDate)}');
      }
    }
    // Loan EMIs.
    for (final (loan, emi) in await LoanService.instance.upcoming(days: 30)) {
      final acc = accounts[loan.accountId];
      final amt = Money.format(emi.amount, code: acc?.currency);
      if (emi.dueDate.isBefore(today)) continue;
      await _schedule(id++, emi.dueDate, 'Loan EMI today', '${loan.name}: EMI ${emi.no} of ${loan.months} · $amt from ${acc?.name ?? 'account'}');
    }
    // Recurring postings.
    for (final r in await RecurringService.instance.all(status: 'active')) {
      if (r.nextDate.isBefore(today) || r.nextDate.isAfter(horizon)) continue;
      final acc = accounts[r.accountId];
      await _schedule(id++, r.nextDate, 'Recurring ${r.type.name} posted',
          '${r.name}: ${Money.format(r.amount, code: r.currency)} · ${acc?.name ?? ''}');
    }
  }

  Future<void> _schedule(int id, DateTime day, String title, String body) async {
    var at = tz.TZDateTime(tz.local, day.year, day.month, day.day, 9);
    final now = tz.TZDateTime.now(tz.local);
    if (at.isBefore(now)) {
      if (day.isBefore(Dates.today())) return;
      at = now.add(const Duration(minutes: 1));
    }
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        at,
        const NotificationDetails(android: _channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // Scheduling can be refused on some devices; the in-app reminders still show.
    }
  }
}
