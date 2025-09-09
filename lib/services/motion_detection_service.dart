import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:async/async.dart';

import '../models/models.dart';
import 'camera_service.dart';
import 'notification_service.dart';

class MotionDetectionService {
  static final MotionDetectionService _instance = MotionDetectionService._internal();
  factory MotionDetectionService() => _instance;
  MotionDetectionService._internal();

  final CameraService _cameraService = CameraService();
  final Map<String, MotionDetectionConfig> _configs = {};
  final Map<String, StreamController<MotionEvent>> _motionStreams = {};
  final Map<String, Timer?> _detectionTimers = {};
  final Map<String, DateTime?> _lastMotionDetected = {};
  final Map<String, List<MotionZone>> _detectionZones = {};

  /// Configura detecção de movimento para uma câmera
  Future<bool> configureMotionDetection(
    String cameraId,
    MotionDetectionConfig config,
  ) async {
    if (!_cameraService.isConnected(cameraId)) {
      print('Câmera $cameraId não está conectada');
      return false;
    }

    try {
      final command = {
        'Command': 'SET_MOTION_DETECTION',
        'Enabled': config.enabled,
        'Sensitivity': config.sensitivity,
        'Threshold': config.threshold,
        'MinObjectSize': config.minObjectSize,
        'MaxObjectSize': config.maxObjectSize,
        'DetectionAreas': config.detectionAreas.map((area) => {
          'x': area.x,
          'y': area.y,
          'width': area.width,
          'height': area.height,
          'enabled': area.enabled,
        }).toList(),
        'Schedule': config.schedule?.map((schedule) => {
          'dayOfWeek': schedule.dayOfWeek,
          'startTime': schedule.startTime,
          'endTime': schedule.endTime,
          'enabled': schedule.enabled,
        }).toList(),
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        _configs[cameraId] = config;
        
        if (config.enabled) {
          _startMotionDetection(cameraId);
        } else {
          _stopMotionDetection(cameraId);
        }
        
        print('Detecção de movimento configurada para câmera $cameraId');
        return true;
      } else {
        print('Falha ao configurar detecção de movimento: ${response?['Error'] ?? 'Erro desconhecido'}');
        return false;
      }
    } catch (e) {
      print('Erro ao configurar detecção de movimento para câmera $cameraId: $e');
      return false;
    }
  }

  /// Habilita detecção de movimento
  Future<bool> enableMotionDetection(String cameraId) async {
    final config = _configs[cameraId];
    if (config == null) {
      print('Configuração de detecção de movimento não encontrada para câmera $cameraId');
      return false;
    }

    final updatedConfig = config.copyWith(enabled: true);
    return await configureMotionDetection(cameraId, updatedConfig);
  }

  /// Desabilita detecção de movimento
  Future<bool> disableMotionDetection(String cameraId) async {
    final config = _configs[cameraId];
    if (config == null) {
      print('Configuração de detecção de movimento não encontrada para câmera $cameraId');
      return false;
    }

    final updatedConfig = config.copyWith(enabled: false);
    return await configureMotionDetection(cameraId, updatedConfig);
  }

  /// Inicia detecção de movimento para uma câmera
  Future<bool> startMotionDetection(CameraModel camera) async {
    return await enableMotionDetection(camera.id.toString());
  }

  /// Para detecção de movimento para uma câmera
  void stopMotionDetection(String cameraId) {
    _stopMotionDetection(cameraId);
  }

  /// Stream de eventos de movimento
  Stream<MotionEvent>? get motionStream {
    // Retorna um stream combinado de todos os eventos de movimento
    if (_motionStreams.isEmpty) return null;
    
    final streams = _motionStreams.values.map((controller) => controller.stream).toList();
    if (streams.isEmpty) return null;
    if (streams.length == 1) return streams.first;
    
    return StreamGroup.merge(streams);
  }

  /// Inicia monitoramento de detecção de movimento
  void _startMotionDetection(String cameraId) {
    // Para timer anterior se existir
    _detectionTimers[cameraId]?.cancel();
    
    // Cria stream de eventos se não existir
    if (_motionStreams[cameraId] == null) {
      _motionStreams[cameraId] = StreamController<MotionEvent>.broadcast();
    }

    // Inicia polling de eventos de movimento
    _detectionTimers[cameraId] = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _checkMotionEvents(cameraId),
    );

    print('Detecção de movimento iniciada para câmera $cameraId');
  }

  /// Para monitoramento de detecção de movimento
  void _stopMotionDetection(String cameraId) {
    _detectionTimers[cameraId]?.cancel();
    _detectionTimers.remove(cameraId);
    print('Detecção de movimento parada para câmera $cameraId');
  }

  /// Verifica eventos de movimento
  Future<void> _checkMotionEvents(String cameraId) async {
    try {
      final command = {
        'Command': 'GET_MOTION_EVENTS',
        'Since': _lastMotionDetected[cameraId]?.millisecondsSinceEpoch ?? 
                (DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch),
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        final events = response['Events'] as List? ?? [];
        
        for (final eventData in events) {
          final motionEvent = _parseMotionEvent(cameraId, eventData);
          if (motionEvent != null) {
            _processMotionEvent(cameraId, motionEvent);
          }
        }
      }
    } catch (e) {
      print('Erro ao verificar eventos de movimento para câmera $cameraId: $e');
    }
  }

  /// Processa evento de movimento
  void _processMotionEvent(String cameraId, MotionEvent event) {
    _lastMotionDetected[cameraId] = event.timestamp;
    
    // Adiciona ao stream
    _motionStreams[cameraId]?.add(event);
    
    // Log do evento
    print('Movimento detectado na câmera $cameraId: ${event.confidence}% de confiança');
    
    // Processa ações automáticas se configuradas
    _processAutomaticActions(cameraId, event);
  }

  /// Processa ações automáticas baseadas no evento
  void _processAutomaticActions(String cameraId, MotionEvent event) {
    final config = _configs[cameraId];
    if (config == null) return;

    // Implementar ações automáticas como:
    // - Enviar notificação
    // - Iniciar gravação
    // - Capturar snapshot
    // - Ativar alarme
    
    // Exemplo: Log de ação automática
    if (event.confidence >= config.threshold) {
      print('Ação automática ativada para câmera $cameraId - Confiança: ${event.confidence}%');
    }
  }

  /// Converte dados do evento em MotionEvent
  MotionEvent? _parseMotionEvent(String cameraId, Map<String, dynamic> eventData) {
    try {
      return MotionEvent(
        id: eventData['Id'] ?? _generateEventId(),
        cameraId: cameraId,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          eventData['Timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        ),
        confidence: (eventData['Confidence'] ?? 0.0).toDouble(),
        boundingBoxes: (eventData['BoundingBoxes'] as List? ?? [])
            .map((box) => MotionBoundingBox(
                  x: (box['x'] ?? 0.0).toDouble(),
                  y: (box['y'] ?? 0.0).toDouble(),
                  width: (box['width'] ?? 0.0).toDouble(),
                  height: (box['height'] ?? 0.0).toDouble(),
                  confidence: (box['confidence'] ?? 0.0).toDouble(),
                ))
            .toList(),
        detectionZones: (eventData['DetectionZones'] as List? ?? [])
            .map((zone) => zone.toString())
            .toList(),
        metadata: Map<String, dynamic>.from(eventData['Metadata'] ?? {}),
      );
    } catch (e) {
      print('Erro ao converter evento de movimento: $e');
      return null;
    }
  }

  /// Gera ID único para evento
  String _generateEventId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    return '${timestamp}_$random';
  }

  /// Obtém configuração atual de detecção de movimento
  MotionDetectionConfig? getMotionDetectionConfig(String cameraId) {
    return _configs[cameraId];
  }

  /// Obtém stream de eventos de movimento
  Stream<MotionEvent>? getMotionEventStream(String cameraId) {
    return _motionStreams[cameraId]?.stream;
  }

  /// Verifica se detecção de movimento está ativa
  bool isMotionDetectionActive(String cameraId) {
    final config = _configs[cameraId];
    return config?.enabled == true && _detectionTimers[cameraId] != null;
  }

  /// Obtém último evento de movimento
  DateTime? getLastMotionDetected(String cameraId) {
    return _lastMotionDetected[cameraId];
  }

  /// Configura zonas de detecção
  Future<bool> configureDetectionZones(
    String cameraId,
    List<MotionZone> zones,
  ) async {
    try {
      final command = {
        'Command': 'SET_DETECTION_ZONES',
        'Zones': zones.map((zone) => {
          'id': zone.id,
          'name': zone.name,
          'points': zone.points.map((point) => {
            'x': point.x,
            'y': point.y,
          }).toList(),
          'sensitivity': zone.sensitivity,
          'enabled': zone.enabled,
        }).toList(),
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        _detectionZones[cameraId] = zones;
        print('Zonas de detecção configuradas para câmera $cameraId');
        return true;
      } else {
        print('Falha ao configurar zonas de detecção: ${response?['Error'] ?? 'Erro desconhecido'}');
        return false;
      }
    } catch (e) {
      print('Erro ao configurar zonas de detecção para câmera $cameraId: $e');
      return false;
    }
  }

  /// Obtém zonas de detecção configuradas
  List<MotionZone> getDetectionZones(String cameraId) {
    return _detectionZones[cameraId] ?? [];
  }

  /// Testa detecção de movimento
  Future<bool> testMotionDetection(String cameraId) async {
    try {
      final command = {
        'Command': 'TEST_MOTION_DETECTION',
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      return response != null && response['Ret'] == 100;
    } catch (e) {
      print('Erro ao testar detecção de movimento para câmera $cameraId: $e');
      return false;
    }
  }

  /// Obtém estatísticas de detecção de movimento
  Future<MotionDetectionStats?> getMotionDetectionStats(String cameraId) async {
    try {
      final command = {
        'Command': 'GET_MOTION_STATS',
        'Period': '24h', // Últimas 24 horas
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        return MotionDetectionStats(
          totalEvents: response['TotalEvents'] ?? 0,
          eventsToday: response['EventsToday'] ?? 0,
          averageConfidence: (response['AverageConfidence'] ?? 0.0).toDouble(),
          lastEventTime: response['LastEventTime'] != null
              ? DateTime.fromMillisecondsSinceEpoch(response['LastEventTime'])
              : null,
          detectionRate: (response['DetectionRate'] ?? 0.0).toDouble(),
          falsePositiveRate: (response['FalsePositiveRate'] ?? 0.0).toDouble(),
        );
      }
    } catch (e) {
      print('Erro ao obter estatísticas de detecção de movimento para câmera $cameraId: $e');
    }
    
    return null;
  }

  /// Limpa histórico de eventos
  Future<bool> clearMotionHistory(String cameraId) async {
    try {
      final command = {
        'Command': 'CLEAR_MOTION_HISTORY',
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        _lastMotionDetected.remove(cameraId);
        return true;
      }
    } catch (e) {
      print('Erro ao limpar histórico de movimento para câmera $cameraId: $e');
    }
    
    return false;
  }

  /// Obtém status da detecção de movimento
  Map<String, dynamic> getMotionDetectionStatus(String cameraId) {
    final config = _configs[cameraId];
    final isActive = isMotionDetectionActive(cameraId);
    final lastMotion = getLastMotionDetected(cameraId);
    
    return {
      'enabled': config?.enabled ?? false,
      'active': isActive,
      'sensitivity': config?.sensitivity ?? 50,
      'threshold': config?.threshold ?? 70.0,
      'lastMotionDetected': lastMotion?.toIso8601String(),
      'timeSinceLastMotion': lastMotion != null
          ? DateTime.now().difference(lastMotion).inSeconds
          : null,
      'detectionZones': getDetectionZones(cameraId).length,
    };
  }

  /// Dispose do serviço
  void dispose() {
    // Para todos os timers
    for (final timer in _detectionTimers.values) {
      timer?.cancel();
    }
    _detectionTimers.clear();
    
    // Fecha todos os streams
    for (final stream in _motionStreams.values) {
      stream.close();
    }
    _motionStreams.clear();
    
    _configs.clear();
    _lastMotionDetected.clear();
    _detectionZones.clear();
  }
}

/// Classe para representar configuração de detecção de movimento
class MotionDetectionConfig {
  final bool enabled;
  final int sensitivity; // 0-100
  final double threshold; // 0.0-100.0
  final int minObjectSize;
  final int maxObjectSize;
  final List<MotionDetectionArea> detectionAreas;
  final List<MotionDetectionSchedule>? schedule;

  const MotionDetectionConfig({
    required this.enabled,
    required this.sensitivity,
    required this.threshold,
    this.minObjectSize = 50,
    this.maxObjectSize = 5000,
    this.detectionAreas = const [],
    this.schedule,
  });

  MotionDetectionConfig copyWith({
    bool? enabled,
    int? sensitivity,
    double? threshold,
    int? minObjectSize,
    int? maxObjectSize,
    List<MotionDetectionArea>? detectionAreas,
    List<MotionDetectionSchedule>? schedule,
  }) {
    return MotionDetectionConfig(
      enabled: enabled ?? this.enabled,
      sensitivity: sensitivity ?? this.sensitivity,
      threshold: threshold ?? this.threshold,
      minObjectSize: minObjectSize ?? this.minObjectSize,
      maxObjectSize: maxObjectSize ?? this.maxObjectSize,
      detectionAreas: detectionAreas ?? this.detectionAreas,
      schedule: schedule ?? this.schedule,
    );
  }
}

/// Classe para representar área de detecção
class MotionDetectionArea {
  final double x;
  final double y;
  final double width;
  final double height;
  final bool enabled;

  const MotionDetectionArea({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.enabled = true,
  });
}

/// Classe para representar agendamento de detecção
class MotionDetectionSchedule {
  final int dayOfWeek; // 0-6 (domingo-sábado)
  final String startTime; // HH:mm
  final String endTime; // HH:mm
  final bool enabled;

  const MotionDetectionSchedule({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.enabled = true,
  });
}

/// Classe para representar evento de movimento
class MotionEvent {
  final String id;
  final String cameraId;
  final DateTime timestamp;
  final double confidence;
  final List<MotionBoundingBox> boundingBoxes;
  final List<String> detectionZones;
  final Map<String, dynamic> metadata;

  const MotionEvent({
    required this.id,
    required this.cameraId,
    required this.timestamp,
    required this.confidence,
    this.boundingBoxes = const [],
    this.detectionZones = const [],
    this.metadata = const {},
  });
}

/// Classe para representar bounding box de movimento
class MotionBoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;

  const MotionBoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });
}

/// Classe para representar zona de detecção
class MotionZone {
  final String id;
  final String name;
  final List<MotionPoint> points;
  final int sensitivity;
  final bool enabled;

  const MotionZone({
    required this.id,
    required this.name,
    required this.points,
    this.sensitivity = 50,
    this.enabled = true,
  });
}

/// Classe para representar ponto de zona
class MotionPoint {
  final double x;
  final double y;

  const MotionPoint({
    required this.x,
    required this.y,
  });
}

/// Classe para representar estatísticas de detecção
class MotionDetectionStats {
  final int totalEvents;
  final int eventsToday;
  final double averageConfidence;
  final DateTime? lastEventTime;
  final double detectionRate;
  final double falsePositiveRate;

  const MotionDetectionStats({
    required this.totalEvents,
    required this.eventsToday,
    required this.averageConfidence,
    this.lastEventTime,
    required this.detectionRate,
    required this.falsePositiveRate,
  });
}