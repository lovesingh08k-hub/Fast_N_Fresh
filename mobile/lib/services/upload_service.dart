import 'dart:io';
import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';

class UploadService {
  final Dio _dio = DioClient.instance.dio;

  /// Uploads a (already compressed/resized) image file and returns the
  /// relative URL to store on Product.imageUrl. Resolve for display with
  /// ApiConfig.resolveAssetUrl.
  Future<String> uploadProductImage(File file) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
      });
      final res = await _dio.post('/uploads/product-image', data: formData);
      final data = res.data['data'] as Map<String, dynamic>;
      return data['url'] as String;
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}
