import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'logging_service.dart';

enum DeviceType {
  camera,
  router,
  printer,
  nas,
  switch_,
  accessPoint,
  unknown
}

class DeviceIdentification {
  final String ip;
  final int port;
  final DeviceType type;
  final String? manufacturer;
  final String? model;
  final String? version;
  final Map<String, dynamic> fingerprint;
  final double confidence; // 0.0 to 1.0
  final List<String> detectionMethods;

  DeviceIdentification({
    required this.ip,
    required this.port,
    required this.type,
    this.manufacturer,
    this.model,
    this.version,
    required this.fingerprint,
    required this.confidence,
    required this.detectionMethods,
  });

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'type': type.toString(),
    'manufacturer': manufacturer,
    'model': model,
    'version': version,
    'fingerprint': fingerprint,
    'confidence': confidence,
    'detectionMethods': detectionMethods,
  };
}

class DeviceIdentificationService {
  static final DeviceIdentificationService _instance = DeviceIdentificationService._internal();
  factory DeviceIdentificationService() => _instance;
  DeviceIdentificationService._internal();

  final LoggingService _logger = LoggingService.instance;
  final Duration _httpTimeout = const Duration(seconds: 5);
  final Duration _socketTimeout = const Duration(seconds: 3);

  // Camera detection patterns
  static const List<String> _cameraServerHeaders = [
    'hikvision',
    'dahua',
    'axis',
    'vivotek',
    'foscam',
    'tp-link',
    'dlink',
    'netcam',
    'ipcam',
    'webcam',
    'onvif',
    'rtsp',
    'mjpeg',
    'h264',
    'h265'
  ];

  static const List<String> _cameraPageTitles = [
    'ip camera',
    'network camera',
    'web camera',
    'surveillance',
    'security camera',
    'cctv',
    'nvr',
    'dvr',
    'video server',
    'camera web interface'
  ];

  static const List<String> _cameraEndpoints = [
    '/onvif/device_service',
    '/onvif/media_service',
    '/cgi-bin/hi3510/param.cgi',
    '/cgi-bin/configManager.cgi',
    '/ISAPI/System/deviceInfo',
    '/axis-cgi/mjpg/video.cgi',
    '/videostream.cgi',
    '/snapshot.cgi',
    '/live/ch00_0.m3u8',
    '/cam/realmonitor',
    '/web/cgi-bin/hi3510/param.cgi',
    '/cgi-bin/snapshot.cgi',
    '/webcapture.jpg',
    '/mjpeg',
    '/live.sdp'
  ];

  // Router detection patterns
  static const List<String> _routerServerHeaders = [
    'tp-link',
    'linksys',
    'netgear',
    'asus',
    'd-link',
    'belkin',
    'cisco',
    'ubiquiti',
    'mikrotik',
    'openwrt',
    'dd-wrt',
    'lighttpd',
    'boa/',
    'goahead',
    'mini_httpd',
    'thttpd',
    'router',
    'embedded'
  ];

  static const List<String> _routerPageTitles = [
    'router',
    'wireless router',
    'access point',
    'gateway',
    'modem',
    'admin panel',
    'configuration',
    'setup wizard',
    'network settings',
    'wireless',
    'admin',
    'management',
    'setup',
    'login'
  ];

  /// Lista de fabricantes conhecidos de roteadores
  static const List<String> _routerManufacturers = [
    'tp-link', 'tplink',
    'linksys',
    'netgear',
    'asus',
    'dlink', 'd-link',
    'cisco',
    'ubiquiti',
    'mikrotik',
    'huawei',
    'xiaomi',
    'mercusys',
    'tenda',
    'buffalo',
  ];

  static const List<String> _routerEndpoints = [
    '/admin',
    '/setup',
    '/config',
    '/cgi-bin/luci',
    '/login.htm',
    '/index.htm',
    '/status.htm',
    '/wireless.htm'
  ];

  /// Identifica o tipo de dispositivo em um IP e porta específicos
  Future<DeviceIdentification> identifyDevice(String ip, int port) async {
    _logger.info('Iniciando identificação de dispositivo: $ip:$port');
    
    final fingerprint = <String, dynamic>{};
    final detectionMethods = <String>[];
    double totalConfidence = 0.0;
    int confidenceCount = 0;

    try {
      // 1. Análise HTTP
      final httpResult = await _analyzeHttpService(ip, port);
      if (httpResult != null) {
        fingerprint.addAll(httpResult['fingerprint']);
        detectionMethods.addAll(httpResult['methods']);
        totalConfidence += httpResult['confidence'];
        confidenceCount++;
      }

      // 2. Análise de portas específicas
      final portResult = await _analyzePortFingerprint(ip, port);
      if (portResult != null) {
        fingerprint.addAll(portResult['fingerprint']);
        detectionMethods.addAll(portResult['methods']);
        totalConfidence += portResult['confidence'];
        confidenceCount++;
      }

      // 3. Análise de protocolos específicos
      final protocolResult = await _analyzeProtocols(ip, port);
      if (protocolResult != null) {
        fingerprint.addAll(protocolResult['fingerprint']);
        detectionMethods.addAll(protocolResult['methods']);
        totalConfidence += protocolResult['confidence'];
        confidenceCount++;
      }

      // Calcular confiança média
      final avgConfidence = confidenceCount > 0 ? totalConfidence / confidenceCount : 0.0;

      // Determinar tipo de dispositivo baseado no fingerprint
      final deviceType = _determineDeviceType(fingerprint, avgConfidence);
      
      final identification = DeviceIdentification(
        ip: ip,
        port: port,
        type: deviceType['type'],
        manufacturer: fingerprint['manufacturer'],
        model: fingerprint['model'],
        version: fingerprint['version'],
        fingerprint: fingerprint,
        confidence: deviceType['confidence'],
        detectionMethods: detectionMethods,
      );

      _logger.info('Dispositivo identificado: $ip:$port como ${identification.type} (confiança: ${identification.confidence.toStringAsFixed(2)})');
      return identification;

    } catch (e) {
      _logger.error('Erro na identificação do dispositivo $ip:$port: $e');
      return DeviceIdentification(
        ip: ip,
        port: port,
        type: DeviceType.unknown,
        fingerprint: fingerprint,
        confidence: 0.0,
        detectionMethods: detectionMethods,
      );
    }
  }

  /// Analisa serviço HTTP para identificação
  Future<Map<String, dynamic>?> _analyzeHttpService(String ip, int port) async {
    try {
      final url = 'http://$ip:$port';
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'CameraDiscovery/1.0'},
      ).timeout(_httpTimeout);

      final fingerprint = <String, dynamic>{};
      final methods = <String>['http_analysis'];
      double confidence = 0.1; // Base confidence for HTTP response

      // Analisar headers
      final serverHeader = response.headers['server']?.toLowerCase() ?? '';
      if (serverHeader.isNotEmpty) {
        fingerprint['server_header'] = serverHeader;
        confidence += 0.2;
        _logger.debug('Server header detectado em $ip:$port: $serverHeader');
        
        // Detectar fabricante pelo header
        for (final pattern in _cameraServerHeaders) {
          if (serverHeader.contains(pattern)) {
            fingerprint['detected_patterns'] = (fingerprint['detected_patterns'] as List<String>? ?? [])..add(pattern);
            fingerprint['likely_camera'] = true;
            confidence += 0.3;
            methods.add('server_header_camera');
            _logger.debug('Padrão de câmera detectado no header: $pattern');
            break;
          }
        }
        
        for (final pattern in _routerServerHeaders) {
          if (serverHeader.contains(pattern)) {
            fingerprint['detected_patterns'] = (fingerprint['detected_patterns'] as List<String>? ?? [])..add(pattern);
            fingerprint['likely_router'] = true;
            confidence += 0.3;
            methods.add('server_header_router');
            _logger.debug('Padrão de roteador detectado no header: $pattern');
            break;
          }
        }
      }

      // Análise do conteúdo HTML
      final body = response.body.toLowerCase();
      final title = _extractPageTitle(body);
      
      // Verifica padrões de câmeras
      final cameraKeywords = ['camera', 'webcam', 'onvif', 'rtsp', 'mjpeg', 'snapshot', 'video', 'stream', 'ipcam'];
      final hasCameraKeywords = cameraKeywords.any((keyword) => 
        body.contains(keyword) || serverHeader.contains(keyword) || title.contains(keyword)
      );
      
      // Verifica padrões de roteadores com análise mais detalhada
      final hasRouterManufacturer = _routerManufacturers.any((manufacturer) =>
        body.contains(manufacturer) || serverHeader.contains(manufacturer) || title.contains(manufacturer)
      );
      
      final hasRouterPageTitle = _routerPageTitles.any((pattern) =>
        title.contains(pattern)
      );
      
      final hasRouterServerHeader = _routerServerHeaders.any((pattern) =>
        serverHeader.contains(pattern)
      );
      
      final hasRouterKeywords = hasRouterManufacturer || hasRouterPageTitle || hasRouterServerHeader;
      
      // Verifica endpoints específicos de roteadores
      final hasRouterEndpoints = await _hasRouterSpecificEndpoints(ip, port);
      
      fingerprint['page_size'] = body.length;
      fingerprint['page_title'] = title;
      
      if (hasCameraKeywords) {
        fingerprint['has_camera_protocols'] = true;
        confidence += 0.5;
        methods.add('camera_protocols_detected');
      }

      // Procurar por elementos de autenticação típicos
      if (body.contains('username') && body.contains('password')) {
        fingerprint['has_auth_form'] = true;
        confidence += 0.1;
        methods.add('auth_form_detected');
      }

      // Verifica padrões de fabricantes de roteadores
      if (hasRouterManufacturer) {
        fingerprint['router_manufacturer'] = _routerManufacturers.firstWhere((manufacturer) =>
          body.contains(manufacturer) || serverHeader.contains(manufacturer) || title.contains(manufacturer)
        );
        fingerprint['likely_router'] = true;
        confidence += 0.4;
        methods.add('router_manufacturer_detected');
      }

      // Calcula confiança baseada em múltiplos fatores
      double cameraConfidence = 0.0;
      double routerConfidence = 0.0;
      
      if (hasCameraKeywords) cameraConfidence += 0.4;
      if (hasRouterKeywords) routerConfidence += 0.3;
      if (hasRouterManufacturer) routerConfidence += 0.4;
      if (hasRouterPageTitle) routerConfidence += 0.3;
      if (hasRouterServerHeader) routerConfidence += 0.3;
      if (hasRouterEndpoints) routerConfidence += 0.2;
      
      return {
        'server_header': serverHeader,
        'content_type': response.headers['content-type'] ?? '',
        'status_code': response.statusCode,
        'page_title': title,
        'fingerprint': {
          'likely_camera': cameraConfidence > 0.3 && cameraConfidence > routerConfidence,
          'likely_router': routerConfidence > 0.4 && routerConfidence > cameraConfidence,
          'camera_confidence': cameraConfidence,
          'router_confidence': routerConfidence,
          'confidence': math.max(cameraConfidence, routerConfidence),
        },
        'raw_response': response.body.length > 1000 ? response.body.substring(0, 1000) : response.body,
      };

    } catch (e) {
      _logger.debug('Erro na análise HTTP de $ip:$port: $e');
      return null;
    }
  }

  /// Analisa serviço HTTP para identificação
  Future<Map<String, dynamic>?> analyzeHttpService(String ip, int port) async {
    _logger.debug('Analisando serviço HTTP em $ip:$port');
    final result = await _analyzeHttpService(ip, port);
    if (result != null) {
      _logger.debug('Análise HTTP concluída para $ip:$port - Confiança: ${result['fingerprint']['confidence']?.toStringAsFixed(2) ?? 'N/A'}');
    } else {
      _logger.debug('Análise HTTP falhou para $ip:$port');
    }
    return result;
  }

  /// Analisa fingerprint baseado na porta
  Future<Map<String, dynamic>?> _analyzePortFingerprint(String ip, int port) async {
    final fingerprint = <String, dynamic>{};
    final methods = <String>['port_analysis'];
    double confidence = 0.0;

    // Portas típicas de câmeras
    final cameraPorts = [80, 81, 554, 8080, 8081, 8000, 8001, 37777, 34567, 9000];
    if (cameraPorts.contains(port)) {
      fingerprint['camera_typical_port'] = true;
      confidence += 0.2;
      methods.add('camera_port_detected');
    }

    // Portas típicas de roteadores
    final routerPorts = [80, 8080, 443, 8443, 8000];
    if (routerPorts.contains(port) && port == 80) {
      fingerprint['router_typical_port'] = true;
      confidence += 0.1; // Menor confiança pois porta 80 é muito comum
      methods.add('router_port_detected');
    }

    // Porta RTSP específica para câmeras
    if (port == 554) {
      fingerprint['rtsp_port'] = true;
      confidence += 0.6;
      methods.add('rtsp_port_detected');
    }

    return confidence > 0 ? {
      'fingerprint': fingerprint,
      'methods': methods,
      'confidence': confidence,
    } : null;
  }

  /// Analisa protocolos específicos
  Future<Map<String, dynamic>?> _analyzeProtocols(String ip, int port) async {
    final fingerprint = <String, dynamic>{};
    final methods = <String>['protocol_analysis'];
    double confidence = 0.0;

    try {
      // Testar ONVIF (específico para câmeras)
      if (await _testOnvifProtocol(ip, port)) {
        fingerprint['supports_onvif'] = true;
        confidence += 0.8;
        methods.add('onvif_detected');
      }

      // Testar RTSP (específico para câmeras)
      if (port == 554 && await _testRtspProtocol(ip, port)) {
        fingerprint['supports_rtsp'] = true;
        confidence += 0.7;
        methods.add('rtsp_detected');
      }

      // Testar endpoints específicos de câmeras
      final cameraEndpointFound = await _testCameraEndpoints(ip, port);
      if (cameraEndpointFound.isNotEmpty) {
        fingerprint['camera_endpoints'] = cameraEndpointFound;
        confidence += 0.6;
        methods.add('camera_endpoints_detected');
      }

      return confidence > 0 ? {
        'fingerprint': fingerprint,
        'methods': methods,
        'confidence': confidence,
      } : null;

    } catch (e) {
      _logger.debug('Erro na análise de protocolos de $ip:$port: $e');
      return null;
    }
  }

  /// Testa protocolo ONVIF
  Future<bool> _testOnvifProtocol(String ip, int port) async {
    try {
      final onvifEndpoints = ['/onvif/device_service', '/onvif/media_service'];
      
      for (final endpoint in onvifEndpoints) {
        final url = 'http://$ip:$port$endpoint';
        final response = await http.get(Uri.parse(url)).timeout(_httpTimeout);
        
        if (response.statusCode == 200 || response.statusCode == 401) {
          final body = response.body.toLowerCase();
          if (body.contains('onvif') || body.contains('soap') || body.contains('devicemgmt')) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Extrai o título da página HTML
  String _extractPageTitle(String body) {
    final titleMatch = RegExp(r'<title[^>]*>([^<]+)</title>').firstMatch(body);
    return titleMatch?.group(1)?.toLowerCase() ?? '';
  }

  /// Verifica se tem endpoints específicos de roteadores
  Future<bool> _hasRouterSpecificEndpoints(String ip, int port) async {
    for (final endpoint in _routerEndpoints) {
      try {
        final url = 'http://$ip:$port$endpoint';
        final response = await http.get(Uri.parse(url)).timeout(_httpTimeout);
        
        if ([200, 401, 403].contains(response.statusCode)) {
          return true;
        }
      } catch (e) {
        // Ignora erros de conexão
      }
    }
    return false;
  }

  /// Testa protocolo RTSP
  Future<bool> _testRtspProtocol(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: _socketTimeout);
      socket.write('OPTIONS rtsp://$ip:$port RTSP/1.0\r\nCSeq: 1\r\n\r\n');
      
      final response = await utf8.decoder.bind(socket).take(1).join().timeout(_socketTimeout);
      socket.destroy();
      
      return response.toLowerCase().contains('rtsp');
    } catch (e) {
      return false;
    }
  }

  /// Testa endpoints específicos de câmeras
  Future<List<String>> _testCameraEndpoints(String ip, int port) async {
    final foundEndpoints = <String>[];
    
    for (final endpoint in _cameraEndpoints) {
      try {
        final url = 'http://$ip:$port$endpoint';
        final response = await http.get(Uri.parse(url)).timeout(_httpTimeout);
        
        // Considera encontrado se retornar 200, 401 (auth required) ou 403 (forbidden)
        if ([200, 401, 403].contains(response.statusCode)) {
          foundEndpoints.add(endpoint);
        }
      } catch (e) {
        // Ignora erros de conexão
      }
    }
    
    return foundEndpoints;
  }

  /// Determina o tipo de dispositivo baseado no fingerprint
  Map<String, dynamic> _determineDeviceType(Map<String, dynamic> fingerprint, double baseConfidence) {
    double cameraScore = 0.0;
    double routerScore = 0.0;
    double printerScore = 0.0;
    double nasScore = 0.0;

    // Pontuação para câmeras
    if (fingerprint['supports_onvif'] == true) cameraScore += 0.8;
    if (fingerprint['supports_rtsp'] == true) cameraScore += 0.7;
    if (fingerprint['has_camera_protocols'] == true) cameraScore += 0.5;
    if (fingerprint['likely_camera'] == true) cameraScore += 0.4;
    if (fingerprint['title_indicates_camera'] == true) cameraScore += 0.4;
    if (fingerprint['camera_typical_port'] == true) cameraScore += 0.2;
    if (fingerprint['camera_endpoints'] != null && (fingerprint['camera_endpoints'] as List).isNotEmpty) {
      cameraScore += 0.6;
    }

    // Pontuação para roteadores
    if (fingerprint['likely_router'] == true) routerScore += 0.4;
    if (fingerprint['title_indicates_router'] == true) routerScore += 0.4;
    if (fingerprint['router_typical_port'] == true) routerScore += 0.1;

    // Determinar tipo com maior pontuação
    DeviceType deviceType = DeviceType.unknown;
    double confidence = baseConfidence;

    if (cameraScore > routerScore && cameraScore > printerScore && cameraScore > nasScore && cameraScore > 0.3) {
      deviceType = DeviceType.camera;
      confidence = (baseConfidence + cameraScore) / 2;
    } else if (routerScore > cameraScore && routerScore > printerScore && routerScore > nasScore && routerScore > 0.2) {
      deviceType = DeviceType.router;
      confidence = (baseConfidence + routerScore) / 2;
    }

    return {
      'type': deviceType,
      'confidence': confidence.clamp(0.0, 1.0),
      'scores': {
        'camera': cameraScore,
        'router': routerScore,
        'printer': printerScore,
        'nas': nasScore,
      }
    };
  }

  /// Verifica se um dispositivo é uma câmera com alta confiança
  Future<bool> isCamera(String ip, int port, {double minConfidence = 0.6}) async {
    final identification = await identifyDevice(ip, port);
    return identification.type == DeviceType.camera && identification.confidence >= minConfidence;
  }

  /// Detecta se um dispositivo é uma câmera IP
  Future<bool> isCameraDevice(String ip, {int? port, Duration? timeout}) async {
    timeout ??= const Duration(seconds: 5);
    _logger.debug('Iniciando detecção de câmera para $ip${port != null ? ':$port' : ''}');
    
    try {
      // 1. Testa protocolos específicos de câmeras
      _logger.debug('Testando protocolo ONVIF em $ip');
      if (await _testOnvifProtocol(ip, port ?? 80)) {
        _logger.info('✓ Câmera detectada via ONVIF em $ip');
        return true;
      }
      
      if (port == 554) {
        _logger.debug('Testando protocolo RTSP em $ip:554');
        if (await _testRtspProtocol(ip, port!)) {
          _logger.info('✓ Câmera detectada via RTSP em $ip:554');
          return true;
        }
      }
      
      // 2. Analisa banners HTTP em portas comuns
      final commonPorts = port != null ? [port] : [80, 8080, 8081, 8000, 8888, 8899];
      _logger.debug('Analisando banners HTTP em portas: ${commonPorts.join(', ')}');
      
      for (final testPort in commonPorts) {
        final httpAnalysis = await _analyzeHttpService(ip, testPort);
        if (httpAnalysis != null && httpAnalysis['fingerprint']['likely_camera'] == true) {
          _logger.info('✓ Câmera detectada via análise HTTP em $ip:$testPort');
          return true;
        }
      }
      
      // 3. Testa endpoints típicos de câmeras
      _logger.debug('Testando endpoints específicos de câmeras em $ip');
      final endpoints = await _testCameraEndpoints(ip, port ?? 80);
      if (endpoints.isNotEmpty) {
        _logger.info('✓ Câmera detectada via endpoints específicos em $ip: ${endpoints.join(', ')}');
        return true;
      }
      
      _logger.debug('✗ Dispositivo $ip não identificado como câmera');
      return false;
    } catch (e) {
      _logger.error('Erro na detecção de câmera para $ip: $e');
      return false;
    }
  }

  /// Verifica se um dispositivo é um roteador com alta confiança
  Future<bool> isRouter(String ip, int port, {double minConfidence = 0.5}) async {
    final identification = await identifyDevice(ip, port);
    return identification.type == DeviceType.router && identification.confidence >= minConfidence;
  }

  /// Detecta se um dispositivo é um roteador
  Future<bool> isRouterDevice(String ip, {int? port, Duration? timeout}) async {
    timeout ??= const Duration(seconds: 5);
    _logger.debug('Iniciando detecção de roteador para $ip${port != null ? ':$port' : ''}');
    
    try {
      // 1. Verifica se é IP de gateway
      if (_isGatewayIP(ip)) {
        _logger.info('✓ Roteador detectado via IP de gateway: $ip');
        return true;
      }
      
      // 2. Analisa banners HTTP em portas de administração
      final adminPorts = port != null ? [port] : [80, 8080, 443, 8443];
      _logger.debug('Analisando banners HTTP em portas administrativas: ${adminPorts.join(', ')}');
      
      for (final testPort in adminPorts) {
        final httpAnalysis = await _analyzeHttpService(ip, testPort);
        if (httpAnalysis != null && httpAnalysis['fingerprint']['likely_router'] == true) {
          _logger.info('✓ Roteador detectado via análise HTTP em $ip:$testPort');
          return true;
        }
      }
      
      // 3. Testa endpoints típicos de roteadores
      _logger.debug('Testando endpoints específicos de roteadores em $ip');
      if (await _testRouterEndpoints(ip, port ?? 80)) {
        _logger.info('✓ Roteador detectado via endpoints específicos em $ip');
        return true;
      }
      
      _logger.debug('✗ Dispositivo $ip não identificado como roteador');
      return false;
    } catch (e) {
      _logger.error('Erro na detecção de roteador para $ip: $e');
      return false;
    }
  }

  /// Verifica se o IP é típico de gateway
  bool _isGatewayIP(String ip) {
    final gatewayPatterns = [
      '192.168.1.1',
      '192.168.0.1',
      '10.0.0.1',
      '172.16.0.1',
      '192.168.2.1'
    ];
    return gatewayPatterns.contains(ip);
  }

  /// Testa endpoints específicos de roteadores
  Future<bool> _testRouterEndpoints(String ip, int port) async {
    for (final endpoint in _routerEndpoints) {
      try {
        final url = 'http://$ip:$port$endpoint';
        final response = await http.get(Uri.parse(url)).timeout(_httpTimeout);
        
        if ([200, 401, 403].contains(response.statusCode)) {
          return true;
        }
      } catch (e) {
        // Ignora erros de conexão
      }
    }
    return false;
  }



  /// Obtém informações detalhadas de identificação
  Future<Map<String, dynamic>> getDetailedIdentification(String ip, int port) async {
    final identification = await identifyDevice(ip, port);
    return identification.toJson();
  }
}