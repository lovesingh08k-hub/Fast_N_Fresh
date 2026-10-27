import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../services/upload_service.dart';

/// Reusable product-photo picker: shows the current image (existing or
/// newly picked), lets the user choose from gallery/camera, compresses and
/// resizes before upload (keeps things fast and keeps storage/API usage
/// small), and returns the uploaded relative URL via [onUploaded].
class ProductImagePicker extends StatefulWidget {
  final String? initialImageUrl;
  final ValueChanged<String> onUploaded;

  const ProductImagePicker({super.key, this.initialImageUrl, required this.onUploaded});

  @override
  State<ProductImagePicker> createState() => _ProductImagePickerState();
}

class _ProductImagePickerState extends State<ProductImagePicker> {
  String? _currentUrl;
  Uint8List? _localPreview;
  bool _uploading = false;
  String? _error;

  static const List<int> _sizes = [480, 400, 320, 256, 192, 160];
  static const List<int> _qualities = [60, 45, 35, 25, 18, 12];
  static const int _maxBytes = 10 * 1024;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialImageUrl;
  }

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    // Browsers have no compress plugin, so the web picker resizes the photo
    // to a thumbnail itself.
    final picked = await picker.pickImage(
      source: source,
      imageQuality: kIsWeb ? 45 : 85,
      maxWidth: kIsWeb ? 400 : null,
      maxHeight: kIsWeb ? 400 : null,
    );
    if (picked == null) return;

    if (!mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final bytes = kIsWeb ? await picked.readAsBytes() : await _compress(picked.path);
      if (mounted) setState(() => _localPreview = bytes);

      final name = kIsWeb ? picked.name : 'product.jpg';
      final url = await UploadService().uploadProductImage(bytes, filename: name);
      if (mounted) setState(() => _currentUrl = url);
      widget.onUploaded(url);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not upload the image. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Compresses the image aggressively for product thumbnails.
  ///
  /// The uploaded file is intentionally kept at or below 10 KB because these
  /// images are only used as small product/menu thumbnails. We progressively
  /// reduce JPEG quality and dimensions until the target is reached.
  Future<Uint8List> _compress(String path) async {
    Uint8List? smallest;

    for (final size in _sizes) {
      for (final quality in _qualities) {
        final result = await FlutterImageCompress.compressWithFile(
          path,
          format: CompressFormat.jpeg,
          quality: quality,
          minWidth: size,
          minHeight: size,
          keepExif: false,
        );

        if (result == null) continue;
        smallest = result;

        if (result.length <= _maxBytes) {
          return result;
        }
      }
    }

    // Extremely detailed images can still be larger than 10 KB. Keep the
    // smallest generated thumbnail rather than uploading the original.
    if (smallest != null) return smallest;
    throw Exception('Could not compress the image.');
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
            // image_picker cannot open the camera on macOS.
            if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pick(ImageSource.camera);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Product Photo', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        InkWell(
          onTap: _uploading ? null : _showSourcePicker,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : _buildPreview(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildPreview() {
    if (_localPreview != null) {
      return Image.memory(_localPreview!, fit: BoxFit.cover, width: double.infinity);
    }
    if (_currentUrl != null && _currentUrl!.isNotEmpty) {
      return Image.network(
        ApiConfig.resolveAssetUrl(_currentUrl!),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 32, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text('Tap to add a photo', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}
