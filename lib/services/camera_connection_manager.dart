import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/camera_model.dart';
import '../models/credentials.dart';
import '../models/connection_log.dart';
import '../models/camera_status.dart';
import 'integrated_logging_service.dart';
import 'rtsp_service.dart';
import 'stream_player_manager.dart';
import 'alternative_url_generator.dart';
import 'credential_storage_service.dart';
import 'onvif_service.dart';

enum ConnectionMode {
  auto,
  manual,
  discovery;

  String get displayName {
    switch (this) {
      case ConnectionMode.auto:
        return 'Automático';
      case ConnectionMode.manual:
        return 'Manual';
      case ConnectionMode.discovery:
        return 'Descoberta';
    }
  }
}

class ConnectionResult {
  final bool success;
  final CameraStatus status;
  final String? streamUrl;
  final PlayerType? playerType;
  final String? error;
  final Duration? responseTime;
  final Map<String, dynamic>? metadata;

  const ConnectionResult({
    required this.success,
    required this.status,
    this.streamUrl,
    this.playerType,
    this.error,
    this.responseTime,
    this.metadata,
  });

  factory ConnectionResult.success({
    required CameraStatus status,
    String? streamUrl,
    PlayerType? playerType,
    Duration? responseTime,
    Map<String, dynamic>? metadata,
  }) {
    return ConnectionResult(
      success: true,
      status: status,
      streamUrl: streamUrl,
      playerType: playerType,
      responseTime: responseTime,
      metadata: metadata,
    );
  }

  factory ConnectionResult.failure({
    required String error,
    CameraStatus status = CameraStatus.error,
    Duration? responseTime,
  }) {
    return ConnectionResult(
      success: false,
      status: status,
      error: error,
      responseTime: responseTime,
    );
  }
}

class ConnectionTestResult {
  final String url;
  final bool isConnected;
  final Duration responseTime;
  final String? error;

  const ConnectionTestResult({
    required this.url,
    required this.isConnected,
    required this.responseTime,
    this.error,
  });
}

class CameraConnectionState {
  final String cameraId;
  final CameraStatus status;
  final ConnectionMode mode;
  final DateTime timestamp;
  final String? currentUrl;
  final PlayerType? playerType;
  final bool isStreaming;
  final String? error;
  final int reconnectAttempts;
  final Duration? lastResponseTime;

  const CameraConnectionState({
    required this.cameraId,
    required this.status,
    required this.mode,
    required this.timestamp,
    this.currentUrl,
    this.playerType,
    this.isStreaming = false,
    this.error,
    this.reconnectAttempts = 0,
    this.lastResponseTime,
  });

  CameraConnectionState copyWith({
    CameraStatus? status,
    ConnectionMode? mode,
    DateTime? timestamp,
    String? currentUrl,
    PlayerType? playerType,
    bool? isStreaming,
    String? error,
    int? reconnectAttempts,
    Duration? lastResponseTime,
  }) {
    return CameraConnectionState(
      cameraId: cameraId,
      status: status ?? this.status,
      mode: mode ?? this.mode,
      timestamp: timestamp ?? this.timestamp,
      currentUrl: currentUrl ?? this.currentUrl,
      playerType: playerType ?? this.playerType,
      isStreaming: isStreaming ?? this.isStreaming,
      error: error ?? this.error,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      lastResponseTime: lastResponseTime ?? this.lastResponseTime,
    );
  }
}

class CameraConnectionManager {
  static final CameraConnectionManager _instance = CameraConnectionManager._internal();
  factory CameraConnectionManager() => _instance;
  CameraConnectionManager._internal();

  final IntegratedLoggingService _logger = IntegratedLoggingService();
  final RTSPService _rtspService = RTSPService();
  final StreamPlayerManager _playerManager = StreamPlayerManager();
  final AlternativeUrlGenerator _urlGenerator = AlternativeUrlGenerator();
  final CredentialStorageService _credentialStorage = CredentialStorageService();
  final ONVIFService _onvifService = ONVIFService();
  
  final Map<String, CameraConnectionState> _connectionStates = {};
  final Map<String, StreamController<CameraConnectionState>> _stateControllers = {};
  final Map<String, Timer> _healthCheckTimers = {};
  final Map<String, Timer> _reconnectTimers = {};
  
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  static const Duration _reconnectBaseDelay = Duration(seconds: 5);
  static const int _maxReconnectAttempts = 10;
  
  bool _isInitialized = false;

  /// Inicializa o gerenciador de conexões
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _logger.info('system', 'Inicializando CameraConnectionManager');
    
    try {
      // Inicializa serviços dependentes
      await _credentialStorage.initialize();
      await StreamPlayerManager.initializeFVP();
      
      _isInitialized = true;
      
      await _logger.info('system', 'CameraConnectionManager inicializado com sucesso');
    } catch (e) {
      await _logger.error('system', 'Falha ao inicializar CameraConnectionManager', 
          details: e.toString());
      rethrow;
    }
  }

  /// Stream de estados de conexão para uma câmera específica
  Stream<CameraConnectionState> getConnectionStateStream(String cameraId) {
    _stateControllers.putIfAbsent(
      cameraId,
      () => StreamController<CameraConnectionState>.broadcast(),
    );
    return _stateControllers[cameraId]!.stream;
  }

  /// Obtém o estado atual da conexão
  CameraConnectionState? getConnectionState(String cameraId) {
    return _connectionStates[cameraId];
  }

  /// Conecta a uma câmera com fallback automático
  Future<ConnectionResult> connectCamera(
    CameraModel camera, {
    Credentials? credentials,
    ConnectionMode mode = ConnectionMode.auto,
    bool enableAutoReconnect = true,
    bool startStreaming = true,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    await _logger.info(camera.id, 'Iniciando conexão com câmera', 
        details: 'Modo: ${mode.displayName}, Auto-reconexão: $enableAutoReconnect');
    
    final stopwatch = Stopwatch()..start();
    
    // Cancela operações anteriores
    await _cancelOperations(camera.id);
    
    // Atualiza estado inicial
    _updateConnectionState(
      camera.id,
      CameraStatus.connecting,
      mode: mode,
    );
    
    try {
      // Obtém ou usa credenciais fornecidas
      final effectiveCredentials = credentials ?? 
          await _credentialStorage.getCredentials(camera.id);
      
      // Salva credenciais se fornecidas
      if (credentials != null) {
        await _credentialStorage.saveCredentials(camera.id, credentials);
      }
      
      ConnectionResult result;
      
      switch (mode) {
        case ConnectionMode.auto:
          result = await _connectAuto(camera, effectiveCredentials, startStreaming);
          break;
        case ConnectionMode.manual:
          result = await _connectManual(camera, effectiveCredentials, startStreaming);
          break;
        case ConnectionMode.discovery:
          result = await _connectDiscovery(camera, effectiveCredentials, startStreaming);
          break;
      }
      
      stopwatch.stop();
      
      if (result.success) {
        _updateConnectionState(
          camera.id,
          result.status,
          mode: mode,
          currentUrl: result.streamUrl,
          playerType: result.playerType,
          isStreaming: startStreaming && result.status == CameraStatus.streaming,
          lastResponseTime: stopwatch.elapsed,
        );
        
        if (enableAutoReconnect) {
          _startHealthCheck(camera, effectiveCredentials, mode, startStreaming);
        }
        
        await _logger.info(camera.id, 'Conexão estabelecida com sucesso', 
            details: 'Tempo: ${stopwatch.elapsed.inMilliseconds}ms, Status: ${result.status.displayName}');
      } else {
        _updateConnectionState(
          camera.id,
          result.status,
          mode: mode,
          error: result.error,
          lastResponseTime: stopwatch.elapsed,
        );
        
        if (enableAutoReconnect) {
          _scheduleReconnect(camera, effectiveCredentials, mode, startStreaming);
        }
        
        await _logger.error(camera.id, 'Falha na conexão', 
            details: result.error ?? 'Erro desconhecido');
      }
      
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      _updateConnectionState(
        camera.id,
        CameraStatus.error,
        mode: mode,
        error: e.toString(),
        lastResponseTime: stopwatch.elapsed,
      );
      
      await _logger.error(camera.id, 'Erro durante conexão', details: e.toString());
      
      return ConnectionResult.failure(
        error: e.toString(),
        responseTime: stopwatch.elapsed,
      );
    }
  }

  /// Desconecta uma câmera
  Future<void> disconnectCamera(String cameraId) async {
    await _logger.info(cameraId, 'Desconectando câmera');
    
    await _cancelOperations(cameraId);
    
    // Para stream se estiver ativo
    await _playerManager.stopStream(cameraId);
    
    _updateConnectionState(cameraId, CameraStatus.offline);
    
    await _logger.info(cameraId, 'Câmera desconectada');
  }

  /// Reconecta uma câmera
  Future<ConnectionResult> reconnectCamera(
    CameraModel camera, {
    Credentials? credentials,
  }) async {
    await _logger.info(camera.id, 'Forçando reconexão');
    
    final currentState = _connectionStates[camera.id];
    final mode = currentState?.mode ?? ConnectionMode.auto;
    final wasStreaming = currentState?.isStreaming ?? false;
    
    await disconnectCamera(camera.id);
    
    return await connectCamera(
      camera,
      credentials: credentials,
      mode: mode,
      startStreaming: wasStreaming,
    );
  }

  /// Inicia streaming para uma câmera já conectada
  Future<bool> startStreaming(String cameraId) async {
    final state = _connectionStates[cameraId];
    
    if (state == null || !state.status.canStream) {
      await _logger.warning(cameraId, 'Não é possível iniciar streaming no estado atual');
      return false;
    }
    
    await _logger.info(cameraId, 'Iniciando streaming');
    
    try {
      // Obtém câmera e credenciais
      final credentials = await _credentialStorage.getCredentials(cameraId);
      
      // Cria modelo temporário da câmera para o player
      final camera = CameraModel(
        id: cameraId,
        name: 'Camera $cameraId',
        ip: '', // Será resolvido pelo URL atual
        connectionUrl: state.currentUrl ?? '',
      );
      
      final success = await _playerManager.startStream(
        camera,
        credentials: credentials,
        preferredPlayer: state.playerType,
      );
      
      if (success) {
        _updateConnectionState(
          cameraId,
          CameraStatus.streaming,
          isStreaming: true,
        );
        
        await _logger.info(cameraId, 'Streaming iniciado com sucesso');
      } else {
        await _logger.error(cameraId, 'Falha ao iniciar streaming');
      }
      
      return success;
      
    } catch (e) {
      await _logger.error(cameraId, 'Erro ao iniciar streaming', details: e.toString());
      return false;
    }
  }

  /// Para streaming
  Future<void> stopStreaming(String cameraId) async {
    await _logger.info(cameraId, 'Parando streaming');
    
    await _playerManager.stopStream(cameraId);
    
    final currentState = _connectionStates[cameraId];
    if (currentState != null) {
      _updateConnectionState(
        cameraId,
        currentState.status.canStream ? CameraStatus.online : currentState.status,
        isStreaming: false,
      );
    }
  }

  /// Conecta com fallback usando URLs alternativas
  Future<ConnectionResult> connectWithFallback(
    CameraModel camera, {
    Credentials? credentials,
    bool startStreaming = false,
  }) async {
    await _logger.info(camera.id, 'Iniciando conexão com fallback');
    
    try {
      // Gera URLs alternativas
      final alternativeUrls = await _urlGenerator.generateAlternativeUrls(
        camera.ip,
        camera.port,
        credentials: credentials,
      );
      
      // Testa múltiplas URLs
      final testResults = await testMultipleUrls(
        alternativeUrls.map((url) => url.url).toList(),
        camera,
        credentials: credentials,
      );
      
      // Encontra a primeira URL que funciona
      final workingResult = testResults.firstWhere(
        (result) => result.isConnected,
        orElse: () => throw Exception('Nenhuma URL alternativa funcionou'),
      );
      
      // Atualiza o modelo da câmera com a URL que funciona
      final updatedCamera = camera.copyWith(
        rtspUrl: workingResult.url,
      );
      
      // Conecta usando a URL que funciona
      if (startStreaming) {
        final streamSuccess = await _playerManager.startStream(
          updatedCamera,
          credentials: credentials,
        );
        
        if (streamSuccess) {
          final playerState = _playerManager.getPlayerState(camera.id);
          return ConnectionResult.success(
            status: CameraStatus.streaming,
            streamUrl: workingResult.url,
            playerType: playerState?.playerType,
            responseTime: workingResult.responseTime,
          );
        }
      }
      
      return ConnectionResult.success(
        status: CameraStatus.online,
        streamUrl: workingResult.url,
        responseTime: workingResult.responseTime,
      );
      
    } catch (e) {
      await _logger.error(camera.id, 'Falha na conexão com fallback', details: e.toString());
      return ConnectionResult.failure(
        error: 'Todas as URLs alternativas falharam: ${e.toString()}',
      );
    }
  }
  
  /// Testa múltiplas URLs de conexão
  Future<List<ConnectionTestResult>> testMultipleUrls(
    List<String> urls,
    CameraModel camera, {
    Credentials? credentials,
    Duration? timeout,
  }) async {
    await _logger.info(camera.id, 'Testando ${urls.length} URLs alternativas');
    
    final results = <ConnectionTestResult>[];
    
    for (final url in urls) {
      try {
        await _logger.debug(camera.id, 'Testando URL: $url');
        
        final stopwatch = Stopwatch()..start();
        
        // Testa conexão RTSP
        final testCamera = camera.copyWith(rtspUrl: url);
        final rtspResult = await _rtspService.testConnection(
          testCamera,
          credentials: credentials,
          timeout: timeout ?? const Duration(seconds: 10),
        );
        
        stopwatch.stop();
        
        final result = ConnectionTestResult(
          url: url,
          isConnected: rtspResult.isConnected,
          responseTime: Duration(milliseconds: stopwatch.elapsedMilliseconds),
          error: rtspResult.error,
        );
        
        results.add(result);
        
        if (result.isConnected) {
          await _logger.info(camera.id, 'URL funcionando encontrada: $url');
        } else {
          await _logger.warning(camera.id, 'URL falhou: $url', details: result.error);
        }
        
      } catch (e) {
        results.add(ConnectionTestResult(
          url: url,
          isConnected: false,
          responseTime: timeout ?? const Duration(seconds: 10),
          error: e.toString(),
        ));
        
        await _logger.error(camera.id, 'Erro ao testar URL: $url', details: e.toString());
      }
    }
    
    final workingUrls = results.where((r) => r.isConnected).length;
    await _logger.info(camera.id, 'Teste concluído: $workingUrls/${urls.length} URLs funcionando');
    
    return results;
  }

  /// Descobre câmeras na rede
  Future<List<CameraModel>> discoverCameras({
    Duration? timeout,
    bool useCache = true,
  }) async {
    await _logger.info('system', 'Iniciando descoberta de câmeras');
    
    try {
      final cameras = await _onvifService.discoverCameras(
        timeout: timeout,
        useCache: useCache,
      );
      
      await _logger.info('system', 'Descoberta concluída', 
          details: '${cameras.length} câmeras encontradas');
      
      return cameras;
      
    } catch (e) {
      await _logger.error('system', 'Erro durante descoberta', details: e.toString());
      return [];
    }
  }

  /// Obtém estatísticas detalhadas
  Map<String, dynamic> getDetailedStatistics() {
    final totalCameras = _connectionStates.length;
    final onlineCameras = _connectionStates.values
        .where((state) => state.status.isConnected)
        .length;
    final streamingCameras = _connectionStates.values
        .where((state) => state.isStreaming)
        .length;
    final errorCameras = _connectionStates.values
        .where((state) => state.status == CameraStatus.error)
        .length;
    
    final playerStats = _playerManager.getGlobalStatistics();
    final rtspStats = _rtspService.getGlobalStatistics();
    
    return {
      'cameras': {
        'total': totalCameras,
        'online': onlineCameras,
        'streaming': streamingCameras,
        'error': errorCameras,
        'connectionRate': totalCameras > 0 
            ? (onlineCameras / totalCameras * 100).toStringAsFixed(2)
            : '0.00',
      },
      'players': playerStats,
      'rtsp': rtspStats,
      'healthChecks': {
        'active': _healthCheckTimers.length,
        'reconnectTimers': _reconnectTimers.length,
      },
      'services': {
        'fvpInitialized': StreamPlayerManager.isFVPAvailable,
        'credentialStorageReady': _credentialStorage.isInitialized,
        'managerInitialized': _isInitialized,
      },
    };
  }

  /// Exporta configurações e logs
  Future<Map<String, dynamic>> exportDiagnostics() async {
    final stats = getDetailedStatistics();
    final logs = await _logger.getRecentLogs(limit: 100);
    
    final connectionStates = <String, dynamic>{};
    for (final entry in _connectionStates.entries) {
      connectionStates[entry.key] = {
        'status': entry.value.status.name,
        'mode': entry.value.mode.name,
        'isStreaming': entry.value.isStreaming,
        'currentUrl': entry.value.currentUrl,
        'playerType': entry.value.playerType?.name,
        'error': entry.value.error,
        'reconnectAttempts': entry.value.reconnectAttempts,
        'lastResponseTime': entry.value.lastResponseTime?.inMilliseconds,
        'timestamp': entry.value.timestamp.toIso8601String(),
      };
    }
    
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'statistics': stats,
      'connectionStates': connectionStates,
      'recentLogs': logs.map((log) => log.toJson()).toList(),
      'version': '1.0.0',
    };
  }

  /// Limpa todos os recursos
  Future<void> dispose() async {
    await _logger.info('system', 'Finalizando CameraConnectionManager');
    
    // Cancela todos os timers
    for (final timer in _healthCheckTimers.values) {
      timer.cancel();
    }
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    
    // Finaliza players
    await _playerManager.dispose();
    
    // Finaliza serviços
    _rtspService.dispose();
    
    // Fecha streams
    for (final controller in _stateControllers.values) {
      await controller.close();
    }
    
    // Limpa estados
    _connectionStates.clear();
    _stateControllers.clear();
    _healthCheckTimers.clear();
    _reconnectTimers.clear();
    
    _isInitialized = false;
  }

  // Métodos privados

  Future<ConnectionResult> _connectAuto(
    CameraModel camera,
    Credentials? credentials,
    bool startStreaming,
  ) async {
    await _logger.info(camera.id, 'Tentando conexão automática');
    
    // 1. Tenta RTSP primeiro
    final rtspResult = await _rtspService.testConnection(camera, credentials: credentials);
    
    if (rtspResult.isConnected) {
      if (startStreaming) {
        final streamSuccess = await _playerManager.startStream(
          camera,
          credentials: credentials,
        );
        
        if (streamSuccess) {
          final playerState = _playerManager.getPlayerState(camera.id);
          return ConnectionResult.success(
            status: CameraStatus.streaming,
            streamUrl: rtspResult.url,
            playerType: playerState?.playerType,
            responseTime: rtspResult.responseTime,
          );
        } else {
          return ConnectionResult.success(
            status: CameraStatus.online,
            streamUrl: rtspResult.url,
            responseTime: rtspResult.responseTime,
          );
        }
      } else {
        return ConnectionResult.success(
          status: CameraStatus.online,
          streamUrl: rtspResult.url,
          responseTime: rtspResult.responseTime,
        );
      }
    }
    
    // 2. Tenta descoberta ONVIF
    try {
      final discoveredCameras = await _onvifService.discoverCameras(
        timeout: const Duration(seconds: 10),
      );
      
      final matchingCamera = discoveredCameras.firstWhere(
        (cam) => cam.ip == camera.ip || cam.id == camera.id,
        orElse: () => throw Exception('Câmera não encontrada via ONVIF'),
      );
      
      // Tenta conectar com a câmera descoberta
      return await _connectManual(matchingCamera, credentials, startStreaming);
      
    } catch (e) {
      await _logger.warning(camera.id, 'Descoberta ONVIF falhou', details: e.toString());
    }
    
    return ConnectionResult.failure(
      error: 'Todas as tentativas de conexão automática falharam',
    );
  }

  Future<ConnectionResult> _connectManual(
    CameraModel camera,
    Credentials? credentials,
    bool startStreaming,
  ) async {
    await _logger.info(camera.id, 'Tentando conexão manual');
    
    final rtspResult = await _rtspService.testConnection(camera, credentials: credentials);
    
    if (!rtspResult.isConnected) {
      return ConnectionResult.failure(
        error: rtspResult.error ?? 'Falha na conexão RTSP',
        responseTime: rtspResult.responseTime,
      );
    }
    
    if (startStreaming) {
      final streamSuccess = await _playerManager.startStream(
        camera,
        credentials: credentials,
      );
      
      if (streamSuccess) {
        final playerState = _playerManager.getPlayerState(camera.id);
        return ConnectionResult.success(
          status: CameraStatus.streaming,
          streamUrl: rtspResult.url,
          playerType: playerState?.playerType,
          responseTime: rtspResult.responseTime,
        );
      } else {
        return ConnectionResult.success(
          status: CameraStatus.online,
          streamUrl: rtspResult.url,
          responseTime: rtspResult.responseTime,
        );
      }
    }
    
    return ConnectionResult.success(
      status: CameraStatus.online,
      streamUrl: rtspResult.url,
      responseTime: rtspResult.responseTime,
    );
  }

  Future<ConnectionResult> _connectDiscovery(
    CameraModel camera,
    Credentials? credentials,
    bool startStreaming,
  ) async {
    await _logger.info(camera.id, 'Tentando conexão via descoberta');