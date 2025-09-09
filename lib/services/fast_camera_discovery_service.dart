import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/camera_models.dart';
import '../constants/camera_ports.dart';
import 'ws_discovery_service.dart';
import 'mdns_service.dart';
import 'onvif_capabilities_service.dart';
import 'logging_service.dart';
import 'device_identification_service.dart';

/// Câmera descoberta com informações básicas
class DiscoveredCamera {
  final String ip;
  final String name;
  final List<String> protocols;
  final Map<String, dynamic> metadata;
  final DateTime discoveredAt;

  DiscoveredCamera({
    required this.ip,
    required this.name,
    required this.protocols,
    this.metadata = const {},
  }) : discoveredAt = DateTime.now();

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'name': name,
    'protocols': protocols,
    'metadata': metadata,
    'discoveredAt': discoveredAt.toIso8601String(),
  };

  factory DiscoveredCamera.fromJson(Map<String, dynamic> json) => DiscoveredCamera(
    ip: json['ip'],
    name: json['name'],
    protocols: List<String>.from(json['protocols']),
    metadata: json['metadata'] ?? {},
  );
}

/// Progresso da descoberta de câmeras
class CameraDiscoveryProgress {
  final String phase;
  final int current;
  final int total;
  final bool isComplete;
  final String? currentDevice;
  final List<DiscoveredCamera> discoveredCameras;

  CameraDiscoveryProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.isComplete,
    this.currentDevice,
    this.discoveredCameras = const [],
  });
}

/// Serviço otimizado para descoberta rápida de câmeras IP
class FastCameraDiscoveryService {
  static final StreamController<CameraDiscoveryProgress> _progressController =
      StreamController<CameraDiscoveryProgress>.broadcast();
  
  static Stream<CameraDiscoveryProgress> get discoveryProgressStream => _progressController.stream;
  
  static final List<DiscoveredCamera> _discoveredCameras = [];
  static final DeviceIdentificationService _deviceIdentificationService = DeviceIdentificationService();
  static bool _isInitialized = false;
  static bool _isDiscovering = false;
  // Scan em segundo plano removido - mantendo apenas scan direto

  /// Inicializa o serviço
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isInitialized = true;
    LoggingService.instance.cameraDiscovery('FastCameraDiscoveryService inicializado');
  }

  /// Finaliza o serviço
  static void dispose() {
    _progressController.close();
    _discoveredCameras.clear();
    _isInitialized = false;
    LoggingService.instance.cameraDiscovery('FastCameraDiscoveryService finalizado');
  }

  // Funções de scan em segundo plano removidas - mantendo apenas descoberta direta

  /// Detecta protocolos suportados pela câmera
  static Future<List<String>> _detectPortProtocols(String ip, int port) async {
    final protocols = <String>[];
    
    try {
      // Testa HTTP/HTTPS
      if (port == 80 || port == 8080 || port == 8081 || port == 8000 || port == 8888 || port == 8899 || port == 9000 || port == 10080) {
        if (await _testHttpProtocol(ip, port)) {
          protocols.add('HTTP');
          
          // Testes específicos para cada porta
          final portFunction = await _identifyPortFunction(ip, port);
          if (portFunction.isNotEmpty) {
            protocols.add(portFunction);
          }
        }
      }
      
      // Testa RTSP
      if (port == 554 || port == 8554) {
        if (await _testRtspProtocol(ip, port)) {
          protocols.add('RTSP');
          protocols.add('Streaming de Vídeo');
        }
      }
      
      // Testa protocolos proprietários
      if (port == 37777 || port == 34567) {
        if (await _testProprietaryProtocol(ip, port)) {
          protocols.add('Proprietário');
          if (port == 37777) {
            protocols.add('Dahua/Hikvision');
          } else if (port == 34567) {
            protocols.add('Controle Remoto');
          }
        }
      }
      
      // Testa RTMP
      if (port == 1935) {
        if (await _testRtmpProtocol(ip, port)) {
          protocols.add('RTMP');
          protocols.add('Streaming Live');
        }
      }
      
      // Testa outros protocolos
      if (port == 7001) {
        if (await _testOtherProtocol(ip, port)) {
          protocols.add('Outros');
          protocols.add('Configuração Avançada');
        }
      }
      
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro ao detectar protocolos para $ip:$port - $e');
    }
    
    return protocols;
  }

  /// Identifica a função específica de cada porta
  static Future<String> _identifyPortFunction(String ip, int port) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      
      final request = await client.getUrl(Uri.parse('http://$ip:$port/'));
      final response = await request.close();
      
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();
      
      // Análise específica por porta
      switch (port) {
        case 80:
          if (responseBody.toLowerCase().contains('camera') || 
              responseBody.toLowerCase().contains('webcam')) {
            return 'Interface Web Principal';
          }
          return 'Servidor Web Padrão';
          
        case 8080:
          if (responseBody.toLowerCase().contains('admin') ||
              responseBody.toLowerCase().contains('config')) {
            return 'Painel Administrativo';
          }
          return 'Servidor Web Alternativo';
          
        case 8081:
          return 'Interface de Configuração';
          
        case 8000:
          if (responseBody.toLowerCase().contains('stream') ||
              responseBody.toLowerCase().contains('video')) {
            return 'Servidor de Streaming';
          }
          return 'Servidor Web Customizado';
          
        case 8888:
          return 'Interface de Monitoramento';
          
        case 8899:
          if (responseBody.toLowerCase().contains('mobile') ||
              responseBody.toLowerCase().contains('app')) {
            return 'Interface Mobile/App';
          } else if (responseBody.toLowerCase().contains('api')) {
            return 'API REST';
          } else if (responseBody.toLowerCase().contains('stream')) {
            return 'Streaming Secundário';
          }
          return 'Porta Personalizada 8899';
          
        case 9000:
          return 'Serviços Avançados';
          
        case 10080:
          return 'Interface Backup';
          
        default:
          return 'Função Desconhecida';
      }
      
    } catch (e) {
      // Tenta identificar pela porta mesmo sem resposta HTTP
      switch (port) {
        case 8899:
          return 'Porta 8899 - Possivelmente Mobile/API';
        default:
          return '';
      }
    }
  }

  /// Testa protocolo HTTP
  static Future<bool> _testHttpProtocol(String ip, int port) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      
      final request = await client.getUrl(Uri.parse('http://$ip:$port/'));
      final response = await request.close();
      
      client.close();
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      return false;
    }
  }

  /// Testa protocolo RTSP
  static Future<bool> _testRtspProtocol(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      
      // Envia comando RTSP OPTIONS
      socket.write('OPTIONS rtsp://$ip:$port RTSP/1.0\r\nCSeq: 1\r\n\r\n');
      
      final response = await utf8.decoder.bind(socket).take(1).join().timeout(const Duration(seconds: 2));
      await socket.close();
      
      return response.contains('RTSP/1.0') || response.contains('OPTIONS');
    } catch (e) {
      return false;
    }
  }

  /// Testa protocolos proprietários
  static Future<bool> _testProprietaryProtocol(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      await socket.close();
      return true; // Se conectou, assume que é um protocolo proprietário
    } catch (e) {
      return false;
    }
  }

  /// Testa protocolo RTMP
  static Future<bool> _testRtmpProtocol(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      await socket.close();
      return true; // Se conectou na porta 1935, assume RTMP
    } catch (e) {
      return false;
    }
  }

  /// Testa outros protocolos
  static Future<bool> _testOtherProtocol(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Descoberta rápida de câmeras (máximo 5 segundos)
  static Future<List<DiscoveredCamera>> discover() async {
    if (_isDiscovering) return _discoveredCameras;
    
    _isDiscovering = true;
    _discoveredCameras.clear();
    
    try {
      // Fase 1: WS-Discovery ONVIF (2 segundos)
      await _discoverOnvifDevices();
      
      // Fase 2: mDNS para câmeras (2 segundos)
      await _discoverMdnsCameras();
      
      // Fase 3: Scan rápido de portas ONVIF (1 segundo)
      await _quickPortScan();
      
      _emitProgress('Concluído', 3, 3, true);
      
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro na descoberta: $e');
    } finally {
      _isDiscovering = false;
    }
    
    return List.from(_discoveredCameras);
  }

  /// Descoberta ultra-rápida apenas com ONVIF (2 segundos)
  static Future<List<DiscoveredCamera>> quickScan() async {
    if (_isDiscovering) return _discoveredCameras;
    
    _isDiscovering = true;
    _discoveredCameras.clear();
    
    try {
      await _discoverOnvifDevices();
      _emitProgress('Scan rápido concluído', 1, 1, true);
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro no scan rápido: $e');
    } finally {
      _isDiscovering = false;
    }
    
    return List.from(_discoveredCameras);
  }

  /// Fase 1: Descoberta ONVIF via WS-Discovery
  static Future<void> _discoverOnvifDevices() async {
    _emitProgress('Descobrindo câmeras ONVIF...', 1, 3, false);
    
    try {
      final wsService = WSDiscoveryService();
      final devices = await wsService.discover(timeout: const Duration(seconds: 2));
      
      for (final device in devices) {
        if (device.isOnvifDevice) {
          // Verificar se é realmente uma câmera antes de adicionar
          final isCamera = await _deviceIdentificationService.isCameraDevice(
            device.deviceIP ?? '',
            port: 80,
          );
          
          if (!isCamera) {
            LoggingService.instance.cameraDiscovery('DISPOSITIVO ONVIF FILTRADO (não é câmera): ${device.deviceIP}');
            continue;
          }
          
          LoggingService.instance.cameraDiscovery('CÂMERA ONVIF IDENTIFICADA: ${device.deviceIP}');
          
          final camera = DiscoveredCamera(
            ip: device.deviceIP ?? '',
            name: device.name ?? 'Câmera ONVIF',
            protocols: ['ONVIF'],
            metadata: {
              'manufacturer': device.manufacturer,
              'model': device.model,
              'xAddr': device.address,
            },
          );
          
          if (!_isDuplicate(camera)) {
            _discoveredCameras.add(camera);
            LoggingService.instance.cameraDiscovery('ONVIF encontrado: ${camera.ip}');
          }
        }
      }
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro WS-Discovery: $e');
    }
  }

  /// Fase 2: Descoberta mDNS para câmeras
  static Future<void> _discoverMdnsCameras() async {
    _emitProgress('Descobrindo via mDNS...', 2, 3, false);
    
    try {
      final mdnsService = MDNSService();
      final devices = await mdnsService.discover(
        serviceTypes: ['_rtsp._tcp', '_onvif._tcp'],
        timeout: const Duration(seconds: 2),
      );
      
      for (final device in devices) {
        if (device.isCameraDevice) {
          final protocols = <String>[];
          if (device.type.contains('_rtsp._tcp')) protocols.add('RTSP');
          if (device.type.contains('_onvif._tcp')) protocols.add('ONVIF');
          
          // Verificar se é realmente uma câmera antes de adicionar
          final isCamera = await _deviceIdentificationService.isCameraDevice(
            device.primaryIP ?? 'Unknown',
            port: device.port,
          );
          
          if (!isCamera) {
            LoggingService.instance.cameraDiscovery('DISPOSITIVO mDNS FILTRADO (não é câmera): ${device.primaryIP}');
            continue;
          }
          
          LoggingService.instance.cameraDiscovery('CÂMERA mDNS IDENTIFICADA: ${device.primaryIP}');
          
          final camera = DiscoveredCamera(
            ip: device.primaryIP ?? 'Unknown',
            name: device.name ?? 'Câmera IP',
            protocols: protocols,
            metadata: {
              'port': device.port,
              'serviceTypes': [device.type],
            },
          );
          
          if (!_isDuplicate(camera)) {
            _discoveredCameras.add(camera);
            LoggingService.instance.cameraDiscovery('mDNS encontrado: ${camera.ip}');
          }
        }
      }
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro mDNS: $e');
    }
  }

  /// Fase 3: Scan completo de portas para câmeras IP
  static Future<void> _quickPortScan() async {
    _emitProgress('Scan completo de portas...', 3, 3, false);
    
    try {
      final subnet = await _getLocalSubnet();
      if (subnet == null) return;
      
      final futures = <Future>[];
      // Portas comuns para câmeras IP - usando constantes do CameraPorts
      final cameraPorts = CameraPorts.getIntelligentDiscoveryPorts();
      
      LoggingService.instance.cameraDiscovery('Iniciando scan completo da subnet $subnet.1-254');
      
      // Scan toda a subnet (1-254)
      for (int i = 1; i <= 254; i++) {
        final ip = '$subnet.$i';
        for (final port in cameraPorts) {
          futures.add(_checkCameraPort(ip, port));
        }
      }
      
      // Aguarda até 10 segundos para scan completo
      await Future.wait(futures).timeout(const Duration(seconds: 10));
      LoggingService.instance.cameraDiscovery('Scan completo finalizado. Câmeras encontradas: ${_discoveredCameras.length}');
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro port scan: $e');
    }
  }

  /// Verifica se uma porta de câmera está aberta e detecta o protocolo
  static Future<void> _checkCameraPort(String ip, int port) async {
    try {
      // Timeout aumentado para 3 segundos
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      await socket.close();
      
      LoggingService.instance.cameraDiscovery('Porta aberta detectada: $ip:$port - verificando protocolo...');
      
      // Detecta o protocolo da câmera
      final protocols = <String>[];
      String cameraName = 'Câmera IP';
      
      // Verifica ONVIF
      if (await _isOnvifDevice(ip, port)) {
        protocols.add('ONVIF');
        cameraName = 'Câmera ONVIF';
      }
      
      // Verifica RTSP
      if (port == 554 || await _isRtspDevice(ip, port)) {
        protocols.add('RTSP');
        if (cameraName == 'Câmera IP') cameraName = 'Câmera RTSP';
      }
      
      // Verifica HTTP/Web interface
      if (port == 80 || port == 8080 || port == 8000 || port == 8888) {
        if (await _isWebInterface(ip, port)) {
          protocols.add('HTTP');
          if (cameraName == 'Câmera IP') cameraName = 'Câmera Web';
        }
      }
      
      // Se encontrou algum protocolo ou é uma porta comum de câmera, adiciona
      if (protocols.isNotEmpty || _isCommonCameraPort(port)) {
        if (protocols.isEmpty) protocols.add('Unknown');
        
        // Verificar se é realmente uma câmera antes de adicionar
        final isCamera = await _deviceIdentificationService.isCameraDevice(
          ip,
          port: port,
        );
        
        if (!isCamera) {
          LoggingService.instance.cameraDiscovery('DISPOSITIVO PORT SCAN FILTRADO (não é câmera): $ip:$port');
          return;
        }
        
        LoggingService.instance.cameraDiscovery('CÂMERA PORT SCAN IDENTIFICADA: $ip:$port');
        
        final camera = DiscoveredCamera(
          ip: ip,
          name: '$cameraName ($ip:$port)',
          protocols: protocols,
          metadata: {
            'port': port, 
            'discovered_via': 'port_scan',
            'scan_timestamp': DateTime.now().toIso8601String()
          },
        );
        
        if (!_isDuplicate(camera)) {
          _discoveredCameras.add(camera);
          LoggingService.instance.cameraDiscovery('CÂMERA ENCONTRADA: $ip:$port - Protocolos: ${protocols.join(", ")}');
        }
      }
    } catch (e) {
      // Porta fechada ou não acessível - isso é normal
    }
  }

  /// Verifica se um dispositivo é ONVIF com verificação real e validação aprimorada
  static Future<bool> _isOnvifDevice(String ip, int port) async {
    try {
      // Primeiro faz uma verificação HTTP básica para detectar não-câmeras
      final basicResponse = await http.get(
        Uri.parse('http://$ip:$port/'),
        headers: {'User-Agent': 'Camera Discovery Service'},
      ).timeout(const Duration(seconds: 3));
      
      if (basicResponse.statusCode == 200) {
        final content = basicResponse.body.toLowerCase();
        
        // Verifica se é realmente uma câmera através da análise HTTP
        final httpAnalysis = await _deviceIdentificationService.analyzeHttpService(ip, port);
        if (httpAnalysis != null && httpAnalysis['fingerprint'] != null && httpAnalysis['fingerprint']['likely_router'] == true) {
          return false;
        }
      }
      
      // Tenta fazer uma requisição ONVIF GetDeviceInformation
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      
      final request = await client.postUrl(Uri.parse('http://$ip:$port/onvif/device_service'));
      request.headers.set('Content-Type', 'application/soap+xml');
      request.headers.set('SOAPAction', 'http://www.onvif.org/ver10/device/wsdl/GetDeviceInformation');
      
      const soapEnvelope = '''
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl">
  <soap:Header/>
  <soap:Body>
    <tds:GetDeviceInformation/>
  </soap:Body>
</soap:Envelope>''';
      
      request.write(soapEnvelope);
      final response = await request.close().timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        client.close();
        return responseBody.contains('GetDeviceInformationResponse') || 
               responseBody.contains('onvif') ||
               responseBody.contains('Device');
      }
      
      client.close();
      return false;
    } catch (e) {
      // Tenta verificação alternativa por caminhos ONVIF comuns
      return await _checkOnvifPaths(ip, port);
    }
  }
  
  /// Verifica caminhos ONVIF comuns com validação aprimorada
  static Future<bool> _checkOnvifPaths(String ip, int port) async {
    final onvifPaths = ['/onvif/device_service', '/onvif/Device', '/Device', '/onvif'];
    
    for (final path in onvifPaths) {
      try {
        final response = await http.get(
          Uri.parse('http://$ip:$port$path'),
          headers: {'User-Agent': 'ONVIF Client'},
        ).timeout(const Duration(seconds: 2));
        
        if (response.statusCode == 200) {
          final content = response.body.toLowerCase();
          
          // Verifica se não é uma câmera baseado na resposta
          final httpAnalysis = await _deviceIdentificationService.analyzeHttpService(ip, port);
          if (httpAnalysis != null && httpAnalysis['fingerprint'] != null && httpAnalysis['fingerprint']['likely_router'] == true) {
            return false;
          }
          
          // Verifica se contém indicadores ONVIF
          if (content.contains('onvif') || content.contains('device')) {
            return true;
          }
        } else if (response.statusCode == 405) {
          return true;
        }
      } catch (e) {
        continue;
      }
    }
    
    return false;
  }
  
  /// Verifica se é um dispositivo RTSP com validação aprimorada
  static Future<bool> _isRtspDevice(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      
      // Envia comando RTSP OPTIONS
      socket.write('OPTIONS rtsp://$ip:$port RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: Camera Discovery\r\n\r\n');
      
      final response = await utf8.decoder.bind(socket).take(1).join().timeout(const Duration(seconds: 2));
      await socket.close();
      
      // Verifica se é uma resposta RTSP válida
      if (response.contains('RTSP/1.0') && 
          (response.contains('200 OK') || response.contains('401 Unauthorized'))) {
        
        // Verifica se contém métodos típicos de câmera
        final cameraRtspMethods = ['DESCRIBE', 'SETUP', 'PLAY', 'TEARDOWN'];
        int methodCount = 0;
        for (final method in cameraRtspMethods) {
          if (response.toUpperCase().contains(method)) {
            methodCount++;
          }
        }
        
        // Se tem pelo menos 2 métodos de câmera, considera válido
        return methodCount >= 2;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }
  
  /// Verifica se tem interface web com validação rigorosa
  static Future<bool> _isWebInterface(String ip, int port) async {
    try {
      final urls = [
        'http://$ip:$port/',
        'http://$ip:$port/index.html',
        'http://$ip:$port/login.html',
        'http://$ip:$port/web/',
      ];
      
      for (final url in urls) {
        try {
          final response = await http.get(
            Uri.parse(url),
            headers: {'User-Agent': 'Camera Discovery'},
          ).timeout(const Duration(seconds: 5));
          
          if (response.statusCode == 200) {
            final content = response.body.toLowerCase();
            
            // Primeiro verifica se NÃO é uma câmera
            final httpAnalysis = await _deviceIdentificationService.analyzeHttpService(ip, port);
            if (httpAnalysis != null && httpAnalysis['fingerprint'] != null && httpAnalysis['fingerprint']['likely_router'] == true) {
              return false;
            }
            
            // Verifica indicadores positivos de interface de câmera
            final cameraIndicators = [
              'camera', 'video', 'stream', 'live view', 'surveillance',
              'security', 'nvr', 'dvr', 'onvif', 'rtsp',
              'hikvision', 'dahua', 'axis', 'bosch', 'foscam',
              'motion detection', 'playback', 'recording',
              'channel', 'preset', 'ptz', 'zoom'
            ];
            
            int positiveMatches = 0;
            for (final indicator in cameraIndicators) {
              if (content.contains(indicator)) {
                positiveMatches++;
              }
            }
            
            // Precisa de pelo menos 2 indicadores positivos
            if (positiveMatches >= 2) {
              return true;
            }
          }
        } catch (e) {
          continue;
        }
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }
  
  /// Verifica se é uma porta comum de câmeras
  static bool _isCommonCameraPort(int port) {
    return CameraPorts.getIntelligentDiscoveryPorts().contains(port);
  }

  /// Obtém a subnet local
  static Future<String?> _getLocalSubnet() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              return '${parts[0]}.${parts[1]}.${parts[2]}';
            }
          }
        }
      }
    } catch (e) {
      LoggingService.instance.cameraDiscovery('Erro ao obter subnet: $e');
    }
    return null;
  }

  /// Verifica se a câmera já foi descoberta
  static bool _isDuplicate(DiscoveredCamera camera) {
    return _discoveredCameras.any((existing) => existing.ip == camera.ip);
  }

  /// Emite progresso da descoberta
  static void _emitProgress(String phase, int current, int total, bool isComplete) {
    final progress = CameraDiscoveryProgress(
      phase: phase,
      current: current,
      total: total,
      isComplete: isComplete,
      discoveredCameras: List.from(_discoveredCameras),
    );
    
    _progressController.add(progress);
  }

  /// Obtém câmeras do cache
  static Future<List<Map<String, dynamic>>> getCachedDevices() async {
    return _discoveredCameras.map((camera) => {
      'ip': camera.ip,
      'name': camera.name,
      'protocol': camera.protocols.isNotEmpty ? camera.protocols.first : null,
      'protocols': camera.protocols,
      'metadata': camera.metadata,
      'manufacturer': null,
      'ports': camera.metadata['port'] != null ? [camera.metadata['port']] : [],
      'isOnline': true,
    }).toList();
  }

  /// Conecta a um dispositivo
  static Future<void> connectToDevice(String ip, String username, String password) async {
    LoggingService.instance.cameraDiscovery('Conectando a $ip com credenciais fornecidas');
    // Implementação da conexão seria aqui
  }

  /// Detecta protocolo de um dispositivo
  static Future<Map<String, dynamic>> detectProtocol(
    String host, {
    String? username,
    String? password,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      // Tenta ONVIF primeiro
      final isOnvif = await _isOnvifDevice(host, 80);
      if (isOnvif) {
        return {
          'isSuccessful': true,
          'protocol': 'ONVIF',
          'port': 80,
        };
      }
      
      // Tenta RTSP
      final isRtsp = await _checkRtspPort(host, 554);
      if (isRtsp) {
        return {
          'isSuccessful': true,
          'protocol': 'RTSP',
          'port': 554,
        };
      }
      
      return {'isSuccessful': false};
    } catch (e) {
      return {'isSuccessful': false, 'error': e.toString()};
    }
  }

  /// Verifica porta RTSP
  static Future<bool> _checkRtspPort(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 1));
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Cria configuração otimizada
  static Future<Map<String, dynamic>> createOptimizedConfiguration(
    String host, {
    String? username,
    String? password,
  }) async {
    final detection = await detectProtocol(host, username: username, password: password);
    
    if (detection['isSuccessful'] == true) {
      return {
        'protocol': detection['protocol'],
        'port': detection['port'],
        'optimized': true,
      };
    }
    
    return {
      'protocol': 'ONVIF',
      'port': 80,
      'optimized': false,
    };
  }
}

/// Alias para compatibilidade
typedef DiscoveryProgress = CameraDiscoveryProgress;