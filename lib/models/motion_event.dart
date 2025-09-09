class MotionEvent {
  final String id;
  final String cameraId;
  final DateTime timestamp;
  final double confidence;
  final List<MotionZone> zones;
  final Map<String, dynamic>? metadata;

  const MotionEvent({
    required this.id,
    required this.cameraId,
    required this.timestamp,
    required this.confidence,
    required this.zones,
    this.metadata,
  });

  factory MotionEvent.fromJson(Map<String, dynamic> json) {
    return MotionEvent(
      id: json['id'] as String,
      cameraId: json['cameraId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      confidence: (json['confidence'] as num).toDouble(),
      zones: (json['zones'] as List<dynamic>)
          .map((zone) => MotionZone.fromJson(zone as Map<String, dynamic>))
          .toList(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cameraId': cameraId,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
      'zones': zones.map((zone) => zone.toJson()).toList(),
      'metadata': metadata,
    };
  }

  MotionEvent copyWith({
    String? id,
    String? cameraId,
    DateTime? timestamp,
    double? confidence,
    List<MotionZone>? zones,
    Map<String, dynamic>? metadata,
  }) {
    return MotionEvent(
      id: id ?? this.id,
      cameraId: cameraId ?? this.cameraId,
      timestamp: timestamp ?? this.timestamp,
      confidence: confidence ?? this.confidence,
      zones: zones ?? this.zones,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MotionEvent &&
        other.id == id &&
        other.cameraId == cameraId &&
        other.timestamp == timestamp &&
        other.confidence == confidence;
  }

  @override
  int get hashCode {
    return Object.hash(id, cameraId, timestamp, confidence);
  }

  @override
  String toString() {
    return 'MotionEvent(id: $id, cameraId: $cameraId, timestamp: $timestamp, confidence: $confidence)';
  }
}

class MotionZone {
  final String id;
  final String name;
  final List<Point> points;
  final double sensitivity;
  final bool isActive;

  const MotionZone({
    required this.id,
    required this.name,
    required this.points,
    required this.sensitivity,
    required this.isActive,
  });

  factory MotionZone.fromJson(Map<String, dynamic> json) {
    return MotionZone(
      id: json['id'] as String,
      name: json['name'] as String,
      points: (json['points'] as List<dynamic>)
          .map((point) => Point.fromJson(point as Map<String, dynamic>))
          .toList(),
      sensitivity: (json['sensitivity'] as num).toDouble(),
      isActive: json['isActive'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'points': points.map((point) => point.toJson()).toList(),
      'sensitivity': sensitivity,
      'isActive': isActive,
    };
  }

  MotionZone copyWith({
    String? id,
    String? name,
    List<Point>? points,
    double? sensitivity,
    bool? isActive,
  }) {
    return MotionZone(
      id: id ?? this.id,
      name: name ?? this.name,
      points: points ?? this.points,
      sensitivity: sensitivity ?? this.sensitivity,
      isActive: isActive ?? this.isActive,
    );
  }
}

class Point {
  final double x;
  final double y;

  const Point({
    required this.x,
    required this.y,
  });

  factory Point.fromJson(Map<String, dynamic> json) {
    return Point(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
    };
  }

  Point copyWith({
    double? x,
    double? y,
  }) {
    return Point(
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Point && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point(x: $x, y: $y)';
}