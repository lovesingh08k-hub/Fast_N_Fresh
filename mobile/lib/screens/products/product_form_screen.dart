import 'package:flutter/material.dart';
import '../../core/network/api_exception.dart';
import '../../models/product.dart';
import '../../models/category.dart';
import '../../services/catalog_service.dart';
import 'product_image_picker.dart';

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
  late final TextEditingController _costController;
  late final TextEditingController _stockController;
  late final TextEditingController _thresholdController;

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
    _costController = TextEditingController(text: p != null ? p.costPrice.toString() : '');
    _stockController = TextEditingController(text: p != null ? p.stock.toString() : '0');
    _thresholdController = TextEditingController(text: p != null ? p.lowStockThreshold.toString() : '10');
    _categoryId = p?.categoryId ?? (widget.categories.isNotEmpty ? widget.categories.first.id : null);
    _trackInventory = p?.trackInventory ?? true;
    _available = p?.isAvailable ?? true;
    _imageUrl = p?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _stockController.dispose();
    _thresholdController.dispose();
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
      'costPrice': double.tryParse(_costController.text) ?? 0,
      'stock': int.tryParse(_stockController.text) ?? 0,
      'lowStockThreshold': int.tryParse(_thresholdController.text) ?? 10,
      'trackInventory': _trackInventory,
      'status': _available ? 'available' : 'unavailable',
      'imageUrl': _imageUrl,
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
            const SizedBox(height: 16),
            ProductImagePicker(initialImageUrl: _imageUrl, onUploaded: (url) => setState(() => _imageUrl = url)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: widget.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Selling Price (₹)'),
                  validator: (v) {
                    final val = double.tryParse(v ?? '');
                    if (val == null || val < 0) return 'Enter a valid price';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cost Price (₹)'),
                ),
              ),
            ]),
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
              Text(_error!, style: const TextStyle(color: Colors.red)),
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
