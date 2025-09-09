import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/services.dart';

class NotificationWidget extends StatefulWidget {
  final CameraNotification notification;
  final Color? customColor;
  final VoidCallback? onDismiss;
  final VoidCallback? onTap;
  final bool showCameraName;
  final bool isCompact;

  const NotificationWidget({
    Key? key,
    required this.notification,
    this.customColor,
    this.onDismiss,
    this.onTap,
    this.showCameraName = true,
    this.isCompact = false,
  }) : super(key: key);

  @override
  State<NotificationWidget> createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<NotificationWidget>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_fadeController);
    
    // Anima entrada
    _slideController.forward();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Dismissible(
          key: Key('notification_${widget.notification.id}'),
          direction: DismissDirection.endToStart,
          onDismissed: _handleDismiss,
          background: _buildDismissBackground(),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: _getBackgroundColor(),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getBorderColor(),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _getBorderColor().withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: widget.isCompact
                  ? _buildCompactContent()
                  : _buildFullContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactContent() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _buildIcon(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showCameraName) ..[
                  Text(
                    widget.notification.cameraName ?? 'Câmera Desconhecida',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  widget.notification.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _buildTimestamp(),
          if (widget.onDismiss != null) ..[
            const SizedBox(width: 8),
            _buildDismissButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildFullContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho
          Row(
            children: [
              _buildIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showCameraName) ..[
                      Text(
                        widget.notification.cameraName ?? 'Câmera Desconhecida',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getBorderColor(),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      widget.notification.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _buildTimestamp(),
              if (widget.onDismiss != null) ..[
                const SizedBox(width: 8),
                _buildDismissButton(),
              ],
            ],
          ),
          
          // Conteúdo
          if (widget.notification.message.isNotEmpty) ..[
            const SizedBox(height: 8),
            Text(
              widget.notification.message,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
          
          // Metadados adicionais
          if (widget.notification.metadata.isNotEmpty) ..[
            const SizedBox(height: 8),
            _buildMetadata(),
          ],
        ],
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _getBorderColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _getNotificationIcon(),
        color: _getBorderColor(),
        size: widget.isCompact ? 16 : 20,
      ),
    );
  }

  Widget _buildTimestamp() {
    return Text(
      _formatTimestamp(widget.notification.timestamp),
      style: TextStyle(
        fontSize: widget.isCompact ? 10 : 12,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildDismissButton() {
    return GestureDetector(
      onTap: _handleDismiss,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.close,
          size: widget.isCompact ? 14 : 16,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildMetadata() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: widget.notification.metadata.entries.map((entry) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${entry.key}: ${entry.value}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDismissBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      color: Colors.red,
      child: const Icon(
        Icons.delete,
        color: Colors.white,
      ),
    );
  }

  Color _getBackgroundColor() {
    if (widget.customColor != null) {
      return widget.customColor!.withOpacity(0.05);
    }
    
    switch (widget.notification.priority) {
      case NotificationPriority.critical:
        return Colors.red.withOpacity(0.05);
      case NotificationPriority.high:
        return Colors.orange.withOpacity(0.05);
      case NotificationPriority.medium:
        return Colors.blue.withOpacity(0.05);
      case NotificationPriority.low:
        return Colors.grey.withOpacity(0.05);
    }
  }

  Color _getBorderColor() {
    if (widget.customColor != null) {
      return widget.customColor!;
    }
    
    switch (widget.notification.priority) {
      case NotificationPriority.critical:
        return Colors.red;
      case NotificationPriority.high:
        return Colors.orange;
      case NotificationPriority.medium:
        return Colors.blue;
      case NotificationPriority.low:
        return Colors.grey;
    }
  }

  IconData _getNotificationIcon() {
    switch (widget.notification.type) {
      case NotificationType.motionDetected:
        return Icons.directions_run;
      case NotificationType.connectionLost:
        return Icons.wifi_off;
      case NotificationType.connectionRestored:
        return Icons.wifi;
      case NotificationType.recordingStarted:
        return Icons.fiber_manual_record;
      case NotificationType.recordingStopped:
        return Icons.stop;
      case NotificationType.storageWarning:
        return Icons.storage;
      case NotificationType.systemError:
        return Icons.error;
      case NotificationType.nightModeEnabled:
        return Icons.nights_stay;
      case NotificationType.nightModeDisabled:
        return Icons.wb_sunny;
      case NotificationType.audioDetected:
        return Icons.volume_up;
      case NotificationType.tamperingDetected:
        return Icons.security;
      case NotificationType.firmwareUpdate:
        return Icons.system_update;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Agora';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }

  void _handleDismiss([DismissDirection? direction]) {
    setState(() {
      _isDismissed = true;
    });
    
    _slideController.reverse().then((_) {
      widget.onDismiss?.call();
    });
  }
}

/// Widget para lista de notificações organizadas por câmera
class NotificationsList extends StatefulWidget {
  final List<CameraNotification> notifications;
  final Map<String, Color>? cameraColors;
  final Function(CameraNotification)? onNotificationTap;
  final Function(CameraNotification)? onNotificationDismiss;
  final bool groupByCamera;
  final bool isCompact;
  final ScrollController? scrollController;

  const NotificationsList({
    Key? key,
    required this.notifications,
    this.cameraColors,
    this.onNotificationTap,
    this.onNotificationDismiss,
    this.groupByCamera = true,
    this.isCompact = false,
    this.scrollController,
  }) : super(key: key);

  @override
  State<NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends State<NotificationsList> {
  late List<CameraNotification> _notifications;
  Map<String, List<CameraNotification>> _groupedNotifications = {};

  @override
  void initState() {
    super.initState();
    _notifications = List.from(widget.notifications);
    _groupNotifications();
  }

  @override
  void didUpdateWidget(NotificationsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notifications != oldWidget.notifications) {
      _notifications = List.from(widget.notifications);
      _groupNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notifications.isEmpty) {
      return _buildEmptyState();
    }

    return widget.groupByCamera
        ? _buildGroupedList()
        : _buildSimpleList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: Colors.grey.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma notificação',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'As notificações das câmeras aparecerão aqui',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleList() {
    return ListView.builder(
      controller: widget.scrollController,
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return NotificationWidget(
          notification: notification,
          customColor: widget.cameraColors?[notification.cameraId],
          onTap: () => widget.onNotificationTap?.call(notification),
          onDismiss: () => _handleDismiss(notification),
          showCameraName: true,
          isCompact: widget.isCompact,
        );
      },
    );
  }

  Widget _buildGroupedList() {
    return ListView.builder(
      controller: widget.scrollController,
      itemCount: _groupedNotifications.length,
      itemBuilder: (context, index) {
        final cameraId = _groupedNotifications.keys.elementAt(index);
        final notifications = _groupedNotifications[cameraId]!;
        final cameraName = notifications.first.cameraName ?? 'Câmera Desconhecida';
        final cameraColor = widget.cameraColors?[cameraId];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho do grupo
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: cameraColor ?? Colors.blue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cameraName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (cameraColor ?? Colors.blue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${notifications.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cameraColor ?? Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Notificações do grupo
            ...notifications.map((notification) {
              return NotificationWidget(
                notification: notification,
                customColor: cameraColor,
                onTap: () => widget.onNotificationTap?.call(notification),
                onDismiss: () => _handleDismiss(notification),
                showCameraName: false,
                isCompact: widget.isCompact,
              );
            }).toList(),
            
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  void _groupNotifications() {
    _groupedNotifications.clear();
    
    for (final notification in _notifications) {
      if (!_groupedNotifications.containsKey(notification.cameraId)) {
        _groupedNotifications[notification.cameraId] = [];
      }
      _groupedNotifications[notification.cameraId]!.add(notification);
    }
    
    // Ordena notificações dentro de cada grupo por timestamp (mais recente primeiro)
    for (final notifications in _groupedNotifications.values) {
      notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
  }

  void _handleDismiss(CameraNotification notification) {
    setState(() {
      _notifications.removeWhere((n) => n.id == notification.id);
      _groupNotifications();
    });
    
    widget.onNotificationDismiss?.call(notification);
  }
}