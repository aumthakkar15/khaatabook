import 'package:flutter/foundation.dart';
import '../models/models.dart';

/// Current signed-in user + a change bus that screens listen to so lists
/// refresh after any write. Everything is on-device; this is not a server session.
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  User? _user;
  User? get user => _user;
  bool get signedIn => _user != null;
  String get base => _user?.baseCurrency ?? 'USD';

  void signIn(User u) {
    _user = u;
    notifyListeners();
  }

  void update(User u) {
    _user = u;
    notifyListeners();
  }

  void signOut() {
    _user = null;
    notifyListeners();
  }
}

/// Fired after any data write; screens call [DataBus.instance.addListener].
class DataBus extends ChangeNotifier {
  DataBus._();
  static final DataBus instance = DataBus._();
  void changed() => notifyListeners();
}
