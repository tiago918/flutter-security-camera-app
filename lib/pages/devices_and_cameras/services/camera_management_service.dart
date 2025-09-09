import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/camera_models.dart';
import '../../../services/ptz_service.dart';
import '../../../services/audio_service.dart';
import 'package:video_player/video_player.dart';

class CameraManagementService {
  final PTZService _ptzService;
  final AudioService _audioService;
  final Function(NotificationData) _showNotification;
  final VoidCallback _setState;
  final Map<int, VideoPlayerController?> _videoControllers;
  final Map<int, bool> _audioMuted;
  final Function(int) _stopVideoPlayer;

  CameraManagementService({
    required PTZService ptzService,
    required AudioService audioService,
    required Function(NotificationData) showNotification,
    required VoidCallback setState,
    required Map<int, VideoPlayerController?> videoControllers,
    required Map<int, bool> audioMuted,
    required Function(int) stopVideoPlayer,
  }) : _ptzService = ptzService,
       _audioService = audioService,
       _showNotification = showNotification,
       _setState = setState,
       _videoControllers = videoControllers,
       _audioMuted = audioMuted,
       _stopVideoPlayer = stopVideoPlayer;

  /// Persiste a lista de câmeras no SharedPreferences
  Future<void> persistCameras(List<CameraData> cameras) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = cameras.map((c) => c.toJson()).toList();
      await prefs.setString('cameras', json.encode(data));
    } catch (e) {
      // ignore
    }
  }

  /// Remove uma câmera da lista
  void removeCamera(List<CameraData> cameras, int cameraId) {
    cameras.removeWhere((c) => c.id == cameraId);
    _stopVideoPlayer(cameraId);
    persistCameras(cameras);
    _setState();
  }

  /// Adiciona um dispositivo descoberto como câmera
  Future<void> addDiscoveredAsCamera(dynamic m, Function showOnvifCredentialsDialog) async {
    // Solicita credenciais para o dispositivo ONVIF
    await showOnvifCredentialsDialog(m['name'] ?? 'Dispositivo ONVIF');
  }

  /// Executa comandos PTZ/Zoom via serviço ONVIF
  Future<void> executePtzCommand(CameraData camera, String command) async {
    try {
      final hasCreds = (camera.username?.isNotEmpty == true) && (camera.password?.isNotEmpty == true);
      if (camera.capabilities?.hasPTZ != true && !hasCreds) {
        _showNotification(
          NotificationData(
            cameraId: camera.id,
            message: '${camera.name}: PTZ indisponível. Adicione usuário e senha ONVIF nas configurações.',
            time: 'agora',
            statusColor: Colors.orange,
          ),
        );
        return;
      }
      final ok = await _ptzService.executePtzCommand(camera, command);
      if (!ok) {
        _showNotification(
          NotificationData(
            cameraId: camera.id,
            message: '${camera.name}: Falha ao executar PTZ (${command.toLowerCase()}).',
            time: 'agora',
            statusColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      _showNotification(
        NotificationData(
          cameraId: camera.id,
          message: '${camera.name}: Erro PTZ (${command.toLowerCase()}).',
          time: 'agora',
          statusColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Alterna mute/unmute do áudio do player associado
  Future<void> toggleMute(CameraData camera) async {
    final controller = _videoControllers[camera.id];
    final ok = await _audioService.toggleMute(controller);
    if (ok) {
      _audioMuted[camera.id] = (controller?.value.volume == 0.0);
      _showNotification(
        NotificationData(
          cameraId: camera.id,
          message: '${camera.name}: Áudio ${_audioMuted[camera.id] == true ? 'desativado' : 'ativado'}.',
          time: 'agora',
          statusColor: Colors.green,
        ),
      );
    } else {
      _showNotification(
        NotificationData(
          cameraId: camera.id,
          message: '${camera.name}: Não foi possível alternar o áudio.',
          time: 'agora',
          statusColor: Colors.redAccent,
        ),
      );
    }
    _setState();
  }

  /// Formata timestamp para exibição
  String formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 1) {
      return 'agora';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}min atrás';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h atrás';
    } else {
      return '${diff.inDays}d atrás';
    }
  }

  /// Obtém cor da notificação baseada no tipo
  Color getNotificationColor(String type) {
    switch (type) {
      case 'person_detected':
        return Colors.red;
      case 'motion_detected':
        return Colors.orange;
      case 'recording_started':
        return Colors.green;
      case 'recording_stopped':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}