import 'package:flutter/material.dart';
import '../../core/network/api_exception.dart';
import '../../models/product.dart';
import '../../models/category.dart';
import '../../services/catalog_service.dart';
import 'product_image_picker.dart';

import '../../core/theme/app_colors.dart';
class ProductFormScreen extends StatefulWidget {
  final Product? product;
  final List<Category> categories;
  const ProductFormScreen({super.key, this.product, required this.categories});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProductService();

  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _thresholdController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _descriptionController;
  String _foodType = '';

  String? _categoryId;
  bool _trackInventory = true;
  bool _available = true;
  bool _saving = false;
  String? _error;
  String _imageUrl = '';

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _priceController = TextEditingController(text: p != null ? p.sellingPrice.toString() : '');
    _stockController = TextEditingController(text: p != null ? p.stock.toString() : '0');
    _thresholdController = TextEditingController(text: p != null ? p.lowStockThreshold.toString() : '10');
    final rate = p?.taxRate;
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _foodType = p?.foodType ?? '';
    _taxRateController = TextEditingController(
      text: rate == null ? '' : (rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString()),
    );
    _categoryId = p?.categoryId ?? (widget.categories.isNotEmpty ? widget.categories.first.id : null);
    _trackInventory = p?.trackInventory ?? true;
    _available = p?.isAvailable ?? true;
    _imageUrl = p?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _thresholdController.dispose();
    _taxRateController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = 'Please select a category.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final body = {
      'name': _nameController.text.trim(),
      'category': _categoryId,
      'sellingPrice': double.parse(_priceController.text),
      'stock': int.tryParse(_stockController.text) ?? 0,
      'lowStockThreshold': int.tryParse(_thresholdController.text) ?? 10,
      'trackInventory': _trackInventory,
      'status': _available ? 'available' : 'unavailable',
      'imageUrl': _imageUrl,
      'description': _descriptionController.text.trim(),
      'foodType': _foodType,
      // Empty = the outlet's default GST rate.
      'taxRate': _taxRateController.text.trim().isEmpty ? '' : double.tryParse(_taxRateController.text.trim()),
    };

    try {
      if (_isEditing) {
        await _service.update(widget.product!.id, body);
      } else {
        await _service.create(body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Product' : 'Add Product')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Product Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Short description (optional)',
                hintText: 'e.g. Cheesy, served with mint chutney',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'veg', label: Text('Veg')),
                ButtonSegment(value: 'non_veg', label: Text('Non-veg')),
                ButtonSegment(value: 'egg', label: Text('Egg')),
                ButtonSegment(value: '', label: Text('None')),
              ],
              selected: {_foodType},
              onSelectionChanged: (v) => setState(() => _foodType = v.first),
            ),
            const SizedBox(height: 16),
            ProductImagePicker(initialImageUrl: _imageUrl, onUploaded: (url) => setState(() => _imageUrl = url)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: widget.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Selling Price (₹)'),
              validator: (v) {
                final val = double.tryParse(v ?? '');
                if (val == null || val < 0) return 'Enter a valid price';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _taxRateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'GST rate (%)',
                hintText: 'Leave empty to use the default rate (e.g. 5)',
              ),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return null;
                final val = double.tryParse(text);
                if (val == null || val < 0 || val > 40) return 'Enter a GST rate like 0, 5, 12 or 18';
                return null;
              },
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Track Inventory'),
              value: _trackInventory,
              onChanged: (v) => setState(() => _trackInventory = v),
            ),
            if (_trackInventory) ...[
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _stockController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stock'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _thresholdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Low Stock Alert'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Available for sale'),
              value: _available,
              onChanged: (v) => setState(() => _available = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_isEditing ? 'Save Changes' : 'Add Product'),
            ),
          ],
        ),
      ),
    );
  }
}
