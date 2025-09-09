enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical;

  String get displayName {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARNING';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.critical:
        return 'CRITICAL';
    }
  }

  int get priority {
    switch (this) {
      case LogLevel.debug:
        return 0;
      case LogLevel.info:
        return 1;
      case LogLevel.warning:
        return 2;
      case LogLevel.error:
        return 3;
      case LogLevel.critical:
        return 4;
    }
  }
}

class ConnectionLog {
  final String id;
  final String cameraId;
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? details;
  final Map<String, dynamic>? metadata;
  final String? stackTrace;
  final Duration? duration;
  final String? url;
  final int? responseCode;

  const ConnectionLog({
    required this.id,
    required this.cameraId,
    required this.timestamp,
    required this.level,
    required this.message,
    this.details,
    this.metadata,
    this.stackTrace,
    this.duration,
    this.url,
    this.responseCode,
  });

  factory ConnectionLog.fromJson(Map<String, dynamic> json) {
    return ConnectionLog(
      id: json['id'] as String,
      cameraId: json['cameraId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      level: LogLevel.values.firstWhere(
        (e) => e.name == json['level'],
        orElse: () => LogLevel.info,
      ),
      message: json['message'] as String,
      details: json['details'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      stackTrace: json['stackTrace'] as String?,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      url: json['url'] as String?,
      responseCode: json['responseCode'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cameraId': cameraId,
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'message': message,
      'details': details,
      'metadata': metadata,
      'stackTrace': stackTrace,
      'duration': duration?.inMilliseconds,
      'url': url,
      'responseCode': responseCode,
    };
  }

  ConnectionLog copyWith({
    String? id,
    String? cameraId,
    DateTime? timestamp,
    LogLevel? level,
    String? message,
    String? details,
    Map<String, dynamic>? metadata,
    String? stackTrace,
    Duration? duration,
    String? url,
    int? responseCode,
  }) {
    return ConnectionLog(
      id: id ?? this.id,
      cameraId: cameraId ?? this.cameraId,
      timestamp: timestamp ?? this.timestamp,
      level: level ?? this.level,
      message: message ?? this.message,
      details: details ?? this.details,
      metadata: metadata ?? this.metadata,
      stackTrace: stackTrace ?? this.stackTrace,
      duration: duration ?? this.duration,
      url: url ?? this.url,
      responseCode: responseCode ?? this.responseCode,
    );
  }

  bool get isError => level == LogLevel.error || level == LogLevel.critical;
  bool get isWarning => level == LogLevel.warning;
  bool get isInfo => level == LogLevel.info;
  bool get isDebug => level == LogLevel.debug;

  String get formattedMessage {
    final buffer = StringBuffer();
    buffer.write('[${level.displayName}] ');
    buffer.write('${timestamp.toIso8601String()} ');
    buffer.write('[$cameraId] ');
    buffer.write(message);
    
    if (details != null) {
      buffer.write(' - $details');
    }
    
    if (duration != null) {
      buffer.write(' (${duration!.inMilliseconds}ms)');
    }
    
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectionLog && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ConnectionLog(id: $id, level: $level, message: $message, timestamp: $timestamp)';
  }
}

// Factory methods para criar logs específicos
class ConnectionLogFactory {
  static String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        '_' +
        (1000 + (DateTime.now().microsecond % 9000)).toString();
  }

  static ConnectionLog debug(String cameraId, String message, {String? details, Map<String, dynamic>? metadata}) {
    return ConnectionLog(
      id: _generateId(),
      cameraId: cameraId,
      timestamp: DateTime.now(),
      level: LogLevel.debug,
      message: message,
      details: details,
      metadata: metadata,
    );
  }

  static ConnectionLog info(String cameraId, String message, {String? details, Map<String, dynamic>? metadata}) {
    return ConnectionLog(
      id: _generateId(),
      cameraId: cameraId,
      timestamp: DateTime.now(),
      level: LogLevel.info,
      message: message,
      details: details,
      metadata: metadata,
    );
  }

  static ConnectionLog warning(String cameraId, String message, {String? details, Map<String, dynamic>? metadata}) {
    return ConnectionLog(
      id: _generateId(),
      cameraId: cameraId,
      timestamp: DateTime.now(),
      level: LogLevel.warning,
      message: message,
      details: details,
      metadata: metadata,
    );
  }

  static ConnectionLog error(String cameraId, String message, {String? details, String? stackTrace, Map<String, dynamic>? metadata}) {
    return ConnectionLog(
      id: _generateId(),
      cameraId: cameraId,
      timestamp: DateTime.now(),
      level: LogLevel.error,
      message: message,
      details: details,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  static ConnectionLog critical(String cameraId, String message, {String? details, String? stackTrace, Map<String, dynamic>? metadata}) {
    return ConnectionLog(
      id: _generateId(),
      cameraId: cameraId,
      timestamp: DateTime.now(),
      level: LogLevel.critical,
      message: message,
      details: details,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  static ConnectionLog connection(String cameraId, String url, Duration duration, {int? responseCode, String? details}) {
    return ConnectionLog(
      id: _generateId(),
      cameraId: cameraId,
      timestamp: DateTime.now(),
      level: responseCode != null && responseCode >= 200 && responseCode < 300 ? LogLevel.info : LogLevel.error,
      message: 'Connection attempt',
      details: details,
      url: url,
      duration: duration,
      responseCode: responseCode,
    );
  }
}