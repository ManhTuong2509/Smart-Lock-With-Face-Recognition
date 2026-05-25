import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'smart_lock_bluetooth_service.dart';

class RegisteredFaceUser {
  final int? faissId;
  final String userName;
  final String? userId;
  final DateTime? registeredAt;
  final String? imagePath;
  final Uint8List? imageBytes;

  const RegisteredFaceUser({
    required this.userName,
    this.faissId,
    this.userId,
    this.registeredAt,
    this.imagePath,
    this.imageBytes,
  });

  factory RegisteredFaceUser.fromJson(Map<String, Object?> json) {
    return RegisteredFaceUser(
      faissId: _asInt(json['faiss_id']),
      userName: _asString(json['user_name']) ?? 'Unknown',
      userId: _asString(json['user_id']),
      registeredAt: _asDateTime(json['registered_at']),
      imagePath: _asString(json['image_path']),
      imageBytes: _decodeBase64Image(_asString(json['image_base64'])),
    );
  }
}

class UnknownFaceImage {
  final DateTime? receivedAt;
  final String? path;
  final Uint8List? imageBytes;
  final int? bytes;

  const UnknownFaceImage({
    this.receivedAt,
    this.path,
    this.imageBytes,
    this.bytes,
  });

  factory UnknownFaceImage.fromJson(Map<String, Object?> json) {
    return UnknownFaceImage(
      receivedAt: _asDateTime(json['received_at']),
      path: _asString(json['path']),
      imageBytes: _decodeBase64Image(_asString(json['image_base64'])),
      bytes: _asInt(json['bytes']),
    );
  }
}

class SmartLockCloudException implements Exception {
  final String message;

  const SmartLockCloudException(this.message);

  @override
  String toString() => message;
}

class SmartLockCloudService {
  SmartLockCloudService._();

  static final SmartLockCloudService instance = SmartLockCloudService._();

  static const String _fallbackCloudAddress = '171.248.246.120:10998';
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  Future<List<RegisteredFaceUser>> fetchUsers({int number = -1}) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/face/users',
      queryParameters: {'number': '$number'},
    );

    final users = json['users'];
    if (users is! List) {
      throw const SmartLockCloudException('Cloud trả về danh sách user sai.');
    }

    return users
        .whereType<Map>()
        .map((user) => RegisteredFaceUser.fromJson(user.cast<String, Object?>()))
        .toList();
  }

  Future<List<UnknownFaceImage>> fetchUnknownFaces({int number = -1}) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/face/unknown-jpg',
      queryParameters: {'number': '$number'},
    );

    final images = json['images'];
    if (images is! List) {
      throw const SmartLockCloudException('Cloud trả về danh sách cảnh báo sai.');
    }

    return images
        .whereType<Map>()
        .map((image) => UnknownFaceImage.fromJson(image.cast<String, Object?>()))
        .toList();
  }

  Future<void> deleteUsersByName(String userName) async {
    final json = await _requestJson(
      method: 'DELETE',
      path: '/face/users/by-name',
      queryParameters: {'user_name': userName},
    );

    if (json['success'] != true) {
      throw SmartLockCloudException(
        _asString(json['message']) ?? 'Cloud không xóa được user.',
      );
    }
  }

  Future<void> registerFaceJpg({
    required String userName,
    required String imagePath,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const SmartLockCloudException('Không tìm thấy ảnh đã chụp.');
    }

    final request = await _openRequest(
      method: 'POST',
      path: '/face/register-jpg',
      queryParameters: {'user_name': userName},
    );
    request.headers.contentType = ContentType('image', 'jpeg');
    request.add(await file.readAsBytes());

    final json = await _readJsonResponse(request);
    if (json['success'] != true) {
      throw SmartLockCloudException(
        _asString(json['message']) ?? 'Cloud không đăng ký được khuôn mặt.',
      );
    }
  }

  Future<Map<String, Object?>> _requestJson({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
  }) async {
    final request = await _openRequest(
      method: method,
      path: path,
      queryParameters: queryParameters,
    );
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    return _readJsonResponse(request);
  }

  Future<HttpClientRequest> _openRequest({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path: path, queryParameters: queryParameters);
    debugPrint('Smart lock cloud $method $uri');
    return _httpClient.openUrl(method, uri).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw const SmartLockCloudException('Không kết nối được cloud.');
      },
    );
  }

  Future<Map<String, Object?>> _readJsonResponse(
    HttpClientRequest request,
  ) async {
    try {
      final response = await request.close().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw const SmartLockCloudException('Cloud phản hồi quá lâu.');
        },
      );
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SmartLockCloudException(
          'Cloud lỗi ${response.statusCode}: $body',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
      throw const SmartLockCloudException('Cloud trả về dữ liệu sai định dạng.');
    } on SmartLockCloudException {
      rethrow;
    } on SocketException {
      throw const SmartLockCloudException(
        'Không kết nối được cloud. Kiểm tra Cloud Address và mạng.',
      );
    } on TimeoutException catch (error) {
      throw SmartLockCloudException(error.message ?? 'Kết nối cloud quá lâu.');
    } on FormatException {
      throw const SmartLockCloudException('Cloud trả về JSON không hợp lệ.');
    } catch (error) {
      throw SmartLockCloudException('Lỗi cloud: $error');
    }
  }

  Uri _buildUri({
    required String path,
    Map<String, String>? queryParameters,
  }) {
    final address =
        SmartLockBluetoothService.instance.currentCloudAddress ??
        _fallbackCloudAddress;
    final normalized = _normalizeCloudAddress(address);
    final base = Uri.parse('http://$normalized');

    return base.replace(
      path: _joinPaths(base.path, path),
      queryParameters: queryParameters,
    );
  }

  String _joinPaths(String basePath, String path) {
    final trimmedBase = basePath.replaceAll(RegExp(r'/+$'), '');
    final trimmedPath = path.replaceFirst(RegExp(r'^/+'), '');

    if (trimmedBase.isEmpty) return '/$trimmedPath';
    return '$trimmedBase/$trimmedPath';
  }
}

String _normalizeCloudAddress(String value) {
  var normalized = value.trim();
  normalized = normalized.replaceFirst(RegExp(r'^https?://'), '');

  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  return normalized;
}

String? _asString(Object? value) {
  if (value == null) return null;
  return value.toString();
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _asDateTime(Object? value) {
  final text = _asString(value);
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

Uint8List? _decodeBase64Image(String? value) {
  if (value == null || value.isEmpty) return null;

  final cleanValue = value.contains(',') ? value.split(',').last : value;
  try {
    return base64Decode(cleanValue);
  } on FormatException {
    return null;
  }
}
