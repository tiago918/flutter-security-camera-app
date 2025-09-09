enum RecordingType {
  manual,
  motion,
  scheduled,
  continuous;

  String get displayName {
    switch (this) {
      case RecordingType.manual:
        return 'Manual';
      case RecordingType.motion:
        return 'Detecção de Movimento';
      case RecordingType.scheduled:
        return 'Agendada';
      case RecordingType.continuous:
        return 'Contínua';
    }
  }
}

enum RecordingStatus {
  recording,
  completed,
  failed,
  paused;

  String get displayName {
    switch (this) {
      case RecordingStatus.recording:
        return 'Gravando';
      case RecordingStatus.completed:
        return 'Concluída';
      case RecordingStatus.failed:
        return 'Falhou';
      case RecordingStatus.paused:
        return 'Pausada';
    }
  }
}

enum RecordingQuality {
  low,
  medium,
  high,
  ultra;

  String get displayName {
    switch (this) {
      case RecordingQuality.low:
        return 'Baixa (480p)';
      case RecordingQuality.medium:
        return 'Média (720p)';
      case RecordingQuality.high:
        return 'Alta (1080p)';
      case RecordingQuality.ultra:
        return 'Ultra (4K)';
    }
  }

  String get resolution {
    switch (this) {
      case RecordingQuality.low:
        return '480p';
      case RecordingQuality.medium:
        return '720p';
      case RecordingQuality.high:
        return '1080p';
      case RecordingQuality.ultra:
        return '4K';
    }
  }
}

enum RecordingEventType {
  started,
  stopped,
  paused,
  resumed,
  failed,
  completed;

  String get displayName {
    switch (this) {
      case RecordingEventType.started:
        return 'Iniciada';
      case RecordingEventType.stopped:
        return 'Parada';
      case RecordingEventType.paused:
        return 'Pausada';
      case RecordingEventType.resumed:
        return 'Retomada';
      case RecordingEventType.failed:
        return 'Falhou';
      case RecordingEventType.completed:
        return 'Concluída';
    }
  }
}

class Recording {
  final String id;
  final String cameraId;
  final String fileName;
  final String filePath;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration? duration;
  final RecordingType type;
  final RecordingQuality quality;
  final RecordingStatus status;
  final int fileSize;
  final String? eventId;
  final String? thumbnailPath;
  final bool audioEnabled;
  final Map<String, dynamic>? metadata;

  const Recording({
    required this.id,
    required this.cameraId,
    required this.fileName,
    required this.filePath,
    required this.startTime,
    this.endTime,
    this.duration,
    required this.type,
    required this.quality,
    required this.status,
    this.fileSize = 0,
    this.eventId,
    this.thumbnailPath,
    this.audioEnabled = false,
    this.metadata,
  });

  factory Recording.fromJson(Map<String, dynamic> json) {
    return Recording(
      id: json['id'] as String,
      cameraId: json['cameraId'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      type: RecordingType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RecordingType.manual,
      ),
      quality: RecordingQuality.values.firstWhere(
        (q) => q.name == json['quality'],
        orElse: () => RecordingQuality.medium,
      ),
      status: RecordingStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => RecordingStatus.completed,
      ),
      fileSize: json['fileSize'] as int? ?? 0,
      eventId: json['eventId'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      audioEnabled: json['audioEnabled'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cameraId': cameraId,
      'fileName': fileName,
      'filePath': filePath,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration?.inMilliseconds,
      'type': type.name,
      'quality': quality.name,
      'status': status.name,
      'fileSize': fileSize,
      'eventId': eventId,
      'thumbnailPath': thumbnailPath,
      'audioEnabled': audioEnabled,
      'metadata': metadata,
    };
  }

  Recording copyWith({
    String? id,
    String? cameraId,
    String? fileName,
    String? filePath,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    RecordingType? type,
    RecordingQuality? quality,
    RecordingStatus? status,
    int? fileSize,
    String? eventId,
    String? thumbnailPath,
    bool? audioEnabled,
    Map<String, dynamic>? metadata,
  }) {
    return Recording(
      id: id ?? this.id,
      cameraId: cameraId ?? this.cameraId,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      type: type ?? this.type,
      quality: quality ?? this.quality,
      status: status ?? this.status,
      fileSize: fileSize ?? this.fileSize,
      eventId: eventId ?? this.eventId,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      metadata: metadata ?? this.metadata,
    );
  }

  String get formattedDuration {
    if (duration == null) return '--:--';
    final hours = duration!.inHours;
    final minutes = duration!.inMinutes.remainder(60);
    final seconds = duration!.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String get formattedFileSize {
    if (fileSize == 0) return '0 B';
    
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = fileSize.toDouble();
    var suffixIndex = 0;
    
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    
    return '${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }

  @override
  String toString() {
    return 'Recording(id: $id, camera: $cameraId, type: ${type.name}, status: ${status.name})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Recording &&
        other.id == id &&
        other.cameraId == cameraId;
  }

  @override
  int get hashCode => Object.hash(id, cameraId);
}

class RecordingSchedule {
  final int dayOfWeek; // 1-7 (Monday-Sunday)
  final String startTime; // HH:mm format
  final String endTime; // HH:mm format
  final bool enabled;

  const RecordingSchedule({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.enabled = true,
  });

  factory RecordingSchedule.fromJson(Map<String, dynamic> json) {
    return RecordingSchedule(
      dayOfWeek: json['dayOfWeek'] as int,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'enabled': enabled,
    };
  }

  String get dayName {
    const days = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo'
    ];
    return days[dayOfWeek - 1];
  }
}

class RecordingConfig {
  final bool autoRecordingEnabled;
  final RecordingQuality quality;
  final Duration? maxDuration;
  final int? maxFileSize; // in bytes
  final String storagePath;
  final String fileNamePattern;
  final bool motionTriggered;
  final bool scheduleEnabled;
  final List<RecordingSchedule>? schedule;
  final Duration preRecordDuration;
  final Duration postRecordDuration;
  final bool audioEnabled;
  final bool overwriteOldFiles;
  final int maxStorageGB;

  const RecordingConfig({
    this.autoRecordingEnabled = false,
    this.quality = RecordingQuality.medium,
    this.maxDuration,
    this.maxFileSize,
    required this.storagePath,
    this.fileNamePattern = '{camera}_{date}_{time}',
    this.motionTriggered = false,
    this.scheduleEnabled = false,
    this.schedule,
    this.preRecordDuration = const Duration(seconds: 5),
    this.postRecordDuration = const Duration(seconds: 5),
    this.audioEnabled = false,
    this.overwriteOldFiles = false,
    this.maxStorageGB = 100,
  });

  factory RecordingConfig.fromJson(Map<String, dynamic> json) {
    return RecordingConfig(
      autoRecordingEnabled: json['autoRecordingEnabled'] as bool? ?? false,
      quality: RecordingQuality.values.firstWhere(
        (q) => q.name == json['quality'],
        orElse: () => RecordingQuality.medium,
      ),
      maxDuration: json['maxDuration'] != null
          ? Duration(seconds: json['maxDuration'] as int)
          : null,
      maxFileSize: json['maxFileSize'] as int?,
      storagePath: json['storagePath'] as String,
      fileNamePattern: json['fileNamePattern'] as String? ?? '{camera}_{date}_{time}',
      motionTriggered: json['motionTriggered'] as bool? ?? false,
      scheduleEnabled: json['scheduleEnabled'] as bool? ?? false,
      schedule: json['schedule'] != null
          ? (json['schedule'] as List)
              .map((s) => RecordingSchedule.fromJson(s as Map<String, dynamic>))
              .toList()
          : null,
      preRecordDuration: Duration(
        seconds: json['preRecordDuration'] as int? ?? 5,
      ),
      postRecordDuration: Duration(
        seconds: json['postRecordDuration'] as int? ?? 5,
      ),
      audioEnabled: json['audioEnabled'] as bool? ?? false,
      overwriteOldFiles: json['overwriteOldFiles'] as bool? ?? false,
      maxStorageGB: json['maxStorageGB'] as int? ?? 100,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'autoRecordingEnabled': autoRecordingEnabled,
      'quality': quality.name,
      'maxDuration': maxDuration?.inSeconds,
      'maxFileSize': maxFileSize,
      'storagePath': storagePath,
      'fileNamePattern': fileNamePattern,
      'motionTriggered': motionTriggered,
      'scheduleEnabled': scheduleEnabled,
      'schedule': schedule?.map((s) => s.toJson()).toList(),
      'preRecordDuration': preRecordDuration.inSeconds,
      'postRecordDuration': postRecordDuration.inSeconds,
      'audioEnabled': audioEnabled,
      'overwriteOldFiles': overwriteOldFiles,
      'maxStorageGB': maxStorageGB,
    };
  }
}

class RecordingEvent {
  final RecordingEventType type;
  final Recording recording;
  final DateTime timestamp;
  final String? message;
  final Map<String, dynamic>? data;

  const RecordingEvent({
    required this.type,
    required this.recording,
    required this.timestamp,
    this.message,
    this.data,
  });

  factory RecordingEvent.fromJson(Map<String, dynamic> json) {
    return RecordingEvent(
      type: RecordingEventType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RecordingEventType.completed,
      ),
      recording: Recording.fromJson(json['recording'] as Map<String, dynamic>),
      timestamp: DateTime.parse(json['timestamp'] as String),
      message: json['message'] as String?,
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'recording': recording.toJson(),
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'data': data,
    };
  }
}

class RecordingStats {
  final Recording? activeRecording;
  final int totalRecordings;
  final int totalSizeBytes;
  final Duration totalDuration;
  final DateTime? lastRecordingTime;
  final Map<RecordingType, int> recordingsByType;
  final Map<RecordingQuality, int> recordingsByQuality;

  const RecordingStats({
    this.activeRecording,
    this.totalRecordings = 0,
    this.totalSizeBytes = 0,
    this.totalDuration = Duration.zero,
    this.lastRecordingTime,
    this.recordingsByType = const {},
    this.recordingsByQuality = const {},
  });

  factory RecordingStats.fromJson(Map<String, dynamic> json) {
    return RecordingStats(
      activeRecording: json['activeRecording'] != null
          ? Recording.fromJson(json['activeRecording'] as Map<String, dynamic>)
          : null,
      totalRecordings: json['totalRecordings'] as int? ?? 0,
      totalSizeBytes: json['totalSizeBytes'] as int? ?? 0,
      totalDuration: Duration(
        milliseconds: json['totalDuration'] as int? ?? 0,
      ),
      lastRecordingTime: json['lastRecordingTime'] != null
          ? DateTime.parse(json['lastRecordingTime'] as String)
          : null,
      recordingsByType: Map<RecordingType, int>.from(
        (json['recordingsByType'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(
                  RecordingType.values.firstWhere((t) => t.name == k),
                  v as int,
                )),
      ),
      recordingsByQuality: Map<RecordingQuality, int>.from(
        (json['recordingsByQuality'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(
                  RecordingQuality.values.firstWhere((q) => q.name == k),
                  v as int,
                )),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activeRecording': activeRecording?.toJson(),
      'totalRecordings': totalRecordings,
      'totalSizeBytes': totalSizeBytes,
      'totalDuration': totalDuration.inMilliseconds,
      'lastRecordingTime': lastRecordingTime?.toIso8601String(),
      'recordingsByType': recordingsByType
          .map((k, v) => MapEntry(k.name, v)),
      'recordingsByQuality': recordingsByQuality
          .map((k, v) => MapEntry(k.name, v)),
    };
  }

  String get formattedTotalSize {
    if (totalSizeBytes == 0) return '0 B';
    
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = totalSizeBytes.toDouble();
    var suffixIndex = 0;
    
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    
    return '${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }

  String get formattedTotalDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
}