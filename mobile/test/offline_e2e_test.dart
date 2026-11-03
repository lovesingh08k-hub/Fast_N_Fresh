// End-to-end offline test against a real backend. Skipped unless E2E_ADMIN is
// given; run it with a throwaway server:
//   flutter test test/offline_e2e_test.dart
//     --dart-define=API_BASE_URL=http://127.0.0.1:5310/api
//     --dart-define=E2E_ADMIN=admin --dart-define=E2E_PASSWORD=pass1234
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwp_pos/core/network/dio_client.dart';
import 'package:pwp_pos/core/network/token_storage.dart';
import 'package:pwp_pos/core/offline/offline_engine.dart';
import 'package:pwp_pos/models/cart_item.dart';
import 'package:pwp_pos/models/product.dart';
import 'package:pwp_pos/services/customer_service.dart';
import 'package:pwp_pos/services/order_service.dart';
import 'package:pwp_pos/services/table_service.dart';

const _admin = String.fromEnvironment('E2E_ADMIN');
const _password = String.fromEnvironment('E2E_PASSWORD');

class _Passthrough extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a day without internet ends up exactly right on the server', () async {
    HttpOverrides.global = _Passthrough();
    FlutterSecureStorage.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('offline_e2e');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );

    final dio = DioClient.instance.dio;
    final engine = OfflineEngine.instance;
    final login = await dio.post('/auth/login', data: {'identifier': _admin, 'password': _password});
    final session = login.data['data'] as Map<String, dynamic>;
    await TokenStorage.instance.saveToken(session['token'] as String);
    await TokenStorage.instance.saveUserJson(jsonEncode(session['user']));

    // Nothing here goes through the engine: the server's own answer.
    final direct = Options(extra: {'offlineBypass': true});
    Future<Map<String, dynamic>> server(String path) async => ((await dio.get(path, options: direct)).data as Map).cast<String, dynamic>();

    await engine.init(dio);
    await engine.refreshCaches();

    final orders = OrderService();
    final tables = TableService();
    final customers = CustomerService();
    final products = ((await server('/products?limit=100'))['data'] as List).cast<Map>();
    Product product(Map raw) => Product(id: '${raw['_id']}', name: '${raw['name']}', categoryId: '', sellingPrice: (raw['sellingPrice'] as num).toDouble(), taxRate: (raw['taxRate'] as num?)?.toDouble());
    final plain = products.where((p) => p['trackInventory'] != true).take(6).map(product).toList();
    final tracked = products.firstWhere((p) => p['trackInventory'] == true);
    final allTables = ((await server('/tables'))['data'] as List).cast<Map>().where((t) => t['openOrderCount'] == 0).toList();
    final customer = ((await server('/customers?limit=5'))['data'] as List).cast<Map>().last;
    final stockBefore = ((await server('/products/${tracked['_id']}'))['data'] as Map)['stock'] as num;
    final dueBefore = (((await server('/customers/${customer['_id']}'))['data'] as Map)['customer'] as Map)['outstandingBalance'] as num;

    // A running order on the server from before the internet went away.
    final runningTable = '${allTables[0]['_id']}';
    final running = await tables.startOrder(runningTable, tableCustomerLabel: 'From before');
    await orders.updateOpenOrderItems(running.id, items: [CartItem(product: plain[0], quantity: 2)], discount: 0);
    await tables.getDetail(runningTable);

    final conflictTable = '${allTables[3]['_id']}';
    final conflict = await _serverOrder(dio, direct, conflictTable, plain[1]);
    await tables.getDetail(conflictTable);

    // Online quotes, to compare with the same carts offline.
    final carts = [
      for (var i = 0; i < 6; i++) [CartItem(product: plain[i], quantity: i + 1), CartItem(product: plain[(i + 1) % 6], quantity: 2)],
    ];
    const adjustments = <Map<String, dynamic>>[
      {},
      {'discountType': 'flat', 'discountValue': 37},
      {'discountType': 'percent', 'discountValue': 12.5},
    ];
    final online = [];
    for (final type in const ['dine_in', 'takeaway', 'delivery']) {
      for (final cart in carts) {
        for (final adjust in adjustments) {
          online.add((await orders.quote(items: cart, orderType: type, adjust: adjust)).grandTotal);
        }
      }
    }

    // ----------------------------------------------------------- OFFLINE
    engine.holdOffline = true;
    engine.markOffline();
    expect(engine.isOffline, isTrue);

    var k = 0;
    for (final type in const ['dine_in', 'takeaway', 'delivery']) {
      for (final cart in carts) {
        for (final adjust in adjustments) {
          expect((await orders.quote(items: cart, orderType: type, adjust: adjust)).grandTotal, online[k++], reason: '$type $adjust');
        }
      }
    }

    // Menu, tables and customers still load.
    expect(((await dio.get('/products', queryParameters: {'limit': 200})).data['data'] as List), isNotEmpty);
    expect(await tables.list(), isNotEmpty);
    final found = await customers.list(search: '${customer['phone']}');
    expect(found.single.id, '${customer['_id']}');

    // Counter bills, every way of paying.
    final cart = [CartItem(product: plain[1], quantity: 2), CartItem(product: plain[2])];
    final cash = await orders.createOrder(items: cart, discount: 0, paymentMethod: 'CASH', amountReceived: 5000, clientRequestId: 'e2e-cash-${dir.path.hashCode}');
    expect(cash.isOfflinePending, isTrue);
    expect(cash.invoiceNumber, startsWith('OFF-'));
    expect(cash.status, 'completed');
    final again = await orders.createOrder(items: cart, discount: 0, paymentMethod: 'CASH', amountReceived: 5000, clientRequestId: 'e2e-cash-${dir.path.hashCode}');
    expect(again.id, cash.id, reason: 'double tap');
    final upi = await orders.createOrder(items: cart, discount: 0, paymentMethod: 'UPI', upiReference: 'UTR-${dir.path.hashCode}', clientRequestId: 'e2e-upi-${dir.path.hashCode}');
    final card = await orders.createOrder(items: cart, discount: 0, paymentMethod: 'CARD', clientRequestId: 'e2e-card-${dir.path.hashCode}', extra: const {'cardReference': 'C1'});
    final swiggy = await orders.createOrder(items: cart, discount: 0, paymentMethod: 'ONLINE', orderType: 'delivery', deliveryInfo: const {'address': 'MG Road', 'phone': '999'}, clientRequestId: 'e2e-online-${dir.path.hashCode}', extra: const {'onlinePlatform': 'Swiggy'});
    final half = (cash.grandTotal / 2).floorToDouble();
    final mixed = await orders.createOrder(items: cart, discount: 0, paymentMethod: 'MIXED', cashPortion: half, upiPortion: cash.grandTotal - half, upiReference: 'M-${dir.path.hashCode}', clientRequestId: 'e2e-mixed-${dir.path.hashCode}');
    final trackedBill = await orders.createOrder(items: [CartItem(product: product(tracked), quantity: 3)], discount: 0, paymentMethod: 'CASH', clientRequestId: 'e2e-stock-${dir.path.hashCode}');
    final credit = await orders.createOrder(items: cart, discount: 0, paymentMethod: 'CREDIT', customerId: '${customer['_id']}', clientRequestId: 'e2e-credit-${dir.path.hashCode}');

    // Same refusals as the server.
    await expectLater(orders.createOrder(items: cart, discount: 0, paymentMethod: 'CREDIT'), throwsA(anything));
    await expectLater(orders.createOrder(items: cart, discount: 0, paymentMethod: 'UPI'), throwsA(anything));
    await expectLater(orders.createOrder(items: cart, discount: 0, paymentMethod: 'CASH', amountReceived: 1), throwsA(anything));

    // A new customer on credit.
    final phone = '91${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final newCustomer = await customers.create(name: 'Offline Guest', phone: phone);
    expect(newCustomer.id, startsWith('local-'));
    await expectLater(customers.create(name: 'Twin', phone: phone), throwsA(anything));
    final newCredit = await orders.createOrder(items: cart, discount: 0, paymentMethod: 'CREDIT', customerId: newCustomer.id, clientRequestId: 'e2e-newcredit-${dir.path.hashCode}');

    // A table: open, add, KOT, add more, KOT again, pay.
    final tableA = '${allTables[1]['_id']}';
    var tab = await tables.startOrder(tableA);
    expect(tab.id, startsWith('local-'));
    expect(tab.tableCustomerLabel, 'Customer 1');
    tab = await orders.updateOpenOrderItems(tab.id, items: [CartItem(product: plain[3], quantity: 2)], discount: 0);
    expect(tab.grandTotal, greaterThan(0));
    final kot1 = await orders.sendKot(tab.id);
    expect(kot1.kots.single.items.single.quantity, 2);
    tab = await orders.updateOpenOrderItems(tab.id, items: [CartItem(product: plain[3], quantity: 3), CartItem(product: plain[4])], discount: 0);
    final kot2 = await orders.sendKot(tab.id);
    expect(kot2.kots.last.items.map((i) => i.quantity).toList(), [1, 1], reason: 'only new items');
    expect((await tables.list()).firstWhere((t) => t.id == tableA).isOccupied, isTrue);
    final tabPaid = await orders.checkoutOrder(tab.id, paymentMethod: 'CASH');
    expect(tabPaid.status, 'completed');
    expect((await tables.list()).firstWhere((t) => t.id == tableA).isOccupied, isFalse);

    // A table left running: must appear on the server as a running order.
    final tableB = '${allTables[2]['_id']}';
    var left = await tables.startOrder(tableB, tableCustomerLabel: 'Still eating');
    left = await orders.updateOpenOrderItems(left.id, items: [CartItem(product: plain[5], quantity: 2)], discount: 0);
    await orders.sendKot(left.id);

    // An order opened and cancelled: must leave no trace.
    final cancelled = await tables.startOrder(tableB, tableCustomerLabel: 'Changed mind');
    await orders.cancelOpenOrder(cancelled.id);

    // The running server order: more items, then paid.
    final shown = (await tables.getDetail(runningTable)).$2;
    expect(shown.map((o) => o.id), contains(running.id));
    final carried = await orders.updateOpenOrderItems(running.id, items: [CartItem(product: plain[0], quantity: 3)], discount: 0);
    expect(carried.items.single.quantity, 3);
    final carriedPaid = await orders.checkoutOrder(running.id, paymentMethod: 'UPI', upiReference: 'R-${dir.path.hashCode}');
    expect(carriedPaid.status, 'completed');
    expect((await tables.getDetail(runningTable)).$2, isEmpty);

    // A server order paid on another device meanwhile: a conflict to show.
    await orders.updateOpenOrderItems(conflict, items: [CartItem(product: plain[1], quantity: 5)], discount: 0);
    final conflictPaid = await orders.checkoutOrder(conflict, paymentMethod: 'CASH');
    await dio.post('/orders/$conflict/checkout', data: {'paymentMethod': 'CARD'}, options: direct);

    // Bill history and dashboard include all of it.
    final today = await orders.list(limit: 100);
    expect(today.map((o) => o.id), containsAll([cash.id, upi.id, credit.id, tabPaid.id]));
    final dashboard = (await dio.get('/dashboard')).data['data']['today'] as Map;
    final serverToday = ((await server('/dashboard'))['data'] as Map)['today'] as Map;
    expect((dashboard['sales'] as num) > (serverToday['sales'] as num), isTrue);

    // The phone restarts: nothing is lost.
    final waiting = engine.pendingCount;
    engine.setScope('other_outlet');
    expect((await orders.list(limit: 100)).where((o) => o.id == cash.id), isEmpty, reason: 'another outlet sees none of it');
    engine.setScope('cafe_main');
    await engine.loaded;
    expect(engine.pendingCount, waiting);

    // ------------------------------------------------------------ ONLINE
    engine.holdOffline = false;
    final before = await server('/orders?limit=1');
    final countBefore = (before['pagination'] as Map)['total'] as int;
    engine.markOnline();
    for (var i = 0; i < 100 && (engine.isSyncing || engine.pendingCount > 1); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final left2 = engine.pendingOrders;
    expect(left2.length, 1, reason: left2.map((o) => o['_sync']).toString());
    expect((left2.single['_sync'] as Map)['state'], 'failed');
    expect('${(left2.single['_sync'] as Map)['error']}', contains('another device'));
    expect(left2.single['grandTotal'], conflictPaid.grandTotal);

    // New records: 8 counter bills + the table bill + the running order.
    final countAfter = ((await server('/orders?limit=1'))['pagination'] as Map)['total'] as int;
    expect(countAfter - countBefore, 10, reason: 'bills and running order, no doubles');

    // Each bill kept its amount, and got a real number.
    for (final bill in [cash, upi, card, swiggy, mixed, trackedBill, credit, newCredit, tabPaid]) {
      final real = await orders.getById(bill.id);
      expect(real.id, isNot(startsWith('local-')), reason: 'local id now leads to the server order');
      expect(real.grandTotal, bill.grandTotal);
      expect(real.status, 'completed');
      expect(real.invoiceNumber, isNot(startsWith('OFF-')));
    }
    expect((await orders.getById(card.id)).paymentMethod, 'CARD');
    expect((await orders.getById(swiggy.id)).onlinePlatform, 'Swiggy');
    expect((await orders.getById(tabPaid.id)).items.map((i) => i.quantity), containsAll([3, 1]));

    // Stock and udhar moved.
    expect(((await server('/products/${tracked['_id']}'))['data'] as Map)['stock'], stockBefore - 3);
    final due = (((await server('/customers/${customer['_id']}'))['data'] as Map)['customer'] as Map)['outstandingBalance'] as num;
    expect((due - dueBefore - credit.grandTotal).abs() < 0.01, isTrue);
    final made = ((await server('/customers?search=$phone'))['data'] as List).single as Map;
    expect(made['outstandingBalance'], newCredit.grandTotal);

    // The running order reached the server as still running.
    final rows = ((await server('/tables/$tableB'))['data'] as Map)['openOrders'] as List;
    final still = rows.singleWhere((o) => o['tableCustomerLabel'] == 'Still eating') as Map;
    expect(still['status'], 'open');
    expect((still['items'] as List).single['kotSentQuantity'], 2);
    expect(rows.where((o) => o['tableCustomerLabel'] == 'Changed mind'), isEmpty);
    // Carrying on with the local id reaches that same order.
    final next = await orders.updateOpenOrderItems(left.id, items: [CartItem(product: plain[5], quantity: 4)], discount: 0);
    expect(next.id, still['_id']);
    expect((await orders.checkoutOrder(left.id, paymentMethod: 'CASH')).status, 'completed');

    // The server order carried on offline was applied, then paid.
    final applied = await orders.getById(running.id);
    expect(applied.status, 'completed');
    expect(applied.items.single.quantity, 3);
    expect(applied.paymentMethod, 'UPI');

    // Sending again changes nothing.
    await engine.retryFailed();
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(((await server('/orders?limit=1'))['pagination'] as Map)['total'], countAfter + 0);
    await dir.delete(recursive: true).catchError((_) => dir);
  }, skip: _admin.isEmpty ? 'needs a test server' : false, timeout: const Timeout(Duration(minutes: 4)));
}

Future<String> _serverOrder(Dio dio, Options direct, String tableId, Product product) async {
  final open = await dio.post('/tables/$tableId/orders', data: {'tableCustomerLabel': 'Conflict'}, options: direct);
  final id = '${open.data['data']['_id']}';
  await dio.put('/orders/$id/items', data: {'items': [{'productId': product.id, 'quantity': 1}]}, options: direct);
  return id;
}
