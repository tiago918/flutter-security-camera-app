import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:http/http.dart' as http;
import 'device_identification_service.dart';
import 'device_blacklist_service.dart';

/// Modelo para dispositivo mDNS descoberto
class MDNSDevice {
  final String name;
  final String type;
  final String domain;
  final String? host;
  final int? port;
  final List<InternetAddress> addresses;
  final Map<String, String> txt;
  final DateTime discoveredAt;
  
  MDNSDevice({
    required this.name,
    required this.type,
    required this.domain,
    this.host,
    this.port,
    required this.addresses,
    required this.txt,
    required this.discoveredAt,
  });
  
  /// Nome completo do serviço
  String get fullName => '$name.$type.$domain';
  
  /// IP principal do dispositivo
  String? get primaryIP {
    if (addresses.isEmpty) return null;
    
    // Prefere IPv4
    final ipv4 = addresses.where((addr) => addr.type == InternetAddressType.IPv4);
    if (ipv4.isNotEmpty) {
      return ipv4.first.address;
    }
    
    return addresses.first.address;
  }
  
  /// Método para obter IP principal (alias)
  String? getPrimaryIP() => primaryIP;
  
  /// Verifica se é um dispositivo de câmera/vídeo com heurísticas melhoradas
  bool get isCameraDevice {
    // Usa identificação positiva em vez de blacklist
    // Esta é uma verificação rápida baseada em heurísticas
    // Para identificação completa, use DeviceIdentificationService.identifyDevice()

    final lowerType = type.toLowerCase();
    final lowerName = name.toLowerCase();
    
    // Verifica tipo de serviço específico de câmeras
    if (lowerType.contains('camera') ||
        lowerType.contains('video') ||
        lowerType.contains('rtsp') ||
        lowerType.contains('onvif') ||
        lowerType.contains('axis') ||
        lowerType.contains('hikvision') ||
        lowerType.contains('ipcam') ||
        lowerType.contains('webcam')) {
      return true;
    }
    
    // Verifica nome do dispositivo com palavras-chave mais específicas
    final cameraKeywords = [
      'camera', 'cam', 'ipcam', 'webcam', 'cctv', 'nvr', 'dvr',
      'hikvision', 'dahua', 'axis', 'bosch security', 'sony camera', 
      'panasonic camera', 'vivotek', 'acti', 'geovision', 'milestone', 
      'avigilon', 'foscam', 'amcrest', 'reolink', 'lorex', 'swann',
      'annke', 'zosi', 'floureon', 'sricam', 'wansview', 'tenvis'
    ];
    
    bool hasPositiveMatch = cameraKeywords.any((keyword) => lowerName.contains(keyword));
    
    // Se encontrou palavra-chave de câmera, verifica se não é falso positivo
    if (hasPositiveMatch) {
      // Verifica se não contém palavras que indicam outros dispositivos
      final excludeKeywords = ['router', 'printer', 'tv', 'nas', 'server'];
      if (excludeKeywords.any((keyword) => lowerName.contains(keyword))) {
        return false;
      }
      return true;
    }
    
    // Verifica registros TXT para indicadores de câmera
    int cameraIndicators = 0;
    for (final entry in txt.entries) {
      final key = entry.key.toLowerCase();
      final value = entry.value.toLowerCase();
      
      // Verifica palavras-chave específicas de câmera
      if (cameraKeywords.any((keyword) => value.contains(keyword))) {
        cameraIndicators++;
      }
      
      // Verifica campos específicos que indicam câmera
      if ((key.contains('model') || key.contains('device')) && 
          (value.contains('ip') && (value.contains('cam') || value.contains('camera')))) {
        cameraIndicators++;
      }
      
      // Verifica se há informações de streaming
      if (key.contains('stream') || key.contains('rtsp') || key.contains('onvif')) {
        cameraIndicators++;
      }
    }

    // Considera câmera se tem pelo menos 2 indicadores
    return cameraIndicators >= 2;
  }
  
  /// Verifica se é um serviço HTTP
  bool get isHttpService {
    return type.contains('_http') || port == 80 || port == 8080 || port == 443;
  }
  
  /// Verifica se é um serviço RTSP
  bool get isRtspService {
    return type.contains('_rtsp') || port == 554;
  }
  
  /// Obtém URL base do dispositivo
  String? get baseUrl {
    if (primaryIP == null || port == null) return null;
    
    final scheme = (port == 443) ? 'https' : 'http';
    return '$scheme://$primaryIP:$port';
  }
  
  /// Obtém informações do fabricante
  String? get manufacturer {
    return txt['manufacturer'] ?? 
           txt['vendor'] ?? 
           txt['make'] ??
           txt['brand'];
  }
  
  /// Obtém modelo do dispositivo
  String? get model {
    return txt['model'] ?? 
           txt['product'] ??
           txt['device'];
  }
  
  @override
  String toString() {
    return 'MDNSDevice(name: $name, type: $type, ip: $primaryIP, port: $port, camera: $isCameraDevice)';
  }
}

/// Service para descoberta mDNS (Multicast DNS / Bonjour / Zeroconf)
class MDNSService {
  static const Duration _defaultTimeout = Duration(seconds: 10);
  
  final StreamController<MDNSDevice> _deviceController = StreamController.broadcast();
  final List<MDNSDevice> _discoveredDevices = [];
  final DeviceIdentificationService _identificationService = DeviceIdentificationService();
  final DeviceBlacklistService _deviceBlacklistService = DeviceBlacklistService();
  
  /// Getter para o serviço de blacklist
  DeviceBlacklistService get _blacklistService => _deviceBlacklistService;
  
  MDnsClient? _mdnsClient;
  bool _isDiscovering = false;
  Timer? _timeoutTimer;
  
  // Controle de erro reusePort
  bool _hasReusePortError = false;
  bool _fallbackModeEnabled = false;
  int _reusePortRetryCount = 0;
  static const int _maxReusePortRetries = 2;
  
  /// Stream de dispositivos descobertos
  Stream<MDNSDevice> get deviceStream => _deviceController.stream;
  
  /// Lista de dispositivos descobertos
  List<MDNSDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  
  /// Verifica se houve erro reusePort
  bool get hasReusePortError => _hasReusePortError;
  
  /// Verifica se está em modo fallback
  bool get isFallbackMode => _fallbackModeEnabled;
  
  /// Obtém o número de tentativas de retry do reusePort
  int get reusePortRetryCount => _reusePortRetryCount;
  
  /// Inicia descoberta mDNS
  Future<List<MDNSDevice>> discover({
    Duration timeout = _defaultTimeout,
    List<String>? serviceTypes,
    bool validateHttp = true,
  }) async {
    if (_isDiscovering) {
      throw StateError('Descoberta já está em andamento');
    }
    
    _isDiscovering = true;
    _discoveredDevices.clear();
    
    try {
      // Tenta descoberta mDNS normal primeiro
      if (!_fallbackModeEnabled) {
        try {
          return await _performNormalDiscovery(timeout: timeout, serviceTypes: serviceTypes, validateHttp: validateHttp);
        } catch (e) {
          // Verifica se é erro reusePort
          if (_isReusePortError(e)) {
            print('MDNSService: Erro reusePort detectado: $e');
            _hasReusePortError = true;
            _reusePortRetryCount++;
            
            // Tenta retry se ainda não excedeu o limite
            if (_reusePortRetryCount <= _maxReusePortRetries) {
              print('MDNSService: Tentativa ${_reusePortRetryCount} de $_maxReusePortRetries para resolver reusePort');
              await Future.delayed(Duration(seconds: _reusePortRetryCount * 2));
              return await discover(timeout: timeout, serviceTypes: serviceTypes, validateHttp: validateHttp);
            } else {
              print('MDNSService: Limite de tentativas excedido. Ativando modo fallback.');
              _fallbackModeEnabled = true;
            }
          } else {
            // Outro tipo de erro, relança
            rethrow;
          }
        }
      }
      
      // Modo fallback: descoberta simplificada
      print('MDNSService: Executando descoberta em modo fallback');
      return await _performFallbackDiscovery(timeout: timeout, serviceTypes: serviceTypes);
      
    } catch (e) {
      print('MDNSService: Erro na descoberta: $e');
      return [];
    } finally {
      _isDiscovering = false;
    }
  }
  
  /// Verifica se o erro é relacionado ao reusePort
  bool _isReusePortError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('reuseport') ||
           errorString.contains('address already in use') ||
           errorString.contains('bind failed') ||
           errorString.contains('socket exception') ||
           errorString.contains('address in use');
  }
  
  /// Executa descoberta mDNS normal
  Future<List<MDNSDevice>> _performNormalDiscovery({
    Duration timeout = _defaultTimeout,
    List<String>? serviceTypes,
    bool validateHttp = true,
  }) async {
    print('MDNSService: Iniciando descoberta mDNS...');
    
    _mdnsClient = MDnsClient();
    await _mdnsClient!.start();
    
    // Lista de tipos de serviço para buscar
    final typesToSearch = serviceTypes ?? [
      '_http._tcp',
      '_https._tcp',
      '_rtsp._tcp',
      '_onvif._tcp',
      '_axis-video._tcp',
      '_hikvision._tcp',
      '_dahua._tcp',
      '_camera._tcp',
      '_nvr._tcp',
      '_dvr._tcp',
      '_ipp._tcp',
      '_printer._tcp',
      '_device-info._tcp',
      '_workstation._tcp',
    ];
    
    // Inicia descoberta para cada tipo
    final futures = typesToSearch.map((type) => _discoverServiceType(type));
    
    // Configura timeout
    final completer = Completer<List<MDNSDevice>>();
    _timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(_discoveredDevices);
      }
    });
    
    // Aguarda todas as descobertas
    await Future.wait(futures);
    
    // Valida dispositivos HTTP se solicitado
    if (validateHttp) {
      await _validateHttpDevices();
    }
    
    if (!completer.isCompleted) {
      completer.complete(_discoveredDevices);
    }
    
    final result = await completer.future;
    await _cleanup();
    
    return result;
  }
  
  /// Executa descoberta em modo fallback (sem mDNS)
  Future<List<MDNSDevice>> _performFallbackDiscovery({
    Duration timeout = _defaultTimeout,
    List<String>? serviceTypes,
  }) async {
    print('MDNSService: Iniciando descoberta fallback (sem mDNS)');
    
    // Em modo fallback, retorna lista vazia para forçar uso do port scanner
    // O HybridDiscoveryService detectará isso e usará apenas o port scanner
    print('MDNSService: Modo fallback ativo - delegando para port scanner');
    
    return [];
  }
  
  /// Descobre serviços de um tipo específico
  Future<void> _discoverServiceType(String serviceType) async {
    try {
      print('MDNSService: Buscando serviços $serviceType...');
      
      await for (final PtrResourceRecord ptr in _mdnsClient!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
      )) {
        if (!_isDiscovering) break;
        
        try {
          await _resolveService(ptr.domainName, serviceType);
        } catch (e) {
          print('MDNSService: Erro ao resolver ${ptr.domainName}: $e');
        }
      }
      
    } catch (e) {
      print('MDNSService: Erro ao buscar $serviceType: $e');
    }
  }
  
  /// Resolve informações detalhadas do serviço
  Future<void> _resolveService(String serviceName, String serviceType) async {
    try {
      String? host;
      int? port;
      final addresses = <InternetAddress>[];
      final txt = <String, String>{};
      
      // Busca registro SRV (host e porta)
      await for (final SrvResourceRecord srv in _mdnsClient!.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(serviceName),
      )) {
        host = srv.target;
        port = srv.port;
        break;
      }
      
      if (host == null || port == null) return;
      
      // Busca registros A/AAAA (endereços IP)
      await for (final IPAddressResourceRecord ip in _mdnsClient!.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(host),
      )) {
        addresses.add(ip.address);
      }
      
      await for (final IPAddressResourceRecord ip in _mdnsClient!.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv6(host),
      )) {
        addresses.add(ip.address);
      }
      
      // Busca registros TXT (informações adicionais)
      await for (final TxtResourceRecord txtRecord in _mdnsClient!.lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(serviceName),
      )) {
        // txtRecord.text é uma String, então fazemos split por vírgula ou ponto e vírgula
        final textEntries = txtRecord.text.split(RegExp(r'[,;]'));
        for (final String entry in textEntries) {
          final trimmedEntry = entry.trim();
          if (trimmedEntry.isNotEmpty) {
            final parts = trimmedEntry.split('=');
            if (parts.length >= 2) {
              txt[parts[0]] = parts.sublist(1).join('=');
            } else if (parts.length == 1) {
              txt[parts[0]] = '';
            }
          }
        }
        break;
      }
      
      // Extrai nome do serviço
      final nameParts = serviceName.split('.');
      final name = nameParts.isNotEmpty ? nameParts.first : serviceName;
      final domain = nameParts.length > 2 ? nameParts.sublist(2).join('.') : 'local';
      
      final device = MDNSDevice(
        name: name,
        type: serviceType,
        domain: domain,
        host: host,
        port: port,
        addresses: addresses,
        txt: txt,
        discoveredAt: DateTime.now(),
      );
      
      // Verifica se já foi descoberto
      final existing = _discoveredDevices.firstWhere(
        (d) => d.fullName == device.fullName,
        orElse: () => device,
      );
      
      if (existing == device && addresses.isNotEmpty) {
        _discoveredDevices.add(device);
        _deviceController.add(device);
        print('MDNSService: Dispositivo descoberto: ${device.name} (${device.primaryIP})');
      }
      
    } catch (e) {
      print('MDNSService: Erro ao resolver $serviceName: $e');
    }
  }
  
  /// Descobre dispositivos de câmera especificamente (alias)
  Future<List<MDNSDevice>> discoverCameras({
    Duration timeout = _defaultTimeout,
  }) async {
    return await discoverCameraDevices(timeout: timeout);
  }

  /// Descobre dispositivos de câmera especificamente
  Future<List<MDNSDevice>> discoverCameraDevices({
    Duration timeout = _defaultTimeout,
  }) async {
    final cameraServiceTypes = [
      '_rtsp._tcp',
      '_onvif._tcp',
      '_axis-video._tcp',
      '_hikvision._tcp',
      '_dahua._tcp',
      '_camera._tcp',
      '_nvr._tcp',
      '_dvr._tcp',
    ];
    
    final devices = await discover(
      timeout: timeout,
      serviceTypes: cameraServiceTypes,
    );
    
    return devices.where((device) => device.isCameraDevice).toList();
  }
  
  /// Descobre serviços HTTP/HTTPS
  Future<List<MDNSDevice>> discoverHttpServices({
    Duration timeout = _defaultTimeout,
  }) async {
    final httpServiceTypes = [
      '_http._tcp',
      '_https._tcp',
    ];
    
    final devices = await discover(
      timeout: timeout,
      serviceTypes: httpServiceTypes,
    );
    
    return devices.where((device) => device.isHttpService).toList();
  }
  
  /// Descobre todos os tipos de serviços
  Future<List<MDNSDevice>> discoverAllServices({
    Duration timeout = _defaultTimeout,
  }) async {
    return await discover(timeout: timeout);
  }
  
  /// Busca um serviço específico por nome
  Future<MDNSDevice?> findServiceByName(
    String serviceName, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();
      
      // Tenta diferentes tipos de serviço
      final serviceTypes = ['_http._tcp', '_https._tcp', '_rtsp._tcp'];
      
      for (final serviceType in serviceTypes) {
        final fullName = '$serviceName.$serviceType.local';
        
        try {
          await _resolveService(fullName, serviceType);
          
          final device = _discoveredDevices.firstWhere(
            (d) => d.name.toLowerCase() == serviceName.toLowerCase(),
            orElse: () => throw StateError('Not found'),
          );
          
          return device;
        } catch (e) {
          continue;
        }
      }
      
      return null;
      
    } catch (e) {
      print('MDNSService: Erro ao buscar $serviceName: $e');
      return null;
    } finally {
      await _cleanup();
    }
  }
  
  /// Valida dispositivos HTTP para verificar se são realmente câmeras
  Future<void> _validateHttpDevices() async {
    final httpDevices = _discoveredDevices.where((device) => 
        device.isHttpService && device.isCameraDevice).toList();
    
    final List<MDNSDevice> validatedDevices = [];
    
    for (final device in httpDevices) {
      try {
        final isValidCamera = await _validateCameraHttpResponse(device);
        if (isValidCamera) {
          validatedDevices.add(device);
        }
      } catch (e) {
        print('Erro ao validar dispositivo ${device.name}: $e');
        // Em caso de erro, mantém o dispositivo (pode ser problema de rede)
        validatedDevices.add(device);
      }
    }
    
    // Remove dispositivos HTTP que não passaram na validação
    _discoveredDevices.removeWhere((device) => 
        device.isHttpService && device.isCameraDevice && 
        !validatedDevices.contains(device));
  }
  
  /// Valida se a resposta HTTP indica uma câmera real
  Future<bool> _validateCameraHttpResponse(MDNSDevice device) async {
    final ip = device.getPrimaryIP();
    if (ip == null) return false;
    
    final urls = [
      'http://$ip:${device.port}/',
      'http://$ip:${device.port}/index.html',
      'http://$ip:${device.port}/login.html',
      'http://$ip:${device.port}/web/',
      'http://$ip:${device.port}/onvif/',
    ];
    
    for (final url in urls) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Camera Discovery Service'},
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final content = response.body.toLowerCase();
          
          // Verifica se a resposta indica que NÃO é uma câmera
          if (_blacklistService.isNonCameraHttpResponse(content)) {
            return false;
          }
          
          // Verifica indicadores positivos de câmera
          final cameraIndicators = [
            'camera', 'video', 'stream', 'rtsp', 'onvif',
            'surveillance', 'security', 'nvr', 'dvr',
            'hikvision', 'dahua', 'axis', 'bosch',
            'live view', 'playback', 'recording',
            'motion detection', 'alarm',
          ];
          
          int positiveMatches = 0;
          for (final indicator in cameraIndicators) {
            if (content.contains(indicator)) {
              positiveMatches++;
            }
          }
          
          // Se encontrou pelo menos 2 indicadores positivos, considera câmera
          if (positiveMatches >= 2) {
            return true;
          }
        }
      } catch (e) {
        // Continua tentando outras URLs
        continue;
      }
    }
    
    // Se não conseguiu validar, assume que pode ser câmera (evita falsos negativos)
    return true;
  }

  /// Para a descoberta atual
  Future<void> stopDiscovery() async {
    await _cleanup();
  }
  
  /// Limpa recursos
  Future<void> _cleanup() async {
    _isDiscovering = false;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    
    if (_mdnsClient != null) {
      try {
        _mdnsClient!.stop();
      } catch (e) {
        print('MDNSService: Erro ao parar cliente mDNS: $e');
      }
      _mdnsClient = null;
    }
  }
  
  /// Reseta o estado de erro reusePort (para testes)
  void resetReusePortError() {
    _hasReusePortError = false;
    _fallbackModeEnabled = false;
    _reusePortRetryCount = 0;
    print('MDNSService: Estado de erro reusePort resetado');
  }
  
  /// Obtém estatísticas da descoberta
  Map<String, dynamic> getStatistics() {
    final cameraDevices = _discoveredDevices.where((d) => d.isCameraDevice).length;
    final httpServices = _discoveredDevices.where((d) => d.isHttpService).length;
    final rtspServices = _discoveredDevices.where((d) => d.isRtspService).length;
    final uniqueIPs = _discoveredDevices
        .map((d) => d.primaryIP)
        .where((ip) => ip != null)
        .toSet()
        .length;
    
    return {
      'totalServices': _discoveredDevices.length,
      'cameraDevices': cameraDevices,
      'httpServices': httpServices,
      'rtspServices': rtspServices,
      'uniqueIPs': uniqueIPs,
      'isDiscovering': _isDiscovering,
    };
  }
  
  /// Dispose do service
  void dispose() {
    _cleanup();
    _deviceController.close();
  }
}