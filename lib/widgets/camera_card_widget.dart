import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/camera_models.dart';
import '../models/camera_status.dart';
import '../models/connection_log.dart';
import '../services/recording_service.dart';
import '../services/camera_connection_manager.dart';
import '../services/auto_reconnection_service.dart';
import '../services/logging_service.dart';

class CameraCardWidget extends StatefulWidget {
  final CameraData camera;
  final VideoPlayerController? controller;
  final bool isLoading;
  final bool isLarge;
  final VoidCallback onPlayPause;
  final RecordingService? recordingService;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final CameraConnectionManager? connectionManager;
  final AutoReconnectionService? reconnectionService;

  const CameraCardWidget({
    super.key,
    required this.camera,
    this.controller,
    required this.isLoading,
    required this.isLarge,
    required this.onPlayPause,
    this.recordingService,
    this.onEdit,
    this.onRemove,
    this.connectionManager,
    this.reconnectionService,
  });

  @override
  State<CameraCardWidget> createState() => _CameraCardWidgetState();
}

class _CameraCardWidgetState extends State<CameraCardWidget> with TickerProviderStateMixin {
  bool _isRecording = false;
  late RecordingService _recordingService;
  late CameraConnectionManager _connectionManager;
  late AutoReconnectionService _reconnectionService;
  late LoggingService _loggingService;
  
  CameraStatus _connectionStatus = CameraStatus.offline;
  String _statusMessage = '';
  bool _isReconnecting = false;
  int _reconnectionAttempts = 0;
  
  late AnimationController _pulseController;
  late AnimationController _reconnectController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _reconnectAnimation;

  @override
  void initState() {
    super.initState();
    _recordingService = widget.recordingService ?? RecordingService();
    _connectionManager = widget.connectionManager ?? CameraConnectionManager();
    _reconnectionService = widget.reconnectionService ?? AutoReconnectionService();
    _loggingService = LoggingService.instance;
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _reconnectController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _reconnectAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _reconnectController, curve: Curves.easeInOut),
    );
    
    _initializeConnection();
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _reconnectController.dispose();
    super.dispose();
  }
  
  Future<void> _initializeConnection() async {
    await _loggingService.initialize();
    await _connectionManager.initialize();
    await _reconnectionService.initialize();
    
    // Monitor connection status
    _connectionManager.connectionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _connectionStatus = _mapConnectionStateToStatus(state.status);
          _statusMessage = state.message;
        });
      }
    });
    
    // Monitor reconnection attempts
    _reconnectionService.reconnectionStream.listen((session) {
      if (mounted && session.cameraId == widget.camera.id.toString()) {
        setState(() {
          _isReconnecting = session.state == ReconnectionState.attempting;
          _reconnectionAttempts = session.attemptCount;
        });
        
        if (_isReconnecting) {
          _reconnectController.repeat();
        } else {
          _reconnectController.stop();
        }
      }
    });
  }
  
  CameraStatus _mapConnectionStateToStatus(String status) {
    switch (status.toLowerCase()) {
      case 'connected':
        return CameraStatus.online;
      case 'connecting':
        return CameraStatus.connecting;
      case 'streaming':
        return CameraStatus.streaming;
      case 'recording':
        return CameraStatus.recording;
      case 'error':
        return CameraStatus.error;
      case 'maintenance':
        return CameraStatus.maintenance;
      default:
        return CameraStatus.offline;
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        await _recordingService.stopRecording(widget.camera.id.toString());
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
        await _recordingService.startRecording(widget.camera.id.toString());
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

  Widget _buildConnectionStatusIndicator() {
    Color statusColor;
    IconData statusIcon;
    
    switch (_connectionStatus) {
      case CameraStatus.online:
        statusColor = Colors.green;
        statusIcon = Icons.wifi;
        break;
      case CameraStatus.connecting:
        statusColor = Colors.orange;
        statusIcon = Icons.wifi_tethering;
        break;
      case CameraStatus.streaming:
        statusColor = Colors.blue;
        statusIcon = Icons.play_circle_filled;
        break;
      case CameraStatus.recording:
        statusColor = Colors.red;
        statusIcon = Icons.fiber_manual_record;
        break;
      case CameraStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case CameraStatus.maintenance:
        statusColor = Colors.yellow;
        statusIcon = Icons.build;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.wifi_off;
    }
    
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(_connectionStatus == CameraStatus.connecting ? _pulseAnimation.value : 0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                statusIcon,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                _connectionStatus.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildReconnectionIndicator() {
    if (!_isReconnecting) return const SizedBox.shrink();
    
    return AnimatedBuilder(
      animation: _reconnectAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(
                angle: _reconnectAnimation.value * 2 * 3.14159,
                child: const Icon(
                  Icons.refresh,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Reconectando... ($_reconnectionAttempts)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = widget.controller?.value.isInitialized ?? false;

    return RepaintBoundary(
      key: ValueKey('camera-${widget.camera.id}'),
      child: GestureDetector(
        onTap: widget.onPlayPause,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(15),
            border: _connectionStatus == CameraStatus.error 
                ? Border.all(color: Colors.red.withOpacity(0.5), width: 2)
                : _connectionStatus == CameraStatus.connecting
                    ? Border.all(color: Colors.orange.withOpacity(0.5), width: 2)
                    : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
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
                            child: widget.isLoading || _connectionStatus == CameraStatus.connecting
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AnimatedBuilder(
                                        animation: _pulseAnimation,
                                        builder: (context, child) {
                                          return Transform.scale(
                                            scale: _pulseAnimation.value,
                                            child: const SizedBox(
                                              width: 32,
                                              height: 32,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _connectionStatus == CameraStatus.connecting 
                                            ? 'Conectando...' 
                                            : 'Carregando stream...',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: widget.isLarge ? 14 : 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (_statusMessage.isNotEmpty) ..[
                                        const SizedBox(height: 4),
                                        Text(
                                          _statusMessage,
                                          style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: widget.isLarge ? 11 : 10,
                                            fontWeight: FontWeight.w400,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
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
                      color: _isRecording ? Colors.red.withValues(alpha: 0.8) : Colors.black.withValues(alpha: 0.6),
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
              // Status indicators
              Positioned(
                top: 8,
                left: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildConnectionStatusIndicator(),
                    if (_isReconnecting) ..[
                      const SizedBox(height: 4),
                      _buildReconnectionIndicator(),
                    ],
                  ],
                ),
              ),
              // Botões de editar e remover
              if (widget.onEdit != null || widget.onRemove != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onEdit != null)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                            onPressed: widget.onEdit,
                            tooltip: 'Editar câmera',
                          ),
                        ),
                      if (widget.onEdit != null && widget.onRemove != null)
                        const SizedBox(width: 4),
                      if (widget.onRemove != null)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: widget.onRemove,
                            tooltip: 'Remover câmera',
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
}