import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../services/smart_lock_bluetooth_service.dart';
import '../widgets/slide_to_unlock.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isUnlocked = false;
  int unlockSecondsRemaining = 0;
  Timer? _unlockTimer;
  final Random _random = Random();
  final SmartLockBluetoothService _bluetoothService =
      SmartLockBluetoothService.instance;

  Future<void> _handleUnlock() async {
    if (isUnlocked) return;

    try {
      await _bluetoothService.unlockFromApp();
    } on SmartLockBluetoothException catch (error) {
      if (!mounted) return;

      await _showErrorDialog(error.message);
      return;
    } catch (error) {
      if (!mounted) return;

      await _showErrorDialog('$error');
      return;
    }

    if (!mounted) return;
    setState(() {
      isUnlocked = true;
      unlockSecondsRemaining = 5;
    });

    _unlockTimer?.cancel();
    _unlockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          unlockSecondsRemaining--;

          if (unlockSecondsRemaining <= 0) {
            isUnlocked = false;
            unlockSecondsRemaining = 0;
            timer.cancel();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _showErrorDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Không gửi được'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String _generateTemporaryCode() {
    return List.generate(6, (_) => _random.nextInt(10)).join();
  }

  Future<void> _showTemporaryKeyDialog() async {
    final temporaryCode = _generateTemporaryCode();
    int secondsRemaining = 30;
    Timer? codeTimer;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            codeTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (secondsRemaining <= 1) {
                timer.cancel();
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                }
                return;
              }

              setDialogState(() {
                secondsRemaining--;
              });
            });

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(26, 16, 26, 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E1E1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Mã mở cửa 1 lần',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'serif',
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: 170,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        temporaryCode,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'serif',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hiệu lực ${secondsRemaining}s',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _TemporaryKeyButton(
                          label: 'Cancel',
                          color: const Color(0xFFFF0505),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                        _TemporaryKeyButton(
                          label: 'Send',
                          color: const Color(0xFF00F736),
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            _sendTemporaryKey(temporaryCode);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    codeTimer?.cancel();
  }

  Future<void> _sendTemporaryKey(String code) async {
    try {
      await _bluetoothService.sendTemporaryKey(code);
    } on SmartLockBluetoothException catch (error) {
      if (!mounted) return;

      await _showErrorDialog(error.message);
      return;
    } catch (error) {
      if (!mounted) return;

      await _showErrorDialog('$error');
      return;
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Gửi thành công'),
          content: Text('Mã $code đã được gửi đến khóa.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Nền đen đã lấy từ thẻ cha
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              // 1. HEADER KHU VỰC: Logo ổ khóa, Title và Trạng thái đè lên nhau
              _buildHeaderArea(),

              const SizedBox(height: 5),

              // 2. KHU VỰC MAIN: Box màu hồng, ảnh Lock và thanh trượt đè lên nhau
              _buildMainPinkCard(),

              const SizedBox(height: 10),

              // 3. KHU VỰC ACTION: Send key & Wifi
              _buildBottomActionCards(),
            ],
          ),
        ),
      ),
    );
  }

  // --- 1. HEADER AREA ---
  Widget _buildHeaderArea() {
    return SizedBox(
      height: 180,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Lớp dưới cùng: Ảnh Logo ổ khóa 3D ở giữa
          Positioned(
            top: -50,
            bottom: 0,
            left: 0,
            right: -190,
            child: Image.asset(
              'image/lock_logo.png',
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.lock, color: Colors.white24, size: 100),
            ),
          ),

          Positioned(
            top: 40,
            bottom: -20,
            left: -190,
            right: 0,
            child: Image.asset(
              'image/lock_logo.png',
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.lock, color: Colors.white24, size: 100),
            ),
          ),
          // Lớp đè lên (trên cùng bên trái): Title SMART LOCK
          const Positioned(
            top: 0,
            left: 20,
            child: Text(
              "SMART",
              style: TextStyle(
                fontSize: 30,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const Positioned(
            top: 30,
            left: 130,
            child: Text(
              "LOCK",
              style: TextStyle(
                fontSize: 35,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Lớp đè lên Box Trạng thái
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B3B3B).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUnlocked ? Icons.lock_open : Icons.lock,
                    color: isUnlocked ? Colors.greenAccent : Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isUnlocked
                        ? "UNLOCKED ${unlockSecondsRemaining}s"
                        : "LOCKED",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. MAIN PINK CARD ---
  Widget _buildMainPinkCard() {
    return Expanded(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF18C96),
          borderRadius: BorderRadius.circular(30),
        ),

        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              right: -120,
              child: Image.asset(
                'image/lock.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.door_front_door_outlined,
                  size: 180,
                  color: Colors.black45,
                ),
              ),
            ),

            // Lớp thanh trượt
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: SlideToUnlockWidget(
                isUnlocked: isUnlocked,
                onUnlock: _handleUnlock,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 3. BOTTOM ACTION CARDS ---
  Widget _buildBottomActionCards() {
    return Row(
      children: [
        // Card Send Key
        Expanded(
          child: GestureDetector(
            onTap: _showTemporaryKeyDialog,
            child: Container(
              height: 140,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFBBE5ED),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.vpn_key_outlined,
                      color: Colors.black,
                    ),
                  ),
                  const Text(
                    "Send key",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 15),

        // Card Wifi
        Expanded(
          child: AnimatedBuilder(
            animation: _bluetoothService,
            builder: (context, _) {
              final wifiName = _bluetoothService.currentWifiName;
              final hasWifiName = wifiName != null && wifiName.isNotEmpty;

              return Container(
                height: 140,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B3B3B),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Image.asset(
                            'image/connect_setup.png',
                            width: 24,
                            height: 24,
                            color: Colors.black,
                            errorBuilder: (c, e, s) =>
                                const Icon(Icons.wifi, color: Colors.black),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: hasWifiName
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'ESP32 Wi-Fi',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      hasWifiName ? wifiName : 'Chưa cấu hình',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TemporaryKeyButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _TemporaryKeyButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 32,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            fontFamily: 'serif',
          ),
        ),
      ),
    );
  }
}
