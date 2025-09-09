import 'package:flutter/material.dart';
import '../models/notification_model.dart';

class NotificationPanel extends StatelessWidget {
  final List<CameraNotification> notifications;
  final Function(CameraNotification) onNotificationTap;
  final Function(String) onNotificationDismiss;

  const NotificationPanel({
    super.key,
    required this.notifications,
    required this.onNotificationTap,
    required this.onNotificationDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Notificações',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
          ),
          
          // Lista de notificações
          Expanded(
            child: notifications.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return _buildNotificationItem(context, notification);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 48,
            color: Colors.grey,
          ),
          SizedBox(height: 8),
          Text(
            'Nenhuma notificação',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(BuildContext context, CameraNotification notification) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(
            color: Color(0xFF4CAF50),
            width: 3,
          ),
        ),
      ),
      child: InkWell(
        onTap: () => onNotificationTap(notification),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          notification.cameraName ?? 'camera 1',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatTimestamp(notification.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(CameraNotification notification) {
    IconData iconData;
    Color iconColor;

    switch (notification.type) {
      case NotificationType.motion:
        iconData = Icons.directions_run;
        iconColor = Colors.orange;
        break;
      case NotificationType.recording:
        iconData = Icons.fiber_manual_record;
        iconColor = Colors.red;
        break;
      case NotificationType.connection:
        iconData = Icons.wifi_off;
        iconColor = Colors.blue;
        break;
      case NotificationType.system:
        iconData = Icons.settings;
        iconColor = Colors.grey;
        break;
      case NotificationType.alert:
        iconData = Icons.warning;
        iconColor = Colors.red;
        break;
      case NotificationType.info:
        iconData = Icons.info;
        iconColor = Colors.blue;
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        iconData,
        size: 20,
        color: iconColor,
      ),
    );
  }

  Color _getPriorityColor(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.low:
        return Colors.green;
      case NotificationPriority.medium:
        return Colors.orange;
      case NotificationPriority.high:
        return Colors.red;
      case NotificationPriority.critical:
        return Colors.purple;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Agora';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m atrás';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h atrás';
    } else {
      return '${difference.inDays}d atrás';
    }
  }
}