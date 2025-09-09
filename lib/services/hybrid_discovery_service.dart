import 'dart:async';
import 'dart:io';
import '../constants/camera_ports.dart';
import '../models/camera_device.dart';
import 'improved_mdns_service.dart';
import 'intelligent_port_scanner.dart';
import 'device_validator.dart';

/// Serviço híbrido de descoberta com cache inteligente
/// Integra mDNS, port scanning e validação multi-camadas
/// Meta: descoberta completa em menos de 5 segundos
class HybridDiscoveryService {
  final ImprovedMDNSService _mdnsService = ImprovedMDNSService();
  final IntelligentPortScanner _portScanner = IntelligentPortScanner();
  final DeviceValidator _validator = DeviceValidator();
  
  // Cache inteligente
  final Map<String, CachedDevice> _deviceCache = {};
  final Map<String, DateTime> _networkScanHistory = {};
  
  static const Duration _cacheExpiry = Duration(minutes: 10);
  static const Duration _networkScanCooldown = Duration(minutes: 2);
  static const Duration _maxDiscoveryTime = Duration(seconds: 5);
  
  bool _isDiscovering = false;
  
  /// Executa descoberta híbrida completa
  Future<List<CameraDevice>> discoverDevices({String? networkBase}) async {
    if (_isDiscovering) {
      print('[HybridDiscovery] Descoberta já em andamento');
      return [];
    }
    
    _isDiscovering = true;
    final stopwatch = Stopwatch()..start();
    
    try {
      print('[HybridDiscovery] Iniciando descoberta híbrida...');
      
      final devices = <CameraDevice>[];
      final networkAddr = networkBase ?? await _detectNetworkBase();
      
      // Verificar cache primeiro
      final cachedDevices = _getCachedDevices(networkAddr);
      if (cachedDevices.isNotEmpty) {
        print('[HybridDiscovery] Encontrados ${cachedDevices.length} dispositivos em cache');
        devices.addAll(cachedDevices);
      }
      
      // Estratégia de descoberta em paralelo com timeout
      final discoveryFuture = _executeHybridDiscovery(networkAddr);
      final timeoutFuture = Future.delayed(_maxDiscoveryTime);
      
      final result = await Future.any([
        discoveryFuture,
        timeoutFuture.then((_) => <CameraDevice>[])
      ]);
      
      devices.addAll(result);
      
      // Remover duplicatas e atualizar cache
      final uniqueDevices = _removeDuplicates(devices);
      _updateCache(networkAddr, uniqueDevices);
      
      stopwatch.stop();
      print('[HybridDiscovery] Descoberta concluída em ${stopwatch.elapsedMilliseconds}ms');
      print('[HybridDiscovery] Encontrados ${uniqueDevices.length} dispositivos únicos');
      
      return uniqueDevices;
      
    } catch (e) {
      print('[HybridDiscovery] Erro na descoberta: $e');
      return [];
    } finally {
      _isDiscovering = false;
    }
  }
  
  /// Executa descoberta híbrida em paralelo
  Future<List<CameraDevice>> _executeHybridDiscovery(String networkBase) async {
    final devices = <CameraDevice>[];
    final futures = <Future>[];
    
    // Fase 1: mDNS rápido (paralelo)
    futures.add(_attemptMDNSDiscovery().then((mdnsDevices) {
      devices.addAll(mdnsDevices);
      print('[HybridDiscovery] mDNS encontrou ${mdnsDevices.length} dispositivos');
    }));
    
    // Fase 2: Port scan inteligente (paralelo)
    futures.add(_attemptPortScanDiscovery(networkBase).then((scanDevices) {
      devices.addAll(scanDevices);
      print('[HybridDiscovery] PortScan encontrou ${scanDevices.length} dispositivos');
    }));
    
    // Aguardar todas as descobertas ou timeout
    await Future.wait(futures, eagerError: false);
    
    return devices;
  }
  
  /// Tenta descoberta via mDNS com fallback rápido
  Future<List<CameraDevice>> _attemptMDNSDiscovery() async {
    try {
      final devices = await _mdnsService.discoverDevices();
      
      if (_mdnsService.hasReusePortError) {
        print('[HybridDiscovery] mDNS com erro reusePort - priorizando port scan');
        return [];
      }
      
      return devices;
    } catch (e) {
      print('[HybridDiscovery] Falha no mDNS: $e');
      return [];
    }
  }
  
  /// Tenta descoberta via port scan inteligente
  Future<List<CameraDevice>> _attemptPortScanDiscovery(String networkBase) async {
    try {
      // Verificar se já fizemos scan recente desta rede
      final lastScan = _networkScanHistory[networkBase];
      if (lastScan != null && 
          DateTime.now().difference(lastScan) < _networkScanCooldown) {
        print('[HybridDiscovery] Scan recente da rede $networkBase - usando cache');
        return [];
      }
      
      final devices = await _portScanner.scanNetwork(networkBase);
      _networkScanHistory[networkBase] = DateTime.now();
      
      return devices;
    } catch (e) {
      print('[HybridDiscovery] Falha no port scan: $e');
      return [];
    }
  }
  
  /// Valida dispositivos descobertos
  Future<List<CameraDevice>> validateDiscoveredDevices(List<CameraDevice> devices) async {
    print('[HybridDiscovery] Validando ${devices.length} dispositivos...');
    
    final validatedDevices = <CameraDevice>[];
    final validationFutures = devices.map((device) async {
      try {
        final result = await _validator.validateDevice(device);
        if (result.finalResult) {
          validatedDevices.add(device);
          print('[HybridDiscovery] Dispositivo validado: ${device.ip}:${device.port}');
        } else {
          print('[HybridDiscovery] Dispositivo inválido: ${device.ip}:${device.port} - ${result.reason}');
        }
      } catch (e) {
        print('[HybridDiscovery] Erro na validação de ${device.ip}:${device.port}: $e');
      }
    });
    
    await Future.wait(validationFutures, eagerError: false);
    
    print('[HybridDiscovery] ${validatedDevices.length}/${devices.length} dispositivos validados');
    return validatedDevices;
  }
  
  /// Descoberta rápida focada em RTSP
  Future<List<CameraDevice>> quickRTSPDiscovery(String networkBase) async {
    print('[HybridDiscovery] Descoberta rápida RTSP para $networkBase');
    
    try {
      final devices = await _portScanner.scanForStreaming(networkBase);
      return await validateDiscoveredDevices(devices);
    } catch (e) {
      print('[HybridDiscovery] Erro na descoberta RTSP: $e');
      return [];
    }
  }
  
  /// Descoberta específica para um IP
  Future<List<CameraDevice>> discoverSpecificIP(String ip, {String? manufacturer}) async {
    print('[HybridDiscovery] Descoberta específica para IP: $ip');
    
    try {
      final devices = await _portScanner.scanSpecificIP(ip, manufacturer: manufacturer);
      return await validateDiscoveredDevices(devices);
    } catch (e) {
      print('[HybridDiscovery] Erro na descoberta específica: $e');
      return [];
    }
  }
  
  /// Detecta base da rede automaticamente
  Future<String> _detectNetworkBase() async {
    try {
      final interfaces = await NetworkInterface.list();
      
      for (final interface in interfaces) {
        if (interface.name.toLowerCase().contains('wi-fi') ||
            interface.name.toLowerCase().contains('ethernet')) {
          for (final addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final networkBase = '${parts[0]}.${parts[1]}.${parts[2]}';
                print('[HybridDiscovery] Rede detectada: $networkBase');
                return networkBase;
              }
            }
          }
        }
      }
    } catch (e) {
      print('[HybridDiscovery] Erro ao detectar rede: $e');
    }
    
    // Fallback para rede padrão
    return '192.168.1';
  }
  
  /// Obtém dispositivos do cache
  List<CameraDevice> _getCachedDevices(String networkBase) {
    final cachedDevices = <CameraDevice>[];
    final now = DateTime.now();
    
    _deviceCache.removeWhere((key, cached) {
      return now.difference(cached.timestamp) > _cacheExpiry;
    });
    
    for (final cached in _deviceCache.values) {
      if (cached.device.ip.startsWith(networkBase)) {
        cachedDevices.add(cached.device);
      }
    }
    
    return cachedDevices;
  }
  
  /// Atualiza cache com novos dispositivos
  void _updateCache(String networkBase, List<CameraDevice> devices) {
    final now = DateTime.now();
    
    for (final device in devices) {
      final key = '${device.ip}:${device.port}';
      _deviceCache[key] = CachedDevice(
        device: device,
        timestamp: now,
        networkBase: networkBase,
      );
    }
    
    print('[HybridDiscovery] Cache atualizado com ${devices.length} dispositivos');
  }
  
  /// Remove dispositivos duplicados
  List<CameraDevice> _removeDuplicates(List<CameraDevice> devices) {
    final seen = <String>{};
    final unique = <CameraDevice>[];
    
    for (final device in devices) {
      final key = '${device.ip}:${device.port}';
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(device);
      }
    }
    
    return unique;
  }
  
  /// Limpa cache manualmente
  void clearCache() {
    _deviceCache.clear();
    _networkScanHistory.clear();
    print('[HybridDiscovery] Cache limpo');
  }
  
  /// Obtém estatísticas do cache
  Map<String, dynamic> getCacheStats() {
    final now = DateTime.now();
    final validEntries = _deviceCache.values
        .where((cached) => now.difference(cached.timestamp) <= _cacheExpiry)
        .length;
    
    return {
      'total_entries': _deviceCache.length,
      'valid_entries': validEntries,
      'networks_scanned': _networkScanHistory.length,
      'cache_expiry_minutes': _cacheExpiry.inMinutes,
    };
  }
  
  /// Para todos os serviços
  Future<void> stop() async {
    await _mdnsService.stop();
    _isDiscovering = false;
    print('[HybridDiscovery] Serviços parados');
  }
}

/// Dispositivo em cache
class CachedDevice {
  final CameraDevice device;
  final DateTime timestamp;
  final String networkBase;
  
  CachedDevice({
    required this.device,
    required this.timestamp,
    required this.networkBase,
  });
}