import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// A single labelled bar row inside a distribution section.
typedef PdfDatum = ({String label, int value, String display, Color color});

/// One distribution block (e.g. "Issues by state").
typedef PdfSection = ({String title, List<PdfDatum> rows});

/// Everything needed to render the report document.
class ReportPdfData {
  ReportPdfData({
    required this.orgName,
    required this.projectName,
    required this.generatedAt,
    required this.totalIssues,
    required this.sections,
    required this.burndown,
    required this.burndownRemaining,
    this.logoUrl,
  });

  final String orgName;
  /// Organization logo (from admin settings). Rendered in the header when it
  /// resolves to an image; otherwise the Hivora wordmark is shown instead.
  final String? logoUrl;
  final String projectName;
  final DateTime generatedAt;
  final int totalIssues;
  final List<PdfSection> sections;
  // (dayIndex, remaining, ideal) — empty when no trend data is available.
  final List<({int day, double remaining, double ideal})> burndown;
  final int burndownRemaining;
}

PdfColor _c(Color c) => PdfColor.fromInt(c.toARGB32());

/// The Hivora hex signet (pointy-top hexagon + centre bar), amber stroke.
/// Tiny and simple, so it always renders in the PDF SVG engine — used as the
/// branding fallback when no org logo is configured/available.
const _hivoraMarkSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">'
    '<g fill="none" stroke="#D9A032" stroke-width="11" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M60 14 99.8 37v46L60 106 20.2 83V37Z"/>'
    '<path d="M20.2 60h79.6"/></g></svg>';

const _navy = PdfColor.fromInt(0xFF2D2B55);
const _ink = PdfColor.fromInt(0xFF23223F);
const _inkSoft = PdfColor.fromInt(0xFF6B6A85);
const _inkFaint = PdfColor.fromInt(0xFF9A99B0);
const _accentStrong = PdfColor.fromInt(0xFFB9831F);
const _canvas2 = PdfColor.fromInt(0xFFEFEEE8);
const _hairline = PdfColor.fromInt(0xFFE7E5DE);

/// Builds the report PDF and hands it to the platform (browser download on
/// web, share sheet on mobile/desktop) via the printing plugin.
Future<void> shareReportPdf(ReportPdfData data) async {
  final doc = await _buildDocument(data);
  final stamp = data.generatedAt.toIso8601String().substring(0, 10);
  final safeProject = data.projectName
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'hivora-report-$safeProject-$stamp.pdf',
  );
}

Future<pw.Document> _buildDocument(ReportPdfData data) async {
  final doc = pw.Document(
    title: 'Hivora · ${data.projectName}',
    author: 'Hivora',
  );

  final df = _fmtDate(data.generatedAt);
  final logo = await _resolveLogo(data.logoUrl);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      build: (context) => [
        _header(data, df, logo),
        pw.SizedBox(height: 22),
        _summaryRow(data),
        pw.SizedBox(height: 22),
        if (data.burndown.length >= 2) ...[
          _burndownSection(data),
          pw.SizedBox(height: 22),
        ],
        ...data.sections.map(_distributionSection),
      ],
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          'Hivora · page ${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: _inkFaint),
        ),
      ),
    ),
  );
  return doc;
}

/// Fetches the organization logo and turns it into a header widget. Handles
/// both raster (PNG/JPEG/…) and SVG logos. Returns null on any failure
/// (missing URL, network error, unsupported format) so the header can fall
/// back to the Hivora wordmark.
Future<pw.Widget?> _resolveLogo(String? url) async {
  if (url == null || url.trim().isEmpty) return null;
  final clean = url.trim();
  try {
    final res = await Dio().get<List<int>>(
      clean,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        // Mirror the API client so a logo behind the same ngrok tunnel is not
        // intercepted by ngrok's HTML browser warning. Harmless elsewhere.
        headers: const {'ngrok-skip-browser-warning': 'true'},
      ),
    );
    final bytes = Uint8List.fromList(res.data ?? const []);
    if (bytes.isEmpty) return null;

    final contentType =
        (res.headers.value('content-type') ?? '').toLowerCase();
    final isSvg = contentType.contains('svg') ||
        clean.toLowerCase().endsWith('.svg') ||
        _looksLikeSvg(bytes);

    if (isSvg) {
      return pw.SvgImage(
        svg: utf8.decode(bytes, allowMalformed: true),
        fit: pw.BoxFit.contain,
      );
    }
    return pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
  } catch (_) {
    return null;
  }
}

/// Cheap sniff for an SVG payload when the server omits a useful content-type.
bool _looksLikeSvg(Uint8List bytes) {
  final head = String.fromCharCodes(
      bytes.take(256).where((b) => b != 0)).toLowerCase();
  return head.contains('<svg') || head.contains('<?xml');
}

pw.Widget _header(ReportPdfData data, String generated, pw.Widget? logo) {
  // The navy band carries the report title. The org logo (typically a dark or
  // coloured mark made for white backgrounds) is placed ABOVE the band on the
  // white page so it stays visible — rendering it inside the navy band tended
  // to make dark logos disappear.
  final band = pw.Container(
    padding: const pw.EdgeInsets.all(20),
    decoration: const pw.BoxDecoration(
      color: _navy,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo == null) ...[
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(
                      width: 26,
                      height: 26,
                      child: pw.SvgImage(svg: _hivoraMarkSvg),
                    ),
                    pw.SizedBox(width: 9),
                    pw.Text('hivora',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 19,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 10),
              ],
              pw.Text('Project report',
                  style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(data.projectName,
                  style: const pw.TextStyle(
                      color: PdfColor.fromInt(0xFFC9C7E0), fontSize: 12)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(data.orgName,
                style: const pw.TextStyle(
                    color: PdfColors.white, fontSize: 11)),
            pw.SizedBox(height: 4),
            pw.Text('Generated $generated',
                style: const pw.TextStyle(
                    color: PdfColor.fromInt(0xFF807EA0), fontSize: 9)),
          ],
        ),
      ],
    ),
  );

  if (logo == null) return band;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 16, left: 2),
        child: pw.ConstrainedBox(
          constraints:
              const pw.BoxConstraints(maxHeight: 46, maxWidth: 260),
          child: pw.FittedBox(
            fit: pw.BoxFit.contain,
            alignment: pw.Alignment.centerLeft,
            child: logo,
          ),
        ),
      ),
      band,
    ],
  );
}

pw.Widget _summaryRow(ReportPdfData data) {
  pw.Widget stat(String value, String label) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(16),
          margin: const pw.EdgeInsets.only(right: 12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _hairline),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink)),
              pw.SizedBox(height: 2),
              pw.Text(label,
                  style: const pw.TextStyle(fontSize: 10, color: _inkSoft)),
            ],
          ),
        ),
      );

  return pw.Row(
    children: [
      stat('${data.totalIssues}', 'Total issues'),
      stat('${data.burndownRemaining}', 'Open (last 30 days)'),
      stat('${data.sections.length}', 'Breakdowns'),
    ],
  );
}

pw.Widget _sectionTitle(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Text(title,
          style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold, color: _ink)),
    );

pw.Widget _burndownSection(ReportPdfData data) {
  final maxY = data.burndown
      .map((p) => p.remaining > p.ideal ? p.remaining : p.ideal)
      .fold<double>(1, (m, v) => v > m ? v : m);
  final lastDay = (data.burndown.length - 1).toDouble();

  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _hairline),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Burndown · last 30 days',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold, color: _ink)),
            pw.Text('${data.burndownRemaining} open remaining',
                style: const pw.TextStyle(fontSize: 10, color: _inkSoft)),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.SizedBox(
          height: 200,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: pw.FixedAxis(
                [0, lastDay],
                divisions: false,
                buildLabel: (v) => pw.Text(
                  v == 0 ? '−30d' : 'today',
                  style: const pw.TextStyle(fontSize: 8, color: _inkFaint),
                ),
              ),
              yAxis: pw.FixedAxis(
                [0, (maxY / 2).roundToDouble(), maxY.ceilToDouble()],
                divisions: true,
                divisionsColor: _hairline,
                textStyle: const pw.TextStyle(fontSize: 8, color: _inkFaint),
              ),
            ),
            datasets: [
              pw.LineDataSet(
                legend: 'Ideal',
                drawSurface: false,
                drawPoints: false,
                isCurved: false,
                lineWidth: 1.2,
                color: _inkFaint,
                data: [
                  for (final p in data.burndown)
                    pw.PointChartValue(p.day.toDouble(), p.ideal),
                ],
              ),
              pw.LineDataSet(
                legend: 'Remaining',
                drawSurface: false,
                drawPoints: true,
                pointSize: 2.5,
                pointColor: _accentStrong,
                isCurved: false,
                lineWidth: 2.4,
                color: _accentStrong,
                data: [
                  for (final p in data.burndown)
                    pw.PointChartValue(p.day.toDouble(), p.remaining),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _distributionSection(PdfSection section) {
  final max = section.rows.isEmpty
      ? 1
      : section.rows.map((r) => r.value).reduce((a, b) => a > b ? a : b);
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 18),
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _hairline),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle(section.title),
        if (section.rows.isEmpty)
          pw.Text('No data',
              style: const pw.TextStyle(fontSize: 10, color: _inkFaint))
        else
          ...section.rows.map((r) => _barRow(r, max)),
      ],
    ),
  );
}

pw.Widget _barRow(PdfDatum d, int max) {
  final frac = (max == 0 ? 0.0 : d.value / max).clamp(0.0, 1.0);
  final filled = (frac * 1000).round();
  final rest = 1000 - filled;
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(d.label,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            height: 8,
            decoration: const pw.BoxDecoration(
              color: _canvas2,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              children: [
                if (filled > 0)
                  pw.Expanded(
                    flex: filled,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: _c(d.color),
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4)),
                      ),
                    ),
                  ),
                if (rest > 0) pw.Expanded(flex: rest, child: pw.SizedBox()),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.SizedBox(
          width: 60,
          child: pw.Text(d.display,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
        ),
      ],
    ),
  );
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, ${d.year} · $hh:$mm';
}
