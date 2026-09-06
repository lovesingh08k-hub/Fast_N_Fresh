import 'dart:typed_data';

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
    final fontSize = is58 ? 7.2 : 8.2;
    final smallSize = is58 ? 6.4 : 7.2;
    final format = _receiptFormat(widthMm, order.items.length);

    final totalTax = order.tax;
    final halfTax = totalTax / 2;
    final taxRate = settings.taxEnabled ? settings.taxPercent : 0;
    final halfRate = taxRate / 2;
    final cafeName = _fit(settings.cafeName, chars);
    final address = _wrap(settings.address, chars);
    final phone = settings.phone.trim();
    final gst = settings.gstNumber.trim();
    final orderFrom = order.tableName?.trim().isNotEmpty == true
        ? 'Table ${order.tableName!.trim()}'
        : order.orderType == 'delivery'
            ? 'Delivery'
            : order.orderType == 'takeaway'
                ? 'Take Away'
                : 'Dine In';

    doc.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: _mono, bold: _monoBold),
        build: (_) {
          final widgets = <pw.Widget>[];
          widgets.add(_center(cafeName, fontSize + 2, bold: true));
          widgets.add(_center('The food which makes you happy', smallSize));
          if (phone.isNotEmpty) widgets.add(_center('Phone: $phone', smallSize));
          for (final line in address) widgets.add(_center(line, smallSize));
          if (gst.isNotEmpty) widgets.add(_center('GST: $gst', smallSize));

          widgets.add(_gap(3));
          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_line('Order from: ${_fit(orderFrom, chars)}', fontSize));
          widgets.add(_twoColumn(
            '${Formatters.date(order.createdAt)} ${Formatters.time(order.createdAt)}',
            'Bill #${order.orderNumber}',
            chars,
            fontSize,
          ));
          if (order.tableCustomerLabel?.trim().isNotEmpty == true) {
            widgets.add(_line('Customer: ${_fit(order.tableCustomerLabel!.trim(), chars)}', fontSize));
          }
          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_receiptColumnHeader(chars, fontSize));
          widgets.add(_line(_dash(chars), fontSize));

          for (final item in order.items) {
            widgets.add(_receiptItemLine(item.name, item.quantity.toString(), _money(item.total), chars, fontSize));
          }

          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_summaryLine('Sub Total', _money(order.subtotal), chars, fontSize));
          widgets.add(_summaryLine('Discount', _money(order.discount), chars, fontSize));
          widgets.add(_summaryLine('Net Total', _money(order.subtotal - order.discount), chars, fontSize));
          if (totalTax > 0) {
            widgets.add(_summaryLine('CGST @${_rate(halfRate)}%', _money(halfTax), chars, fontSize));
            widgets.add(_summaryLine('SGST @${_rate(halfRate)}%', _money(halfTax), chars, fontSize));
          }
          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_summaryLine('TOTAL', _money(order.grandTotal), chars, fontSize, bold: true, large: true));
          widgets.add(_summaryLine('Payment mode', order.paymentMethod, chars, fontSize));
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
    final leftWidth = ((chars * .62).floor()).clamp(1, chars - 1);
    final rightWidth = chars - leftWidth;
    return pw.Text(
      _fit(left, leftWidth).padRight(leftWidth) + _fit(right, rightWidth).padLeft(rightWidth),
      maxLines: 1,
      style: pw.TextStyle(font: _mono, fontSize: size),
    );
  }

  pw.Widget _threeColumnHeader(int chars, double size) {
    final itemWidth = ((chars - 10) * .55).floor().clamp(8, chars);
    final remaining = chars - itemWidth;
    final qtyWidth = 4;
    final rateWidth = (remaining - qtyWidth) ~/ 2;
    final amountWidth = remaining - qtyWidth - rateWidth;
    return _line(
      _fit('Particulars', itemWidth).padRight(itemWidth) +
          _fit('Qty', qtyWidth).padLeft(qtyWidth) +
          _fit('Rate', rateWidth).padLeft(rateWidth) +
          _fit('Amount', amountWidth).padLeft(amountWidth),
      size,
    );
  }

  pw.Widget _fourColumn(
    String item,
    String qty,
    String rate,
    String amount,
    int chars,
    double size,
  ) {
    final itemWidth = ((chars - 12) * .52).floor().clamp(8, chars - 12);
    final qtyWidth = 4;
    final rateWidth = 7;
    final amountWidth = chars - itemWidth - qtyWidth - rateWidth;
    return _line(
      _fit(item, itemWidth).padRight(itemWidth) +
          _fit(qty, qtyWidth).padLeft(qtyWidth) +
          _fit(rate, rateWidth).padLeft(rateWidth) +
          _fit(amount, amountWidth).padLeft(amountWidth),
      size,
    );
  }

  pw.Widget _receiptColumnHeader(int chars, double size) {
    final qtyWidth = 5;
    final amountWidth = 11;
    final itemWidth = chars - qtyWidth - amountWidth;
    return _line(
      _fit('ITEM', itemWidth).padRight(itemWidth) +
          _fit('QTY', qtyWidth).padLeft(qtyWidth) +
          _fit('AMT', amountWidth).padLeft(amountWidth),
      size,
    );
  }

  pw.Widget _receiptItemLine(
    String item,
    String qty,
    String amount,
    int chars,
    double size,
  ) {
    final qtyWidth = 5;
    final amountWidth = 11;
    final itemWidth = chars - qtyWidth - amountWidth;
    return _line(
      _fit(item, itemWidth).padRight(itemWidth) +
          _fit(qty, qtyWidth).padLeft(qtyWidth) +
          _fit(amount, amountWidth).padLeft(amountWidth),
      size,
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

  String _dash(int chars) => List.filled(chars, '-').join();

  String _fit(String value, int width) {
    final cleaned = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (cleaned.length <= width) return cleaned;
    if (width <= 1) return cleaned.substring(0, width);
    return cleaned.substring(0, width - 3) + '...';
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

  /// The exact page size used for a receipt with [itemCount] line items on a
  /// [widthMm] roll. Shared by [buildReceiptPdf] (to build the PDF) and
  /// [printReceipt] (to tell the OS print dialog what size that PDF already
  /// is), so the two can never disagree.
  PdfPageFormat _receiptFormat(double widthMm, int itemCount) {
    final pageWidth = widthMm * PdfPageFormat.mm;
    final is58 = widthMm <= 60;
    final fontSize = is58 ? 7.2 : 8.2;
    final lineCount = 24 + itemCount * 2;
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
      format: _receiptFormat(widthMm, order.items.length),
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
      ..writeln('GST: ${settings.gstNumber}')
      ..writeln('Order from: ${order.tableName?.trim().isNotEmpty == true ? order.tableName : order.orderType}')
      ..writeln('Bill #${order.orderNumber}')
      ..writeln('Date: ${Formatters.date(order.createdAt)}')
      ..writeln('Time: ${Formatters.time(order.createdAt)}')
      ..writeln('---');

    for (final item in order.items) {
      buffer.writeln(
        '${item.name}  ${item.quantity}  ${_money(item.total)}',
      );
    }

    buffer
      ..writeln('---')
      ..writeln('Sub Total : ${_money(order.subtotal)}')
      ..writeln('Discount  : ${_money(order.discount)}')
      ..writeln('CGST      : ${_money(order.tax / 2)}')
      ..writeln('SGST      : ${_money(order.tax / 2)}')
      ..writeln('TOTAL     : ${_money(order.grandTotal)}')
      ..writeln('Payment mode: ${order.paymentMethod}')
      ..writeln(settings.receiptFooter)
      ..writeln('Powered by GoogliXLabs');

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
    final qtyWidth = 5;
    final amountWidth = 11;

    List<int> bytes = [];
    final cafeName = _fit(settings.cafeName, chars);
    bytes += generator.text(
      cafeName,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
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
      bytes += generator.text('GST: ${settings.gstNumber.trim()}', styles: const PosStyles(align: PosAlign.center));
    }

    bytes += generator.hr();
    final orderFrom = order.tableName?.trim().isNotEmpty == true
        ? 'Table ${order.tableName!.trim()}'
        : order.orderType == 'delivery'
            ? 'Delivery'
            : order.orderType == 'takeaway'
                ? 'Take Away'
                : 'Dine In';
    bytes += generator.text('Order from: $orderFrom');
    bytes += generator.text(_twoColumnText(
      '${Formatters.date(order.createdAt)} ${Formatters.time(order.createdAt)}',
      'Bill #${order.orderNumber}',
      chars,
    ));
    if (order.tableCustomerLabel?.trim().isNotEmpty == true) {
      bytes += generator.text('Customer: ${_fit(order.tableCustomerLabel!.trim(), chars)}');
    }
    bytes += generator.hr();

    final header = _fit('ITEM', itemWidth).padRight(itemWidth) +
        _fit('QTY', qtyWidth).padLeft(qtyWidth) +
        _fit('AMT', amountWidth).padLeft(amountWidth);
    bytes += generator.text(header);
    bytes += generator.hr();

    for (final item in order.items) {
      final line = _fit(item.name, itemWidth).padRight(itemWidth) +
          _fit(item.quantity.toString(), qtyWidth).padLeft(qtyWidth) +
          _fit(_money(item.total), amountWidth).padLeft(amountWidth);
      bytes += generator.text(line);
    }

    bytes += generator.hr();
    bytes += generator.text(_summaryLineText('Sub Total', _money(order.subtotal), chars));
    bytes += generator.text(_summaryLineText('Discount', _money(order.discount), chars));
    bytes += generator.text(_summaryLineText('Net Total', _money(order.subtotal - order.discount), chars));
    if (order.tax > 0) {
      final halfTax = order.tax / 2;
      final halfRate = (settings.taxEnabled ? settings.taxPercent : 0) / 2;
      bytes += generator.text(_summaryLineText('CGST @${_rate(halfRate)}%', _money(halfTax), chars));
      bytes += generator.text(_summaryLineText('SGST @${_rate(halfRate)}%', _money(halfTax), chars));
    }
    bytes += generator.hr();
    bytes += generator.text(
      _summaryLineText('TOTAL', _money(order.grandTotal), chars),
      styles: const PosStyles(bold: true),
    );
    bytes += generator.text(_summaryLineText('Payment mode', order.paymentMethod, chars));
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
    final bytes = await buildThermalTicketBytes(order, settings, widthMm: widthMm);
    return BluetoothPrinterService().printBytes(bytes);
  }

  String _twoColumnText(String left, String right, int chars) {
    final leftWidth = ((chars * .62).floor()).clamp(1, chars - 1);
    final rightWidth = chars - leftWidth;
    return _fit(left, leftWidth).padRight(leftWidth) + _fit(right, rightWidth).padLeft(rightWidth);
  }

  String _threeColumnHeaderText(int chars) {
    final itemWidth = ((chars - 10) * .55).floor().clamp(8, chars);
    final remaining = chars - itemWidth;
    final qtyWidth = 4;
    final rateWidth = (remaining - qtyWidth) ~/ 2;
    final amountWidth = remaining - qtyWidth - rateWidth;
    return _fit('Particulars', itemWidth).padRight(itemWidth) +
        _fit('Qty', qtyWidth).padLeft(qtyWidth) +
        _fit('Rate', rateWidth).padLeft(rateWidth) +
        _fit('Amount', amountWidth).padLeft(amountWidth);
  }

  String _fourColumnText(String item, String qty, String rate, String amount, int chars) {
    final itemWidth = ((chars - 12) * .52).floor().clamp(8, chars - 12);
    final qtyWidth = 4;
    final rateWidth = 7;
    final amountWidth = chars - itemWidth - qtyWidth - rateWidth;
    return _fit(item, itemWidth).padRight(itemWidth) +
        _fit(qty, qtyWidth).padLeft(qtyWidth) +
        _fit(rate, rateWidth).padLeft(rateWidth) +
        _fit(amount, amountWidth).padLeft(amountWidth);
  }

  String _summaryLineText(String label, String value, int chars) {
    final valueWidth = 10;
    final labelWidth = chars - valueWidth;
    return _fit(label, labelWidth).padRight(labelWidth) + _fit(value, valueWidth).padLeft(valueWidth);
  }
}
