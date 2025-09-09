import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/connection_log.dart';

class IntegratedLoggingService {
  static final IntegratedLoggingService _instance = IntegratedLoggingService._internal();
  static IntegratedLoggingService get instance => _instance;
  factory IntegratedLoggingService() => _instance;
  IntegratedLoggingService._internal();

  final Queue<ConnectionLog> _memoryLogs = Queue<ConnectionLog>();
  final StreamController<ConnectionLog> _logStreamController = StreamController<ConnectionLog>.broadcast();
  
  static const int _maxMemoryLogs = 1000;
  static const int _maxFileSize = 10 * 1024 * 1024; // 10MB
  static const String _logFileName = 'camera_connection_logs.json';
  
  File? _logFile;
  bool _initialized = false;
  LogLevel _minLogLevel = LogLevel.debug;
  Timer? _flushTimer;
  final List<ConnectionLog> _pendingLogs = [];

  /// Stream de logs em tempo real
  Stream<ConnectionLog> get logStream => _logStreamController.stream;

  /// Inicializa o serviço de logging
  Future<void> initialize({LogLevel minLogLevel = LogLevel.debug}) async {
    if (_initialized) return;
    
    try {
      _minLogLevel = minLogLevel;
      await _initializeLogFile();
      await _loadExistingLogs();
      _startPeriodicFlush();
      _initialized = true;
      
      // Log de inicialização
      await info('SYSTEM', 'Serviço de logging inicializado', 
          details: 'Nível mínimo: ${minLogLevel.displayName}');
    } catch (e) {
      throw Exception('Falha ao inicializar serviço de logging: $e');
    }
  }

  /// Verifica se o serviço foi inicializado
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('IntegratedLoggingService não foi inicializado. Chame initialize() primeiro.');
    }
  }

  /// Log de debug
  Future<void> debug(String cameraId, String message, {String? details, Map<String, dynamic>? metadata}) async {
    await _log(ConnectionLogFactory.debug(cameraId, message, details: details, metadata: metadata));
  }

  /// Log de informação
  Future<void> info(String cameraId, String message, {String? details, Map<String, dynamic>? metadata}) async {
    await _log(ConnectionLogFactory.info(cameraId, message, details: details, metadata: metadata));
  }

  /// Log de aviso
  Future<void> warning(String cameraId, String message, {String? details, Map<String, dynamic>? metadata}) async {
    await _log(ConnectionLogFactory.warning(cameraId, message, details: details, metadata: metadata));
  }

  /// Log de erro
  Future<void> error(String cameraId, String message, {String? details, String? stackTrace, Map<String, dynamic>? metadata}) async {
    await _log(ConnectionLogFactory.error(cameraId, message, details: details, stackTrace: stackTrace, metadata: metadata));
  }

  /// Log crítico
  Future<void> critical(String cameraId, String message, {String? details, String? stackTrace, Map<String, dynamic>? metadata}) async {
    await _log(ConnectionLogFactory.critical(cameraId, message, details: details, stackTrace: stackTrace, metadata: metadata));
  }

  /// Log de tentativa de conexão
  Future<void> logConnection(String cameraId, String url, Duration duration, {int? responseCode, String? details}) async {
    await _log(ConnectionLogFactory.connection(cameraId, url, duration, responseCode: responseCode, details: details));
  }

  /// Log personalizado
  Future<void> log(ConnectionLog logEntry) async {
    await _log(logEntry);
  }

  /// Método interno para processar logs
  Future<void> _log(ConnectionLog logEntry) async {
    if (!_initialized) {
      // Se não inicializado, armazena em buffer temporário
      _pendingLogs.add(logEntry);
      return;
    }

    // Verifica nível mínimo
    if (logEntry.level.priority < _minLogLevel.priority) {
      return;
    }

    // Adiciona à memória
    _memoryLogs.add(logEntry);
    
    // Remove logs antigos se exceder limite
    while (_memoryLogs.length > _maxMemoryLogs) {
      _memoryLogs.removeFirst();
    }

    // Emite no stream
    _logStreamController.add(logEntry);

    // Adiciona à lista de logs pendentes para flush
    _pendingLogs.add(logEntry);

    // Flush imediato para logs críticos e de erro
    if (logEntry.level == LogLevel.critical || logEntry.level == LogLevel.error) {
      await _flushToFile();
    }
  }

  /// Recupera logs da memória
  List<ConnectionLog> getMemoryLogs({
    String? cameraId,
    LogLevel? minLevel,
    DateTime? since,
    int? limit,
  }) {
    _ensureInitialized();
    
    var logs = _memoryLogs.toList();
    
    // Filtros
    if (cameraId != null) {
      logs = logs.where((log) => log.cameraId == cameraId).toList();
    }
    
    if (minLevel != null) {
      logs = logs.where((log) => log.level.priority >= minLevel.priority).toList();
    }
    
    if (since != null) {
      logs = logs.where((log) => log.timestamp.isAfter(since)).toList();
    }
    
    // Ordena por timestamp (mais recente primeiro)
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    // Limita resultados
    if (limit != null && logs.length > limit) {
      logs = logs.take(limit).toList();
    }
    
    return logs;
  }

  /// Recupera logs do arquivo
  Future<List<ConnectionLog>> getFileLogs({
    String? cameraId,
    LogLevel? minLevel,
    DateTime? since,
    DateTime? until,
    int? limit,
  }) async {
    _ensureInitialized();
    
    if (_logFile == null || !await _logFile!.exists()) {
      return [];
    }

    try {
      final content = await _logFile!.readAsString();
      final lines = content.split('\n').where((line) => line.trim().isNotEmpty);
      final logs = <ConnectionLog>[];

      for (final line in lines) {
        try {
          final jsonMap = jsonDecode(line) as Map<String, dynamic>;
          final log = ConnectionLog.fromJson(jsonMap);
          
          // Aplicar filtros
          if (cameraId != null && log.cameraId != cameraId) continue;
          if (minLevel != null && log.level.priority < minLevel.priority) continue;
          if (since != null && log.timestamp.isBefore(since)) continue;
          if (until != null && log.timestamp.isAfter(until)) continue;
          
          logs.add(log);
        } catch (e) {
          // Ignora linhas malformadas
          continue;
        }
      }

      // Ordena por timestamp (mais recente primeiro)
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      // Limita resultados
      if (limit != null && logs.length > limit) {
        return logs.take(limit).toList();
      }
      
      return logs;
    } catch (e) {
      await error('SYSTEM', 'Falha ao ler logs do arquivo', details: e.toString());
      return [];
    }
  }

  /// Combina logs da memória e arquivo
  Future<List<ConnectionLog>> getAllLogs({
    String? cameraId,
    LogLevel? minLevel,
    DateTime? since,
    DateTime? until,
    int? limit,
  }) async {
    final memoryLogs = getMemoryLogs(
      cameraId: cameraId,
      minLevel: minLevel,
      since: since,
    );
    
    final fileLogs = await getFileLogs(
      cameraId: cameraId,
      minLevel: minLevel,
      since: since,
      until: until,
    );

    // Combina e remove duplicatas
    final allLogs = <String, ConnectionLog>{};
    
    for (final log in [...fileLogs, ...memoryLogs]) {
      allLogs[log.id] = log;
    }

    final logs = allLogs.values.toList();
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (limit != null && logs.length > limit) {
      return logs.take(limit).toList();
    }
    
    return logs;
  }

  /// Limpa logs antigos
  Future<void> clearOldLogs({Duration? olderThan}) async {
    _ensureInitialized();
    
    final cutoffDate = DateTime.now().subtract(olderThan ?? const Duration(days: 30));
    
    // Limpa logs da memória
    _memoryLogs.removeWhere((log) => log.timestamp.isBefore(cutoffDate));
    
    // Reescreve arquivo sem logs antigos
    if (_logFile != null && await _logFile!.exists()) {
      final logs = await getFileLogs(since: cutoffDate);
      await _rewriteLogFile(logs);
    }
  }

  /// Exporta logs para arquivo
  Future<File> exportLogs({
    String? cameraId,
    LogLevel? minLevel,
    DateTime? since,
    DateTime? until,
    String? fileName,
  }) async {
    _ensureInitialized();
    
    final logs = await getAllLogs(
      cameraId: cameraId,
      minLevel: minLevel,
      since: since,
      until: until,
    );

    final directory = await getApplicationDocumentsDirectory();
    final exportFile = File('${directory.path}/${fileName ?? 'exported_logs_${DateTime.now().millisecondsSinceEpoch}.json'}');
    
    final exportData = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'filters': {
        'cameraId': cameraId,
        'minLevel': minLevel?.name,
        'since': since?.toIso8601String(),
        'until': until?.toIso8601String(),
      },
      'logs': logs.map((log) => log.toJson()).toList(),
    };

    await exportFile.writeAsString(jsonEncode(exportData));
    return exportFile;
  }

  /// Obtém estatísticas dos logs
  Future<Map<String, dynamic>> getLogStatistics({String? cameraId, Duration? period}) async {
    final since = period != null ? DateTime.now().subtract(period) : null;
    final logs = await getAllLogs(cameraId: cameraId, since: since);
    
    final stats = <String, dynamic>{
      'totalLogs': logs.length,
      'byLevel': <String, int>{},
      'byCameraId': <String, int>{},
      'errorRate': 0.0,
      'averageResponseTime': 0.0,
      'period': period?.inHours ?? 'all time',
    };

    if (logs.isEmpty) return stats;

    // Estatísticas por nível
    for (final level in LogLevel.values) {
      stats['byLevel'][level.name] = logs.where((log) => log.level == level).length;
    }

    // Estatísticas por câmera
    final cameraGroups = <String, List<ConnectionLog>>{};
    for (final log in logs) {
      cameraGroups.putIfAbsent(log.cameraId, () => []).add(log);
    }
    
    for (final entry in cameraGroups.entries) {
      stats['byCameraId'][entry.key] = entry.value.length;
    }

    // Taxa de erro
    final errorLogs = logs.where((log) => log.isError).length;
    stats['errorRate'] = (errorLogs / logs.length * 100).toStringAsFixed(2);

    // Tempo médio de resposta
    final logsWithDuration = logs.where((log) => log.duration != null);
    if (logsWithDuration.isNotEmpty) {
      final totalMs = logsWithDuration.fold<int>(0, (sum, log) => sum + log.duration!.inMilliseconds);
      stats['averageResponseTime'] = (totalMs / logsWithDuration.length).toStringAsFixed(2);
    }

    return stats;
  }

  /// Configura nível mínimo de log
  void setMinLogLevel(LogLevel level) {
    _minLogLevel = level;
  }

  /// Força flush dos logs pendentes
  Future<void> flush() async {
    await _flushToFile();
  }

  /// Limpa todos os logs
  Future<void> clearAllLogs() async {
    _ensureInitialized();
    
    _memoryLogs.clear();
    _pendingLogs.clear();
    
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.delete();
      await _initializeLogFile();
    }
  }

  /// Finaliza o serviço
  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _flushToFile();
    await _logStreamController.close();
    _initialized = false;
  }

  // Métodos privados

  Future<void> _initializeLogFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File('${directory.path}/$_logFileName');
      
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
    } catch (e) {
      throw Exception('Falha ao inicializar arquivo de log: $e');
    }
  }

  Future<void> _loadExistingLogs() async {
    if (_logFile == null || !await _logFile!.exists()) return;
    
    try {
      // Carrega apenas os logs mais recentes na memória
      final recentLogs = await getFileLogs(
        since: DateTime.now().subtract(const Duration(hours: 1)),
        limit: _maxMemoryLogs ~/ 2,
      );
      
      for (final log in recentLogs.reversed) {
        _memoryLogs.add(log);
      }
      
      // Processa logs pendentes
      for (final log in _pendingLogs) {
        await _log(log);
      }
      _pendingLogs.clear();
    } catch (e) {
      // Em caso de erro, continua sem logs existentes
    }
  }

  void _startPeriodicFlush() {
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _flushToFile();
    });
  }

  Future<void> _flushToFile() async {
    if (_logFile == null || _pendingLogs.isEmpty) return;
    
    try {
      // Verifica tamanho do arquivo
      if (await _logFile!.exists()) {
        final stat = await _logFile!.stat();
        if (stat.size > _maxFileSize) {
          await _rotateLogFile();
        }
      }

      // Escreve logs pendentes
      final buffer = StringBuffer();
      for (final log in _pendingLogs) {
        buffer.writeln(jsonEncode(log.toJson()));
      }
      
      await _logFile!.writeAsString(buffer.toString(), mode: FileMode.append);
      _pendingLogs.clear();
    } catch (e) {
      // Em caso de erro, mantém logs na memória
    }
  }

  Future<void> _rotateLogFile() async {
    if (_logFile == null) return;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final backupFile = File('${directory.path}/${_logFileName}.backup');
      
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      
      await _logFile!.rename(backupFile.path);
      await _initializeLogFile();
    } catch (e) {
      // Em caso de erro, apenas limpa o arquivo atual
      await _logFile!.writeAsString('');
    }
  }

  Future<void> _rewriteLogFile(List<ConnectionLog> logs) async {
    if (_logFile == null) return;
    
    try {
      final buffer = StringBuffer();
      for (final log in logs) {
        buffer.writeln(jsonEncode(log.toJson()));
      }
      
      await _logFile!.writeAsString(buffer.toString());
    } catch (e) {
      throw Exception('Falha ao reescrever arquivo de log: $e');
    }
  }
}