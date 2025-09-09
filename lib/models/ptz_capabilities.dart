import 'ptz_command.dart';

class PTZCapabilities {
  final bool supportsPan;
  final bool supportsTilt;
  final bool supportsZoom;
  final bool supportsFocus;
  final bool supportsPresets;
  final bool supportsAutoScan;
  final int maxPresets;
  final List<double> panRange;
  final List<double> tiltRange;
  final List<double> zoomRange;
  final List<PTZSpeed> supportedSpeeds;
  final Map<String, dynamic>? additionalCapabilities;

  const PTZCapabilities({
    required this.supportsPan,
    required this.supportsTilt,
    required this.supportsZoom,
    required this.supportsFocus,
    required this.supportsPresets,
    required this.supportsAutoScan,
    required this.maxPresets,
    required this.panRange,
    required this.tiltRange,
    required this.zoomRange,
    this.supportedSpeeds = const [
      PTZSpeed.slow,
      PTZSpeed.medium,
      PTZSpeed.fast,
    ],
    this.additionalCapabilities,
  });

  factory PTZCapabilities.fromJson(Map<String, dynamic> json) {
    return PTZCapabilities(
      supportsPan: json['supportsPan'] as bool? ?? true,
      supportsTilt: json['supportsTilt'] as bool? ?? true,
      supportsZoom: json['supportsZoom'] as bool? ?? true,
      supportsFocus: json['supportsFocus'] as bool? ?? false,
      supportsPresets: json['supportsPresets'] as bool? ?? true,
      supportsAutoScan: json['supportsAutoScan'] as bool? ?? false,
      maxPresets: json['maxPresets'] as int? ?? 8,
      panRange: (json['panRange'] as List?)?.cast<double>() ?? [-180.0, 180.0],
      tiltRange: (json['tiltRange'] as List?)?.cast<double>() ?? [-90.0, 90.0],
      zoomRange: (json['zoomRange'] as List?)?.cast<double>() ?? [1.0, 10.0],
      supportedSpeeds: (json['supportedSpeeds'] as List?)
          ?.map((e) => PTZSpeed.values.firstWhere(
                (s) => s.name == e,
                orElse: () => PTZSpeed.medium,
              ))
          .toList() ??
          const [PTZSpeed.slow, PTZSpeed.medium, PTZSpeed.fast],
      additionalCapabilities: json['additionalCapabilities'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'supportsPan': supportsPan,
      'supportsTilt': supportsTilt,
      'supportsZoom': supportsZoom,
      'supportsFocus': supportsFocus,
      'supportsPresets': supportsPresets,
      'supportsAutoScan': supportsAutoScan,
      'maxPresets': maxPresets,
      'panRange': panRange,
      'tiltRange': tiltRange,
      'zoomRange': zoomRange,
      'supportedSpeeds': supportedSpeeds.map((s) => s.name).toList(),
      'additionalCapabilities': additionalCapabilities,
    };
  }

  bool get hasMovementCapabilities => supportsPan || supportsTilt;
  bool get hasZoomCapabilities => supportsZoom || supportsFocus;
  bool get hasAdvancedFeatures => supportsPresets || supportsAutoScan;

  PTZCapabilities copyWith({
    bool? supportsPan,
    bool? supportsTilt,
    bool? supportsZoom,
    bool? supportsFocus,
    bool? supportsPresets,
    bool? supportsAutoScan,
    int? maxPresets,
    List<double>? panRange,
    List<double>? tiltRange,
    List<double>? zoomRange,
    List<PTZSpeed>? supportedSpeeds,
    Map<String, dynamic>? additionalCapabilities,
  }) {
    return PTZCapabilities(
      supportsPan: supportsPan ?? this.supportsPan,
      supportsTilt: supportsTilt ?? this.supportsTilt,
      supportsZoom: supportsZoom ?? this.supportsZoom,
      supportsFocus: supportsFocus ?? this.supportsFocus,
      supportsPresets: supportsPresets ?? this.supportsPresets,
      supportsAutoScan: supportsAutoScan ?? this.supportsAutoScan,
      maxPresets: maxPresets ?? this.maxPresets,
      panRange: panRange ?? this.panRange,
      tiltRange: tiltRange ?? this.tiltRange,
      zoomRange: zoomRange ?? this.zoomRange,
      supportedSpeeds: supportedSpeeds ?? this.supportedSpeeds,
      additionalCapabilities: additionalCapabilities ?? this.additionalCapabilities,
    );
  }

  @override
  String toString() {
    return 'PTZCapabilities(pan: $supportsPan, tilt: $supportsTilt, zoom: $supportsZoom, focus: $supportsFocus, presets: $supportsPresets/$maxPresets)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PTZCapabilities &&
        other.supportsPan == supportsPan &&
        other.supportsTilt == supportsTilt &&
        other.supportsZoom == supportsZoom &&
        other.supportsFocus == supportsFocus &&
        other.supportsPresets == supportsPresets &&
        other.supportsAutoScan == supportsAutoScan &&
        other.maxPresets == maxPresets;
  }

  @override
  int get hashCode {
    return Object.hash(
      supportsPan,
      supportsTilt,
      supportsZoom,
      supportsFocus,
      supportsPresets,
      supportsAutoScan,
      maxPresets,
    );
  }
}

class PTZMovementStep {
  final PTZDirection direction;
  final PTZSpeed speed;
  final Duration duration;
  final Duration? pauseAfter;
  final String? description;

  const PTZMovementStep({
    required this.direction,
    required this.speed,
    required this.duration,
    this.pauseAfter,
    this.description,
  });

  factory PTZMovementStep.fromJson(Map<String, dynamic> json) {
    return PTZMovementStep(
      direction: PTZDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => PTZDirection.stop,
      ),
      speed: PTZSpeed.values.firstWhere(
        (s) => s.name == json['speed'],
        orElse: () => PTZSpeed.medium,
      ),
      duration: Duration(milliseconds: json['duration'] as int),
      pauseAfter: json['pauseAfter'] != null
          ? Duration(milliseconds: json['pauseAfter'] as int)
          : null,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'direction': direction.name,
      'speed': speed.name,
      'duration': duration.inMilliseconds,
      'pauseAfter': pauseAfter?.inMilliseconds,
      'description': description,
    };
  }

  PTZMovementStep copyWith({
    PTZDirection? direction,
    PTZSpeed? speed,
    Duration? duration,
    Duration? pauseAfter,
    String? description,
  }) {
    return PTZMovementStep(
      direction: direction ?? this.direction,
      speed: speed ?? this.speed,
      duration: duration ?? this.duration,
      pauseAfter: pauseAfter ?? this.pauseAfter,
      description: description ?? this.description,
    );
  }

  @override
  String toString() {
    return 'PTZMovementStep(${direction.name}, ${speed.name}, ${duration.inSeconds}s)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PTZMovementStep &&
        other.direction == direction &&
        other.speed == speed &&
        other.duration == duration;
  }

  @override
  int get hashCode {
    return Object.hash(direction, speed, duration);
  }
}

class PTZPreset {
  final int number;
  final String name;
  final double? panPosition;
  final double? tiltPosition;
  final double? zoomLevel;
  final DateTime? createdAt;
  final DateTime? lastUsed;
  final String? description;

  const PTZPreset({
    required this.number,
    required this.name,
    this.panPosition,
    this.tiltPosition,
    this.zoomLevel,
    this.createdAt,
    this.lastUsed,
    this.description,
  });

  factory PTZPreset.fromJson(Map<String, dynamic> json) {
    return PTZPreset(
      number: json['number'] as int,
      name: json['name'] as String,
      panPosition: json['panPosition'] as double?,
      tiltPosition: json['tiltPosition'] as double?,
      zoomLevel: json['zoomLevel'] as double?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      lastUsed: json['lastUsed'] != null
          ? DateTime.parse(json['lastUsed'] as String)
          : null,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'name': name,
      'panPosition': panPosition,
      'tiltPosition': tiltPosition,
      'zoomLevel': zoomLevel,
      'createdAt': createdAt?.toIso8601String(),
      'lastUsed': lastUsed?.toIso8601String(),
      'description': description,
    };
  }

  PTZPreset copyWith({
    int? number,
    String? name,
    double? panPosition,
    double? tiltPosition,
    double? zoomLevel,
    DateTime? createdAt,
    DateTime? lastUsed,
    String? description,
  }) {
    return PTZPreset(
      number: number ?? this.number,
      name: name ?? this.name,
      panPosition: panPosition ?? this.panPosition,
      tiltPosition: tiltPosition ?? this.tiltPosition,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
      description: description ?? this.description,
    );
  }

  @override
  String toString() {
    return 'PTZPreset($number: $name)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PTZPreset &&
        other.number == number &&
        other.name == name;
  }

  @override
  int get hashCode {
    return Object.hash(number, name);
  }
}