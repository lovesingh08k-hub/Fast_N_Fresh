import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';

class UploadService {
  final Dio _dio = DioClient.instance.dio;

  /// Uploads an (already compressed/resized) image and returns the
  /// relative URL to store on Product.imageUrl. Resolve for display with
  /// ApiConfig.resolveAssetUrl.
  Future<String> uploadProductImage(Uint8List bytes, {required String filename}) async {
    try {
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: filename, contentType: _imageType(filename)),
      });
      final res = await _dio.post('/uploads/product-image', data: formData);
      final data = res.data['data'] as Map<String, dynamic>;
      return data['url'] as String;
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// The server only accepts JPG, PNG and WEBP, checked by content type.
  DioMediaType _imageType(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.png')) return DioMediaType('image', 'png');
    if (name.endsWith('.webp')) return DioMediaType('image', 'webp');
    return DioMediaType('image', 'jpeg');
  }
}
