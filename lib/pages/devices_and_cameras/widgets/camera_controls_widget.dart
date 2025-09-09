import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../models/camera_models.dart';

class CameraControlsWidget extends StatelessWidget {
  final CameraData camera;
  final VideoPlayerController? controller;
  final Map<int, bool> audioMuted;
  final Map<int, bool> motionDetectionEnabled;
  final Map<int, bool> nightModeEnabled;
  final Map<int, bool> notificationsEnabled;
  final Function(CameraData) onShowPTZControls;
  final Function(CameraData) onToggleMute;
  final Function(CameraData) onShowMotionDetectionSettings;
  final Function(CameraData) onShowNightModeSettings;
  final Function(CameraData) onShowAutoRecordingSettings;
  final Function(CameraData) onShowNotificationSettings;
  final Function(CameraData) onShowSDCardRecordings;
  final VoidCallback onShowUnsupportedFeatureMessage;

  const CameraControlsWidget({
    Key? key,
    required this.camera,
    this.controller,
    required this.audioMuted,
    required this.motionDetectionEnabled,
    required this.nightModeEnabled,
    required this.notificationsEnabled,
    required this.onShowPTZControls,
    required this.onToggleMute,
    required this.onShowMotionDetectionSettings,
    required this.onShowNightModeSettings,
    required this.onShowAutoRecordingSettings,
    required this.onShowNotificationSettings,
    required this.onShowSDCardRecordings,
    required this.onShowUnsupportedFeatureMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasVideo = controller?.value.isInitialized ?? false;
    
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Controle PTZ/Zoom
            _buildControlIcon(
              icon: Icons.control_camera,
              isSupported: (camera.capabilities?.hasPTZ == true) || ((camera.username?.isNotEmpty == true) && (camera.password?.isNotEmpty == true)),
              onTap: () => onShowPTZControls(camera),
            ),
            const SizedBox(width: 12),
            // Controle de Áudio
            _buildControlIcon(
              icon: audioMuted[camera.id] == true ? Icons.volume_off : Icons.volume_up,
              isSupported: hasVideo,
              onTap: () => onToggleMute(camera),
            ),
            const SizedBox(width: 12),
            // Detecção de Movimento
            _buildControlIcon(
              icon: motionDetectionEnabled[camera.id] == true ? Icons.motion_photos_on : Icons.motion_photos_off,
              isSupported: camera.capabilities?.hasMotionDetection == true,
              onTap: () => onShowMotionDetectionSettings(camera),
            ),
            const SizedBox(width: 12),
            // Modo Noturno
            _buildControlIcon(
              icon: (nightModeEnabled[camera.id] ?? false) ? Icons.nightlight : Icons.nightlight_outlined,
              isSupported: camera.capabilities?.hasNightVision == true,
              onTap: () => onShowNightModeSettings(camera),
            ),
            const SizedBox(width: 12),
            // Gravação Automática
            _buildControlIcon(
              icon: Icons.smart_display,
              isSupported: true, // Sempre disponível
              onTap: () => onShowAutoRecordingSettings(camera),
            ),
            const SizedBox(width: 12),
            // Notificações
            _buildControlIcon(
              icon: (notificationsEnabled[camera.id] ?? true) ? Icons.notifications : Icons.notifications_off,
              isSupported: camera.capabilities?.hasNotifications == true,
              onTap: () => onShowNotificationSettings(camera),
            ),
            const SizedBox(width: 12),
            // Cartão SD - Gravações
            _buildControlIcon(
              icon: Icons.sd_card,
              isSupported: camera.capabilities?.hasPlayback == true || camera.capabilities?.hasRecordingSearch == true,
              onTap: () => onShowSDCardRecordings(camera),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlIcon({
    required IconData icon,
    required bool isSupported,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isSupported ? onTap : onShowUnsupportedFeatureMessage,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSupported
               ? Colors.white.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isSupported ? Colors.white : Colors.grey[400],
          size: 16,
        ),
      ),
    );
  }
}