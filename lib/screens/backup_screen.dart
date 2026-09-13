import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';

import '../db/database.dart';
import '../services/backup_service.dart';
import '../services/excel_io.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// Feature 15: manual + automatic backup to phone / Google Drive (via the
/// system file picker or share sheet), Excel + encrypted .kbk, restore.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _auto = false;
  String _freq = 'daily';
  int _hour = 2;
  DateTime? _last;
  bool _lastAuto = false;
  bool _hasPassword = false;
  List<File> _files = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = BackupService.instance;
    _auto = await b.autoEnabled();
    _freq = await b.frequency();
    _hour = await b.hour();
    _last = await b.lastBackup();
    _lastAuto = (await AppDb.instance.getSetting('last_backup_auto') ?? '0') == '1';
    _hasPassword = ((await b.backupPassword()) ?? '').isNotEmpty;
    _files = await b.existing();
    if (mounted) setState(() {});
  }

  Future<String?> _ensurePassword() async {
    final existing = await BackupService.instance.backupPassword();
    if (existing != null && existing.isNotEmpty) return existing;
    if (!mounted) return null;
    final p = await promptText(context, 'Set a backup password', hint: 'Protects your backup files (min 6)', obscure: true, okLabel: 'Save');
    if (p == null || p.length < 6) {
      if (mounted) showMsg(context, 'Backup password must be at least 6 characters', error: true);
      return null;
    }
    await BackupService.instance.setBackupPassword(p);
    _hasPassword = true;
    return p;
  }

  Future<void> _backupNow() async {
    final pw = await _ensurePassword();
    if (pw == null) return;
    setState(() => _busy = true);
    try {
      final r = await BackupService.instance.backupNow(password: pw);
      await _load();
      if (!mounted) return;
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Backup saved on this phone', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('Also copy it to Google Drive or another place?')),
            ListTile(leading: const Icon(Icons.cloud_upload_outlined), title: const Text('Save to Google Drive / folder…'), subtitle: const Text('Opens the file picker — choose Drive'), onTap: () => Navigator.pop(c, 'drive')),
            ListTile(leading: const Icon(Icons.share_outlined), title: const Text('Share both files'), subtitle: const Text('WhatsApp, email, Drive…'), onTap: () => Navigator.pop(c, 'share')),
            ListTile(leading: const Icon(Icons.check_rounded), title: const Text('Done'), onTap: () => Navigator.pop(c, 'done')),
          ]),
        ),
      );
      if (choice == 'drive') {
        final p1 = await ExcelIO.saveAs(r.kbk);
        final p2 = await ExcelIO.saveAs(r.excel);
        if (mounted && (p1 != null || p2 != null)) showMsg(context, 'Saved');
      } else if (choice == 'share') {
        await ExcelIO.share(r.kbk, text: 'Khaata Book backup');
        await ExcelIO.share(r.excel, text: 'Khaata Book backup (Excel)');
      }
    } catch (e) {
      if (mounted) showMsg(context, 'Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final f = await BackupService.instance.pickBackupFile();
    if (f == null) return;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      if (f.name.toLowerCase().endsWith('.kbk')) {
        final ok = await confirm(context, 'Restore full backup?', 'Everything currently in the app will be REPLACED by the backup. This cannot be undone.', okLabel: 'Restore', danger: true);
        if (!ok) return;
        if (!mounted) return;
        final pw = await promptText(context, 'Backup password', obscure: true, okLabel: 'Restore');
        if (pw == null) return;
        await BackupService.instance.restoreKbk(utf8.decode(bytes), pw);
        if (mounted) showMsg(context, 'Backup restored');
      } else if (f.name.toLowerCase().endsWith('.xlsx')) {
        final ok = await confirm(context, 'Import from Excel?', 'Accounts, categories and transactions in the file will be ADDED to the app (nothing is deleted).', okLabel: 'Import');
        if (!ok) return;
        final summary = await BackupService.instance.restoreExcel(Excel.decodeBytes(bytes));
        if (!mounted) return;
        showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Import finished'), content: Text(summary), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))]));
      } else {
        showMsg(context, 'Choose a .kbk or .xlsx backup file', error: true);
      }
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAuto(bool v) async {
    if (v) {
      final pw = await _ensurePassword();
      if (pw == null) return;
    }
    await AppDb.instance.setSetting('backup_auto', v ? '1' : '0');
    _auto = v;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lastText = _last == null ? 'No backup yet' : 'Last backup · ${Dates.friendly(_last!)}, ${Dates.time.format(_last!)}${_lastAuto ? ' (automatic)' : ''}';
    return Scaffold(
      body: Column(
        children: [
          NavyHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [BackButtonNavy(), SizedBox(width: 12), Text('Backup & restore', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KColors.white))]),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(18)),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: _last == null ? KColors.amber : KColors.green, shape: BoxShape.circle), child: Icon(_last == null ? Icons.priority_high_rounded : Icons.check_rounded, color: KColors.white)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(lastText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KColors.white)),
                        const SizedBox(height: 3),
                        Text('${_files.length} file${_files.length == 1 ? '' : 's'} on this phone · keeps last 10', style: const TextStyle(fontSize: 12, color: KColors.onNavyMuted, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _backupNow,
                      icon: const Icon(Icons.backup_outlined, size: 20),
                      label: const Text('Back up now'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.settings_backup_restore_rounded, size: 20),
                      label: const Text('Restore'),
                    ),
                  ),
                ]),
                if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2)),
                const SizedBox(height: 16),
                KCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListRow(
                        leading: const IconTile(Icons.schedule_rounded),
                        title: 'Automatic backup',
                        subtitle: _auto ? 'Runs when the app is opened after the scheduled time' : 'Off',
                        trailing: Switch(value: _auto, onChanged: _setAuto),
                      ),
                      if (_auto) ...[
                        const Divider(indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Row(children: [
                            const Expanded(child: Text('Frequency', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                            for (final f in ['daily', 'weekly', 'monthly']) ...[
                              Pill(f[0].toUpperCase() + f.substring(1), selected: _freq == f, onTap: () async {
                                await AppDb.instance.setSetting('backup_freq', f);
                                setState(() => _freq = f);
                              }),
                              const SizedBox(width: 6),
                            ],
                          ]),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        ListRow(
                          leading: const IconTile(Icons.access_time_rounded),
                          title: 'Time',
                          subtitle: 'Backup is taken the first time the app opens after this time',
                          trailing: Text('${_hour.toString().padLeft(2, '0')}:00', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          onTap: () async {
                            final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _hour, minute: 0));
                            if (t != null) {
                              await AppDb.instance.setSetting('backup_hour', t.hour.toString());
                              setState(() => _hour = t.hour);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionLabel('Backup to'),
                KCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    const ListRow(
                      leading: IconTile(Icons.smartphone_rounded),
                      title: 'This phone',
                      subtitle: 'App folder KhaataBook/Backups · always on',
                      trailing: Icon(Icons.check_box_rounded, color: KColors.navy),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListRow(
                      leading: const IconTile(Icons.cloud_outlined),
                      title: 'Google Drive',
                      subtitle: 'After each backup choose "Save to Google Drive" — needs internet',
                      trailing: const Icon(Icons.open_in_new_rounded, color: KColors.faint, size: 18),
                      onTap: _files.isEmpty ? null : () async {
                        final f = _files.first;
                        final p = await ExcelIO.saveAs(f);
                        if (mounted && p != null) showMsg(context, 'Saved');
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                const SectionLabel('File format'),
                Row(children: [
                  Expanded(child: _fmt('Excel (.xlsx)', 'Readable · one sheet per master · importable')),
                  const SizedBox(width: 10),
                  Expanded(child: _fmt('Khaata file (.kbk)', 'Full restore · encrypted with your backup password')),
                ]),
                const SizedBox(height: 16),
                KCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    const IconTile(Icons.key_outlined),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_hasPassword ? 'Backup password is set' : 'No backup password yet', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    TextButton(
                      onPressed: () async {
                        final p = await promptText(context, 'Backup password', hint: 'Min 6 characters', obscure: true, okLabel: 'Save');
                        if (p != null && p.length >= 6) {
                          await BackupService.instance.setBackupPassword(p);
                          setState(() => _hasPassword = true);
                        }
                      },
                      child: Text(_hasPassword ? 'Change' : 'Set'),
                    ),
                  ]),
                ),
                if (_files.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const SectionLabel('Backups on this phone'),
                  KCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < _files.length && i < 10; i++) ...[
                        if (i > 0) const Divider(indent: 16, endIndent: 16),
                        ListRow(
                          leading: IconTile(_files[i].path.endsWith('.kbk') ? Icons.lock_outline : Icons.table_chart_outlined),
                          title: _files[i].uri.pathSegments.last,
                          subtitle: '${Dates.friendly(_files[i].lastModifiedSync())} · ${(_files[i].lengthSync() / 1024).toStringAsFixed(0)} KB',
                          trailing: IconButton(icon: const Icon(Icons.share_outlined, color: KColors.muted, size: 20), onPressed: () => ExcelIO.share(_files[i])),
                        ),
                      ],
                    ]),
                  ),
                ],
                const SizedBox(height: 12),
                Text('Base currency ${Session.instance.base} · all masters and transactions are included in every backup.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: KColors.faint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fmt(String t, String s) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: KColors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: KColors.navy, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(s, style: const TextStyle(fontSize: 11, color: KColors.muted)),
        ]),
      );
}
