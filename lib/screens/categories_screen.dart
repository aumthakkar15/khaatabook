import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/category_service.dart';
import '../services/excel_io.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Feature 4: expense & income category master with sub-categories,
/// manual add/edit and Excel import.
class CategoriesScreen extends StatefulWidget {
  final TxType? initialType;
  const CategoriesScreen({super.key, this.initialType});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  TxType _type = TxType.expense;
  List<Category> _cats = [];
  Map<int, List<Category>> _subs = {};
  int? _expanded;
  int _expenseCount = 0, _incomeCount = 0;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType == TxType.income ? TxType.income : TxType.expense;
    DataBus.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    _cats = await CategoryService.instance.top(_type);
    _subs = {for (final c in _cats) c.id!: await CategoryService.instance.subs(c.id!)};
    _expenseCount = (await CategoryService.instance.top(TxType.expense)).length;
    _incomeCount = (await CategoryService.instance.top(TxType.income)).length;
    if (mounted) setState(() {});
  }

  Future<void> _addCategory({Category? edit}) async {
    final name = TextEditingController(text: edit?.name ?? '');
    var icon = edit?.icon ?? 'tag';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(edit == null ? 'New ${_type.name} category' : 'Edit category', style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Category name')),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in CategoryIcons.keys)
                    InkWell(
                      onTap: () => setD(() => icon = k),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: icon == k ? KColors.navy : KColors.offWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: icon == k ? KColors.navy : KColors.line)),
                        child: Icon(CategoryIcons.of(k), size: 20, color: icon == k ? KColors.white : KColors.navy),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    if (edit == null) {
      await CategoryService.instance.add(Category(type: _type, name: name.text.trim(), icon: icon, sort: _cats.length));
    } else {
      await CategoryService.instance.update(Category(id: edit.id, type: edit.type, name: name.text.trim(), icon: icon, parentId: edit.parentId, sort: edit.sort, archived: edit.archived));
    }
  }

  Future<void> _addSub(Category parent, {Category? edit}) async {
    final v = await promptText(context, edit == null ? 'New sub-category in ${parent.name}' : 'Edit sub-category', hint: 'Sub-category name', initial: edit?.name, okLabel: 'Save');
    if (v == null || v.trim().isEmpty) return;
    if (edit == null) {
      await CategoryService.instance.add(Category(type: _type, name: v.trim(), icon: 'dot', parentId: parent.id, sort: (_subs[parent.id] ?? []).length));
    } else {
      await CategoryService.instance.update(Category(id: edit.id, type: edit.type, name: v.trim(), icon: 'dot', parentId: edit.parentId, sort: edit.sort));
    }
  }

  Future<void> _menu(Category c, {Category? parent}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (x) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800))),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Rename / edit'), onTap: () => Navigator.pop(x, 'edit')),
          if (parent == null) ListTile(leading: const Icon(Icons.add_rounded), title: const Text('Add sub-category'), onTap: () => Navigator.pop(x, 'sub')),
          ListTile(leading: const Icon(Icons.delete_outline, color: KColors.red), title: const Text('Delete', style: TextStyle(color: KColors.red)), onTap: () => Navigator.pop(x, 'delete')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        parent == null ? await _addCategory(edit: c) : await _addSub(parent, edit: c);
      case 'sub':
        await _addSub(c);
      case 'delete':
        final ok = await confirm(context, 'Delete ${c.name}?', 'If it is already used in transactions it will be archived instead of deleted.', okLabel: 'Delete', danger: true);
        if (!ok) return;
        final deleted = await CategoryService.instance.delete(c.id!);
        if (mounted) showMsg(context, deleted ? 'Deleted' : 'In use — archived instead');
    }
  }

  Future<void> _import() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.upload_file_outlined), title: const Text('Import categories from Excel'), subtitle: const Text('Columns: Type | Category | Sub-category'), onTap: () => Navigator.pop(c, 'import')),
          ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Get the Excel template'), onTap: () => Navigator.pop(c, 'template')),
        ]),
      ),
    );
    if (choice == 'template') {
      final f = await CategoryService.instance.template();
      await ExcelIO.share(f, text: 'Khaata Book – categories template');
    } else if (choice == 'import') {
      final x = await ExcelIO.pick();
      if (x == null) return;
      final s = await CategoryService.instance.importExcel(x);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Import finished', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(child: Text([s.toString(), ...s.errors].join('\n'))),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          NavyHeader(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Row(children: [
                  const BackButtonNavy(),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Categories', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KColors.white))),
                  Pill('Import Excel', onNavy: true, selected: true, icon: Icons.upload_file_outlined, onTap: _import),
                ]),
                const SizedBox(height: 18),
                Segmented<TxType>(
                  values: const [TxType.expense, TxType.income],
                  value: _type,
                  onNavy: true,
                  label: (t) => t == TxType.expense ? 'Expense  $_expenseCount' : 'Income  $_incomeCount',
                  onChanged: (t) {
                    _type = t;
                    _expanded = null;
                    _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              children: [
                for (final c in _cats) ...[
                  KCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListRow(
                          leading: IconTile(CategoryIcons.of(c.icon), filled: _expanded == c.id),
                          title: c.name,
                          subtitle: (_subs[c.id] ?? []).isEmpty ? 'No sub-categories' : (_subs[c.id]!.length <= 4 ? _subs[c.id]!.map((s) => s.name).join(' · ') : '${_subs[c.id]!.length} sub-categories'),
                          trailing: Icon(_expanded == c.id ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: KColors.faint),
                          onTap: () => setState(() => _expanded = _expanded == c.id ? null : c.id),
                          onLongPress: () => _menu(c),
                        ),
                        if (_expanded == c.id)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              children: [
                                for (final s in _subs[c.id] ?? [])
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: InkWell(
                                      onTap: () => _menu(s, parent: c),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 44,
                                        padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                                        decoration: BoxDecoration(color: KColors.offWhite, borderRadius: BorderRadius.circular(12)),
                                        child: Row(children: [
                                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: KColors.navy, shape: BoxShape.circle)),
                                          const SizedBox(width: 10),
                                          Expanded(child: Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                                          const Icon(Icons.edit_outlined, size: 16, color: KColors.faint),
                                        ]),
                                      ),
                                    ),
                                  ),
                                InkWell(
                                  onTap: () => _addSub(c),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    height: 44,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: KColors.faint)),
                                    child: const Row(children: [
                                      Icon(Icons.add_rounded, size: 16, color: KColors.navyMid),
                                      SizedBox(width: 8),
                                      Text('Add sub-category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: KColors.navyMid)),
                                    ]),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  TextButton.icon(onPressed: () => _menu(c), icon: const Icon(Icons.more_horiz_rounded, size: 18), label: const Text('Edit category')),
                                ]),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_cats.isEmpty) const KCard(child: EmptyState(icon: Icons.sell_outlined, title: 'No categories yet')),
                const SizedBox(height: 8),
                const Text('Tip: long-press a category or tap a sub-category to rename or delete it.', style: TextStyle(fontSize: 12, color: KColors.faint), textAlign: TextAlign.center),
              ],
            ),
          ),
          BottomButton(label: 'New ${_type == TxType.income ? 'income' : 'expense'} category', icon: Icons.add_rounded, onPressed: () => _addCategory()),
        ],
      ),
    );
  }
}
