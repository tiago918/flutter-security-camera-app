import 'dart:async';
import 'package:easy_onvif/onvif.dart';
import '../models/camera_models.dart';
import '../models/camera_model.dart';
import 'hybrid_camera_connection_manager.dart';

/// Serviço ONVIF unificado que usa a nova arquitetura de portas
/// e integra com o HybridCameraConnectionManager
class UnifiedOnvifService {
  static final UnifiedOnvifService _instance = UnifiedOnvifService._internal();
  factory UnifiedOnvifService() => _instance;
  UnifiedOnvifService._internal();

  final Map<String, HybridCameraConnectionManager> _connectionManagers = {};
  final Map<String, Onvif> _onvifConnections = {};
  
  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _commandTimeout = Duration(seconds: 5);

  /// Conecta a uma câmera usando a nova arquitetura de portas
  Future<bool> connect(CameraData camera) async {
    try {
      final cameraId = camera.id.toString();
      
      // Verificar se já existe conexão ativa
      if (_connectionManagers.containsKey(cameraId)) {
        final manager = _connectionManagers[cameraId]!;
        if (manager.connectionState == ConnectionState.connected) {
          return true;
        }
      }

      // Criar novo gerenciador de conexão híbrida
      final manager = await HybridCameraConnectionManager.createAndConnect(camera);
      if (manager.connectionState == ConnectionState.connected) {
        _connectionManagers[cameraId] = manager;
        
        // Se for protocolo ONVIF ou híbrido, manter referência da conexão ONVIF
        if (camera.portConfiguration.preferredProtocol == 'onvif' ||
            camera.portConfiguration.preferredProtocol == 'hybrid') {
          final onvif = await _createOnvifConnection(camera);
          if (onvif != null) {
            _onvifConnections[cameraId] = onvif;
          }
        }
        
        return true;
      }
      
      return false;
    } catch (e) {
      print('UnifiedOnvifService: Error connecting to ${camera.name}: $e');
      return false;
    }
  }

  /// Desconecta de uma câmera
  Future<void> disconnect(String cameraId) async {
    try {
      final manager = _connectionManagers[cameraId];
      if (manager != null) {
        manager.disconnect();
        _connectionManagers.remove(cameraId);
      }
      
      _onvifConnections.remove(cameraId);
    } catch (e) {
      print('UnifiedOnvifService: Error disconnecting camera $cameraId: $e');
    }
  }

  /// Obtém informações do dispositivo
  Future<Map<String, dynamic>?> getDeviceInformation(String cameraId) async {
    try {
      final manager = _connectionManagers[cameraId];
      if (manager == null) return null;
      
      final result = await manager.getDeviceInformation();
      return result.isSuccess ? result.data : null;
    } catch (e) {
      print('UnifiedOnvifService: Error getting device info for $cameraId: $e');
      return null;
    }
  }

  /// Obtém lista de gravações
  Future<List<RecordingInfo>> getRecordingList(
    String cameraId, {
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    try {
      final manager = _connectionManagers[cameraId];
      if (manager == null) return [];
      
      final result = await manager.getRecordingList(
        startTime: startTime,
        endTime: endTime,
      );
      
      if (result.isSuccess && result.data is List) {
        return (result.data as List)
            .map((item) => RecordingInfo.fromJson(item))
            .toList();
      }
      
      return [];
    } catch (e) {
      print('UnifiedOnvifService: Error getting recordings for $cameraId: $e');
      return [];
    }
  }

  /// Inicia reprodução de gravação
  Future<String?> startPlayback(
    String cameraId,
    String recordingId,
  ) async {
    try {
      final manager = _connectionManagers[cameraId];
      if (manager == null) return null;
      
      final result = await manager.startPlayback(recordingId);
      return result.isSuccess ? result.data : null;
    } catch (e) {
      print('UnifiedOnvifService: Error starting playback for $cameraId: $e');
      return null;
    }
  }

  /// Controla PTZ
  Future<bool> ptzControl(
    String cameraId,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    try {
      final manager = _connectionManagers[cameraId];
      if (manager == null) return false;
      
      final result = await manager.ptzControl(command, speed: parameters['speed'] ?? 4);
      return result.isSuccess;
    } catch (e) {
      print('UnifiedOnvifService: Error controlling PTZ for $cameraId: $e');
      return false;
    }
  }

  /// Obtém capacidades da câmera usando ONVIF
  Future<CameraCapabilities?> getCapabilities(String cameraId) async {
    try {
      final onvif = _onvifConnections[cameraId];
      if (onvif == null) return null;

      final capabilities = CameraCapabilities(
        supportsPTZ: await _checkPtzSupport(onvif),
        hasEvents: await _checkEventsSupport(onvif),
        supportsAudio: await _checkAudioSupport(onvif),
        supportsNightMode: await _checkNightModeSupport(onvif),
        supportsMotionDetection: await _checkMotionDetectionSupport(onvif),
        supportsRecording: await _checkRecordingSupport(onvif),
      );

      return capabilities;
    } catch (e) {
      print('UnifiedOnvifService: Error getting capabilities for $cameraId: $e');
      return null;
    }
  }

  /// Testa conexão com uma câmera
  Future<bool> testConnection(CameraData camera) async {
    try {
      final manager = await HybridCameraConnectionManager.createAndConnect(camera);
      final isConnected = manager.connectionState == ConnectionState.connected;
      manager.disconnect();
      return isConnected;
    } catch (e) {
      print('UnifiedOnvifService: Error testing connection to ${camera.name}: $e');
      return false;
    }
  }

  /// Obtém o gerenciador de conexão para uma câmera
  HybridCameraConnectionManager? getConnectionManager(String cameraId) {
    return _connectionManagers[cameraId];
  }

  /// Obtém a conexão ONVIF direta (se disponível)
  Onvif? getOnvifConnection(String cameraId) {
    return _onvifConnections[cameraId];
  }

  /// Getter para compatibilidade com código existente
  Onvif? get onvifConnection {
    // Retorna a primeira conexão ONVIF disponível
    return _onvifConnections.values.isNotEmpty ? _onvifConnections.values.first : null;
  }

  /// Cria conexão ONVIF usando a configuração de portas
  Future<Onvif?> _createOnvifConnection(CameraData camera) async {
    try {
      final host = camera.getHost();
      final config = camera.portConfiguration;
      final user = camera.username ?? '';
      final pass = camera.password ?? '';

      if (user.isEmpty || pass.isEmpty) {
        print('UnifiedOnvifService: Missing credentials for ${camera.name}');
        return null;
      }

      // Tentar porta ONVIF específica primeiro
      try {
        return await Onvif.connect(
          host: '$host:${config.onvifPort}',
          username: user,
          password: pass,
        ).timeout(_connectionTimeout);
      } catch (e) {
        print('UnifiedOnvifService: Failed to connect to ONVIF port ${config.onvifPort}: $e');
      }
    
      // Tentar portas de fallback padrão
      final fallbackPorts = [80, 8080, 554, 8554];
      for (final port in fallbackPorts) {
        try {
          return await Onvif.connect(
            host: '$host:$port',
            username: user,
            password: pass,
          ).timeout(_connectionTimeout);
        } catch (e) {
          continue;
        }
      }

      return null;
    } catch (e) {
      print('UnifiedOnvifService: Error creating ONVIF connection: $e');
      return null;
    }
  }

  // Métodos para verificar capacidades específicas
  Future<bool> _checkPtzSupport(Onvif onvif) async {
    try {
      final profiles = await onvif.media.getProfiles().timeout(_commandTimeout);
      return profiles.any((profile) => profile.ptzConfiguration != null);
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkEventsSupport(Onvif onvif) async {
    try {
      // Verificar se o serviço de eventos está disponível
      // Nota: Implementação específica depende da versão do easy_onvif
      return false; // Por enquanto, assumir não suportado
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkAudioSupport(Onvif onvif) async {
    try {
      final profiles = await onvif.media.getProfiles().timeout(_commandTimeout);
      return profiles.any((profile) => profile.audioEncoderConfiguration != null);
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkNightModeSupport(Onvif onvif) async {
    try {
      // Verificar se há configurações de imagem disponíveis
      return true; // Assumir suporte básico
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkMotionDetectionSupport(Onvif onvif) async {
    try {
      // Verificar se há configurações de análise de vídeo
      return true; // Assumir suporte básico
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkRecordingSupport(Onvif onvif) async {
    try {
      // Verificar se há capacidades de gravação
      return true; // Assumir suporte básico
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkNotificationsSupport(Onvif onvif) async {
    try {
      // Verificar se há suporte a eventos/notificações
      return false; // Por enquanto, assumir não suportado
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkPlaybackSupport(Onvif onvif) async {
    try {
      // Verificar se há capacidades de reprodução
      return true; // Assumir suporte básico
    } catch (e) {
      return false;
    }
  }

  /// Limpa todas as conexões
  Future<void> dispose() async {
    for (final manager in _connectionManagers.values) {
      manager.disconnect();
    }
    _connectionManagers.clear();
    _onvifConnections.clear();
  }
}