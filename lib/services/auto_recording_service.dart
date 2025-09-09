import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

import 'motion_detection_service.dart';
import 'recording_service.dart';

// Import MotionEvent from motion_detection_service
export 'motion_detection_service.dart' show MotionEvent;

/// Serviço para gravação automática baseada em detecção de movimento
class AutoRecordingService {
  static final AutoRecordingService _instance = AutoRecordingService._internal();
  factory AutoRecordingService() => _instance;
  AutoRecordingService._internal();

  final MotionDetectionService _motionService = MotionDetectionService();
  final RecordingService _recordingService = RecordingService();
  
  final Map<String, StreamSubscription?> _motionSubscriptions = {};
  final Map<String, Timer> _recordingTimers = {};
  final Map<String, AutoRecordingSettings> _settings = {};
  
  final StreamController<AutoRecordingEvent> _eventController = StreamController<AutoRecordingEvent>.broadcast();
  Stream<AutoRecordingEvent> get eventStream => _eventController.stream;

  /// Inicia gravação automática para uma câmera
  Future<void> startAutoRecording(CameraModel camera) async {
    if (_motionSubscriptions.containsKey(camera.id)) {
      print('Auto Recording: Already active for camera ${camera.name}');
      return;
    }

    final settings = await getAutoRecordingSettings(camera.id);
    if (!settings.enabled) {
      print('Auto Recording: Disabled for camera ${camera.name}');
      return;
    }

    _settings[camera.id] = settings;
    
    // Integra com MotionDetectionService para detectar movimento real
    await _motionService.startMotionDetection(camera);
    
    // Escuta eventos de movimento
    _motionSubscriptions[camera.id] = _motionService.motionStream
        ?.where((event) => event.cameraId == camera.id)
        ?.listen((motionEvent) => _handleMotionDetected(camera, motionEvent, settings));
    
    print('Auto Recording: Started for camera ${camera.name}');
    
    _eventController.add(AutoRecordingEvent(
      type: AutoRecordingEventType.started,
      cameraId: camera.id,
      cameraName: camera.name,
      timestamp: DateTime.now(),
      message: 'Gravação automática iniciada',
    ));
  }

  /// Para gravação automática para uma câmera
  Future<void> stopAutoRecording(String cameraId) async {
    _motionSubscriptions[cameraId]?.cancel();
    _motionSubscriptions.remove(cameraId);
    
    _recordingTimers[cameraId]?.cancel();
    _recordingTimers.remove(cameraId);
    
    // Para a detecção de movimento real
    _motionService.stopMotionDetection(cameraId);
    _settings.remove(cameraId);
    
    print('Auto Recording: Stopped for camera ID $cameraId');
  }

  /// Manipula evento de movimento detectado
  Future<void> _handleMotionDetected(CameraModel camera, MotionEvent motionEvent, AutoRecordingSettings settings) async {
    print('Auto Recording: Motion detected on ${camera.name}, starting recording...');
    
    // Cancelar timer anterior se existir
    _recordingTimers[camera.id]?.cancel();
    
    try {
      // Verifica se precisa fazer limpeza cíclica antes de gravar
      if (settings.cyclicRecording) {
        await _performCyclicCleanup(camera.id);
      }
      
      // Iniciar gravação
      final recording = await _recordingService.startRecording(
        camera.id.toString(),
        duration: Duration(seconds: settings.recordingDuration),
      );
      
      if (recording != null) {
        _eventController.add(AutoRecordingEvent(
          type: AutoRecordingEventType.recordingStarted,
          cameraId: camera.id,
          cameraName: camera.name,
          timestamp: DateTime.now(),
          message: 'Gravação iniciada por movimento (${motionEvent.confidence}% confiança)',
          motionEvent: motionEvent,
        ));
        
        // Configurar timer para parar gravação
        _recordingTimers[camera.id] = Timer(
          Duration(seconds: settings.recordingDuration),
          () => _stopRecordingAfterMotion(camera),
        );
      } else {
        _eventController.add(AutoRecordingEvent(
          type: AutoRecordingEventType.error,
          cameraId: camera.id,
          cameraName: camera.name,
          timestamp: DateTime.now(),
          message: 'Falha ao iniciar gravação automática',
        ));
      }
    } catch (e) {
      print('Auto Recording Error: Failed to start recording for ${camera.name}: $e');
      _eventController.add(AutoRecordingEvent(
        type: AutoRecordingEventType.error,
        cameraId: camera.id,
        cameraName: camera.name,
        timestamp: DateTime.now(),
        message: 'Erro na gravação automática: $e',
      ));
    }
  }

  /// Para gravação após movimento
  Future<void> _stopRecordingAfterMotion(CameraModel camera) async {
    try {
      final success = await _recordingService.stopRecording(camera.id.toString());
      
      if (success) {
        _eventController.add(AutoRecordingEvent(
          type: AutoRecordingEventType.recordingStopped,
          cameraId: camera.id,
          cameraName: camera.name,
          timestamp: DateTime.now(),
          message: 'Gravação finalizada automaticamente',
        ));
        
        // Verificar se precisa fazer limpeza de arquivos antigos
        await _performCyclicCleanup(camera.id);
      }
    } catch (e) {
      print('Auto Recording Error: Failed to stop recording for ${camera.name}: $e');
    }
  }

  /// Realiza limpeza cíclica de gravações antigas
  Future<void> _performCyclicCleanup(String cameraId) async {
    final settings = _settings[cameraId];
    if (settings == null || !settings.cyclicRecording) return;
    
    try {
      final recordingsDir = await _getRecordingsDirectory();
      final files = await recordingsDir.list().where((entity) => 
        entity is File && entity.path.contains('camera_${cameraId}_')
      ).cast<File>().toList();
      
      // Ordenar por data de modificação (mais antigos primeiro)
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      
      // Verificar espaço disponível
      final totalSize = files.fold<int>(0, (sum, file) => sum + file.lengthSync());
      final maxSizeBytes = settings.maxStorageMB * 1024 * 1024;
      
      if (totalSize > maxSizeBytes) {
        final filesToDelete = <File>[];
        int sizeToDelete = totalSize - maxSizeBytes;
        
        for (final file in files) {
          if (sizeToDelete <= 0) break;
          filesToDelete.add(file);
          sizeToDelete -= file.lengthSync();
        }
        
        // Deletar arquivos mais antigos
        for (final file in filesToDelete) {
          await file.delete();
          print('Auto Recording: Deleted old recording: ${file.path}');
        }
        
        _eventController.add(AutoRecordingEvent(
          type: AutoRecordingEventType.cyclicCleanup,
          cameraId: cameraId,
          cameraName: 'Camera $cameraId',
          timestamp: DateTime.now(),
          message: 'Limpeza cíclica: ${filesToDelete.length} arquivos removidos',
        ));
      }
    } catch (e) {
      print('Auto Recording Error: Cyclic cleanup failed for camera $cameraId: $e');
    }
  }

  /// Obtém diretório de gravações
  Future<Directory> _getRecordingsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${appDir.path}/camera_recordings');
    
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    
    return recordingsDir;
  }

  /// Obtém configurações de gravação automática
  Future<AutoRecordingSettings> getAutoRecordingSettings(String cameraId) async {
    final prefs = await SharedPreferences.getInstance();
    
    return AutoRecordingSettings(
      enabled: prefs.getBool('auto_recording_enabled_$cameraId') ?? false,
      recordingDuration: prefs.getInt('auto_recording_duration_$cameraId') ?? 30,
      preRecordingSeconds: prefs.getInt('auto_pre_recording_$cameraId') ?? 5,
      postRecordingSeconds: prefs.getInt('auto_post_recording_$cameraId') ?? 10,
      cyclicRecording: prefs.getBool('auto_cyclic_recording_$cameraId') ?? true,
      maxStorageMB: prefs.getInt('auto_max_storage_mb_$cameraId') ?? 1024, // 1GB padrão
      recordingFormat: prefs.getString('auto_recording_format_$cameraId') ?? 'mp4',
      recordingQuality: prefs.getString('auto_recording_quality_$cameraId') ?? 'medium',
      storageLocation: prefs.getString('auto_storage_location_$cameraId') ?? 'internal',
    );
  }

  /// Salva configurações de gravação automática
  Future<void> saveAutoRecordingSettings(String cameraId, AutoRecordingSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool('auto_recording_enabled_$cameraId', settings.enabled);
    await prefs.setInt('auto_recording_duration_$cameraId', settings.recordingDuration);
    await prefs.setInt('auto_pre_recording_$cameraId', settings.preRecordingSeconds);
    await prefs.setInt('auto_post_recording_$cameraId', settings.postRecordingSeconds);
    await prefs.setBool('auto_cyclic_recording_$cameraId', settings.cyclicRecording);
    await prefs.setInt('auto_max_storage_mb_$cameraId', settings.maxStorageMB);
    await prefs.setString('auto_recording_format_$cameraId', settings.recordingFormat);
    await prefs.setString('auto_recording_quality_$cameraId', settings.recordingQuality);
    await prefs.setString('auto_storage_location_$cameraId', settings.storageLocation);
    
    _settings[cameraId] = settings;
    print('Auto Recording: Settings saved for camera $cameraId');
  }

  /// Verifica se gravação automática está ativa
  bool isAutoRecordingActive(String cameraId) {
    return _motionSubscriptions.containsKey(cameraId);
  }

  /// Obtém estatísticas de gravação
  Future<AutoRecordingStats> getRecordingStats(String cameraId) async {
    try {
      final recordingsDir = await _getRecordingsDirectory();
      final files = await recordingsDir.list().where((entity) => 
        entity is File && entity.path.contains('camera_${cameraId}_')
      ).cast<File>().toList();
      
      final totalSize = files.fold<int>(0, (sum, file) => sum + file.lengthSync());
      final totalCount = files.length;
      
      DateTime? oldestRecording;
      DateTime? newestRecording;
      
      if (files.isNotEmpty) {
        files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        oldestRecording = files.first.lastModifiedSync();
        newestRecording = files.last.lastModifiedSync();
      }
      
      return AutoRecordingStats(
        totalRecordings: totalCount,
        totalSizeMB: (totalSize / (1024 * 1024)).round(),
        oldestRecording: oldestRecording,
        newestRecording: newestRecording,
      );
    } catch (e) {
      print('Auto Recording Error: Failed to get stats for camera $cameraId: $e');
      return const AutoRecordingStats(
        totalRecordings: 0,
        totalSizeMB: 0,
        oldestRecording: null,
        newestRecording: null,
      );
    }
  }

  /// Dispose resources
  void dispose() {
    for (final subscription in _motionSubscriptions.values) {
      subscription?.cancel();
    }
    _motionSubscriptions.clear();
    
    for (final timer in _recordingTimers.values) {
      timer.cancel();
    }
    _recordingTimers.clear();
    
    _settings.clear();
    _eventController.close();
  }
}

/// Configurações de gravação automática
class AutoRecordingSettings {
  final bool enabled;
  final int recordingDuration; // segundos
  final int preRecordingSeconds; // segundos antes do movimento
  final int postRecordingSeconds; // segundos após o movimento
  final bool cyclicRecording; // substituir gravações antigas
  final int maxStorageMB; // tamanho máximo em MB
  final String recordingFormat; // mp4, avi, etc.
  final String recordingQuality; // low, medium, high
  final String storageLocation; // internal, sdcard

  const AutoRecordingSettings({
    required this.enabled,
    required this.recordingDuration,
    required this.preRecordingSeconds,
    required this.postRecordingSeconds,
    required this.cyclicRecording,
    required this.maxStorageMB,
    required this.recordingFormat,
    required this.recordingQuality,
    required this.storageLocation,
  });

  AutoRecordingSettings copyWith({
    bool? enabled,
    int? recordingDuration,
    int? preRecordingSeconds,
    int? postRecordingSeconds,
    bool? cyclicRecording,
    int? maxStorageMB,
    String? recordingFormat,
    String? recordingQuality,
    String? storageLocation,
  }) {
    return AutoRecordingSettings(
      enabled: enabled ?? this.enabled,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      preRecordingSeconds: preRecordingSeconds ?? this.preRecordingSeconds,
      postRecordingSeconds: postRecordingSeconds ?? this.postRecordingSeconds,
      cyclicRecording: cyclicRecording ?? this.cyclicRecording,
      maxStorageMB: maxStorageMB ?? this.maxStorageMB,
      recordingFormat: recordingFormat ?? this.recordingFormat,
      recordingQuality: recordingQuality ?? this.recordingQuality,
      storageLocation: storageLocation ?? this.storageLocation,
    );
  }
}

/// Evento de gravação automática
class AutoRecordingEvent {
  final AutoRecordingEventType type;
  final String cameraId;
  final String cameraName;
  final DateTime timestamp;
  final String message;
  final MotionEvent? motionEvent;

  const AutoRecordingEvent({
    required this.type,
    required this.cameraId,
    required this.cameraName,
    required this.timestamp,
    required this.message,
    this.motionEvent,
  });
}

/// Tipos de eventos de gravação automática
enum AutoRecordingEventType {
  started,
  stopped,
  recordingStarted,
  recordingStopped,
  cyclicCleanup,
  error,
}

/// Estatísticas de gravação
class AutoRecordingStats {
  final int totalRecordings;
  final int totalSizeMB;
  final DateTime? oldestRecording;
  final DateTime? newestRecording;

  const AutoRecordingStats({
    required this.totalRecordings,
    required this.totalSizeMB,
    required this.oldestRecording,
    required this.newestRecording,
  });
}