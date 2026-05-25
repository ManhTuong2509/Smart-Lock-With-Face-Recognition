import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiConfig {
  final String? wifiName;
  final String? password;
  final String? cloudAddress;

  const WifiConfig({
    this.wifiName,
    this.password,
    this.cloudAddress,
  });

  Map<String, Object> toPayload() {
    return {
      if (wifiName != null && password != null) ...{
        'ssid': wifiName!,
        'wifiPassword': password!,
      },
      if (cloudAddress != null)
        'cloudUrl': _normalizeCloudAddress(cloudAddress!),
    };
  }
}

class SmartLockBluetoothException implements Exception {
  final String message;

  const SmartLockBluetoothException(this.message);

  @override
  String toString() => message;
}

class SmartLockBluetoothService extends ChangeNotifier {
  SmartLockBluetoothService._();

  static final SmartLockBluetoothService instance = SmartLockBluetoothService._();

  static final Guid _serviceUuid = Guid(
    '7b0f0001-64f0-4f5b-9f89-5d9b3f4c2a10',
  );
  static final Guid _configCharacteristicUuid = Guid(
    '7b0f0002-64f0-4f5b-9f89-5d9b3f4c2a10',
  );

  static const String _deviceName = 'SmartLock-ESP32';

  String? _currentWifiName;
  String? get currentWifiName => _currentWifiName;

  String? _currentCloudAddress;
  String? get currentCloudAddress => _currentCloudAddress;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  Future<void> sendTemporaryKey(String code) async {
    await _sendPayload({
      'temporaryKey': code,
    });
  }

  Future<void> unlockFromApp() async {
    await _sendPayload({
      'command': 'unlock',
    });
  }

  Future<void> sendWifiConfig(WifiConfig config) async {
    final payload = config.toPayload();

    if (payload.isEmpty) {
      return;
    }

    await _sendPayload(payload);

    if (config.wifiName != null && config.password != null) {
      _currentWifiName = config.wifiName;
    }

    if (config.cloudAddress != null) {
      _currentCloudAddress = _normalizeCloudAddress(config.cloudAddress!);
    }

    if (config.wifiName != null ||
        config.password != null ||
        config.cloudAddress != null) {
      notifyListeners();
    }
  }

  Future<void> _sendPayload(Map<String, Object> payload) async {
    if (_isBusy) {
      throw const SmartLockBluetoothException('Đang gửi dữ liệu đến khóa.');
    }

    _setBusy(true);

    BluetoothDevice? device;
    try {
      await _ensureBluetoothReady();
      device = await _findSmartLock();
      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 15),
      );

      final characteristic = await _findConfigCharacteristic(device);
      final jsonPayload = jsonEncode(payload);

      debugPrint('Smart lock BLE payload: $jsonPayload');
      await characteristic.write(
        utf8.encode(jsonPayload),
        withoutResponse: characteristic.properties.writeWithoutResponse,
      );
    } on SmartLockBluetoothException {
      rethrow;
    } catch (error) {
      throw SmartLockBluetoothException('Không gửi được dữ liệu: $error');
    } finally {
      await _stopScanQuietly();
      await _disconnectQuietly(device);
      _setBusy(false);
    }
  }

  Future<void> _stopScanQuietly() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<void> _disconnectQuietly(BluetoothDevice? device) async {
    if (device == null) return;

    try {
      await device.disconnect(queue: false);
    } catch (_) {}
  }

  Future<void> _ensureBluetoothReady() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final denied = statuses.values.any(
        (status) => status.isDenied || status.isPermanentlyDenied,
      );

      if (denied) {
        throw const SmartLockBluetoothException(
          'App chưa có quyền Bluetooth để tìm khóa.',
        );
      }
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState == BluetoothAdapterState.off &&
        defaultTargetPlatform == TargetPlatform.android) {
      await FlutterBluePlus.turnOn(timeout: 15);
    }

    final readyState = await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 15));

    if (readyState != BluetoothAdapterState.on) {
      throw const SmartLockBluetoothException('Bluetooth chưa sẵn sàng.');
    }
  }

  Future<BluetoothDevice> _findSmartLock() async {
    final completer = Completer<BluetoothDevice>();
    StreamSubscription<List<ScanResult>>? subscription;

    subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final name = result.advertisementData.advName.isNotEmpty
            ? result.advertisementData.advName
            : result.device.platformName;

        final hasDeviceName = name == _deviceName || name.contains(_deviceName);
        final hasService = result.advertisementData.serviceUuids.any(
          (uuid) => uuid == _serviceUuid,
        );

        if (hasDeviceName || hasService) {
          if (!completer.isCompleted) {
            completer.complete(result.device);
          }
          return;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        androidUsesFineLocation: false,
      );

      return await completer.future.timeout(
        const Duration(seconds: 13),
        onTimeout: () => throw const SmartLockBluetoothException(
          'Không tìm thấy khóa SmartLock-ESP32.',
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<BluetoothCharacteristic> _findConfigCharacteristic(
    BluetoothDevice device,
  ) async {
    final services = await device.discoverServices();

    for (final service in services) {
      if (service.uuid != _serviceUuid) continue;

      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == _configCharacteristicUuid) {
          return characteristic;
        }
      }
    }

    throw const SmartLockBluetoothException(
      'Không tìm thấy kênh cấu hình BLE trên khóa.',
    );
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
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
