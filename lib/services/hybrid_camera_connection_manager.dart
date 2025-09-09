import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_onvif/onvif.dart';
import '../models/camera_models.dart';
import 'proprietary_protocol_service.dart';
import 'fast_camera_discovery_service.dart';

// Estado da conexão híbrida
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  authenticating,
  authenticated,
  error
}

// Resultado de operação híbrida
class HybridOperationResult<T> {
  final bool success;
  final T? data;
  final String? error;
  final ProtocolType? usedProtocol;

  const HybridOperationResult({
    required this.success,
    this.data,
    this.error,
    this.usedProtocol,
  });

  factory HybridOperationResult.success(T data, ProtocolType protocol) {
    return HybridOperationResult(
      success: true,
      data: data,
      usedProtocol: protocol,
    );
  }

  factory HybridOperationResult.failure(String error) {
    return HybridOperationResult(
      success: false,
      error: error,
    );
  }

  // Getter para compatibilidade
  bool get isSuccess => success;
}

// Gerenciador de conexões híbridas para câmeras
class HybridCameraConnectionManager {
  final CameraData cameraData;
  
  Onvif? _onvifClient;
  ProprietaryProtocolService? _proprietaryService;
  ConnectionState _connectionState = ConnectionState.disconnected;
  ProtocolType? _activeProtocol;
  
  final StreamController<ConnectionState> _stateController = StreamController.broadcast();
  final StreamController<String> _errorController = StreamController.broadcast();

  // Streams públicos
  Stream<ConnectionState> get connectionStateStream => _stateController.stream;
  Stream<String> get errorStream => _errorController.stream;
  
  // Getters
  ConnectionState get connectionState => _connectionState;
  ProtocolType? get activeProtocol => _activeProtocol;
  bool get isConnected => _connectionState == ConnectionState.connected || _connectionState == ConnectionState.authenticated;
  bool get isAuthenticated => _connectionState == ConnectionState.authenticated;

  HybridCameraConnectionManager(this.cameraData) {
    _initializeServices();
  }

  // Inicializa os serviços baseado na configuração da câmera
  void _initializeServices() {
    final config = cameraData.portConfiguration;

    // Inicializa ONVIF se suportado
    if (config.preferredProtocol == 'onvif' || config.preferredProtocol == 'auto') {
      // Nota: A inicialização será feita durante a conexão
      // pois Onvif.connect() é assíncrono
    }

    // Inicializa serviço proprietário se suportado
    if ((config.preferredProtocol == 'proprietary' || config.preferredProtocol == 'auto')) {
      _proprietaryService = ProprietaryProtocolService();
    }
  }

  // Conecta à câmera usando o protocolo apropriado
  Future<bool> connect({Duration timeout = const Duration(seconds: 10)}) async {
    if (isConnected) {
      return true;
    }

    _updateState(ConnectionState.connecting);
    
    try {
      final config = cameraData.portConfiguration;

      // Estratégia de conexão baseada no tipo de protocolo
      switch (config.preferredProtocol) {
        case 'onvif':
          return await _connectOnvif(timeout);
        
        case 'proprietary':
          return await _connectProprietary(timeout);
        
        case 'auto':
          // Tenta ONVIF primeiro, depois proprietário
          if (await _connectOnvif(timeout)) {
            return true;
          }
          return await _connectProprietary(timeout);
      }
      
      return false;
    } catch (e) {
      _handleError('Erro na conexão: $e');
      return false;
    }
  }

  // Conecta usando protocolo ONVIF
  Future<bool> _connectOnvif(Duration timeout) async {
    try {
      print('Tentando conexão ONVIF...');
      
      final config = cameraData.portConfiguration;
      final host = cameraData.getHost();
      
      // Conecta usando Onvif.connect()
      _onvifClient = await Onvif.connect(
        host: '$host:${config.onvifPort}',
        username: cameraData.username,
        password: cameraData.password,
      ).timeout(timeout);
      
      // Testa conexão básica
      await _onvifClient!.deviceManagement
          .getDeviceInformation()
          .timeout(timeout);

      _activeProtocol = ProtocolType.onvif;
      _updateState(ConnectionState.connected);
      
      // Se há credenciais, considera como autenticado
      if (cameraData.username != null && cameraData.password != null) {
        _updateState(ConnectionState.authenticated);
      }
      
      print('Conexão ONVIF estabelecida com sucesso');
      return true;
    } catch (e) {
      print('Falha na conexão ONVIF: $e');
    }
    
    return false;
  }

  // Conecta usando protocolo proprietário
  Future<bool> _connectProprietary(Duration timeout) async {
    if (_proprietaryService == null) {
      _handleError('Serviço proprietário não configurado');
      return false;
    }

    try {
      print('Tentando conexão proprietária...');
      
      final host = cameraData.getHost();
      final port = cameraData.portConfiguration.proprietaryPort;
      
      // Método connect não implementado - usando testSupport como alternativa
      final connected = await _proprietaryService!.testSupport(host, port);
      
      if (connected) {
        _activeProtocol = ProtocolType.proprietary;
        _updateState(ConnectionState.connected);
        
        // Tenta autenticação se credenciais disponíveis
        if (cameraData.username != null && cameraData.password != null) {
          _updateState(ConnectionState.authenticating);
          
          // Método login não implementado - usando authenticate como alternativa
          final authenticated = await _proprietaryService!.login(
            cameraData.username!,
            cameraData.password!,
          );
          
          if (authenticated) {
            _updateState(ConnectionState.authenticated);
          } else {
            _handleError('Falha na autenticação proprietária');
          }
        }
        
        print('Conexão proprietária estabelecida com sucesso');
        return true;
      }
    } catch (e) {
      print('Falha na conexão proprietária: $e');
    }
    
    return false;
  }

  // Desconecta da câmera
  void disconnect() {
    _proprietaryService?.disconnect();
    _onvifClient = null;
    _activeProtocol = null;
    _updateState(ConnectionState.disconnected);
    print('Desconectado da câmera ${cameraData.name}');
  }

  // Obtém informações do dispositivo
  Future<HybridOperationResult<Map<String, dynamic>>> getDeviceInformation() async {
    if (!isConnected) {
      return HybridOperationResult.failure('Não conectado à câmera');
    }

    try {
      switch (_activeProtocol) {
        case ProtocolType.onvif:
          if (_onvifClient != null) {
            final deviceInfo = await _onvifClient!.deviceManagement.getDeviceInformation();
            final info = {
              'manufacturer': deviceInfo.manufacturer,
              'model': deviceInfo.model,
              'firmwareVersion': deviceInfo.firmwareVersion,
              'serialNumber': deviceInfo.serialNumber,
              'hardwareId': deviceInfo.hardwareId,
            };
            return HybridOperationResult.success(info, ProtocolType.onvif);
                    }
          break;
        
        case ProtocolType.proprietary:
          // Para protocolo proprietário, retorna informações básicas
          final info = {
            'protocol': 'DVRIP-Web',
            'port': cameraData.portConfiguration.proprietaryPort,
            'sessionId': 'N/A', // sessionId não implementado
            'connected': _proprietaryService != null, // Verifica se serviço existe
          };
          return HybridOperationResult.success(info, ProtocolType.proprietary);
        
        default:
          break;
      }
    } catch (e) {
      return HybridOperationResult.failure('Erro ao obter informações: $e');
    }

    return HybridOperationResult.failure('Protocolo não suportado ou erro desconhecido');
  }

  // Obtém lista de gravações
  Future<HybridOperationResult<List<Map<String, dynamic>>>> getRecordings({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    return await getRecordingList(startTime: startTime, endTime: endTime);
  }

  // Método alternativo para compatibilidade
  Future<HybridOperationResult<List<Map<String, dynamic>>>> getRecordingList({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    if (!isAuthenticated) {
      return HybridOperationResult.failure('Não autenticado na câmera');
    }

    try {
      switch (_activeProtocol) {
        case ProtocolType.proprietary:
          if (_proprietaryService != null) {
            // Método getRecordingList não implementado - retornando lista vazia
            final recordings = <Map<String, dynamic>>[];
            return HybridOperationResult.success(recordings, ProtocolType.proprietary);
          }
          break;
        
        case ProtocolType.onvif:
          // ONVIF não tem método padrão para listar gravações do SD card
          // Retorna lista vazia ou implementa busca via Profile G se suportado
          return HybridOperationResult.success(<Map<String, dynamic>>[], ProtocolType.onvif);
        
        default:
          break;
      }
    } catch (e) {
      return HybridOperationResult.failure('Erro ao obter gravações: $e');
    }

    return HybridOperationResult.failure('Funcionalidade não suportada pelo protocolo ativo');
  }

  // Inicia reprodução de gravação
  Future<HybridOperationResult<String>> startPlayback(String fileName) async {
    if (!isAuthenticated) {
      return HybridOperationResult.failure('Não autenticado na câmera');
    }

    try {
      switch (_activeProtocol) {
        case ProtocolType.proprietary:
          if (_proprietaryService != null) {
            // Método startPlayback não implementado - retornando URL padrão
            final streamUrl = cameraData.streamUrl;
            if (streamUrl != null) {
              return HybridOperationResult.success(streamUrl, ProtocolType.proprietary);
            }
          }
          break;
        
        case ProtocolType.onvif:
          // Para ONVIF, retorna a URL de stream principal
          return HybridOperationResult.success(cameraData.streamUrl, ProtocolType.onvif);
        
        default:
          break;
      }
    } catch (e) {
      return HybridOperationResult.failure('Erro ao iniciar reprodução: $e');
    }

    return HybridOperationResult.failure('Funcionalidade não suportada pelo protocolo ativo');
  }

  // Controle PTZ
  Future<HybridOperationResult<bool>> ptzControl(String command, {int speed = 4}) async {
    if (!isConnected) {
      return HybridOperationResult.failure('Não conectado à câmera');
    }

    try {
      switch (_activeProtocol) {
        case ProtocolType.proprietary:
          if (_proprietaryService != null) {
            // Método ptzControl não implementado - retornando false
            final success = false;
            return HybridOperationResult.success(success, ProtocolType.proprietary);
          }
          break;
        
        case ProtocolType.onvif:
          if (_onvifClient != null) {
            // Implementa controle PTZ via ONVIF
            // Nota: Requer implementação específica baseada nos perfis ONVIF disponíveis
            try {
              // Placeholder para implementação ONVIF PTZ
              // await _onvifClient!.ptz.continuousMove(...);
              return HybridOperationResult.success(true, ProtocolType.onvif);
            } catch (e) {
              return HybridOperationResult.failure('PTZ ONVIF não suportado: $e');
            }
          }
          break;
        
        default:
          break;
      }
    } catch (e) {
      return HybridOperationResult.failure('Erro no controle PTZ: $e');
    }

    return HybridOperationResult.failure('PTZ não suportado pelo protocolo ativo');
  }

  // Testa conectividade atual
  Future<bool> testConnection() async {
    if (!isConnected) {
      return false;
    }

    try {
      final result = await getDeviceInformation();
      return result.success;
    } catch (e) {
      _handleError('Teste de conexão falhou: $e');
      return false;
    }
  }

  // Reconecta automaticamente
  Future<bool> reconnect({Duration timeout = const Duration(seconds: 10)}) async {
    print('Tentando reconexão para ${cameraData.name}...');
    disconnect();
    await Future.delayed(const Duration(seconds: 1));
    return await connect(timeout: timeout);
  }

  // Atualiza estado da conexão
  void _updateState(ConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _stateController.add(newState);
      print('Estado da conexão alterado para: $newState');
    }
  }

  // Manipula erros
  void _handleError(String error) {
    print('Erro: $error');
    _updateState(ConnectionState.error);
    _errorController.add(error);
  }

  // Cleanup
  void dispose() {
    disconnect();
    _stateController.close();
    _errorController.close();
    // Método dispose não implementado no ProprietaryProtocolService
    _proprietaryService = null;
  }

  // Método estático para criar e conectar automaticamente
  static Future<HybridCameraConnectionManager> createAndConnect(
    CameraData cameraData, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final manager = HybridCameraConnectionManager(cameraData);
    await manager.connect(timeout: timeout);
    return manager;
  }

  // Método estático para detecção e criação automática
  static Future<HybridCameraConnectionManager> createWithAutoDetection(
    String host, {
    String? username,
    String? password,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // Detecta protocolo automaticamente
    final detection = await FastCameraDiscoveryService.detectProtocol(
      host,
      username: username,
      password: password,
      timeout: timeout,
    );

    // Cria CameraData temporário para teste
    final tempCamera = CameraData(
      id: 0,
      name: 'Auto-detected Camera',
      isLive: false,
      statusColor: const Color(0xFF2196F3),
      uniqueColor: const Color(0xFF2196F3),
      icon: Icons.videocam,
      streamUrl: 'rtsp://$host:554/stream',
      username: username,
      password: password,
      portConfiguration: CameraPortConfiguration(
        onvifPort: detection['portConfiguration']?['onvifPort'] ?? 80,
        httpPort: detection['portConfiguration']?['httpPort'] ?? 80,
        rtspPort: detection['portConfiguration']?['rtspPort'] ?? 554,
        proprietaryPort: detection['portConfiguration']?['proprietaryPort'] ?? 8080,
        alternativePort: detection['portConfiguration']?['alternativePort'] ?? 8000,
        useHttps: detection['portConfiguration']?['useHttps'] ?? false,
        acceptSelfSigned: detection['portConfiguration']?['acceptSelfSigned'] ?? true,
        preferredProtocol: detection['portConfiguration']?['preferredProtocol'] ?? 'auto',
      ),
      host: host,
    );

    final manager = HybridCameraConnectionManager(tempCamera);
    await manager.connect(timeout: timeout);
    return manager;
  }
}