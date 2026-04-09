import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'photo_preview_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _ctrl;
  bool _initialized = false;
  bool _taking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = '未找到可用相机');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _ctrl = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await _ctrl!.initialize();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = '相机初始化失败：$e');
    }
  }

  Future<void> _takePhoto() async {
    if (_ctrl == null || !_initialized || _taking) return;
    setState(() => _taking = true);
    try {
      final xfile = await _ctrl!.takePicture();
      if (!mounted) return;
      final result = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoPreviewScreen(imagePath: xfile.path),
        ),
      );
      if (result != null && mounted) {
        Navigator.pop(context, result);
      } else if (mounted) {
        setState(() => _taking = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _taking = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('拍照失败：$e')));
      }
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  color: Colors.white, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return _buildCamera(context);
  }

  Widget _buildCamera(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final frameW = size.width * 0.8;
    final frameH = size.height * 0.4;
    // Center vertically, shift up slightly to leave room for shutter button
    final frameLeft = (size.width - frameW) / 2;
    final frameTop = (size.height - frameH) / 2 - 40;
    final frame = Rect.fromLTWH(frameLeft, frameTop, frameW, frameH);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Full-screen camera preview ───────────────────────────
          Positioned.fill(child: CameraPreview(_ctrl!)),

          // ── Semi-transparent overlay + white guide frame ─────────
          Positioned.fill(
            child: CustomPaint(painter: _GuideOverlayPainter(frame)),
          ),

          // ── Guide text below frame ───────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            top: frameTop + frameH + 12,
            child: const Text(
              '请对准食物或商品标签',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
          ),

          // ── Back button ──────────────────────────────────────────
          Positioned(
            top: padding.top + 4,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // ── Shutter button ───────────────────────────────────────
          Positioned(
            bottom: padding.bottom + 32,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _taking ? null : _takePhoto,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 4,
                    ),
                  ),
                  child: _taking
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Guide overlay painter ─────────────────────────────────────────────

class _GuideOverlayPainter extends CustomPainter {
  final Rect frame;
  const _GuideOverlayPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    // Dark mask with rectangular cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(8)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    // White border
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(8)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GuideOverlayPainter old) => old.frame != frame;
}
