import 'dart:typed_data';

/// Representa uma posição PTZ favorita
class PtzPosition {
  final String id;
  final String name;
  final double pan;
  final double tilt;
  final double zoom;
  final Uint8List? thumbnail;
  final DateTime createdAt;

  PtzPosition({
    required this.id,
    required this.name,
    required this.pan,
    required this.tilt,
    required this.zoom,
    this.thumbnail,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pan': pan,
      'tilt': tilt,
      'zoom': zoom,
      'thumbnail': thumbnail?.toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PtzPosition.fromJson(Map<String, dynamic> json) {
    return PtzPosition(
      id: json['id'] as String,
      name: json['name'] as String,
      pan: (json['pan'] as num).toDouble(),
      tilt: (json['tilt'] as num).toDouble(),
      zoom: (json['zoom'] as num).toDouble(),
      thumbnail: json['thumbnail'] != null 
          ? Uint8List.fromList((json['thumbnail'] as List).cast<int>())
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Representa uma velocidade PTZ
class PtzSpeed {
  final Vector2D? panTilt;
  final Vector1D? zoom;

  PtzSpeed({
    this.panTilt,
    this.zoom,
  });
}

/// Representa um vetor 2D para pan/tilt
class Vector2D {
  final double x;
  final double y;
  final String? space;

  Vector2D({
    required this.x,
    required this.y,
    this.space,
  });
}

/// Representa um vetor 1D para zoom
class Vector1D {
  final double x;
  final String? space;

  Vector1D({
    required this.x,
    this.space,
  });
}

/// Direções de movimento PTZ
enum PTZDirection {
  up,
  down,
  left,
  right,
  upLeft,
  upRight,
  downLeft,
  downRight,
  zoomIn,
  zoomOut,
  stop
}

/// Capacidades PTZ de uma câmera
class PTZCapabilities {
  final bool supportsPan;
  final bool supportsTilt;
  final bool supportsZoom;
  final bool supportsPresets;
  final int maxPresets;
  final PTZRange panRange;
  final PTZRange tiltRange;
  final PTZRange zoomRange;

  PTZCapabilities({
    required this.supportsPan,
    required this.supportsTilt,
    required this.supportsZoom,
    required this.supportsPresets,
    required this.maxPresets,
    required this.panRange,
    required this.tiltRange,
    required this.zoomRange,
  });

  Map<String, dynamic> toJson() {
    return {
      'supportsPan': supportsPan,
      'supportsTilt': supportsTilt,
      'supportsZoom': supportsZoom,
      'supportsPresets': supportsPresets,
      'maxPresets': maxPresets,
      'panRange': panRange.toJson(),
      'tiltRange': tiltRange.toJson(),
      'zoomRange': zoomRange.toJson(),
    };
  }

  factory PTZCapabilities.fromJson(Map<String, dynamic> json) {
    return PTZCapabilities(
      supportsPan: json['supportsPan'] as bool,
      supportsTilt: json['supportsTilt'] as bool,
      supportsZoom: json['supportsZoom'] as bool,
      supportsPresets: json['supportsPresets'] as bool,
      maxPresets: json['maxPresets'] as int,
      panRange: PTZRange.fromJson(json['panRange'] as Map<String, dynamic>),
      tiltRange: PTZRange.fromJson(json['tiltRange'] as Map<String, dynamic>),
      zoomRange: PTZRange.fromJson(json['zoomRange'] as Map<String, dynamic>),
    );
  }
}

/// Range de valores PTZ
class PTZRange {
  final double min;
  final double max;

  PTZRange({
    required this.min,
    required this.max,
  });

  Map<String, dynamic> toJson() {
    return {
      'min': min,
      'max': max,
    };
  }

  factory PTZRange.fromJson(Map<String, dynamic> json) {
    return PTZRange(
      min: (json['min'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
    );
  }
}