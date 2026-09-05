import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
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

  ProductImagePicker({super.key, this.initialImageUrl, required this.onUploaded});

  @override
  State<ProductImagePicker> createState() => _ProductImagePickerState();
}

class _ProductImagePickerState extends State<ProductImagePicker> {
  String? _currentUrl;
  File? _localPreview;
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
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final compressedFile = await _compress(File(picked.path));
      setState(() => _localPreview = compressedFile);

      final url = await UploadService().uploadProductImage(compressedFile);
      setState(() => _currentUrl = url);
      widget.onUploaded(url);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not upload the image. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Compresses the image aggressively for product thumbnails.
  ///
  /// The uploaded file is intentionally kept at or below 10 KB because these
  /// images are only used as small product/menu thumbnails. We progressively
  /// reduce JPEG quality and dimensions until the target is reached.
  Future<File> _compress(File file) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // Try sensible thumbnail sizes first, then fall back to a tiny thumbnail
    // if a complex photo still exceeds 10 KB.


    File? smallest;

    for (final size in _sizes) {
      for (final quality in _qualities) {
        final targetPath = '${dir.path}/product_${stamp}_${size}_$quality.jpg';
        final result = await FlutterImageCompress.compressAndGetFile(
          file.absolute.path,
          targetPath,
          format: CompressFormat.jpeg,
          quality: quality,
          minWidth: size,
          minHeight: size,
          keepExif: false,
        );

        if (result == null) continue;
        final output = File(result.path);
        final bytes = await output.length();
        smallest = output;

        if (bytes <= _maxBytes) {
          return output;
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
              leading: Icon(Icons.photo_library_outlined),
              title: Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Take a Photo'),
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
        SizedBox(height: 10),
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
                ? Center(child: CircularProgressIndicator())
                : _buildPreview(),
          ),
        ),
        if (_error != null) ...[
          SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildPreview() {
    if (_localPreview != null) {
      return Image.file(_localPreview!, fit: BoxFit.cover, width: double.infinity);
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
          SizedBox(height: 8),
          Text('Tap to add a photo', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}
