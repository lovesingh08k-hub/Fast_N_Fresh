import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/utils/formatters.dart';
import '../models/misc_models.dart';
import '../models/order.dart';
import 'bluetooth_printer_service.dart';

/// Renders a kitchen-only ticket from the existing Order record.
///
/// This service deliberately has no order/payment/database logic. It is only
/// another output format for the existing order, so the KDS remains the single
/// kitchen workflow and the Order remains the source of truth.
class KotService {
  static const double width55mm = 55;
  static const double width58mm = 58;
  static const double width80mm = 80;

  Future<Uint8List> buildPdf(
    Order order,
    BusinessSettings settings, {
    double widthMm = width80mm,
  }) async {
    final isNarrow = widthMm <= 60;
    final chars = isNarrow ? 30 : 42;
    final font = pw.Font.courier();
    final bold = pw.Font.courierBold();
    final format = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      (130 + order.items.length * 14) * PdfPageFormat.mm,
      marginLeft: 3 * PdfPageFormat.mm,
      marginRight: 3 * PdfPageFormat.mm,
      marginTop: 3 * PdfPageFormat.mm,
      marginBottom: 3 * PdfPageFormat.mm,
    );

    final orderFrom = order.tableNumber != null
        ? 'Table No: ${order.tableNumber}'
        : order.tableName?.trim().isNotEmpty == true
            ? 'Table No: ${order.tableName!.trim().replaceFirst(RegExp(r'^Table\\s*', caseSensitive: false), '')}'
            : order.orderType == 'delivery'
                ? 'Delivery'
                : order.orderType == 'takeaway'
                    ? 'Take Away'
                    : 'Dine In';

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _center(settings.cafeName, chars, font, bold, 11, true),
            _center('KITCHEN ORDER TICKET', chars, font, bold, 10, true),
            _line(chars, font),
            _text('Bill No: #${order.orderNumber}', font, 8),
            _text('Order from: $orderFrom', font, 8),
            if (order.printCustomerName != null)
              _text('Customer: ${order.printCustomerName!}', font, 8),
            _text('${Formatters.shortDate(order.createdAt)}, ${Formatters.time(order.createdAt)}', font, 8),
            _line(chars, font),
            _text(
              _fit('QTY', 5).padRight(5) +
                  _fit('ITEM', chars - 5),
              font,
              8,
              true,
            ),
            _line(chars, font),
            for (final item in order.items)
              ..._itemLines(item.quantity, _kotName(item.name, item.note), chars)
                  .map((line) => _text(line, font, 8)),
            if (order.notes?.trim().isNotEmpty == true) ...[
              _line(chars, font),
              _text('NOTE:', font, 8, true),
              ..._wrap(order.notes!.trim(), chars).map((line) => _text(line, font, 8)),
            ],
            _line(chars, font),
          ],
        ),
      ),
    );
    return doc.save();
  }

  Future<Uint8List> buildKotPdf(
    Order order,
    BusinessSettings settings,
    KotTicket ticket, {
    double widthMm = width80mm,
  }) async {
    final isNarrow = widthMm <= 60;
    final chars = isNarrow ? 30 : 42;
    final font = pw.Font.courier();
    final bold = pw.Font.courierBold();
    final format = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      (105 + ticket.items.length * 14) * PdfPageFormat.mm,
      marginLeft: 3 * PdfPageFormat.mm,
      marginRight: 3 * PdfPageFormat.mm,
      marginTop: 3 * PdfPageFormat.mm,
      marginBottom: 3 * PdfPageFormat.mm,
    );

    final source = order.tableNumber != null
        ? 'Table No: ${order.tableNumber}'
        : order.tableName?.trim().isNotEmpty == true
            ? 'Table No: ${order.tableName!.trim().replaceFirst(RegExp(r'^Table\\s*', caseSensitive: false), '')}'
            : order.orderType == 'delivery'
                ? 'Delivery'
                : order.orderType == 'takeaway'
                    ? 'Take Away'
                    : 'Dine In';

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _center(settings.cafeName, chars, font, bold, 11, true),
            _center(
              'KITCHEN ORDER TICKET  #${ticket.kotNumber}',
              chars,
              font,
              bold,
              10,
              true,
            ),
            _line(chars, font),
            _text('Bill No: #${order.orderNumber}', font, 8),
            _text('Order from: $source', font, 8),
            if (order.printCustomerName != null)
              _text(
                'Customer: ${order.printCustomerName!}',
                font,
                8,
              ),
            _text(
              '${Formatters.shortDate(ticket.createdAt)}, ${Formatters.time(ticket.createdAt)}',
              font,
              8,
            ),
            _line(chars, font),
            _text(
              _fit('QTY', 5).padRight(5) + _fit('ITEM', chars - 5),
              font,
              8,
              true,
            ),
            _line(chars, font),
            for (final item in ticket.items)
              ..._itemLines(item.quantity, _kotName(item.name, item.note), chars)
                  .map((line) => _text(line, font, 8)),
            if (order.notes?.trim().isNotEmpty == true) ...[
              _line(chars, font),
              _text('NOTE:', font, 8, true),
              ..._wrap(order.notes!.trim(), chars).map(
                (line) => _text(line, font, 8),
              ),
            ],
            _line(chars, font),
          ],
        ),
      ),
    );
    return doc.save();
  }

  Future<void> printKotPdf(Order order, BusinessSettings settings, KotTicket ticket, {double widthMm = width80mm}) async {
    final bytes = await buildKotPdf(order, settings, ticket, widthMm: widthMm);
    await Printing.layoutPdf(onLayout: (_) async => bytes, format: PdfPageFormat(widthMm * PdfPageFormat.mm, (105 + ticket.items.length * 14) * PdfPageFormat.mm), dynamicLayout: false);
  }

  Future<List<int>> buildBluetoothKot(Order order, BusinessSettings settings, KotTicket ticket, {double widthMm = width80mm}) async {
    final isNarrow = widthMm <= 60;
    final profile = await CapabilityProfile.load();
    final generator = Generator(isNarrow ? PaperSize.mm58 : PaperSize.mm80, profile);
    final chars = isNarrow ? 30 : 48;
    final source = order.tableNumber != null
        ? 'Table No: ${order.tableNumber}'
        : order.tableName?.trim().isNotEmpty == true
            ? 'Table No: ${order.tableName!.trim().replaceFirst(RegExp(r'^Table\\s*', caseSensitive: false), '')}'
            : order.orderType == 'delivery'
                ? 'Delivery'
                : order.orderType == 'takeaway'
                    ? 'Take Away'
                    : 'Dine In';
    List<int> bytes = [];
    final cafeName = _fit(settings.cafeName, chars);
    bytes += generator.text(cafeName, styles: _cafeNameStyle(cafeName, isNarrow));
    bytes += generator.text('KITCHEN ORDER TICKET #${ticket.kotNumber}', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr();
    bytes += generator.text('Bill No: #${order.orderNumber}');
    bytes += generator.text('Order from: $source');
    if (order.printCustomerName != null) bytes += generator.text('Customer: ${order.printCustomerName!}');
    bytes += generator.text('${Formatters.shortDate(ticket.createdAt)}, ${Formatters.time(ticket.createdAt)}');
    bytes += generator.hr();
    for (final item in ticket.items) {
      for (final line in _itemLines(item.quantity, _kotName(item.name, item.note), chars)) {
        bytes += generator.text(line);
      }
    }
    bytes += generator.hr();
    bytes += generator.feed(1);
    bytes += generator.cut();
    return bytes;
  }

  Future<bool> printKotViaBluetooth(Order order, BusinessSettings settings, KotTicket ticket, {double widthMm = width80mm}) async {
    // The web app prints through the browser print dialog instead.
    if (kIsWeb) {
      await printKotPdf(order, settings, ticket, widthMm: widthMm);
      return true;
    }
    final bytes = await buildBluetoothKot(order, settings, ticket, widthMm: widthMm);
    return BluetoothPrinterService().printBytes(bytes);
  }

  Future<void> printPdf(
    Order order,
    BusinessSettings settings, {
    double widthMm = width80mm,
  }) async {
    final bytes = await buildPdf(order, settings, widthMm: widthMm);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: PdfPageFormat(
        widthMm * PdfPageFormat.mm,
        (130 + order.items.length * 14) * PdfPageFormat.mm,
        marginLeft: 3 * PdfPageFormat.mm,
        marginRight: 3 * PdfPageFormat.mm,
        marginTop: 3 * PdfPageFormat.mm,
        marginBottom: 3 * PdfPageFormat.mm,
      ),
      dynamicLayout: false,
    );
  }

  Future<List<int>> buildBluetoothTicket(
    Order order,
    BusinessSettings settings, {
    double widthMm = width80mm,
  }) async {
    final isNarrow = widthMm <= 60;
    final profile = await CapabilityProfile.load();
    final generator = Generator(isNarrow ? PaperSize.mm58 : PaperSize.mm80, profile);
    final chars = isNarrow ? 30 : 48;

    final orderFrom = order.tableNumber != null
        ? 'Table No: ${order.tableNumber}'
        : order.tableName?.trim().isNotEmpty == true
            ? 'Table No: ${order.tableName!.trim().replaceFirst(RegExp(r'^Table\\s*', caseSensitive: false), '')}'
            : order.orderType == 'delivery'
                ? 'Delivery'
                : order.orderType == 'takeaway'
                    ? 'Take Away'
                    : 'Dine In';

    List<int> bytes = [];
    final cafeName = _fit(settings.cafeName, chars);
    bytes += generator.text(cafeName, styles: _cafeNameStyle(cafeName, isNarrow));
    bytes += generator.text('KITCHEN ORDER TICKET', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr();
    bytes += generator.text('Bill No: #${order.orderNumber}');
    bytes += generator.text('Order from: $orderFrom');
    if (order.printCustomerName != null) {
      bytes += generator.text('Customer: ${order.printCustomerName!}');
    }
    bytes += generator.text('${Formatters.shortDate(order.createdAt)}, ${Formatters.time(order.createdAt)}');
    bytes += generator.hr();
    bytes += generator.text(_fit('QTY', 5).padRight(5) + _fit('ITEM', chars - 5));
    bytes += generator.hr();

    for (final item in order.items) {
      for (final line in _itemLines(item.quantity, _kotName(item.name, item.note), chars)) {
        bytes += generator.text(line);
      }
    }

    if (order.notes?.trim().isNotEmpty == true) {
      bytes += generator.hr();
      bytes += generator.text('NOTE:', styles: const PosStyles(bold: true));
      for (final line in _wrap(order.notes!.trim(), chars)) {
        bytes += generator.text(line);
      }
    }
    bytes += generator.hr();
    bytes += generator.feed(1);
    bytes += generator.cut();
    return bytes;
  }

  Future<bool> printViaBluetooth(
    Order order,
    BusinessSettings settings, {
    double widthMm = width80mm,
  }) async {
    if (kIsWeb) {
      await printPdf(order, settings, widthMm: widthMm);
      return true;
    }
    final bytes = await buildBluetoothTicket(order, settings, widthMm: widthMm);
    return BluetoothPrinterService().printBytes(bytes);
  }

  pw.Widget _center(String text, int chars, pw.Font font, pw.Font bold, double size, bool isBold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Text(
        _fit(text, chars),
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: isBold ? bold : font, fontSize: size),
      ),
    );
  }

  pw.Widget _text(String text, pw.Font font, double size, [bool isBold = false]) =>
      pw.Text(text, maxLines: 2, style: pw.TextStyle(font: isBold ? pw.Font.courierBold() : font, fontSize: size));

  pw.Widget _line(int chars, pw.Font font) =>
      pw.Text(List.filled(chars, '-').join(), style: pw.TextStyle(font: font, fontSize: 8));

  String _fit(String value, int width) {
    final cleaned = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (cleaned.length <= width) return cleaned;
    if (width <= 1) return cleaned.substring(0, width);
    return '${cleaned.substring(0, width - 3)}...';
  }

  /// Item name with its kitchen note, e.g. "Paneer Tikka (less spicy)".
  static String _kotName(String name, String? note) =>
      note == null || note.trim().isEmpty ? name : '$name (${note.trim()})';

  /// "QTY  ITEM" rows with the full item name: long names wrap onto
  /// following lines (indented under ITEM) instead of being cut with "...".
  List<String> _itemLines(int quantity, String name, int chars) {
    const qtyWidth = 5;
    final nameLines = _wrap(name, chars - qtyWidth);
    if (nameLines.isEmpty) nameLines.add('');
    return [
      _fit(quantity.toString(), qtyWidth).padRight(qtyWidth) + nameLines.first,
      for (final line in nameLines.skip(1)) ''.padRight(qtyWidth) + line,
    ];
  }

  /// Double-width text uses two columns per character, so the cafe name
  /// only prints double-wide when it fits on one line (58mm Font A = 32
  /// columns, 80mm = 48); otherwise it stays tall but normal width instead
  /// of spilling its last letter onto a second line.
  PosStyles _cafeNameStyle(String name, bool isNarrow) {
    final fitsDoubleWidth = name.length * 2 <= (isNarrow ? 32 : 48);
    return PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: fitsDoubleWidth ? PosTextSize.size2 : PosTextSize.size1,
    );
  }

  List<String> _wrap(String value, int width) {
    final result = <String>[];
    for (var line in value.replaceAll('\r', '').split('\n')) {
      line = line.trim();
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
}
