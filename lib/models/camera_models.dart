import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:security_camera_app/models/ptz_models.dart';
import 'camera_model.dart';
import 'camera_status.dart';

// Enum para tipos de protocolo suportados
enum ProtocolType {
  onvif,
  proprietary, // DVRIP-Web ou outros protocolos proprietários
  hybrid // Suporte a ambos os protocolos
}

// Configuração de portas para comunicação com câmeras
class CameraPortConfiguration {
  final int httpPort;
  final int rtspPort;
  final int onvifPort;
  final int proprietaryPort;
  final int alternativePort;
  final bool useHttps;
  final bool acceptSelfSigned;
  final String preferredProtocol; // 'onvif', 'proprietary', 'rtsp'

  const CameraPortConfiguration({
    this.httpPort = 80,
    this.rtspPort = 554,
    this.onvifPort = 80,
    this.proprietaryPort = 8000,
    this.alternativePort = 8899,
    this.useHttps = false,
    this.acceptSelfSigned = false,
    this.preferredProtocol = 'onvif',
  });

  CameraPortConfiguration copyWith({
    int? httpPort,
    int? rtspPort,
    int? onvifPort,
    int? proprietaryPort,
    int? alternativePort,
    bool? useHttps,
    bool? acceptSelfSigned,
    String? preferredProtocol,
  }) {
    return CameraPortConfiguration(
      httpPort: httpPort ?? this.httpPort,
      rtspPort: rtspPort ?? this.rtspPort,
      onvifPort: onvifPort ?? this.onvifPort,
      proprietaryPort: proprietaryPort ?? this.proprietaryPort,
      alternativePort: alternativePort ?? this.alternativePort,
      useHttps: useHttps ?? this.useHttps,
      acceptSelfSigned: acceptSelfSigned ?? this.acceptSelfSigned,
      preferredProtocol: preferredProtocol ?? this.preferredProtocol,
    );
  }

  Map<String, dynamic> toJson() => {
        'httpPort': httpPort,
        'rtspPort': rtspPort,
        'onvifPort': onvifPort,
        'proprietaryPort': proprietaryPort,
        'alternativePort': alternativePort,
        'useHttps': useHttps,
        'acceptSelfSigned': acceptSelfSigned,
        'preferredProtocol': preferredProtocol,
      };

  factory CameraPortConfiguration.fromJson(Map<String, dynamic> json) => CameraPortConfiguration(
        httpPort: json['httpPort'] as int? ?? 80,
        rtspPort: json['rtspPort'] as int? ?? 554,
        onvifPort: json['onvifPort'] as int? ?? 80,
        proprietaryPort: json['proprietaryPort'] as int? ?? 8000,
        alternativePort: json['alternativePort'] as int? ?? 8899,
        useHttps: json['useHttps'] as bool? ?? false,
        acceptSelfSigned: json['acceptSelfSigned'] as bool? ?? false,
        preferredProtocol: json['preferredProtocol'] as String? ?? 'onvif',
       );

  // Método para criar configuração padrão para câmeras ONVIF
  factory CameraPortConfiguration.onvifDefault() => const CameraPortConfiguration(
        httpPort: 80,
        onvifPort: 8080,
        preferredProtocol: 'onvif',
      );

  // Método para criar configuração padrão para câmeras proprietárias
  factory CameraPortConfiguration.proprietaryDefault() => const CameraPortConfiguration(
        httpPort: 80,
        onvifPort: 8080,
        proprietaryPort: 34567,
        preferredProtocol: 'proprietary',
      );

  // Método para criar configuração híbrida
  factory CameraPortConfiguration.hybridDefault() => const CameraPortConfiguration(
        httpPort: 80,
        onvifPort: 8080,
        proprietaryPort: 34567,
        preferredProtocol: 'auto',
      );
}

class ProtocolDetectionResult {
  final bool onvifAvailable;
  final bool proprietaryAvailable;
  final bool rtspAvailable;
  final int? detectedOnvifPort;
  final int? detectedProprietaryPort;
  final int? detectedRtspPort;
  final String? error;

  const ProtocolDetectionResult({
    this.onvifAvailable = false,
    this.proprietaryAvailable = false,
    this.rtspAvailable = false,
    this.detectedOnvifPort,
    this.detectedProprietaryPort,
    this.detectedRtspPort,
    this.error,
  });

  bool get hasAnyProtocol => onvifAvailable || proprietaryAvailable || rtspAvailable;
  
  List<String> get supportedProtocols {
    final protocols = <String>[];
    if (onvifAvailable) protocols.add('onvif');
    if (proprietaryAvailable) protocols.add('proprietary');
    if (rtspAvailable) protocols.add('rtsp');
    return protocols;
  }

  Map<String, dynamic> toJson() => {
        'onvifAvailable': onvifAvailable,
        'proprietaryAvailable': proprietaryAvailable,
        'rtspAvailable': rtspAvailable,
        'detectedOnvifPort': detectedOnvifPort,
        'detectedProprietaryPort': detectedProprietaryPort,
        'detectedRtspPort': detectedRtspPort,
        'error': error,
      };

  factory ProtocolDetectionResult.fromJson(Map<String, dynamic> json) => ProtocolDetectionResult(
        onvifAvailable: json['onvifAvailable'] as bool? ?? false,
        proprietaryAvailable: json['proprietaryAvailable'] as bool? ?? false,
        rtspAvailable: json['rtspAvailable'] as bool? ?? false,
        detectedOnvifPort: json['detectedOnvifPort'] as int?,
        detectedProprietaryPort: json['detectedProprietaryPort'] as int?,
        detectedRtspPort: json['detectedRtspPort'] as int?,
        error: json['error'] as String?,
       );
}

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

// CameraCapabilities removida para evitar conflito - usar a de camera_model.dart

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
  final int? port; // opcional, para referência (mantido para compatibilidade)
  final String transport; // 'tcp' ou 'udp'
  final CameraCapabilities? capabilities; // Capacidades detectadas via ONVIF
  final bool acceptSelfSigned;
  final CameraPortConfiguration portConfiguration; // Nova configuração de portas
  final String? host; // Host/IP da câmera (extraído do streamUrl se não fornecido)
  final CameraStatus status; // Status atual da câmera

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
    CameraPortConfiguration? portConfiguration,
    this.host,
    this.status = CameraStatus.offline, // Status padrão
  }) : portConfiguration = portConfiguration ?? const CameraPortConfiguration();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isLive': isLive,
        'statusColor': statusColor.toARGB32(),
        'uniqueColor': uniqueColor.toARGB32(),
        'icon': icon.codePoint,
        'streamUrl': streamUrl,
        'username': username,
        'password': password,
        'port': port,
        'transport': transport,
        'capabilities': capabilities?.toJson(),
        'acceptSelfSigned': acceptSelfSigned,
        'portConfiguration': portConfiguration.toJson(),
        'host': host,
        'status': status.name,
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
        portConfiguration: json['portConfiguration'] != null 
            ? CameraPortConfiguration.fromJson(json['portConfiguration'] as Map<String, dynamic>)
            : const CameraPortConfiguration(), // Configuração padrão para compatibilidade
        host: json['host'] as String?,
        status: CameraStatus.values.firstWhere(
          (e) => e.name == (json['status'] as String?),
          orElse: () => CameraStatus.offline,
        ),
       );

  // Extrai o host/IP do streamUrl
  String getHost() {
    if (host != null) return host!;
    
    try {
      final uri = Uri.parse(streamUrl);
      return uri.host;
    } catch (e) {
      // Fallback: tentar extrair IP/host manualmente
      final regex = RegExp(r'://([^:/]+)');
      final match = regex.firstMatch(streamUrl);
      return match?.group(1) ?? 'unknown';
    }
  }

  // Getter para compatibilidade com código existente
  String get ipAddress => getHost();

  // Método copyWith para compatibilidade
  CameraData copyWith({
    int? id,
    String? name,
    bool? isLive,
    Color? statusColor,
    Color? uniqueColor,
    IconData? icon,
    String? streamUrl,
    String? username,
    String? password,
    int? port,
    String? transport,
    CameraCapabilities? capabilities,
    bool? acceptSelfSigned,
    CameraPortConfiguration? portConfiguration,
    String? host,
    CameraStatus? status,
  }) {
    return CameraData(
      id: id ?? this.id,
      name: name ?? this.name,
      isLive: isLive ?? this.isLive,
      statusColor: statusColor ?? this.statusColor,
      uniqueColor: uniqueColor ?? this.uniqueColor,
      icon: icon ?? this.icon,
      streamUrl: streamUrl ?? this.streamUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      port: port ?? this.port,
      transport: transport ?? this.transport,
      capabilities: capabilities ?? this.capabilities,
      acceptSelfSigned: acceptSelfSigned ?? this.acceptSelfSigned,
      portConfiguration: portConfiguration ?? this.portConfiguration,
      host: host ?? this.host,
      status: status ?? this.status,
    );
  }

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

// Modelo para dados de notificação da UI
class NotificationData {
  final int cameraId;
  final String message;
  final String time;
  final Color statusColor;

  const NotificationData({
    required this.cameraId,
    required this.message,
    required this.time,
    required this.statusColor,
  });

  Map<String, dynamic> toJson() => {
        'cameraId': cameraId,
        'message': message,
        'time': time,
        'statusColor': statusColor.toARGB32(),
      };

  factory NotificationData.fromJson(Map<String, dynamic> json) => NotificationData(
        cameraId: json['cameraId'] as int,
        message: json['message'] as String,
        time: json['time'] as String,
        statusColor: Color(json['statusColor'] as int),
      );
}
