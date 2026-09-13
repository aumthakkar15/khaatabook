import 'dart:io';

import 'package:excel/excel.dart';

import '../db/database.dart';
import '../models/models.dart';
import 'excel_io.dart';
import 'session.dart';

class ImportSummary {
  int added = 0;
  int skipped = 0;
  int updated = 0;
  final List<String> errors = [];
  @override
  String toString() =>
      'Added $added · Updated $updated · Skipped $skipped${errors.isEmpty ? '' : ' · ${errors.length} error(s)'}';
}

/// Feature 4: expense & income categories with sub-categories,
/// manual entry and Excel import.
class CategoryService {
  CategoryService._();
  static final CategoryService instance = CategoryService._();

  static const defaults = <TxType, List<MapEntry<String, List<String>>>>{
    TxType.expense: [
      MapEntry('Food & Dining|food', ['Groceries', 'Restaurants', 'Coffee & Snacks', 'Food delivery']),
      MapEntry('Transport|transport', ['Fuel', 'Taxi', 'Parking', 'Metro & Bus', 'Car maintenance']),
      MapEntry('Bills & Utilities|bills', ['Electricity', 'Water', 'Mobile', 'Internet', 'Gas']),
      MapEntry('Housing|housing', ['Rent', 'Maintenance', 'Furniture']),
      MapEntry('Health|health', ['Doctor', 'Pharmacy', 'Insurance', 'Gym']),
      MapEntry('Shopping|shopping', ['Clothing', 'Electronics', 'Home', 'Gifts']),
      MapEntry('Education|education', ['Tuition', 'Books', 'Courses']),
      MapEntry('Entertainment|entertainment', ['Movies', 'Subscriptions', 'Travel', 'Hobbies']),
      MapEntry('Family|family', ['Kids', 'Parents', 'Remittance']),
      MapEntry('Loan EMI|loan', ['Loan EMI']),
      MapEntry('Fees & Charges|fees', ['Bank charges', 'Card interest', 'Late fees']),
      MapEntry('Other|tag', ['Miscellaneous']),
    ],
    TxType.income: [
      MapEntry('Salary|salary', ['Monthly pay', 'Bonus', 'Overtime']),
      MapEntry('Business|business', ['Sales', 'Commission', 'Services']),
      MapEntry('Rental|housing', ['Property rent']),
      MapEntry('Interest & Dividends|interest', ['Bank interest', 'Dividends']),
      MapEntry('Other income|tag', ['Gift', 'Refund', 'Miscellaneous']),
    ],
  };

  Future<void> seedDefaultsIfEmpty() async {
    final d = await AppDb.instance.db;
    final rows = await d.rawQuery('SELECT COUNT(*) c FROM categories');
    if ((rows.first['c'] as int) > 0) return;
    for (final e in defaults.entries) {
      var sort = 0;
      for (final cat in e.value) {
        final parts = cat.key.split('|');
        final id = await d.insert('categories',
            Category(type: e.key, name: parts[0], icon: parts.length > 1 ? parts[1] : 'tag', sort: sort++).toMap()..remove('id'));
        var s = 0;
        for (final sub in cat.value) {
          await d.insert('categories', Category(type: e.key, name: sub, icon: 'dot', parentId: id, sort: s++).toMap()..remove('id'));
        }
      }
    }
  }

  Future<List<Category>> top(TxType type, {bool includeArchived = false}) async {
    final d = await AppDb.instance.db;
    final rows = await d.query('categories',
        where: 'type = ? AND parent_id IS NULL${includeArchived ? '' : ' AND archived = 0'}',
        whereArgs: [type.name],
        orderBy: 'sort, name');
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Category>> subs(int parentId, {bool includeArchived = false}) async {
    final d = await AppDb.instance.db;
    final rows = await d.query('categories',
        where: 'parent_id = ?${includeArchived ? '' : ' AND archived = 0'}', whereArgs: [parentId], orderBy: 'sort, name');
    return rows.map(Category.fromMap).toList();
  }

  Future<Map<int, Category>> map() async {
    final d = await AppDb.instance.db;
    final rows = await d.query('categories');
    return {for (final r in rows) r['id'] as int: Category.fromMap(r)};
  }

  /// Top-level categories ordered by how often they were used recently.
  Future<List<Category>> mostUsed(TxType type) async {
    final d = await AppDb.instance.db;
    final rows = await d.rawQuery('''
      SELECT c.*, (SELECT COUNT(*) FROM transactions t WHERE t.category_id = c.id) AS uses
      FROM categories c WHERE c.type = ? AND c.parent_id IS NULL AND c.archived = 0
      ORDER BY uses DESC, c.sort, c.name''', [type.name]);
    return rows.map(Category.fromMap).toList();
  }

  Future<int> add(Category c) async {
    final d = await AppDb.instance.db;
    final dup = await d.query('categories',
        where: 'type = ? AND name = ? COLLATE NOCASE AND ${c.parentId == null ? 'parent_id IS NULL' : 'parent_id = ?'}',
        whereArgs: c.parentId == null ? [c.type.name, c.name] : [c.type.name, c.name, c.parentId]);
    if (dup.isNotEmpty) return dup.first['id'] as int;
    final id = await d.insert('categories', c.toMap()..remove('id'));
    DataBus.instance.changed();
    return id;
  }

  Future<void> update(Category c) async {
    final d = await AppDb.instance.db;
    await d.update('categories', c.toMap()..remove('id'), where: 'id = ?', whereArgs: [c.id]);
    DataBus.instance.changed();
  }

  Future<void> setArchived(int id, bool archived) async {
    final d = await AppDb.instance.db;
    await d.update('categories', {'archived': archived ? 1 : 0}, where: 'id = ? OR parent_id = ?', whereArgs: [id, id]);
    DataBus.instance.changed();
  }

  /// Deletes only when unused; otherwise archives.
  Future<bool> delete(int id) async {
    final d = await AppDb.instance.db;
    final used = await d.rawQuery(
        'SELECT COUNT(*) c FROM transactions WHERE category_id = ? OR subcategory_id = ? OR subcategory_id IN (SELECT id FROM categories WHERE parent_id = ?)',
        [id, id, id]);
    if ((used.first['c'] as int) > 0) {
      await setArchived(id, true);
      return false;
    }
    await d.delete('categories', where: 'id = ?', whereArgs: [id]);
    DataBus.instance.changed();
    return true;
  }

  // ---------- Excel ----------
  static const importHeader = ['Type (Expense/Income)', 'Category', 'Sub-category'];

  Future<File> template() async {
    final x = ExcelIO.build({
      'Categories': [
        importHeader,
        ['Expense', 'Food & Dining', 'Groceries'],
        ['Expense', 'Food & Dining', 'Restaurants'],
        ['Income', 'Salary', 'Monthly pay'],
      ]
    });
    return ExcelIO.save(x, 'khaata_categories_template.xlsx', subDir: 'templates');
  }

  Future<ImportSummary> importExcel(Excel x) async {
    final s = ImportSummary();
    final rows = ExcelIO.rows(x);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final typeS = ExcelIO.at(r, 0).toLowerCase();
      final cat = ExcelIO.at(r, 1);
      final sub = ExcelIO.at(r, 2);
      if (cat.isEmpty) {
        s.skipped++;
        continue;
      }
      final type = typeS.startsWith('i') ? TxType.income : (typeS.startsWith('e') ? TxType.expense : null);
      if (type == null) {
        s.errors.add('Row ${i + 2}: type must be Expense or Income');
        continue;
      }
      final d = await AppDb.instance.db;
      final existing = await d.query('categories',
          where: 'type = ? AND name = ? COLLATE NOCASE AND parent_id IS NULL', whereArgs: [type.name, cat]);
      int catId;
      if (existing.isEmpty) {
        catId = await d.insert('categories', Category(type: type, name: cat).toMap()..remove('id'));
        s.added++;
      } else {
        catId = existing.first['id'] as int;
        if (sub.isEmpty) s.skipped++;
      }
      if (sub.isNotEmpty) {
        final ex2 = await d.query('categories',
            where: 'parent_id = ? AND name = ? COLLATE NOCASE', whereArgs: [catId, sub]);
        if (ex2.isEmpty) {
          await d.insert('categories', Category(type: type, name: sub, icon: 'dot', parentId: catId).toMap()..remove('id'));
          s.added++;
        } else {
          s.skipped++;
        }
      }
    }
    DataBus.instance.changed();
    return s;
  }

  Future<List<List<Object?>>> exportRows() async {
    final all = await map();
    final out = <List<Object?>>[importHeader];
    for (final c in all.values.where((c) => c.parentId == null)) {
      final subs = all.values.where((s) => s.parentId == c.id).toList();
      if (subs.isEmpty) out.add([c.type == TxType.income ? 'Income' : 'Expense', c.name, '']);
      for (final s in subs) {
        out.add([c.type == TxType.income ? 'Income' : 'Expense', c.name, s.name]);
      }
    }
    return out;
  }
}
