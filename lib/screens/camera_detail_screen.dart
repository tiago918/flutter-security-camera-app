import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../widgets/camera_card/camera_card_widgets.dart';
import '../widgets/dialogs/dialogs.dart';
import '../widgets/live_stream_player.dart';

class CameraDetailScreen extends StatefulWidget {
  final CameraModel camera;
  
  const CameraDetailScreen({
    super.key,
    required this.camera,
  });

  @override
  State<CameraDetailScreen> createState() => _CameraDetailScreenState();
}

class _CameraDetailScreenState extends State<CameraDetailScreen>
    with TickerProviderStateMixin {
  final CameraService _cameraService = CameraService();
  final PTZService _ptzService = PTZService();
  final RecordingService _recordingService = RecordingService();
  final NotificationService _notificationService = NotificationService();
  
  late AnimationController _controlsAnimationController;
  late AnimationController _loadingAnimationController;
  
  late CameraModel _camera;
  bool _isFullscreen = false;
  bool _showControls = true;
  bool _isLoading = false;
  bool _isRecording = false;
  bool _isMuted = false;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _camera = widget.camera;
    _initializeAnimations();
    _loadCameraStream();
    _setupAutoHideControls();
  }
  
  void _initializeAnimations() {
    _controlsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _loadingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    _controlsAnimationController.forward();
  }
  
  Future<void> _loadCameraStream() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      
      // All cameras (IP, ONVIF, RTSP) will use RTSP protocol directly
      // Proprietary protocol should only be used for specific camera types
      // and only after successful connection for accessing settings and recorded videos
      setState(() {
        _isLoading = false;
        // Keep existing status or set to online if it was offline
        final newStatus = _camera.status == CameraStatus.offline 
            ? CameraStatus.online 
            : _camera.status;
        _camera = _camera.copyWith(status: newStatus);
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erro ao conectar: $e';
        _camera = _camera.copyWith(status: CameraStatus.error);
      });
    }
  }
  
  void _setupAutoHideControls() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showControls) {
        _hideControls();
      }
    });
  }
  
  void _showControlsMethod() {
    if (!_showControls) {
      setState(() => _showControls = true);
      _controlsAnimationController.forward();
      _setupAutoHideControls();
    }
  }
  
  void _hideControls() {
    if (_showControls && !_isFullscreen) {
      setState(() => _showControls = false);
      _controlsAnimationController.reverse();
    }
  }
  
  void _toggleControls() {
    if (_showControls) {
      _hideControls();
    } else {
      _showControlsMethod();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isFullscreen ? _buildFullscreenView() : _buildNormalView(),
    );
  }
  
  Widget _buildNormalView() {
    return SafeArea(
      child: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _buildVideoPlayer(),
          ),
          _buildBottomControls(),
        ],
      ),
    );
  }
  
  Widget _buildFullscreenView() {
    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        children: [
          _buildVideoPlayer(),
          if (_showControls) ..[
            _buildFullscreenAppBar(),
            _buildFullscreenControls(),
          ],
        ],
      ),
    );
  }
  
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _camera.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _camera.ipAddress,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _buildStatusIndicator(),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showCameraMenu,
          ),
        ],
      ),
    );
  }
  
  Widget _buildFullscreenAppBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _controlsAnimationController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, -60 * (1 - _controlsAnimationController.value)),
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                    onPressed: _exitFullscreen,
                  ),
                  Expanded(
                    child: Text(
                      _camera.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed: _showCameraMenu,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildStatusIndicator() {
    Color statusColor;
    IconData statusIcon;
    
    switch (_camera.status) {
      case CameraStatus.online:
        statusColor = Colors.green;
        statusIcon = Icons.circle;
        break;
      case CameraStatus.offline:
        statusColor = Colors.grey;
        statusIcon = Icons.circle;
        break;
      case CameraStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case CameraStatus.recording:
        statusColor = Colors.red;
        statusIcon = Icons.fiber_manual_record;
        break;
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          statusIcon,
          color: statusColor,
          size: 12,
        ),
        const SizedBox(width: 4),
        Text(
          _camera.status.name.toUpperCase(),
          style: TextStyle(
            color: statusColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildVideoPlayer() {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // Placeholder para o player de vídeo
          Center(
            child: _isLoading
                ? _buildLoadingIndicator()
                : _errorMessage != null
                    ? _buildErrorState()
                    : _buildVideoStream(),
          ),
          
          // Controles sobrepostos
          if (!_isFullscreen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleControls,
                child: Container(color: Colors.transparent),
              ),
            ),
          
          // Player controls
          if (_showControls && !_isFullscreen)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controlsAnimationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _controlsAnimationController.value,
                    child: PlayerControls(
                      camera: _camera,
                      isRecording: _isRecording,
                      isMuted: _isMuted,
                      onSnapshot: _takeSnapshot,
                      onRecord: _toggleRecording,
                      onMute: _toggleMute,
                      onFullscreen: _enterFullscreen,
                      onPTZ: _showPTZControls,
                      onNightMode: _showNightModeDialog,
                      onSettings: _showCameraSettings,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildLoadingIndicator() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _loadingAnimationController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _loadingAnimationController.value * 2 * 3.14159,
              child: const Icon(
                Icons.videocam,
                size: 64,
                color: Colors.white54,
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'Conectando à câmera...',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
  
  Widget _buildErrorState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.error_outline,
          size: 64,
          color: Colors.red,
        ),
        const SizedBox(height: 16),
        Text(
          _errorMessage!,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _loadCameraStream,
          icon: const Icon(Icons.refresh),
          label: const Text('Tentar Novamente'),
        ),
      ],
    );
  }
  
  Widget _buildVideoStream() {
    // Construir URL do stream RTSP da câmera
    final streamUrl = _buildStreamUrl();
    
    if (streamUrl == null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.red.withOpacity(0.3),
              Colors.orange.withOpacity(0.3),
            ],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
              SizedBox(height: 8),
              Text(
                'Erro na Configuração',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Não foi possível construir URL do stream',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    print('--- DIAGNÓSTICO: Tentando renderizar LiveStreamPlayer com URL: $streamUrl ---');
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.black,
      ),
      child: LiveStreamPlayer(
        camera: _camera,
        streamUrl: streamUrl,
        preferredPlayer: LivePlayerType.fvp, // Usar FVP para melhor compatibilidade RTSP
        enableAutoReconnect: true,
        maxReconnectAttempts: 5,
        reconnectDelay: const Duration(seconds: 3),
        onPlayerStateChanged: (state) {
          // Callback para mudanças de estado do player
          print('Live stream state changed: $state');
        },
        onError: (error) {
          // Callback para erros do player
          print('Live stream error: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro no stream: $error'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
      ),
    );
  }

  /// Constrói a URL do stream RTSP da câmera
  String? _buildStreamUrl() {
    try {
      final camera = _camera;
      
      // Verificar se temos as informações necessárias
      if (camera.ipAddress.isEmpty) {
        print('Erro: IP da câmera não definido');
        return null;
      }

      // Usar o método connectionUrl do CameraModel que já constrói a URL corretamente
      final connectionUrl = camera.connectionUrl;
      print('URL do stream construída: $connectionUrl');
      
      // Validate that this is actually an RTSP URL
      if (!connectionUrl.startsWith('rtsp://') && !connectionUrl.startsWith('rtsps://')) {
        print('Erro: URL não é RTSP válida: $connectionUrl');
        return null;
      }
      
      return connectionUrl;
      
    } catch (e) {
      print('Erro ao construir URL do stream: $e');
      return null;
    }
  }
  
  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Qualidade: ${_camera.streamConfig.quality}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'FPS: ${_camera.streamConfig.fps}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
            onPressed: _toggleMute,
          ),
          IconButton(
            icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
            color: _isRecording ? Colors.red : null,
            onPressed: _toggleRecording,
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: _enterFullscreen,
          ),
        ],
      ),
    );
  }
  
  Widget _buildFullscreenControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _controlsAnimationController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, 80 * (1 - _controlsAnimationController.value)),
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildFullscreenButton(
                    Icons.camera_alt,
                    'Snapshot',
                    _takeSnapshot,
                  ),
                  _buildFullscreenButton(
                    _isRecording ? Icons.stop : Icons.fiber_manual_record,
                    _isRecording ? 'Parar' : 'Gravar',
                    _toggleRecording,
                    color: _isRecording ? Colors.red : Colors.white,
                  ),
                  _buildFullscreenButton(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    _isMuted ? 'Ativar' : 'Mudo',
                    _toggleMute,
                  ),
                  _buildFullscreenButton(
                    Icons.control_camera,
                    'PTZ',
                    _showPTZControls,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildFullscreenButton(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    Color color = Colors.white,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: color),
          onPressed: onPressed,
          iconSize: 28,
        ),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
  
  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _showControls();
  }
  
  void _exitFullscreen() {
    setState(() => _isFullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _showControls();
  }
  
  void _takeSnapshot() {
    HapticFeedback.lightImpact();
    // TODO: Implementar captura de snapshot
    _showSnackBar('Snapshot capturado', Icons.camera_alt);
  }
  
  void _toggleRecording() {
    setState(() => _isRecording = !_isRecording);
    HapticFeedback.mediumImpact();
    
    if (_isRecording) {
      _recordingService.startRecording(_camera.id);
      _showSnackBar('Gravação iniciada', Icons.fiber_manual_record, Colors.red);
    } else {
      _recordingService.stopRecording(_camera.id);
      _showSnackBar('Gravação parada', Icons.stop);
    }
  }
  
  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    HapticFeedback.lightImpact();
    
    _showSnackBar(
      _isMuted ? 'Áudio desativado' : 'Áudio ativado',
      _isMuted ? Icons.volume_off : Icons.volume_up,
    );
  }
  
  void _showPTZControls() {
    showDialog(
      context: context,
      builder: (context) => PTZControlDialog(camera: _camera),
    );
  }
  
  void _showNightModeDialog() {
    showDialog(
      context: context,
      builder: (context) => NightModeDialog(camera: _camera),
    );
  }
  
  void _showCameraSettings() {
    // TODO: Implementar configurações da câmera
    _showSnackBar('Configurações em desenvolvimento', Icons.settings);
  }
  
  void _showCameraMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => CameraOptionsMenu(
        camera: _camera,
        onEdit: () {
          Navigator.pop(context);
          _showSnackBar('Edição em desenvolvimento', Icons.edit);
        },
        onReload: () {
          Navigator.pop(context);
          _loadCameraStream();
        },
        onRemove: () {
          Navigator.pop(context);
          _showRemoveConfirmation();
        },
      ),
    );
  }
  
  void _showRemoveConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Câmera'),
        content: Text(
          'Tem certeza que deseja remover a câmera "${_camera.name}"?\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              _showSnackBar('Câmera removida', Icons.delete, Colors.red);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }
  
  void _showSnackBar(String message, IconData icon, [Color? color]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: color ?? Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  @override
  void dispose() {
    _controlsAnimationController.dispose();
    _loadingAnimationController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
}