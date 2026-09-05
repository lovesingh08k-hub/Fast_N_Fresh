import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/customer.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/customer_service.dart';

import '../pos/add_customer_sheet.dart';
import 'customer_detail_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> with WidgetsBindingObserver {
  final _service = CustomerService();
  final _searchController = TextEditingController();

  Timer? _debounce;

  // `null` = no data loaded yet (or every attempt so far has failed).
  // A non-null list -- even an empty one -- is real data, so a failed
  // background refresh never blanks a screen that already has results;
  // the last successful list just stays up with a small retry banner.
  List<Customer>? _customers;

  bool _isRefreshing = true;
  String? _error;
  bool _dueOnly = false;

  AppLifecycleState? _lastLifecycleState;
  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final connectivity = context.read<ConnectivityProvider>();
    if (!identical(connectivity, _connectivity)) {
      _connectivity?.removeListener(_handleConnectivityChange);
      _connectivity = connectivity;
      _wasOnline = connectivity.isOnline;
      _connectivity!.addListener(_handleConnectivityChange);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.removeListener(_handleConnectivityChange);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded = _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground = state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground && _error != null && mounted) {
      _load();
    }
  }

  void _handleConnectivityChange() {
    final isOnline = _connectivity?.isOnline ?? true;

    if (isOnline && !_wasOnline && _error != null) {
      _load();
    }

    _wasOnline = isOnline;
  }

  Future<void> _load() async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      final customers = await _service.list(
        search: _searchController.text.trim(),
        hasDue: _dueOnly ? true : null,
      );

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      // Deliberately NOT clearing `_customers` -- if we already had a
      // successful list, it stays visible with an inline retry banner
      // instead of the whole page turning into an error state.
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not load customers.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(
      Duration(milliseconds: 400),
      _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canViewCreditHistory =
        context.watch<AuthProvider>().currentUser?.canViewCreditHistory ??
            false;

    return Scaffold(
      appBar: AppBar(
        title: Text('Customers'),
      ),

      // ---------------------------------------------------------------
      // ADD CUSTOMER
      // ---------------------------------------------------------------
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => AddCustomerSheet(),
          );

          if (result != null && mounted) {
            _load();
          }
        },
        child: Icon(Icons.person_add_alt),
      ),

      body: Column(
        children: [
          // -----------------------------------------------------------
          // SEARCH
          // -----------------------------------------------------------
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                ),
                isDense: true,
              ),
            ),
          ),

          // -----------------------------------------------------------
          // HAS DUE FILTER
          // ONLY ADMIN + MANAGER
          // -----------------------------------------------------------
          if (canViewCreditHistory)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    label: Text('Has Due'),
                    selected: _dueOnly,
                    onSelected: (value) {
                      setState(() {
                        _dueOnly = value;
                      });

                      _load();
                    },
                    labelStyle: TextStyle(
                      color: _dueOnly
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    selectedColor: AppColors.credit,
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: AppColors.border,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(height: 6),

          // -----------------------------------------------------------
          // CUSTOMER LIST
          // -----------------------------------------------------------
          Expanded(
            child: _buildBody(canViewCreditHistory: canViewCreditHistory),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({required bool canViewCreditHistory}) {
    final customers = _customers;

    // Nothing cached yet and a load is in flight -> full skeleton.
    if (customers == null && _isRefreshing) {
      return LoadingState();
    }

    // Nothing cached and the load failed -> full-screen error/retry as a
    // last-resort fallback, exactly as the existing pattern elsewhere.
    if (customers == null && _error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }

    if (customers == null) {
      return LoadingState();
    }

    if (customers.isEmpty) {
      return Column(
        children: [
          if (_error != null)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: InlineRetryBanner(
                message: 'Could not refresh. $_error',
                onRetry: _load,
              ),
            ),
          Expanded(
            child: EmptyState(
              icon: Icons.people_outline,
              title: 'No customers yet',
              subtitle: 'Add your first customer to get started.',
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.all(16),
        itemCount: customers.length + (_error != null ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (_error != null && index == 0) {
            return InlineRetryBanner(
              message: 'Could not refresh. Showing the last loaded customers.',
              onRetry: _load,
            );
          }

          final customerIndex = _error != null ? index - 1 : index;
          final customer = customers[customerIndex];

          return _CustomerTile(
            customer: customer,
            onChanged: _load,
            canViewCreditHistory: canViewCreditHistory,
          );
        },
      ),
    );
  }
}

// =====================================================================
// CUSTOMER TILE
// =====================================================================

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onChanged;
  final bool canViewCreditHistory;

  _CustomerTile({
    required this.customer,
    required this.onChanged,
    required this.canViewCreditHistory,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(
              customerId: customer.id,
            ),
          ),
        );

        if (context.mounted) {
          onChanged();
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          children: [
            // ---------------------------------------------------------
            // CUSTOMER AVATAR
            // ---------------------------------------------------------
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primaryLight,
              child: Text(
                customer.name.isNotEmpty
                    ? customer.name[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            SizedBox(width: 12),

            // ---------------------------------------------------------
            // CUSTOMER NAME + PHONE
            // ---------------------------------------------------------
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    customer.phone,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------
            // DUE
            // ONLY ADMIN + MANAGER
            // ---------------------------------------------------------
            if (canViewCreditHistory)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Due',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    Formatters.currency(
                      customer.outstandingBalance,
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: customer.hasDue
                          ? AppColors.credit
                          : AppColors.success,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
