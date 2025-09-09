import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/camera_state_service.dart';
import '../models/camera_models.dart';

class VideoControlsWidget extends StatefulWidget {
  final CameraData camera;
  final VoidCallback? onFullscreen;
  final VoidCallback? onSnapshot;
  final VoidCallback? onRecord;
  final VoidCallback? onSettings;

  const VideoControlsWidget({
    super.key,
    required this.camera,
    this.onFullscreen,
    this.onSnapshot,
    this.onRecord,
    this.onSettings,
  });

  @override
  State<VideoControlsWidget> createState() => _VideoControlsWidgetState();
}

class _VideoControlsWidgetState extends State<VideoControlsWidget> {
  final CameraStateService _stateService = CameraStateService();
  bool _showControls = true;

  late StreamSubscription _stateSubscription;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _stateService.stateChanged.listen((cameraId) {
      if (cameraId == widget.camera.id.toString() && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _stateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _stateService.getVideoController(widget.camera.id.toString());
    final isPlaying = _stateService.isPlaying(widget.camera.id.toString());
    final isLoading = _stateService.isLoading(widget.camera.id.toString());
    final error = _stateService.getError(widget.camera.id.toString());
    final isConnected = _stateService.isConnected(widget.camera.id.toString());
    final isRecording = _stateService.isRecording(widget.camera.id.toString());

    return GestureDetector(
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Stack(
          children: [
            // Vídeo player
            if (controller != null && controller.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              )
            else if (isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              )
            else if (error != null)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Erro de conexão',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      error,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _reconnect(),
                      child: const Text('Reconectar'),
                    ),
                  ],
                ),
              )
            else
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam_off,
                      color: Colors.white54,
                      size: 48,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Câmera desconectada',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),

            // Indicador de status de conexão
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isConnected ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isConnected ? Icons.wifi : Icons.wifi_off,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isConnected ? 'Online' : 'Offline',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Indicador de gravação
            if (isRecording)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fiber_manual_record,
                        color: Colors.white,
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'REC',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Controles de vídeo
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Barra de progresso do vídeo
                      if (controller != null && controller.value.isInitialized)
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.white,
                            bufferedColor: Colors.white30,
                            backgroundColor: Colors.white10,
                          ),
                        ),
                      
                      const SizedBox(height: 8),
                      
                      // Botões de controle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Play/Pause
                          IconButton(
                            onPressed: isConnected ? _togglePlayPause : null,
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: isConnected ? Colors.white : Colors.white54,
                              size: 32,
                            ),
                          ),
                          
                          // Snapshot
                          IconButton(
                            onPressed: isConnected ? widget.onSnapshot : null,
                            icon: Icon(
                              Icons.camera_alt,
                              color: isConnected ? Colors.white : Colors.white54,
                              size: 24,
                            ),
                          ),
                          
                          // Record
                          IconButton(
                            onPressed: isConnected ? widget.onRecord : null,
                            icon: Icon(
                              isRecording ? Icons.stop : Icons.fiber_manual_record,
                              color: isConnected 
                                  ? (isRecording ? Colors.red : Colors.white)
                                  : Colors.white54,
                              size: 24,
                            ),
                          ),
                          
                          // Fullscreen
                          IconButton(
                            onPressed: isConnected ? widget.onFullscreen : null,
                            icon: Icon(
                              Icons.fullscreen,
                              color: isConnected ? Colors.white : Colors.white54,
                              size: 24,
                            ),
                          ),
                          
                          // Settings
                          IconButton(
                            onPressed: widget.onSettings,
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _togglePlayPause() {
    final isPlaying = _stateService.isPlaying(widget.camera.id.toString());
    if (isPlaying) {
      _stateService.pauseVideo(widget.camera.id.toString());
    } else {
      _stateService.playVideo(widget.camera.id.toString());
    }
  }

  void _reconnect() {
    _stateService.initializeVideoController(
      widget.camera.id.toString(),
      widget.camera.streamUrl,
    );
  }
}

/// Widget para controles de vídeo em tela cheia
class FullscreenVideoControls extends StatefulWidget {
  final CameraData camera;
  final VoidCallback onExit;

  const FullscreenVideoControls({
    super.key,
    required this.camera,
    required this.onExit,
  });

  @override
  State<FullscreenVideoControls> createState() => _FullscreenVideoControlsState();
}

class _FullscreenVideoControlsState extends State<FullscreenVideoControls> {
  final CameraStateService _stateService = CameraStateService();
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _stateService.stateChanged.listen((cameraId) {
      if (cameraId == widget.camera.id.toString() && mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _stateService.getVideoController(widget.camera.id.toString());
    final isPlaying = _stateService.isPlaying(widget.camera.id.toString());

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        child: Stack(
          children: [
            // Vídeo em tela cheia
            if (controller != null && controller.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),

            // Controles em tela cheia
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: widget.onExit,
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            widget.camera.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Controles inferiores
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Barra de progresso
                        if (controller != null && controller.value.isInitialized)
                          VideoProgressIndicator(
                            controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white10,
                            ),
                          ),
                        
                        const SizedBox(height: 16),
                        
                        // Botão de play/pause centralizado
                        IconButton(
                          onPressed: _togglePlayPause,
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _togglePlayPause() {
    final isPlaying = _stateService.isPlaying(widget.camera.id.toString());
    if (isPlaying) {
      _stateService.pauseVideo(widget.camera.id.toString());
    } else {
      _stateService.playVideo(widget.camera.id.toString());
    }
  }
}