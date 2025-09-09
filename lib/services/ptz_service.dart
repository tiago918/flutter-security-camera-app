import 'dart:async';
import '../models/ptz_command.dart';
import '../models/ptz_capabilities.dart';
import 'camera_service.dart';

class PTZService {
  static final PTZService _instance = PTZService._internal();
  factory PTZService() => _instance;
  PTZService._internal();

  final CameraService _cameraService = CameraService();
  final Map<String, bool> _isMoving = {};
  final Map<String, Timer?> _movementTimers = {};
  final Map<String, PTZCapabilities?> _capabilities = {};

  /// Executa comando PTZ
  Future<bool> executePTZCommand(
    String cameraId,
    PTZCommand command,
  ) async {
    if (!_cameraService.isConnected(cameraId)) {
      print('Câmera $cameraId não está conectada');
      return false;
    }

    try {
      final ptzCommand = {
        'Command': 'PTZ_CONTROL',
        'Action': command.action.name,
        'Direction': command.direction?.name,
        'Speed': command.speed.index,
        'PresetNumber': command.presetNumber,
        'ZoomDirection': command.zoomDirection?.index,
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, ptzCommand);
      
      if (response != null && response['Ret'] == 100) {
        _updateMovementState(cameraId, command);
        return true;
      } else {
        print('Falha ao executar comando PTZ: ${response?['Error'] ?? 'Erro desconhecido'}');
        return false;
      }
    } catch (e) {
      print('Erro ao executar comando PTZ para câmera $cameraId: $e');
      return false;
    }
  }

  /// Move a câmera em uma direção específica
  Future<bool> moveCamera(
    String cameraId,
    PTZDirection direction,
    PTZSpeed speed,
  ) async {
    final command = PTZCommand.move(
      cameraId: cameraId,
      direction: direction,
      speed: speed,
    );
    return await executePTZCommand(cameraId, command);
  }

  /// Para o movimento da câmera
  Future<bool> stopMovement(String cameraId) async {
    // Cancela timer de movimento se existir
    _movementTimers[cameraId]?.cancel();
    _movementTimers.remove(cameraId);
    _isMoving[cameraId] = false;

    final command = PTZCommand.stop(cameraId: cameraId);
    return await executePTZCommand(cameraId, command);
  }

  /// Controla zoom da câmera
  Future<bool> zoomCamera(
    String cameraId,
    bool zoomIn,
    PTZSpeed speed,
  ) async {
    final direction = zoomIn ? PTZDirection.zoomIn : PTZDirection.zoomOut;
    final command = PTZCommand.zoom(
      cameraId: cameraId,
      direction: direction,
      speed: speed,
    );
    return await executePTZCommand(cameraId, command);
  }

  /// Controla foco da câmera
  Future<bool> focusCamera(
    String cameraId,
    bool focusNear,
    PTZSpeed speed,
  ) async {
    final direction = focusNear ? PTZDirection.focusNear : PTZDirection.focusFar;
    final command = PTZCommand.focus(
      cameraId: cameraId,
      direction: direction,
      speed: speed,
    );
    return await executePTZCommand(cameraId, command);
  }

  /// Vai para uma posição preset
  Future<bool> gotoPreset(
    String cameraId,
    int presetNumber,
  ) async {
    final command = PTZCommand.preset(
      cameraId: cameraId,
      presetNumber: presetNumber,
    );
    return await executePTZCommand(cameraId, command);
  }

  /// Salva posição atual como preset
  Future<bool> savePreset(
    String cameraId,
    int presetNumber,
  ) async {
    final command = PTZCommand.preset(
      cameraId: cameraId,
      presetNumber: presetNumber,
    );
    return await executePTZCommand(cameraId, command);
  }

  /// Remove um preset
  Future<bool> deletePreset(
    String cameraId,
    int presetNumber,
  ) async {
    final command = PTZCommand.preset(
      cameraId: cameraId,
      presetNumber: presetNumber,
    );
    return await executePTZCommand(cameraId, command);
  }

  /// Inicia auto scan entre dois presets
  Future<bool> startAutoScan(
    String cameraId,
    int startPreset,
    int endPreset,
  ) async {
    final command = PTZCommand.autoScan(
      cameraId: cameraId,
      scanParams: {
        'startPreset': startPreset,
        'endPreset': endPreset,
        'enable': true,
      },
    );
    return await executePTZCommand(cameraId, command);
  }

  /// Para auto scan
  Future<bool> stopAutoScan(String cameraId) async {
    final command = PTZCommand.autoScan(
      cameraId: cameraId,
      scanParams: {
        'enable': false,
      },
    );
    return await executePTZCommand(cameraId, command);
  }

  /// Move a câmera continuamente por um período específico
  Future<bool> moveContinuous(
    String cameraId,
    PTZDirection direction,
    PTZSpeed speed,
    Duration duration,
  ) async {
    // Para movimento anterior se existir
    await stopMovement(cameraId);

    // Inicia movimento
    final success = await moveCamera(cameraId, direction, speed);
    if (!success) return false;

    // Programa parada automática
    _movementTimers[cameraId] = Timer(duration, () {
      stopMovement(cameraId);
    });

    return true;
  }

  /// Executa sequência de movimentos
  Future<bool> executeMovementSequence(
    String cameraId,
    List<PTZMovementStep> steps,
  ) async {
    for (final step in steps) {
      final success = await moveContinuous(
        cameraId,
        step.direction,
        step.speed,
        step.duration,
      );
      
      if (!success) {
        print('Falha ao executar passo da sequência: ${step.direction}');
        return false;
      }

      // Aguarda conclusão do movimento
      await Future.delayed(step.duration);
      
      // Pausa entre movimentos se especificada
      if (step.pauseAfter != null) {
        await Future.delayed(step.pauseAfter!);
      }
    }

    return true;
  }

  /// Obtém capacidades PTZ da câmera
  Future<PTZCapabilities?> getPTZCapabilities(String cameraId) async {
    // Retorna do cache se disponível
    if (_capabilities[cameraId] != null) {
      return _capabilities[cameraId];
    }

    try {
      final command = {
        'Command': 'GET_PTZ_CAPABILITIES',
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        final capabilities = PTZCapabilities(
          supportsPan: response['SupportsPan'] ?? true,
          supportsTilt: response['SupportsTilt'] ?? true,
          supportsZoom: response['SupportsZoom'] ?? true,
          supportsFocus: response['SupportsFocus'] ?? false,
          supportsPresets: response['SupportsPresets'] ?? true,
          supportsAutoScan: response['SupportsAutoScan'] ?? false,
          maxPresets: response['MaxPresets'] ?? 8,
          panRange: (response['PanRange'] as List?)?.cast<double>() ?? [-180.0, 180.0],
          tiltRange: (response['TiltRange'] as List?)?.cast<double>() ?? [-90.0, 90.0],
          zoomRange: (response['ZoomRange'] as List?)?.cast<double>() ?? [1.0, 10.0],
        );
        
        _capabilities[cameraId] = capabilities;
        return capabilities;
      }
    } catch (e) {
      print('Erro ao obter capacidades PTZ da câmera $cameraId: $e');
    }

    // Retorna capacidades padrão se falhar
    final defaultCapabilities = PTZCapabilities(
      supportsPan: true,
      supportsTilt: true,
      supportsZoom: true,
      supportsFocus: false,
      supportsPresets: true,
      supportsAutoScan: false,
      maxPresets: 8,
      panRange: [-180.0, 180.0],
      tiltRange: [-90.0, 90.0],
      zoomRange: [1.0, 10.0],
    );
    
    _capabilities[cameraId] = defaultCapabilities;
    return defaultCapabilities;
  }

  /// Obtém lista de presets salvos
  Future<List<PTZPreset>> getPresets(String cameraId) async {
    try {
      final command = {
        'Command': 'GET_PRESETS',
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        final presetsData = response['Presets'] as List? ?? [];
        return presetsData.map((preset) => PTZPreset(
          number: preset['Number'] ?? 0,
          name: preset['Name'] ?? 'Preset ${preset['Number']}',
          pan: (preset['Pan'] ?? 0.0).toDouble(),
          tilt: (preset['Tilt'] ?? 0.0).toDouble(),
          zoom: (preset['Zoom'] ?? 1.0).toDouble(),
        )).toList();
      }
    } catch (e) {
      print('Erro ao obter presets da câmera $cameraId: $e');
    }

    return [];
  }

  /// Atualiza estado de movimento
  void _updateMovementState(String cameraId, PTZCommand command) {
    switch (command.action) {
      case PTZAction.move:
        _isMoving[cameraId] = true;
        break;
      case PTZAction.stop:
        _isMoving[cameraId] = false;
        _movementTimers[cameraId]?.cancel();
        _movementTimers.remove(cameraId);
        break;
      default:
        break;
    }
  }

  /// Verifica se a câmera está em movimento
  bool isMoving(String cameraId) {
    return _isMoving[cameraId] ?? false;
  }

  /// Obtém status atual do PTZ
  Map<String, dynamic> getPTZStatus(String cameraId) {
    return {
      'isMoving': isMoving(cameraId),
      'hasActiveTimer': _movementTimers[cameraId] != null,
      'capabilities': _capabilities[cameraId]?.toJson(),
    };
  }

  /// Para todos os movimentos de uma câmera
  Future<void> stopAllMovements(String cameraId) async {
    _movementTimers[cameraId]?.cancel();
    _movementTimers.remove(cameraId);
    await stopMovement(cameraId);
    await stopAutoScan(cameraId);
  }

  /// Limpa cache de capacidades
  void clearCapabilitiesCache(String cameraId) {
    _capabilities.remove(cameraId);
  }

  /// Dispose do serviço
  void dispose() {
    // Para todos os timers
    for (final timer in _movementTimers.values) {
      timer?.cancel();
    }
    _movementTimers.clear();
    _isMoving.clear();
    _capabilities.clear();
  }
}

/// Classe para representar um passo de movimento em sequência
class PTZMovementStep {
  final PTZDirection direction;
  final PTZSpeed speed;
  final Duration duration;
  final Duration? pauseAfter;

  const PTZMovementStep({
    required this.direction,
    required this.speed,
    required this.duration,
    this.pauseAfter,
  });
}

/// Classe para representar um preset PTZ
class PTZPreset {
  final int number;
  final String name;
  final double pan;
  final double tilt;
  final double zoom;

  const PTZPreset({
    required this.number,
    required this.name,
    required this.pan,
    required this.tilt,
    required this.zoom,
  });

  Map<String, dynamic> toJson() => {
    'number': number,
    'name': name,
    'pan': pan,
    'tilt': tilt,
    'zoom': zoom,
  };

  factory PTZPreset.fromJson(Map<String, dynamic> json) => PTZPreset(
    number: json['number'] ?? 0,
    name: json['name'] ?? '',
    pan: (json['pan'] ?? 0.0).toDouble(),
    tilt: (json['tilt'] ?? 0.0).toDouble(),
    zoom: (json['zoom'] ?? 1.0).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PTZPreset &&
          runtimeType == other.runtimeType &&
          number == other.number;

  @override
  int get hashCode => number.hashCode;

  @override
  String toString() => 'PTZPreset(number: $number, name: $name)';
}