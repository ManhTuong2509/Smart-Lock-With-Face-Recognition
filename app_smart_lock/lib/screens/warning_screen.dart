import 'dart:async';

import 'package:app_smart_lock/services/smart_lock_cloud_service.dart';
import 'package:app_smart_lock/services/smart_lock_notification_service.dart';
import 'package:flutter/material.dart';

class WarningScreen extends StatefulWidget {
  const WarningScreen({super.key});

  @override
  State<WarningScreen> createState() => _WarningScreenState();
}

class _WarningScreenState extends State<WarningScreen> {
  DateTime _selectedDate = DateTime.now();
  final SmartLockCloudService _cloudService = SmartLockCloudService.instance;
  final SmartLockNotificationService _notificationService =
      SmartLockNotificationService.instance;

  List<UnknownFaceImage> _warningLogs = const [];
  Set<String> _knownWarningKeys = const {};
  Timer? _refreshTimer;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  List<UnknownFaceImage> get _visibleWarnings {
    return _warningLogs.where((warning) {
      final receivedAt = warning.receivedAt;
      return receivedAt != null && _isSameDay(receivedAt, _selectedDate);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadWarnings(showLoading: true);
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadWarnings(notifyNewWarnings: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadWarnings({
    bool showLoading = false,
    bool notifyNewWarnings = false,
  }) async {
    if (_isRefreshing) return;

    _isRefreshing = true;
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final warnings = await _cloudService.fetchUnknownFaces();
      if (!mounted) return;

      final oldKeys = _knownWarningKeys;
      final nextKeys = warnings.map(_warningKey).toSet();
      final newWarnings = notifyNewWarnings
          ? warnings.where((warning) => !oldKeys.contains(_warningKey(warning)))
          : const Iterable<UnknownFaceImage>.empty();

      setState(() {
        _warningLogs = warnings;
        _knownWarningKeys = nextKeys;
        _isLoading = false;
        _errorMessage = null;
      });

      for (final warning in newWarnings) {
        final receivedAt = warning.receivedAt ?? DateTime.now();
        await _notificationService.showIntruderAlert(
          dateLabel: _formatDate(receivedAt),
          timeLabel: _formatTime(receivedAt),
        );
      }
    } on SmartLockCloudException catch (error) {
      if (!mounted) return;
      if (showLoading) {
        setState(() {
          _errorMessage = error.message;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (showLoading) {
        setState(() {
          _errorMessage = '$error';
          _isLoading = false;
        });
      }
    } finally {
      _isRefreshing = false;
    }
  }

  String _warningKey(UnknownFaceImage warning) {
    return warning.path ??
        warning.receivedAt?.toIso8601String() ??
        warning.bytes?.toString() ??
        warning.hashCode.toString();
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFF47F91),
              onPrimary: Colors.black,
              surface: Color(0xFF2B2B2B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null) return;

    setState(() {
      _selectedDate = pickedDate;
    });
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day - $month - ${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final visibleWarnings = _visibleWarnings;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _pickDate,
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                    ),
                    child: const Icon(Icons.calendar_month_outlined, size: 34),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: _isLoading
                      ? null
                      : () => _loadWarnings(showLoading: true),
                  icon: const Icon(Icons.refresh),
                  color: Colors.white,
                  tooltip: 'Refresh',
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: _buildWarnings(visibleWarnings),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWarnings(List<UnknownFaceImage> visibleWarnings) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF47F91)),
      );
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return _WarningStateMessage(
        message: errorMessage,
        actionLabel: 'Thử lại',
        onPressed: () => _loadWarnings(showLoading: true),
      );
    }

    if (visibleWarnings.isEmpty) {
      return _EmptyWarning(dateLabel: _formatDate(_selectedDate));
    }

    return RefreshIndicator(
      onRefresh: () => _loadWarnings(showLoading: true),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 14),
        itemCount: visibleWarnings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final receivedAt = visibleWarnings[index].receivedAt ?? DateTime.now();
          return _WarningTile(
            warning: visibleWarnings[index],
            dateLabel: _formatDate(receivedAt),
            timeLabel: _formatTime(receivedAt),
          );
        },
      ),
    );
  }
}

class _WarningTile extends StatelessWidget {
  final UnknownFaceImage warning;
  final String dateLabel;
  final String timeLabel;

  const _WarningTile({
    required this.warning,
    required this.dateLabel,
    required this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      decoration: BoxDecoration(
        color: const Color(0xFFE4E4E4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(18),
              right: Radius.circular(16),
            ),
            child: _WarningImage(warning: warning),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$dateLabel\n$timeLabel',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.w500,
                fontFamily: 'serif',
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _WarningImage extends StatelessWidget {
  final UnknownFaceImage warning;

  const _WarningImage({required this.warning});

  @override
  Widget build(BuildContext context) {
    final imageBytes = warning.imageBytes;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      return Image.memory(
        imageBytes,
        width: 132,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    }

    return Image.asset(
      'image/fake_warning.png',
      width: 132,
      height: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: 132,
          height: double.infinity,
          color: const Color(0xFF2E2E2E),
          child: const Icon(
            Icons.person_outline,
            color: Colors.white70,
            size: 46,
          ),
        );
      },
    );
  }
}

class _WarningStateMessage extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onPressed;

  const _WarningStateMessage({
    required this.message,
    this.actionLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'serif',
              ),
            ),
            if (actionLabel != null && onPressed != null) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF47F91),
                  foregroundColor: Colors.black,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyWarning extends StatelessWidget {
  final String dateLabel;

  const _EmptyWarning({required this.dateLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Không có cảnh báo trong ngày $dateLabel',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'serif',
          ),
        ),
      ),
    );
  }
}
