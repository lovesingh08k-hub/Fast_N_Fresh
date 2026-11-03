import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../network/api_config.dart';
import '../network/token_storage.dart';
import 'blob_store.dart';
import 'local_bill.dart';

/// Keeps the app working without internet.
///
/// It sits inside the network layer ([DioClient]) and answers API calls itself
/// when the server cannot be reached, in the same shape as the server. So the
/// screens need no special offline code: billing, tables, counters and KOTs
/// work as usual, and when the connection is back everything is sent to the
/// server (see [sync]).
///
/// - Reads are answered from the last server response, stored on the device.
/// - Bills and running orders are stored on the device with an id starting
///   with `local-`. They stay on this device until they are synced.
/// - A running order that came from the server can be carried on offline: a
///   local copy remembers its `serverId` and is applied to it later.
///
/// A bill is never dropped: what cannot be sent stays listed on the Offline
/// Sync screen with the reason, until it goes through.
class OfflineEngine extends ChangeNotifier {
  OfflineEngine._();

  static final OfflineEngine instance = OfflineEngine._();

  static const _idPrefix = 'local-';
  static const _maxCacheEntries = 60;
  static const _maxCacheChars = 600 * 1024;
  static const _pingEvery = Duration(seconds: 15);
  static const _syncEvery = Duration(seconds: 30);

  /// Set by [init]. Until then every request simply goes to the network
  /// (widget tests have no storage or connectivity plugins).
  bool enabled = false;

  /// True while the server cannot be reached.
  bool isOffline = false;

  /// Tests stay offline with a reachable server.
  @visibleForTesting
  bool holdOffline = false;

  bool isSyncing = false;
  DateTime? lastSyncAt;

  Dio? _dio;
  final BlobStore _blobs = BlobStore();
  String _scope = 'cafe_main';
  Future<void>? _loading;
  String _deviceTag = '';
  int _seq = 0;

  Map<String, Map<String, dynamic>> _orders = {};
  Map<String, Map<String, dynamic>> _customers = {};
  Map<String, String> _idMap = {};
  Map<String, Map<String, dynamic>> _catalog = {};
  Map<String, Map<String, dynamic>> _directory = {};
  Map<String, Map<String, dynamic>> _knownOrders = {};
  Map<String, int> _cacheIndex = {};
  int _directoryAt = 0;
  String? _user;
  Map<String, dynamic>? _settingsMemo;
  final Map<String, int> _writtenHash = {};

  Timer? _pingTimer;
  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  // -------------------------------------------------------------------
  // STATE FOR THE UI
  // -------------------------------------------------------------------

  /// Local records still waiting for the server, oldest first.
  List<Map<String, dynamic>> get pendingOrders {
    // An order opened with nothing on it yet has nothing to send.
    final list = _orders.values.where((o) => !(_isActive(o) && o['serverId'] == null && _itemCount(o) == 0)).toList();
    list.sort((a, b) => '${a['createdAt']}'.compareTo('${b['createdAt']}'));
    return list;
  }

  int get pendingCount => pendingOrders.length + _customers.length;

  int get failedCount => pendingOrders.where((o) => _sync(o)['state'] == 'failed').length;

  bool get hasPending => pendingCount > 0;

  /// Bills paid on this device that the server has not seen yet.
  int get unsyncedBills => pendingOrders.where((o) => o['status'] == 'completed').length;

  Map<String, dynamic> _sync(Map<String, dynamic> order) =>
      (order['_sync'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

  // -------------------------------------------------------------------
  // START-UP
  // -------------------------------------------------------------------

  Future<void> init(Dio dio) async {
    _dio = dio;
    enabled = true;
    try {
      _deviceTag = await _blobs.read('device') ?? '';
      if (_deviceTag.isEmpty) {
        _deviceTag = const Uuid().v4().substring(0, 4).toUpperCase();
        await _blobs.write('device', _deviceTag);
      }
    } catch (_) {
      _deviceTag = 'A1';
    }
    await _ensureLoaded();
    try {
      _connectivity = Connectivity().onConnectivityChanged.listen((results) {
        if (results.contains(ConnectivityResult.none)) {
          markOffline();
        } else {
          unawaited(_ping());
        }
      });
      final now = await Connectivity().checkConnectivity();
      if (now.contains(ConnectivityResult.none)) markOffline();
    } catch (_) {
      // Connection changes are also noticed from failing requests.
    }
    _syncTimer = Timer.periodic(_syncEvery, (_) {
      if (!isOffline && hasPending) unawaited(sync());
    });
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _syncTimer?.cancel();
    _connectivity?.cancel();
    super.dispose();
  }

  /// Which business and outlet the app works in. Each has its own records.
  void setScope(String scope) {
    final value = scope.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (value == _scope) return;
    _scope = value;
    _settingsMemo = null;
    _loading = null;
    if (enabled) unawaited(_ensureLoaded());
  }

  /// Who is logged in: what the server shows depends on the person, so one
  /// staff member must never be shown what was stored for the owner.
  void setUser(String? id) {
    _user = id;
    _settingsMemo = null;
  }

  Future<void> _ensureLoaded() => _loading ??= _load();

  /// Finished loading the current scope from disk.
  @visibleForTesting
  Future<void> get loaded => _ensureLoaded();

  String _file(String name) => '$_scope.$name.json';

  Future<Map<String, Map<String, dynamic>>> _readMap(String name) async {
    try {
      final raw = await _blobs.read(_file(name));
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _load() async {
    _orders = await _readMap('orders');
    _customers = await _readMap('customers');
    _catalog = await _readMap('catalog');
    _directory = await _readMap('directory');
    _knownOrders = await _readMap('known');
    try {
      final raw = await _blobs.read(_file('meta'));
      final meta = raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      _seq = (meta['seq'] as num?)?.toInt() ?? 0;
      _idMap = (meta['ids'] as Map?)?.cast<String, String>() ?? {};
      _cacheIndex = (meta['cache'] as Map?)?.map((k, v) => MapEntry('$k', (v as num).toInt())) ?? {};
      _directoryAt = (meta['directoryAt'] as num?)?.toInt() ?? 0;
    } catch (_) {
      _seq = 0;
      _idMap = {};
      _cacheIndex = {};
    }
    notifyListeners();
    if (!isOffline && hasPending) unawaited(sync());
  }

  /// Writes [value] unless the same text is already on disk.
  Future<void> _write(String name, String value) async {
    final hash = value.hashCode;
    if (_writtenHash['$_scope/$name'] == hash) return;
    await _blobs.write(_file(name), value);
    _writtenHash['$_scope/$name'] = hash;
  }

  Future<void> _saveOrders() => _write('orders', jsonEncode(_orders));

  Future<void> _saveCustomers() => _write('customers', jsonEncode(_customers));

  Future<void> _saveMeta() => _write('meta', jsonEncode({'seq': _seq, 'ids': _idMap, 'cache': _cacheIndex, 'directoryAt': _directoryAt}));

  // -------------------------------------------------------------------
  // ONLINE / OFFLINE
  // -------------------------------------------------------------------

  void markOffline() {
    if (!enabled) return;
    if (!isOffline) {
      isOffline = true;
      notifyListeners();
    }
    _pingTimer ??= Timer.periodic(_pingEvery, (_) => unawaited(_ping()));
  }

  void markOnline() {
    if (!isOffline || holdOffline) return;
    isOffline = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    notifyListeners();
    unawaited(_afterReconnect());
  }

  Future<void> _afterReconnect() async {
    await sync();
    await refreshCaches();
  }

  Future<void> _ping() async {
    if (holdOffline) return;
    try {
      final probe = Dio(BaseOptions(connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 6)));
      final res = await probe.get('${ApiConfig.assetHost}/health');
      if (res.statusCode == 200) markOnline();
    } catch (_) {
      markOffline();
    }
  }

  /// Checks the connection now (the "Sync now" button).
  Future<void> checkNow() async {
    await _ping();
    if (!isOffline) await sync();
  }

  /// Saves everything needed to work offline. Called after login and when
  /// the connection comes back.
  Future<void> refreshCaches() async {
    final dio = _dio;
    if (dio == null || !enabled || isOffline) return;
    await _ensureLoaded();
    // The screen the user just opened goes first.
    await Future<void>.delayed(const Duration(seconds: 2));
    try {
      await Future.wait([
        dio.get('/settings'),
        dio.get('/categories', queryParameters: {'status': 'active'}),
        dio.get('/tables'),
        dio.get('/counters'),
        dio.get('/dashboard'),
        dio.get('/dashboard/sales-overview'),
        dio.get('/orders', queryParameters: {'status': 'active', 'page': 1, 'limit': 100}),
      ]);
      for (var page = 1; page < 50; page++) {
        final res = await dio.get('/products', queryParameters: {'limit': 200, if (page > 1) 'page': page});
        final rows = (res.data as Map)['data'] as List? ?? const [];
        if (rows.length < 200) break;
      }
      // All customers is a big download, and customers seen in between are
      // added to the list anyway.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_directory.isEmpty || now - _directoryAt > const Duration(hours: 1).inMilliseconds) {
        final res = await dio.get('/customers/directory');
        final rows = (res.data as Map)['data'] as List? ?? const [];
        _directory = {for (final row in rows) '${row['_id']}': (row as Map).cast<String, dynamic>()};
        _directoryAt = now;
        await _write('directory', jsonEncode(_directory));
        await _saveMeta();
      }
    } catch (_) {
      // Whatever was saved stays; the next refresh gets the rest.
    }
  }

  // -------------------------------------------------------------------
  // INSTANT SCREENS
  // -------------------------------------------------------------------

  /// What the server last answered to this request, with this device's unsent
  /// work added. Screens show it at once and then replace it with the fresh
  /// answer, so opening a screen does not wait for the network.
  Future<Map<String, dynamic>?> peek(String path, {Map<String, dynamic> query = const {}}) async {
    if (!enabled) return null;
    await _ensureLoaded();
    final options = RequestOptions(path: path, queryParameters: query);
    final stored = await _cached(options);
    return stored == null ? null : _overlay(options, stored);
  }

  /// The menu as last seen.
  List<Map<String, dynamic>> get cachedCatalog => enabled ? _catalog.values.toList() : const [];

  /// The bill for a cart worked out here, the same as the server would. Null
  /// when this device does not know the settings or an item yet.
  Future<Map<String, dynamic>?> quoteNow({
    required List<Map<String, dynamic>> items,
    required String orderType,
    required Map<String, dynamic> adjust,
  }) async {
    if (!enabled) return null;
    await _ensureLoaded();
    final settings = await _settings();
    if (settings.isEmpty) return null;
    try {
      final lines = _priceLines(RequestOptions(path: '/orders/quote'), items);
      return computeLocalBill(lines: lines, settings: settings, orderType: orderType, adjust: _adjustOf(adjust));
    } on DioException {
      return null;
    }
  }

  // -------------------------------------------------------------------
  // THE NETWORK LAYER CALLS THESE
  // -------------------------------------------------------------------

  static bool isConnectionProblem(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      default:
        return false;
    }
  }

  bool _isExempt(RequestOptions options) {
    final path = _pathOf(options);
    return options.extra['offlineBypass'] == true ||
        path.startsWith('/auth') ||
        path.startsWith('/public') ||
        path.startsWith('/platform') ||
        path.startsWith('/uploads') ||
        path.startsWith('/archive/export');
  }

  String _pathOf(RequestOptions options) {
    var path = options.path;
    final base = options.baseUrl;
    if (base.isNotEmpty && path.startsWith(base)) path = path.substring(base.length);
    return path.split('?').first;
  }

  /// Local ids that have reached the server become the server's ids.
  void rewriteIds(RequestOptions options) {
    if (!enabled || _idMap.isEmpty) return;
    if (options.path.contains(_idPrefix)) {
      options.path = options.path.replaceAllMapped(RegExp('$_idPrefix[A-Za-z0-9-]+'), (m) => _idMap[m[0]] ?? m[0]!);
    }
    final data = options.data;
    if (data is Map) {
      for (final key in const ['customerId', 'tableId', 'fromOrderId']) {
        final value = data[key];
        if (value is String && _idMap.containsKey(value)) data[key] = _idMap[value];
      }
    }
  }

  /// Whether this request must be answered here instead of by the server.
  bool shouldServeLocally(RequestOptions options) {
    if (!enabled || _isExempt(options)) return false;
    if (isOffline) return true;
    final data = options.data;
    final refersToLocal = options.path.contains(_idPrefix) ||
        (data is Map && '${data['customerId']}'.startsWith(_idPrefix));
    return refersToLocal;
  }

  /// A request failed for lack of connection: may it be answered here?
  /// A write that may have reached the server is only repeated locally when
  /// repeating it is safe, which is what clientRequestId is for.
  bool canServeAfterFailure(DioException e) {
    if (!enabled || !isConnectionProblem(e) || _isExempt(e.requestOptions)) return false;
    final options = e.requestOptions;
    final method = options.method.toUpperCase();
    if (method == 'GET') return true;
    final path = _pathOf(options);
    if (method == 'POST' && (path == '/orders' || path == '/orders/quote')) return true;
    if (method == 'PUT' && path.endsWith('/items')) return true;
    if (method == 'POST' && path.endsWith('/checkout')) return true;
    // Anything else only if it certainly never left the phone.
    return e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout;
  }

  /// Stores a good server response and adds what only this device knows.
  Future<void> onServerResponse(Response<dynamic> response) async {
    if (!enabled || _isExempt(response.requestOptions)) return;
    await _ensureLoaded();
    final options = response.requestOptions;
    if (options.method.toUpperCase() != 'GET' || response.data is! Map) return;
    await _remember(options, response.data as Map);
    if (hasPending) response.data = _overlay(options, _clone(response.data as Map));
  }

  // -------------------------------------------------------------------
  // STORED RESPONSES
  // -------------------------------------------------------------------

  String _cacheKey(RequestOptions options) {
    final params = options.queryParameters.entries.map((e) => '${e.key}=${e.value}').toList()..sort();
    return '${_pathOf(options)}?${params.join('&')}';
  }

  // Two small hashes rather than one big one: browsers have no 64-bit integers.
  String _cacheFile(String key) {
    var a = 7;
    var b = 11;
    for (final unit in '$_user|$key'.codeUnits) {
      a = (a * 31 + unit) & 0x7fffffff;
      b = (b * 131 + unit) & 0x7fffffff;
    }
    return 'c${a.toRadixString(36)}${b.toRadixString(36)}';
  }

  Future<void> _remember(RequestOptions options, Map data) async {
    final path = _pathOf(options);
    final query = options.queryParameters;
    final payload = data['data'];

    if (path == '/settings') _settingsMemo = null;
    if (path == '/products' && payload is List && !query.containsKey('search')) {
      for (final row in payload) {
        if (row is Map) _catalog['${row['_id']}'] = row.cast<String, dynamic>();
      }
      await _write('catalog', jsonEncode(_catalog));
    }
    if (path == '/customers' && payload is List) {
      for (final row in payload) {
        if (row is Map) _directory['${row['_id']}'] = row.cast<String, dynamic>();
      }
    }
    if (path == '/orders' && payload is List) _noteOrders(payload);
    if (path.startsWith('/orders/') && payload is Map && payload['_id'] != null) _noteOrders([payload]);
    if (path.startsWith('/tables/') && payload is Map && payload['openOrders'] is List) {
      _noteOrders(payload['openOrders'] as List);
    }

    // Big and always changing, or of no use offline.
    if (path == '/customers/directory' || path.startsWith('/archive') || path.startsWith('/audit')) return;
    final text = jsonEncode(data);
    if (text.length > _maxCacheChars) return;

    final key = _cacheKey(options);
    try {
      await _write(_cacheFile(key), text);
      _cacheIndex[key] = DateTime.now().millisecondsSinceEpoch;
      if (_cacheIndex.length > _maxCacheEntries) {
        final oldest = (_cacheIndex.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).first.key;
        _cacheIndex.remove(oldest);
        await _blobs.delete(_file(_cacheFile(oldest)));
      }
      await _saveMeta();
    } catch (_) {
      // Storage full or unavailable: the app simply has less to show offline.
    }
  }

  void _noteOrders(List rows) {
    for (final row in rows) {
      if (row is! Map || row['_id'] == null) continue;
      final id = '${row['_id']}';
      if (const ['open', 'preparing', 'ready'].contains(row['status'])) {
        _knownOrders[id] = row.cast<String, dynamic>();
      } else {
        _knownOrders.remove(id);
      }
    }
    if (_knownOrders.length > 400) {
      final keys = _knownOrders.keys.toList();
      for (final key in keys.take(keys.length - 400)) {
        _knownOrders.remove(key);
      }
    }
    unawaited(_write('known', jsonEncode(_knownOrders)).catchError((_) {}));
  }

  Future<Map<String, dynamic>?> _cached(RequestOptions options) async {
    try {
      final raw = await _blobs.read(_file(_cacheFile(_cacheKey(options))));
      return raw == null ? null : (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _settings() async {
    final memo = _settingsMemo;
    if (memo != null) return memo;
    try {
      final raw = await _blobs.read(_file(_cacheFile('/settings?')));
      if (raw != null) return _settingsMemo = (((jsonDecode(raw) as Map)['data'] as Map?) ?? const {}).cast<String, dynamic>();
    } catch (_) {
      // Falls through to no GST and no charges.
    }
    return const {};
  }

  static Map<String, dynamic> _clone(Map source) => (jsonDecode(jsonEncode(source)) as Map).cast<String, dynamic>();

  // -------------------------------------------------------------------
  // ANSWERING REQUESTS
  // -------------------------------------------------------------------

  Response<dynamic> _ok(RequestOptions options, Map<String, dynamic> body, [int status = 200]) =>
      Response<dynamic>(requestOptions: options, statusCode: status, data: _clone(body));

  DioException _refuse(RequestOptions options, int status, String message) => DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: status,
          data: {'success': false, 'message': message},
        ),
      );

  /// Answers the request; throws a [DioException] when it cannot be done here.
  Future<Response<dynamic>> serve(RequestOptions options) async {
    await _ensureLoaded();
    final method = options.method.toUpperCase();
    final path = _pathOf(options);
    final body = options.data is Map ? (options.data as Map).cast<String, dynamic>() : <String, dynamic>{};
    final orderMatch = RegExp(r'^/orders/([^/]+)(?:/([a-z-]+))?$').firstMatch(path);
    final tableOrders = RegExp(r'^/tables/([^/]+)/orders$').firstMatch(path);

    if (method == 'GET') return _serveRead(options, path);

    if (method == 'POST' && path == '/orders/quote') return _quote(options, body);
    if (method == 'POST' && path == '/orders') return _createBill(options, body);
    if (method == 'POST' && path == '/orders/open') return _openOrder(options, body);
    if (method == 'POST' && tableOrders != null) {
      return _openOrder(options, {...body, 'orderType': 'dine_in', 'tableId': tableOrders[1], 'autoLabel': true});
    }
    if (method == 'POST' && path == '/customers') return _createCustomer(options, body);
    if (orderMatch != null) {
      final id = orderMatch[1]!;
      final action = orderMatch[2];
      if (method == 'PUT' && action == 'items') return _updateItems(options, id, body);
      if (method == 'POST' && action == 'kot') return _kot(options, id);
      if (method == 'POST' && action == 'checkout') return _checkout(options, id, body);
      if (method == 'DELETE' && action == null) return _cancel(options, id, body);
      if (method == 'PATCH' && action == 'notes') return _patch(options, id, (o) => o['notes'] = body['notes']);
      if (method == 'PATCH' && action == 'customer') {
        final customer = _customerById('${body['customerId']}');
        return _patch(options, id, (o) => o['customer'] = customer);
      }
      if (method == 'PATCH' && action == 'table') {
        final table = await _tableById('${body['tableId']}');
        return _patch(options, id, (o) => o['table'] = table ?? body['tableId']);
      }
    }
    throw _refuse(options, 503, 'This needs internet. It will work again when you are back online.');
  }

  Future<Response<dynamic>> _serveRead(RequestOptions options, String path) async {
    final query = options.queryParameters;

    if (path == '/customers') return _customerList(options, query);
    final customerMatch = RegExp(r'^/customers/([^/]+)$').firstMatch(path);
    if (customerMatch != null && customerMatch[1] != 'directory') {
      final customer = _customerById(customerMatch[1]!);
      if (customer != null) return _ok(options, {'success': true, 'data': {'customer': customer, 'transactions': const []}});
    }

    final orderMatch = RegExp(r'^/orders/([^/]+)$').firstMatch(path);
    if (orderMatch != null) {
      final order = _orderById(orderMatch[1]!);
      if (order != null) return _ok(options, {'success': true, 'data': order});
    }

    final tableMatch = RegExp(r'^/tables/([^/]+)$').firstMatch(path);
    final stored = await _cached(options);

    if (path == '/tables/${tableMatch?[1]}' && stored == null) {
      final table = await _tableById(tableMatch![1]!);
      if (table != null) {
        final open = _knownOrders.values.where((o) => _refId(o['table']) == tableMatch[1]).toList();
        return _ok(options, _overlay(options, {'success': true, 'data': {'table': table, 'openOrders': open}}));
      }
    }
    if (path == '/orders' && stored == null) {
      final known = _knownOrders.values.where((o) => _matchesOrderQuery(o, query)).toList();
      return _ok(options, _overlay(options, {'success': true, 'data': known, 'pagination': {'page': 1, 'limit': 30, 'total': known.length, 'pages': 1}}));
    }
    if (stored != null) return _ok(options, _overlay(options, stored));
    throw _refuse(options, 503, 'This has not been loaded on this device yet. Please connect to the internet once.');
  }

  /// Adds this device's unsynced work to what the server last said.
  Map<String, dynamic> _overlay(RequestOptions options, Map<String, dynamic> body) {
    final path = _pathOf(options);
    final query = options.queryParameters;
    final payload = body['data'];
    final locals = _orders.values.toList();

    if (path == '/orders' && payload is List) {
      final page = int.tryParse('${query['page'] ?? 1}') ?? 1;
      final replaced = {for (final o in locals) if (o['serverId'] != null) '${o['serverId']}'};
      final rows = payload.where((o) => o is! Map || !replaced.contains('${o['_id']}')).toList();
      if (page <= 1) {
        final mine = locals.where((o) => _matchesOrderQuery(o, query)).toList()
          ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
        rows.insertAll(0, mine);
      }
      body['data'] = rows;
    } else if (path == '/tables' && payload is List) {
      for (final table in payload) {
        if (table is! Map) continue;
        final id = '${table['_id']}';
        final mine = locals.where((o) => _refId(o['table']) == id);
        var count = (table['openOrderCount'] as num?)?.toInt() ?? 0;
        var items = (table['openItemCount'] as num?)?.toInt() ?? 0;
        for (final order in mine) {
          final active = _isActive(order);
          if (order['serverId'] != null && !active) count -= 1;
          if (order['serverId'] == null && active) count += 1;
          if (active) items += _itemCount(order);
        }
        table['openOrderCount'] = math.max(0, count);
        table['openItemCount'] = math.max(0, items);
        if (table['status'] != 'reserved') table['liveStatus'] = count > 0 ? 'occupied' : 'available';
      }
    } else if (RegExp(r'^/tables/[^/]+$').hasMatch(path) && payload is Map) {
      final id = path.split('/').last;
      final replaced = {for (final o in locals) if (o['serverId'] != null) '${o['serverId']}'};
      final open = (payload['openOrders'] as List? ?? const []).where((o) => o is! Map || !replaced.contains('${o['_id']}')).toList();
      open.addAll(locals.where((o) => _refId(o['table']) == id && _isActive(o)));
      payload['openOrders'] = open;
    } else if (path == '/dashboard' && payload is Map) {
      final today = payload['today'];
      if (today is Map) {
        for (final order in locals.where((o) => o['status'] == 'completed')) {
          final paid = (order['paymentBreakdown'] as Map?) ?? const {};
          double add(Object? a, Object? b) => round2(((a as num?) ?? 0) + ((b as num?) ?? 0));
          today['sales'] = add(today['sales'], order['grandTotal']);
          today['orders'] = ((today['orders'] as num?) ?? 0) + 1;
          for (final key in const ['cash', 'upi', 'credit', 'card', 'online']) {
            today[key] = add(today[key], paid[key]);
          }
        }
      }
    }
    return body;
  }

  bool _isActive(Map<String, dynamic> order) => const ['open', 'preparing', 'ready'].contains(order['status']);

  int _itemCount(Map<String, dynamic> order) =>
      (order['items'] as List? ?? const []).fold<int>(0, (s, l) => s + (((l as Map)['quantity'] as num?)?.toInt() ?? 0));

  String? _refId(Object? ref) => ref is Map ? '${ref['_id']}' : ref?.toString();

  bool _matchesOrderQuery(Map<String, dynamic> order, Map<String, dynamic> query) {
    final status = query['status']?.toString();
    if (status == null && order['status'] == 'voided') return false;
    if (status != null) {
      if (status == 'active') {
        if (!_isActive(order)) return false;
      } else if (order['status'] != status) {
        return false;
      }
    }
    final type = query['orderType']?.toString();
    if (type != null && order['orderType'] != type) return false;
    final method = query['paymentMethod']?.toString();
    if (method != null && order['paymentMethod'] != method) return false;
    final table = query['table']?.toString();
    if (table != null && _refId(order['table']) != table) return false;
    final customer = query['customer']?.toString();
    if (customer != null && _refId(order['customer']) != customer) return false;
    final created = DateTime.tryParse('${order['createdAt']}');
    final from = DateTime.tryParse('${query['from']}');
    final to = DateTime.tryParse('${query['to']}');
    if (created != null && from != null && created.isBefore(from)) return false;
    if (created != null && to != null && created.isAfter(to)) return false;
    final search = query['search']?.toString().trim().toLowerCase();
    if (search != null && search.isNotEmpty) {
      final customerMap = order['customer'];
      final text = [
        order['orderNumber'],
        order['offlineRef'],
        order['tableCustomerLabel'],
        if (customerMap is Map) customerMap['name'],
        if (customerMap is Map) customerMap['phone'],
      ].join(' ').toLowerCase();
      if (!text.contains(search)) return false;
    }
    return true;
  }

  // -------------------------------------------------------------------
  // CUSTOMERS AND TABLES
  // -------------------------------------------------------------------

  Map<String, dynamic>? _customerById(String id) {
    final mapped = _idMap[id] ?? id;
    return _customers[mapped] ?? _directory[mapped];
  }

  Response<dynamic> _customerList(RequestOptions options, Map<String, dynamic> query) {
    final search = query['search']?.toString().trim().toLowerCase() ?? '';
    final hasDue = '${query['hasDue']}' == 'true';
    final page = math.max(int.tryParse('${query['page'] ?? 1}') ?? 1, 1);
    final limit = int.tryParse('${query['limit'] ?? 50}') ?? 50;
    final all = [..._customers.values, ..._directory.values].where((c) {
      if (hasDue && (((c['outstandingBalance'] as num?) ?? 0) <= 0)) return false;
      if (search.isEmpty) return true;
      return '${c['name']}'.toLowerCase().contains(search) || '${c['phone']}'.contains(search);
    }).toList()
      ..sort((a, b) {
        final due = ((b['outstandingBalance'] as num?) ?? 0).compareTo((a['outstandingBalance'] as num?) ?? 0);
        return due != 0 ? due : '${a['name']}'.compareTo('${b['name']}');
      });
    final rows = all.skip((page - 1) * limit).take(limit).toList();
    return _ok(options, {
      'success': true,
      'data': rows,
      'pagination': {'page': page, 'limit': limit, 'total': all.length, 'pages': (all.length / limit).ceil()},
    });
  }

  Future<Response<dynamic>> _createCustomer(RequestOptions options, Map<String, dynamic> body) async {
    final name = '${body['name'] ?? ''}'.trim();
    final phone = '${body['phone'] ?? ''}'.trim();
    if (name.isEmpty) throw _refuse(options, 400, 'Customer name is required.');
    if (phone.isEmpty) throw _refuse(options, 400, 'Phone number is required.');
    String digits(String v) {
      final only = v.replaceAll(RegExp(r'\D'), '');
      return only.length > 10 ? only.substring(only.length - 10) : only;
    }

    final existing = [..._customers.values, ..._directory.values].where((c) => digits('${c['phone']}') == digits(phone));
    if (existing.isNotEmpty) throw _refuse(options, 409, '$phone is already saved for ${existing.first['name']}.');
    final id = '$_idPrefix${const Uuid().v4()}';
    final customer = <String, dynamic>{
      '_id': id,
      'name': name,
      'phone': phone,
      'address': body['address'],
      'notes': body['notes'],
      'outstandingBalance': 0,
      'totalPurchases': 0,
      'status': 'active',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    _customers[id] = customer;
    await _saveCustomers();
    notifyListeners();
    return _ok(options, {'success': true, 'data': customer}, 201);
  }

  Future<Map<String, dynamic>?> _tableById(String id) async {
    try {
      final raw = await _blobs.read(_file(_cacheFile('/tables?')));
      if (raw == null) return null;
      final rows = (jsonDecode(raw) as Map)['data'] as List? ?? const [];
      for (final row in rows) {
        if (row is Map && '${row['_id']}' == id) {
          return {'_id': row['_id'], 'name': row['name'], 'number': row['number'], 'capacity': row['capacity'], 'status': row['status'], 'area': row['area'], 'active': true};
        }
      }
    } catch (_) {
      // Unknown table: the order keeps just its id.
    }
    return null;
  }

  // -------------------------------------------------------------------
  // ORDERS
  // -------------------------------------------------------------------

  Map<String, dynamic>? _orderById(String rawId) {
    final id = _idMap[rawId] ?? rawId;
    final local = _orders[id];
    if (local != null) return local;
    for (final order in _orders.values) {
      if (order['serverId'] == id) return order;
    }
    return _knownOrders[id];
  }

  /// A local order to work on; a running server order gets a local copy.
  Future<Map<String, dynamic>> _workingCopy(RequestOptions options, String rawId) async {
    final id = _idMap[rawId] ?? rawId;
    final found = _orderById(id);
    if (found == null) throw _refuse(options, 503, 'This order has not been loaded on this device. It needs internet.');
    if ('${found['_id']}'.startsWith(_idPrefix)) return found;
    final copy = _clone(found);
    final localId = '$_idPrefix${const Uuid().v4()}';
    copy['serverId'] = found['_id'];
    copy['_id'] = localId;
    copy['offline'] = true;
    copy['clientRequestId'] = const Uuid().v4();
    copy['items'] = _normalLines(copy['items']);
    copy['_sync'] = <String, dynamic>{'state': 'pending'};
    _orders[localId] = copy;
    return copy;
  }

  List<Map<String, dynamic>> _normalLines(Object? items) => (items as List? ?? const []).map((raw) {
        final line = (raw as Map).cast<String, dynamic>();
        final product = line['product'];
        return <String, dynamic>{...line, if (product is Map) 'product': product['_id']};
      }).toList();

  /// Turns request items into priced lines. An edited order keeps what was
  /// already sent to the kitchen.
  List<Map<String, dynamic>> _priceLines(RequestOptions options, Object? items, {List<Map<String, dynamic>> previous = const []}) {
    if (items is! List) throw _refuse(options, 400, 'Cart is empty. Add at least one item.');
    final byKey = {for (final line in previous) '${line['product'] ?? 'quick:${line['name']}'}': line};
    return items.map((raw) {
      final item = (raw as Map).cast<String, dynamic>();
      final quantity = num.tryParse('${item['quantity']}') ?? 0;
      final note = '${item['note'] ?? ''}'.trim();
      final quick = item['quickItem'];
      if (quantity < 1 || quantity != quantity.toInt()) throw _refuse(options, 400, 'Invalid quantity.');
      if (quick is Map && '${quick['name'] ?? ''}'.trim().isNotEmpty) {
        final name = '${quick['name']}'.trim();
        final old = byKey['quick:$name'];
        return <String, dynamic>{
          'name': name,
          'price': quick['price'],
          'quantity': quantity,
          'quickItem': {'name': name, 'price': quick['price']},
          if (note.isNotEmpty) 'note': note,
          'kotSentQuantity': old?['kotSentQuantity'] ?? 0,
        };
      }
      final id = '${item['productId'] ?? item['product']}';
      final product = _catalog[id];
      final old = byKey[id];
      if (product == null && old == null) throw _refuse(options, 400, 'This item is not available offline. Connect once to load the menu.');
      if (product != null && product['status'] == 'unavailable') throw _refuse(options, 400, '${product['name']} is currently unavailable.');
      return <String, dynamic>{
        'product': id,
        'name': product?['name'] ?? old?['name'],
        'price': product?['sellingPrice'] ?? old?['price'],
        'quantity': quantity,
        'taxRate': product != null ? product['taxRate'] : old?['taxRate'],
        if (note.isNotEmpty) 'note': note,
        'kotSentQuantity': old?['kotSentQuantity'] ?? 0,
      };
    }).toList();
  }

  /// The discount/charge choices of a request, else those on the order.
  Map<String, dynamic> _adjustOf(Map<String, dynamic> body, [Map<String, dynamic>? order]) {
    Object? pick(String key, Object? fallback) => body.containsKey(key) ? body[key] : fallback;
    final hasOwnType = body.containsKey('discountType');
    return {
      'discountType': pick('discountType', order?['discountType']),
      'discountValue': body.containsKey('discountValue')
          ? body['discountValue']
          : (body.containsKey('discount') && !hasOwnType ? body['discount'] : order?['discountValue']),
      'discountReason': pick('discountReason', order?['discountReason']),
      'serviceCharge': pick('serviceCharge', order?['serviceChargeEnabled']),
      'packagingCharge': pick('packagingCharge', order?['packagingChargeOverride']),
      'deliveryCharge': pick('deliveryCharge', order?['deliveryChargeOverride']),
      'complimentary': body['paymentMethod'] == 'COMPLIMENTARY' || body['complimentary'] == true,
      'complimentaryReason': body['complimentaryReason'],
    };
  }

  void _applyBill(Map<String, dynamic> order, Map<String, dynamic> bill) {
    final lines = bill['orderItems'];
    order.addAll(bill);
    order.remove('orderItems');
    order['items'] = lines;
  }

  Future<Response<dynamic>> _quote(RequestOptions options, Map<String, dynamic> body) async {
    final lines = _priceLines(options, body['items']);
    final bill = computeLocalBill(lines: lines, settings: await _settings(), orderType: '${body['orderType'] ?? 'takeaway'}', adjust: _adjustOf(body));
    return _ok(options, {'success': true, 'data': bill});
  }

  Future<Map<String, dynamic>> _staff() async {
    try {
      final raw = await TokenStorage.instance.readUserJson();
      if (raw != null) {
        final user = (jsonDecode(raw) as Map).cast<String, dynamic>();
        return {'_id': user['_id'] ?? user['id'], 'name': user['name'], 'role': user['role']};
      }
    } catch (_) {
      // The server sets the real staff member at sync anyway.
    }
    return {'name': 'Staff'};
  }

  Future<Map<String, dynamic>> _newOrder(Map<String, dynamic> body) async {
    _seq += 1;
    await _saveMeta();
    final customerId = body['customerId']?.toString();
    final tableId = body['tableId']?.toString();
    final table = tableId == null ? null : await _tableById(tableId);
    return <String, dynamic>{
      '_id': '$_idPrefix${const Uuid().v4()}',
      'orderNumber': _seq,
      'offline': true,
      'offlineRef': 'OFF-$_deviceTag-$_seq',
      'clientRequestId': body['clientRequestId'] ?? const Uuid().v4(),
      'orderType': body['orderType'] ?? 'takeaway',
      'orderSource': 'pos',
      'table': table ?? tableId,
      'tableCustomerLabel': body['tableCustomerLabel'],
      'deliveryInfo': body['orderType'] == 'delivery' ? body['deliveryInfo'] : null,
      'customer': customerId == null ? null : _customerById(customerId),
      'notes': body['notes'],
      'staff': await _staff(),
      'kitchenStatus': 'served',
      'kots': <dynamic>[],
      'items': <dynamic>[],
      'subtotal': 0,
      'grandTotal': 0,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      '_sync': <String, dynamic>{'state': 'pending'},
    };
  }

  /// Same checks as the server's checkout; sets how the bill was paid.
  void _applyPayment(RequestOptions options, Map<String, dynamic> order, Map<String, dynamic> body) {
    final method = '${body['paymentMethod'] ?? ''}';
    if (!const ['CASH', 'UPI', 'CARD', 'ONLINE', 'CREDIT', 'MIXED', 'COMPLIMENTARY'].contains(method)) {
      throw _refuse(options, 400, 'A valid payment method is required.');
    }
    final total = (order['grandTotal'] as num).toDouble();
    double amount(Object? v) => round2(num.tryParse('${v ?? 0}') ?? 0);
    final paid = <String, double>{'cash': 0, 'upi': 0, 'card': 0, 'online': 0, 'credit': 0};
    switch (method) {
      case 'CASH':
        paid['cash'] = total;
      case 'UPI':
        if ('${body['upiReference'] ?? ''}'.trim().isEmpty) throw _refuse(options, 400, 'UPI reference / UTR is required before marking payment paid.');
        paid['upi'] = total;
      case 'CARD':
        paid['card'] = total;
      case 'ONLINE':
        if ('${body['onlinePlatform'] ?? ''}'.trim().isEmpty) throw _refuse(options, 400, 'Choose the delivery app (e.g. Swiggy / Zomato) for an online order.');
        paid['online'] = total;
      case 'CREDIT':
        paid['credit'] = total;
      case 'MIXED':
        paid['cash'] = amount(body['cashPortion']);
        paid['upi'] = amount(body['upiPortion']);
        paid['card'] = amount(body['cardPortion']);
        paid['credit'] = amount(body['creditPortion']);
        final sum = round2(paid.values.fold<double>(0, (s, v) => s + v));
        if (sum != total) throw _refuse(options, 400, 'Mixed payment split (Rs $sum) does not equal grand total (Rs $total).');
        if (paid['upi']! > 0 && '${body['upiReference'] ?? ''}'.trim().isEmpty) throw _refuse(options, 400, 'UPI reference / UTR is required when Mixed payment includes UPI.');
    }
    if (paid['credit']! > 0 && order['customer'] == null) throw _refuse(options, 400, 'A customer must be selected for UDHAR / credit payments.');

    var change = 0.0;
    final received = body['amountReceived'];
    if (method == 'CASH' && received != null && '$received'.isNotEmpty) {
      final value = num.tryParse('$received');
      if (value == null) throw _refuse(options, 400, 'Amount received must be a valid number.');
      if (value < total) throw _refuse(options, 400, 'Amount received is less than the grand total.');
      change = round2(value - total);
    }
    order.addAll({
      'status': 'completed',
      'paymentStatus': 'paid',
      'paymentMethod': method,
      'paymentBreakdown': paid,
      'invoiceNumber': order['offlineRef'],
      'amountReceived': received,
      'changeReturned': change,
      'upiReference': body['upiReference'],
      'onlinePlatform': body['onlinePlatform'],
      'onlineOrderRef': body['onlineOrderRef'],
      'cardReference': body['cardReference'],
      'cashPortion': body['cashPortion'],
      'upiPortion': body['upiPortion'],
      'cardPortion': body['cardPortion'],
      'creditPortion': body['creditPortion'],
    });
  }

  void _keepAdjust(Map<String, dynamic> order, Map<String, dynamic> adjust) {
    order['serviceChargeEnabled'] = adjust['serviceCharge'];
    order['packagingChargeOverride'] = adjust['packagingCharge'];
    order['deliveryChargeOverride'] = adjust['deliveryCharge'];
  }

  Future<Response<dynamic>> _createBill(RequestOptions options, Map<String, dynamic> body) async {
    // The same bill sent again (a retry, or a double tap).
    final requestId = body['clientRequestId'];
    if (requestId != null) {
      for (final existing in _orders.values) {
        if (existing['clientRequestId'] == requestId) {
          return _ok(options, {'success': true, 'data': {'order': existing, 'customer': existing['customer']}});
        }
      }
    }
    final lines = _priceLines(options, body['items']);
    if (lines.isEmpty) throw _refuse(options, 400, 'Cart is empty. Add at least one item.');
    final settings = await _settings();
    final adjust = _adjustOf(body);
    final order = await _newOrder(body);
    _applyBill(order, computeLocalBill(lines: lines, settings: settings, orderType: '${order['orderType']}', adjust: adjust));
    _keepAdjust(order, adjust);
    _applyPayment(options, order, body);
    order['settings'] = _settingsSnapshot(settings);
    _orders['${order['_id']}'] = order;
    await _saveOrders();
    notifyListeners();
    return _ok(options, {'success': true, 'message': 'Bill saved on this device.', 'data': {'order': order, 'customer': order['customer']}}, 201);
  }

  Map<String, dynamic> _settingsSnapshot(Map<String, dynamic> s) => {
        for (final key in const [
          'taxEnabled', 'taxPercent', 'taxInclusive', 'gstType', 'roundOff', 'serviceChargePercent',
          'serviceChargeOn', 'packagingCharge', 'packagingChargeOn', 'deliveryCharge',
        ])
          if (s.containsKey(key)) key: s[key],
      };

  Future<Response<dynamic>> _openOrder(RequestOptions options, Map<String, dynamic> body) async {
    final order = await _newOrder(body);
    order['status'] = 'open';
    order['paymentStatus'] = 'pending';
    if (body['autoLabel'] == true && '${body['tableCustomerLabel'] ?? ''}'.trim().isEmpty) {
      final tableId = '${body['tableId']}';
      final server = _knownOrders.values.where((o) => _refId(o['table']) == tableId).length;
      final mine = _orders.values.where((o) => _refId(o['table']) == tableId && _isActive(o) && o['serverId'] == null).length;
      order['tableCustomerLabel'] = 'Customer ${server + mine + 1}';
    }
    order['settings'] = _settingsSnapshot(await _settings());
    _orders['${order['_id']}'] = order;
    await _saveOrders();
    notifyListeners();
    return _ok(options, {'success': true, 'message': 'Order opened.', 'data': order}, 201);
  }

  Future<Response<dynamic>> _updateItems(RequestOptions options, String id, Map<String, dynamic> body) async {
    final order = await _workingCopy(options, id);
    if (!_isActive(order)) throw _refuse(options, 409, 'This bill is already closed.');
    final previous = _normalLines(order['items']);
    final lines = _priceLines(options, body['items'] ?? const [], previous: previous);
    final adjust = _adjustOf(body, order);
    final settings = await _settings();
    _applyBill(order, computeLocalBill(lines: lines, settings: settings, orderType: '${order['orderType']}', adjust: adjust));
    _keepAdjust(order, adjust);
    if (body['notes'] != null) order['notes'] = body['notes'];
    if (body['tableCustomerLabel'] != null) order['tableCustomerLabel'] = body['tableCustomerLabel'];
    final customerId = body['customerId']?.toString();
    if (customerId != null && customerId.isNotEmpty) order['customer'] = _customerById(customerId);
    order['settings'] ??= _settingsSnapshot(settings);
    final sync = _sync(order)..['itemsChanged'] = true;
    order['_sync'] = sync;
    await _saveOrders();
    notifyListeners();
    return _ok(options, {'success': true, 'data': order});
  }

  Future<Response<dynamic>> _kot(RequestOptions options, String id) async {
    final order = await _workingCopy(options, id);
    final lines = _normalLines(order['items']);
    if (lines.isEmpty) throw _refuse(options, 400, 'Add items before sending a KOT.');
    final delta = <Map<String, dynamic>>[];
    for (final line in lines) {
      final sent = (line['kotSentQuantity'] as num?)?.toInt() ?? 0;
      final quantity = (line['quantity'] as num).toInt();
      if (quantity > sent) {
        delta.add({'product': line['product'], 'name': line['name'], 'quantity': quantity - sent, 'note': line['note']});
        line['kotSentQuantity'] = quantity;
      }
    }
    if (delta.isEmpty) throw _refuse(options, 409, 'No new items to send. All current quantities are already in the kitchen.');
    final kots = (order['kots'] as List? ?? <dynamic>[]).toList();
    final kot = <String, dynamic>{
      '_id': const Uuid().v4(),
      'kotNumber': kots.length + 1,
      'items': delta,
      'status': 'new',
      'sentBy': (await _staff())['name'],
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    kots.add(kot);
    order['kots'] = kots;
    order['items'] = lines;
    order['_sync'] = _sync(order)..['kot'] = true;
    await _saveOrders();
    notifyListeners();
    return _ok(options, {'success': true, 'message': 'KOT #${kot['kotNumber']} saved. Print it from this device.', 'data': {'order': order, 'kot': kot}}, 201);
  }

  Future<Response<dynamic>> _checkout(RequestOptions options, String id, Map<String, dynamic> body) async {
    final order = await _workingCopy(options, id);
    if (order['status'] == 'completed') {
      return _ok(options, {'success': true, 'data': {'order': order, 'customer': order['customer']}});
    }
    if ((order['items'] as List? ?? const []).isEmpty) throw _refuse(options, 400, 'Cart is empty. Add at least one item.');
    final customerId = body['customerId']?.toString();
    if (customerId != null && customerId.isNotEmpty) order['customer'] = _customerById(customerId);
    final adjust = _adjustOf(body, order);
    final settings = await _settings();
    _applyBill(order, computeLocalBill(lines: _normalLines(order['items']), settings: settings, orderType: '${order['orderType']}', adjust: adjust));
    _keepAdjust(order, adjust);
    _applyPayment(options, order, body);
    order['offlineRef'] ??= 'OFF-$_deviceTag-${++_seq}';
    order['invoiceNumber'] = order['offlineRef'];
    order['settings'] ??= _settingsSnapshot(settings);
    order['_sync'] = _sync(order)..['state'] = 'pending';
    await _saveMeta();
    await _saveOrders();
    notifyListeners();
    return _ok(options, {'success': true, 'data': {'order': order, 'customer': order['customer']}});
  }

  Future<Response<dynamic>> _cancel(RequestOptions options, String id, Map<String, dynamic> body) async {
    final order = await _workingCopy(options, id);
    if (order['status'] == 'completed') throw _refuse(options, 409, 'This bill is already paid.');
    if (order['serverId'] == null) {
      _orders.remove('${order['_id']}');
    } else {
      order['status'] = 'voided';
      order['_sync'] = _sync(order)
        ..['state'] = 'pending'
        ..['cancel'] = true
        ..['reason'] = body['reason'];
    }
    await _saveOrders();
    notifyListeners();
    return _ok(options, {'success': true, 'message': 'Order cancelled.'});
  }

  Future<Response<dynamic>> _patch(RequestOptions options, String id, void Function(Map<String, dynamic>) change) async {
    final order = await _workingCopy(options, id);
    change(order);
    order['_sync'] = _sync(order)..['detailsChanged'] = true;
    await _saveOrders();
    notifyListeners();
    return _ok(options, {'success': true, 'data': order});
  }

  // -------------------------------------------------------------------
  // SENDING TO THE SERVER
  // -------------------------------------------------------------------

  /// Sends everything waiting. Stops at the first sign of no connection;
  /// a record the server refuses is marked and the rest carry on.
  Future<void> sync() async {
    final dio = _dio;
    if (dio == null || !enabled || isSyncing) return;
    await _ensureLoaded();
    if (!hasPending) return;
    isSyncing = true;
    notifyListeners();
    final send = Options(extra: {'offlineBypass': true}, receiveTimeout: const Duration(seconds: 60));
    try {
      for (final customer in _customers.values.toList()) {
        await _sendCustomer(dio, send, customer);
      }
      for (final order in pendingOrders) {
        if ('${order['customer'] is Map ? order['customer']['_id'] : ''}'.startsWith(_idPrefix) &&
            !_idMap.containsKey(order['customer']['_id'])) {
          continue;
        }
        await _sendOrder(dio, send, order);
        notifyListeners();
      }
      lastSyncAt = DateTime.now();
    } on _StopSync {
      // Back to waiting; the timer or the next reconnect tries again.
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  /// Try a failed record again.
  Future<void> retryFailed() async {
    for (final order in pendingOrders) {
      if (_sync(order)['state'] == 'failed') {
        order['_sync'] = _sync(order)
          ..['state'] = 'pending'
          ..remove('error');
      }
    }
    await _saveOrders();
    notifyListeners();
    await checkNow();
  }

  /// Network trouble or a logged-out session stops the run; 5xx too, since
  /// the next try may well work.
  Never _stopOn(DioException e) {
    final status = e.response?.statusCode;
    if (isConnectionProblem(e)) {
      markOffline();
    }
    throw _StopSync(status);
  }

  bool _isRefusal(DioException e) {
    final status = e.response?.statusCode;
    return status != null && status >= 400 && status < 500 && status != 401 && status != 402 && status != 429;
  }

  String _messageOf(DioException e) {
    final data = e.response?.data;
    return data is Map ? '${data['message'] ?? 'Refused by the server.'}' : 'Refused by the server.';
  }

  Future<void> _sendCustomer(Dio dio, Options send, Map<String, dynamic> customer) async {
    final localId = '${customer['_id']}';
    String? serverId;
    try {
      final res = await dio.post('/customers', data: {'name': customer['name'], 'phone': customer['phone'], 'address': customer['address'], 'notes': customer['notes']}, options: send);
      serverId = '${res.data['data']['_id']}';
    } on DioException catch (e) {
      final details = e.response?.data is Map ? e.response!.data['details'] : null;
      if (e.response?.statusCode == 409 && details is Map && details['customerId'] != null) {
        serverId = '${details['customerId']}'; // Someone already saved this number.
      } else {
        _stopOn(e);
      }
    }
    _idMap[localId] = serverId;
    _directory[serverId] = {...customer, '_id': serverId};
    _customers.remove(localId);
    await _saveCustomers();
    await _saveMeta();
  }

  String? _customerRef(Map<String, dynamic> order) {
    final id = _refId(order['customer']);
    return id == null ? null : (_idMap[id] ?? id);
  }

  Map<String, dynamic> _paymentFields(Map<String, dynamic> order) => {
        for (final key in const [
          'paymentMethod', 'amountReceived', 'upiReference', 'onlinePlatform', 'onlineOrderRef', 'cardReference',
          'cashPortion', 'upiPortion', 'cardPortion', 'creditPortion',
        ])
          if (order[key] != null) key: order[key],
      };

  Map<String, dynamic> _adjustFields(Map<String, dynamic> order) => {
        'discountType': order['discountType'],
        'discountValue': order['discountValue'],
        'discountReason': order['discountReason'],
        if (order['serviceChargeEnabled'] != null) 'serviceCharge': order['serviceChargeEnabled'],
        if (order['packagingChargeOverride'] != null) 'packagingCharge': order['packagingChargeOverride'],
        if (order['deliveryChargeOverride'] != null) 'deliveryCharge': order['deliveryChargeOverride'],
      };

  /// The whole order as one record (see backend offlineController).
  Map<String, dynamic> _offlinePayload(Map<String, dynamic> order, {required bool open}) => {
        'clientRequestId': order['clientRequestId'],
        'offlineRef': order['offlineRef'],
        'createdAt': order['createdAt'],
        'status': open ? 'open' : 'completed',
        'orderType': order['orderType'],
        'tableId': _refId(order['table']),
        'tableCustomerLabel': order['tableCustomerLabel'],
        'deliveryInfo': order['deliveryInfo'],
        'customerId': _customerRef(order),
        'notes': order['notes'],
        'settings': order['settings'],
        'grandTotal': order['grandTotal'],
        ..._adjustFields(order),
        if (!open) ..._paymentFields(order),
        'items': _normalLines(order['items']).map((line) => {
              if (line['product'] != null) 'productId': line['product'],
              'name': line['name'],
              'price': line['price'],
              'quantity': line['quantity'],
              'taxRate': line['taxRate'],
              'note': line['note'],
              'kotSentQuantity': line['kotSentQuantity'],
              if (line['quickItem'] != null) 'quick': true,
            }).toList(),
      };

  Future<void> _finish(Map<String, dynamic> order, String? serverId) async {
    final localId = '${order['_id']}';
    if (serverId != null) {
      _idMap[localId] = serverId;
      await _saveMeta();
    }
    _orders.remove(localId);
    await _saveOrders();
  }

  Future<void> _fail(Map<String, dynamic> order, String message) async {
    order['_sync'] = _sync(order)
      ..['state'] = 'failed'
      ..['error'] = message;
    await _saveOrders();
  }

  Future<void> _sendOrder(Dio dio, Options send, Map<String, dynamic> order) async {
    if (_sync(order)['state'] == 'failed') return;
    final serverId = order['serverId']?.toString();
    final sync = _sync(order);
    final items = _normalLines(order['items']);
    if (serverId == null) {
      if (items.isEmpty && _isActive(order)) {
        // An empty order that was opened offline: nothing to tell the server
        // until something is added to it.
        return;
      }
      try {
        final res = await dio.post('/orders/offline-sync', data: _offlinePayload(order, open: _isActive(order)), options: send);
        await _finish(order, '${res.data['data']['order']['_id']}');
      } on DioException catch (e) {
        if (_isRefusal(e)) {
          await _fail(order, _messageOf(e));
        } else {
          _stopOn(e);
        }
      }
      return;
    }

    // A running server order that was changed here.
    try {
      if (sync['cancel'] == true) {
        await dio.delete('/orders/$serverId', data: {'reason': sync['reason']}, options: send);
        await _finish(order, serverId);
        return;
      }
      if (sync['itemsChanged'] == true || sync['detailsChanged'] == true) {
        await dio.put('/orders/$serverId/items', data: {
          'items': items.map((line) => {
                if (line['quickItem'] != null) 'quickItem': line['quickItem'] else 'productId': line['product'],
                'quantity': line['quantity'],
                if (line['note'] != null) 'note': line['note'],
              }).toList(),
          ..._adjustFields(order),
          if (order['notes'] != null) 'notes': order['notes'],
          if (_customerRef(order) != null) 'customerId': _customerRef(order),
          if (order['tableCustomerLabel'] != null) 'tableCustomerLabel': order['tableCustomerLabel'],
        }, options: send);
      }
      if (sync['kot'] == true) {
        try {
          await dio.post('/orders/$serverId/kot', options: send);
        } on DioException catch (e) {
          if (e.response?.statusCode != 409) rethrow;
        }
      }
      if (order['status'] == 'completed') {
        await dio.post('/orders/$serverId/checkout', data: {
          ..._paymentFields(order),
          if (_customerRef(order) != null) 'customerId': _customerRef(order),
          ..._adjustFields(order),
        }, options: send);
      }
      await _finish(order, serverId);
    } on DioException catch (e) {
      if (!_isRefusal(e)) _stopOn(e);
      await _resolveRefusedServerOrder(dio, send, order, serverId, e);
    }
  }

  /// The server would not apply a change to one of its running orders, for
  /// example it is already paid on another device, an item ran out of stock,
  /// or the business day was closed.
  Future<void> _resolveRefusedServerOrder(Dio dio, Options send, Map<String, dynamic> order, String serverId, DioException refusal) async {
    Map? current;
    try {
      final res = await dio.get('/orders/$serverId', options: send);
      current = res.data['data'] as Map?;
    } on DioException catch (e) {
      if (!_isRefusal(e)) _stopOn(e);
    }
    final total = (order['grandTotal'] as num?)?.toDouble() ?? 0;
    if (current?['status'] == 'completed') {
      final sameBill = (((current?['grandTotal'] as num?) ?? -1) - total).abs() < 0.01;
      if (order['status'] == 'completed' && sameBill) {
        await _finish(order, serverId); // Our earlier try did reach the server.
      } else {
        await _fail(order, 'This order was already paid on another device (Rs ${current?['grandTotal']}). Please check it with the manager.');
      }
      return;
    }
    if (order['status'] != 'completed') {
      await _fail(order, _messageOf(refusal));
      return;
    }
    // The customer has paid: record the sale as it happened, and take the
    // old running order off the table.
    try {
      final res = await dio.post('/orders/offline-sync', data: _offlinePayload(order, open: false), options: send);
      try {
        await dio.delete('/orders/$serverId', data: {'reason': 'Billed offline as ${order['offlineRef']}'}, options: send);
      } on DioException catch (e) {
        if (!_isRefusal(e)) _stopOn(e);
      }
      await _finish(order, '${res.data['data']['order']['_id']}');
    } on DioException catch (e) {
      if (_isRefusal(e)) {
        await _fail(order, _messageOf(e));
      } else {
        _stopOn(e);
      }
    }
  }
}

class _StopSync implements Exception {
  final int? status;
  const _StopSync(this.status);
}
