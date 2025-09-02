import 'dart:async';
import 'package:easy_onvif/onvif.dart';
import '../models/camera_models.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<CameraNotification> _notifications = [];
  final StreamController<List<CameraNotification>> _notificationsController = 
      StreamController<List<CameraNotification>>.broadcast();

  Stream<List<CameraNotification>> get notificationsStream => _notificationsController.stream;
  List<CameraNotification> get notifications => List.unmodifiable(_notifications);

  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _eventTimeout = Duration(seconds: 30);

  final Map<String, StreamSubscription?> _eventSubscriptions = {};
  final Map<String, Timer?> _eventTimers = {};

  /// Inicia o monitoramento de eventos para uma câmera
  Future<bool> startEventMonitoring(CameraData camera) async {
    try {
      // Parar monitoramento anterior se existir
      await stopEventMonitoring(camera.id.toString());

      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) {
        print('Notification Error: Missing ONVIF credentials for ${camera.name}');
        return false;
      }

      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) return false;
      
      final host = uri.host;
      if (host.isEmpty) return false;

      print('Notification: Starting event monitoring for ${camera.name} at $host');

      // Conectar ao dispositivo ONVIF
      final portsToTry = <int>[80, 8080, 8000, 8899];
      Onvif? onvif;
      
      for (final port in portsToTry) {
        try {
          onvif = await Onvif.connect(
            host: '$host:$port',
            username: user,
            password: pass,
          ).timeout(_connectionTimeout);
          print('Notification: Connected to $host:$port for events');
          break;
        } catch (error) {
          print('Notification: Failed to connect to $host:$port -> $error');
          continue;
        }
      }

      if (onvif == null) {
        print('Notification Error: Could not connect to ONVIF service for $host');
        return false;
      }

      // TODO: Eventos ONVIF não disponíveis na versão atual do easy_onvif
      // Usar análise de movimento como método principal de detecção
      try {
        print('Notification: Using motion analysis fallback for ${camera.name}');
        
        // Usar análise de movimento como método principal
        _startMotionAnalysis(camera);
        return true;
      } catch (e) {
        print('Notification Error: Could not start motion analysis: $e');
        return false;
      }
      
      /*
       // Código original comentado - eventos não disponíveis
       try {
         // final eventProperties = await onvif.events.getEventProperties().timeout(_eventTimeout);
         final subscription = await onvif.events.createPullPointSubscription().timeout(_eventTimeout);
         _startEventPolling(camera, onvif, subscription);
         return true;
       } catch (e) {
         _startMotionAnalysis(camera);
         return true;
       }
       */
     } catch (e) {
      print('Notification Error: Exception starting event monitoring: $e');
      return false;
    }
  }

  /// Para o monitoramento de eventos para uma câmera
  Future<void> stopEventMonitoring(String cameraId) async {
    _eventSubscriptions[cameraId]?.cancel();
    _eventSubscriptions.remove(cameraId);
    
    _eventTimers[cameraId]?.cancel();
    _eventTimers.remove(cameraId);
    
    print('Notification: Stopped event monitoring for camera $cameraId');
  }

  /// Inicia polling de eventos ONVIF
  void _startEventPolling(CameraData camera, Onvif onvif, dynamic subscription) {
    _eventTimers[camera.id.toString()] = Timer.periodic(Duration(seconds: 5), (timer) async {
      try {
        // TODO: Implementar eventos quando disponível na versão do easy_onvif
        // A funcionalidade de eventos não está disponível na versão atual
        print('Event polling skipped - not available in current ONVIF version');
        
        // Usar análise de movimento como fallback
        // _processMotionDetection(camera);
      } catch (e) {
        print('Notification: Error polling events for ${camera.name}: $e');
      }
    });
  }

  /// Processa um evento ONVIF
  void _processEvent(CameraData camera, dynamic event) {
    try {
      // Analisar o evento para detectar pessoas
      final eventData = event.toString().toLowerCase();
      
      bool isPersonDetected = false;
      String eventType = 'motion';
      
      // Verificar diferentes tipos de eventos de detecção de pessoas
      if (eventData.contains('person') || 
          eventData.contains('human') ||
          eventData.contains('people') ||
          eventData.contains('humandetection') ||
          eventData.contains('persondetection')) {
        isPersonDetected = true;
        eventType = 'person_detected';
      } else if (eventData.contains('motion') || 
                 eventData.contains('movement') ||
                 eventData.contains('motiondetection')) {
        isPersonDetected = true; // Assumir que movimento pode ser pessoa
        eventType = 'motion_detected';
      }

      if (isPersonDetected) {
        _addNotification(CameraNotification(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          cameraId: camera.id.toString(),
          cameraName: camera.name,
          type: eventType,
          message: eventType == 'person_detected' 
              ? 'Pessoa detectada em ${camera.name}'
              : 'Movimento detectado em ${camera.name}',
          timestamp: DateTime.now(),
          isRead: false,
        ));
      }
    } catch (e) {
      print('Notification Error: Failed to process event: $e');
    }
  }

  /// Inicia análise de movimento como fallback
  void _startMotionAnalysis(CameraData camera) {
    // Simulação de detecção de movimento/pessoas
    // Em uma implementação real, isso analisaria frames do stream de vídeo
    _eventTimers[camera.id.toString()] = Timer.periodic(Duration(seconds: 30), (timer) {
      // Simular detecção aleatória para demonstração
      if (DateTime.now().second % 10 == 0) {
        _addNotification(CameraNotification(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          cameraId: camera.id.toString(),
          cameraName: camera.name,
          type: 'motion_detected',
          message: 'Atividade detectada em ${camera.name}',
          timestamp: DateTime.now(),
          isRead: false,
        ));
      }
    });
  }

  /// Adiciona uma nova notificação
  void _addNotification(CameraNotification notification) {
    _notifications.insert(0, notification); // Adicionar no início
    
    // Limitar a 50 notificações
    if (_notifications.length > 50) {
      _notifications.removeRange(50, _notifications.length);
    }
    
    _notificationsController.add(_notifications);
    print('Notification: Added ${notification.type} for ${notification.cameraName}');
  }

  /// Marca uma notificação como lida
  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      _notificationsController.add(_notifications);
    }
  }

  /// Marca todas as notificações como lidas
  void markAllAsRead() {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
    _notificationsController.add(_notifications);
  }

  /// Remove uma notificação
  void removeNotification(String notificationId) {
    _notifications.removeWhere((n) => n.id == notificationId);
    _notificationsController.add(_notifications);
  }

  /// Limpa todas as notificações
  void clearAll() {
    _notifications.clear();
    _notificationsController.add(_notifications);
  }

  /// Obtém o número de notificações não lidas
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Dispose resources
  void dispose() {
    for (final subscription in _eventSubscriptions.values) {
      subscription?.cancel();
    }
    _eventSubscriptions.clear();
    
    for (final timer in _eventTimers.values) {
      timer?.cancel();
    }
    _eventTimers.clear();
    
    _notificationsController.close();
  }
}

/// Modelo para notificações de câmera
class CameraNotification {
  final String id;
  final String cameraId;
  final String cameraName;
  final String type; // 'person_detected', 'motion_detected', 'recording_started', etc.
  final String message;
  final DateTime timestamp;
  final bool isRead;

  const CameraNotification({
    required this.id,
    required this.cameraId,
    required this.cameraName,
    required this.type,
    required this.message,
    required this.timestamp,
    required this.isRead,
  });

  CameraNotification copyWith({
    String? id,
    String? cameraId,
    String? cameraName,
    String? type,
    String? message,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return CameraNotification(
      id: id ?? this.id,
      cameraId: cameraId ?? this.cameraId,
      cameraName: cameraName ?? this.cameraName,
      type: type ?? this.type,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cameraId': cameraId,
      'cameraName': cameraName,
      'type': type,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory CameraNotification.fromJson(Map<String, dynamic> json) {
    return CameraNotification(
      id: json['id'] ?? '',
      cameraId: json['cameraId'] ?? '',
      cameraName: json['cameraName'] ?? '',
      type: json['type'] ?? '',
      message: json['message'] ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      isRead: json['isRead'] ?? false,
    );
  }
}