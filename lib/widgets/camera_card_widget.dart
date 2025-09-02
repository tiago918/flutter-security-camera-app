import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/camera_models.dart';
import '../services/recording_service.dart';

class CameraCardWidget extends StatefulWidget {
  final CameraData camera;
  final VideoPlayerController? controller;
  final bool isLoading;
  final bool isLarge;
  final VoidCallback onPlayPause;
  final RecordingService? recordingService;

  const CameraCardWidget({
    super.key,
    required this.camera,
    this.controller,
    required this.isLoading,
    required this.isLarge,
    required this.onPlayPause,
    this.recordingService,
  });

  @override
  State<CameraCardWidget> createState() => _CameraCardWidgetState();
}

class _CameraCardWidgetState extends State<CameraCardWidget> {
  bool _isRecording = false;
  late RecordingService _recordingService;

  @override
  void initState() {
    super.initState();
    _recordingService = widget.recordingService ?? RecordingService();
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        await _recordingService.stopRecording(widget.camera.id);
        setState(() {
          _isRecording = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gravação parada para ${widget.camera.name}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        await _recordingService.startRecording(widget.camera);
        setState(() {
          _isRecording = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gravação iniciada para ${widget.camera.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro na gravação: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = widget.controller?.value.isInitialized ?? false;

    return RepaintBoundary(
      key: ValueKey('camera-card-${camera.id}'),
      child: GestureDetector(
        onTap: widget.onPlayPause,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: hasVideo
                    ? AspectRatio(
                        aspectRatio: widget.controller!.value.aspectRatio > 0
                            ? widget.controller!.value.aspectRatio
                            : 16 / 9,
                        child: VideoPlayer(widget.controller!),
                      )
                    : AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF3A3A3A),
                                Color(0xFF2A2A2A),
                              ],
                            ),
                          ),
                          child: Center(
                            child: widget.isLoading
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: CircularProgressIndicator(strokeWidth: 3),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Carregando stream...',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: widget.isLarge ? 14 : 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.play_circle_outline,
                                        size: widget.isLarge ? 56 : 46,
                                        color: widget.camera.isLive ? Colors.white70 : const Color(0xFF666666),
                                      ),
                                      if (widget.isLarge) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          widget.camera.name,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                        ),
                      ),
              ),
              if (hasVideo)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isRecording ? Colors.red.withOpacity(0.8) : Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isRecording ? Icons.stop : Icons.fiber_manual_record,
                        color: _isRecording ? Colors.white : Colors.red,
                        size: 24,
                      ),
                      onPressed: _toggleRecording,
                      tooltip: _isRecording ? 'Parar gravação' : 'Iniciar gravação',
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