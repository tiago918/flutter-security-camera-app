import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../models/recording.dart';
import 'camera_service.dart';

class RecordingService {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  final CameraService _cameraService = CameraService();
  final Map<String, List<Recording>> _recordings = {};
  final Map<String, Recording?> _activeRecordings = {};
  final Map<String, Timer?> _recordingTimers = {};
  final Map<String, StreamController<RecordingEvent>> _eventStreams = {};
  final Map<String, RecordingConfig> _configs = {};
  final Map<String, int> _recordingCounters = {};

  /// Configura gravação para uma câmera
  Future<bool> configureRecording(
    String cameraId,
    RecordingConfig config,
  ) async {
    if (!_cameraService.isConnected(cameraId)) {
      print('Câmera $cameraId não está conectada');
      return false;
    }

    try {
      final command = {
        'Command': 'SET_RECORDING_CONFIG',
        'AutoRecordingEnabled': config.autoRecordingEnabled,
        'RecordingQuality': config.quality.name,
        'MaxDuration': config.maxDuration?.inSeconds,
        'MaxFileSize': config.maxFileSize,
        'StoragePath': config.storagePath,
        'FileNamePattern': config.fileNamePattern,
        'MotionTriggered': config.motionTriggered,
        'ScheduleEnabled': config.scheduleEnabled,
        'Schedule': config.schedule?.map((schedule) => {
          'dayOfWeek': schedule.dayOfWeek,
          'startTime': schedule.startTime,
          'endTime': schedule.endTime,
          'enabled': schedule.enabled,
        }).toList(),
        'PreRecordDuration': config.preRecordDuration.inSeconds,
        'PostRecordDuration': config.postRecordDuration.inSeconds,
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        _configs[cameraId] = config;
        _recordingCounters[cameraId] = 0;
        
        // Cria diretório de armazenamento se não existir
        await _ensureStorageDirectory(config.storagePath);
        
        print('Configuração de gravação definida para câmera $cameraId');
        return true;
      } else {
        print('Falha ao configurar gravação: ${response?['Error'] ?? 'Erro desconhecido'}');
        return false;
      }
    } catch (e) {
      print('Erro ao configurar gravação para câmera $cameraId: $e');
      return false;
    }
  }

  /// Inicia gravação manual
  Future<Recording?> startRecording(
    String cameraId, {
    Duration? duration,
    RecordingType type = RecordingType.manual,
    String? eventId,
  }) async {
    if (!_cameraService.isConnected(cameraId)) {
      print('Câmera $cameraId não está conectada');
      return null;
    }

    // Verifica se já está gravando
    if (_activeRecordings[cameraId] != null) {
      print('Câmera $cameraId já está gravando');
      return _activeRecordings[cameraId];
    }

    try {
      final config = _configs[cameraId] ?? _getDefaultConfig();
      final recordingId = _generateRecordingId(cameraId);
      final fileName = _generateFileName(cameraId, type);
      final filePath = '${config.storagePath}/$fileName';

      final command = {
        'Command': 'START_RECORDING',
        'RecordingId': recordingId,
        'FilePath': filePath,
        'Quality': config.quality.name,
        'Duration': duration?.inSeconds ?? config.maxDuration?.inSeconds,
        'AudioEnabled': config.audioEnabled,
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        final recording = Recording(
          id: recordingId,
          cameraId: cameraId,
          fileName: fileName,
          filePath: filePath,
          startTime: DateTime.now(),
          type: type,
          quality: config.quality,
          status: RecordingStatus.recording,
          eventId: eventId,
        );

        _activeRecordings[cameraId] = recording;
        _addRecordingToList(cameraId, recording);
        
        // Configura timer para parar gravação automaticamente
        if (duration != null) {
          _recordingTimers[cameraId] = Timer(duration, () {
            stopRecording(cameraId);
          });
        }
        
        _emitRecordingEvent(cameraId, RecordingEvent(
          type: RecordingEventType.started,
          recording: recording,
          timestamp: DateTime.now(),
        ));
        
        print('Gravação iniciada para câmera $cameraId: $fileName');
        return recording;
      } else {
        print('Falha ao iniciar gravação: ${response?['Error'] ?? 'Erro desconhecido'}');
        return null;
      }
    } catch (e) {
      print('Erro ao iniciar gravação para câmera $cameraId: $e');
      return null;
    }
  }

  /// Para gravação
  Future<bool> stopRecording(String cameraId) async {
    final activeRecording = _activeRecordings[cameraId];
    if (activeRecording == null) {
      print('Nenhuma gravação ativa para câmera $cameraId');
      return false;
    }

    try {
      final command = {
        'Command': 'STOP_RECORDING',
        'RecordingId': activeRecording.id,
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        // Para timer se existir
        _recordingTimers[cameraId]?.cancel();
        _recordingTimers.remove(cameraId);
        
        // Atualiza recording
        final updatedRecording = activeRecording.copyWith(
          endTime: DateTime.now(),
          status: RecordingStatus.completed,
          fileSize: response['FileSize'] ?? 0,
          duration: DateTime.now().difference(activeRecording.startTime),
        );
        
        _updateRecordingInList(cameraId, updatedRecording);
        _activeRecordings.remove(cameraId);
        
        _emitRecordingEvent(cameraId, RecordingEvent(
          type: RecordingEventType.stopped,
          recording: updatedRecording,
          timestamp: DateTime.now(),
        ));
        
        print('Gravação parada para câmera $cameraId');
        return true;
      } else {
        print('Falha ao parar gravação: ${response?['Error'] ?? 'Erro desconhecido'}');
        return false;
      }
    } catch (e) {
      print('Erro ao parar gravação para câmera $cameraId: $e');
      return false;
    }
  }

  /// Inicia gravação por evento de movimento
  Future<Recording?> startMotionRecording(
    String cameraId,
    String motionEventId,
  ) async {
    final config = _configs[cameraId];
    if (config == null || !config.motionTriggered) {
      return null;
    }

    final duration = config.maxDuration ?? const Duration(minutes: 5);
    return await startRecording(
      cameraId,
      duration: duration,
      type: RecordingType.motion,
      eventId: motionEventId,
    );
  }

  /// Inicia gravação agendada
  Future<Recording?> startScheduledRecording(String cameraId) async {
    final config = _configs[cameraId];
    if (config == null || !config.scheduleEnabled) {
      return null;
    }

    return await startRecording(
      cameraId,
      type: RecordingType.scheduled,
    );
  }

  /// Obtém lista de gravações de uma câmera
  List<Recording> getRecordings(String cameraId) {
    return _recordings[cameraId] ?? [];
  }

  /// Obtém gravação ativa
  Recording? getActiveRecording(String cameraId) {
    return _activeRecordings[cameraId];
  }

  /// Verifica se está gravando
  bool isRecording(String cameraId) {
    return _activeRecordings[cameraId] != null;
  }

  /// Obtém gravação por ID
  Recording? getRecordingById(String cameraId, String recordingId) {
    final recordings = _recordings[cameraId] ?? [];
    try {
      return recordings.firstWhere((r) => r.id == recordingId);
    } catch (e) {
      return null;
    }
  }

  /// Remove gravação
  Future<bool> deleteRecording(String cameraId, String recordingId) async {
    final recording = getRecordingById(cameraId, recordingId);
    if (recording == null) {
      print('Gravação $recordingId não encontrada');
      return false;
    }

    try {
      // Remove arquivo físico
      final file = File(recording.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      // Remove da lista
      _recordings[cameraId]?.removeWhere((r) => r.id == recordingId);
      
      _emitRecordingEvent(cameraId, RecordingEvent(
        type: RecordingEventType.deleted,
        recording: recording,
        timestamp: DateTime.now(),
      ));
      
      print('Gravação $recordingId removida');
      return true;
    } catch (e) {
      print('Erro ao remover gravação $recordingId: $e');
      return false;
    }
  }

  /// Remove múltiplas gravações
  Future<int> deleteRecordings(String cameraId, List<String> recordingIds) async {
    int deletedCount = 0;
    
    for (final recordingId in recordingIds) {
      if (await deleteRecording(cameraId, recordingId)) {
        deletedCount++;
      }
    }
    
    return deletedCount;
  }

  /// Remove gravações antigas
  Future<int> cleanupOldRecordings(
    String cameraId, {
    Duration? olderThan,
    int? keepCount,
  }) async {
    final recordings = getRecordings(cameraId);
    if (recordings.isEmpty) return 0;

    List<Recording> toDelete = [];
    
    if (olderThan != null) {
      final cutoffDate = DateTime.now().subtract(olderThan);
      toDelete.addAll(recordings.where((r) => r.startTime.isBefore(cutoffDate)));
    }
    
    if (keepCount != null && recordings.length > keepCount) {
      // Ordena por data (mais recentes primeiro)
      final sortedRecordings = List<Recording>.from(recordings)
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
      
      // Adiciona os mais antigos para remoção
      toDelete.addAll(sortedRecordings.skip(keepCount));
    }
    
    // Remove duplicatas
    toDelete = toDelete.toSet().toList();
    
    final recordingIds = toDelete.map((r) => r.id).toList();
    return await deleteRecordings(cameraId, recordingIds);
  }

  /// Obtém estatísticas de gravação
  RecordingStats getRecordingStats(String cameraId) {
    final recordings = getRecordings(cameraId);
    final activeRecording = getActiveRecording(cameraId);
    
    int totalRecordings = recordings.length;
    int totalSize = recordings.fold(0, (sum, r) => sum + r.fileSize);
    Duration totalDuration = recordings.fold(
      Duration.zero,
      (sum, r) => sum + (r.duration ?? Duration.zero),
    );
    
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final recordingsToday = recordings
        .where((r) => r.startTime.isAfter(todayStart))
        .length;
    
    return RecordingStats(
      totalRecordings: totalRecordings,
      recordingsToday: recordingsToday,
      totalSize: totalSize,
      totalDuration: totalDuration,
      isCurrentlyRecording: activeRecording != null,
      activeRecording: activeRecording,
    );
  }

  /// Obtém stream de eventos de gravação
  Stream<RecordingEvent>? getRecordingEventStream(String cameraId) {
    if (_eventStreams[cameraId] == null) {
      _eventStreams[cameraId] = StreamController<RecordingEvent>.broadcast();
    }
    return _eventStreams[cameraId]?.stream;
  }

  /// Sincroniza gravações com a câmera
  Future<void> syncRecordings(String cameraId) async {
    try {
      final command = {
        'Command': 'GET_RECORDINGS',
        'Since': DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch,
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        final recordingsData = response['Recordings'] as List? ?? [];
        final recordings = recordingsData.map((data) => Recording.fromJson(data)).toList();
        
        _recordings[cameraId] = recordings;
        
        print('${recordings.length} gravações sincronizadas para câmera $cameraId');
      }
    } catch (e) {
      print('Erro ao sincronizar gravações para câmera $cameraId: $e');
    }
  }

  /// Métodos auxiliares
  
  String _generateRecordingId(String cameraId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final counter = (_recordingCounters[cameraId] ?? 0) + 1;
    _recordingCounters[cameraId] = counter;
    return '${cameraId}_${timestamp}_$counter';
  }

  String _generateFileName(String cameraId, RecordingType type) {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final typeStr = type.name.toUpperCase();
    
    return '${cameraId}_${typeStr}_${dateStr}_$timeStr.mp4';
  }

  Future<void> _ensureStorageDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  void _addRecordingToList(String cameraId, Recording recording) {
    if (_recordings[cameraId] == null) {
      _recordings[cameraId] = [];
    }
    _recordings[cameraId]!.add(recording);
  }

  void _updateRecordingInList(String cameraId, Recording updatedRecording) {
    final recordings = _recordings[cameraId];
    if (recordings != null) {
      final index = recordings.indexWhere((r) => r.id == updatedRecording.id);
      if (index != -1) {
        recordings[index] = updatedRecording;
      }
    }
  }

  void _emitRecordingEvent(String cameraId, RecordingEvent event) {
    if (_eventStreams[cameraId] == null) {
      _eventStreams[cameraId] = StreamController<RecordingEvent>.broadcast();
    }
    _eventStreams[cameraId]?.add(event);
  }

  RecordingConfig _getDefaultConfig() {
    return const RecordingConfig(
      autoRecordingEnabled: false,
      quality: RecordingQuality.high,
      storagePath: './recordings',
      fileNamePattern: '{camera}_{type}_{date}_{time}',
      motionTriggered: false,
      scheduleEnabled: false,
      audioEnabled: true,
      preRecordDuration: Duration(seconds: 5),
      postRecordDuration: Duration(seconds: 5),
    );
  }

  /// Dispose do serviço
  void dispose() {
    // Para todas as gravações ativas
    final activeCameras = List<String>.from(_activeRecordings.keys);
    for (final cameraId in activeCameras) {
      stopRecording(cameraId);
    }
    
    // Para todos os timers
    for (final timer in _recordingTimers.values) {
      timer?.cancel();
    }
    _recordingTimers.clear();
    
    // Fecha todos os streams
    for (final stream in _eventStreams.values) {
      stream.close();
    }
    _eventStreams.clear();
    
    _recordings.clear();
    _activeRecordings.clear();
    _configs.clear();
    _recordingCounters.clear();
  }
}

/// Classes auxiliares para gravação

class RecordingConfig {
  final bool autoRecordingEnabled;
  final RecordingQuality quality;
  final Duration? maxDuration;
  final int? maxFileSize; // em bytes
  final String storagePath;
  final String fileNamePattern;
  final bool motionTriggered;
  final bool scheduleEnabled;
  final List<RecordingSchedule>? schedule;
  final bool audioEnabled;
  final Duration preRecordDuration;
  final Duration postRecordDuration;

  const RecordingConfig({
    required this.autoRecordingEnabled,
    required this.quality,
    this.maxDuration,
    this.maxFileSize,
    required this.storagePath,
    required this.fileNamePattern,
    required this.motionTriggered,
    required this.scheduleEnabled,
    this.schedule,
    this.audioEnabled = true,
    this.preRecordDuration = const Duration(seconds: 5),
    this.postRecordDuration = const Duration(seconds: 5),
  });
}

class RecordingSchedule {
  final int dayOfWeek; // 0-6 (domingo-sábado)
  final String startTime; // HH:mm
  final String endTime; // HH:mm
  final bool enabled;

  const RecordingSchedule({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.enabled = true,
  });
}

class RecordingStats {
  final int totalRecordings;
  final int recordingsToday;
  final int totalSize;
  final Duration totalDuration;
  final bool isCurrentlyRecording;
  final Recording? activeRecording;

  const RecordingStats({
    required this.totalRecordings,
    required this.recordingsToday,
    required this.totalSize,
    required this.totalDuration,
    required this.isCurrentlyRecording,
    this.activeRecording,
  });
}

enum RecordingEventType {
  started,
  stopped,
  paused,
  resumed,
  error,
  deleted,
}

class RecordingEvent {
  final RecordingEventType type;
  final Recording recording;
  final DateTime timestamp;
  final String? error;

  const RecordingEvent({
    required this.type,
    required this.recording,
    required this.timestamp,
    this.error,
  });
}