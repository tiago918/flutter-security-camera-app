import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/camera_model.dart';
import '../models/camera_status.dart';
import '../models/connection_log.dart';
import 'integrated_logging_service.dart';
import 'camera_connection_manager.dart';

enum ReconnectionState {
  idle,
  attempting,
  backing_off,
  failed,
  disabled,
}

class ReconnectionAttempt {
  final int attemptNumber;
  final DateTime timestamp;
  final Duration backoffDelay;
  final String? error;
  final bool successful;

  const ReconnectionAttempt({
    required this.attemptNumber,
    required this.timestamp,
    required this.backoffDelay,
    this.error,
    this.successful = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'attemptNumber': attemptNumber,
      'timestamp': timestamp.toIso8601String(),
      'backoffDelay': backoffDelay.inMilliseconds,
      'error': error,
      'successful': successful,
    };
  }
}

class ReconnectionConfig {
  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffMultiplier;
  final int maxAttempts;
  final Duration connectionTimeout;
  final bool enableJitter;
  final List<Duration> customDelays;

  const ReconnectionConfig({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 5),
    this.backoffMultiplier = 2.0,
    this.maxAttempts = 10,
    this.connectionTimeout = const Duration(seconds: 30),
    this.enableJitter = true,
    this.customDelays = const [],
  });

  ReconnectionConfig copyWith({
    Duration? initialDelay,
    Duration? maxDelay,
    double? backoffMultiplier,
    int? maxAttempts,
    Duration? connectionTimeout,
    bool? enableJitter,
    List<Duration>? customDelays,
  }) {
    return ReconnectionConfig(
      initialDelay: initialDelay ?? this.initialDelay,
      maxDelay: maxDelay ?? this.maxDelay,
      backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      enableJitter: enableJitter ?? this.enableJitter,
      customDelays: customDelays ?? this.customDelays,
    );
  }
}

class ReconnectionSession {
  final String cameraId;
  final DateTime startTime;
  final ReconnectionConfig config;
  final List<ReconnectionAttempt> attempts;
  
  ReconnectionState _state;
  Timer? _backoffTimer;
  Timer? _timeoutTimer;
  int _currentAttempt;
  DateTime? _lastAttemptTime;
  String? _lastError;

  ReconnectionSession({
    required this.cameraId,
    required this.config,
  }) : startTime = DateTime.now(),
       attempts = [],
       _state = ReconnectionState.idle,
       _currentAttempt = 0;

  ReconnectionState get state => _state;
  int get currentAttempt => _currentAttempt;
  DateTime? get lastAttemptTime => _lastAttemptTime;
  String? get lastError => _lastError;
  bool get isActive => _state != ReconnectionState.idle && _state != ReconnectionState.failed && _state != ReconnectionState.disabled;
  Duration get totalDuration => DateTime.now().difference(startTime);

  void _setState(ReconnectionState newState) {
    _state = newState;
  }

  void _addAttempt(ReconnectionAttempt attempt) {
    attempts.add(attempt);
    _currentAttempt = attempt.attemptNumber;
    _lastAttemptTime = attempt.timestamp;
    _lastError = attempt.error;
  }

  void dispose() {
    _backoffTimer?.cancel();
    _timeoutTimer?.cancel();
    _setState(ReconnectionState.disabled);
  }

  Map<String, dynamic> toJson() {
    return {
      'cameraId': cameraId,
      'startTime': startTime.toIso8601String(),
      'state': _state.name,
      'currentAttempt': _currentAttempt,
      'lastAttemptTime': _lastAttemptTime?.toIso8601String(),
      'lastError': _lastError,
      'totalDuration': totalDuration.inMilliseconds,
      'attempts': attempts.map((a) => a.toJson()).toList(),
      'config': {
        'initialDelay': config.initialDelay.inMilliseconds,
        'maxDelay': config.maxDelay.inMilliseconds,
        'backoffMultiplier': config.backoffMultiplier,
        'maxAttempts': config.maxAttempts,
        'connectionTimeout': config.connectionTimeout.inMilliseconds,
        'enableJitter': config.enableJitter,
      },
    };
  }
}

class AutoReconnectionService extends ChangeNotifier {
  static final AutoReconnectionService _instance = AutoReconnectionService._internal();
  factory AutoReconnectionService() => _instance;
  AutoReconnectionService._internal();

  final IntegratedLoggingService _logger = IntegratedLoggingService();
  final CameraConnectionManager _connectionManager = CameraConnectionManager();
  
  final Map<String, ReconnectionSession> _sessions = {};
  final Map<String, ReconnectionConfig> _configs = {};
  
  bool _globalEnabled = true;
  Timer? _healthCheckTimer;
  
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  static const ReconnectionConfig _defaultConfig = ReconnectionConfig();

  /// Inicia o serviço de reconexão automática
  Future<void> initialize() async {
    await _logger.info('reconnection', 'Inicializando serviço de reconexão automática');
    
    // Inicia verificação periódica de saúde das conexões
    _startHealthCheck();
    
    await _logger.info('reconnection', 'Serviço de reconexão inicializado');
  }

  /// Habilita/desabilita reconexão automática globalmente
  void setGlobalEnabled(bool enabled) {
    _globalEnabled = enabled;
    
    if (!enabled) {
      // Para todas as sessões ativas
      for (final session in _sessions.values) {
        session.dispose();
      }
      _sessions.clear();
    }
    
    _logger.info('reconnection', 'Reconexão automática ${enabled ? "habilitada" : "desabilitada"}');
    notifyListeners();
  }

  /// Configura parâmetros de reconexão para uma câmera específica
  void configureCamera(String cameraId, ReconnectionConfig config) {
    _configs[cameraId] = config;
    _logger.info('reconnection', 'Configuração atualizada para câmera $cameraId');
  }

  /// Inicia reconexão automática para uma câmera
  Future<void> startReconnection(String cameraId, {String? reason}) async {
    if (!_globalEnabled) {
      await _logger.info('reconnection', 'Reconexão desabilitada globalmente para $cameraId');
      return;
    }

    // Para sessão existente se houver
    await stopReconnection(cameraId);

    final config = _configs[cameraId] ?? _defaultConfig;
    final session = ReconnectionSession(
      cameraId: cameraId,
      config: config,
    );

    _sessions[cameraId] = session;

    await _logger.info('reconnection', 'Iniciando reconexão para câmera $cameraId', 
        details: reason != null ? 'Motivo: $reason' : null);

    // Inicia primeira tentativa
    await _attemptReconnection(session);
    
    notifyListeners();
  }

  /// Para reconexão automática para uma câmera
  Future<void> stopReconnection(String cameraId) async {
    final session = _sessions[cameraId];
    if (session != null) {
      session.dispose();
      _sessions.remove(cameraId);
      
      await _logger.info('reconnection', 'Reconexão parada para câmera $cameraId');
      notifyListeners();
    }
  }

  /// Obtém estado de reconexão de uma câmera
  ReconnectionState getReconnectionState(String cameraId) {
    return _sessions[cameraId]?.state ?? ReconnectionState.idle;
  }

  /// Obtém sessão de reconexão de uma câmera
  ReconnectionSession? getReconnectionSession(String cameraId) {
    return _sessions[cameraId];
  }

  /// Obtém todas as sessões ativas
  List<ReconnectionSession> getActiveSessions() {
    return _sessions.values.where((s) => s.isActive).toList();
  }

  /// Força uma tentativa de reconexão imediata
  Future<bool> forceReconnection(String cameraId) async {
    final session = _sessions[cameraId];
    if (session == null) {
      await _logger.warning('reconnection', 'Tentativa de reconexão forçada para câmera inexistente: $cameraId');
      return false;
    }

    await _logger.info('reconnection', 'Reconexão forçada para câmera $cameraId');
    
    // Cancela timers existentes
    session._backoffTimer?.cancel();
    session._timeoutTimer?.cancel();
    
    // Executa tentativa imediata
    return await _attemptReconnection(session);
  }

  /// Obtém estatísticas do serviço
  Map<String, dynamic> getStatistics() {
    final activeSessions = getActiveSessions();
    
    return {
      'globalEnabled': _globalEnabled,
      'totalSessions': _sessions.length,
      'activeSessions': activeSessions.length,
      'sessionsByState': {
        for (final state in ReconnectionState.values)
          state.name: _sessions.values.where((s) => s.state == state).length,
      },
      'sessions': {
        for (final entry in _sessions.entries)
          entry.key: entry.value.toJson(),
      },
      'healthCheckActive': _healthCheckTimer?.isActive ?? false,
    };
  }

  /// Finaliza o serviço
  void dispose() {
    _healthCheckTimer?.cancel();
    
    for (final session in _sessions.values) {
      session.dispose();
    }
    
    _sessions.clear();
    _configs.clear();
    
    super.dispose();
  }

  // Métodos privados

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) async {
      await _performHealthCheck();
    });
  }

  Future<void> _performHealthCheck() async {
    if (!_globalEnabled) return;

    try {
      // Verifica estado das câmeras conectadas
      final cameras = await _connectionManager.getConnectedCameras();
      
      for (final camera in cameras) {
        final isHealthy = await _connectionManager.isConnectionHealthy(camera.id);
        
        if (!isHealthy && !_sessions.containsKey(camera.id)) {
          await _logger.warning('reconnection', 'Câmera não saudável detectada: ${camera.id}');
          await startReconnection(camera.id, reason: 'Health check failed');
        }
      }
    } catch (e) {
      await _logger.error('reconnection', 'Erro durante verificação de saúde', details: e.toString());
    }
  }

  Future<bool> _attemptReconnection(ReconnectionSession session) async {
    if (session.currentAttempt >= session.config.maxAttempts) {
      session._setState(ReconnectionState.failed);
      await _logger.error('reconnection', 'Máximo de tentativas atingido para câmera ${session.cameraId}');
      notifyListeners();
      return false;
    }

    session._setState(ReconnectionState.attempting);
    notifyListeners();

    final attemptNumber = session.currentAttempt + 1;
    final backoffDelay = _calculateBackoffDelay(session, attemptNumber);
    
    await _logger.info('reconnection', 'Tentativa $attemptNumber para câmera ${session.cameraId}', 
        details: 'Delay: ${backoffDelay.inSeconds}s');

    try {
      // Configura timeout para a tentativa
      session._timeoutTimer = Timer(session.config.connectionTimeout, () {
        _logger.warning('reconnection', 'Timeout na tentativa $attemptNumber para câmera ${session.cameraId}');
      });

      // Tenta reconectar
      final result = await _connectionManager.reconnectCamera(session.cameraId)
          .timeout(session.config.connectionTimeout);

      session._timeoutTimer?.cancel();

      if (result.success) {
        // Sucesso na reconexão
        final attempt = ReconnectionAttempt(
          attemptNumber: attemptNumber,
          timestamp: DateTime.now(),
          backoffDelay: backoffDelay,
          successful: true,
        );
        
        session._addAttempt(attempt);
        session._setState(ReconnectionState.idle);
        
        await _logger.info('reconnection', 'Reconexão bem-sucedida para câmera ${session.cameraId}', 
            details: 'Tentativa $attemptNumber');
        
        // Remove sessão após sucesso
        _sessions.remove(session.cameraId);
        notifyListeners();
        
        return true;
      } else {
        // Falha na reconexão
        final attempt = ReconnectionAttempt(
          attemptNumber: attemptNumber,
          timestamp: DateTime.now(),
          backoffDelay: backoffDelay,
          error: result.error,
          successful: false,
        );
        
        session._addAttempt(attempt);
        
        await _logger.warning('reconnection', 'Falha na tentativa $attemptNumber para câmera ${session.cameraId}', 
            details: result.error);
        
        // Agenda próxima tentativa
        await _scheduleNextAttempt(session, backoffDelay);
        
        return false;
      }
    } catch (e) {
      session._timeoutTimer?.cancel();
      
      final attempt = ReconnectionAttempt(
        attemptNumber: attemptNumber,
        timestamp: DateTime.now(),
        backoffDelay: backoffDelay,
        error: e.toString(),
        successful: false,
      );
      
      session._addAttempt(attempt);
      
      await _logger.error('reconnection', 'Erro na tentativa $attemptNumber para câmera ${session.cameraId}', 
          details: e.toString());
      
      // Agenda próxima tentativa
      await _scheduleNextAttempt(session, backoffDelay);
      
      return false;
    }
  }

  Future<void> _scheduleNextAttempt(ReconnectionSession session, Duration delay) async {
    session._setState(ReconnectionState.backing_off);
    notifyListeners();
    
    session._backoffTimer = Timer(delay, () async {
      if (session.state == ReconnectionState.backing_off) {
        await _attemptReconnection(session);
      }
    });
  }

  Duration _calculateBackoffDelay(ReconnectionSession session, int attemptNumber) {
    final config = session.config;
    
    // Usa delays customizados se disponíveis
    if (config.customDelays.isNotEmpty && attemptNumber <= config.customDelays.length) {
      return config.customDelays[attemptNumber - 1];
    }
    
    // Calcula delay exponencial
    final baseDelay = config.initialDelay.inMilliseconds;
    final multiplier = pow(config.backoffMultiplier, attemptNumber - 1);
    var delayMs = (baseDelay * multiplier).round();
    
    // Aplica jitter se habilitado
    if (config.enableJitter) {
      final jitter = Random().nextDouble() * 0.1; // ±10%
      delayMs = (delayMs * (1 + jitter - 0.05)).round();
    }
    
    // Limita ao delay máximo
    delayMs = min(delayMs, config.maxDelay.inMilliseconds);
    
    return Duration(milliseconds: delayMs);
  }
}