import 'package:flutter/foundation.dart';
import 'stream_config.dart';
import 'camera_status.dart';

enum CameraType {
  ip,
  usb,
  rtsp,
  onvif;

  String get displayName {
    switch (this) {
      case CameraType.ip:
        return 'Câmera IP';
      case CameraType.usb:
        return 'Câmera USB';
      case CameraType.rtsp:
        return 'RTSP Stream';
      case CameraType.onvif:
        return 'ONVIF';
    }
  }
}

class CameraSettings {
  final bool motionDetectionEnabled;
  final bool nightModeEnabled;
  final bool audioEnabled;
  final double brightness;
  final double contrast;
  final double saturation;
  final String? username;
  final String? password;
  final Map<String, dynamic> customSettings;

  const CameraSettings({
    this.motionDetectionEnabled = false,
    this.nightModeEnabled = false,
    this.audioEnabled = false,
    this.brightness = 0.5,
    this.contrast = 0.5,
    this.saturation = 0.5,
    this.username,
    this.password,
    this.customSettings = const {},
  });

  factory CameraSettings.fromJson(Map<String, dynamic> json) {
    return CameraSettings(
      motionDetectionEnabled: json['motionDetectionEnabled'] as bool? ?? false,
      nightModeEnabled: json['nightModeEnabled'] as bool? ?? false,
      audioEnabled: json['audioEnabled'] as bool? ?? false,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.5,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0.5,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0.5,
      username: json['username'] as String?,
      password: json['password'] as String?,
      customSettings: Map<String, dynamic>.from(json['customSettings'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'motionDetectionEnabled': motionDetectionEnabled,
      'nightModeEnabled': nightModeEnabled,
      'audioEnabled': audioEnabled,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'username': username,
      'password': password,
      'customSettings': customSettings,
    };
  }

  CameraSettings copyWith({
    bool? motionDetectionEnabled,
    bool? nightModeEnabled,
    bool? audioEnabled,
    double? brightness,
    double? contrast,
    double? saturation,
    String? username,
    String? password,
    Map<String, dynamic>? customSettings,
  }) {
    return CameraSettings(
      motionDetectionEnabled: motionDetectionEnabled ?? this.motionDetectionEnabled,
      nightModeEnabled: nightModeEnabled ?? this.nightModeEnabled,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      username: username ?? this.username,
      password: password ?? this.password,
      customSettings: customSettings ?? this.customSettings,
    );
  }
}

class CameraModel {
  final String id;
  final String name;
  final CameraType type;
  final String ipAddress;
  final int port;
  final String? username;
  final String? password;
  final String? rtspPath;
  final bool isSecure;
  final CameraStatus status;
  final DateTime? lastSeen;
  final CameraCapabilities capabilities;
  final StreamConfig streamConfig;
  final CameraSettings settings;
  final String? thumbnailUrl;
  final Map<String, dynamic>? metadata;

  const CameraModel({
    required this.id,
    required this.name,
    required this.type,
    required this.ipAddress,
    required this.port,
    this.username,
    this.password,
    this.rtspPath,
    this.isSecure = false,
    required this.status,
    this.lastSeen,
    required this.capabilities,
    required this.streamConfig,
    required this.settings,
    this.thumbnailUrl,
    this.metadata,
  });

  factory CameraModel.fromJson(Map<String, dynamic> json) {
    return CameraModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: CameraType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => CameraType.ip,
      ),
      ipAddress: json['ipAddress'] as String,
      port: json['port'] as int,
      username: json['username'] as String?,
      password: json['password'] as String?,
      rtspPath: json['rtspPath'] as String?,
      isSecure: json['isSecure'] as bool? ?? false,
      status: CameraStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => CameraStatus.offline,
      ),
      lastSeen: json['lastSeen'] != null 
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
      capabilities: CameraCapabilities.fromJson(
          json['capabilities'] as Map<String, dynamic>),
      streamConfig: StreamConfig.fromJson(
          json['streamConfig'] as Map<String, dynamic>),
      settings: CameraSettings.fromJson(
          json['settings'] as Map<String, dynamic>? ?? {}),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'ipAddress': ipAddress,
      'port': port,
      'username': username,
      'password': password,
      'rtspPath': rtspPath,
      'isSecure': isSecure,
      'status': status.name,
      'lastSeen': lastSeen?.toIso8601String(),
      'capabilities': capabilities.toJson(),
      'streamConfig': streamConfig.toJson(),
      'settings': settings.toJson(),
      'thumbnailUrl': thumbnailUrl,
      'metadata': metadata,
    };
  }

  CameraModel copyWith({
    String? id,
    String? name,
    CameraType? type,
    String? ipAddress,
    int? port,
    String? username,
    String? password,
    String? rtspPath,
    bool? isSecure,
    CameraStatus? status,
    DateTime? lastSeen,
    CameraCapabilities? capabilities,
    StreamConfig? streamConfig,
    CameraSettings? settings,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
  }) {
    return CameraModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      rtspPath: rtspPath ?? this.rtspPath,
      isSecure: isSecure ?? this.isSecure,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      capabilities: capabilities ?? this.capabilities,
      streamConfig: streamConfig ?? this.streamConfig,
      settings: settings ?? this.settings,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get isOnline => status.isConnected;
  bool get canStream => status.canStream;
  bool get canRecord => status.canRecord;

  String get connectionUrl {
    final protocol = isSecure ? 'rtsps' : 'rtsp';
    final auth = username != null && password != null ? '$username:$password@' : '';
    final path = rtspPath ?? '/stream1';
    return '$protocol://$auth$ipAddress:$port$path';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CameraModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'CameraModel(id: $id, name: $name, type: $type, ipAddress: $ipAddress, status: $status)';
  }
}

class CameraCapabilities {
  final bool supportsPTZ;
  final bool supportsAudio;
  final bool supportsMotionDetection;
  final bool supportsNightMode;
  final bool supportsRecording;
  final bool supportsZoom;
  final bool hasEvents;
  final List<String> supportedResolutions;
  final List<String> supportedCodecs;
  final PTZCapabilities? ptzCapabilities;

  const CameraCapabilities({
    this.supportsPTZ = false,
    this.supportsAudio = false,
    this.supportsMotionDetection = false,
    this.supportsNightMode = false,
    this.supportsRecording = false,
    this.supportsZoom = false,
    this.hasEvents = false,
    this.supportedResolutions = const ['1920x1080'],
    this.supportedCodecs = const ['H.264'],
    this.ptzCapabilities,
  });

  factory CameraCapabilities.fromJson(Map<String, dynamic> json) {
    return CameraCapabilities(
      supportsPTZ: json['supportsPTZ'] as bool? ?? false,
      supportsAudio: json['supportsAudio'] as bool? ?? false,
      supportsMotionDetection: json['supportsMotionDetection'] as bool? ?? false,
      supportsNightMode: json['supportsNightMode'] as bool? ?? false,
      supportsRecording: json['supportsRecording'] as bool? ?? false,
      supportsZoom: json['supportsZoom'] as bool? ?? false,
      hasEvents: json['hasEvents'] as bool? ?? false,
      supportedResolutions: List<String>.from(json['supportedResolutions'] ?? ['1920x1080']),
      supportedCodecs: List<String>.from(json['supportedCodecs'] ?? ['H.264']),
      ptzCapabilities: json['ptzCapabilities'] != null
          ? PTZCapabilities.fromJson(json['ptzCapabilities'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'supportsPTZ': supportsPTZ,
      'supportsAudio': supportsAudio,
      'supportsMotionDetection': supportsMotionDetection,
      'supportsNightMode': supportsNightMode,
      'supportsRecording': supportsRecording,
      'supportsZoom': supportsZoom,
      'hasEvents': hasEvents,
      'supportedResolutions': supportedResolutions,
      'supportedCodecs': supportedCodecs,
      'ptzCapabilities': ptzCapabilities?.toJson(),
    };
  }
}

class PTZCapabilities {
  final double maxPanSpeed;
  final double maxTiltSpeed;
  final double maxZoomSpeed;
  final int panRange;
  final int tiltRange;
  final int zoomRange;
  final bool supportsPresets;
  final int maxPresets;

  const PTZCapabilities({
    this.maxPanSpeed = 1.0,
    this.maxTiltSpeed = 1.0,
    this.maxZoomSpeed = 1.0,
    this.panRange = 360,
    this.tiltRange = 180,
    this.zoomRange = 10,
    this.supportsPresets = false,
    this.maxPresets = 0,
  });

  factory PTZCapabilities.fromJson(Map<String, dynamic> json) {
    return PTZCapabilities(
      maxPanSpeed: (json['maxPanSpeed'] as num?)?.toDouble() ?? 1.0,
      maxTiltSpeed: (json['maxTiltSpeed'] as num?)?.toDouble() ?? 1.0,
      maxZoomSpeed: (json['maxZoomSpeed'] as num?)?.toDouble() ?? 1.0,
      panRange: json['panRange'] as int? ?? 360,
      tiltRange: json['tiltRange'] as int? ?? 180,
      zoomRange: json['zoomRange'] as int? ?? 10,
      supportsPresets: json['supportsPresets'] as bool? ?? false,
      maxPresets: json['maxPresets'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxPanSpeed': maxPanSpeed,
      'maxTiltSpeed': maxTiltSpeed,
      'maxZoomSpeed': maxZoomSpeed,
      'panRange': panRange,
      'tiltRange': tiltRange,
      'zoomRange': zoomRange,
      'supportsPresets': supportsPresets,
      'maxPresets': maxPresets,
    };
  }
}

// Alias para compatibilidade com widgets existentes