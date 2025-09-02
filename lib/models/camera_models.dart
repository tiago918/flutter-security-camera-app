import 'package:flutter/material.dart';
import 'dart:typed_data';

class RecordingInfo {
  final String id;
  final String filename;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final int sizeBytes;
  final String recordingType; // 'Motion', 'Continuous', 'Event', 'Manual'
  final String? thumbnailUrl;
  final Map<String, dynamic>? metadata;

  RecordingInfo({
    required this.id,
    required this.filename,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.sizeBytes,
    required this.recordingType,
    this.thumbnailUrl,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'duration': duration.inSeconds,
        'sizeBytes': sizeBytes,
        'recordingType': recordingType,
        'thumbnailUrl': thumbnailUrl,
        'metadata': metadata,
      };

  factory RecordingInfo.fromJson(Map<String, dynamic> json) => RecordingInfo(
        id: json['id'] as String,
        filename: json['filename'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
        duration: Duration(seconds: json['duration'] as int),
        sizeBytes: json['sizeBytes'] as int,
        recordingType: json['recordingType'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );

  String get formattedSize {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}

class PtzPosition {
  final String id;
  final String name;
  final double pan;
  final double tilt;
  final double zoom;
  final Uint8List? thumbnail; // Miniatura da posição
  final DateTime createdAt;

  const PtzPosition({
    required this.id,
    required this.name,
    required this.pan,
    required this.tilt,
    required this.zoom,
    this.thumbnail,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pan': pan,
        'tilt': tilt,
        'zoom': zoom,
        'thumbnail': thumbnail,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PtzPosition.fromJson(Map<String, dynamic> json) => PtzPosition(
        id: json['id'] as String,
        name: json['name'] as String,
        pan: (json['pan'] as num).toDouble(),
        tilt: (json['tilt'] as num).toDouble(),
        zoom: (json['zoom'] as num).toDouble(),
        thumbnail: json['thumbnail'] as Uint8List?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class MotionDetectionZone {
  final String id;
  final String name;
  final List<Offset> points; // Pontos que definem a área
  final bool isEnabled;
  final bool isExclusionZone; // true = ignorar, false = detectar
  final double sensitivity; // 0.0 a 1.0

  const MotionDetectionZone({
    required this.id,
    required this.name,
    required this.points,
    this.isEnabled = true,
    this.isExclusionZone = false,
    this.sensitivity = 0.5,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'points': points.map((p) => <String, double>{'x': p.dx, 'y': p.dy}).toList(),
        'isEnabled': isEnabled,
        'isExclusionZone': isExclusionZone,
        'sensitivity': sensitivity,
      };

  factory MotionDetectionZone.fromJson(Map<String, dynamic> json) => MotionDetectionZone(
        id: json['id'] as String,
        name: json['name'] as String,
        points: (json['points'] as List)
            .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList(),
        isEnabled: json['isEnabled'] as bool? ?? true,
        isExclusionZone: json['isExclusionZone'] as bool? ?? false,
        sensitivity: (json['sensitivity'] as num?)?.toDouble() ?? 0.5,
      );
}

class CameraCapabilities {
  final bool hasMotionDetection;
  final bool hasNightVision;
  final bool hasPTZ;
  final bool hasAudio;
  final bool hasEvents;
  final bool hasRecording;
  final bool hasNotifications;
  final bool hasPlayback; // Capacidade de reproduzir gravações do cartão SD
  final bool hasRecordingSearch; // Capacidade de buscar gravações
  final bool hasRecordingDownload; // Capacidade de baixar gravações
  final List<String> availableProfiles;
  final String? imagingOptions;
  final DateTime? lastDetected;
  final List<PtzPosition> ptzPositions;
  final List<MotionDetectionZone> motionZones;
  final bool nightModeEnabled;
  final bool irLightsEnabled;
  final List<String> supportedRecordingFormats; // Formatos suportados para gravação
  final bool supportsOnvifProfileG; // Suporte ao ONVIF Profile G (Recording)

  const CameraCapabilities({
    this.hasMotionDetection = false,
    this.hasNightVision = false,
    this.hasPTZ = false,
    this.hasAudio = false,
    this.hasEvents = false,
    this.hasRecording = false,
    this.hasNotifications = false,
    this.hasPlayback = false,
    this.hasRecordingSearch = false,
    this.hasRecordingDownload = false,
    this.availableProfiles = const [],
    this.imagingOptions,
    this.lastDetected,
    this.ptzPositions = const [],
    this.motionZones = const [],
    this.nightModeEnabled = false,
    this.irLightsEnabled = false,
    this.supportedRecordingFormats = const [],
    this.supportsOnvifProfileG = false,
  });

  Map<String, dynamic> toJson() => {
        'hasMotionDetection': hasMotionDetection,
        'hasNightVision': hasNightVision,
        'hasPTZ': hasPTZ,
        'hasAudio': hasAudio,
        'hasEvents': hasEvents,
        'hasRecording': hasRecording,
        'hasNotifications': hasNotifications,
        'hasPlayback': hasPlayback,
        'hasRecordingSearch': hasRecordingSearch,
        'hasRecordingDownload': hasRecordingDownload,
        'availableProfiles': availableProfiles,
        'imagingOptions': imagingOptions,
        'lastDetected': lastDetected?.toIso8601String(),
        'ptzPositions': ptzPositions.map((p) => p.toJson()).toList(),
        'motionZones': motionZones.map((z) => z.toJson()).toList(),
        'nightModeEnabled': nightModeEnabled,
        'irLightsEnabled': irLightsEnabled,
        'supportedRecordingFormats': supportedRecordingFormats,
        'supportsOnvifProfileG': supportsOnvifProfileG,
      };

  factory CameraCapabilities.fromJson(Map<String, dynamic> json) => CameraCapabilities(
        hasMotionDetection: json['hasMotionDetection'] as bool? ?? false,
        hasNightVision: json['hasNightVision'] as bool? ?? false,
        hasPTZ: json['hasPTZ'] as bool? ?? false,
        hasAudio: json['hasAudio'] as bool? ?? false,
        hasEvents: json['hasEvents'] as bool? ?? false,
        hasRecording: json['hasRecording'] as bool? ?? false,
        hasNotifications: json['hasNotifications'] as bool? ?? false,
        hasPlayback: json['hasPlayback'] as bool? ?? false,
        hasRecordingSearch: json['hasRecordingSearch'] as bool? ?? false,
        hasRecordingDownload: json['hasRecordingDownload'] as bool? ?? false,
        availableProfiles: List<String>.from(json['availableProfiles'] as List? ?? []),
        imagingOptions: json['imagingOptions'] as String?,
        lastDetected: json['lastDetected'] != null ? DateTime.parse(json['lastDetected'] as String) : null,
        ptzPositions: (json['ptzPositions'] as List? ?? [])
            .map((p) => PtzPosition.fromJson(p as Map<String, dynamic>))
            .toList(),
        motionZones: (json['motionZones'] as List? ?? [])
            .map((z) => MotionDetectionZone.fromJson(z as Map<String, dynamic>))
            .toList(),
        nightModeEnabled: json['nightModeEnabled'] as bool? ?? false,
        irLightsEnabled: json['irLightsEnabled'] as bool? ?? false,
        supportedRecordingFormats: List<String>.from(json['supportedRecordingFormats'] as List? ?? []),
        supportsOnvifProfileG: json['supportsOnvifProfileG'] as bool? ?? false,
       );
}

class CameraData {
  final int id;
  final String name;
  final bool isLive;
  final Color statusColor;
  final Color uniqueColor; // Cor única para identificação visual
  final IconData icon;
  final String streamUrl; // RTSP/HTTP URL
  final String? username;
  final String? password;
  final int? port; // opcional, para referência
  final String transport; // 'tcp' ou 'udp'
  final CameraCapabilities? capabilities; // Capacidades detectadas via ONVIF
  final bool acceptSelfSigned;

  const CameraData({
    required this.id,
    required this.name,
    required this.isLive,
    required this.statusColor,
    required this.uniqueColor,
    required this.icon,
    required this.streamUrl,
    this.username,
    this.password,
    this.port,
    this.transport = 'tcp', // Padrão TCP para melhor estabilidade
    this.capabilities,
    this.acceptSelfSigned = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isLive': isLive,
        'statusColor': statusColor.value,
        'uniqueColor': uniqueColor.value,
        'icon': icon.codePoint,
        'streamUrl': streamUrl,
        'username': username,
        'password': password,
        'port': port,
        'transport': transport,
        'capabilities': capabilities?.toJson(),
        'acceptSelfSigned': acceptSelfSigned,
      };

  factory CameraData.fromJson(Map<String, dynamic> json) => CameraData(
        id: json['id'] as int,
        name: json['name'] as String,
        isLive: json['isLive'] as bool? ?? false,
        statusColor: Color(json['statusColor'] as int? ?? 0xFF888888),
        uniqueColor: Color(json['uniqueColor'] as int? ?? generateUniqueColor(json['id'] as int)),
        icon: _getIconFromCodePoint(json['icon'] as int?),
        streamUrl: json['streamUrl'] as String,
        username: json['username'] as String?,
        password: json['password'] as String?,
        port: json['port'] as int?,
        transport: json['transport'] as String? ?? 'tcp',
        capabilities: json['capabilities'] != null ? CameraCapabilities.fromJson(json['capabilities'] as Map<String, dynamic>) : null,
        acceptSelfSigned: json['acceptSelfSigned'] as bool? ?? false,
       );

  // Gera uma cor única baseada no ID da câmera
  static int generateUniqueColor(int cameraId) {
    final colors = [
      0xFF2196F3, // Azul
      0xFF4CAF50, // Verde
      0xFFFF9800, // Laranja
      0xFF9C27B0, // Roxo
      0xFFF44336, // Vermelho
      0xFF00BCD4, // Ciano
      0xFFFFEB3B, // Amarelo
      0xFF795548, // Marrom
      0xFF607D8B, // Azul acinzentado
      0xFFE91E63, // Rosa
    ];
    return colors[cameraId % colors.length];
  }

  // Mapeamento de ícones para permitir tree-shake
  static IconData _getIconFromCodePoint(int? codePoint) {
    if (codePoint == null) return Icons.videocam_outlined;

    // Mapeia os codePoints mais comuns para ícones conhecidos
    switch (codePoint) {
      case 57436: // Icons.videocam_outlined.codePoint
        return Icons.videocam_outlined;
      case 57435: // Icons.videocam.codePoint
        return Icons.videocam;
      case 58173: // Icons.camera_alt.codePoint
        return Icons.camera_alt;
      case 58655: // Icons.security.codePoint
        return Icons.security;
      case 59576: // Icons.router.codePoint
        return Icons.router;
      default:
        return Icons.videocam_outlined; // fallback padrão
    }
  }
}