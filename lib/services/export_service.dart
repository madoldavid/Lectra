import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:archive/archive.dart';

import '../backend/recordings/recording_store.dart';

class ExportService {
  /// Exports a single recording’s notes to PDF and returns the saved file.
  static Future<File> exportNotesToPdf({
    required RecordingEntry entry,
    required String notesText,
  }) async {
    final doc = pw.Document();

    final created = entry.createdAt;
    final duration = entry.duration;

    final body = pw.TextStyle(
      fontSize: 11,
      lineSpacing: 1.2,
    );
    final heading = pw.TextStyle(
      fontSize: 16,
      fontWeight: pw.FontWeight.bold,
    );
    final subhead = pw.TextStyle(
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(28),
          theme: pw.ThemeData.withFont(),
        ),
        build: (context) => [
          pw.Text(entry.title, style: heading),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_formatDate(created)} • ${_formatDuration(duration)}',
            style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
          ),
          pw.Divider(),
          pw.Text('AI Structured Notes', style: subhead),
          pw.SizedBox(height: 8),
          ..._buildNoteParagraphs(notesText, body),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final safeTitle =
        entry.title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').trim();
    final filename = safeTitle.isEmpty
        ? 'lecture_${DateTime.now().millisecondsSinceEpoch}.pdf'
        : '$safeTitle.pdf';
    final outPath = p.join(exportDir.path, filename);
    final file = File(outPath);
    await file.writeAsBytes(await doc.save());
    return file;
  }

  /// Exports notes to a lightweight DOCX built on the fly (no template file).
  static Future<File> exportNotesToDocx({
    required RecordingEntry entry,
    required String notesText,
  }) async {
    final archive = Archive();

    // Content Types
    const contentTypes = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
    archive.addFile(
      ArchiveFile('[Content_Types].xml', contentTypes.length, contentTypes.codeUnits),
    );

    // Relationships
    const rels = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
    archive.addFile(
      ArchiveFile('_rels/.rels', rels.length, rels.codeUnits),
    );

    // Document XML
    final docXml = _buildDocxXml(entry: entry, notesText: notesText);
    archive.addFile(
      ArchiveFile('word/document.xml', docXml.length, docXml.codeUnits),
    );

    final bytes = ZipEncoder().encode(archive) ?? <int>[];

    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final safeTitle =
        entry.title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').trim();
    final filename = safeTitle.isEmpty
        ? 'lecture_${DateTime.now().millisecondsSinceEpoch}.docx'
        : '$safeTitle.docx';
    final outPath = p.join(exportDir.path, filename);
    final file = File(outPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _buildDocxXml({
    required RecordingEntry entry,
    required String notesText,
  }) {
    final paragraphs = <String>[];

    void addPara(String text,
        {bool bold = false, double spaceAfter = 6, double spaceBefore = 0}) {
      final escaped = _escapeXml(text);
      final boldTag = bold ? '<w:b/>' : '';
      paragraphs.add('''
<w:p>
  <w:pPr>
    <w:spacing w:before="${(spaceBefore * 20).round()}" w:after="${(spaceAfter * 20).round()}"/>
  </w:pPr>
  <w:r>
    <w:rPr>$boldTag</w:rPr>
    <w:t xml:space="preserve">$escaped</w:t>
  </w:r>
</w:p>
''');
    }

    addPara(entry.title, bold: true, spaceAfter: 8);
    addPara('${_formatDate(entry.createdAt)} • ${_formatDuration(entry.duration)}',
        spaceAfter: 10);
    addPara('AI Structured Notes', bold: true, spaceAfter: 6);

    for (final line in notesText.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        paragraphs.add('<w:p><w:r><w:t/></w:t></w:r></w:p>');
      } else {
        addPara(trimmed, spaceAfter: 4);
      }
    }

    final body = paragraphs.join('\n');

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
 xmlns:v="urn:schemas-microsoft-com:vml"
 xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
 xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
 xmlns:w10="urn:schemas-microsoft-com:office:word"
 xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
 xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
 xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
 xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml"
 xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
 mc:Ignorable="w14 wp14">
  <w:body>
$body
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>
''';
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static List<pw.Widget> _buildNoteParagraphs(
    String notes,
    pw.TextStyle style,
  ) {
    final lines = notes.split('\n');
    final widgets = <pw.Widget>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(pw.SizedBox(height: 4));
        continue;
      }
      widgets.add(pw.Text(trimmed, style: style));
      widgets.add(pw.SizedBox(height: 4));
    }
    return widgets;
  }

  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
