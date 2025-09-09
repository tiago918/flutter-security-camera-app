import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../models/camera_model.dart';
import '../models/credentials.dart';
import '../models/connection_log.dart';
import 'alternative_url_generator.dart';
import 'integrated_logging_service.dart';

enum RTSPConnectionState {
  disconnected,
  connecting,
  connected,
  streaming,
  error,
  reconnecting;

  String get displayName {
    switch (this) {
      case RTSPConnectionState.disconnected:
        return 'Desconectado';
      case RTSPConnectionState.connecting:
        return 'Conectando';
      case RTSPConnectionState.connected:
        return 'Conectado';
      case RTSPConnectionState.streaming:
        return 'Transmitindo';
      case RTSPConnectionState.error:
        return 'Erro';
      case RTSPConnectionState.reconnecting:
        return 'Reconectando';
    }
  }
}

class RTSPConnectionInfo {
  final String url;
  final RTSPConnectionState state;
  final DateTime timestamp;
  final Duration? responseTime;
  final String? error;
  final Map<String, String>? headers;
  final int? statusCode;

  const RTSPConnectionInfo({
    required this.url,
    required this.state,
    required this.timestamp,
    this.responseTime,
    this.error,
    this.headers,
    this.statusCode,
  });

  bool get isConnected => state == RTSPConnectionState.connected || state == RTSPConnectionState.streaming;
  bool get hasError => state == RTSPConnectionState.error;
}

class RTSPService {
  static final RTSPService _instance = RTSPService._internal();
  factory RTSPService() => _instance;
  RTSPService._internal();

  final IntegratedLoggingService _logger = IntegratedLoggingService();
  final AlternativeUrlGenerator _urlGenerator = AlternativeUrlGenerator();
  
  final Map<String, RTSPConnectionInfo> _connectionStates = {};
  final Map<String, StreamController<RTSPConnectionInfo>> _stateControllers = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, int> _reconnectAttempts = {};
  
  static const int _maxReconnectAttempts = 5;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);
  static const Duration _connectionTimeout = Duration(seconds: 15);

  /// Stream de estados de conexão para uma câmera específica
  Stream<RTSPConnectionInfo> getConnectionStateStream(String cameraId) {
    _stateControllers.putIfAbsent(
      cameraId,
      () => StreamController<RTSPConnectionInfo>.broadcast(),
    );
    return _stateControllers[cameraId]!.stream;
  }

  /// Obtém o estado atual da conexão
  RTSPConnectionInfo? getConnectionState(String cameraId) {
    return _connectionStates[cameraId];
  }

  /// Testa conexão RTSP com uma câmera
  Future<RTSPConnectionInfo> testConnection(
    CameraModel camera, {
    Credentials? credentials,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _connectionTimeout;
    final stopwatch = Stopwatch()..start();
    
    await _logger.info(camera.id, 'Iniciando teste de conexão RTSP');
    _updateConnectionState(camera.id, RTSPConnectionState.connecting);

    try {
      // Gera URLs alternativas
      final urls = _urlGenerator.generateAlternativeUrls(camera, credentials: credentials);
      final rtspUrls = urls.where((url) => url.url.startsWith('rtsp')).toList();
      
      if (rtspUrls.isEmpty) {
        throw Exception('Nenhuma URL RTSP disponível para teste');
      }

      // Testa URLs em ordem de prioridade
      RTSPConnectionInfo? lastResult;
      
      for (final url in rtspUrls) {
        try {
          final result = await _testSingleRtspUrl(camera.id, url.url, effectiveTimeout);
          
          if (result.isConnected) {
            stopwatch.stop();
            
            final connectionInfo = RTSPConnectionInfo(
              url: url.url,
              state: RTSPConnectionState.connected,
              timestamp: DateTime.now(),
              responseTime: stopwatch.elapsed,
            );
            
            _updateConnectionState(camera.id, RTSPConnectionState.connected, connectionInfo);
            
            await _logger.info(camera.id, 'Conexão RTSP estabelecida com sucesso', 
                details: 'URL: ${url.url}, Tempo: ${stopwatch.elapsed.inMilliseconds}ms');
            
            return connectionInfo;
          }
          
          lastResult = result;
        } catch (e) {
          await _logger.warning(camera.id, 'Falha ao testar URL RTSP: ${url.url}', 
              details: e.toString());
          continue;
        }
      }
      
      // Se chegou aqui, nenhuma URL funcionou
      stopwatch.stop();
      
      final errorInfo = RTSPConnectionInfo(
        url: rtspUrls.first.url,
        state: RTSPConnectionState.error,
        timestamp: DateTime.now(),
        responseTime: stopwatch.elapsed,
        error: lastResult?.error ?? 'Todas as URLs RTSP falharam',
      );
      
      _updateConnectionState(camera.id, RTSPConnectionState.error, errorInfo);
      
      await _logger.error(camera.id, 'Falha ao estabelecer conexão RTSP', 
          details: 'Testadas ${rtspUrls.length} URLs');
      
      return errorInfo;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorInfo = RTSPConnectionInfo(
        url: camera.connectionUrl,
        state: RTSPConnectionState.error,
        timestamp: DateTime.now(),
        responseTime: stopwatch.elapsed,
        error: e.toString(),
      );
      
      _updateConnectionState(camera.id, RTSPConnectionState.error, errorInfo);
      
      await _logger.error(camera.id, 'Erro durante teste de conexão RTSP', 
          details: e.toString());
      
      return errorInfo;
    }
  }

  /// Estabelece conexão RTSP com reconexão automática
  Future<bool> connect(
    CameraModel camera, {
    Credentials? credentials,
    bool enableAutoReconnect = true,
  }) async {
    await _logger.info(camera.id, 'Estabelecendo conexão RTSP', 
        details: 'Auto-reconexão: $enableAutoReconnect');
    
    // Cancela tentativas anteriores
    _cancelReconnectTimer(camera.id);
    _reconnectAttempts[camera.id] = 0;
    
    final result = await testConnection(camera, credentials: credentials);
    
    if (result.isConnected) {
      _updateConnectionState(camera.id, RTSPConnectionState.streaming, result);
      
      if (enableAutoReconnect) {
        _startConnectionMonitoring(camera, credentials);
      }
      
      return true;
    }
    
    if (enableAutoReconnect) {
      _scheduleReconnect(camera, credentials);
    }
    
    return false;
  }

  /// Desconecta de uma câmera
  Future<void> disconnect(String cameraId) async {
    await _logger.info(cameraId, 'Desconectando RTSP');
    
    _cancelReconnectTimer(cameraId);
    _reconnectAttempts.remove(cameraId);
    
    _updateConnectionState(cameraId, RTSPConnectionState.disconnected);
  }

  /// Força reconexão
  Future<bool> reconnect(
    CameraModel camera, {
    Credentials? credentials,
  }) async {
    await _logger.info(camera.id, 'Forçando reconexão RTSP');
    
    _updateConnectionState(camera.id, RTSPConnectionState.reconnecting);
    
    return await connect(camera, credentials: credentials);
  }

  /// Verifica se uma URL RTSP é válida
  bool isValidRtspUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'rtsp' || uri.scheme == 'rtsps';
    } catch (e) {
      return false;
    }
  }

  /// Extrai informações de uma URL RTSP
  Map<String, dynamic> parseRtspUrl(String url) {
    try {
      final uri = Uri.parse(url);
      
      return {
        'scheme': uri.scheme,
        'host': uri.host,
        'port': uri.port,
        'path': uri.path,
        'isSecure': uri.scheme == 'rtsps',
        'hasAuth': uri.userInfo.isNotEmpty,
        'username': uri.userInfo.contains(':') ? uri.userInfo.split(':')[0] : null,
        'query': uri.query,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Obtém estatísticas de conexão
  Map<String, dynamic> getConnectionStatistics(String cameraId) {
    final state = _connectionStates[cameraId];
    final attempts = _reconnectAttempts[cameraId] ?? 0;
    
    return {
      'cameraId': cameraId,
      'currentState': state?.state.name ?? 'unknown',
      'isConnected': state?.isConnected ?? false,
      'lastConnectionTime': state?.timestamp.toIso8601String(),
      'lastResponseTime': state?.responseTime?.inMilliseconds,
      'reconnectAttempts': attempts,
      'hasActiveReconnectTimer': _reconnectTimers.containsKey(cameraId),
      'lastError': state?.error,
    };
  }

  /// Obtém estatísticas globais
  Map<String, dynamic> getGlobalStatistics() {
    final totalConnections = _connectionStates.length;
    final connectedCount = _connectionStates.values
        .where((state) => state.isConnected)
        .length;
    final errorCount = _connectionStates.values
        .where((state) => state.hasError)
        .length;
    final reconnectingCount = _reconnectTimers.length;
    
    return {
      'totalConnections': totalConnections,
      'connectedCount': connectedCount,
      'errorCount': errorCount,
      'reconnectingCount': reconnectingCount,
      'connectionRate': totalConnections > 0 
          ? (connectedCount / totalConnections * 100).toStringAsFixed(2)
          : '0.00',
      'activeReconnectTimers': reconnectingCount,
    };
  }

  /// Limpa todos os estados e timers
  void dispose() {
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    
    for (final controller in _stateControllers.values) {
      controller.close();
    }
    
    _connectionStates.clear();
    _stateControllers.clear();
    _reconnectTimers.clear();
    _reconnectAttempts.clear();
  }

  // Métodos privados

  Future<RTSPConnectionInfo> _testSingleRtspUrl(
    String cameraId,
    String url,
    Duration timeout,
  ) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final uri = Uri.parse(url);
      
      // Teste básico de conectividade TCP
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: timeout,
      );
      
      // Envia comando RTSP básico
      socket.write('OPTIONS $url RTSP/1.0\r\n');
      socket.write('CSeq: 1\r\n');
      socket.write('\r\n');
      
      // Aguarda resposta
      final response = await socket.transform(utf8.decoder).first
          .timeout(const Duration(seconds: 5));
      
      await socket.close();
      stopwatch.stop();
      
      // Verifica se é uma resposta RTSP válida
      if (response.startsWith('RTSP/1.0')) {
        return RTSPConnectionInfo(
          url: url,
          state: RTSPConnectionState.connected,
          timestamp: DateTime.now(),
          responseTime: stopwatch.elapsed,
        );
      } else {
        return RTSPConnectionInfo(
          url: url,
          state: RTSPConnectionState.error,
          timestamp: DateTime.now(),
          responseTime: stopwatch.elapsed,
          error: 'Resposta RTSP inválida',
        );
      }
    } catch (e) {
      stopwatch.stop();
      return RTSPConnectionInfo(
        url: url,
        state: RTSPConnectionState.error,
        timestamp: DateTime.now(),
        responseTime: stopwatch.elapsed,
        error: e.toString(),
      );
    }
  }

  void _updateConnectionState(
    String cameraId,
    RTSPConnectionState state, [RTSPConnectionInfo? info]
  ) {
    final connectionInfo = info ?? RTSPConnectionInfo(
      url: _connectionStates[cameraId]?.url ?? '',
      state: state,
      timestamp: DateTime.now(),
    );
    
    _connectionStates[cameraId] = connectionInfo;
    
    // Emite no stream se existir
    if (_stateControllers.containsKey(cameraId)) {
      _stateControllers[cameraId]!.add(connectionInfo);
    }
  }

  void _startConnectionMonitoring(
    CameraModel camera,
    Credentials? credentials,
  ) {
    // Monitora conexão a cada 30 segundos
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      final state = _connectionStates[camera.id];
      
      if (state == null || !state.isConnected) {
        timer.cancel();
        return;
      }
      
      // Testa se ainda está conectado
      try {
        final result = await _testSingleRtspUrl(
          camera.id,
          state.url,
          const Duration(seconds: 5),
        );
        
        if (!result.isConnected) {
          await _logger.warning(camera.id, 'Conexão RTSP perdida, iniciando reconexão');
          _scheduleReconnect(camera, credentials);
          timer.cancel();
        }
      } catch (e) {
        await _logger.error(camera.id, 'Erro ao monitorar conexão RTSP', details: e.toString());
        _scheduleReconnect(camera, credentials);
        timer.cancel();
      }
    });
  }

  void _scheduleReconnect(
    CameraModel camera,
    Credentials? credentials,
  ) {
    final attempts = _reconnectAttempts[camera.id] ?? 0;
    
    if (attempts >= _maxReconnectAttempts) {
      _logger.error(camera.id, 'Máximo de tentativas de reconexão atingido');
      _updateConnectionState(camera.id, RTSPConnectionState.error);
      return;
    }
    
    _reconnectAttempts[camera.id] = attempts + 1;
    
    // Backoff exponencial
    final delay = Duration(
      seconds: _baseReconnectDelay.inSeconds * (1 << attempts),
    );
    
    _logger.info(camera.id, 'Agendando reconexão RTSP', 
        details: 'Tentativa ${attempts + 1}/$_maxReconnectAttempts em ${delay.inSeconds}s');
    
    _reconnectTimers[camera.id] = Timer(delay, () async {
      _reconnectTimers.remove(camera.id);
      
      _updateConnectionState(camera.id, RTSPConnectionState.reconnecting);
      
      final success = await connect(camera, credentials: credentials);
      
      if (!success) {
        _scheduleReconnect(camera, credentials);
      } else {
        _reconnectAttempts[camera.id] = 0;
      }
    });
  }

  void _cancelReconnectTimer(String cameraId) {
    final timer = _reconnectTimers.remove(cameraId);
    timer?.cancel();
  }
}