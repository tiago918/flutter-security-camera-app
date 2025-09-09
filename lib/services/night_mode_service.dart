import 'dart:async';
import '../models/models.dart';
import 'camera_service.dart';

class NightModeService {
  static final NightModeService _instance = NightModeService._internal();
  factory NightModeService() => _instance;
  NightModeService._internal();

  final CameraService _cameraService = CameraService();
  final Map<String, NightModeConfig> _configs = {};
  final Map<String, bool> _nightModeStates = {};
  final Map<String, Timer?> _autoModeTimers = {};
  final Map<String, StreamController<NightModeEvent>> _eventStreams = {};
  final Map<String, double?> _lightSensorValues = {};

  /// Configura modo noturno para uma câmera
  Future<bool> configureNightMode(
    String cameraId,
    NightModeConfig config,
  ) async {
    if (!_cameraService.isConnected(cameraId)) {
      print('Câmera $cameraId não está conectada');
      return false;
    }

    try {
      final command = {
        'Command': 'SET_NIGHT_MODE_CONFIG',
        'Mode': config.mode.name,
        'AutoSwitchEnabled': config.autoSwitchEnabled,
        'LightThreshold': config.lightThreshold,
        'SwitchDelay': config.switchDelay.inSeconds,
        'IRLedEnabled': config.irLedEnabled,
        'IRLedIntensity': config.irLedIntensity,
        'ColorToMonoThreshold': config.colorToMonoThreshold,
        'MonoToColorThreshold': config.monoToColorThreshold,
        'Schedule': config.schedule?.map((schedule) => {
          'startTime': schedule.startTime,
          'endTime': schedule.endTime,
          'enabled': schedule.enabled,
        }).toList(),
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        _configs[cameraId] = config;
        
        if (config.autoSwitchEnabled) {
          _startAutoModeMonitoring(cameraId);
        } else {
          _stopAutoModeMonitoring(cameraId);
        }
        
        print('Modo noturno configurado para câmera $cameraId');
        return true;
      } else {
        print('Falha ao configurar modo noturno: ${response?['Error'] ?? 'Erro desconhecido'}');
        return false;
      }
    } catch (e) {
      print('Erro ao configurar modo noturno para câmera $cameraId: $e');
      return false;
    }
  }

  /// Ativa modo noturno manualmente
  Future<bool> enableNightMode(String cameraId) async {
    return await _setNightMode(cameraId, true);
  }

  /// Desativa modo noturno manualmente
  Future<bool> disableNightMode(String cameraId) async {
    return await _setNightMode(cameraId, false);
  }

  /// Define estado do modo noturno
  Future<bool> _setNightMode(String cameraId, bool enabled) async {
    if (!_cameraService.isConnected(cameraId)) {
      print('Câmera $cameraId não está conectada');
      return false;
    }

    try {
      final command = {
        'Command': 'SET_NIGHT_MODE',
        'Enabled': enabled,
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        final previousState = _nightModeStates[cameraId] ?? false;
        _nightModeStates[cameraId] = enabled;
        
        // Emite evento de mudança
        _emitNightModeEvent(cameraId, NightModeEvent(
          cameraId: cameraId,
          timestamp: DateTime.now(),
          enabled: enabled,
          trigger: NightModeTrigger.manual,
          previousState: previousState,
        ));
        
        print('Modo noturno ${enabled ? 'ativado' : 'desativado'} para câmera $cameraId');
        return true;
      } else {
        print('Falha ao definir modo noturno: ${response?['Error'] ?? 'Erro desconhecido'}');
        return false;
      }
    } catch (e) {
      print('Erro ao definir modo noturno para câmera $cameraId: $e');
      return false;
    }
  }

  /// Alterna modo noturno
  Future<bool> toggleNightMode(String cameraId) async {
    final currentState = _nightModeStates[cameraId] ?? false;
    return await _setNightMode(cameraId, !currentState);
  }

  /// Inicia monitoramento automático do modo noturno
  void _startAutoModeMonitoring(String cameraId) {
    // Para timer anterior se existir
    _autoModeTimers[cameraId]?.cancel();
    
    // Cria stream de eventos se não existir
    if (_eventStreams[cameraId] == null) {
      _eventStreams[cameraId] = StreamController<NightModeEvent>.broadcast();
    }

    // Inicia monitoramento periódico
    _autoModeTimers[cameraId] = Timer.periodic(
      const Duration(seconds: 30),
      (timer) => _checkAutoModeConditions(cameraId),
    );

    print('Monitoramento automático do modo noturno iniciado para câmera $cameraId');
  }

  /// Para monitoramento automático do modo noturno
  void _stopAutoModeMonitoring(String cameraId) {
    _autoModeTimers[cameraId]?.cancel();
    _autoModeTimers.remove(cameraId);
    print('Monitoramento automático do modo noturno parado para câmera $cameraId');
  }

  /// Verifica condições para mudança automática do modo noturno
  Future<void> _checkAutoModeConditions(String cameraId) async {
    final config = _configs[cameraId];
    if (config == null || !config.autoSwitchEnabled) return;

    try {
      // Obtém valor do sensor de luz
      final lightValue = await _getLightSensorValue(cameraId);
      if (lightValue == null) return;

      _lightSensorValues[cameraId] = lightValue;
      final currentNightMode = _nightModeStates[cameraId] ?? false;
      bool shouldEnableNightMode = false;
      NightModeTrigger trigger = NightModeTrigger.lightSensor;

      // Verifica condições baseadas no modo configurado
      switch (config.mode) {
        case NightModeType.auto:
          // Baseado no sensor de luz
          if (!currentNightMode && lightValue < config.colorToMonoThreshold) {
            shouldEnableNightMode = true;
          } else if (currentNightMode && lightValue > config.monoToColorThreshold) {
            shouldEnableNightMode = false;
          } else {
            return; // Sem mudança necessária
          }
          break;
          
        case NightModeType.scheduled:
          // Baseado no agendamento
          final shouldBeNightMode = _shouldBeNightModeBySchedule(config);
          if (shouldBeNightMode != currentNightMode) {
            shouldEnableNightMode = shouldBeNightMode;
            trigger = NightModeTrigger.schedule;
          } else {
            return; // Sem mudança necessária
          }
          break;
          
        case NightModeType.manual:
          return; // Não faz mudanças automáticas
      }

      // Aplica delay se configurado
      if (config.switchDelay.inSeconds > 0) {
        await Future.delayed(config.switchDelay);
        
        // Verifica novamente após o delay
        final newLightValue = await _getLightSensorValue(cameraId);
        if (newLightValue == null) return;
        
        // Confirma se ainda deve fazer a mudança
        if (config.mode == NightModeType.auto) {
          if (shouldEnableNightMode && newLightValue >= config.colorToMonoThreshold) {
            return; // Condição mudou durante o delay
          }
          if (!shouldEnableNightMode && newLightValue <= config.monoToColorThreshold) {
            return; // Condição mudou durante o delay
          }
        }
      }

      // Executa mudança
      final success = await _setNightMode(cameraId, shouldEnableNightMode);
      if (success) {
        _emitNightModeEvent(cameraId, NightModeEvent(
          cameraId: cameraId,
          timestamp: DateTime.now(),
          enabled: shouldEnableNightMode,
          trigger: trigger,
          previousState: currentNightMode,
          lightValue: lightValue,
        ));
      }
    } catch (e) {
      print('Erro ao verificar condições do modo noturno para câmera $cameraId: $e');
    }
  }

  /// Obtém valor do sensor de luz
  Future<double?> _getLightSensorValue(String cameraId) async {
    try {
      final command = {
        'Command': 'GET_LIGHT_SENSOR',
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        return (response['LightValue'] ?? 0.0).toDouble();
      }
    } catch (e) {
      print('Erro ao obter valor do sensor de luz para câmera $cameraId: $e');
    }
    
    return null;
  }

  /// Verifica se deve estar em modo noturno baseado no agendamento
  bool _shouldBeNightModeBySchedule(NightModeConfig config) {
    if (config.schedule == null || config.schedule!.isEmpty) {
      return false;
    }

    final now = DateTime.now();
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    
    for (final schedule in config.schedule!) {
      if (!schedule.enabled) continue;
      
      // Verifica se está dentro do horário agendado
      if (_isTimeInRange(currentTime, schedule.startTime, schedule.endTime)) {
        return true;
      }
    }
    
    return false;
  }

  /// Verifica se um horário está dentro de um intervalo
  bool _isTimeInRange(String currentTime, String startTime, String endTime) {
    final current = _timeToMinutes(currentTime);
    final start = _timeToMinutes(startTime);
    final end = _timeToMinutes(endTime);
    
    if (start <= end) {
      // Mesmo dia
      return current >= start && current <= end;
    } else {
      // Atravessa meia-noite
      return current >= start || current <= end;
    }
  }

  /// Converte horário para minutos desde meia-noite
  int _timeToMinutes(String time) {
    final parts = time.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    return hours * 60 + minutes;
  }

  /// Emite evento de modo noturno
  void _emitNightModeEvent(String cameraId, NightModeEvent event) {
    _eventStreams[cameraId]?.add(event);
  }

  /// Configura intensidade do LED IR
  Future<bool> setIRLedIntensity(String cameraId, int intensity) async {
    if (intensity < 0 || intensity > 100) {
      print('Intensidade do LED IR deve estar entre 0 e 100');
      return false;
    }

    try {
      final command = {
        'Command': 'SET_IR_LED_INTENSITY',
        'Intensity': intensity,
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      
      if (response != null && response['Ret'] == 100) {
        // Atualiza configuração local
        final config = _configs[cameraId];
        if (config != null) {
          _configs[cameraId] = config.copyWith(irLedIntensity: intensity);
        }
        
        print('Intensidade do LED IR definida para $intensity% na câmera $cameraId');
        return true;
      }
    } catch (e) {
      print('Erro ao definir intensidade do LED IR para câmera $cameraId: $e');
    }
    
    return false;
  }

  /// Obtém configuração atual do modo noturno
  NightModeConfig? getNightModeConfig(String cameraId) {
    return _configs[cameraId];
  }

  /// Verifica se modo noturno está ativo
  bool isNightModeActive(String cameraId) {
    return _nightModeStates[cameraId] ?? false;
  }

  /// Obtém valor atual do sensor de luz
  double? getCurrentLightValue(String cameraId) {
    return _lightSensorValues[cameraId];
  }

  /// Obtém stream de eventos do modo noturno
  Stream<NightModeEvent>? getNightModeEventStream(String cameraId) {
    return _eventStreams[cameraId]?.stream;
  }

  /// Obtém status do modo noturno
  Map<String, dynamic> getNightModeStatus(String cameraId) {
    final config = _configs[cameraId];
    final isActive = isNightModeActive(cameraId);
    final lightValue = getCurrentLightValue(cameraId);
    final hasAutoMode = _autoModeTimers[cameraId] != null;
    
    return {
      'active': isActive,
      'mode': config?.mode.name ?? 'manual',
      'autoSwitchEnabled': config?.autoSwitchEnabled ?? false,
      'autoModeRunning': hasAutoMode,
      'lightValue': lightValue,
      'lightThreshold': config?.lightThreshold ?? 50.0,
      'irLedEnabled': config?.irLedEnabled ?? true,
      'irLedIntensity': config?.irLedIntensity ?? 80,
      'switchDelay': config?.switchDelay.inSeconds ?? 0,
    };
  }

  /// Testa modo noturno
  Future<bool> testNightMode(String cameraId) async {
    print('Testando modo noturno para câmera $cameraId');
    
    // Ativa modo noturno
    final enableResult = await enableNightMode(cameraId);
    if (!enableResult) return false;
    
    await Future.delayed(const Duration(seconds: 2));
    
    // Desativa modo noturno
    final disableResult = await disableNightMode(cameraId);
    
    print('Teste do modo noturno ${enableResult && disableResult ? 'bem-sucedido' : 'falhou'}');
    return enableResult && disableResult;
  }

  /// Calibra sensor de luz
  Future<bool> calibrateLightSensor(String cameraId) async {
    try {
      final command = {
        'Command': 'CALIBRATE_LIGHT_SENSOR',
        'Timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await _cameraService.sendCommand(cameraId, command);
      return response != null && response['Ret'] == 100;
    } catch (e) {
      print('Erro ao calibrar sensor de luz para câmera $cameraId: $e');
      return false;
    }
  }

  /// Dispose do serviço
  void dispose() {
    // Para todos os timers
    for (final timer in _autoModeTimers.values) {
      timer?.cancel();
    }
    _autoModeTimers.clear();
    
    // Fecha todos os streams
    for (final stream in _eventStreams.values) {
      stream.close();
    }
    _eventStreams.clear();
    
    _configs.clear();
    _nightModeStates.clear();
    _lightSensorValues.clear();
  }
}

/// Enums e classes para modo noturno
enum NightModeType {
  manual,
  auto,
  scheduled,
}

enum NightModeTrigger {
  manual,
  lightSensor,
  schedule,
  api,
}

/// Classe para configuração do modo noturno
class NightModeConfig {
  final NightModeType mode;
  final bool autoSwitchEnabled;
  final double lightThreshold;
  final Duration switchDelay;
  final bool irLedEnabled;
  final int irLedIntensity; // 0-100
  final double colorToMonoThreshold;
  final double monoToColorThreshold;
  final List<NightModeSchedule>? schedule;

  const NightModeConfig({
    required this.mode,
    required this.autoSwitchEnabled,
    this.lightThreshold = 50.0,
    this.switchDelay = const Duration(seconds: 5),
    this.irLedEnabled = true,
    this.irLedIntensity = 80,
    this.colorToMonoThreshold = 30.0,
    this.monoToColorThreshold = 70.0,
    this.schedule,
  });

  NightModeConfig copyWith({
    NightModeType? mode,
    bool? autoSwitchEnabled,
    double? lightThreshold,
    Duration? switchDelay,
    bool? irLedEnabled,
    int? irLedIntensity,
    double? colorToMonoThreshold,
    double? monoToColorThreshold,
    List<NightModeSchedule>? schedule,
  }) {
    return NightModeConfig(
      mode: mode ?? this.mode,
      autoSwitchEnabled: autoSwitchEnabled ?? this.autoSwitchEnabled,
      lightThreshold: lightThreshold ?? this.lightThreshold,
      switchDelay: switchDelay ?? this.switchDelay,
      irLedEnabled: irLedEnabled ?? this.irLedEnabled,
      irLedIntensity: irLedIntensity ?? this.irLedIntensity,
      colorToMonoThreshold: colorToMonoThreshold ?? this.colorToMonoThreshold,
      monoToColorThreshold: monoToColorThreshold ?? this.monoToColorThreshold,
      schedule: schedule ?? this.schedule,
    );
  }
}

/// Classe para agendamento do modo noturno
class NightModeSchedule {
  final String startTime; // HH:mm
  final String endTime; // HH:mm
  final bool enabled;

  const NightModeSchedule({
    required this.startTime,
    required this.endTime,
    this.enabled = true,
  });
}

/// Classe para evento do modo noturno
class NightModeEvent {
  final String cameraId;
  final DateTime timestamp;
  final bool enabled;
  final NightModeTrigger trigger;
  final bool previousState;
  final double? lightValue;

  const NightModeEvent({
    required this.cameraId,
    required this.timestamp,
    required this.enabled,
    required this.trigger,
    required this.previousState,
    this.lightValue,
  });
}