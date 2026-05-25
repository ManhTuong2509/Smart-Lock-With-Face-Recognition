import 'dart:io';

import 'package:camera/camera.dart';
import 'package:app_smart_lock/services/smart_lock_cloud_service.dart';
import 'package:flutter/material.dart';

class AddedMember {
  final String name;
  final String photoPath;

  const AddedMember({
    required this.name,
    required this.photoPath,
  });
}

class AddUserScreen extends StatefulWidget {
  const AddUserScreen({super.key});

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<CameraDescription> _cameras = const [];
  CameraController? _cameraController;
  XFile? _capturedPhoto;
  bool _isFrontCamera = true;
  bool _isCameraLoading = true;
  bool _isSaving = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _setupCamera() async {
    setState(() {
      _isCameraLoading = true;
      _cameraError = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _cameraError = 'Không tìm thấy camera';
          _isCameraLoading = false;
        });
        return;
      }

      final frontCamera = _findCamera(CameraLensDirection.front);
      final selectedCamera = frontCamera ?? _cameras.first;
      _isFrontCamera =
          selectedCamera.lensDirection == CameraLensDirection.front;
      await _startCamera(selectedCamera);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Không thể mở camera';
        _isCameraLoading = false;
      });
    }
  }

  CameraDescription? _findCamera(CameraLensDirection direction) {
    for (final camera in _cameras) {
      if (camera.lensDirection == direction) return camera;
    }
    return null;
  }

  Future<void> _startCamera(CameraDescription camera) async {
    final oldController = _cameraController;
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await oldController?.dispose();
    await _cameraController!.initialize();

    if (!mounted) return;
    setState(() {
      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;
      _isCameraLoading = false;
      _cameraError = null;
    });
  }

  Future<void> _saveMember() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên thành viên')),
      );
      return;
    }

    final capturedPhoto = _capturedPhoto;
    if (capturedPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chụp ảnh thành viên')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await SmartLockCloudService.instance.registerFaceJpg(
        userName: name,
        imagePath: capturedPhoto.path,
      );
    } on SmartLockCloudException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() => _isSaving = false);
      return;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
      setState(() => _isSaving = false);
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 34),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: const Color(0xFFE4E4E4),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Color(0xFFF47F91),
                  size: 54,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Thêm user thành công',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'serif',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 118,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF47F91),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    Navigator.of(context).pop(
      AddedMember(name: name, photoPath: capturedPhoto.path),
    );
  }

  Future<void> _capturePhoto() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    try {
      final photo = await controller.takePicture();
      if (!mounted) return;
      setState(() {
        _capturedPhoto = photo;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Không chụp được ảnh')));
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedPhoto = null;
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isCameraLoading) return;

    final targetDirection = _isFrontCamera
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    final targetCamera = _findCamera(targetDirection);
    if (targetCamera == null) return;

    await _startCamera(targetCamera);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 14),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white,
                    iconSize: 30,
                    tooltip: 'Back',
                  ),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveMember,
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                        backgroundColor: const Color(0xFFF47F91),
                        foregroundColor: Colors.black,
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 30),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 54,
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'serif',
                  ),
                  decoration: InputDecoration(
                    hintText: 'UserName',
                    hintStyle: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'serif',
                    ),
                    filled: true,
                    fillColor: const Color(0xFFE4E4E4),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: const BorderSide(
                        color: Color(0xFFF47F91),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE1E1E1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _buildCameraPreview(),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 74,
                child: Row(
                  children: [
                    const Spacer(),
                    SizedBox(
                      width: 74,
                      height: 74,
                      child: ElevatedButton(
                        onPressed: _capturedPhoto == null
                            ? _capturePhoto
                            : _retakePhoto,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: const Color(0xFFF47F91),
                          foregroundColor: Colors.black,
                          elevation: 0,
                        ),
                        child: Icon(
                          _capturedPhoto == null
                              ? Icons.camera_alt_outlined
                              : Icons.refresh,
                          size: 31,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: ElevatedButton(
                            onPressed: _switchCamera,
                            style: ElevatedButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: EdgeInsets.zero,
                              backgroundColor: const Color(0xFFF47F91),
                              foregroundColor: Colors.black,
                              elevation: 0,
                            ),
                            child: Icon(
                              _isFrontCamera
                                  ? Icons.cameraswitch_outlined
                                  : Icons.flip_camera_android_outlined,
                              size: 25,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final capturedPhoto = _capturedPhoto;
    if (capturedPhoto != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(capturedPhoto.path),
            fit: BoxFit.cover,
          ),
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'Ảnh đã chụp',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final controller = _cameraController;

    if (_isCameraLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF47F91)),
      );
    }

    if (_cameraError != null ||
        controller == null ||
        !controller.value.isInitialized) {
      return Center(
        child: Text(
          _cameraError ?? 'Camera chưa sẵn sàng',
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 1,
            height: controller.value.previewSize?.width ?? 1,
            child: CameraPreview(controller),
          ),
        ),
        Positioned(
          left: 50,
          top: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _isFrontCamera ? 'Front camera' : 'Back camera',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
