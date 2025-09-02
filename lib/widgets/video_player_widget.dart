import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/camera_models.dart';
import '../services/onvif_playback_service.dart';

/// Widget para reprodução de vídeos gravados das câmeras
class VideoPlayerWidget extends StatefulWidget {
  final CameraData camera;
  final RecordingInfo recording;
  final String? localVideoPath;

  const VideoPlayerWidget({
    super.key,
    required this.camera,
    required this.recording,
    this.localVideoPath,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  final OnvifPlaybackService _playbackService = OnvifPlaybackService(acceptSelfSigned: widget.camera.acceptSelfSigned);
  
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _isControlsVisible = true;
  bool _isPlaying = false;
  bool _isMuted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = null;
      });

      String? videoPath = widget.localVideoPath;
      
      // Se não temos um arquivo local, tentar obter URL de playback ou baixar
      if (videoPath == null) {
        // Primeiro, tentar obter URL de playback RTSP
        final playbackUrl = await _playbackService.getPlaybackUrl(
          widget.camera,
          widget.recording,
        );
        
        if (playbackUrl != null) {
          videoPath = playbackUrl;
        } else {
          // Se não conseguiu URL de playback, tentar baixar o arquivo
          final tempDir = Directory.systemTemp;
          final tempPath = '${tempDir.path}/temp_${widget.recording.id}.mp4';
          
          final success = await _playbackService.downloadRecording(
            widget.camera,
            widget.recording,
            tempPath,
          );
          
          if (success) {
            videoPath = tempPath;
          }
        }
      }

      if (videoPath == null || videoPath.isEmpty) {
        throw Exception('Não foi possível obter o vídeo para reprodução');
      }

      // Inicializar o player
      if (videoPath.startsWith('http') || videoPath.startsWith('rtsp')) {
        // URL de rede
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoPath));
      } else {
        // Arquivo local
        _controller = VideoPlayerController.file(File(videoPath));
      }

      await _controller!.initialize();
      
      _controller!.addListener(_videoListener);
      
      setState(() {
        _isLoading = false;
        _duration = _controller!.value.duration;
      });
      
      // Auto-play
      _controller!.play();
      setState(() {
        _isPlaying = true;
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
      print('VideoPlayer: Error initializing player: $e');
    }
  }

  void _videoListener() {
    if (_controller != null && mounted) {
      setState(() {
        _position = _controller!.value.position;
        _isPlaying = _controller!.value.isPlaying;
      });
    }
  }

  void _togglePlayPause() {
    if (_controller != null) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    }
  }

  void _toggleMute() {
    if (_controller != null) {
      final newVolume = _isMuted ? 1.0 : 0.0;
      _controller!.setVolume(newVolume);
      setState(() {
        _isMuted = !_isMuted;
      });
    }
  }

  void _seekTo(Duration position) {
    if (_controller != null) {
      _controller!.seekTo(position);
    }
  }

  void _toggleControls() {
    setState(() {
      _isControlsVisible = !_isControlsVisible;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.recording.filename),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: _buildVideoPlayer(),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Carregando vídeo...',
            style: TextStyle(color: Colors.white),
          ),
        ],
      );
    }

    if (_hasError) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Erro ao carregar vídeo',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Erro desconhecido',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _initializePlayer,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video player
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
          
          // Controls overlay
          if (_isControlsVisible)
            _buildControlsOverlay(),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
          color: Colors.black.withValues(alpha: 0.3),
      child: Column(
        children: [
          // Top info bar
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.camera.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Gravação: ${widget.recording.startTime.day.toString().padLeft(2, '0')}/${widget.recording.startTime.month.toString().padLeft(2, '0')}/${widget.recording.startTime.year} ${widget.recording.startTime.hour.toString().padLeft(2, '0')}:${widget.recording.startTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Center play/pause button
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _togglePlayPause,
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
          
          const Spacer(),
          
          // Bottom controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Progress bar
                Row(
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _duration.inMilliseconds > 0
                              ? _position.inMilliseconds / _duration.inMilliseconds
                              : 0.0,
                          onChanged: (value) {
                            final position = Duration(
                              milliseconds: (value * _duration.inMilliseconds).round(),
                            );
                            _seekTo(position);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _toggleMute,
                      icon: Icon(
                        _isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      onPressed: _togglePlayPause,
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      onPressed: () {
                        // Implementar fullscreen se necessário
                      },
                      icon: const Icon(
                        Icons.fullscreen,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}