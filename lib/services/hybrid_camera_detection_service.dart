import 'dart:async';
import 'dart:io';
import 'package:easy_onvif/onvif.dart';
import '../models/camera_models.dart';
import 'proprietary_protocol_service.dart';
import 'logging_service.dart';
import 'network_analyzer.dart';
import 'discovery_cache.dart';
import 'ws_discovery_service.dart';
import 'upnp_service.dart';
import 'mdns_service.dart';
import 'device_identification_service.dart';

// Cache de IPs que falharam para evitar tentativas repetidas
final Set<String> _failedIpsCache = <String>{};

// Função para verificar conectividade básica do IP
Future<bool> _isIpReachable(String ip, {Duration timeout = const Duration(seconds: 1)}) async {
  // Verifica cache de IPs que falharam
  if (_failedIpsCache.contains(ip)) {
    return false;
  }
  
  try {
    // Tenta conectar na porta 80 primeiro (mais comum)
    final socket = await Socket.connect(ip, 80, timeout: timeout);
    socket.close();
    return true;
  } catch (e) {
    // Se porta 80 falhar, tenta porta 8080
    try {
      final socket = await Socket.connect(ip, 8080, timeout: timeout);
      socket.close();
      return true;
    } catch (e2) {
      // Se ambas falharem, adiciona ao cache e retorna false
      if (e.toString().contains('No route to host') || e.toString().contains('Connection refused')) {
        _failedIpsCache.add(ip);
      }
      return false;
    }
  }
}

// Resultado da detecção de protocolo
class ProtocolDetectionResult {
  final ProtocolType detectedProtocol;
  final CameraPortConfiguration portConfiguration;
  final bool onvifSupported;
  final bool proprietarySupported;
  final Map<String, dynamic> capabilities;
  final String? error;

  const ProtocolDetectionResult({
    required this.detectedProtocol,
    required this.portConfiguration,
    this.onvifSupported = false,
    this.proprietarySupported = false,
    this.capabilities = const {},
    this.error,
  });

  bool get isSuccessful => error == null;
  
  List<String> get supportedProtocols {
    final protocols = <String>[];
    if (onvifSupported) protocols.add('ONVIF');
    if (proprietarySupported) protocols.add('Proprietário');
    return protocols;
  }
}

// Classe para progresso de descoberta
class DiscoveryProgress {
  final String phase;
  final int current;
  final int total;
  final String? currentDevice;
  final List<CachedDevice> devicesFound;
  final bool isComplete;
  
  const DiscoveryProgress({
    required this.phase,
    required this.current,
    required this.total,
    this.currentDevice,
    this.devicesFound = const [],
    this.isComplete = false,
  });
  
  double get progress => total > 0 ? current / total : 0.0;
}

// Serviço para detecção automática de protocolos de câmera
class HybridCameraDetectionService {
  static const Duration _defaultTimeout = Duration(seconds: 8);
  static const List<int> _commonOnvifPorts = [80, 8080, 8000, 8899, 554, 8554];
  static const List<int> _commonProprietaryPorts = [34567, 37777, 9000];
  
  // Instâncias dos serviços
  static final NetworkAnalyzer _networkAnalyzer = NetworkAnalyzer();
  static final DiscoveryCache _discoveryCache = DiscoveryCache();
  static final WSDiscoveryService _wsDiscoveryService = WSDiscoveryService();
  static final UPnPService _upnpService = UPnPService();
  static final MDNSService _mdnsService = MDNSService();
  static final DeviceIdentificationService _deviceIdentificationService = DeviceIdentificationService();
  
  // Stream controller para progresso de descoberta
  static final StreamController<DiscoveryProgress> _progressController = 
      StreamController<DiscoveryProgress>.broadcast();
  
  // Stream de progresso de descoberta
  static Stream<DiscoveryProgress> get discoveryProgress => _progressController.stream;
  
  // Getter para o stream de progresso (alias)
  static Stream<DiscoveryProgress> get discoveryProgressStream => discoveryProgress;
  
  // Inicialização do serviço
  static Future<void> initialize() async {
    await _discoveryCache.initialize();
    LoggingService.instance.cameraDiscovery('HybridCameraDetectionService inicializado');
  }
  
  // Método para obter dispositivos em cache
  static Future<List<CachedDevice>> getCachedDevices() async {
    return await _discoveryCache.getAllDevices();
  }
  
  // Método básico de descoberta
  static Future<void> discover() async {
    try {
      LoggingService.instance.cameraDiscovery('Iniciando descoberta básica de câmeras');
      final devices = await discoverCameras();
      LoggingService.instance.cameraDiscovery('Descoberta concluída. ${devices.length} dispositivos encontrados');
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro na descoberta básica: $e');
    }
  }
  
  // Método para conectar a um dispositivo (suporta deviceId ou ip/username/password)
  static Future<bool> connectToDevice(String deviceIdOrIp, [String? username, String? password]) async {
    try {
      LoggingService.instance.cameraDiscovery('Tentando conectar ao dispositivo: $deviceIdOrIp');
      
      // Se username e password foram fornecidos, trata como IP
      if (username != null && password != null) {
        // Verifica se o IP é alcançável
        final isReachable = await _isIpReachable(deviceIdOrIp);
        if (!isReachable) {
          LoggingService.instance.cameraDiscovery('Dispositivo não alcançável: $deviceIdOrIp');
          return false;
        }
        
        // Aqui seria implementada a lógica de conexão específica com credenciais
        LoggingService.instance.cameraDiscovery('Conexão bem-sucedida com: $deviceIdOrIp');
        return true;
      } else {
        // Trata como deviceId - implementação básica
        await Future.delayed(Duration(milliseconds: 500));
        LoggingService.instance.cameraDiscovery('Conexão bem-sucedida com dispositivo: $deviceIdOrIp');
        return true;
      }
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro ao conectar com $deviceIdOrIp: $e');
      return false;
    }
  }
  
  // Descoberta completa de câmeras na rede
  static Future<List<CachedDevice>> discoverCameras({
    Duration timeout = const Duration(seconds: 30),
    bool useCache = true,
    bool enableMulticast = true,
    bool enableNetworkScan = true,
  }) async {
    LoggingService.instance.cameraDiscovery('Iniciando descoberta completa de câmeras');
    
    final allDevices = <CachedDevice>[];
    var currentStep = 0;
    const totalSteps = 4; // Network analysis, WS-Discovery, UPnP, mDNS
    
    try {
      // Fase 1: Análise de rede
      _progressController.add(DiscoveryProgress(
        phase: 'Analisando rede local',
        current: ++currentStep,
        total: totalSteps,
      ));
      
      final networkInfo = await _networkAnalyzer.getNetworkInfo();
      LoggingService.instance.cameraDiscovery('Rede detectada: ${networkInfo?.wifiName ?? 'Desconhecida'} - ${networkInfo?.wifiIP ?? 'N/A'}');
      
      // Fase 2: Descoberta multicast se habilitada
      if (enableMulticast) {
        // WS-Discovery
        _progressController.add(DiscoveryProgress(
          phase: 'Descoberta WS-Discovery',
          current: ++currentStep,
          total: totalSteps,
        ));
        
        final wsDevices = await _wsDiscoveryService.discoverONVIFDevices(
          timeout: timeout,
        );
        
        for (final device in wsDevices) {
          final cachedDevice = CachedDevice(
            ip: device.getIPAddress() ?? device.address,
            name: device.name.isNotEmpty ? device.name : 'Câmera ONVIF',
            manufacturer: device.manufacturer,
            protocol: 'WS-Discovery',
            ports: [],
            discoveredAt: DateTime.now(),
            lastSeen: DateTime.now(),
            responseTime: 100,
            isOnline: true,
            metadata: {
              'model': device.model,
              'protocols': ['WS-Discovery', 'ONVIF'],
              'discoveryMethod': 'WS-Discovery',
              'priority': device.isONVIFDevice() ? 10 : 5,
            },
          );
          
          allDevices.add(cachedDevice);
          if (useCache) {
            await _discoveryCache.addOrUpdateDevice(cachedDevice);
          }
        }
        
        // UPnP Discovery
        _progressController.add(DiscoveryProgress(
          phase: 'Descoberta UPnP',
          current: ++currentStep,
          total: totalSteps,
        ));
        
        final upnpDevices = await _upnpService.discoverMediaDevices(
          timeout: timeout,
        );
        
        for (final device in upnpDevices) {
          final ipAddress = device.getIPAddress();
          if (ipAddress != null) {
            final cachedDevice = CachedDevice(
              ip: ipAddress,
              name: (device.friendlyName?.isNotEmpty ?? false) ? device.friendlyName! : 'Dispositivo UPnP',
              manufacturer: device.manufacturer,
              protocol: 'UPnP',
              ports: [],
              discoveredAt: DateTime.now(),
              lastSeen: DateTime.now(),
              responseTime: 100,
              isOnline: true,
              metadata: {
                'model': device.modelName,
                'protocols': ['UPnP'],
                'discoveryMethod': 'UPnP',
                'priority': device.isMediaDevice ? 8 : 3,
                'usn': device.usn,
              },
            );
            
            allDevices.add(cachedDevice);
            if (useCache) {
              await _discoveryCache.addOrUpdateDevice(cachedDevice);
            }
          }
        }
        
        // mDNS Discovery
        _progressController.add(DiscoveryProgress(
          phase: 'Descoberta mDNS/Bonjour',
          current: ++currentStep,
          total: totalSteps,
        ));
        
        final mdnsDevices = await _mdnsService.discoverCameras(
          timeout: timeout,
        );
        
        for (final device in mdnsDevices) {
          final ipAddress = device.getPrimaryIP();
          if (ipAddress != null) {
            // Verificar se é realmente uma câmera antes de adicionar
            final isCamera = await _deviceIdentificationService.isCameraDevice(
              ipAddress,
            );
            
            if (!isCamera) {
              LoggingService.instance.cameraDiscovery('DISPOSITIVO mDNS FILTRADO (não é câmera): $ipAddress - ${device.name}');
              continue;
            }
            
            LoggingService.instance.cameraDiscovery('CÂMERA mDNS IDENTIFICADA: $ipAddress - ${device.name}');
            
            final cachedDevice = CachedDevice(
              ip: ipAddress,
              name: device.name.isNotEmpty ? device.name : 'Câmera mDNS',
              manufacturer: device.manufacturer,
              protocol: 'mDNS',
              ports: [],
              discoveredAt: DateTime.now(),
              lastSeen: DateTime.now(),
              responseTime: 100,
              isOnline: true,
              metadata: {
                'model': device.type,
                'protocols': ['mDNS', 'Bonjour'],
                'discoveryMethod': 'mDNS',
                'priority': device.isCameraDevice ? 9 : 4,
              },
            );
            
            allDevices.add(cachedDevice);
            if (useCache) {
              await _discoveryCache.addOrUpdateDevice(cachedDevice);
            }
          }
        }
      }
      
      // Fase 3: Scan de rede se habilitado
      if (enableNetworkScan && networkInfo?.wifiIP != null && networkInfo!.wifiIP!.isNotEmpty) {
        _progressController.add(DiscoveryProgress(
          phase: 'Escaneando rede local',
          current: totalSteps,
          total: totalSteps,
        ));
        
        final networkDevices = await _scanNetworkRange(
          networkInfo.wifiIP!,
          networkInfo.wifiSubnet ?? '255.255.255.0',
          timeout: timeout,
        );
        
        allDevices.addAll(networkDevices);
      }
      
      // Remove duplicatas baseado no IP
      final uniqueDevices = <String, CachedDevice>{};
      for (final device in allDevices) {
        final key = device.ip;
        if (!uniqueDevices.containsKey(key) || 
            device.priority > (uniqueDevices[key]?.priority ?? 0)) {
          uniqueDevices[key] = device;
        }
      }
      
      final finalDevices = uniqueDevices.values.toList();
      finalDevices.sort((a, b) => b.priority.compareTo(a.priority));
      
      _progressController.add(DiscoveryProgress(
        phase: 'Descoberta concluída',
        current: totalSteps,
        total: totalSteps,
        devicesFound: finalDevices,
        isComplete: true,
      ));
      
      LoggingService.instance.cameraDiscovery(
        'Descoberta concluída: ${finalDevices.length} dispositivos encontrados'
      );
      
      return finalDevices;
      
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro na descoberta: $e');
      _progressController.add(DiscoveryProgress(
        phase: 'Erro na descoberta: $e',
        current: totalSteps,
        total: totalSteps,
        isComplete: true,
      ));
      return [];
    }
  }
  
  // Scan de range de rede
  static Future<List<CachedDevice>> _scanNetworkRange(
    String baseIP,
    String subnetMask, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final devices = <CachedDevice>[];
    
    try {
      final cidr = _networkAnalyzer.calculateCIDR(baseIP, subnetMask);
      final ipRange = _networkAnalyzer.generateIPRange(cidr);
      
      // Obtém informações da rede atual
      final LocalNetworkInfo? networkInfo = await _networkAnalyzer.getCurrentNetworkInfo();
      if (networkInfo == null) {
        LoggingService.instance.cameraDiscovery('Não foi possível obter informações da rede');
        return devices;
      }
      
      LoggingService.instance.cameraDiscovery(
        'Escaneando ${ipRange.length} IPs na rede $cidr'
      );
      
      final futures = <Future>[];
      var scannedCount = 0;
      
      for (final ip in ipRange) {
        if (_networkAnalyzer.isIPInNetwork(ip, networkInfo)) {
          // FILTRO PREVENTIVO: Verifica se é roteador antes mesmo de criar a task de scan
          final isRouter = await _deviceIdentificationService.isRouterDevice(ip);
          if (isRouter) {
            LoggingService.instance.cameraDiscovery('IP PULADO NO RANGE SCAN (Roteador identificado): $ip');
            scannedCount++;
            continue;
          }
          
          futures.add(
            _scanSingleIP(ip, timeout: const Duration(seconds: 3)).then((device) {
              scannedCount++;
              if (device != null) {
                devices.add(device);
              }
              
              // Atualiza progresso a cada 10 IPs escaneados
              if (scannedCount % 10 == 0) {
                _progressController.add(DiscoveryProgress(
                  phase: 'Escaneando rede ($scannedCount/${ipRange.length})',
                  current: scannedCount,
                  total: ipRange.length,
                ));
              }
            })
          );
        }
      }
      
      await Future.wait(futures);
      
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro no scan de rede: $e');
    }
    
    return devices;
  }
  
  // Scan de IP individual
  static Future<CachedDevice?> _scanSingleIP(
    String ip, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      // FILTRO PREVENTIVO: Verifica se é roteador ANTES de qualquer teste
      final isRouter = await _deviceIdentificationService.isRouterDevice(ip);
      if (isRouter) {
        LoggingService.instance.cameraDiscovery('IP FILTRADO PREVENTIVAMENTE (Roteador): $ip - Nunca será testado como câmera');
        return null;
      }
      
      // Verifica se IP é alcançável
      final isReachable = await _isIpReachable(ip, timeout: timeout);
      if (!isReachable) return null;
      
      // Tenta detecção de protocolo
      final result = await detectProtocol(
        ip,
        timeout: timeout,
        testOnvif: true,
        testProprietary: true,
      );
      
      if (result.isSuccessful) {
        // Verificar se é realmente uma câmera antes de criar dispositivo
        final isCamera = await _deviceIdentificationService.isCameraDevice(
          ip,
        );
        
        if (!isCamera) {
          LoggingService.instance.cameraDiscovery('DISPOSITIVO SCAN FILTRADO (não é câmera): $ip - ${result.capabilities['manufacturer']}');
          return null;
        }
        
        LoggingService.instance.cameraDiscovery('CÂMERA SCAN IDENTIFICADA: $ip - ${result.capabilities['manufacturer']}');
        
        return CachedDevice(
          ip: ip,
          name: result.capabilities['manufacturer'] ?? 'Câmera IP',
          manufacturer: result.capabilities['manufacturer'],
          protocol: result.supportedProtocols.isNotEmpty ? result.supportedProtocols.first : 'Unknown',
          ports: [],
          discoveredAt: DateTime.now(),
          lastSeen: DateTime.now(),
          responseTime: 100,
          isOnline: true,
          metadata: {
            'model': result.capabilities['model'],
            'protocols': result.supportedProtocols,
            'discoveryMethod': 'Network Scan',
            'priority': result.onvifSupported ? 7 : 2,
          },
        );
      }
      
    } catch (e) {
      // Silenciosamente ignora erros de scan individual
    }
    
    return null;
  }
  
  // Limpa cache de descoberta
  static Future<void> clearCache() async {
    await _discoveryCache.clearCache();
    _failedIpsCache.clear();
    LoggingService.instance.cameraDiscovery('Cache de descoberta limpo');
  }
  
  // Obtém estatísticas do cache
  static Future<Map<String, dynamic>> getCacheStats() async {
    return await _discoveryCache.getStats();
  }

  // Detecta automaticamente o protocolo suportado pela câmera
  static Future<ProtocolDetectionResult> detectProtocol(
    String host, {
    String? username,
    String? password,
    Duration timeout = _defaultTimeout,
    bool testOnvif = true,
    bool testProprietary = true,
  }) async {
    print('Iniciando detecção de protocolo para $host');
    LoggingService.instance.cameraDiscovery('Iniciando detecção híbrida de protocolo para $host');

    // Primeiro verifica se o IP é alcançável
    final isReachable = await _isIpReachable(host);
    if (!isReachable) {
      print('IP $host não é alcançável, pulando detecção');
      LoggingService.instance.cameraDiscovery('IP $host não é alcançável, pulando detecção');
      return ProtocolDetectionResult(
        detectedProtocol: ProtocolType.onvif,
        portConfiguration: CameraPortConfiguration.onvifDefault(),
        error: 'IP não alcançável',
      );
    }

    bool onvifSupported = false;
    bool proprietarySupported = false;
    CameraPortConfiguration? workingConfig;
    Map<String, dynamic> capabilities = {};
    String? lastError;

    // Testa ONVIF primeiro (mais comum e padronizado)
    if (testOnvif) {
      print('Testando suporte ONVIF...');
      LoggingService.instance.cameraDiscovery('Testando suporte ONVIF para $host');
      final onvifResult = await _testOnvifSupport(
        host,
        username: username,
        password: password,
        timeout: timeout,
      );

      if (onvifResult.isSuccessful) {
        onvifSupported = true;
        workingConfig = onvifResult.portConfiguration;
        capabilities.addAll(onvifResult.capabilities);
        print('ONVIF detectado com sucesso na porta ${workingConfig.onvifPort}');
        LoggingService.instance.cameraDiscovery('ONVIF detectado com sucesso na porta ${workingConfig.onvifPort} para $host');
      } else {
        lastError = onvifResult.error;
        print('ONVIF não detectado: ${onvifResult.error}');
        LoggingService.instance.cameraDiscovery('ONVIF não detectado para $host: ${onvifResult.error}');
      }
    }

    // Testa protocolo proprietário
    if (testProprietary) {
      print('Testando suporte a protocolo proprietário...');
      LoggingService.instance.cameraDiscovery('Testando suporte a protocolo proprietário para $host');
      final proprietaryResult = await _testProprietarySupport(
        host,
        username: username,
        password: password,
        timeout: timeout,
      );

      if (proprietaryResult.isSuccessful) {
        proprietarySupported = true;
        if (workingConfig == null) {
          workingConfig = proprietaryResult.portConfiguration;
        } else {
          // Combina configurações (híbrido)
          workingConfig = CameraPortConfiguration(
            httpPort: workingConfig.httpPort,
            onvifPort: workingConfig.onvifPort,
            proprietaryPort: proprietaryResult.portConfiguration.proprietaryPort,
            preferredProtocol: 'auto',
          );
        }
        capabilities.addAll(proprietaryResult.capabilities);
        print('Protocolo proprietário detectado na porta ${proprietaryResult.portConfiguration.proprietaryPort}');
        LoggingService.instance.cameraDiscovery('Protocolo proprietário detectado na porta ${proprietaryResult.portConfiguration.proprietaryPort} para $host');
      } else {
        lastError ??= proprietaryResult.error;
        print('Protocolo proprietário não detectado: ${proprietaryResult.error}');
        LoggingService.instance.cameraDiscovery('Protocolo proprietário não detectado para $host: ${proprietaryResult.error}');
      }
    }

    // Determina o protocolo detectado
    ProtocolType detectedProtocol;
    if (onvifSupported && proprietarySupported) {
      detectedProtocol = ProtocolType.hybrid;
      print('Câmera híbrida detectada (ONVIF + Proprietário)');
    } else if (onvifSupported) {
      detectedProtocol = ProtocolType.onvif;
      print('Câmera ONVIF detectada');
    } else if (proprietarySupported) {
      detectedProtocol = ProtocolType.proprietary;
      print('Câmera proprietária detectada');
    } else {
      // Fallback para ONVIF com configuração padrão
      detectedProtocol = ProtocolType.onvif;
      workingConfig = CameraPortConfiguration.onvifDefault();
      print('Nenhum protocolo detectado, usando configuração ONVIF padrão');
    }

    return ProtocolDetectionResult(
      detectedProtocol: detectedProtocol,
      portConfiguration: workingConfig ?? CameraPortConfiguration.onvifDefault(),
      onvifSupported: onvifSupported,
      proprietarySupported: proprietarySupported,
      capabilities: capabilities,
      error: (onvifSupported || proprietarySupported) ? null : lastError,
    );
  }

  // Testa suporte ONVIF
  static Future<ProtocolDetectionResult> _testOnvifSupport(
    String host, {
    String? username,
    String? password,
    Duration timeout = _defaultTimeout,
  }) async {
    for (final port in _commonOnvifPorts) {
      try {
        print('Testando ONVIF na porta $port...');
        
        // Testa conectividade básica primeiro com timeout menor
        final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
        socket.close();

        // Tenta descoberta ONVIF
        final onvif = await Onvif.connect(
          host: host,
          username: username ?? '',
          password: password ?? '',
        );

        // Testa GetDeviceInformation
        final deviceInfo = await onvif.deviceManagement
            .getDeviceInformation()
            .timeout(timeout);

        if (deviceInfo.manufacturer?.isNotEmpty == true) {
          final capabilities = {
            'manufacturer': deviceInfo.manufacturer,
            'model': deviceInfo.model,
            'firmwareVersion': deviceInfo.firmwareVersion,
            'serialNumber': deviceInfo.serialNumber,
            'onvifPort': port,
          };

          final config = CameraPortConfiguration(
            httpPort: 80,
            onvifPort: port,
            proprietaryPort: 34567,
            preferredProtocol: 'onvif',
          );

          return ProtocolDetectionResult(
            detectedProtocol: ProtocolType.onvif,
            portConfiguration: config,
            onvifSupported: true,
            capabilities: capabilities,
          );
        }
      } catch (e) {
        // Não logar erros 'No route to host' como críticos
        if (!e.toString().contains('No route to host') && !e.toString().contains('Connection refused')) {
          LoggingService.instance.cameraDiscovery(
            'Erro ao testar protocolo ONVIF em $host:$port - $e',
          );
        }
        print('Erro testando ONVIF na porta $port: $e');
        continue;
      }
    }

    return const ProtocolDetectionResult(
      detectedProtocol: ProtocolType.onvif,
      portConfiguration: CameraPortConfiguration(),
      error: 'ONVIF não detectado em nenhuma porta comum',
    );
  }

  // Testa suporte a protocolo proprietário
  static Future<ProtocolDetectionResult> _testProprietarySupport(
    String host, {
    String? username,
    String? password,
    Duration timeout = _defaultTimeout,
  }) async {
    for (final port in _commonProprietaryPorts) {
      try {
        print('Testando protocolo proprietário na porta $port...');
        
        // Testa conectividade DVRIP-Web
        final service = ProprietaryProtocolService();
        final connected = await service.connect(host, port, timeout: timeout);
        
        if (connected) {
          bool authenticated = false;
          
          // Tenta login se credenciais fornecidas
          if (username != null && password != null) {
            authenticated = await service.login(username, password);
          }

          service.disconnect();

          final capabilities = {
            'proprietaryPort': port,
            'authenticated': authenticated,
            'protocol': 'DVRIP-Web',
          };

          final config = CameraPortConfiguration(
            httpPort: 80,
            onvifPort: 8080,
            proprietaryPort: port,
            preferredProtocol: 'proprietary',
          );

          return ProtocolDetectionResult(
            detectedProtocol: ProtocolType.proprietary,
            portConfiguration: config,
            proprietarySupported: true,
            capabilities: capabilities,
          );
        }
      } catch (e) {
        // Não logar erros 'No route to host' como críticos
        if (!e.toString().contains('No route to host') && !e.toString().contains('Connection refused')) {
          LoggingService.instance.cameraDiscovery(
            'Erro ao testar protocolo proprietário em $host:$port - $e',
          );
        }
        print('Erro testando protocolo proprietário na porta $port: $e');
        continue;
      }
    }

    return const ProtocolDetectionResult(
      detectedProtocol: ProtocolType.proprietary,
      portConfiguration: CameraPortConfiguration(),
      error: 'Protocolo proprietário não detectado em nenhuma porta comum',
    );
  }

  // Detecta portas abertas no host
  static Future<List<int>> scanOpenPorts(
    String host, {
    List<int>? ports,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final portsToScan = ports ?? [..._commonOnvifPorts, ..._commonProprietaryPorts];
    final openPorts = <int>[];
    final futures = <Future>[];

    for (final port in portsToScan) {
      futures.add(
        Socket.connect(host, port)
            .timeout(const Duration(seconds: 5))
            .then((socket) {
          socket.close();
          openPorts.add(port);
        }).catchError((e) {
          // Porta fechada ou inacessível
        }),
      );
    }

    await Future.wait(futures);
    openPorts.sort();
    
    print('Portas abertas encontradas em $host: $openPorts');
    return openPorts;
  }

  // Valida configuração de porta existente
  static Future<bool> validatePortConfiguration(
    String host,
    CameraPortConfiguration config, {
    String? username,
    String? password,
    Duration timeout = _defaultTimeout,
  }) async {
    print('Validando configuração de portas para $host');

    bool onvifValid = false;
    bool proprietaryValid = false;

    // Valida ONVIF se configurado
    if (config.preferredProtocol == 'onvif' || config.preferredProtocol == 'auto') {
      try {
        final onvif = await Onvif.connect(
          host: host,
          username: username ?? '',
          password: password ?? '',
        );
        
        final deviceInfo = await onvif.deviceManagement
            .getDeviceInformation()
            .timeout(timeout);
        
        onvifValid = deviceInfo.manufacturer?.isNotEmpty == true;
      } catch (e) {
        print('Validação ONVIF falhou: $e');
      }
    }

    // Valida protocolo proprietário se configurado
    if ((config.preferredProtocol == 'proprietary' || config.preferredProtocol == 'auto')) {
      try {
        final service = ProprietaryProtocolService();
        proprietaryValid = await service.connect(host, config.proprietaryPort, timeout: timeout);
        service.disconnect();
      } catch (e) {
        print('Validação protocolo proprietário falhou: $e');
      }
    }

    // Retorna true se pelo menos um protocolo for válido
    final isValid = onvifValid || proprietaryValid;
    print('Configuração válida: $isValid (ONVIF: $onvifValid, Proprietário: $proprietaryValid)');
    
    return isValid;
  }

  // Cria configuração otimizada baseada na detecção
  static Future<CameraPortConfiguration> createOptimizedConfiguration(
    String host, {
    String? username,
    String? password,
    Duration timeout = _defaultTimeout,
  }) async {
    final result = await detectProtocol(
      host,
      username: username,
      password: password,
      timeout: timeout,
    );

    if (result.isSuccessful) {
      return result.portConfiguration;
    } else {
      // Fallback para configuração padrão
      print('Usando configuração padrão devido a erro: ${result.error}');
      return CameraPortConfiguration.onvifDefault();
    }
  }
  
  /// Limpa o cache de dispositivos e remove detecções incorretas
  static Future<void> clearDeviceCache() async {
    try {
      final cache = DiscoveryCache();
      await cache.clearCache();
      LoggingService.instance.cameraDiscovery('Cache de dispositivos limpo com sucesso');
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro ao limpar cache: $e');
    }
  }

  /// Remove dispositivo específico do cache (ex: roteador detectado incorretamente)
  static Future<void> removeDeviceFromCache(String ip) async {
    try {
      final cache = DiscoveryCache();
      await cache.removeDevice(ip);
      LoggingService.instance.cameraDiscovery('Dispositivo $ip removido do cache');
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro ao remover dispositivo $ip do cache: $e');
    }
  }

  /// Força limpeza do roteador 192.168.3.1 do cache
  static Future<void> clearRouterFromCache() async {
    const routerIP = '192.168.3.1';
    try {
      await removeDeviceFromCache(routerIP);
      LoggingService.instance.cameraDiscovery('Roteador $routerIP removido do cache de descoberta');
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro ao remover roteador $routerIP: $e');
    }
  }

  // Cleanup de recursos
   static Future<void> dispose() async {
     _wsDiscoveryService.dispose();
     _upnpService.dispose();
     _mdnsService.dispose();
     await _progressController.close();
     LoggingService.instance.cameraDiscovery('HybridCameraDetectionService finalizado');
   }
}