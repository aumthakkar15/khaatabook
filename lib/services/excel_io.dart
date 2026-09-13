import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Small helpers shared by every Excel import/export in the app.
class ExcelIO {
  /// Lets the user pick an .xlsx file; returns null if cancelled.
  static Future<Excel?> pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) return null;
    return Excel.decodeBytes(bytes);
  }

  /// Rows of the first sheet (or the sheet named [sheet]) as trimmed strings,
  /// skipping the header row and fully empty rows.
  static List<List<String>> rows(Excel x, {String? sheet, bool skipHeader = true}) {
    final name = sheet != null && x.tables.containsKey(sheet) ? sheet : x.tables.keys.first;
    final t = x.tables[name]!;
    final out = <List<String>>[];
    for (var i = skipHeader ? 1 : 0; i < t.rows.length; i++) {
      final r = t.rows[i].map((c) => cellText(c)).toList();
      if (r.every((s) => s.isEmpty)) continue;
      out.add(r);
    }
    return out;
  }

  static String cellText(Data? c) {
    if (c == null || c.value == null) return '';
    final v = c.value;
    if (v is DateCellValue) {
      return '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    if (v is DateTimeCellValue) {
      return '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    if (v is IntCellValue) return v.value.toString();
    if (v is TextCellValue) {
      final dynamic span = v.value;
      try {
        final dynamic t = span.text;
        if (t is String) return t.trim();
      } catch (_) {}
      return span.toString().trim();
    }
    return v.toString().trim();
  }

  static String at(List<String> r, int i) => i < r.length ? r[i].trim() : '';

  /// Builds a workbook with [sheets] = {name: [header, ...rows]}.
  static Excel build(Map<String, List<List<Object?>>> sheets) {
    final x = Excel.createExcel();
    final defaultSheet = x.getDefaultSheet();
    var first = true;
    for (final e in sheets.entries) {
      if (first && defaultSheet != null) {
        x.rename(defaultSheet, e.key);
        first = false;
      }
      final s = x[e.key];
      for (final row in e.value) {
        s.appendRow(row.map<CellValue?>((v) {
          if (v == null) return null;
          if (v is int) return IntCellValue(v);
          if (v is double) return DoubleCellValue(v);
          return TextCellValue(v.toString());
        }).toList());
      }
    }
    return x;
  }

  /// Saves the workbook into the app documents folder and returns the file.
  static Future<File> save(Excel x, String fileName, {String subDir = 'exports'}) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/KhaataBook/$subDir');
    if (!await folder.exists()) await folder.create(recursive: true);
    final f = File('${folder.path}/$fileName');
    final bytes = x.encode();
    await f.writeAsBytes(bytes!, flush: true);
    return f;
  }

  /// Opens the Android share sheet (WhatsApp, Drive, Files, email...).
  static Future<void> share(File f, {String? text}) async {
    await Share.shareXFiles([XFile(f.path)], text: text);
  }

  /// Lets the user choose a folder (e.g. Google Drive in the Files app) and
  /// copies the file there. Returns the saved path, or null if cancelled.
  static Future<String?> saveAs(File f) async {
    final bytes = await f.readAsBytes();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save backup',
      fileName: f.uri.pathSegments.last,
      bytes: bytes,
    );
    return path;
  }
}
