import 'dart:async';
import 'package:video_player/video_player.dart';

class CameraStateService {
  static final CameraStateService _instance = CameraStateService._internal();
  factory CameraStateService() => _instance;
  CameraStateService._internal();

  // Controladores de vídeo por câmera
  final Map<String, VideoPlayerController> _videoControllers = {};
  
  // Estados de reprodução por câmera
  final Map<String, bool> _isPlaying = {};
  
  // Estados de carregamento por câmera
  final Map<String, bool> _isLoading = {};
  
  // Estados de erro por câmera
  final Map<String, String?> _errors = {};
  
  // Estados de conexão por câmera
  final Map<String, bool> _isConnected = {};
  
  // Estados de gravação por câmera
  final Map<String, bool> _isRecording = {};
  
  // Estados de detecção de movimento por câmera
  final Map<String, bool> _motionDetectionEnabled = {};
  
  // Estados de notificação por câmera
  final Map<String, bool> _notificationsEnabled = {};
  
  // Estados de e-mail de alerta por câmera
  final Map<String, bool> _emailAlertsEnabled = {};
  
  // Streams para notificar mudanças de estado
  final StreamController<String> _stateChangedController = StreamController<String>.broadcast();
  
  Stream<String> get stateChanged => _stateChangedController.stream;
  
  // Callback para notificar mudanças de estado
  Function(String cameraId)? onStateChanged;

  // Getters para controladores de vídeo
  VideoPlayerController? getVideoController(String cameraId) {
    return _videoControllers[cameraId];
  }

  // Setters e getters para estados de reprodução
  bool isPlaying(String cameraId) => _isPlaying[cameraId] ?? false;
  
  void setPlaying(String cameraId, bool playing) {
    _isPlaying[cameraId] = playing;
    _notifyStateChanged(cameraId);
  }

  // Setters e getters para estados de carregamento
  bool isLoading(String cameraId) => _isLoading[cameraId] ?? false;
  
  void setLoading(String cameraId, bool loading) {
    _isLoading[cameraId] = loading;
    _notifyStateChanged(cameraId);
  }

  // Setters e getters para estados de erro
  String? getError(String cameraId) => _errors[cameraId];
  
  void setError(String cameraId, String? error) {
    _errors[cameraId] = error;
    _notifyStateChanged(cameraId);
  }

  // Setters e getters para estados de conexão
  bool isConnected(String cameraId) => _isConnected[cameraId] ?? false;
  
  void setConnected(String cameraId, bool connected) {
    _isConnected[cameraId] = connected;
    _notifyStateChanged(cameraId);
  }

  // Setters e getters para estados de gravação
  bool isRecording(String cameraId) => _isRecording[cameraId] ?? false;
  
  void setRecording(String cameraId, bool recording) {
    _isRecording[cameraId] = recording;
    _notifyStateChanged(cameraId);
  }

  // Setters e getters para detecção de movimento
  bool isMotionDetectionEnabled(String cameraId) => _motionDetectionEnabled[cameraId] ?? false;
  
  void setMotionDetectionEnabled(String cameraId, bool enabled) {
    _motionDetectionEnabled[cameraId] = enabled;
    _notifyStateChanged(cameraId);
  }

  // Setters e getters para notificações
  bool areNotificationsEnabled(String cameraId) => _notificationsEnabled[cameraId] ?? false;
  
  void setNotificationsEnabled(String cameraId, bool enabled) {
    _notificationsEnabled[cameraId] = enabled;
    _notifyStateChanged(cameraId);
  }

  // Setters e getters para e-mail de alerta
  bool areEmailAlertsEnabled(String cameraId) => _emailAlertsEnabled[cameraId] ?? false;
  
  void setEmailAlertsEnabled(String cameraId, bool enabled) {
    _emailAlertsEnabled[cameraId] = enabled;
    _notifyStateChanged(cameraId);
  }

  // Inicializar estado básico de uma câmera
  void initializeCamera(String cameraId) {
    // Inicializar estados padrão para a câmera
    _isPlaying[cameraId] = false;
    _isLoading[cameraId] = false;
    _errors[cameraId] = null;
    _isConnected[cameraId] = false;
    _isRecording[cameraId] = false;
    _motionDetectionEnabled[cameraId] = false;
    _notificationsEnabled[cameraId] = true;
    _emailAlertsEnabled[cameraId] = false;
    _notifyStateChanged(cameraId);
  }

  // Gerenciamento de controladores de vídeo
  Future<void> initializeVideoController(String cameraId, String streamUrl) async {
    // Dispose do controlador anterior se existir
    await disposeVideoController(cameraId);
    
    try {
      setLoading(cameraId, true);
      setError(cameraId, null);
      
      final controller = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
      _videoControllers[cameraId] = controller;
      
      await controller.initialize();
      setConnected(cameraId, true);
      setLoading(cameraId, false);
      
    } catch (e) {
      setError(cameraId, 'Erro ao inicializar vídeo: $e');
      setConnected(cameraId, false);
      setLoading(cameraId, false);
    }
  }

  Future<void> playVideo(String cameraId) async {
    final controller = _videoControllers[cameraId];
    if (controller != null && controller.value.isInitialized) {
      await controller.play();
      setPlaying(cameraId, true);
    }
  }

  Future<void> pauseVideo(String cameraId) async {
    final controller = _videoControllers[cameraId];
    if (controller != null && controller.value.isInitialized) {
      await controller.pause();
      setPlaying(cameraId, false);
    }
  }

  Future<void> disposeVideoController(String cameraId) async {
    final controller = _videoControllers[cameraId];
    if (controller != null) {
      await controller.dispose();
      _videoControllers.remove(cameraId);
      setPlaying(cameraId, false);
      setConnected(cameraId, false);
    }
  }

  // Método para dispose completo de uma câmera (controlador + estado)
  Future<void> disposeCamera(String cameraId) async {
    await disposeVideoController(cameraId);
    clearCameraState(cameraId);
  }

  // Limpar estado de uma câmera específica
  void clearCameraState(String cameraId) {
    _isPlaying.remove(cameraId);
    _isLoading.remove(cameraId);
    _errors.remove(cameraId);
    _isConnected.remove(cameraId);
    _isRecording.remove(cameraId);
    _motionDetectionEnabled.remove(cameraId);
    _notificationsEnabled.remove(cameraId);
    _emailAlertsEnabled.remove(cameraId);
    _notifyStateChanged(cameraId);
  }

  // Limpar todos os estados
  void clearAllStates() {
    _isPlaying.clear();
    _isLoading.clear();
    _errors.clear();
    _isConnected.clear();
    _isRecording.clear();
    _motionDetectionEnabled.clear();
    _notificationsEnabled.clear();
    _emailAlertsEnabled.clear();
  }

  // Dispose de todos os controladores
  Future<void> disposeAllControllers() async {
    final controllers = List<VideoPlayerController>.from(_videoControllers.values);
    _videoControllers.clear();
    
    for (final controller in controllers) {
      await controller.dispose();
    }
    
    clearAllStates();
  }

  // Obter resumo do estado de uma câmera
  CameraState getCameraState(String cameraId) {
    return CameraState(
      cameraId: cameraId,
      isPlaying: isPlaying(cameraId),
      isLoading: isLoading(cameraId),
      error: getError(cameraId),
      isConnected: isConnected(cameraId),
      isRecording: isRecording(cameraId),
      motionDetectionEnabled: isMotionDetectionEnabled(cameraId),
      notificationsEnabled: areNotificationsEnabled(cameraId),
      emailAlertsEnabled: areEmailAlertsEnabled(cameraId),
    );
  }

  // Notificar mudança de estado
  void _notifyStateChanged(String cameraId) {
    _stateChangedController.add(cameraId);
    onStateChanged?.call(cameraId);
  }

  // Dispose do serviço
  void dispose() {
    _stateChangedController.close();
    onStateChanged = null;
    disposeAllControllers();
  }
}

/// Classe para representar o estado completo de uma câmera
class CameraState {
  final String cameraId;
  final bool isPlaying;
  final bool isLoading;
  final String? error;
  final bool isConnected;
  final bool isRecording;
  final bool motionDetectionEnabled;
  final bool notificationsEnabled;
  final bool emailAlertsEnabled;

  CameraState({
    required this.cameraId,
    required this.isPlaying,
    required this.isLoading,
    this.error,
    required this.isConnected,
    required this.isRecording,
    required this.motionDetectionEnabled,
    required this.notificationsEnabled,
    required this.emailAlertsEnabled,
  });

  @override
  String toString() {
    return 'CameraState(cameraId: $cameraId, isPlaying: $isPlaying, isLoading: $isLoading, error: $error, isConnected: $isConnected, isRecording: $isRecording, motionDetectionEnabled: $motionDetectionEnabled, notificationsEnabled: $notificationsEnabled, emailAlertsEnabled: $emailAlertsEnabled)';
  }
}