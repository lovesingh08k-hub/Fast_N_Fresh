import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
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

    final orderFrom = order.tableName?.trim().isNotEmpty == true
        ? 'Table ${order.tableName!.trim()}'
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
            if (order.tableCustomerLabel?.trim().isNotEmpty == true)
              _text('Customer: ${order.tableCustomerLabel!.trim()}', font, 8),
            _text('${Formatters.date(order.createdAt)}, ${Formatters.time(order.createdAt)}', font, 8),
            _line(chars, font),
            _text(
              _fit('QTY', 5).padRight(5) +
                  _fit('ITEM', chars - 5),
              font,
              8,
              true,
            ),
            _line(chars, font),
            ...order.items.map(
              (item) => _text(
                _fit(item.quantity.toString(), 5).padRight(5) +
                    _fit(item.name, chars - 5),
                font,
                8,
              ),
            ),
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

    final source = order.tableName?.trim().isNotEmpty == true
        ? 'Table ${order.tableName!.trim()}'
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
            if (order.tableCustomerLabel?.trim().isNotEmpty == true)
              _text(
                'Customer: ${order.tableCustomerLabel!.trim()}',
                font,
                8,
              ),
            _text(
              '${Formatters.date(ticket.createdAt)}, ${Formatters.time(ticket.createdAt)}',
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
            ...ticket.items.map(
              (item) => _text(
                _fit(item.quantity.toString(), 5).padRight(5) +
                    _fit(item.name, chars - 5),
                font,
                8,
              ),
            ),
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
    final source = order.tableName?.trim().isNotEmpty == true ? 'Table ${order.tableName!.trim()}' : order.orderType == 'delivery' ? 'Delivery' : order.orderType == 'takeaway' ? 'Take Away' : 'Dine In';
    List<int> bytes = [];
    bytes += generator.text(_fit(settings.cafeName, chars), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.text('KITCHEN ORDER TICKET #${ticket.kotNumber}', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr();
    bytes += generator.text('Bill No: #${order.orderNumber}');
    bytes += generator.text('Order from: $source');
    if (order.tableCustomerLabel?.trim().isNotEmpty == true) bytes += generator.text('Customer: ${order.tableCustomerLabel!.trim()}');
    bytes += generator.text('${Formatters.date(ticket.createdAt)}, ${Formatters.time(ticket.createdAt)}');
    bytes += generator.hr();
    for (final item in ticket.items) bytes += generator.text(_fit(item.quantity.toString(), 5).padRight(5) + _fit(item.name, chars - 5));
    bytes += generator.hr();
    bytes += generator.feed(1);
    bytes += generator.cut();
    return bytes;
  }

  Future<bool> printKotViaBluetooth(Order order, BusinessSettings settings, KotTicket ticket, {double widthMm = width80mm}) async {
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

    final orderFrom = order.tableName?.trim().isNotEmpty == true
        ? 'Table ${order.tableName!.trim()}'
        : order.orderType == 'delivery'
            ? 'Delivery'
            : order.orderType == 'takeaway'
                ? 'Take Away'
                : 'Dine In';

    List<int> bytes = [];
    bytes += generator.text(
      _fit(settings.cafeName, chars),
      styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
    );
    bytes += generator.text('KITCHEN ORDER TICKET', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr();
    bytes += generator.text('Bill No: #${order.orderNumber}');
    bytes += generator.text('Order from: $orderFrom');
    if (order.tableCustomerLabel?.trim().isNotEmpty == true) {
      bytes += generator.text('Customer: ${order.tableCustomerLabel!.trim()}');
    }
    bytes += generator.text('${Formatters.date(order.createdAt)}, ${Formatters.time(order.createdAt)}');
    bytes += generator.hr();
    bytes += generator.text(_fit('QTY', 5).padRight(5) + _fit('ITEM', chars - 5));
    bytes += generator.hr();

    for (final item in order.items) {
      bytes += generator.text(
        _fit(item.quantity.toString(), 5).padRight(5) +
            _fit(item.name, chars - 5),
      );
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
