import 'package:app_smart_lock/screens/home_screen.dart';
import 'package:app_smart_lock/screens/manageruser.dart';
import 'package:app_smart_lock/screens/settingconnect.dart';
import 'package:app_smart_lock/screens/warning_screen.dart';
import 'package:flutter/material.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  // Danh sách các màn hình
  final List<Widget> _screens = const [
    HomeScreen(),
    SettingConnectScreen(),
    ManagerUserScreen(),
    WarningScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Dùng IndexedStack để khi chuyển tab, state (như thời gian đếm ngược 30s) không bị mất
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildAnimatedBottomNav(),
    );
  }

  // Giao diện Bottom Navigation Bar mượt mà
  Widget _buildAnimatedBottomNav() {
    List<IconData> icons = [
      Icons.home_outlined,
      Icons.wifi_tethering,
      Icons.person_add_alt,
      Icons.mail_outline,
    ];

    return Container(
      margin: const EdgeInsets.all(20).copyWith(top: 10),
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF3B3B3B),
        borderRadius: BorderRadius.circular(35),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(icons.length, (index) {
          bool isSelected = _currentIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() {
                _currentIndex = index;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icons[index],
                color: isSelected ? Colors.black : Colors.white70,
                size: 28,
              ),
            ),
          );
        }),
      ),
    );
  }
}
