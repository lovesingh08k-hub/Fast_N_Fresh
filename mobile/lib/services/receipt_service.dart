import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../core/utils/formatters.dart';
import '../models/misc_models.dart';
import '../models/order.dart';
import 'bluetooth_printer_service.dart';

/// Creates formal, thermal-printer-friendly cafe bills.
///
/// The layout intentionally follows a classic printed POS receipt:
/// centered cafe header, TAX INVOICE, compact bill metadata, fixed columns
/// for Item / Qty / Rate / Amount, discount, CGST/SGST, grand total, GST and
/// a simple closing footer. It works with both 55 mm and 80 mm rolls.
class ReceiptService {
  static const double width55mm = 55 * PdfPageFormat.mm;
  static const double width58mm = 58 * PdfPageFormat.mm;
  static const double width80mm = 80 * PdfPageFormat.mm;

  pw.Font get _mono => pw.Font.courier();
  pw.Font get _monoBold => pw.Font.courierBold();

  Future<Uint8List> buildReceiptPdf(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final doc = pw.Document();
    final isNarrow = widthMm <= 60;
    final chars = isNarrow ? 30 : 42;
    const fontSize = 7.2;
    const smallSize = 6.4;
    final format = _receiptFormat(widthMm, _itemRowCount(order, widthMm));

    final totalTax = order.tax;
    final halfTax = totalTax / 2;
    final taxRate = settings.taxEnabled ? settings.taxPercent : 0;
    final halfRate = taxRate / 2;
    final cafeName = _fit(settings.cafeName, chars);
    final address = _wrap(settings.address, chars);
    final phone = settings.phone.trim();
    final gst = settings.gstNumber.trim();
    final orderFrom = _orderFrom(order);

    doc.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: _mono, bold: _monoBold),
        build: (_) {
          final widgets = <pw.Widget>[];
          widgets.add(_center(cafeName, fontSize + 2, bold: true));
          widgets.add(_center('The food which makes you happy', smallSize));
          if (phone.isNotEmpty) widgets.add(_center('Phone: $phone', smallSize));
          for (final line in address) {
            widgets.add(_center(line, smallSize));
          }
          if (gst.isNotEmpty) widgets.add(_center('GSTIN: $gst', smallSize));
          if (settings.fssai.trim().isNotEmpty) widgets.add(_center('FSSAI: ${settings.fssai.trim()}', smallSize));

          widgets.add(_gap(3));
          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_line('Order from: ${_fit(orderFrom, chars)}', fontSize));
          widgets.add(_twoColumn(
            '${Formatters.shortDate(order.createdAt)} ${Formatters.time(order.createdAt)}',
            'Bill #${order.orderNumber}',
            chars,
            fontSize,
          ));
          if (order.invoiceNumber != null) {
            widgets.add(_line('Invoice: ${_fit(order.invoiceNumber!, chars - 9)}', fontSize));
          }
          if (order.printCustomerName != null) {
            widgets.add(_line('Customer: ${_fit(order.printCustomerName!, chars)}', fontSize));
          }
          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_receiptColumnHeader(chars, fontSize));
          widgets.add(_line(_dash(chars), fontSize));

          for (final item in order.items) {
            for (final row in _itemRows(item.name, item.quantity.toString(), _money(item.total), chars)) {
              widgets.add(_line(row, fontSize));
            }
          }

          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_summaryLine('Sub Total', _money(order.subtotal), chars, fontSize));
          for (final row in _billLines(order, halfRate, halfTax)) {
            widgets.add(_summaryLine(row.$1, row.$2, chars, fontSize));
          }
          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_summaryLine('TOTAL', _money(order.grandTotal), chars, fontSize, bold: true, large: true));
          widgets.add(_summaryLine('Payment mode', paymentLabel(order), chars, fontSize));
                    widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_center('Thank you!', fontSize + .5, bold: true));
          if (settings.receiptFooter.trim().isNotEmpty) {
            for (final line in _wrap(settings.receiptFooter, chars)) {
              widgets.add(_center(line, smallSize));
            }
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: widgets,
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _center(String text, double size, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: bold ? _monoBold : _mono,
          fontSize: size,
        ),
      ),
    );
  }

  pw.Widget _line(String text, double size) {
    return pw.Text(
      text,
      maxLines: 1,
      style: pw.TextStyle(font: _mono, fontSize: size),
    );
  }

  pw.Widget _twoColumn(String left, String right, int chars, double size) {
    final rightWidth = (right.trim().length + 1).clamp(1, chars - 1);
    final leftWidth = chars - rightWidth;
    return pw.Text(
      _fit(left, leftWidth).padRight(leftWidth) + _fit(right, rightWidth).padLeft(rightWidth),
      maxLines: 1,
      style: pw.TextStyle(font: _mono, fontSize: size),
    );
  }

  pw.Widget _receiptColumnHeader(int chars, double size) {
    const qtyWidth = 5;
    const amountWidth = 11;
    final itemWidth = chars - qtyWidth - amountWidth;
    return _line(
      _fit('ITEM', itemWidth).padRight(itemWidth) +
          _fit('QTY', qtyWidth).padLeft(qtyWidth) +
          _fit('AMT', amountWidth).padLeft(amountWidth),
      size,
    );
  }

  /// "ITEM  QTY  AMT" rows with the full item name: a long name wraps onto
  /// following lines in the ITEM column instead of being cut with "...".
  /// QTY and AMT are printed on the first line only.
  List<String> _itemRows(String item, String qty, String amount, int chars) {
    const qtyWidth = 5;
    const amountWidth = 11;
    final itemWidth = chars - qtyWidth - amountWidth;
    final nameLines = _wrap(item, itemWidth);
    if (nameLines.isEmpty) nameLines.add('');
    return [
      nameLines.first.padRight(itemWidth) +
          _fit(qty, qtyWidth).padLeft(qtyWidth) +
          _fit(amount, amountWidth).padLeft(amountWidth),
      ...nameLines.skip(1),
    ];
  }

  int _itemRowCount(Order order, double widthMm) {
    final chars = widthMm <= 60 ? 30 : 42;
    return order.items.fold(
      0,
      (sum, item) => sum + _itemRows(item.name, '', '', chars).length,
    );
  }

  pw.Widget _summaryLine(
    String label,
    String value,
    int chars,
    double size, {
    bool bold = false,
    bool large = false,
  }) {
    final valueWidth = large ? 10 : 10;
    final labelWidth = chars - valueWidth;
    return pw.Text(
      _fit(label, labelWidth).padRight(labelWidth) + _fit(value, valueWidth).padLeft(valueWidth),
      maxLines: 1,
      style: pw.TextStyle(
        font: bold ? _monoBold : _mono,
        fontSize: large ? size + 1.2 : size,
      ),
    );
  }

  pw.Widget _gap(double height) => pw.SizedBox(height: height);

  String _orderFrom(Order order) {
    final table = order.tableName?.trim() ?? '';
    if (table.isNotEmpty) {
      // Table names are often already "Table 1"; avoid "Table Table 1".
      return table.toLowerCase().startsWith('table') ? table : 'Table $table';
    }
    if (order.orderType == 'delivery') return 'Delivery';
    if (order.orderType == 'takeaway') return 'Take Away';
    return 'Dine In';
  }

  String _dash(int chars) => List.filled(chars, '-').join();

  String _fit(String value, int width) {
    final cleaned = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (cleaned.length <= width) return cleaned;
    if (width <= 1) return cleaned.substring(0, width);
    return '${cleaned.substring(0, width - 3)}...';
  }

  List<String> _wrap(String value, int width) {
    final cleaned = value.replaceAll('\r', '').trim();
    if (cleaned.isEmpty) return const [];
    final result = <String>[];
    for (final sourceLine in cleaned.split('\n')) {
      var line = sourceLine.trim();
      while (line.length > width) {
        var cut = line.lastIndexOf(' ', width);
        if (cut <= 0) cut = width;
        result.add(line.substring(0, cut).trim());
        line = line.substring(cut).trim();
      }
      if (line.isNotEmpty) result.add(line);
    }
    return result;
  }

  String _money(num value) {
    return value.toStringAsFixed(2);
  }

  String _rate(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  /// The exact page size used for a receipt with [itemRows] item lines on a
  /// [widthMm] roll. Shared by [buildReceiptPdf] (to build the PDF) and
  /// [printReceipt] (to tell the OS print dialog what size that PDF already
  /// is), so the two can never disagree.
  PdfPageFormat _receiptFormat(double widthMm, int itemRows) {
    final pageWidth = widthMm * PdfPageFormat.mm;
    const fontSize = 7.2;
    final lineCount = 24 + itemRows * 2;
    final estimatedHeight = (lineCount * (fontSize + 2.5) + 70).clamp(180, 500).toDouble() * PdfPageFormat.mm;
    return PdfPageFormat(
      pageWidth,
      estimatedHeight,
      marginLeft: 3.5 * PdfPageFormat.mm,
      marginRight: 3.5 * PdfPageFormat.mm,
      marginTop: 4 * PdfPageFormat.mm,
      marginBottom: 4 * PdfPageFormat.mm,
    );
  }

  Future<void> printReceipt(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final bytes = await buildReceiptPdf(order, settings, widthMm: widthMm);

    // IMPORTANT: without an explicit `format` (matching the PDF's own page
    // size) and `dynamicLayout: false`, the OS print dialog is free to
    // renegotiate the page size against the selected printer — commonly
    // defaulting to A4. Since our PDF is a small fixed thermal-roll size,
    // that renegotiation is exactly what caused receipts to print as a
    // small block pinned to the left of an otherwise blank full page.
    // Locking the job to the receipt's real format keeps output filling the
    // 55mm/80mm roll edge to edge.
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: _receiptFormat(widthMm, _itemRowCount(order, widthMm)),
      dynamicLayout: false,
    );
  }

  Future<void> shareReceipt(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final bytes = await buildReceiptPdf(order, settings, widthMm: widthMm);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'bill_${order.orderNumber}.pdf',
    );
  }

  Future<void> shareTextSummary(
    Order order,
    BusinessSettings settings,
  ) async {
    final buffer = StringBuffer()
      ..writeln(settings.cafeName)
      ..writeln('The food which makes you happy')
      ..writeln('Phone: ${settings.phone}')
      ..writeln('Address: ${settings.address}')
      ..writeln('GSTIN: ${settings.gstNumber}')
      ..writeln('Order from: ${order.tableName?.trim().isNotEmpty == true ? order.tableName : order.orderType}')
      ..writeln('Bill #${order.orderNumber}${order.invoiceNumber != null ? '  Invoice: ${order.invoiceNumber}' : ''}')
      ..writeln('Date: ${Formatters.shortDate(order.createdAt)}')
      ..writeln('Time: ${Formatters.time(order.createdAt)}')
      ..writeln('---');

    for (final item in order.items) {
      buffer.writeln(
        '${item.name}  ${item.quantity}  ${_money(item.total)}',
      );
    }

    buffer
      ..writeln('---')
      ..writeln('Sub Total : ${_money(order.subtotal)}');
    final halfRate = (settings.taxEnabled ? settings.taxPercent : 0) / 2;
    for (final row in _billLines(order, halfRate, order.tax / 2)) {
      buffer.writeln('${row.$1}: ${row.$2}');
    }
    buffer
      ..writeln('TOTAL     : ${_money(order.grandTotal)}')
      ..writeln('Payment mode: ${paymentLabel(order)}')
      ..writeln(settings.receiptFooter)
      ..writeln('Powered by PWP');

    await Share.share(buffer.toString());
  }

  // ---------------------------------------------------------------------
  // Bluetooth thermal (ESC/POS) printing — the café billing-counter path.
  //
  // This prints the SAME bill data as buildReceiptPdf() above (same
  // subtotal/discount/tax/total, same item list, same order metadata) — it
  // only renders it differently: as raw ESC/POS commands sent directly to
  // a paired Bluetooth thermal printer, instead of a PDF handed to the
  // OS/A4 print dialog. No billing/order logic is touched.
  // ---------------------------------------------------------------------

  /// Builds the raw ESC/POS byte ticket for [order] on a 58mm or 80mm
  /// thermal roll. Font A on these printers is conventionally 32 columns
  /// wide on 58mm paper and 48 columns wide on 80mm paper.
  Future<List<int>> buildThermalTicketBytes(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final isNarrow = widthMm <= 60;
    final profile = await CapabilityProfile.load();
    // esc_pos_utils_plus exposes 58mm as its narrow ESC/POS profile. We use
    // the 58mm command profile for 55mm rolls but constrain content to 30
    // columns so the printed ticket stays compact and readable.
    final generator = Generator(isNarrow ? PaperSize.mm58 : PaperSize.mm80, profile);
    final chars = isNarrow ? 30 : 48;
    final itemWidth = chars - 16;
    const qtyWidth = 5;
    const amountWidth = 11;

    List<int> bytes = [];
    final cafeName = _fit(settings.cafeName, chars);
    // Double-width text uses two columns per character. On a 58mm roll
    // (32 columns) a 17-letter name would spill its last letter onto a
    // second line, so fall back to tall-but-normal-width text when needed.
    final fitsDoubleWidth = cafeName.length * 2 <= (isNarrow ? 32 : 48);
    bytes += generator.text(
      cafeName,
      styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: fitsDoubleWidth ? PosTextSize.size2 : PosTextSize.size1,
      ),
    );
    bytes += generator.text('The food which makes you happy', styles: const PosStyles(align: PosAlign.center));
    if (settings.phone.trim().isNotEmpty) {
      bytes += generator.text('Phone: ${settings.phone.trim()}', styles: const PosStyles(align: PosAlign.center));
    }
    for (final line in _wrap(settings.address, chars)) {
      bytes += generator.text(line, styles: const PosStyles(align: PosAlign.center));
    }
    if (settings.gstNumber.trim().isNotEmpty) {
      bytes += generator.text('GSTIN: ${settings.gstNumber.trim()}', styles: const PosStyles(align: PosAlign.center));
    }
    if (settings.fssai.trim().isNotEmpty) {
      bytes += generator.text('FSSAI: ${settings.fssai.trim()}', styles: const PosStyles(align: PosAlign.center));
    }

    bytes += generator.hr();
    final orderFrom = _orderFrom(order);
    bytes += generator.text('Order from: $orderFrom');
    bytes += generator.text(_twoColumnText(
      '${Formatters.shortDate(order.createdAt)} ${Formatters.time(order.createdAt)}',
      'Bill #${order.orderNumber}',
      chars,
    ));
    if (order.invoiceNumber != null) {
      bytes += generator.text('Invoice: ${_fit(order.invoiceNumber!, chars - 9)}');
    }
    if (order.printCustomerName != null) {
      bytes += generator.text('Customer: ${_fit(order.printCustomerName!, chars)}');
    }
    bytes += generator.hr();

    final header = _fit('ITEM', itemWidth).padRight(itemWidth) +
        _fit('QTY', qtyWidth).padLeft(qtyWidth) +
        _fit('AMT', amountWidth).padLeft(amountWidth);
    bytes += generator.text(header);
    bytes += generator.hr();

    for (final item in order.items) {
      for (final row in _itemRows(item.name, item.quantity.toString(), _money(item.total), chars)) {
        bytes += generator.text(row);
      }
    }

    bytes += generator.hr();
    bytes += generator.text(_summaryLineText('Sub Total', _money(order.subtotal), chars));
    final halfRate = (settings.taxEnabled ? settings.taxPercent : 0) / 2;
    for (final row in _billLines(order, halfRate, order.tax / 2)) {
      bytes += generator.text(_summaryLineText(row.$1, row.$2, chars));
    }
    bytes += generator.hr();
    bytes += generator.text(
      _summaryLineText('TOTAL', _money(order.grandTotal), chars),
      styles: const PosStyles(bold: true),
    );
    bytes += generator.text(_summaryLineText('Payment mode', paymentLabel(order), chars));
    bytes += generator.hr();
    bytes += generator.text('Thank you!', styles: const PosStyles(align: PosAlign.center, bold: true));
    for (final line in _wrap(settings.receiptFooter, chars)) {
      bytes += generator.text(line, styles: const PosStyles(align: PosAlign.center));
    }
    bytes += generator.feed(1);
    bytes += generator.cut();
    return bytes;
  }

  /// Prints [order] on the currently-connected Bluetooth thermal printer.
  /// Returns false if no printer is connected or the print failed — the
  /// caller should send the user to the printer settings screen in that
  /// case rather than silently falling back to the A4/PDF dialog.
  Future<bool> printViaBluetooth(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    // The web app prints through the browser print dialog instead.
    if (kIsWeb) {
      await printReceipt(order, settings, widthMm: widthMm);
      return true;
    }
    final bytes = await buildThermalTicketBytes(order, settings, widthMm: widthMm);
    return BluetoothPrinterService().printBytes(bytes);
  }

  /// Rows between Sub Total and TOTAL: discount, charges, CGST/SGST (or
  /// IGST) per rate and round-off. Bills from before per-rate GST only have
  /// a total tax, printed as half CGST / half SGST at the outlet rate.
  List<(String, String)> _billLines(Order order, num legacyHalfRate, double legacyHalfTax) {
    final halfRate = legacyHalfRate.toDouble();
    final bill = order.bill;
    final rows = <(String, String)>[];
    if (bill.taxes.isEmpty && order.tax > 0) {
      if (order.discount > 0) rows.add(('Discount', '-${_money(order.discount)}'));
      rows.add(('CGST @${_rate(halfRate)}%', _money(legacyHalfTax)));
      rows.add(('SGST @${_rate(halfRate)}%', _money(legacyHalfTax)));
      return rows;
    }
    for (final row in bill.rows()) {
      rows.add((row.$1, row.$2 < 0 ? '-${_money(-row.$2)}' : _money(row.$2)));
    }
    return rows;
  }

  /// "Card", "Online (Swiggy)", "Complimentary", "Mixed (Cash 100, Card 121)".
  static String paymentLabel(Order order) {
    final b = order.paymentBreakdown;
    switch (order.paymentMethod) {
      case 'ONLINE':
        return order.onlinePlatform == null ? 'Online' : 'Online (${order.onlinePlatform})';
      case 'COMPLIMENTARY':
        return 'Complimentary';
      case 'CARD':
        return 'Card';
      case 'MIXED':
        final parts = [
          if (b.cash > 0) 'Cash ${b.cash.toStringAsFixed(0)}',
          if (b.upi > 0) 'UPI ${b.upi.toStringAsFixed(0)}',
          if (b.card > 0) 'Card ${b.card.toStringAsFixed(0)}',
          if (b.credit > 0) 'Credit ${b.credit.toStringAsFixed(0)}',
        ];
        return parts.isEmpty ? 'Mixed' : 'Mixed (${parts.join(', ')})';
      default:
        return order.paymentMethod;
    }
  }

  String _twoColumnText(String left, String right, int chars) {
    final rightWidth = (right.trim().length + 1).clamp(1, chars - 1);
    final leftWidth = chars - rightWidth;
    return _fit(left, leftWidth).padRight(leftWidth) + _fit(right, rightWidth).padLeft(rightWidth);
  }

  String _summaryLineText(String label, String value, int chars) {
    const valueWidth = 10;
    final labelWidth = chars - valueWidth;
    return _fit(label, labelWidth).padRight(labelWidth) + _fit(value, valueWidth).padLeft(valueWidth);
  }
}
