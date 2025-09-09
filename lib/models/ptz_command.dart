enum PTZAction {
  move,
  zoom,
  stop,
  preset,
  autoScan,
  focus;

  String get commandName {
    switch (this) {
      case PTZAction.move:
        return 'PTZ_MOVE';
      case PTZAction.zoom:
        return 'PTZ_ZOOM';
      case PTZAction.stop:
        return 'PTZ_STOP';
      case PTZAction.preset:
        return 'PTZ_PRESET';
      case PTZAction.autoScan:
        return 'PTZ_AUTO_SCAN';
      case PTZAction.focus:
        return 'PTZ_FOCUS';
    }
  }
}

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
  focusNear,
  focusFar,
  stop;

  String get directionCode {
    switch (this) {
      case PTZDirection.up:
        return 'UP';
      case PTZDirection.down:
        return 'DOWN';
      case PTZDirection.left:
        return 'LEFT';
      case PTZDirection.right:
        return 'RIGHT';
      case PTZDirection.upLeft:
        return 'UP_LEFT';
      case PTZDirection.upRight:
        return 'UP_RIGHT';
      case PTZDirection.downLeft:
        return 'DOWN_LEFT';
      case PTZDirection.downRight:
        return 'DOWN_RIGHT';
      case PTZDirection.zoomIn:
        return 'ZOOM_IN';
      case PTZDirection.zoomOut:
        return 'ZOOM_OUT';
      case PTZDirection.focusNear:
        return 'FOCUS_NEAR';
      case PTZDirection.focusFar:
        return 'FOCUS_FAR';
      case PTZDirection.stop:
        return 'STOP';
    }
  }

  String get displayName {
    switch (this) {
      case PTZDirection.up:
        return 'Cima';
      case PTZDirection.down:
        return 'Baixo';
      case PTZDirection.left:
        return 'Esquerda';
      case PTZDirection.right:
        return 'Direita';
      case PTZDirection.upLeft:
        return 'Cima-Esquerda';
      case PTZDirection.upRight:
        return 'Cima-Direita';
      case PTZDirection.downLeft:
        return 'Baixo-Esquerda';
      case PTZDirection.downRight:
        return 'Baixo-Direita';
      case PTZDirection.zoomIn:
        return 'Zoom In';
      case PTZDirection.zoomOut:
        return 'Zoom Out';
      case PTZDirection.focusNear:
        return 'Foco Próximo';
      case PTZDirection.focusFar:
        return 'Foco Distante';
      case PTZDirection.stop:
        return 'Parar';
    }
  }

  bool get isMovement {
    return [up, down, left, right, upLeft, upRight, downLeft, downRight].contains(this);
  }

  bool get isZoom {
    return [zoomIn, zoomOut].contains(this);
  }

  bool get isFocus {
    return [focusNear, focusFar].contains(this);
  }
}

enum PTZSpeed {
  slow,
  medium,
  fast,
  veryFast;

  int get speedValue {
    switch (this) {
      case PTZSpeed.slow:
        return 1;
      case PTZSpeed.medium:
        return 3;
      case PTZSpeed.fast:
        return 5;
      case PTZSpeed.veryFast:
        return 7;
    }
  }

  String get displayName {
    switch (this) {
      case PTZSpeed.slow:
        return 'Lenta';
      case PTZSpeed.medium:
        return 'Média';
      case PTZSpeed.fast:
        return 'Rápida';
      case PTZSpeed.veryFast:
        return 'Muito Rápida';
    }
  }
}

class PTZCommand {
  final String cameraId;
  final PTZAction action;
  final PTZDirection? direction;
  final PTZSpeed speed;
  final int? presetNumber;
  final int? duration; // em milissegundos
  final Map<String, dynamic>? additionalParams;
  final DateTime timestamp;

  PTZCommand({    required this.cameraId,    required this.action,    this.direction,    this.speed = PTZSpeed.medium,    this.presetNumber,    this.duration,    this.additionalParams,    DateTime? timestamp,  }) : timestamp = timestamp ?? DateTime.now();

  // Getter para direção do zoom
  PTZDirection? get zoomDirection {
    if (direction != null && direction!.isZoom) {
      return direction;
    }
    return null;
  }

  factory PTZCommand.fromJson(Map<String, dynamic> json) {
    return PTZCommand(
      cameraId: json['cameraId'] as String,
      action: PTZAction.values.firstWhere(
        (a) => a.name == json['action'],
        orElse: () => PTZAction.stop,
      ),
      direction: json['direction'] != null
          ? PTZDirection.values.firstWhere(
              (d) => d.name == json['direction'],
              orElse: () => PTZDirection.stop,
            )
          : null,
      speed: PTZSpeed.values.firstWhere(
        (s) => s.name == json['speed'],
        orElse: () => PTZSpeed.medium,
      ),
      presetNumber: json['presetNumber'] as int?,
      duration: json['duration'] as int?,
      additionalParams: json['additionalParams'] as Map<String, dynamic>?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cameraId': cameraId,
      'action': action.name,
      'direction': direction?.name,
      'speed': speed.name,
      'presetNumber': presetNumber,
      'duration': duration,
      'additionalParams': additionalParams,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Converte o comando para o payload do protocolo da câmera
  Map<String, dynamic> toProtocolPayload() {
    final payload = <String, dynamic>{
      'Command': action.commandName,
      'Speed': speed.speedValue,
      'Timestamp': timestamp.millisecondsSinceEpoch,
    };

    if (direction != null) {
      payload['Direction'] = direction!.directionCode;
    }

    if (presetNumber != null) {
      payload['PresetNumber'] = presetNumber;
    }

    if (duration != null) {
      payload['Duration'] = duration;
    }

    if (additionalParams != null) {
      payload.addAll(additionalParams!);
    }

    return payload;
  }

  /// Cria comando de movimento
  static PTZCommand move({
    required String cameraId,
    required PTZDirection direction,
    PTZSpeed speed = PTZSpeed.medium,
    int? duration,
  }) {
    return PTZCommand(
      cameraId: cameraId,
      action: PTZAction.move,
      direction: direction,
      speed: speed,
      duration: duration,
    );
  }

  /// Cria comando de zoom
  static PTZCommand zoom({
    required String cameraId,
    required PTZDirection direction, // zoomIn ou zoomOut
    PTZSpeed speed = PTZSpeed.medium,
    int? duration,
  }) {
    assert(direction.isZoom, 'Direction must be zoomIn or zoomOut');
    return PTZCommand(
      cameraId: cameraId,
      action: PTZAction.zoom,
      direction: direction,
      speed: speed,
      duration: duration,
    );
  }

  /// Cria comando de parada
  static PTZCommand stop({
    required String cameraId,
  }) {
    return PTZCommand(
      cameraId: cameraId,
      action: PTZAction.stop,
      direction: PTZDirection.stop,
    );
  }

  /// Cria comando de preset
  static PTZCommand preset({
    required String cameraId,
    required int presetNumber,
  }) {
    return PTZCommand(
      cameraId: cameraId,
      action: PTZAction.preset,
      presetNumber: presetNumber,
    );
  }

  /// Cria comando de foco
  static PTZCommand focus({
    required String cameraId,
    required PTZDirection direction, // focusNear ou focusFar
    PTZSpeed speed = PTZSpeed.medium,
    int? duration,
  }) {
    assert(direction.isFocus, 'Direction must be focusNear or focusFar');
    return PTZCommand(
      cameraId: cameraId,
      action: PTZAction.focus,
      direction: direction,
      speed: speed,
      duration: duration,
    );
  }

  /// Cria comando de auto scan
  static PTZCommand autoScan({
    required String cameraId,
    Map<String, dynamic>? scanParams,
  }) {
    return PTZCommand(
      cameraId: cameraId,
      action: PTZAction.autoScan,
      additionalParams: scanParams,
    );
  }

  PTZCommand copyWith({
    String? cameraId,
    PTZAction? action,
    PTZDirection? direction,
    PTZSpeed? speed,
    int? presetNumber,
    int? duration,
    Map<String, dynamic>? additionalParams,
    DateTime? timestamp,
  }) {
    return PTZCommand(
      cameraId: cameraId ?? this.cameraId,
      action: action ?? this.action,
      direction: direction ?? this.direction,
      speed: speed ?? this.speed,
      presetNumber: presetNumber ?? this.presetNumber,
      duration: duration ?? this.duration,
      additionalParams: additionalParams ?? this.additionalParams,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'PTZCommand(camera: $cameraId, action: ${action.name}, direction: ${direction?.name}, speed: ${speed.name})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PTZCommand &&
        other.cameraId == cameraId &&
        other.action == action &&
        other.direction == direction &&
        other.speed == speed &&
        other.presetNumber == presetNumber;
  }

  @override
  int get hashCode {
    return Object.hash(
      cameraId,
      action,
      direction,
      speed,
      presetNumber,
    );
  }
}