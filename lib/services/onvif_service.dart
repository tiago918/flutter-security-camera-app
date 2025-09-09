import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_onvif/onvif.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/camera_model.dart';
import '../models/credentials.dart';
import '../models/connection_log.dart';
import 'integrated_logging_service.dart';

class DiscoveryResult {
  final List<CameraModel> cameras;
  final DateTime timestamp;
  final Duration discoveryTime;
  final bool fromCache;
  final Map<String, dynamic>? metadata;

  const DiscoveryResult({
    required this.cameras,
    required this.timestamp,
    required this.discoveryTime,
    this.fromCache = false,
    this.metadata,
  });

  bool get isExpired {
    return DateTime.now().difference(timestamp) > const Duration(minutes: 5);
  }
}

class ONVIFDeviceInfo {
  final String ip;
  final int port;
  final String? manufacturer;
  final String? model;
  final String? serialNumber;
  final String? firmwareVersion;
  final List<String> services;
  final Map<String, String> capabilities;
  final DateTime discoveredAt;

  const ONVIFDeviceInfo({
    required this.ip,
    required this.port,
    this.manufacturer,
    this.model,
    this.serialNumber,
    this.firmwareVersion,
    this.services = const [],
    this.capabilities = const {},
    required this.discoveredAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'manufacturer': manufacturer,
      'model': model,
      'serialNumber': serialNumber,
      'firmwareVersion': firmwareVersion,
      'services': services,
      'capabilities': capabilities,
      'discoveredAt': discoveredAt.toIso8601String(),
    };
  }

  factory ONVIFDeviceInfo.fromJson(Map<String, dynamic> json) {
    return ONVIFDeviceInfo(
      ip: json['ip'] as String,
      port: json['port'] as int,
      manufacturer: json['manufacturer'] as String?,
      model: json['model'] as String?,
      serialNumber: json['serialNumber'] as String?,
      firmwareVersion: json['firmwareVersion'] as String?,
      services: List<String>.from(json['services'] ?? []),
      capabilities: Map<String, String>.from(json['capabilities'] ?? {}),
      discoveredAt: DateTime.parse(json['discoveredAt'] as String),
    );
  }
}

class ONVIFService {
  static final ONVIFService _instance = ONVIFService._internal();
  factory ONVIFService() => _instance;
  ONVIFService._internal();

  final IntegratedLoggingService _logger = IntegratedLoggingService();
  
  DiscoveryResult? _cachedResult;
  final Map<String, ONVIFDeviceInfo> _deviceCache = {};
  final Map<String, Onvif> _onvifClients = {};
  
  static const Duration _cacheTimeout = Duration(minutes: 5);
  static const Duration _discoveryTimeout = Duration(seconds: 30);
  static const Duration _deviceTimeout = Duration(seconds: 10);
  
  /// Descobre câmeras ONVIF na rede
  Future<List<CameraModel>> discoverCameras({
    Duration? timeout,
    bool useCache = true,
    String? networkInterface,
  }) async {
    final effectiveTimeout = timeout ?? _discoveryTimeout;
    
    await _logger.info('onvif', 'Iniciando descoberta ONVIF', 
        details: 'Timeout: ${effectiveTimeout.inSeconds}s, Cache: $useCache');
    
    // Verifica cache se habilitado
    if (useCache && _cachedResult != null && !_cachedResult!.isExpired) {
      await _logger.info('onvif', 'Retornando resultado do cache', 
          details: '${_cachedResult!.cameras.length} câmeras');
      
      return _cachedResult!.cameras;
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      final cameras = <CameraModel>[];
      
      // Método 1: Descoberta via multicast DNS
      final mdnsDevices = await _discoverViaMDNS(effectiveTimeout);
      cameras.addAll(mdnsDevices);
      
      // Método 2: Descoberta via WS-Discovery
      final wsDevices = await _discoverViaWSDiscovery(effectiveTimeout);
      cameras.addAll(wsDevices);
      
      // Método 3: Scan de rede local
      final scanDevices = await _discoverViaNetworkScan(effectiveTimeout);
      cameras.addAll(scanDevices);
      
      // Remove duplicatas baseado no IP
      final uniqueCameras = <String, CameraModel>{};
      for (final camera in cameras) {
        uniqueCameras[camera.ip] = camera;
      }
      
      final finalCameras = uniqueCameras.values.toList();
      
      stopwatch.stop();
      
      // Atualiza cache
      _cachedResult = DiscoveryResult(
        cameras: finalCameras,
        timestamp: DateTime.now(),
        discoveryTime: stopwatch.elapsed,
        fromCache: false,
        metadata: {
          'mdnsCount': mdnsDevices.length,
          'wsDiscoveryCount': wsDevices.length,
          'networkScanCount': scanDevices.length,
          'totalFound': cameras.length,
          'uniqueDevices': finalCameras.length,
        },
      );
      
      await _logger.info('onvif', 'Descoberta concluída', 
          details: '${finalCameras.length} câmeras únicas encontradas em ${stopwatch.elapsed.inSeconds}s');
      
      return finalCameras;
      
    } catch (e) {
      stopwatch.stop();
      
      await _logger.error('onvif', 'Erro durante descoberta', details: e.toString());
      
      // Retorna cache se disponível em caso de erro
      if (_cachedResult != null) {
        await _logger.info('onvif', 'Retornando cache devido ao erro');
        return _cachedResult!.cameras;
      }
      
      return [];
    }
  }

  /// Obtém informações detalhadas de um dispositivo ONVIF
  Future<ONVIFDeviceInfo?> getDeviceInfo(
    String ip, {
    int port = 80,
    Credentials? credentials,
    Duration? timeout,
  }) async {
    final deviceKey = '$ip:$port';
    final effectiveTimeout = timeout ?? _deviceTimeout;
    
    // Verifica cache
    final cached = _deviceCache[deviceKey];
    if (cached != null && 
        DateTime.now().difference(cached.discoveredAt) < _cacheTimeout) {
      return cached;
    }
    
    await _logger.info('onvif', 'Obtendo informações do dispositivo', 
        details: 'IP: $ip, Porta: $port');
    
    try {
      final onvif = await _getOnvifClient(ip, port, credentials);
      
      // Obtém informações do dispositivo
      final deviceInfo = await onvif.deviceManagement.getDeviceInformation()
          .timeout(effectiveTimeout);
      
      // Obtém capacidades
      final capabilities = await onvif.deviceManagement.getCapabilities()
          .timeout(effectiveTimeout);
      
      // Obtém serviços
      final services = await onvif.deviceManagement.getServices(false)
          .timeout(effectiveTimeout);
      
      final info = ONVIFDeviceInfo(
        ip: ip,
        port: port,
        manufacturer: deviceInfo.manufacturer,
        model: deviceInfo.model,
        serialNumber: deviceInfo.serialNumber,
        firmwareVersion: deviceInfo.firmwareVersion,
        services: services.map((s) => s.namespace).toList(),
        capabilities: _extractCapabilities(capabilities),
        discoveredAt: DateTime.now(),
      );
      
      // Atualiza cache
      _deviceCache[deviceKey] = info;
      
      await _logger.info('onvif', 'Informações obtidas com sucesso', 
          details: 'Fabricante: ${info.manufacturer}, Modelo: ${info.model}');
      
      return info;
      
    } catch (e) {
      await _logger.warning('onvif', 'Falha ao obter informações do dispositivo', 
          details: 'IP: $ip, Erro: ${e.toString()}');
      return null;
    }
  }

  /// Testa conectividade ONVIF com um dispositivo
  Future<bool> testConnection(
    String ip, {
    int port = 80,
    Credentials? credentials,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _deviceTimeout;
    
    await _logger.info('onvif', 'Testando conexão ONVIF', 
        details: 'IP: $ip, Porta: $port');
    
    try {
      final onvif = await _getOnvifClient(ip, port, credentials);
      
      // Tenta obter informações básicas do dispositivo
      await onvif.deviceManagement.getDeviceInformation()
          .timeout(effectiveTimeout);
      
      await _logger.info('onvif', 'Conexão ONVIF bem-sucedida', details: 'IP: $ip');
      return true;
      
    } catch (e) {
      await _logger.warning('onvif', 'Falha na conexão ONVIF', 
          details: 'IP: $ip, Erro: ${e.toString()}');
      return false;
    }
  }

  /// Obtém URLs de stream de um dispositivo
  Future<List<String>> getStreamUrls(
    String ip, {
    int port = 80,
    Credentials? credentials,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _deviceTimeout;
    
    await _logger.info('onvif', 'Obtendo URLs de stream', details: 'IP: $ip');
    
    try {
      final onvif = await _getOnvifClient(ip, port, credentials);
      
      // Obtém perfis de mídia
      final profiles = await onvif.media.getProfiles()
          .timeout(effectiveTimeout);
      
      final streamUrls = <String>[];
      
      for (final profile in profiles) {
        try {
          // Obtém URI do stream
          final streamUri = await onvif.media.getStreamUri(
            profile.token,
            'RTP-Unicast',
            'UDP',
          ).timeout(const Duration(seconds: 5));
          
          if (streamUri.uri.isNotEmpty) {
            streamUrls.add(streamUri.uri);
          }
        } catch (e) {
          await _logger.warning('onvif', 'Falha ao obter stream URI', 
              details: 'Perfil: ${profile.token}, Erro: ${e.toString()}');
        }
      }
      
      await _logger.info('onvif', 'URLs de stream obtidas', 
          details: '${streamUrls.length} URLs encontradas');
      
      return streamUrls;
      
    } catch (e) {
      await _logger.error('onvif', 'Erro ao obter URLs de stream', 
          details: 'IP: $ip, Erro: ${e.toString()}');
      return [];
    }
  }

  /// Limpa cache de descoberta
  void clearCache() {
    _cachedResult = null;
    _deviceCache.clear();
    _logger.info('onvif', 'Cache limpo');
  }

  /// Obtém estatísticas do serviço
  Map<String, dynamic> getStatistics() {
    return {
      'cacheStatus': {
        'hasDiscoveryCache': _cachedResult != null,
        'cacheAge': _cachedResult != null 
            ? DateTime.now().difference(_cachedResult!.timestamp).inMinutes
            : null,
        'cacheExpired': _cachedResult?.isExpired ?? true,
        'cachedCameras': _cachedResult?.cameras.length ?? 0,
      },
      'deviceCache': {
        'totalDevices': _deviceCache.length,
        'activeClients': _onvifClients.length,
      },
      'lastDiscovery': _cachedResult != null ? {
        'timestamp': _cachedResult!.timestamp.toIso8601String(),
        'discoveryTime': _cachedResult!.discoveryTime.inMilliseconds,
        'fromCache': _cachedResult!.fromCache,
        'metadata': _cachedResult!.metadata,
      } : null,
    };
  }

  /// Finaliza o serviço
  void dispose() {
    _onvifClients.clear();
    _deviceCache.clear();
    _cachedResult = null;
  }

  // Métodos privados

  Future<List<CameraModel>> _discoverViaMDNS(Duration timeout) async {
    await _logger.info('onvif', 'Iniciando descoberta via mDNS');
    
    try {
      final mdns = MDnsClient();
      await mdns.start();
      
      final cameras = <CameraModel>[];
      
      // Procura por serviços ONVIF
      await for (final ptr in mdns.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_onvif._tcp.local'),
      ).timeout(timeout)) {
        try {
          // Resolve o serviço
          await for (final srv in mdns.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          ).timeout(const Duration(seconds: 5))) {
            
            // Resolve o endereço IP
            await for (final ip in mdns.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            ).timeout(const Duration(seconds: 3))) {
              
              final camera = await _createCameraFromMDNS(
                ip.address.address,
                srv.port,
                ptr.domainName,
              );
              
              if (camera != null) {
                cameras.add(camera);
              }
            }
          }
        } catch (e) {
          await _logger.warning('onvif', 'Erro ao resolver serviço mDNS', 
              details: e.toString());
        }
      }
      
      await mdns.stop();
      
      await _logger.info('onvif', 'Descoberta mDNS concluída', 
          details: '${cameras.length} câmeras encontradas');
      
      return cameras;
      
    } catch (e) {
      await _logger.warning('onvif', 'Falha na descoberta mDNS', details: e.toString());
      return [];
    }
  }

  Future<List<CameraModel>> _discoverViaWSDiscovery(Duration timeout) async {
    await _logger.info('onvif', 'Iniciando descoberta via WS-Discovery');
    
    try {
      // Implementação básica de WS-Discovery
      // Em uma implementação real, seria usado um cliente WS-Discovery adequado
      
      final cameras = <CameraModel>[];
      
      // Por enquanto, retorna lista vazia
      // TODO: Implementar WS-Discovery completo
      
      await _logger.info('onvif', 'Descoberta WS-Discovery concluída', 
          details: '${cameras.length} câmeras encontradas');
      
      return cameras;
      
    } catch (e) {
      await _logger.warning('onvif', 'Falha na descoberta WS-Discovery', 
          details: e.toString());
      return [];
    }
  }

  Future<List<CameraModel>> _discoverViaNetworkScan(Duration timeout) async {
    await _logger.info('onvif', 'Iniciando scan de rede');
    
    try {
      final cameras = <CameraModel>[];
      
      // Obtém informações da rede local
      final networkInfo = NetworkInfo();
      final wifiIP = await networkInfo.getWifiIP();
      
      if (wifiIP == null) {
        await _logger.warning('onvif', 'Não foi possível obter IP da rede');
        return cameras;
      }
      
      // Extrai a rede base (ex: 192.168.1.0/24)
      final ipParts = wifiIP.split('.');
      if (ipParts.length != 4) {
        await _logger.warning('onvif', 'Formato de IP inválido: $wifiIP');
        return cameras;
      }
      
      final networkBase = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';
      
      // Scan paralelo de IPs comuns para câmeras
      final commonPorts = [80, 8080, 554, 8000, 8899];
      final scanTasks = <Future>[];
      
      for (int i = 1; i <= 254; i++) {
        final ip = '$networkBase.$i';
        
        for (final port in commonPorts) {
          scanTasks.add(_scanDevice(ip, port));
        }
      }
      
      // Executa scans com timeout
      final results = await Future.wait(
        scanTasks,
        eagerError: false,
      ).timeout(timeout);
      
      // Coleta resultados válidos
      for (final result in results) {
        if (result is CameraModel) {
          cameras.add(result);
        }
      }
      
      await _logger.info('onvif', 'Scan de rede concluído', 
          details: '${cameras.length} câmeras encontradas');
      
      return cameras;
      
    } catch (e) {
      await _logger.warning('onvif', 'Falha no scan de rede', details: e.toString());
      return [];
    }
  }

  Future<CameraModel?> _scanDevice(String ip, int port) async {
    try {
      // Testa conectividade básica
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      await socket.close();
      
      // Testa se é um dispositivo ONVIF
      final isOnvif = await testConnection(ip, port: port, timeout: const Duration(seconds: 3));
      
      if (isOnvif) {
        final deviceInfo = await getDeviceInfo(ip, port: port, timeout: const Duration(seconds: 5));
        
        return CameraModel(
          id: 'onvif_${ip}_$port',
          name: deviceInfo?.model ?? 'Câmera ONVIF',
          ip: ip,
          port: port,
          type: CameraType.ip,
          connectionUrl: 'rtsp://$ip:554/stream',
          capabilities: CameraCapabilities(
            supportedResolutions: ['1920x1080', '1280x720'],
            supportedCodecs: ['H264', 'H265'],
            hasPTZ: deviceInfo?.capabilities.containsKey('PTZ') ?? false,
            hasAudio: deviceInfo?.capabilities.containsKey('Audio') ?? false,
            hasMotionDetection: true,
          ),
        );
      }
      
      return null;
      
    } catch (e) {
      // Falha silenciosa para não poluir logs
      return null;
    }
  }

  Future<CameraModel?> _createCameraFromMDNS(
    String ip,
    int port,
    String serviceName,
  ) async {
    try {
      final deviceInfo = await getDeviceInfo(ip, port: port);
      
      if (deviceInfo != null) {
        final streamUrls = await getStreamUrls(ip, port: port);
        
        return CameraModel(
          id: 'mdns_${ip}_$port',
          name: deviceInfo.model ?? serviceName,
          ip: ip,
          port: port,
          type: CameraType.ip,
          connectionUrl: streamUrls.isNotEmpty ? streamUrls.first : 'rtsp://$ip:554/stream',
          capabilities: CameraCapabilities(
            supportedResolutions: ['1920x1080', '1280x720'],
            supportedCodecs: ['H264', 'H265'],
            hasPTZ: deviceInfo.capabilities.containsKey('PTZ'),
            hasAudio: deviceInfo.capabilities.containsKey('Audio'),
            hasMotionDetection: true,
          ),
        );
      }
      
      return null;
      
    } catch (e) {
      await _logger.warning('onvif', 'Falha ao criar câmera do mDNS', 
          details: 'IP: $ip, Erro: ${e.toString()}');
      return null;
    }
  }

  Future<Onvif> _getOnvifClient(
    String ip,
    int port,
    Credentials? credentials,
  ) async {
    final clientKey = '$ip:$port';
    
    if (_onvifClients.containsKey(clientKey)) {
      return _onvifClients[clientKey]!;
    }
    
    final onvif = await Onvif.connect(
      host: ip,
      port: port,
      username: credentials?.username,
      password: credentials?.password,
    );
    
    _onvifClients[clientKey] = onvif;
    
    return onvif;
  }

  Map<String, String> _extractCapabilities(dynamic capabilities) {
    final result = <String, String>{};
    
    try {
      // Extrai capacidades do objeto de capacidades ONVIF
      // A implementação específica depende da estrutura retornada pela biblioteca
      
      if (capabilities != null) {
        result['hasDeviceIO'] = 'true';
        result['hasEvents'] = 'true';
        result['hasImaging'] = 'true';
        result['hasMedia'] = 'true';
        result['hasPTZ'] = 'false'; // Será determinado posteriormente
      }
    } catch (e) {
      // Ignora erros de parsing
    }
    
    return result;
  }
}