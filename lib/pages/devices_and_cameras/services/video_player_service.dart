import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/camera_models.dart';
import '../../../services/logging_service.dart';

class VideoPlayerService {
  static final VideoPlayerService _instance = VideoPlayerService._internal();
  factory VideoPlayerService() => _instance;
  VideoPlayerService._internal();

  // Maps para gerenciar estado dos players
  final Map<int, VideoPlayerController?> _controllers = {};
  final Map<int, bool> _loadingVideo = {};
  final Map<int, int> _bufferingEvents = {};
  final Map<int, int> _errorEvents = {};
  final Map<int, int> _reconnects = {};
  final Map<int, Duration> _lastKnownPosition = {};
  final Map<int, DateTime> _lastProgressAt = {};
  final Map<int, Timer?> _healthCheckTimers = {};

  // Getters para acessar o estado
  VideoPlayerController? getController(int cameraId) => _controllers[cameraId];
  bool isLoadingVideo(int cameraId) => _loadingVideo[cameraId] ?? false;
  int getBufferingEvents(int cameraId) => _bufferingEvents[cameraId] ?? 0;
  int getErrorEvents(int cameraId) => _errorEvents[cameraId] ?? 0;
  int getReconnects(int cameraId) => _reconnects[cameraId] ?? 0;
  Duration getLastKnownPosition(int cameraId) => _lastKnownPosition[cameraId] ?? Duration.zero;
  DateTime? getLastProgressAt(int cameraId) => _lastProgressAt[cameraId];

  Future<void> initializeVideoPlayer(CameraData camera, Function(int, {required bool isLive, required Color statusColor}) updateCameraStatus, {int retryCount = 0}) async {
    final playerId = 'camera_${camera.id}';
    final maxRetries = 3;
    
    // Dispose do controller anterior se existir
    await _disposeController(camera.id);
    
    _loadingVideo[camera.id] = true;
    updateCameraStatus(camera.id, isLive: false, statusColor: Colors.orange);
    
    try {
      LoggingService.instance.videoPlayer(
        'Iniciando inicialização do player (tentativa ${retryCount + 1}/${maxRetries + 1})',
        playerId: playerId,
        state: 'initializing'
      );
      
      // Valida URL antes de tentar conectar
      if (!_isValidStreamUrl(camera.streamUrl)) {
        throw Exception('URL de stream inválida: ${camera.streamUrl}');
      }
      
      // Constrói URL com credenciais se fornecidas
      String playbackUrl = _buildPlaybackUrl(camera);
      Map<String, String> headers = _buildHeaders(camera);
      
      LoggingService.instance.videoPlayer(
        'Conectando em: $playbackUrl',
        playerId: playerId,
        state: 'connecting'
      );
      
      // Cria novo controller com configurações otimizadas
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(playbackUrl),
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );
      
      _controllers[camera.id] = controller;
      
      // Adiciona listener antes da inicialização
      controller.addListener(() => _handleVideoPlayerStateChange(camera, controller, updateCameraStatus));
      
      // Inicializa com timeout aumentado e progressivo
      final timeoutDuration = Duration(seconds: 30 + (retryCount * 15)); // 30s, 45s, 60s, 75s
      
      await controller.initialize().timeout(
        timeoutDuration,
        onTimeout: () {
          throw TimeoutException('Timeout na inicialização do player após ${timeoutDuration.inSeconds}s', timeoutDuration);
        },
      );
      
      // Verifica se realmente inicializou
      if (!controller.value.isInitialized) {
        throw Exception('Controller não foi inicializado corretamente');
      }
      
      // Verifica se há erro imediatamente após inicialização
      if (controller.value.hasError) {
        throw Exception('Erro detectado após inicialização: ${controller.value.errorDescription}');
      }
      
      LoggingService.instance.videoPlayer(
        'Player inicializado com sucesso - Duração: ${controller.value.duration}, Tamanho: ${controller.value.size}',
        playerId: playerId,
        state: 'initialized'
      );
      
      // Auto-play com verificação
      await controller.play();
      
      // Aguarda um pouco para verificar se começou a reproduzir
      await Future.delayed(Duration(seconds: 2));
      
      if (controller.value.hasError) {
        throw Exception('Erro após tentar reproduzir: ${controller.value.errorDescription}');
      }
      
      // Inicia health check
      _startHealthCheck(camera, updateCameraStatus);
      
      // Reset retry count em caso de sucesso
      _reconnects[camera.id] = 0;
      
      updateCameraStatus(camera.id, isLive: true, statusColor: Colors.green);
      
      LoggingService.instance.videoPlayer(
        'Inicialização completa e reprodução iniciada',
        playerId: playerId,
        state: 'playing'
      );
      
    } catch (e) {
      LoggingService.instance.videoPlayer(
        'Erro na inicialização (tentativa ${retryCount + 1}): ${e.toString()}',
        playerId: playerId,
        state: 'initialization_error',
        isError: true
      );
      
      updateCameraStatus(camera.id, isLive: false, statusColor: Colors.red);
      
      // Retry automático se não excedeu o limite
      if (retryCount < maxRetries) {
        final delaySeconds = (retryCount + 1) * 5; // 5s, 10s, 15s
        LoggingService.instance.videoPlayer(
          'Agendando retry em ${delaySeconds}s',
          playerId: playerId,
          state: 'scheduling_retry'
        );
        
        Timer(Duration(seconds: delaySeconds), () {
          initializeVideoPlayer(camera, updateCameraStatus, retryCount: retryCount + 1);
        });
      } else {
        LoggingService.instance.videoPlayer(
          'Máximo de tentativas excedido para câmera ${camera.name}',
          playerId: playerId,
          state: 'max_retries_exceeded',
          isError: true
        );
      }
    } finally {
      _loadingVideo[camera.id] = false;
    }
  }

  void _handleVideoPlayerStateChange(CameraData camera, VideoPlayerController controller, Function(int, {required bool isLive, required Color statusColor}) updateCameraStatus) {
    if (!controller.value.isInitialized) return;

    final playerId = 'camera_${camera.id}';
    final value = controller.value;

    // Atualiza posição conhecida
    if (value.position != Duration.zero) {
      _lastKnownPosition[camera.id] = value.position;
      _lastProgressAt[camera.id] = DateTime.now();
    }

    // Verifica buffering
    if (value.isBuffering) {
      _bufferingEvents[camera.id] = (_bufferingEvents[camera.id] ?? 0) + 1;
      
      LoggingService.instance.videoPlayer(
        'Player entrando em buffering',
        playerId: playerId,
        state: 'buffering'
      );
      
      updateCameraStatus(camera.id, isLive: false, statusColor: Colors.orange);
    } else if (value.isPlaying) {
      LoggingService.instance.videoPlayer(
        'Player reproduzindo normalmente',
        playerId: playerId,
        state: 'playing_normal'
      );
      
      updateCameraStatus(camera.id, isLive: true, statusColor: Colors.green);
    }

    // Verifica erros
    if (value.hasError) {
      _errorEvents[camera.id] = (_errorEvents[camera.id] ?? 0) + 1;
      
      LoggingService.instance.videoPlayer(
        'Erro detectado no player: ${value.errorDescription}',
        playerId: playerId,
        state: 'player_error',
        isError: true
      );
      
      updateCameraStatus(camera.id, isLive: false, statusColor: Colors.red);
      
      // Tenta reconectar
      if ((_reconnects[camera.id] ?? 0) < 3) {
        _reconnects[camera.id] = (_reconnects[camera.id] ?? 0) + 1;
        Timer(Duration(seconds: 5), () {
          LoggingService.instance.videoPlayer(
            'Iniciando reconexão automática após erro',
            playerId: playerId,
            state: 'auto_reconnecting'
          );
          initializeVideoPlayer(camera, updateCameraStatus);
        });
      }
    }
    
    // Log de mudanças de estado de reprodução
    static Map<int, bool> _lastPlayingState = {};
    if (_lastPlayingState[camera.id] != value.isPlaying) {
      _lastPlayingState[camera.id] = value.isPlaying;
      
      LoggingService.instance.videoPlayer(
        value.isPlaying ? 'Reprodução iniciada' : 'Reprodução pausada',
        playerId: playerId,
        state: value.isPlaying ? 'started_playing' : 'paused_playing'
      );
    }
  }

  void _startHealthCheck(CameraData camera, Function(int, {required bool isLive, required Color statusColor}) updateCameraStatus) {
    _healthCheckTimers[camera.id]?.cancel();
    _healthCheckTimers[camera.id] = Timer.periodic(Duration(seconds: 30), (timer) {
      final controller = _controllers[camera.id];
      if (controller == null || !controller.value.isInitialized) {
        timer.cancel();
        return;
      }

      _performHealthCheck(camera, controller, updateCameraStatus);

      final lastProgress = _lastProgressAt[camera.id];
      if (lastProgress != null) {
        final timeSinceProgress = DateTime.now().difference(lastProgress);
        if (timeSinceProgress.inSeconds > 60) {
          // Sem progresso há mais de 1 minuto, reconectar
          updateCameraStatus(camera.id, isLive: false, statusColor: Colors.red);
          initializeVideoPlayer(camera, updateCameraStatus);
        }
      }
    });
  }

  void _performHealthCheck(CameraData camera, VideoPlayerController controller, Function(int, {required bool isLive, required Color statusColor}) updateCameraStatus) {
    final playerId = 'camera_${camera.id}';
    
    if (!controller.value.isInitialized) {
      LoggingService.instance.videoPlayer(
        'Health check: Player não inicializado',
        playerId: playerId,
        state: 'health_check_not_initialized'
      );
      updateCameraStatus(camera.id, isLive: false, statusColor: Colors.red);
      return;
    }

    final now = DateTime.now();
    final lastProgress = _lastProgressAt[camera.id];
    final lastPosition = _lastKnownPosition[camera.id];
    final currentPosition = controller.value.position;

    // Verifica se o vídeo está progredindo
    bool isProgressing = false;
    if (lastProgress != null && lastPosition != null) {
      final timeSinceLastProgress = now.difference(lastProgress).inSeconds;
      final positionChanged = currentPosition != lastPosition;
      
      isProgressing = positionChanged || timeSinceLastProgress < 10;
      
      LoggingService.instance.videoPlayer(
        'Health check: Progresso - Tempo desde último: ${timeSinceLastProgress}s, Posição mudou: $positionChanged',
        playerId: playerId,
        state: 'health_check_progress'
      );
    }

    // Atualiza status baseado no health check
    if (controller.value.hasError) {
      LoggingService.instance.videoPlayer(
        'Health check: Player com erro',
        playerId: playerId,
        state: 'health_check_error',
        isError: true
      );
      updateCameraStatus(camera.id, isLive: false, statusColor: Colors.red);
    } else if (controller.value.isBuffering) {
      LoggingService.instance.videoPlayer(
        'Health check: Player em buffering',
        playerId: playerId,
        state: 'health_check_buffering'
      );
      updateCameraStatus(camera.id, isLive: false, statusColor: Colors.orange);
    } else if (controller.value.isPlaying && isProgressing) {
      LoggingService.instance.videoPlayer(
        'Health check: Player funcionando normalmente',
        playerId: playerId,
        state: 'health_check_ok'
      );
      updateCameraStatus(camera.id, isLive: true, statusColor: Colors.green);
    } else {
      LoggingService.instance.videoPlayer(
        'Health check: Player com problemas de reprodução',
        playerId: playerId,
        state: 'health_check_issues'
      );
      updateCameraStatus(camera.id, isLive: false, statusColor: Colors.yellow);
    }
  }

  Future<void> stopVideoPlayer(int cameraId) async {
    await _disposeController(cameraId);
    _healthCheckTimers[cameraId]?.cancel();
    _healthCheckTimers[cameraId] = null;
    _loadingVideo[cameraId] = false;
  }

  Future<void> _disposeController(int cameraId) async {
    final controller = _controllers[cameraId];
    if (controller != null) {
      try {
        await controller.pause();
        await controller.dispose();
      } catch (e) {
        // Ignora erros de dispose
      }
      _controllers[cameraId] = null;
    }
  }

  bool _isValidStreamUrl(String url) {
    if (url.isEmpty) return false;
    
    try {
      final uri = Uri.parse(url);
      
      // Verifica se tem esquema válido
      if (!['rtsp', 'http', 'https'].contains(uri.scheme.toLowerCase())) {
        return false;
      }
      
      // Verifica se tem host
      if (uri.host.isEmpty) {
        return false;
      }
      
      // Verifica se a porta é válida (se especificada)
      if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  String _buildPlaybackUrl(CameraData camera) {
    String url = camera.streamUrl;
    
    // Se a URL não contém credenciais e temos username/password, adiciona na URL para RTSP
    if (camera.streamUrl.startsWith('rtsp://') && 
        camera.username.isNotEmpty && 
        camera.password.isNotEmpty &&
        !camera.streamUrl.contains('@')) {
      
      final uri = Uri.parse(camera.streamUrl);
      final credentials = '${Uri.encodeComponent(camera.username)}:${Uri.encodeComponent(camera.password)}';
      
      url = 'rtsp://$credentials@${uri.host}:${uri.port}${uri.path}';
      if (uri.query.isNotEmpty) {
        url += '?${uri.query}';
      }
    }
    
    return url;
  }
  
  Map<String, String> _buildHeaders(CameraData camera) {
    Map<String, String> headers = {
      'User-Agent': 'CameraApp/1.0',
      'Connection': 'keep-alive',
    };
    
    // Para HTTP/HTTPS, usa Basic Auth no header
    if ((camera.streamUrl.startsWith('http://') || camera.streamUrl.startsWith('https://')) &&
        camera.username.isNotEmpty && camera.password.isNotEmpty) {
      
      final credentials = base64Encode(utf8.encode('${camera.username}:${camera.password}'));
      headers['Authorization'] = 'Basic $credentials';
    }
    
    return headers;
  }

  String _encodeCredentials(String username, String password) {
    final credentials = '$username:$password';
    return base64Encode(utf8.encode(credentials));
  }

  String friendlyPlaybackError(String error) {
    final lowerError = error.toLowerCase();
    
    if (lowerError.contains('401') || lowerError.contains('unauthorized')) {
      return 'Credenciais inválidas. Verifique usuário e senha.';
    }
    if (lowerError.contains('404') || lowerError.contains('not found')) {
      return 'Stream não encontrado. Verifique o caminho RTSP.';
    }
    if (lowerError.contains('timeout') || lowerError.contains('timed out')) {
      return 'Timeout de conexão. Verifique a rede.';
    }
    if (lowerError.contains('connection refused') || lowerError.contains('refused')) {
      return 'Conexão recusada. Verifique IP e porta.';
    }
    if (lowerError.contains('network') || lowerError.contains('unreachable')) {
      return 'Erro de rede. Verifique conectividade.';
    }
    if (lowerError.contains('format') || lowerError.contains('codec')) {
      return 'Formato não suportado. Tente outro codec.';
    }
    
    return 'Erro de reprodução: $error';
  }

  Future<List<CameraData>> loadPersistedCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final camerasJson = prefs.getStringList('cameras') ?? [];
      
      List<CameraData> loadedCameras = [];
      
      for (String cameraJson in camerasJson) {
        try {
          final Map<String, dynamic> cameraMap = jsonDecode(cameraJson);
          final cameraData = CameraData.fromJson(cameraMap);
          
          // Migração: se não tem porta definida, usar padrão
          if (cameraData.port == 0) {
            final migratedCamera = CameraData(
              id: cameraData.id,
              name: cameraData.name,
              isLive: false,
              statusColor: Colors.grey,
              uniqueColor: cameraData.uniqueColor,
              icon: cameraData.icon,
              streamUrl: cameraData.streamUrl,
              username: cameraData.username,
              password: cameraData.password,
              port: 554, // Porta padrão RTSP
              transport: cameraData.transport.isEmpty ? 'tcp' : cameraData.transport,
              capabilities: cameraData.capabilities,
            );
            loadedCameras.add(migratedCamera);
          } else {
            loadedCameras.add(cameraData);
          }
        } catch (e) {
          print('Erro ao carregar câmera: $e');
          continue;
        }
      }
      
      return loadedCameras;
    } catch (e) {
      print('Erro ao carregar câmeras persistidas: $e');
      return [];
    }
  }

  Future<void> initializeAllCameras(List<CameraData> cameras, Function(int, {required bool isLive, required Color statusColor}) updateCameraStatus) async {
    // Inicializa players de forma escalonada para evitar sobrecarga
    for (int i = 0; i < cameras.length; i++) {
      final camera = cameras[i];
      
      // Delay escalonado
      await Future.delayed(Duration(milliseconds: i * 500));
      
      // Inicializa player
      initializeVideoPlayer(camera, updateCameraStatus);
      
      // Inicia monitoramento de eventos (se necessário)
      // _startEventMonitoring(camera);
    }
  }

  void dispose() {
    // Dispose de todos os controllers
    for (final cameraId in _controllers.keys.toList()) {
      stopVideoPlayer(cameraId);
    }
    
    // Cancela todos os timers
    for (final timer in _healthCheckTimers.values) {
      timer?.cancel();
    }
    
    // Limpa maps
    _controllers.clear();
    _loadingVideo.clear();
    _bufferingEvents.clear();
    _errorEvents.clear();
    _reconnects.clear();
    _lastKnownPosition.clear();
    _lastProgressAt.clear();
    _healthCheckTimers.clear();
  }
}