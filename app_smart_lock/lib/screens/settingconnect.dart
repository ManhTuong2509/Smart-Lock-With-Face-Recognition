import 'package:flutter/material.dart';
import '../services/smart_lock_bluetooth_service.dart';

class SettingConnectScreen extends StatefulWidget {
  const SettingConnectScreen({super.key});

  @override
  State<SettingConnectScreen> createState() => _SettingConnectScreenState();
}

class _SettingConnectScreenState extends State<SettingConnectScreen> {
  final TextEditingController _wifiNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _cloudAddressController = TextEditingController();
  final SmartLockBluetoothService _bluetoothService =
      SmartLockBluetoothService.instance;

  bool _isSending = false;

  Future<void> _sendConfig() async {
    final wifiName = _wifiNameController.text.trim();
    final password = _passwordController.text.trim();
    final cloudAddress = _cloudAddressController.text.trim();
    final hasWifiName = wifiName.isNotEmpty;
    final hasPassword = password.isNotEmpty;

    if (hasWifiName != hasPassword) {
      await _showMessageDialog(
        title: 'Thiếu thông tin',
        message: 'Vui lòng nhập đủ WiFi Name và Password trước khi gửi.',
      );
      return;
    }

    if (!hasWifiName && cloudAddress.isEmpty) {
      await _showMessageDialog(
        title: 'Chưa có dữ liệu',
        message: 'Nhập Wi-Fi/password hoặc Cloud Address để gửi cấu hình.',
      );
      return;
    }

    if (cloudAddress.isNotEmpty && !_isValidCloudAddress(cloudAddress)) {
      await _showMessageDialog(
        title: 'Sai định dạng Cloud',
        message: 'Vui lòng nhập theo dạng IP:Port, ví dụ 171.226.34.64:45553.',
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await _bluetoothService.sendWifiConfig(
        WifiConfig(
          wifiName: hasWifiName ? wifiName : null,
          password: hasPassword ? password : null,
          cloudAddress: cloudAddress.isNotEmpty ? cloudAddress : null,
        ),
      );

      if (!mounted) return;

      _wifiNameController.clear();
      _passwordController.clear();
      _cloudAddressController.clear();

      await _showMessageDialog(
        title: 'Gửi thành công',
        message: 'Cấu hình đã được gửi đến khóa.',
      );
    } on SmartLockBluetoothException catch (error) {
      if (!mounted) return;

      await _showMessageDialog(
        title: 'Không gửi được',
        message: error.message,
      );
    } catch (error) {
      if (!mounted) return;

      await _showMessageDialog(
        title: 'Không gửi được',
        message: '$error',
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  bool _isValidCloudAddress(String value) {
    final normalized = value
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    final pattern = RegExp(
      r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}'
      r'(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d):'
      r'([1-9]\d{0,4})$',
    );

    if (!pattern.hasMatch(normalized)) return false;

    final port = int.tryParse(normalized.split(':').last);
    return port != null && port <= 65535;
  }

  Future<void> _showMessageDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
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

  @override
  void dispose() {
    _wifiNameController.dispose();
    _passwordController.dispose();
    _cloudAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Device Setup',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'serif',
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Connect your lock',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'serif',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Configure Wi-Fi\nand cloud\nconnection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFD8D8D8),
                  fontSize: 22,
                  height: 1.12,
                  fontWeight: FontWeight.w300,
                  fontFamily: 'serif',
                ),
              ),
              const SizedBox(height: 14),
              Image.asset(
                'image/connect_setup.png',
                height: 112,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.wifi_tethering,
                  color: Colors.white70,
                  size: 96,
                ),
              ),
              const SizedBox(height: 24),
              _SetupInput(
                label: 'WiFi Name',
                controller: _wifiNameController,
              ),
              const SizedBox(height: 10),
              _SetupInput(
                label: 'Password',
                controller: _passwordController,
                obscureText: true,
              ),
              const SizedBox(height: 10),
              _SetupInput(
                label: 'Cloud Address',
                controller: _cloudAddressController,
                hintText: '171.226.34.64:45553',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              Center(
                child: SizedBox(
                  width: 172,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _sendConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF47F91),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'Send',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'serif',
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final String? hintText;
  final TextInputType? keyboardType;

  const _SetupInput({
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.hintText,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              fontFamily: 'serif',
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 38,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Colors.black38),
              filled: true,
              fillColor: const Color(0xFFD9D9D9),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: Color(0xFFF47F91),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
