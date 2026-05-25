import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class SmartLockNotificationService {
  SmartLockNotificationService._();

  static final SmartLockNotificationService instance =
      SmartLockNotificationService._();

  static const MethodChannel _channel = MethodChannel(
    'app_smart_lock/notifications',
  );

  bool _permissionRequested = false;

  Future<void> showIntruderAlert({
    required String dateLabel,
    required String timeLabel,
  }) async {
    final canNotify = await _ensurePermission();
    if (!canNotify) return;

    try {
      await _channel.invokeMethod<void>('showIntruderAlert', {
        'title': 'Cảnh báo đột nhập',
        'body': 'Có khuôn mặt lạ lúc $timeLabel ngày $dateLabel.',
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<bool> _ensurePermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    if (_permissionRequested) return false;
    _permissionRequested = true;

    final requestedStatus = await Permission.notification.request();
    return requestedStatus.isGranted;
  }
}
