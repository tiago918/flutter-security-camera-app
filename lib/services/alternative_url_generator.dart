import 'dart:async';
import 'dart:io';
import '../models/camera_model.dart';
import '../models/credentials.dart';
import '../constants/camera_ports.dart';
import 'integrated_logging_service.dart';

class AlternativeUrl {
  final String url;
  final int port;
  final String path;
  final bool isSecure;
  final int priority;
  final String description;

  const AlternativeUrl({
    required this.url,
    required this.port,
    required this.path,
    required this.isSecure,
    required this.priority,
    required this.description,
  });

  @override
  String toString() => url;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlternativeUrl && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}

class ConnectionTestResult {
  final AlternativeUrl url;
  final bool isReachable;
  final Duration responseTime;
  final String? error;
  final int? httpStatusCode;
  final Map<String, String>? headers;

  const ConnectionTestResult({
    required this.url,
    required this.isReachable,
    required this.responseTime,
    this.error,
    this.httpStatusCode,
    this.headers,
  });

  bool get isSuccessful => isReachable && (httpStatusCode == null || (httpStatusCode! >= 200 && httpStatusCode! < 400));
}

class AlternativeUrlGenerator {
  static final AlternativeUrlGenerator _instance = AlternativeUrlGenerator._internal();
  factory AlternativeUrlGenerator() => _instance;
  AlternativeUrlGenerator._internal();

  final IntegratedLoggingService _logger = IntegratedLoggingService();
  
  // Cache de URLs testadas
  final Map<String, List<ConnectionTestResult>> _testCache = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);
  final Map<String, DateTime> _cacheTimestamps = {};

  /// Gera lista de URLs alternativas para uma câmera
  List<AlternativeUrl> generateAlternativeUrls(
    CameraModel camera, {
    Credentials? credentials,
    List<int>? customPorts,
    List<String>? customPaths,
  }) {
    final urls = <AlternativeUrl>[];
    final ipAddress = camera.ipAddress;
    
    // Portas a serem testadas (ordem de prioridade)
    final ports = customPorts ?? [
      camera.port, // Porta original primeiro
      ...CameraPorts.rtspPorts,
      ...CameraPorts.httpPorts,
      ...CameraPorts.onvifPorts,
    ].toSet().toList(); // Remove duplicatas mantendo ordem

    // Caminhos a serem testados
    final paths = customPaths ?? [
      camera.rtspPath ?? '/stream1', // Caminho original primeiro
      '/stream1',
      '/stream',
      '/live',
      '/cam/realmonitor?channel=1&subtype=0',
      '/h264',
      '/video1',
      '/axis-media/media.amp',
      '/mjpeg/1/video.mjpg',
      '/videostream.cgi',
      '/cgi-bin/mjpg/video.cgi',
      '/onvif/media_service/streaming',
    ];

    int priority = 1;
    
    // Gera URLs RTSP
    for (final port in ports.where((p) => CameraPorts.rtspPorts.contains(p) || p == camera.port)) {
      for (final path in paths) {
        urls.add(_createRtspUrl(ipAddress, port, path, credentials, priority++, camera.isSecure));
      }
    }

    // Gera URLs HTTP para câmeras que suportam
    for (final port in ports.where((p) => CameraPorts.httpPorts.contains(p))) {
      for (final path in paths.where((p) => p.contains('mjpeg') || p.contains('.cgi') || p.contains('video'))) {
        urls.add(_createHttpUrl(ipAddress, port, path, credentials, priority++, camera.isSecure));
      }
    }

    // Gera URLs ONVIF
    for (final port in ports.where((p) => CameraPorts.onvifPorts.contains(p))) {
      urls.add(_createOnvifUrl(ipAddress, port, credentials, priority++));
    }

    _logger.debug(camera.id, 'Geradas ${urls.length} URLs alternativas', 
        details: 'Portas: ${ports.join(", ")}, Caminhos: ${paths.length}');

    return urls;
  }

  /// Testa conectividade de uma URL específica
  Future<ConnectionTestResult> testUrl(
    AlternativeUrl url, {
    Duration timeout = const Duration(seconds: 10),
    String? cameraId,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _logger.debug(cameraId ?? 'UNKNOWN', 'Testando URL: ${url.url}');
      
      if (url.url.startsWith('rtsp://') || url.url.startsWith('rtsps://')) {
        return await _testRtspUrl(url, timeout, stopwatch);
      } else if (url.url.startsWith('http://') || url.url.startsWith('https://')) {
        return await _testHttpUrl(url, timeout, stopwatch);
      } else {
        throw Exception('Protocolo não suportado: ${url.url}');
      }
    } catch (e) {
      stopwatch.stop();
      
      final result = ConnectionTestResult(
        url: url,
        isReachable: false,
        responseTime: stopwatch.elapsed,
        error: e.toString(),
      );
      
      _logger.warning(cameraId ?? 'UNKNOWN', 'Falha ao testar URL: ${url.url}', 
          details: e.toString());
      
      return result;
    }
  }

  /// Testa múltiplas URLs em paralelo
  Future<List<ConnectionTestResult>> testMultipleUrls(
    List<AlternativeUrl> urls, {
    Duration timeout = const Duration(seconds: 10),
    int maxConcurrent = 5,
    String? cameraId,
  }) async {
    final cacheKey = '${cameraId ?? "unknown"}_${urls.map((u) => u.url).join("|")}';
    
    // Verifica cache
    if (_testCache.containsKey(cacheKey) && _cacheTimestamps.containsKey(cacheKey)) {
      final cacheTime = _cacheTimestamps[cacheKey]!;
      if (DateTime.now().difference(cacheTime) < _cacheExpiry) {
        _logger.debug(cameraId ?? 'UNKNOWN', 'Usando resultados do cache para teste de URLs');
        return _testCache[cacheKey]!;
      }
    }

    _logger.info(cameraId ?? 'UNKNOWN', 'Testando ${urls.length} URLs alternativas', 
        details: 'Timeout: ${timeout.inSeconds}s, Concorrência: $maxConcurrent');

    final results = <ConnectionTestResult>[];
    
    // Processa URLs em lotes para controlar concorrência
    for (int i = 0; i < urls.length; i += maxConcurrent) {
      final batch = urls.skip(i).take(maxConcurrent).toList();
      final batchResults = await Future.wait(
        batch.map((url) => testUrl(url, timeout: timeout, cameraId: cameraId)),
      );
      results.addAll(batchResults);
    }

    // Ordena por prioridade e sucesso
    results.sort((a, b) {
      if (a.isSuccessful && !b.isSuccessful) return -1;
      if (!a.isSuccessful && b.isSuccessful) return 1;
      return a.url.priority.compareTo(b.url.priority);
    });

    // Atualiza cache
    _testCache[cacheKey] = results;
    _cacheTimestamps[cacheKey] = DateTime.now();

    final successfulCount = results.where((r) => r.isSuccessful).length;
    _logger.info(cameraId ?? 'UNKNOWN', 'Teste de URLs concluído', 
        details: '$successfulCount de ${results.length} URLs funcionais');

    return results;
  }

  /// Encontra a melhor URL funcional
  Future<AlternativeUrl?> findBestWorkingUrl(
    CameraModel camera, {
    Credentials? credentials,
    Duration timeout = const Duration(seconds: 10),
    List<int>? customPorts,
    List<String>? customPaths,
  }) async {
    final urls = generateAlternativeUrls(
      camera,
      credentials: credentials,
      customPorts: customPorts,
      customPaths: customPaths,
    );

    final results = await testMultipleUrls(
      urls,
      timeout: timeout,
      cameraId: camera.id,
    );

    final workingResults = results.where((r) => r.isSuccessful).toList();
    
    if (workingResults.isEmpty) {
      _logger.warning(camera.id, 'Nenhuma URL funcional encontrada');
      return null;
    }

    final bestUrl = workingResults.first.url;
    _logger.info(camera.id, 'Melhor URL encontrada: ${bestUrl.url}', 
        details: 'Tempo de resposta: ${workingResults.first.responseTime.inMilliseconds}ms');
    
    return bestUrl;
  }

  /// Gera URLs específicas para descoberta ONVIF
  List<AlternativeUrl> generateOnvifDiscoveryUrls(String ipAddress) {
    final urls = <AlternativeUrl>[];
    int priority = 1;

    for (final port in CameraPorts.onvifPorts) {
      urls.add(AlternativeUrl(
        url: 'http://$ipAddress:$port/onvif/device_service',
        port: port,
        path: '/onvif/device_service',
        isSecure: false,
        priority: priority++,
        description: 'ONVIF Device Service (Port $port)',
      ));
    }

    return urls;
  }

  /// Limpa cache de testes
  void clearCache() {
    _testCache.clear();
    _cacheTimestamps.clear();
    _logger.debug('SYSTEM', 'Cache de testes de URL limpo');
  }

  /// Obtém estatísticas do cache
  Map<String, dynamic> getCacheStatistics() {
    final now = DateTime.now();
    final validEntries = _cacheTimestamps.entries
        .where((entry) => now.difference(entry.value) < _cacheExpiry)
        .length;

    return {
      'totalEntries': _testCache.length,
      'validEntries': validEntries,
      'expiredEntries': _testCache.length - validEntries,
      'cacheHitRate': _testCache.isNotEmpty ? (validEntries / _testCache.length * 100).toStringAsFixed(2) : '0.00',
    };
  }

  // Métodos privados

  AlternativeUrl _createRtspUrl(
    String ipAddress,
    int port,
    String path,
    Credentials? credentials,
    int priority,
    bool isSecure,
  ) {
    final protocol = isSecure ? 'rtsps' : 'rtsp';
    final auth = credentials != null ? '${credentials.username}:${credentials.password}@' : '';
    final cleanPath = path.startsWith('/') ? path : '/$path';
    
    return AlternativeUrl(
      url: '$protocol://$auth$ipAddress:$port$cleanPath',
      port: port,
      path: cleanPath,
      isSecure: isSecure,
      priority: priority,
      description: 'RTSP Stream (Port $port)',
    );
  }

  AlternativeUrl _createHttpUrl(
    String ipAddress,
    int port,
    String path,
    Credentials? credentials,
    int priority,
    bool isSecure,
  ) {
    final protocol = isSecure ? 'https' : 'http';
    final cleanPath = path.startsWith('/') ? path : '/$path';
    
    String url = '$protocol://$ipAddress:$port$cleanPath';
    
    // Adiciona autenticação como parâmetros para HTTP se necessário
    if (credentials != null && !path.contains('?')) {
      url += '?user=${credentials.username}&pwd=${credentials.password}';
    }
    
    return AlternativeUrl(
      url: url,
      port: port,
      path: cleanPath,
      isSecure: isSecure,
      priority: priority,
      description: 'HTTP Stream (Port $port)',
    );
  }

  AlternativeUrl _createOnvifUrl(
    String ipAddress,
    int port,
    Credentials? credentials,
    int priority,
  ) {
    return AlternativeUrl(
      url: 'http://$ipAddress:$port/onvif/device_service',
      port: port,
      path: '/onvif/device_service',
      isSecure: false,
      priority: priority,
      description: 'ONVIF Service (Port $port)',
    );
  }

  Future<ConnectionTestResult> _testRtspUrl(
    AlternativeUrl url,
    Duration timeout,
    Stopwatch stopwatch,
  ) async {
    try {
      // Para RTSP, fazemos um teste básico de conectividade TCP
      final socket = await Socket.connect(
        url.url.split('@').last.split(':')[0], // Extrai IP
        url.port,
        timeout: timeout,
      );
      
      await socket.close();
      stopwatch.stop();
      
      return ConnectionTestResult(
        url: url,
        isReachable: true,
        responseTime: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ConnectionTestResult(
        url: url,
        isReachable: false,
        responseTime: stopwatch.elapsed,
        error: e.toString(),
      );
    }
  }

  Future<ConnectionTestResult> _testHttpUrl(
    AlternativeUrl url,
    Duration timeout,
    Stopwatch stopwatch,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;
      
      final request = await client.getUrl(Uri.parse(url.url));
      final response = await request.close();
      
      stopwatch.stop();
      client.close();
      
      return ConnectionTestResult(
        url: url,
        isReachable: true,
        responseTime: stopwatch.elapsed,
        httpStatusCode: response.statusCode,
        headers: response.headers.map((name, values) => MapEntry(name, values.join(', '))),
      );
    } catch (e) {
      stopwatch.stop();
      return ConnectionTestResult(
        url: url,
        isReachable: false,
        responseTime: stopwatch.elapsed,
        error: e.toString(),
      );
    }
  }
}