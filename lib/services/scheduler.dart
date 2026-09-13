import 'backup_service.dart';
import 'card_service.dart';
import 'loan_service.dart';
import 'notification_service.dart';
import 'recurring_service.dart';

/// Runs the "things that happen on a date" every time the app opens or
/// comes back to the foreground: card cycles, loan EMIs, recurring
/// postings, automatic backup, and reminder scheduling.
class Scheduler {
  Scheduler._();
  static final Scheduler instance = Scheduler._();
  bool _running = false;

  Future<void> runAll() async {
    if (_running) return;
    _running = true;
    try {
      await LoanService.instance.postDue();
      await RecurringService.instance.postDue();
      await CardService.instance.generateCycles();
      await BackupService.instance.runAutoIfDue();
      await NotificationService.instance.reschedule();
    } catch (_) {
      // Never block the UI because of a background step.
    } finally {
      _running = false;
    }
  }
}
