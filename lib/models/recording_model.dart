enum RecordingType {
  manual,
  scheduled,
  motionTriggered,
  audioTriggered,
  continuous,
  alarm;

  String get displayName {
    switch (this) {
      case RecordingType.manual:
        return 'Manual';
      case RecordingType.scheduled:
        return 'Agendada';
      case RecordingType.motionTriggered:
        return 'Por Movimento';
      case RecordingType.audioTriggered:
        return 'Por Áudio';
      case RecordingType.continuous:
        return 'Contínua';
      case RecordingType.alarm:
        return 'Por Alarme';
    }
  }

  String get description {
    switch (this) {
      case RecordingType.manual:
        return 'Gravação iniciada manualmente pelo usuário';
      case RecordingType.scheduled:
        return 'Gravação programada por horário';
      case RecordingType.motionTriggered:
        return 'Gravação ativada por detecção de movimento';
      case RecordingType.audioTriggered:
        return 'Gravação ativada por detecção de áudio';
      case RecordingType.continuous:
        return 'Gravação contínua 24/7';
      case RecordingType.alarm:
        return 'Gravação ativada por alarme do sistema';
    }
  }
}

enum RecordingStatus {
  recording,
  completed,
  failed,
  processing,
  archived;

  String get displayName {
    switch (this) {
      case RecordingStatus.recording:
        return 'Gravando';
      case RecordingStatus.completed:
        return 'Concluída';
      case RecordingStatus.failed:
        return 'Falhou';
      case RecordingStatus.processing:
        return 'Processando';
      case RecordingStatus.archived:
        return 'Arquivada';
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
        return '640x480';
      case RecordingQuality.medium:
        return '1280x720';
      case RecordingQuality.high:
        return '1920x1080';
      case RecordingQuality.ultra:
        return '3840x2160';
    }
  }
}

class Recording {
  final String id;
  final String cameraId;
  final String cameraName;
  final String fileName;
  final String filePath;
  final RecordingType type;
  final RecordingStatus status;
  final RecordingQuality quality;
  final DateTime startTime;
  final DateTime? endTime;
  final int? duration; // em segundos
  final int? fileSize; // em bytes
  final String? thumbnailPath;
  final bool hasAudio;
  final Map<String, dynamic>? metadata;
  final List<String>? tags;
  final String? description;

  Recording({
    required this.id,
    required this.cameraId,
    required this.cameraName,
    required this.fileName,
    required this.filePath,
    required this.type,
    required this.status,
    required this.quality,
    required this.startTime,
    this.endTime,
    this.duration,
    this.fileSize,
    this.thumbnailPath,
    this.hasAudio = false,
    this.metadata,
    this.tags,
    this.description,
  });

  factory Recording.fromJson(Map<String, dynamic> json) {
    return Recording(
      id: json['id'] as String,
      cameraId: json['cameraId'] as String,
      cameraName: json['cameraName'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      type: RecordingType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RecordingType.manual,
      ),
      status: RecordingStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => RecordingStatus.completed,
      ),
      quality: RecordingQuality.values.firstWhere(
        (q) => q.name == json['quality'],
        orElse: () => RecordingQuality.medium,
      ),
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      duration: json['duration'] as int?,
      fileSize: json['fileSize'] as int?,
      thumbnailPath: json['thumbnailPath'] as String?,
      hasAudio: json['hasAudio'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : null,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cameraId': cameraId,
      'cameraName': cameraName,
      'fileName': fileName,
      'filePath': filePath,
      'type': type.name,
      'status': status.name,
      'quality': quality.name,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration,
      'fileSize': fileSize,
      'thumbnailPath': thumbnailPath,
      'hasAudio': hasAudio,
      'metadata': metadata,
      'tags': tags,
      'description': description,
    };
  }

  /// Duração formatada como string (HH:MM:SS)
  String get formattedDuration {
    if (duration == null) return '--:--:--';
    
    final hours = duration! ~/ 3600;
    final minutes = (duration! % 3600) ~/ 60;
    final seconds = duration! % 60;
    
    return '${hours.toString().padLeft(2, '0')}:'
           '${minutes.toString().padLeft(2, '0')}:'
           '${seconds.toString().padLeft(2, '0')}';
  }

  /// Tamanho do arquivo formatado
  String get formattedFileSize {
    if (fileSize == null) return 'Desconhecido';
    
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = fileSize!.toDouble();
    int unitIndex = 0;
    
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  /// Data formatada para exibição
  String get formattedDate {
    return '${startTime.day.toString().padLeft(2, '0')}/'
           '${startTime.month.toString().padLeft(2, '0')}/'
           '${startTime.year}';
  }

  /// Hora formatada para exibição
  String get formattedTime {
    return '${startTime.hour.toString().padLeft(2, '0')}:'
           '${startTime.minute.toString().padLeft(2, '0')}';
  }

  /// Verifica se a gravação está em andamento
  bool get isRecording => status == RecordingStatus.recording;

  /// Verifica se a gravação foi concluída
  bool get isCompleted => status == RecordingStatus.completed;

  /// Verifica se a gravação falhou
  bool get hasFailed => status == RecordingStatus.failed;

  /// Cria uma nova gravação
  static Recording create({
    required String cameraId,
    required String cameraName,
    required RecordingType type,
    required RecordingQuality quality,
    String? description,
    bool hasAudio = false,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    final now = DateTime.now();
    final id = '${cameraId}_${now.millisecondsSinceEpoch}';
    final fileName = 'recording_${id}.mp4';
    final filePath = '/recordings/$cameraId/$fileName';

    return Recording(
      id: id,
      cameraId: cameraId,
      cameraName: cameraName,
      fileName: fileName,
      filePath: filePath,
      type: type,
      status: RecordingStatus.recording,
      quality: quality,
      startTime: now,
      hasAudio: hasAudio,
      description: description,
      tags: tags,
      metadata: metadata,
    );
  }

  /// Finaliza a gravação
  Recording complete({
    DateTime? endTime,
    int? fileSize,
    String? thumbnailPath,
  }) {
    final actualEndTime = endTime ?? DateTime.now();
    final calculatedDuration = actualEndTime.difference(startTime).inSeconds;

    return copyWith(
      status: RecordingStatus.completed,
      endTime: actualEndTime,
      duration: calculatedDuration,
      fileSize: fileSize,
      thumbnailPath: thumbnailPath,
    );
  }

  /// Marca a gravação como falhou
  Recording markAsFailed() {
    return copyWith(
      status: RecordingStatus.failed,
      endTime: DateTime.now(),
    );
  }

  /// Arquiva a gravação
  Recording archive() {
    return copyWith(status: RecordingStatus.archived);
  }

  Recording copyWith({
    String? id,
    String? cameraId,
    String? cameraName,
    String? fileName,
    String? filePath,
    RecordingType? type,
    RecordingStatus? status,
    RecordingQuality? quality,
    DateTime? startTime,
    DateTime? endTime,
    int? duration,
    int? fileSize,
    String? thumbnailPath,
    bool? hasAudio,
    Map<String, dynamic>? metadata,
    List<String>? tags,
    String? description,
  }) {
    return Recording(
      id: id ?? this.id,
      cameraId: cameraId ?? this.cameraId,
      cameraName: cameraName ?? this.cameraName,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      type: type ?? this.type,
      status: status ?? this.status,
      quality: quality ?? this.quality,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      hasAudio: hasAudio ?? this.hasAudio,
      metadata: metadata ?? this.metadata,
      tags: tags ?? this.tags,
      description: description ?? this.description,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Recording && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Recording(id: $id, camera: $cameraName, type: ${type.name}, status: ${status.name})';
  }
}