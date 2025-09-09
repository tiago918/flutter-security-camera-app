import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_model.dart';


/// Serviço para gerenciar notificações do sistema de câmeras
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<CameraNotification> _notifications = [];
  final Map<String, Color> _cameraColors = {};
  final StreamController<List<CameraNotification>> _notificationsController =
      StreamController<List<CameraNotification>>.broadcast();
  final StreamController<CameraNotification> _newNotificationController =
      StreamController<CameraNotification>.broadcast();

  // Configurações
  int _maxNotifications = 100;
  Duration _autoCleanupDuration = const Duration(hours: 24);
  bool _enableAutoCleanup = true;
  Map<NotificationType, bool> _enabledTypes = {
    for (var type in NotificationType.values) type: true,
  };
  Map<NotificationPriority, bool> _enabledPriorities = {
    for (var priority in NotificationPriority.values) priority: true,
  };

  Timer? _cleanupTimer;

  // Configurações de estado
  bool _isEnabled = true;

  // Getters
  List<CameraNotification> get notifications => List.unmodifiable(_notifications);
  Stream<List<CameraNotification>> get notificationsStream => _notificationsController.stream;
  Stream<CameraNotification> get newNotificationStream => _newNotificationController.stream;
  Map<String, Color> get cameraColors => Map.unmodifiable(_cameraColors);
  bool get isEnabled => _isEnabled;
  Map<NotificationType, bool> get enabledTypes => Map.unmodifiable(_enabledTypes);
  Map<NotificationPriority, bool> get enabledPriorities => Map.unmodifiable(_enabledPriorities);

  // Método getNotifications
  List<CameraNotification> getNotifications() {
    return List.unmodifiable(_notifications);
  }

  // Setter para callback de notificação adicionada
  set onNotificationAdded(Function(CameraNotification)? callback) {
    // Implementação do setter
  }

  /// Inicializa o serviço de notificações
  void initialize() {
    _startAutoCleanup();
    debugPrint('NotificationService initialized');
  }

  /// Adiciona uma nova notificação
  void addNotification(CameraNotification notification) {
    // Verifica se o tipo e prioridade estão habilitados
    if (!_enabledTypes[notification.type]! || 
        !_enabledPriorities[notification.priority]!) {
      return;
    }

    // Remove notificações antigas se necessário
    if (_notifications.length >= _maxNotifications) {
      _notifications.removeAt(0);
    }

    // Adiciona a nova notificação
    _notifications.add(notification);
    
    // Ordena por timestamp (mais recente primeiro)
    _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Notifica os ouvintes
    _notificationsController.add(List.unmodifiable(_notifications));
    _newNotificationController.add(notification);

    debugPrint('Notification added: ${notification.title} for camera ${notification.cameraName}');
  }

  /// Remove uma notificação específica
  void removeNotification(String notificationId) {
    _notifications.removeWhere((n) => n.id == notificationId);
    _notificationsController.add(List.unmodifiable(_notifications));
  }

  /// Remove todas as notificações de uma câmera específica
  void removeNotificationsForCamera(String cameraId) {
    _notifications.removeWhere((n) => n.cameraId == cameraId);
    _notificationsController.add(List.unmodifiable(_notifications));
  }

  /// Remove todas as notificações
  void clearAllNotifications() {
    _notifications.clear();
    _notificationsController.add(List.unmodifiable(_notifications));
  }

  /// Remove todas as notificações (alias para clearAllNotifications)
  void clearAll() {
    clearAllNotifications();
  }

  /// Define se as notificações estão habilitadas
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Define se um tipo específico de notificação está habilitado
  void setTypeEnabled(NotificationType type, bool enabled) {
    _enabledTypes[type] = enabled;
  }

  /// Define se uma prioridade específica de notificação está habilitada
  void setPriorityEnabled(NotificationPriority priority, bool enabled) {
    _enabledPriorities[priority] = enabled;
  }

  /// Remove notificações por tipo
  void removeNotificationsByType(NotificationType type) {
    _notifications.removeWhere((n) => n.type == type);
    _notificationsController.add(List.unmodifiable(_notifications));
  }

  /// Remove notificações por prioridade
  void removeNotificationsByPriority(NotificationPriority priority) {
    _notifications.removeWhere((n) => n.priority == priority);
    _notificationsController.add(List.unmodifiable(_notifications));
  }

  /// Obtém notificações de uma câmera específica
  List<CameraNotification> getNotificationsForCamera(String cameraId) {
    return _notifications.where((n) => n.cameraId == cameraId).toList();
  }

  /// Obtém notificações por tipo
  List<CameraNotification> getNotificationsByType(NotificationType type) {
    return _notifications.where((n) => n.type == type).toList();
  }

  /// Obtém notificações por prioridade
  List<CameraNotification> getNotificationsByPriority(NotificationPriority priority) {
    return _notifications.where((n) => n.priority == priority).toList();
  }

  /// Obtém contagem de notificações não lidas por câmera
  Map<String, int> getUnreadCountByCamera() {
    final Map<String, int> counts = {};
    for (final notification in _notifications) {
      if (!notification.isRead) {
        final cameraId = notification.cameraId;
        if (cameraId != null) {
          counts[cameraId] = (counts[cameraId] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  /// Marca uma notificação como lida
  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      _notificationsController.add(List.unmodifiable(_notifications));
    }
  }

  /// Marca todas as notificações como lidas
  void markAllAsRead() {
    for (int i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    }
    _notificationsController.add(List.unmodifiable(_notifications));
  }

  /// Marca todas as notificações de uma câmera como lidas
  void markCameraNotificationsAsRead(String cameraId) {
    for (int i = 0; i < _notifications.length; i++) {
      if (_notifications[i].cameraId == cameraId && !_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    }
    _notificationsController.add(List.unmodifiable(_notifications));
  }

  /// Define cor personalizada para uma câmera
  void setCameraColor(String cameraId, Color color) {
    _cameraColors[cameraId] = color;
  }

  /// Remove cor personalizada de uma câmera
  void removeCameraColor(String cameraId) {
    _cameraColors.remove(cameraId);
  }

  /// Obtém cor de uma câmera
  Color? getCameraColor(String cameraId) {
    return _cameraColors[cameraId];
  }

  /// Configura tipos de notificação habilitados
  void setEnabledTypes(Map<NotificationType, bool> enabledTypes) {
    _enabledTypes = Map.from(enabledTypes);
  }

  /// Configura prioridades de notificação habilitadas
  void setEnabledPriorities(Map<NotificationPriority, bool> enabledPriorities) {
    _enabledPriorities = Map.from(enabledPriorities);
  }

  /// Configura número máximo de notificações
  void setMaxNotifications(int maxNotifications) {
    _maxNotifications = maxNotifications;
    
    // Remove notificações antigas se necessário
    while (_notifications.length > _maxNotifications) {
      _notifications.removeAt(0);
    }
    
    _notificationsController.add(List.unmodifiable(_notifications));
  }

  /// Configura limpeza automática
  void setAutoCleanup(bool enabled, [Duration? duration]) {
    _enableAutoCleanup = enabled;
    if (duration != null) {
      _autoCleanupDuration = duration;
    }
    
    if (enabled) {
      _startAutoCleanup();
    } else {
      _stopAutoCleanup();
    }
  }

  /// Inicia limpeza automática
  void _startAutoCleanup() {
    _stopAutoCleanup();
    
    if (_enableAutoCleanup) {
      _cleanupTimer = Timer.periodic(
        const Duration(hours: 1),
        (_) => _performCleanup(),
      );
    }
  }

  /// Para limpeza automática
  void _stopAutoCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// Executa limpeza de notificações antigas
  void _performCleanup() {
    final cutoffTime = DateTime.now().subtract(_autoCleanupDuration);
    final initialCount = _notifications.length;
    
    _notifications.removeWhere((n) => n.timestamp.isBefore(cutoffTime));
    
    final removedCount = initialCount - _notifications.length;
    if (removedCount > 0) {
      _notificationsController.add(List.unmodifiable(_notifications));
      debugPrint('Cleaned up $removedCount old notifications');
    }
  }

  /// Força limpeza manual
  void performManualCleanup() {
    _performCleanup();
  }

  /// Exporta notificações para JSON
  String exportNotifications() {
    final data = {
      'notifications': _notifications.map((n) => n.toJson()).toList(),
      'cameraColors': _cameraColors.map(
        (key, value) => MapEntry(key, value.value),
      ),
      'exportedAt': DateTime.now().toIso8601String(),
    };
    
    return jsonEncode(data);
  }

  /// Importa notificações de JSON
  void importNotifications(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      // Importa notificações
      if (data['notifications'] is List) {
        _notifications.clear();
        for (final notificationData in data['notifications']) {
          try {
            final notification = CameraNotification.fromJson(notificationData);
            _notifications.add(notification);
          } catch (e) {
            debugPrint('Error importing notification: $e');
          }
        }
        
        // Ordena por timestamp
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      
      // Importa cores das câmeras
      if (data['cameraColors'] is Map) {
        _cameraColors.clear();
        final colorsData = data['cameraColors'] as Map<String, dynamic>;
        for (final entry in colorsData.entries) {
          if (entry.value is int) {
            _cameraColors[entry.key] = Color(entry.value);
          }
        }
      }
      
      _notificationsController.add(List.unmodifiable(_notifications));
      debugPrint('Notifications imported successfully');
    } catch (e) {
      debugPrint('Error importing notifications: $e');
      throw Exception('Failed to import notifications: $e');
    }
  }

  /// Obtém estatísticas das notificações
  NotificationStats getStats() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeek = now.subtract(const Duration(days: 7));
    final thisMonth = DateTime(now.year, now.month, 1);
    
    final todayCount = _notifications
        .where((n) => n.timestamp.isAfter(today))
        .length;
    
    final weekCount = _notifications
        .where((n) => n.timestamp.isAfter(thisWeek))
        .length;
    
    final monthCount = _notifications
        .where((n) => n.timestamp.isAfter(thisMonth))
        .length;
    
    final unreadCount = _notifications
        .where((n) => !n.isRead)
        .length;
    
    final typeStats = <NotificationType, int>{};
    final priorityStats = <NotificationPriority, int>{};
    final cameraStats = <String, int>{};
    
    for (final notification in _notifications) {
      typeStats[notification.type] = (typeStats[notification.type] ?? 0) + 1;
      priorityStats[notification.priority] = (priorityStats[notification.priority] ?? 0) + 1;
      final cameraId = notification.cameraId;
      if (cameraId != null) {
        cameraStats[cameraId] = (cameraStats[cameraId] ?? 0) + 1;
      }
    }
    
    return NotificationStats(
      total: _notifications.length,
      unread: unreadCount,
      today: todayCount,
      thisWeek: weekCount,
      thisMonth: monthCount,
      byType: typeStats,
      byPriority: priorityStats,
      byCamera: cameraStats,
    );
  }

  /// Libera recursos
  void dispose() {
    _stopAutoCleanup();
    _notificationsController.close();
    _newNotificationController.close();
    _notifications.clear();
    _cameraColors.clear();
  }

  // Métodos de conveniência para criar notificações específicas
  
  /// Cria notificação de movimento detectado
  void notifyMotionDetected(String cameraId, String cameraName, {Map<String, dynamic>? metadata}) {
    addNotification(CameraNotification.motionDetected(
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata ?? {},
    ));
  }

  /// Cria notificação de conexão perdida
  void notifyConnectionLost(String cameraId, String cameraName, {Map<String, dynamic>? metadata}) {
    addNotification(CameraNotification.connectionLost(
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata ?? {},
    ));
  }

  /// Cria notificação de conexão restaurada
  void notifyConnectionRestored(String cameraId, String cameraName, {Map<String, dynamic>? metadata}) {
    addNotification(CameraNotification.connectionRestored(
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata ?? {},
    ));
  }

  /// Cria notificação de gravação iniciada
  void notifyRecordingStarted(String cameraId, String cameraName, {Map<String, dynamic>? metadata}) {
    addNotification(CameraNotification.recordingStarted(
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata ?? {},
    ));
  }

  /// Cria notificação de gravação parada
  void notifyRecordingStopped(String cameraId, String cameraName, {Map<String, dynamic>? metadata}) {
    addNotification(CameraNotification.recordingStopped(
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata ?? {},
    ));
  }

  /// Cria notificação de aviso de armazenamento
  void notifyStorageWarning(String cameraId, String cameraName, {Map<String, dynamic>? metadata}) {
    addNotification(CameraNotification.storageWarning(
      cameraId: cameraId,
      cameraName: cameraName,
      metadata: metadata ?? {},
    ));
  }

  /// Cria notificação de erro do sistema
  void notifySystemError(String cameraId, String cameraName, String error, {Map<String, dynamic>? metadata}) {
    addNotification(CameraNotification.systemError(
      cameraId: cameraId,
      cameraName: cameraName,
      error: error,
      metadata: metadata ?? {},
    ));
  }
}

/// Classe para estatísticas de notificações
class NotificationStats {
  final int total;
  final int unread;
  final int today;
  final int thisWeek;
  final int thisMonth;
  final Map<NotificationType, int> byType;
  final Map<NotificationPriority, int> byPriority;
  final Map<String, int> byCamera;

  const NotificationStats({
    required this.total,
    required this.unread,
    required this.today,
    required this.thisWeek,
    required this.thisMonth,
    required this.byType,
    required this.byPriority,
    required this.byCamera,
  });
}