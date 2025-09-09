import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class LoggingService {
  static LoggingService? _instance;
  static LoggingService get instance => _instance ??= LoggingService._();
  
  LoggingService._();
  
  File? _logFile;
  bool _isInitialized = false;
  final List<String> _logBuffer = [];
  
  /// Inicializa o serviço de logging
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Criar diretório de logs se não existir
      final Directory appDir = Directory('c:\\Users\\tiago\\Desktop\\app camera 2\\logs');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
      
      // Criar arquivo de log com timestamp
      final String timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      _logFile = File('${appDir.path}\\app_log_$timestamp.txt');
      
      // Escrever cabeçalho do log
      await _writeToFile('=== INÍCIO DO LOG - ${DateTime.now()} ===\n');
      await _writeToFile('App: Camera Discovery System\n');
      await _writeToFile('Versão: 1.0.0\n');
      await _writeToFile('Plataforma: ${Platform.operatingSystem}\n');
      await _writeToFile('========================================\n\n');
      
      _isInitialized = true;
      
      // Escrever logs em buffer
      for (String bufferedLog in _logBuffer) {
        await _writeToFile(bufferedLog);
      }
      _logBuffer.clear();
      
      log('LoggingService inicializado com sucesso', level: LogLevel.info);
    } catch (e) {
      debugPrint('Erro ao inicializar LoggingService: $e');
    }
  }
  
  /// Escreve log no arquivo
  Future<void> _writeToFile(String content) async {
    if (_logFile != null) {
      try {
        await _logFile!.writeAsString(content, mode: FileMode.append);
      } catch (e) {
        debugPrint('Erro ao escrever no arquivo de log: $e');
      }
    }
  }
  
  /// Registra um log com nível específico
  Future<void> log(String message, {
    LogLevel level = LogLevel.info,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final String timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
    final String levelStr = level.name.toUpperCase().padRight(5);
    final String tagStr = tag != null ? '[$tag] ' : '';
    
    String logEntry = '[$timestamp] $levelStr $tagStr$message';
    
    if (error != null) {
      logEntry += '\nERRO: $error';
    }
    
    if (stackTrace != null) {
      logEntry += '\nSTACK TRACE:\n$stackTrace';
    }
    
    logEntry += '\n';
    
    // Se não estiver inicializado, adicionar ao buffer
    if (!_isInitialized) {
      _logBuffer.add(logEntry);
      return;
    }
    
    // Escrever no arquivo
    await _writeToFile(logEntry);
    
    // Também imprimir no console para debug
    if (kDebugMode) {
      switch (level) {
        case LogLevel.error:
          debugPrint('🔴 $tagStr$message');
          break;
        case LogLevel.warning:
          debugPrint('🟡 $tagStr$message');
          break;
        case LogLevel.info:
          debugPrint('🔵 $tagStr$message');
          break;
        case LogLevel.debug:
          debugPrint('⚪ $tagStr$message');
          break;
      }
    }
    
    // Usar developer.log para logs do sistema
    developer.log(
      message,
      name: tag ?? 'App',
      level: _getDeveloperLogLevel(level),
      error: error,
      stackTrace: stackTrace,
    );
  }
  
  /// Converte LogLevel para nível do developer.log
  int _getDeveloperLogLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
  
  /// Log de erro
  Future<void> error(String message, {String? tag, Object? error, StackTrace? stackTrace}) async {
    await log(message, level: LogLevel.error, tag: tag, error: error, stackTrace: stackTrace);
  }
  
  /// Log de aviso
  Future<void> warning(String message, {String? tag}) async {
    await log(message, level: LogLevel.warning, tag: tag);
  }
  
  /// Log de informação
  Future<void> info(String message, {String? tag}) async {
    await log(message, level: LogLevel.info, tag: tag);
  }
  
  /// Log de debug
  Future<void> debug(String message, {String? tag}) async {
    await log(message, level: LogLevel.debug, tag: tag);
  }
  
  /// Log específico para descoberta de câmeras
  Future<void> cameraDiscovery(String message, {String? cameraType, String? ip}) async {
    final String tag = 'DISCOVERY${cameraType != null ? '_$cameraType' : ''}';
    final String fullMessage = ip != null ? '[$ip] $message' : message;
    await info(fullMessage, tag: tag);
  }
  
  /// Log específico para conexão de câmeras
  Future<void> cameraConnection(String message, {String? ip, bool isError = false}) async {
    final String tag = 'CONNECTION';
    final String fullMessage = ip != null ? '[$ip] $message' : message;
    
    if (isError) {
      await error(fullMessage, tag: tag);
    } else {
      await info(fullMessage, tag: tag);
    }
  }
  
  /// Log específico para protocolos
  Future<void> protocol(String message, {String? protocolType, String? ip}) async {
    final String tag = 'PROTOCOL${protocolType != null ? '_$protocolType' : ''}';
    final String fullMessage = ip != null ? '[$ip] $message' : message;
    await debug(fullMessage, tag: tag);
  }
  
  /// Log específico para descoberta de dispositivos
  Future<void> discoveryLog(String message, {String? deviceType, String? ip}) async {
    final String tag = 'DISCOVERY${deviceType != null ? '_$deviceType' : ''}';
    final String fullMessage = ip != null ? '[$ip] $message' : message;
    await info(fullMessage, tag: tag);
  }
  
  /// Log específico para reprodução de vídeo
  Future<void> videoPlayback(String message, {String? cameraId, String? url}) async {
    final String tag = 'VIDEO_PLAYBACK';
    final String fullMessage = cameraId != null ? '[$cameraId] $message' : message;
    final String detailedMessage = url != null ? '$fullMessage (URL: $url)' : fullMessage;
    await info(detailedMessage, tag: tag);
  }
  
  /// Log específico para player de vídeo
  Future<void> videoPlayer(String message, {String? playerId, String? state, bool isError = false}) async {
    final String tag = 'VIDEO_PLAYER';
    final String fullMessage = playerId != null ? '[$playerId] $message' : message;
    final String detailedMessage = state != null ? '$fullMessage (State: $state)' : fullMessage;
    
    if (isError) {
      await error(detailedMessage, tag: tag);
    } else {
      await info(detailedMessage, tag: tag);
    }
  }
  
  /// Finaliza o serviço de logging
  Future<void> dispose() async {
    if (_isInitialized) {
      await _writeToFile('\n=== FIM DO LOG - ${DateTime.now()} ===\n');
      _isInitialized = false;
      _logFile = null;
    }
  }
  
  /// Obtém o caminho do arquivo de log atual
  String? get currentLogPath => _logFile?.path;
}

/// Níveis de log
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// Extensão para facilitar o uso do logging
extension LoggingExtension on Object {
  Future<void> logInfo(String message, {String? tag}) async {
    await LoggingService.instance.info('[$runtimeType] $message', tag: tag);
  }
  
  Future<void> logError(String message, {Object? error, StackTrace? stackTrace}) async {
    await LoggingService.instance.error('[$runtimeType] $message', 
        tag: runtimeType.toString(), error: error, stackTrace: stackTrace);
  }
  
  Future<void> logDebug(String message) async {
    await LoggingService.instance.debug('[$runtimeType] $message', tag: runtimeType.toString());
  }
}