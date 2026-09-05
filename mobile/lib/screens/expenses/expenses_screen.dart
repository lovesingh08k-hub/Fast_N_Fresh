import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/misc_models.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/misc_services.dart';

class ExpensesScreen extends StatefulWidget {
  ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> with WidgetsBindingObserver {
  final _service = ExpenseService();
  List<Expense> _expenses = [];
  bool _loading = true;
  String? _error;

  static const List<String> _categories = ['Electricity', 'Rent', 'Raw Materials', 'Maintenance', 'Salaries', 'Other'];

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded = _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground = state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground && mounted && _error != null) {
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
      _loading = true;
      _error = null;
    });
    try {
      final expenses = await _service.list();
      setState(() => _expenses = expenses);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load expenses.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addExpense() async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    String category = 'Other';
    DateTime date = DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)))),
                SizedBox(height: 16),
                Text('Add Expense', style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: 16),
                TextField(controller: titleController, decoration: InputDecoration(labelText: 'Expense Title')),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: InputDecoration(labelText: 'Category'),
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setModalState(() => category = v ?? 'Other'),
                ),
                SizedBox(height: 12),
                TextField(controller: amountController, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Amount (₹)')),
                SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Date: ${Formatters.date(date)}'),
                  trailing: Icon(Icons.calendar_today_outlined, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (picked != null) setModalState(() => date = picked);
                  },
                ),
                TextField(controller: notesController, decoration: InputDecoration(labelText: 'Notes (optional)')),
                SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () async {
                    final amount = double.tryParse(amountController.text);
                    if (titleController.text.trim().isEmpty || amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enter a valid title and amount.')));
                      return;
                    }
                    try {
                      await _service.create({
                        'title': titleController.text.trim(),
                        'category': category,
                        'amount': amount,
                        'date': date.toIso8601String(),
                        'notes': notesController.text.trim(),
                      });
                      if (context.mounted) Navigator.pop(context, true);
                    } on ApiException catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  child: Text('Save Expense'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) _load();
  }

  Future<void> _delete(Expense expense) async {
    try {
      await _service.delete(expense.id);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold(0.0, (sum, e) => sum + e.amount);

    return Scaffold(
      appBar: AppBar(title: Text('Expenses')),
      floatingActionButton: FloatingActionButton(onPressed: _addExpense, child: Icon(Icons.add)),
      body: _loading
          ? LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 90),
                    children: [
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Expenses', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(Formatters.currency(total), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.danger)),
                          ],
                        ),
                      ),
                      SizedBox(height: 14),
                      if (_expenses.isEmpty)
                        Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No expenses recorded yet.', style: TextStyle(color: AppColors.textMuted))))
                      else
                        ..._expenses.map((e) => Container(
                              margin: EdgeInsets.only(bottom: 8),
                              padding: EdgeInsets.all(14),
                              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(e.title, style: TextStyle(fontWeight: FontWeight.w700)),
                                      SizedBox(height: 3),
                                      Text('${e.category} · ${Formatters.date(e.date)}', style: Theme.of(context).textTheme.bodyMedium),
                                    ],
                                  ),
                                ),
                                Text(Formatters.currency(e.amount), style: TextStyle(fontWeight: FontWeight.w700)),
                                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: AppColors.danger), onPressed: () => _delete(e)),
                              ]),
                            )),
                    ],
                  ),
                ),
    );
  }
}
