import 'dart:async';
import 'dart:io';
import '../models/camera_device.dart';
import '../constants/camera_ports.dart';

/// Scanner inteligente de portas com foco em descoberta rápida de RTSP
/// Meta: encontrar porta 554 em menos de 5 segundos
class IntelligentPortScanner {
  static const Duration _fastScanTimeout = Duration(seconds: 2);
  static const Duration _commonScanTimeout = Duration(seconds: 3);
  static const Duration _fullScanTimeout = Duration(seconds: 5);
  
  // Controle de concorrência para evitar sobrecarga
  static const int _maxConcurrentConnections = 50;
  
  // Getters públicos para os timeouts (necessários para testes)
  Duration get fastTimeout => _fastScanTimeout;
  Duration get normalTimeout => _commonScanTimeout;
  Duration get fullTimeout => _fullScanTimeout;
  
  /// Executa scan inteligente em três fases
  Future<List<CameraDevice>> scanNetwork(String networkBase) async {
    print('[PortScanner] Iniciando scan inteligente da rede $networkBase');
    
    final devices = <CameraDevice>[];
    final ips = _generateIPRange(networkBase);
    
    // Fase 1: Scan rápido de portas RTSP prioritárias
    print('[PortScanner] Fase 1: Scan rápido RTSP (${CameraPorts.rtspPriorityPorts})');
    final phase1Devices = await _scanPhase1(ips);
    devices.addAll(phase1Devices);
    
    if (phase1Devices.isNotEmpty) {
      print('[PortScanner] Fase 1 encontrou ${phase1Devices.length} dispositivos - priorizando');
      return devices; // Retorna imediatamente se encontrou dispositivos RTSP
    }
    
    // Fase 2: Scan de portas comuns
    print('[PortScanner] Fase 2: Scan portas comuns (${CameraPorts.mostCommonPorts})');
    final phase2Devices = await _scanPhase2(ips);
    devices.addAll(phase2Devices);
    
    if (phase2Devices.isNotEmpty) {
      print('[PortScanner] Fase 2 encontrou ${phase2Devices.length} dispositivos');
      return devices;
    }
    
    // Fase 3: Scan completo (apenas se necessário)
    print('[PortScanner] Fase 3: Scan completo');
    final phase3Devices = await _scanPhase3(ips);
    devices.addAll(phase3Devices);
    
    return devices;
  }
  
  /// Fase 1: Scan ultra-rápido de portas RTSP prioritárias
  Future<List<CameraDevice>> _scanPhase1(List<String> ips) async {
    final devices = <CameraDevice>[];
    final futures = <Future>[];
    
    for (final ip in ips) {
      for (final port in CameraPorts.rtspPriorityPorts) {
        futures.add(_scanSinglePort(ip, port, _fastScanTimeout).then((device) {
          if (device != null) {
            devices.add(device);
            print('[PortScanner] RTSP encontrado: ${device.ip}:${device.port}');
          }
        }));
        
        // Controle de concorrência - processa em lotes
        if (futures.length >= _maxConcurrentConnections) {
          await Future.wait(futures);
          futures.clear();
        }
      }
    }
    
    // Processa futures restantes
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    
    return devices;
  }
  
  /// Fase 2: Scan de portas comuns de câmeras
  Future<List<CameraDevice>> _scanPhase2(List<String> ips) async {
    final devices = <CameraDevice>[];
    final futures = <Future>[];
    
    for (final ip in ips) {
      for (final port in CameraPorts.mostCommonPorts) {
        futures.add(_scanSinglePort(ip, port, _commonScanTimeout).then((device) {
          if (device != null) {
            devices.add(device);
            print('[PortScanner] Câmera comum encontrada: ${device.ip}:${device.port}');
          }
        }));
        
        // Controle de concorrência - processa em lotes
        if (futures.length >= _maxConcurrentConnections) {
          await Future.wait(futures);
          futures.clear();
        }
      }
    }
    
    // Processa futures restantes
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    
    return devices;
  }
  
  /// Fase 3: Scan completo de todas as portas
  Future<List<CameraDevice>> _scanPhase3(List<String> ips) async {
    final devices = <CameraDevice>[];
    final futures = <Future>[];
    final allPorts = CameraPorts.getAllPorts();
    
    for (final ip in ips) {
      for (final port in allPorts) {
        if (!CameraPorts.rtspPriorityPorts.contains(port) && 
            !CameraPorts.mostCommonPorts.contains(port)) {
          futures.add(_scanSinglePort(ip, port, _fullScanTimeout).then((device) {
            if (device != null) {
              devices.add(device);
              print('[PortScanner] Dispositivo encontrado: ${device.ip}:${device.port}');
            }
          }));
          
          // Controle de concorrência - processa em lotes
          if (futures.length >= _maxConcurrentConnections) {
            await Future.wait(futures);
            futures.clear();
          }
        }
      }
    }
    
    // Processa futures restantes
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    
    return devices;
  }
  
  /// Scan de uma única porta com timeout otimizado
  Future<CameraDevice?> _scanSinglePort(String ip, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      await socket.close();
      
      final protocol = _determineProtocol(port);
      final device = CameraDevice(
        ip: ip,
        port: port,
        protocol: protocol,
        manufacturer: 'Desconhecido',
        model: 'Port Scan',
        discoveryMethod: 'PortScan'
      );
      
      return device;
    } on SocketException catch (e) {
      // Erro de conexão esperado - porta fechada ou host inacessível
      return null;
    } on TimeoutException catch (e) {
      // Timeout esperado - host não responde
      return null;
    } catch (e) {
      // Outros erros inesperados
      print('[PortScanner] Erro inesperado ao escanear $ip:$port - $e');
      return null;
    }
  }
  
  /// Scan específico para um IP com portas priorizadas
  Future<List<CameraDevice>> scanSpecificIP(String ip, {String? manufacturer}) async {
    print('[PortScanner] Scan específico para IP: $ip');
    
    final devices = <CameraDevice>[];
    List<int> portsToScan;
    
    if (manufacturer != null) {
      portsToScan = CameraPorts.getPortsForManufacturer(manufacturer);
      print('[PortScanner] Usando portas específicas para $manufacturer: $portsToScan');
    } else {
      portsToScan = CameraPorts.getFastDiscoveryPorts();
    }
    
    final futures = portsToScan.map((port) => 
      _scanSinglePort(ip, port, _fastScanTimeout).then((device) {
        if (device != null) {
          devices.add(device);
        }
      })
    );
    
    await Future.wait(futures);
    return devices;
  }
  
  /// Verifica se uma porta específica está aberta
  Future<bool> isPortOpen(String ip, int port, {Duration? timeout}) async {
    try {
      final socket = await Socket.connect(
        ip, 
        port, 
        timeout: timeout ?? _fastScanTimeout
      );
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Gera range de IPs para scan com suporte a diferentes máscaras
  List<String> _generateIPRange(String networkBase) {
    final ips = <String>[];
    final parts = networkBase.split('.');
    
    if (parts.length == 3) {
      // Scan da rede /24 (padrão)
      for (int i = 1; i <= 254; i++) {
        ips.add('${parts[0]}.${parts[1]}.${parts[2]}.$i');
      }
    } else if (parts.length == 4) {
      // IP específico fornecido
      ips.add(networkBase);
    } else if (parts.length == 2) {
      // Scan de rede /16 (limitado para performance)
      for (int i = 1; i <= 10; i++) { // Limita a 10 subredes para evitar timeout
        for (int j = 1; j <= 254; j++) {
          ips.add('${parts[0]}.${parts[1]}.$i.$j');
        }
      }
    }
    
    return ips;
  }
  
  /// Determina protocolo baseado na porta
  String _determineProtocol(int port) {
    if (CameraPorts.isStreamingPort(port)) {
      return 'RTSP';
    } else if (CameraPorts.isWebInterfacePort(port)) {
      return 'HTTP';
    } else if (CameraPorts.isOnvifPort(port)) {
      return 'ONVIF';
    }
    return 'TCP';
  }
  
  /// Scan otimizado para descoberta de streaming
  Future<List<CameraDevice>> scanForStreaming(String networkBase) async {
    print('[PortScanner] Scan otimizado para streaming RTSP');
    
    final devices = <CameraDevice>[];
    final ips = _generateIPRange(networkBase);
    final futures = <Future>[];
    
    // Priorizar apenas portas de streaming
    for (final ip in ips) {
      for (final port in CameraPorts.rtspPriorityPorts) {
        futures.add(_scanSinglePort(ip, port, _fastScanTimeout).then((device) {
          if (device != null && device.protocol == 'RTSP') {
            devices.add(device);
            print('[PortScanner] Stream RTSP encontrado: ${device.ip}:${device.port}');
          }
        }));
      }
    }
    
    await Future.wait(futures);
    return devices;
  }
}