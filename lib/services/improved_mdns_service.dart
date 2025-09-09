import 'dart:async';
import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';
import '../constants/camera_ports.dart';
import '../models/camera_device.dart';

/// Serviço mDNS melhorado com detecção rápida de falha e fallback automático
/// Resolve o problema do erro reusePort identificado nos logs
class ImprovedMDNSService {
  static const Duration _fastFailureTimeout = Duration(seconds: 3);
  static const Duration _maxDiscoveryTime = Duration(seconds: 8);
  static const String _onvifServiceType = '_onvif._tcp';
  static const String _httpServiceType = '_http._tcp';
  
  MDnsClient? _client;
  bool _isRunning = false;
  bool _hasReusePortError = false;
  
  /// Inicia descoberta mDNS com detecção rápida de falha
  Future<List<CameraDevice>> discoverDevices() async {
    print('[ImprovedMDNS] Iniciando descoberta mDNS...');
    
    try {
      return await _attemptMDNSDiscovery();
    } catch (e) {
      print('[ImprovedMDNS] Erro na descoberta mDNS: $e');
      
      // Detectar erro reusePort específico
      if (e.toString().contains('reusePort') || 
          e.toString().contains('address already in use')) {
        _hasReusePortError = true;
        print('[ImprovedMDNS] Erro reusePort detectado - ativando fallback');
      }
      
      return [];
    }
  }
  
  /// Tenta descoberta mDNS com timeout rápido
  Future<List<CameraDevice>> _attemptMDNSDiscovery() async {
    final devices = <CameraDevice>[];
    
    try {
      // Configurar cliente mDNS com opções específicas para evitar reusePort
      _client = MDnsClient(
        reuseAddress: false,
        reusePort: false,
        interfaceIndex: null, // Usar interface padrão
      );
      
      await _client!.start();
      _isRunning = true;
      
      print('[ImprovedMDNS] Cliente mDNS iniciado com sucesso (reusePort=false)');
      
      // Descoberta com timeout rápido para detectar falhas
      final discoveryFuture = _performDiscovery();
      final timeoutFuture = Future.delayed(_fastFailureTimeout);
      
      final result = await Future.any([
        discoveryFuture,
        timeoutFuture.then((_) => <CameraDevice>[])
      ]);
      
      if (result.isEmpty && _isRunning) {
        print('[ImprovedMDNS] Timeout rápido atingido - possível falha mDNS');
      }
      
      return result;
      
    } catch (e) {
      print('[ImprovedMDNS] Erro durante descoberta: $e');
      
      // Se erro relacionado a socket, tentar abordagem alternativa
      if (e.toString().contains('reusePort') || 
          e.toString().contains('address already in use') ||
          e.toString().contains('bind')) {
        print('[ImprovedMDNS] Tentando abordagem alternativa sem reusePort...');
        return await _attemptAlternativeMDNS();
      }
      
      rethrow;
    } finally {
      await _cleanup();
    }
  }
  
  /// Executa a descoberta mDNS propriamente dita
  Future<List<CameraDevice>> _performDiscovery() async {
    final devices = <CameraDevice>[];
    final completer = Completer<List<CameraDevice>>();
    
    // Buscar serviços ONVIF
    _client!.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(_onvifServiceType)
    ).listen(
      (PtrResourceRecord ptr) {
        _handleServiceDiscovery(ptr, devices);
      },
      onError: (error) {
        print('[ImprovedMDNS] Erro na busca ONVIF: $error');
      }
    );
    
    // Buscar serviços HTTP genéricos
    _client!.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(_httpServiceType)
    ).listen(
      (PtrResourceRecord ptr) {
        _handleServiceDiscovery(ptr, devices);
      },
      onError: (error) {
        print('[ImprovedMDNS] Erro na busca HTTP: $error');
      }
    );
    
    // Timeout para completar descoberta
    Timer(_maxDiscoveryTime, () {
      if (!completer.isCompleted) {
        print('[ImprovedMDNS] Descoberta concluída por timeout: ${devices.length} dispositivos');
        completer.complete(devices);
      }
    });
    
    return completer.future;
  }
  
  /// Processa descoberta de serviços
  void _handleServiceDiscovery(PtrResourceRecord ptr, List<CameraDevice> devices) {
    final serviceName = ptr.domainName;
    print('[ImprovedMDNS] Serviço descoberto: $serviceName');
    
    // Buscar detalhes do serviço
    _client!.lookup<SrvResourceRecord>(
      ResourceRecordQuery.service(serviceName)
    ).listen((SrvResourceRecord srv) {
      _handleServiceDetails(srv, devices);
    });
  }
  
  /// Processa detalhes do serviço descoberto
  void _handleServiceDetails(SrvResourceRecord srv, List<CameraDevice> devices) {
    final host = srv.target;
    final port = srv.port;
    
    print('[ImprovedMDNS] Detalhes do serviço - Host: $host, Porta: $port');
    
    // Resolver endereço IP
    _client!.lookup<IPAddressResourceRecord>(
      ResourceRecordQuery.addressIPv4(host)
    ).listen((IPAddressResourceRecord ip) {
      final device = CameraDevice(
        ip: ip.address.address,
        port: port,
        protocol: _determineProtocol(port),
        manufacturer: 'Desconhecido',
        model: 'mDNS Discovery',
        discoveryMethod: 'mDNS'
      );
      
      // Evitar duplicatas
      if (!devices.any((d) => d.ip == device.ip && d.port == device.port)) {
        devices.add(device);
        print('[ImprovedMDNS] Dispositivo adicionado: ${device.ip}:${device.port}');
      }
    });
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
    return 'Desconhecido';
  }
  
  /// Limpa recursos do cliente mDNS
  Future<void> _cleanup() async {
    if (_client != null && _isRunning) {
      try {
        _client!.stop();
        _isRunning = false;
        print('[ImprovedMDNS] Cliente mDNS parado');
      } catch (e) {
        print('[ImprovedMDNS] Erro ao parar cliente: $e');
      }
    }
  }
  
  /// Verifica se houve erro reusePort
  bool get hasReusePortError => _hasReusePortError;
  
  /// Verifica se mDNS está funcionando
  bool get isWorking => _isRunning && !_hasReusePortError;
  
  /// Abordagem alternativa para mDNS quando reusePort falha
  Future<List<CameraDevice>> _attemptAlternativeMDNS() async {
    final devices = <CameraDevice>[];
    
    try {
      // Aguardar um pouco antes de tentar novamente
      await Future.delayed(Duration(milliseconds: 500));
      
      // Tentar com configuração mais simples
      _client = MDnsClient(
        reuseAddress: true,
        reusePort: false, // Explicitamente desabilitar reusePort
      );
      
      await _client!.start();
      _isRunning = true;
      
      print('[ImprovedMDNS] Cliente mDNS alternativo iniciado');
      
      // Descoberta mais simples e rápida
      final discoveryFuture = _performSimpleDiscovery();
      final timeoutFuture = Future.delayed(Duration(seconds: 5));
      
      final result = await Future.any([
        discoveryFuture,
        timeoutFuture.then((_) => <CameraDevice>[])
      ]);
      
      return result;
      
    } catch (e) {
      print('[ImprovedMDNS] Falha na abordagem alternativa: $e');
      _hasReusePortError = true;
      return [];
    }
  }
  
  /// Descoberta mDNS simplificada
  Future<List<CameraDevice>> _performSimpleDiscovery() async {
    final devices = <CameraDevice>[];
    final completer = Completer<List<CameraDevice>>();
    
    try {
      // Buscar apenas serviços ONVIF (mais específicos para câmeras)
      _client!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_onvifServiceType)
      ).listen(
        (PtrResourceRecord ptr) {
          _handleServiceDiscovery(ptr, devices);
        },
        onError: (error) {
          print('[ImprovedMDNS] Erro na busca ONVIF simplificada: $error');
        }
      );
      
      // Timeout mais curto para descoberta simplificada
      Timer(Duration(seconds: 4), () {
        if (!completer.isCompleted) {
          print('[ImprovedMDNS] Descoberta simplificada concluída: ${devices.length} dispositivos');
          completer.complete(devices);
        }
      });
      
      return completer.future;
      
    } catch (e) {
      print('[ImprovedMDNS] Erro na descoberta simplificada: $e');
      if (!completer.isCompleted) {
        completer.complete([]);
      }
      return completer.future;
    }
  }

  /// Para o serviço
  Future<void> stop() async {
    await _cleanup();
  }
}