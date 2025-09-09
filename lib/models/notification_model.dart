// Enums para tipos e prioridades de notificação
enum NotificationType {
  motion,
  recording,
  connection,
  system,
  alert,
  info,
}

enum NotificationPriority {
  low,
  medium,
  high,
  critical,
}

// Extensões para facilitar o uso dos enums
extension NotificationTypeExtension on NotificationType {
  String get displayName {
    switch (this) {
      case NotificationType.motion:
        return 'Movimento';
      case NotificationType.recording:
        return 'Gravação';
      case NotificationType.connection:
        return 'Conexão';
      case NotificationType.system:
        return 'Sistema';
      case NotificationType.alert:
        return 'Alerta';
      case NotificationType.info:
        return 'Informação';
    }
  }

  String get iconName {
    switch (this) {
      case NotificationType.motion:
        return 'motion_photos_on';
      case NotificationType.recording:
        return 'videocam';
      case NotificationType.connection:
        return 'wifi';
      case NotificationType.system:
        return 'settings';
      case NotificationType.alert:
        return 'warning';
      case NotificationType.info:
        return 'info';
    }
  }
}

extension NotificationPriorityExtension on NotificationPriority {
  String get displayName {
    switch (this) {
      case NotificationPriority.low:
        return 'Baixa';
      case NotificationPriority.medium:
        return 'Média';
      case NotificationPriority.high:
        return 'Alta';
      case NotificationPriority.critical:
        return 'Crítica';
    }
  }

  int get level {
    switch (this) {
      case NotificationPriority.low:
        return 1;
      case NotificationPriority.medium:
        return 2;
      case NotificationPriority.high:
        return 3;
      case NotificationPriority.critical:
        return 4;
    }
  }
}

// Classe principal de notificação
class CameraNotification {
  final String id;
  final NotificationType type;
  final NotificationPriority priority;
  final DateTime timestamp;
  final String title;
  final String message;
  final String? cameraId;
  final String? cameraName;
  final bool isRead;
  final Map<String, dynamic>? metadata;

  const CameraNotification({
    required this.id,
    required this.type,
    required this.priority,
    required this.timestamp,
    required this.title,
    required this.message,
    this.cameraId,
    this.cameraName,
    this.isRead = false,
    this.metadata,
  });

  // Factory constructor para criar a partir de JSON
  factory CameraNotification.fromJson(Map<String, dynamic> json) {
    return CameraNotification(
      id: json['id'] as String,
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NotificationType.info,
      ),
      priority: NotificationPriority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => NotificationPriority.medium,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      title: json['title'] as String,
      message: json['message'] as String,
      cameraId: json['cameraId'] as String?,
      cameraName: json['cameraName'] as String?,
      isRead: json['isRead'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  // Converter para JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'priority': priority.name,
      'timestamp': timestamp.toIso8601String(),
      'title': title,
      'message': message,
      'cameraId': cameraId,
      'cameraName': cameraName,
      'isRead': isRead,
      'metadata': metadata,
    };
  }

  // Método copyWith para criar cópias modificadas
  CameraNotification copyWith({
    String? id,
    NotificationType? type,
    NotificationPriority? priority,
    DateTime? timestamp,
    String? title,
    String? message,
    String? cameraId,
    String? cameraName,
    bool? isRead,
    Map<String, dynamic>? metadata,
  }) {
    return CameraNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      timestamp: timestamp ?? this.timestamp,
      title: title ?? this.title,
      message: message ?? this.message,
      cameraId: cameraId ?? this.cameraId,
      cameraName: cameraName ?? this.cameraName,
      isRead: isRead ?? this.isRead,
      metadata: metadata ?? this.metadata,
    );
  }

  // Factory constructors para diferentes tipos de notificação
  static CameraNotification motionDetected({
    required String cameraId,
    required String cameraName,
    String? details,
    Map<String, dynamic>? metadata,
  }) {
    return CameraNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.motion,
      priority: NotificationPriority.high,
      timestamp: DateTime.now(),
      title: 'Movimento Detectado',
      message: 'Movimento detectado na câmera $cameraName${details != null ? ': $details' : ''}',
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata,
    );
  }

  static CameraNotification connectionLost({
    required String cameraId,
    required String cameraName,
    String? reason,
    Map<String, dynamic>? metadata,
  }) {
    return CameraNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.connection,
      priority: NotificationPriority.critical,
      timestamp: DateTime.now(),
      title: 'Conexão Perdida',
      message: 'Conexão perdida com a câmera $cameraName${reason != null ? ': $reason' : ''}',
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata,
    );
  }

  static CameraNotification connectionRestored({
    required String cameraId,
    required String cameraName,
    Map<String, dynamic>? metadata,
  }) {
    return CameraNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.connection,
      priority: NotificationPriority.medium,
      timestamp: DateTime.now(),
      title: 'Conexão Restaurada',
      message: 'Conexão restaurada com a câmera $cameraName',
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata,
    );
  }

  static CameraNotification recordingStarted({
    required String cameraId,
    required String cameraName,
    String? fileName,
    Map<String, dynamic>? metadata,
  }) {
    return CameraNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.recording,
      priority: NotificationPriority.low,
      timestamp: DateTime.now(),
      title: 'Gravação Iniciada',
      message: 'Gravação iniciada na câmera $cameraName${fileName != null ? ': $fileName' : ''}',
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata,
    );
  }

  static CameraNotification recordingStopped({
    required String cameraId,
    required String cameraName,
    String? fileName,
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    return CameraNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.recording,
      priority: NotificationPriority.low,
      timestamp: DateTime.now(),
      title: 'Gravação Finalizada',
      message: 'Gravação finalizada na câmera $cameraName${fileName != null ? ': $fileName' : ''}${duration != null ? ' (${duration.inMinutes}min)' : ''}',
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata,
    );
  }

  static CameraNotification storageWarning({
    required String cameraId,
    required String cameraName,
    String? message,
    Map<String, dynamic>? metadata,
  }) {
    return CameraNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.system,
      priority: NotificationPriority.high,
      timestamp: DateTime.now(),
      title: 'Aviso de Armazenamento',
      message: message ?? 'Aviso de armazenamento para a câmera $cameraName',
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata,
    );
  }

  static CameraNotification systemError({
    required String cameraId,
    required String cameraName,
    required String error,
    Map<String, dynamic>? metadata,
  }) {
    return CameraNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.system,
      priority: NotificationPriority.critical,
      timestamp: DateTime.now(),
      title: 'Erro do Sistema',
      message: error,
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata,
    );
  }

  @override
  String toString() {
    return 'CameraNotification(id: $id, type: $type, priority: $priority, title: $title)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CameraNotification && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}