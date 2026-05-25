import 'package:flutter/material.dart';

class SlideToUnlockWidget extends StatefulWidget {
  final bool isUnlocked;
  final Future<void> Function() onUnlock;

  const SlideToUnlockWidget({
    super.key,
    required this.isUnlocked,
    required this.onUnlock,
  });

  @override
  State<SlideToUnlockWidget> createState() => _SlideToUnlockWidgetState();
}

class _SlideToUnlockWidgetState extends State<SlideToUnlockWidget> {
  double _dragPosition = 0.0;
  final double _thumbSize = 56.0;
  double _maxDrag = 0.0;
  bool _isUnlocking = false;

  @override
  void didUpdateWidget(covariant SlideToUnlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isUnlocked && !widget.isUnlocked) {
      setState(() {
        _dragPosition = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tính toán quãng đường tối đa có thể kéo (chiều rộng khung trừ đi chiều rộng nút và padding)
        _maxDrag = constraints.maxWidth - _thumbSize - 10;

        if (widget.isUnlocked && _dragPosition != _maxDrag) {
          _dragPosition = _maxDrag;
        }

        return Container(
          height: _thumbSize + 10,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(
              alpha: 0.2,
            ), // Màu nền đen trong suốt của thanh trượt
            borderRadius: BorderRadius.circular(40),
          ),
          child: Stack(
            children: [
              // Background track: Các mũi tên mờ mờ ở dưới nền
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 40),
                    Icon(
                      Icons.keyboard_double_arrow_right,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.keyboard_double_arrow_right,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.keyboard_double_arrow_right,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.keyboard_double_arrow_right,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.keyboard_double_arrow_right,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 40),
                    Icon(
                      Icons.lock_open,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),

              // Thumb
              AnimatedPositioned(
                duration: _dragPosition == 0
                    ? const Duration(milliseconds: 300)
                    : Duration.zero,
                curve: Curves.bounceOut,
                left: _dragPosition,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    if (widget.isUnlocked || _isUnlocking) return;
                    setState(() {
                      _dragPosition += details.delta.dx;

                      _dragPosition = _dragPosition.clamp(0.0, _maxDrag);
                    });
                  },
                  onPanEnd: (details) async {
                    if (widget.isUnlocked || _isUnlocking) return;

                    if (_dragPosition > _maxDrag * 0.9) {
                      setState(() {
                        _dragPosition = _maxDrag;
                        _isUnlocking = true;
                      });
                      try {
                        await widget.onUnlock();
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isUnlocking = false;
                            if (!widget.isUnlocked) {
                              _dragPosition = 0.0;
                            }
                          });
                        }
                      }
                    } else {
                      setState(() {
                        _dragPosition = 0.0;
                      });
                    }
                  },
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: _isUnlocking
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.black,
                            ),
                          )
                        : Icon(
                            widget.isUnlocked
                                ? Icons.lock_open
                                : Icons.lock_outline,
                            color: widget.isUnlocked
                                ? Colors.green
                                : Colors.black,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
