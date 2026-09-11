import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/table.dart';

/// Builds and shares/prints a simple, print-ready table-tent style PDF
/// containing a table's QR ordering code — same pattern as ReceiptService.
class QrService {
  Future<Uint8List> buildQrFlyerPdf(CafeTable table, Uint8List qrPngBytes, {String cafeName = 'Fast N Fresh Cafe'}) async {
    final doc = pw.Document();
    final qrImage = pw.MemoryImage(qrPngBytes);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                cafeName,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Scan to view menu & order', style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 18),
              pw.Image(qrImage, width: 180, height: 180),
              pw.SizedBox(height: 18),
              pw.Text(
                table.name,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<void> printQrFlyer(CafeTable table, Uint8List qrPngBytes, {String cafeName = 'Fast N Fresh Cafe'}) async {
    final bytes = await buildQrFlyerPdf(table, qrPngBytes, cafeName: cafeName);
    // Lock the print job to the flyer's real A6 page size (matching
    // pageFormat above) instead of letting the OS renegotiate against the
    // selected printer, which otherwise defaults to A4 and prints the
    // small flyer pinned to a corner of an otherwise blank full page.
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: PdfPageFormat.a6,
      dynamicLayout: false,
    );
  }

  Future<void> shareQrFlyer(CafeTable table, Uint8List qrPngBytes, {String cafeName = 'Fast N Fresh Cafe'}) async {
    final bytes = await buildQrFlyerPdf(table, qrPngBytes, cafeName: cafeName);
    await Printing.sharePdf(bytes: bytes, filename: 'table-${table.number ?? table.name}-qr.pdf');
  }
}
