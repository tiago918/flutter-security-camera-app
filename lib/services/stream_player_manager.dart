import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:fvp/fvp.dart' as fvp;
import '../models/camera_model.dart';
import 'integrated_logging_service.dart';

enum PlayerType {
  fvp,
  native,
}

enum PlayerStatus {
  initializing,
  ready,
  playing,
  paused,
  error,
  disposed,
}

class PlayerError {
  final String code;
  final String message;
  final String? details;

  PlayerError({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'PlayerError(code: $code, message: $message, details: $details)';
}

class StreamPlayerManager {
  static final StreamPlayerManager _instance = StreamPlayerManager._internal();
  factory StreamPlayerManager() => _instance;
  StreamPlayerManager._internal();

  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, StreamController<PlayerStatus>> _statusStreams = {};
  final Map<String, PlayerStatus> _currentStatus = {};
  final IntegratedLoggingService _logger = IntegratedLoggingService();
  bool _fvpInitialized = false;

  /// Inicializa o FVP plugin
  Future<void> initializeFVP() async {
    if (_fvpInitialized) return;
    
    try {
      fvp.registerWith(options: {
        'platforms': ['windows', 'linux', 'macos', 'android', 'ios'],
        'video.decoders': ['FFmpeg'],
        'logLevel': 'Info',
      });
      _fvpInitialized = true;
      _logger.logInfo('StreamPlayerManager', 'FVP plugin inicializado com sucesso');
    } catch (e) {
      _logger.logError('StreamPlayerManager', 'Erro ao inicializar FVP: $e');
      rethrow;
    }
  }

  /// Seleciona o player ótimo baseado na URL do stream
  Future<PlayerType> selectOptimalPlayer(String streamUrl) async {
    try {
      _logger.logInfo('StreamPlayerManager', 'Selecionando player ótimo para URL: $streamUrl');
      
      // Inicializa FVP se necessário
      await initializeFVP();
      
      // Para streams RTSP, prefere FVP
      if (streamUrl.toLowerCase().startsWith('rtsp://')) {
        _logger.logInfo('StreamPlayerManager', 'Stream RTSP detectado, selecionando FVP');
        return PlayerType.fvp;
      }
      
      // Para outros tipos, usa player nativo
      _logger.logInfo('StreamPlayerManager', 'Stream não-RTSP detectado, selecionando player nativo');
      return PlayerType.native;
    } catch (e) {
      _logger.logError('StreamPlayerManager', 'Erro ao selecionar player: $e');
      // Fallback para player nativo em caso de erro
      return PlayerType.native;
    }
  }

  /// Inicializa o player com logs detalhados
  Future<void> initializePlayerWithLogs(String cameraId, String streamUrl) async {
    try {
      _logger.logConnectionAttempt(cameraId, streamUrl, 'RTSP');
      _updatePlayerStatus(cameraId, PlayerStatus.initializing);
      
      // Seleciona o player ótimo
      final playerType = await selectOptimalPlayer(streamUrl);
      _logger.logPlayerInitialization(cameraId, playerType, 'Iniciando inicialização');
      
      // Dispose do controller anterior se existir
      await _disposeController(cameraId);
      
      // Cria novo controller
      final controller = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
      _controllers[cameraId] = controller;
      
      // Configura listeners de erro
      controller.addListener(() {
        if (controller.value.hasError) {
          final error = PlayerError(
            code: 'PLAYER_ERROR',
            message: 'Erro no player de vídeo',
            details: controller.value.errorDescription,
          );
          handlePlayerError(cameraId, error);
        }
      });
      
      // Inicializa o controller
      await controller.initialize();
      
      _logger.logPlayerInitialization(cameraId, playerType, 'Inicialização concluída com sucesso');
      _updatePlayerStatus(cameraId, PlayerStatus.ready);
      
    } catch (e) {
      _logger.logError('StreamPlayerManager', 'Erro na inicialização do player para câmera $cameraId: $e');
      final error = PlayerError(
        code: 'INITIALIZATION_ERROR',
        message: 'Falha na inicialização do player',
        details: e.toString(),
      );
      handlePlayerError(cameraId, error);
      rethrow;
    }
  }

  /// Retorna stream de status do player
  Stream<PlayerStatus> getPlayerStatusStream(String cameraId) {
    if (!_statusStreams.containsKey(cameraId)) {
      _statusStreams[cameraId] = StreamController<PlayerStatus>.broadcast();
    }
    return _statusStreams[cameraId]!.stream;
  }

  /// Trata erros do player
  Future<void> handlePlayerError(String cameraId, PlayerError error) async {
    try {
      _logger.logError('StreamPlayerManager', 'Erro no player da câmera $cameraId: $error');
      _updatePlayerStatus(cameraId, PlayerStatus.error);
      
      // Tenta recuperação automática para alguns tipos de erro
      if (error.code == 'NETWORK_ERROR' || error.code == 'TIMEOUT_ERROR') {
        _logger.logInfo('StreamPlayerManager', 'Tentando recuperação automática para câmera $cameraId');
        
        // Aguarda um pouco antes de tentar novamente
        await Future.delayed(const Duration(seconds: 2));
        
        // Aqui poderia implementar lógica de retry
        // Por enquanto, apenas loga a tentativa
        _logger.logInfo('StreamPlayerManager', 'Recuperação automática iniciada para câmera $cameraId');
      }
    } catch (e) {
      _logger.logError('StreamPlayerManager', 'Erro ao tratar erro do player: $e');
    }
  }

  /// Inicia reprodução do stream
  Future<void> playStream(String cameraId) async {
    try {
      final controller = _controllers[cameraId];
      if (controller != null && controller.value.isInitialized) {
        await controller.play();
        _updatePlayerStatus(cameraId, PlayerStatus.playing);
        _logger.logInfo('StreamPlayerManager', 'Reprodução iniciada para câmera $cameraId');
      }
    } catch (e) {
      _logger.logError('StreamPlayerManager', 'Erro ao iniciar reprodução: $e');
      final error = PlayerError(
        code: 'PLAY_ERROR',
        message: 'Erro ao iniciar reprodução',
        details: e.toString(),
      );
      handlePlayerError(cameraId, error);
    }
  }

  /// Pausa reprodução do stream
  Future<void> pauseStream(String cameraId) async {
    try {
      final controller = _controllers[cameraId];
      if (controller != null && controller.value.isInitialized) {
        await controller.pause();
        _updatePlayerStatus(cameraId, PlayerStatus.paused);
        _logger.logInfo('StreamPlayerManager', 'Reprodução pausada para câmera $cameraId');
      }
    } catch (e) {
      _logger.logError('StreamPlayerManager', 'Erro ao pausar reprodução: $e');
    }
  }

  /// Obtém controller do player
  VideoPlayerController? getController(String cameraId) {
    return _controllers[cameraId];
  }

  /// Obtém status atual do player
  PlayerStatus? getCurrentStatus(String cameraId) {
    return _currentStatus[cameraId];
  }

  /// Dispose de um controller específico
  Future<void> _disposeController(String cameraId) async {
    final controller = _controllers[cameraId];
    if (controller != null) {
      try {
        await controller.dispose();
        _controllers.remove(cameraId);
        _updatePlayerStatus(cameraId, PlayerStatus.disposed);
        _logger.logInfo('StreamPlayerManager', 'Controller disposed para câmera $cameraId');
      } catch (e) {
        _logger.logError('StreamPlayerManager', 'Erro ao fazer dispose do controller: $e');
      }
    }
  }

  /// Dispose de todos os controllers
  Future<void> disposeAll() async {
    final cameraIds = List<String>.from(_controllers.keys);
    for (final cameraId in cameraIds) {
      await _disposeController(cameraId);
    }
    
    // Fecha todos os streams de status
    for (final stream in _statusStreams.values) {
      await stream.close();
    }
    _statusStreams.clear();
    _currentStatus.clear();
    
    _logger.logInfo('StreamPlayerManager', 'Todos os controllers foram disposed');
  }

  /// Atualiza status do player e notifica listeners
  void _updatePlayerStatus(String cameraId, PlayerStatus status) {
    _currentStatus[cameraId] = status;
    final stream = _statusStreams[cameraId];
    if (stream != null && !stream.isClosed) {
      stream.add(status);
    }
  }

  /// Dispose de um player específico
  Future<void> disposePlayer(String cameraId) async {
    await _disposeController(cameraId);
    
    // Fecha stream de status específico
    final stream = _statusStreams[cameraId];
    if (stream != null) {
      await stream.close();
      _statusStreams.remove(cameraId);
    }
    
    _currentStatus.remove(cameraId);
  }
}