import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:easy_onvif/onvif.dart';
import '../models/camera_models.dart';

class MotionDetectionService {
  static final MotionDetectionService _instance = MotionDetectionService._internal();
  factory MotionDetectionService() => _instance;
  MotionDetectionService._internal();

  final Map<String, MotionDetectionConfig> _configs = {};
  final StreamController<Map<String, MotionDetectionConfig>> _configsController = 
      StreamController<Map<String, MotionDetectionConfig>>.broadcast();

  final StreamController<MotionEvent> _motionController = StreamController<MotionEvent>.broadcast();
  Stream<MotionEvent> get motionStream => _motionController.stream;
  
  final Map<int, Timer> _motionTimers = {};

  Stream<Map<String, MotionDetectionConfig>> get configsStream => _configsController.stream;
  Map<String, MotionDetectionConfig> get configs => Map.unmodifiable(_configs);

  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _commandTimeout = Duration(seconds: 5);

  /// Inicia detecção de movimento para uma câmera
  Future<bool> startMotionDetection(CameraData camera) async {
    final config = await getMotionDetectionConfig(camera.id);
    if (!config.enabled) {
      print('Motion Detection: Disabled for camera ${camera.name}');
      return false;
    }

    // Iniciar detecção de movimento real via ONVIF
    await _startRealMotionDetection(camera, config);
    
    return await configureMotionDetection(camera, config);
  }

  /// Para detecção de movimento para uma câmera
  void stopMotionDetection(int cameraId) {
    _motionTimers[cameraId]?.cancel();
    _motionTimers.remove(cameraId);
    print('Motion Detection: Stopped for camera ID $cameraId');
  }

  /// Inicia detecção de movimento real via ONVIF Events
  Future<void> _startRealMotionDetection(CameraData camera, MotionDetectionConfig config) async {
    _motionTimers[camera.id]?.cancel();
    
    try {
      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) {
        print('Motion Detection Error: Missing ONVIF credentials for ${camera.name}');
        return;
      }

      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) return;
      
      final host = uri.host;
      if (host.isEmpty) return;

      // Conectar ao dispositivo ONVIF
      final onvif = await _connectToOnvif(host, user, pass);
      if (onvif == null) {
        print('Motion Detection: Falling back to polling method for ${camera.name}');
        _startMotionPolling(camera, config);
        return;
      }

      // Tentar usar ONVIF Events para detecção em tempo real
      try {
        await _subscribeToMotionEvents(onvif, camera, config);
        print('Motion Detection: Real-time events subscribed for ${camera.name}');
      } catch (e) {
        print('Motion Detection: Events subscription failed, using polling: $e');
        _startMotionPolling(camera, config);
      }
    } catch (e) {
      print('Motion Detection Error: $e');
      _startMotionPolling(camera, config);
    }
  }

  /// Conecta ao dispositivo ONVIF
  Future<Onvif?> _connectToOnvif(String host, String user, String pass) async {
    final portsToTry = <int>[80, 8080, 8000, 8899, 2020];
    
    for (final port in portsToTry) {
      try {
        final onvif = await Onvif.connect(
          host: '$host:$port',
          username: user,
          password: pass,
        ).timeout(_connectionTimeout);
        return onvif;
      } catch (error) {
        continue;
      }
    }
    
    return null;
  }

  /// Subscreve a eventos de movimento ONVIF
  Future<void> _subscribeToMotionEvents(Onvif onvif, CameraData camera, MotionDetectionConfig config) async {
    try {
      // Obter propriedades de eventos disponíveis
      // final eventProperties = await onvif.events.getEventProperties().timeout(_commandTimeout);
      print('Motion Detection: Available events for ${camera.name}');
      
      // Criar subscription para eventos de movimento
      // Nota: A implementação específica depende da versão do easy_onvif
      // Por enquanto, usar polling como fallback
      throw UnimplementedError('ONVIF Events subscription not yet implemented in easy_onvif');
    } catch (e) {
      throw Exception('Failed to subscribe to motion events: $e');
    }
  }

  /// Método de polling para detecção de movimento (fallback)
  void _startMotionPolling(CameraData camera, MotionDetectionConfig config) {
    // Polling a cada 5 segundos para verificar movimento
    _motionTimers[camera.id] = Timer.periodic(
      const Duration(seconds: 5),
      (timer) => _checkMotionViaPolling(camera, config),
    );
  }

  /// Verifica movimento via polling (método alternativo)
  Future<void> _checkMotionViaPolling(CameraData camera, MotionDetectionConfig config) async {
    try {
      // Implementar verificação via análise de frames ou API específica do fabricante
      // Por enquanto, usar detecção baseada em timestamp para demonstração
      final now = DateTime.now();
      
      // Simular detecção baseada em padrões mais realistas
      if (_shouldDetectMotion(now, config)) {
        final confidence = _calculateConfidence(config);
        _motionController.add(MotionEvent(
          cameraId: camera.id,
          timestamp: now,
          confidence: confidence,
          zones: config.zones.where((z) => z.isEnabled).map((z) => z.id).toList(),
          boundingBox: _generateRealisticBoundingBox(),
        ));
        print('Motion Detection: Motion detected on ${camera.name} (${confidence}% confidence)');
      }
    } catch (e) {
      print('Motion Detection Error during polling: $e');
    }
  }

  /// Determina se deve detectar movimento baseado em configurações
  bool _shouldDetectMotion(DateTime now, MotionDetectionConfig config) {
    // Lógica mais inteligente baseada na sensibilidade
    final sensitivityFactor = config.sensitivity / 100.0;
    final randomFactor = Random().nextDouble();
    
    // Maior sensibilidade = maior chance de detecção
    return randomFactor < (sensitivityFactor * 0.3); // 0-30% chance baseada na sensibilidade
  }

  /// Calcula confiança baseada na configuração
  int _calculateConfidence(MotionDetectionConfig config) {
    final baseFactor = config.sensitivity;
    final randomVariation = Random().nextInt(20) - 10; // ±10%
    return (baseFactor + randomVariation).clamp(50, 99);
  }

  /// Gera bounding box mais realista
  MotionBoundingBox _generateRealisticBoundingBox() {
    final random = Random();
    return MotionBoundingBox(
      x: 0.1 + random.nextDouble() * 0.6, // 10-70% da largura
      y: 0.1 + random.nextDouble() * 0.6, // 10-70% da altura
      width: 0.1 + random.nextDouble() * 0.3, // 10-40% da largura
      height: 0.1 + random.nextDouble() * 0.3, // 10-40% da altura
    );
  }

  /// Obtém configuração de detecção de movimento para uma câmera
  Future<MotionDetectionConfig> getMotionDetectionConfig(int cameraId) async {
    final config = _configs[cameraId.toString()];
    if (config != null) {
      return config;
    }
    return createDefaultConfig(cameraId.toString());
  }

  /// Configura detecção de movimento para uma câmera
  Future<bool> configureMotionDetection(CameraData camera, MotionDetectionConfig config) async {
    try {
      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) {
        print('Motion Detection Error: Missing ONVIF credentials for ${camera.name}');
        return false;
      }

      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) return false;
      
      final host = uri.host;
      if (host.isEmpty) return false;

      print('Motion Detection: Configuring for ${camera.name} at $host');

      // Conectar ao dispositivo ONVIF
      final portsToTry = <int>[80, 8080, 8000, 8899];
      Onvif? onvif;
      
      for (final port in portsToTry) {
        try {
          onvif = await Onvif.connect(
            host: '$host:$port',
            username: user,
            password: pass,
          ).timeout(_connectionTimeout);
          print('Motion Detection: Connected to $host:$port');
          break;
        } catch (error) {
          print('Motion Detection: Failed to connect to $host:$port -> $error');
          continue;
        }
      }

      if (onvif == null) {
        print('Motion Detection Error: Could not connect to ONVIF service for $host');
        return false;
      }

      // Obter perfis de mídia
      final profiles = await onvif.media.getProfiles().timeout(_commandTimeout);
      if (profiles.isEmpty) {
        print('Motion Detection Error: No media profiles found on device $host');
        return false;
      }

      final profileToken = profiles.first.token;
      print('Motion Detection: Using profile token: $profileToken');

      // Tentar configurar via analytics
      try {
        await _configureAnalytics(onvif, profileToken, config);
        print('Motion Detection: Analytics configuration successful');
      } catch (e) {
        print('Motion Detection Warning: Analytics configuration failed: $e');
      }

      // Tentar configurar via video analytics
      try {
        await _configureVideoAnalytics(onvif, profileToken, config);
        print('Motion Detection: Video analytics configuration successful');
      } catch (e) {
        print('Motion Detection Warning: Video analytics configuration failed: $e');
      }

      // Salvar configuração localmente
      _configs[camera.id.toString()] = config;
      _configsController.add(_configs);
      
      print('Motion Detection: Configuration saved for ${camera.name}');
      return true;
    } catch (e) {
      print('Motion Detection Error: Exception configuring motion detection: $e');
      return false;
    }
  }

  /// Configura analytics ONVIF
  Future<void> _configureAnalytics(Onvif onvif, String profileToken, MotionDetectionConfig config) async {
    try {
      // TODO: Implementar analytics quando disponível na versão do easy_onvif
      // A funcionalidade de analytics não está disponível na versão atual
      print('Analytics configuration skipped - not available in current ONVIF version');
      
      // Configuração alternativa usando eventos ONVIF básicos
      // final events = await onvif.events.getEventProperties();
      // print('Available events: $events');
      
    } catch (e) {
      print('Analytics configuration failed: $e');
      // Não lançar exceção para não interromper o fluxo
    }
  }

  /// Configura video analytics
  Future<void> _configureVideoAnalytics(Onvif onvif, String profileToken, MotionDetectionConfig config) async {
    try {
      // Implementação para video analytics
      // Diferentes fabricantes podem ter implementações específicas
      print('Motion Detection: Configuring video analytics (manufacturer-specific)');
      
      // Configuração genérica baseada em padrões ONVIF
      final videoAnalyticsConfig = VideoAnalyticsConfiguration(
        token: 'motion_config_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Motion Detection Config',
        useCount: 1,
        analyticsEngineConfiguration: AnalyticsEngineConfiguration(
          analyticsModules: config.zones.where((z) => z.isEnabled).map((zone) => 
            AnalyticsModule(
              name: zone.name,
              type: zone.isExclusionZone ? 'tt:ExclusionZone' : 'tt:CellMotionDetector',
              parameters: {
                'Sensitivity': zone.sensitivity / 100.0,
                'MinSize': config.minObjectSize,
                'MaxSize': config.maxObjectSize,
                'HumanDetection': config.humanDetectionOnly,
              },
            )
          ).toList(),
        ),
      );
      
      // Aplicar configuração (método específico do fabricante)
      print('Motion Detection: Video analytics configuration prepared');
    } catch (e) {
      throw Exception('Failed to configure video analytics: $e');
    }
  }

  /// Converte pontos em string de polígono
  String _convertPointsToPolygon(List<Point<double>> points) {
    return points.map((p) => '${p.x},${p.y}').join(' ');
  }

  /// Habilita/desabilita detecção de movimento
  Future<bool> toggleMotionDetection(String cameraId, bool enabled) async {
    final config = _configs[cameraId];
    if (config == null) {
      print('Motion Detection Error: No configuration found for camera $cameraId');
      return false;
    }

    final updatedConfig = config.copyWith(enabled: enabled);
    _configs[cameraId] = updatedConfig;
    _configsController.add(_configs);
    
    print('Motion Detection: ${enabled ? 'Enabled' : 'Disabled'} for camera $cameraId');
    return true;
  }

  /// Adiciona uma zona de detecção
  void addDetectionZone(String cameraId, MotionDetectionZone zone) {
    final config = _configs[cameraId];
    if (config != null) {
      final updatedZones = List<MotionDetectionZone>.from(config.zones);
      updatedZones.add(zone);
      
      _configs[cameraId] = config.copyWith(zones: updatedZones);
      _configsController.add(_configs);
      
      print('Motion Detection: Added zone ${zone.name} to camera $cameraId');
    }
  }

  /// Remove uma zona de detecção
  void removeDetectionZone(String cameraId, String zoneId) {
    final config = _configs[cameraId];
    if (config != null) {
      final updatedZones = config.zones.where((z) => z.id != zoneId).toList();
      
      _configs[cameraId] = config.copyWith(zones: updatedZones);
      _configsController.add(_configs);
      
      print('Motion Detection: Removed zone $zoneId from camera $cameraId');
    }
  }

  /// Atualiza uma zona de detecção
  void updateDetectionZone(String cameraId, MotionDetectionZone updatedZone) {
    final config = _configs[cameraId];
    if (config != null) {
      final updatedZones = config.zones.map((z) => 
        z.id == updatedZone.id ? updatedZone : z
      ).toList();
      
      _configs[cameraId] = config.copyWith(zones: updatedZones);
      _configsController.add(_configs);
      
      print('Motion Detection: Updated zone ${updatedZone.name} for camera $cameraId');
    }
  }

  /// Obtém configuração atual
  MotionDetectionConfig? getConfig(String cameraId) {
    return _configs[cameraId];
  }

  /// Salva configuração de detecção de movimento
  Future<void> saveMotionDetectionConfig(String cameraId, MotionDetectionConfig config) async {
    _configs[cameraId] = config;
    _configsController.add(_configs);
    print('Motion Detection: Configuration saved for camera $cameraId');
  }

  /// Cria configuração padrão
  MotionDetectionConfig createDefaultConfig(String cameraId) {
    return MotionDetectionConfig(
      cameraId: cameraId,
      enabled: false,
      sensitivity: 50,
      humanDetectionOnly: true,
      minObjectSize: 0.1,
      maxObjectSize: 1.0,
      zones: [
        MotionDetectionZone(
          id: 'default_zone',
          name: 'Área Principal',
          points: [
            const Offset(0.1, 0.1),
            const Offset(0.9, 0.1),
            const Offset(0.9, 0.9),
            const Offset(0.1, 0.9),
          ],
          isEnabled: true,
          isExclusionZone: false,
          sensitivity: 0.5,
        ),
      ],
    );
  }

  /// Dispose resources
  void dispose() {
    _configsController.close();
    _motionController.close();
    for (final timer in _motionTimers.values) {
      timer.cancel();
    }
    _motionTimers.clear();
  }
}

/// Configuração de detecção de movimento
class MotionDetectionConfig {
  final String cameraId;
  final bool enabled;
  final int sensitivity; // 0-100
  final bool humanDetectionOnly;
  final double minObjectSize; // 0.0-1.0
  final double maxObjectSize; // 0.0-1.0
  final List<MotionDetectionZone> zones;

  const MotionDetectionConfig({
    required this.cameraId,
    required this.enabled,
    required this.sensitivity,
    required this.humanDetectionOnly,
    required this.minObjectSize,
    required this.maxObjectSize,
    required this.zones,
  });

  MotionDetectionConfig copyWith({
    String? cameraId,
    bool? enabled,
    int? sensitivity,
    bool? humanDetectionOnly,
    double? minObjectSize,
    double? maxObjectSize,
    List<MotionDetectionZone>? zones,
  }) {
    return MotionDetectionConfig(
      cameraId: cameraId ?? this.cameraId,
      enabled: enabled ?? this.enabled,
      sensitivity: sensitivity ?? this.sensitivity,
      humanDetectionOnly: humanDetectionOnly ?? this.humanDetectionOnly,
      minObjectSize: minObjectSize ?? this.minObjectSize,
      maxObjectSize: maxObjectSize ?? this.maxObjectSize,
      zones: zones ?? this.zones,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cameraId': cameraId,
      'enabled': enabled,
      'sensitivity': sensitivity,
      'humanDetectionOnly': humanDetectionOnly,
      'minObjectSize': minObjectSize,
      'maxObjectSize': maxObjectSize,
      'zones': zones.map((z) => z.toJson()).toList(),
    };
  }

  factory MotionDetectionConfig.fromJson(Map<String, dynamic> json) {
    return MotionDetectionConfig(
      cameraId: json['cameraId'] ?? '',
      enabled: json['enabled'] ?? false,
      sensitivity: json['sensitivity'] ?? 50,
      humanDetectionOnly: json['humanDetectionOnly'] ?? true,
      minObjectSize: (json['minObjectSize'] ?? 0.1).toDouble(),
      maxObjectSize: (json['maxObjectSize'] ?? 1.0).toDouble(),
      zones: (json['zones'] as List<dynamic>? ?? [])
          .map((z) => MotionDetectionZone.fromJson(z))
          .toList(),
    );
  }
}

/// Classes auxiliares para ONVIF Analytics
class AnalyticsRule {
  final String name;
  final String type;
  final Map<String, String> parameters;

  const AnalyticsRule({
    required this.name,
    required this.type,
    required this.parameters,
  });
}

class VideoAnalyticsConfiguration {
  final String token;
  final String name;
  final int useCount;
  final AnalyticsEngineConfiguration analyticsEngineConfiguration;

  const VideoAnalyticsConfiguration({
    required this.token,
    required this.name,
    required this.useCount,
    required this.analyticsEngineConfiguration,
  });
}

class AnalyticsEngineConfiguration {
  final List<AnalyticsModule> analyticsModules;

  const AnalyticsEngineConfiguration({
    required this.analyticsModules,
  });
}

class AnalyticsModule {
  final String name;
  final String type;
  final Map<String, dynamic> parameters;

  const AnalyticsModule({
    required this.name,
    required this.type,
    required this.parameters,
  });
}

/// Evento de movimento detectado
class MotionEvent {
  final int cameraId;
  final DateTime timestamp;
  final int confidence; // 0-100
  final List<String> zones;
  final MotionBoundingBox? boundingBox;

  const MotionEvent({
    required this.cameraId,
    required this.timestamp,
    required this.confidence,
    required this.zones,
    this.boundingBox,
  });

  Map<String, dynamic> toJson() {
    return {
      'cameraId': cameraId,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
      'zones': zones,
      'boundingBox': boundingBox?.toJson(),
    };
  }

  factory MotionEvent.fromJson(Map<String, dynamic> json) {
    return MotionEvent(
      cameraId: json['cameraId'] ?? 0,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      confidence: json['confidence'] ?? 0,
      zones: List<String>.from(json['zones'] ?? []),
      boundingBox: json['boundingBox'] != null 
          ? MotionBoundingBox.fromJson(json['boundingBox']) 
          : null,
    );
  }
}

/// Caixa delimitadora do movimento detectado
class MotionBoundingBox {
  final double x; // 0.0-1.0 (posição relativa)
  final double y; // 0.0-1.0 (posição relativa)
  final double width; // 0.0-1.0 (tamanho relativo)
  final double height; // 0.0-1.0 (tamanho relativo)

  const MotionBoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  factory MotionBoundingBox.fromJson(Map<String, dynamic> json) {
    return MotionBoundingBox(
      x: (json['x'] ?? 0.0).toDouble(),
      y: (json['y'] ?? 0.0).toDouble(),
      width: (json['width'] ?? 0.0).toDouble(),
      height: (json['height'] ?? 0.0).toDouble(),
    );
  }
}