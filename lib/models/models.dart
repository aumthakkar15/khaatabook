/// Data models for Khaata Book. All amounts are doubles rounded to 2 dp
/// at storage; rates keep 6 dp.

class User {
  final int? id;
  final String name;
  final String loginId;
  final String passwordHash;
  final String salt;
  final String country;
  final String baseCurrency;
  final bool biometric;
  const User({
    this.id,
    required this.name,
    required this.loginId,
    required this.passwordHash,
    required this.salt,
    required this.country,
    required this.baseCurrency,
    this.biometric = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'login_id': loginId,
        'password_hash': passwordHash,
        'salt': salt,
        'country': country,
        'base_currency': baseCurrency,
        'biometric': biometric ? 1 : 0,
      };

  static User fromMap(Map<String, Object?> m) => User(
        id: m['id'] as int?,
        name: m['name'] as String,
        loginId: m['login_id'] as String,
        passwordHash: m['password_hash'] as String,
        salt: m['salt'] as String,
        country: m['country'] as String,
        baseCurrency: m['base_currency'] as String,
        biometric: (m['biometric'] as int? ?? 0) == 1,
      );
}

class Currency {
  final String code;
  final String name;
  final String symbol;
  final String country;

  /// 1 unit of BASE currency = [rate] units of this currency.
  final double rate;
  final bool manual;
  final bool inUse;
  final String? updatedAt;
  const Currency({
    required this.code,
    required this.name,
    required this.symbol,
    required this.country,
    required this.rate,
    this.manual = false,
    this.inUse = false,
    this.updatedAt,
  });

  Currency copyWith({double? rate, bool? manual, bool? inUse, String? updatedAt}) => Currency(
        code: code,
        name: name,
        symbol: symbol,
        country: country,
        rate: rate ?? this.rate,
        manual: manual ?? this.manual,
        inUse: inUse ?? this.inUse,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'code': code,
        'name': name,
        'symbol': symbol,
        'country': country,
        'rate': rate,
        'manual': manual ? 1 : 0,
        'in_use': inUse ? 1 : 0,
        'updated_at': updatedAt,
      };

  static Currency fromMap(Map<String, Object?> m) => Currency(
        code: m['code'] as String,
        name: m['name'] as String,
        symbol: m['symbol'] as String,
        country: m['country'] as String,
        rate: (m['rate'] as num).toDouble(),
        manual: (m['manual'] as int? ?? 0) == 1,
        inUse: (m['in_use'] as int? ?? 0) == 1,
        updatedAt: m['updated_at'] as String?,
      );
}

enum TxType { expense, income, transfer }

TxType txTypeFrom(String s) => TxType.values.firstWhere((e) => e.name == s, orElse: () => TxType.expense);

class Category {
  final int? id;
  final TxType type; // expense or income
  final String name;
  final String icon; // key into CategoryIcons
  final int? parentId; // null = top-level category, else sub-category
  final int sort;
  final bool archived;
  const Category({
    this.id,
    required this.type,
    required this.name,
    this.icon = 'tag',
    this.parentId,
    this.sort = 0,
    this.archived = false,
  });

  bool get isSub => parentId != null;

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'name': name,
        'icon': icon,
        'parent_id': parentId,
        'sort': sort,
        'archived': archived ? 1 : 0,
      };

  static Category fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int?,
        type: txTypeFrom(m['type'] as String),
        name: m['name'] as String,
        icon: (m['icon'] as String?) ?? 'tag',
        parentId: m['parent_id'] as int?,
        sort: m['sort'] as int? ?? 0,
        archived: (m['archived'] as int? ?? 0) == 1,
      );
}

enum AccountType { cash, bank, card }

AccountType accountTypeFrom(String s) =>
    AccountType.values.firstWhere((e) => e.name == s, orElse: () => AccountType.cash);

class Account {
  final int? id;
  final String name;
  final AccountType type;
  final String currency;
  final double openingBalance;
  final String? last4;
  final String? note;
  final double creditLimit; // cards only
  final int billDay; // cards only, 1..28
  final int dueDay; // cards only, 1..28
  final bool archived;

  /// Computed at read time (not stored): current balance in account currency.
  /// For cards this is negative when there is an outstanding amount.
  final double balance;

  const Account({
    this.id,
    required this.name,
    required this.type,
    required this.currency,
    this.openingBalance = 0,
    this.last4,
    this.note,
    this.creditLimit = 0,
    this.billDay = 1,
    this.dueDay = 20,
    this.archived = false,
    this.balance = 0,
  });

  bool get isCard => type == AccountType.card;
  double get outstanding => isCard ? (balance < 0 ? -balance : 0) : 0;
  double get availableLimit => isCard ? (creditLimit - outstanding) : 0;
  double get utilization => isCard && creditLimit > 0 ? (outstanding / creditLimit).clamp(0, 1).toDouble() : 0;

  Account copyWith({double? balance, bool? archived}) => Account(
        id: id,
        name: name,
        type: type,
        currency: currency,
        openingBalance: openingBalance,
        last4: last4,
        note: note,
        creditLimit: creditLimit,
        billDay: billDay,
        dueDay: dueDay,
        archived: archived ?? this.archived,
        balance: balance ?? this.balance,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'currency': currency,
        'opening_balance': openingBalance,
        'last4': last4,
        'note': note,
        'credit_limit': creditLimit,
        'bill_day': billDay,
        'due_day': dueDay,
        'archived': archived ? 1 : 0,
      };

  static Account fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: accountTypeFrom(m['type'] as String),
        currency: m['currency'] as String,
        openingBalance: (m['opening_balance'] as num? ?? 0).toDouble(),
        last4: m['last4'] as String?,
        note: m['note'] as String?,
        creditLimit: (m['credit_limit'] as num? ?? 0).toDouble(),
        billDay: m['bill_day'] as int? ?? 1,
        dueDay: m['due_day'] as int? ?? 20,
        archived: (m['archived'] as int? ?? 0) == 1,
        balance: (m['balance'] as num? ?? 0).toDouble(),
      );
}

class Tx {
  final int? id;
  final TxType type;
  final DateTime date;

  /// Amount as entered, in [currency].
  final double amount;
  final String currency;

  /// Rate used at entry: 1 base = rateToBase units of [currency].
  final double rateToBase;

  /// amount converted to base currency at entry time.
  final double baseAmount;

  /// Effect on the (from) account in that account's currency.
  final double accountAmount;

  /// Transfer only: amount received by the destination account (its currency).
  final double toAmount;

  final int accountId;
  final int? toAccountId;
  final int? categoryId;
  final int? subcategoryId;
  final String? note;
  final String source; // manual | import | recurring | loan | card_payment
  final int? refId;

  const Tx({
    this.id,
    required this.type,
    required this.date,
    required this.amount,
    required this.currency,
    required this.rateToBase,
    required this.baseAmount,
    required this.accountAmount,
    this.toAmount = 0,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.subcategoryId,
    this.note,
    this.source = 'manual',
    this.refId,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'date': _ymd(date),
        'amount': amount,
        'currency': currency,
        'rate_to_base': rateToBase,
        'base_amount': baseAmount,
        'account_amount': accountAmount,
        'to_amount': toAmount,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'note': note,
        'source': source,
        'ref_id': refId,
      };

  static Tx fromMap(Map<String, Object?> m) => Tx(
        id: m['id'] as int?,
        type: txTypeFrom(m['type'] as String),
        date: DateTime.parse(m['date'] as String),
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'] as String,
        rateToBase: (m['rate_to_base'] as num? ?? 1).toDouble(),
        baseAmount: (m['base_amount'] as num? ?? 0).toDouble(),
        accountAmount: (m['account_amount'] as num? ?? 0).toDouble(),
        toAmount: (m['to_amount'] as num? ?? 0).toDouble(),
        accountId: m['account_id'] as int,
        toAccountId: m['to_account_id'] as int?,
        categoryId: m['category_id'] as int?,
        subcategoryId: m['subcategory_id'] as int?,
        note: m['note'] as String?,
        source: (m['source'] as String?) ?? 'manual',
        refId: m['ref_id'] as int?,
      );
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Loan {
  final int? id;
  final String name;
  final String lender;
  final double principal;
  final double ratePct; // % per annum
  final int months;
  final DateTime startDate;
  final int emiDay;
  final double emi;
  final int accountId; // bank or card the EMI is deducted from
  final String status; // active | closed
  const Loan({
    this.id,
    required this.name,
    required this.lender,
    required this.principal,
    required this.ratePct,
    required this.months,
    required this.startDate,
    required this.emiDay,
    required this.emi,
    required this.accountId,
    this.status = 'active',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'lender': lender,
        'principal': principal,
        'rate_pct': ratePct,
        'months': months,
        'start_date': _ymd(startDate),
        'emi_day': emiDay,
        'emi': emi,
        'account_id': accountId,
        'status': status,
      };

  static Loan fromMap(Map<String, Object?> m) => Loan(
        id: m['id'] as int?,
        name: m['name'] as String,
        lender: (m['lender'] as String?) ?? '',
        principal: (m['principal'] as num).toDouble(),
        ratePct: (m['rate_pct'] as num).toDouble(),
        months: m['months'] as int,
        startDate: DateTime.parse(m['start_date'] as String),
        emiDay: m['emi_day'] as int,
        emi: (m['emi'] as num).toDouble(),
        accountId: m['account_id'] as int,
        status: (m['status'] as String?) ?? 'active',
      );
}

class LoanEmi {
  final int? id;
  final int loanId;
  final int no;
  final DateTime dueDate;
  final double principal;
  final double interest;
  final double amount;
  final double balanceAfter;
  final bool paid;
  final DateTime? paidDate;
  final int? transactionId;
  const LoanEmi({
    this.id,
    required this.loanId,
    required this.no,
    required this.dueDate,
    required this.principal,
    required this.interest,
    required this.amount,
    required this.balanceAfter,
    this.paid = false,
    this.paidDate,
    this.transactionId,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'loan_id': loanId,
        'no': no,
        'due_date': _ymd(dueDate),
        'principal': principal,
        'interest': interest,
        'amount': amount,
        'balance_after': balanceAfter,
        'paid': paid ? 1 : 0,
        'paid_date': paidDate == null ? null : _ymd(paidDate!),
        'transaction_id': transactionId,
      };

  static LoanEmi fromMap(Map<String, Object?> m) => LoanEmi(
        id: m['id'] as int?,
        loanId: m['loan_id'] as int,
        no: m['no'] as int,
        dueDate: DateTime.parse(m['due_date'] as String),
        principal: (m['principal'] as num).toDouble(),
        interest: (m['interest'] as num).toDouble(),
        amount: (m['amount'] as num).toDouble(),
        balanceAfter: (m['balance_after'] as num).toDouble(),
        paid: (m['paid'] as int? ?? 0) == 1,
        paidDate: m['paid_date'] == null ? null : DateTime.parse(m['paid_date'] as String),
        transactionId: m['transaction_id'] as int?,
      );
}

class CardCycle {
  final int? id;
  final int accountId;
  final DateTime cycleStart;
  final DateTime cycleEnd; // = bill date
  final DateTime dueDate;
  final double amountDue;
  final double paidAmount;
  final String status; // due | paid
  const CardCycle({
    this.id,
    required this.accountId,
    required this.cycleStart,
    required this.cycleEnd,
    required this.dueDate,
    required this.amountDue,
    this.paidAmount = 0,
    this.status = 'due',
  });

  double get remaining => (amountDue - paidAmount) < 0 ? 0 : amountDue - paidAmount;

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'cycle_start': _ymd(cycleStart),
        'cycle_end': _ymd(cycleEnd),
        'due_date': _ymd(dueDate),
        'amount_due': amountDue,
        'paid_amount': paidAmount,
        'status': status,
      };

  static CardCycle fromMap(Map<String, Object?> m) => CardCycle(
        id: m['id'] as int?,
        accountId: m['account_id'] as int,
        cycleStart: DateTime.parse(m['cycle_start'] as String),
        cycleEnd: DateTime.parse(m['cycle_end'] as String),
        dueDate: DateTime.parse(m['due_date'] as String),
        amountDue: (m['amount_due'] as num).toDouble(),
        paidAmount: (m['paid_amount'] as num? ?? 0).toDouble(),
        status: (m['status'] as String?) ?? 'due',
      );
}

class Recurring {
  final int? id;
  final TxType type;
  final String name;
  final double amount;
  final String currency;
  final int accountId;
  final int? toAccountId;
  final int? categoryId;
  final int? subcategoryId;
  final String frequency; // monthly | weekly | yearly
  final int day; // day of month (monthly/yearly) or weekday 1..7 (weekly)
  final DateTime startDate;
  final int? totalCount; // null = no end
  final int postedCount;
  final DateTime nextDate;
  final String status; // active | paused | completed
  final String? note;
  const Recurring({
    this.id,
    required this.type,
    required this.name,
    required this.amount,
    required this.currency,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.subcategoryId,
    this.frequency = 'monthly',
    required this.day,
    required this.startDate,
    this.totalCount,
    this.postedCount = 0,
    required this.nextDate,
    this.status = 'active',
    this.note,
  });

  Recurring copyWith({int? postedCount, DateTime? nextDate, String? status}) => Recurring(
        id: id,
        type: type,
        name: name,
        amount: amount,
        currency: currency,
        accountId: accountId,
        toAccountId: toAccountId,
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        frequency: frequency,
        day: day,
        startDate: startDate,
        totalCount: totalCount,
        postedCount: postedCount ?? this.postedCount,
        nextDate: nextDate ?? this.nextDate,
        status: status ?? this.status,
        note: note,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'name': name,
        'amount': amount,
        'currency': currency,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'frequency': frequency,
        'day': day,
        'start_date': _ymd(startDate),
        'total_count': totalCount,
        'posted_count': postedCount,
        'next_date': _ymd(nextDate),
        'status': status,
        'note': note,
      };

  static Recurring fromMap(Map<String, Object?> m) => Recurring(
        id: m['id'] as int?,
        type: txTypeFrom(m['type'] as String),
        name: m['name'] as String,
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'] as String,
        accountId: m['account_id'] as int,
        toAccountId: m['to_account_id'] as int?,
        categoryId: m['category_id'] as int?,
        subcategoryId: m['subcategory_id'] as int?,
        frequency: (m['frequency'] as String?) ?? 'monthly',
        day: m['day'] as int? ?? 1,
        startDate: DateTime.parse(m['start_date'] as String),
        totalCount: m['total_count'] as int?,
        postedCount: m['posted_count'] as int? ?? 0,
        nextDate: DateTime.parse(m['next_date'] as String),
        status: (m['status'] as String?) ?? 'active',
        note: m['note'] as String?,
      );
}
