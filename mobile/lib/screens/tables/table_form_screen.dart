import 'package:flutter/material.dart';
import '../../core/network/api_exception.dart';
import '../../models/table.dart';
import '../../services/table_service.dart';

class TableFormScreen extends StatefulWidget {
  final CafeTable? table;
  const TableFormScreen({super.key, this.table});

  @override
  State<TableFormScreen> createState() => _TableFormScreenState();
}

class _TableFormScreenState extends State<TableFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = TableService();
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  late final TextEditingController _qrNumberController;
  String _status = 'available';
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.table != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.table?.name ?? '');
    _capacityController = TextEditingController(text: (widget.table?.capacity ?? 4).toString());
    _qrNumberController = TextEditingController(text: widget.table?.number?.toString() ?? '');
    _status = widget.table?.status ?? 'available';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    _qrNumberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        final qrText = _qrNumberController.text.trim();
        await _service.update(widget.table!.id, {
          'name': _nameController.text.trim(),
          'capacity': int.tryParse(_capacityController.text) ?? 4,
          'status': _status,
          'number': qrText.isEmpty ? null : (int.tryParse(qrText) ?? widget.table?.number),
        });
      } else {
        await _service.create(name: _nameController.text.trim(), capacity: int.tryParse(_capacityController.text) ?? 4);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate table?'),
        content: Text('Deactivate "${widget.table!.name}"? Historical orders on this table are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deactivate')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.delete(widget.table!.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Table' : 'Add Table'),
        actions: [
          if (_isEditing) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Table Name / Number'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Capacity (seats)'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _qrNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'QR Order Number (optional)',
                  helperText: 'Used in the customer QR menu link, e.g. /menu?table=5. Leave blank to remove.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'available', child: Text('Available')),
                  DropdownMenuItem(value: 'reserved', child: Text('Reserved')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'available'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  "'Occupied' is set automatically once a customer order is opened on this table.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_isEditing ? 'Save Changes' : 'Add Table'),
            ),
          ],
        ),
      ),
    );
  }
}
