import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:easy_onvif/onvif.dart';
import 'package:easy_onvif/probe.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_models.dart';
import '../services/onvif_capabilities_service.dart';
import '../services/onvif_ptz_service.dart';
import '../services/audio_service.dart';
import '../services/ptz_favorites_service.dart';
import '../services/night_mode_service.dart';
import '../services/notification_service.dart';
import '../services/recording_service.dart';
import '../services/motion_detection_service.dart';
import '../services/onvif_playback_service.dart';
import '../services/auto_recording_service.dart';
import '../services/video_management_service.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/camera_card_widget.dart';
import 'auto_recording_settings_page.dart';
import 'recorded_videos_page.dart';

// Movido para OnvifCapabilitiesService
Future<CameraCapabilities?> _detectOnvifCapabilities(Onvif onvif) async {
  final service = OnvifCapabilitiesService();
  return service.detect(onvif);
}

class DevicesAndCamerasScreen extends StatefulWidget {
  const DevicesAndCamerasScreen({super.key});

  @override
  State<DevicesAndCamerasScreen> createState() => _DevicesAndCamerasScreenState();
}

class _DevicesAndCamerasScreenState extends State<DevicesAndCamerasScreen> {
  // Lista de câmeras reais (inicialmente vazia)
  final List<CameraData> cameras = [];

  // Lista de notificações (inicialmente vazia, será populada conforme câmeras forem adicionadas)
  final List<NotificationData> notifications = [];

  // Preferência para detecção ONVIF em background
  bool _onvifDetectionEnabled = true;



  // Descoberta ONVIF
  bool _isScanning = false;
  List<dynamic> _discovered = [];
  String? _scanError;

  // Player de vídeo para cada câmera
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Set<int> _loadingVideo = {};

  // Serviços auxiliares
  final OnvifPtzService _ptzService = const OnvifPtzService();
  final AudioService _audioService = const AudioService();
  final PtzFavoritesService _ptzFavoritesService = PtzFavoritesService();
  final NightModeService _nightModeService = const NightModeService();
  final NotificationService _notificationService = NotificationService();
  final RecordingService _recordingService = RecordingService();
  final MotionDetectionService _motionDetectionService = MotionDetectionService();

  final AutoRecordingService _autoRecordingService = AutoRecordingService();
  final VideoManagementService _videoManagementService = VideoManagementService();

  // Health-check e telemetria por câmera
  final Map<int, Timer?> _healthCheckTimers = {};
  final Map<int, Duration> _lastKnownPosition = {};
  final Map<int, DateTime> _lastProgressAt = {};
  final Map<int, int> _bufferingEvents = {};
  final Map<int, int> _errorEvents = {};
  final Map<int, int> _reconnects = {};

  // Estados dos controles por câmera
  final Map<int, bool> _audioMuted = {};
  final Map<int, bool> _motionDetectionEnabled = {};
  final Map<int, bool> _nightModeEnabled = {};
  final Map<int, bool> _irLightEnabled = {};
  final Map<int, bool> _recordingEnabled = {};
  final Map<int, bool> _notificationsEnabled = {};


  // Filtros de busca para gravações do cartão SD
  DateTime? _searchStartDate;
  DateTime? _searchEndDate;

  // Controlador para entrada de IP manual
  final TextEditingController _ipController = TextEditingController();

  // Lista de caminhos RTSP comuns para diferentes fabricantes (priorizando substreams)
  static const List<String> _commonRtspPaths = [
    // Dahua/Hikvision - Substreams (menor latência) primeiro
    '/cam/realmonitor?channel=1&subtype=1', // substream
    '/cam/realmonitor?channel=1&subtype=0', // mainstream
    // Axis - Perfis de menor qualidade primeiro
    '/axis-media/media.amp',
    '/axis-media/media.amp?streamprofile=Mobile',
    '/axis-media/media.amp?streamprofile=Quality',
    // Foscam - Fluxos menores primeiro
    '/videoSub', // substream se disponível
    '/videoMain',
    '/video.cgi',
    // Generic ONVIF - Múltiplos perfis
    '/onvif/media_service/stream_1',
    '/onvif1',
    // TP-Link - Fluxos secundários primeiro
    '/stream2', // substream se disponível
    '/stream1',
    '/stream/1',
    // D-Link - Resoluções menores primeiro
    '/video.cgi?resolution=CIF',
    '/video.cgi?resolution=VGA',
    '/video1.mjpeg',
    // Vivotek
    '/live.sdp',
    // Amcrest
    '/cam/realmonitor?channel=1&subtype=1',
    // Reolink
    '/h264Preview_01_main',
    '/h264Preview_01_sub',
    // Genéricos
    '/',
    '/live',
    '/stream',
    '/media',
    '/video',
    '/mjpeg',
    '/h264',
    '/rtsp',
  ];

  // Codifica credenciais para URL RTSP (escape de caracteres especiais)
  String _encodeCredentials(String username, String password) {
    final encodedUser = Uri.encodeComponent(username);
    final encodedPass = Uri.encodeComponent(password);
    return '$encodedUser:$encodedPass';
  }

  // Mostrar gravações salvas
  void _showSavedRecordings(CameraData camera) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          'Gravações Salvas - ${camera.name}',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: FutureBuilder<List<SavedRecording>>(
            future: _recordingService.getSavedRecordings(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.blue),
                );
              }
              
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Erro ao carregar gravações',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }
              
              final recordings = snapshot.data ?? [];
              
              if (recordings.isEmpty) {
                return const Center(
                  child: Text(
                    'Nenhuma gravação encontrada',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }
              
              return ListView.builder(
                itemCount: recordings.length,
                itemBuilder: (context, index) {
                  final recording = recordings[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.video_file,
                      color: Colors.blue,
                    ),
                    title: Text(
                      recording.filename,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'Duração: ${recording.duration ?? 'N/A'}\nTamanho: ${(recording.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: const Color(0xFF3A3A3A),
                      onSelected: (value) {
                        if (value == 'delete') {
                          _deleteRecording(recording);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Excluir', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Excluir gravação
  void _deleteRecording(SavedRecording recording) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Confirmar Exclusão',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja realmente excluir a gravação "${recording.filename}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              // Implementar exclusão do arquivo
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Fechar também o diálogo de gravações
              _showNotification(
                NotificationData(
                  cameraId: 0, // SavedRecording não tem cameraId
                  message: 'Gravação "${recording.filename}" excluída',
                  time: 'agora',
                  statusColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  // Mostrar diálogo para adicionar área de detecção
  void _showAddDetectionZone(CameraData camera, StateSetter setDialogState) {
    final nameController = TextEditingController();
    bool isExclusionZone = false;
    double sensitivity = 0.5;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setAddDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Adicionar Área de Detecção',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nome da área',
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: 'Ex: Entrada Principal',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text(
                  'Área de exclusão',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Ignorar movimento nesta área',
                  style: TextStyle(color: Colors.white70),
                ),
                value: isExclusionZone,
                onChanged: (value) {
                  setAddDialogState(() {
                    isExclusionZone = value;
                  });
                },
                activeColor: Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                'Sensibilidade: ${(sensitivity * 100).round()}%',
                style: const TextStyle(color: Colors.white),
              ),
              Slider(
                value: sensitivity,
                onChanged: (value) {
                  setAddDialogState(() {
                    sensitivity = value;
                  });
                },
                activeColor: Colors.blue,
                inactiveColor: Colors.white24,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  final newZone = MotionDetectionZone(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: name,
                    points: [
                      const Offset(0.2, 0.2),
                      const Offset(0.8, 0.2),
                      const Offset(0.8, 0.8),
                      const Offset(0.2, 0.8),
                    ],
                    isEnabled: true,
                    isExclusionZone: isExclusionZone,
                    sensitivity: sensitivity,
                  );
                  
                  _motionDetectionService.addDetectionZone(
                    camera.id.toString(),
                    newZone,
                  );
                  
                  Navigator.of(context).pop();
                  
                  setDialogState(() {
                    camera.capabilities?.motionZones.add(newZone);
                  });
                    _showNotification(
                      NotificationData(
                        cameraId: camera.id,
                        message: 'Área "$name" adicionada com sucesso',
                        time: 'agora',
                        statusColor: Colors.green,
                      ),
                    );

                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
  }

  // Configurar sensibilidade geral de movimento
  void _configureMotionSensitivity(CameraData camera, StateSetter setDialogState) {
    double globalSensitivity = 0.7; // Valor padrão
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSensitivityState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Configurar Sensibilidade',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ajuste a sensibilidade geral da detecção de movimento:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              Text(
                'Sensibilidade: ${(globalSensitivity * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Slider(
                value: globalSensitivity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                onChanged: (value) {
                  setSensitivityState(() {
                    globalSensitivity = value;
                  });
                },
                activeColor: Colors.orange,
                inactiveColor: Colors.white24,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Baixa',
                    style: TextStyle(
                      color: globalSensitivity <= 0.3 ? Colors.orange : Colors.white54,
                      fontWeight: globalSensitivity <= 0.3 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Text(
                    'Média',
                    style: TextStyle(
                      color: globalSensitivity > 0.3 && globalSensitivity <= 0.7 ? Colors.orange : Colors.white54,
                      fontWeight: globalSensitivity > 0.3 && globalSensitivity <= 0.7 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Text(
                    'Alta',
                    style: TextStyle(
                      color: globalSensitivity > 0.7 ? Colors.orange : Colors.white54,
                      fontWeight: globalSensitivity > 0.7 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                final config = MotionDetectionConfig(
                  cameraId: camera.id.toString(),
                  enabled: _motionDetectionEnabled[camera.id] ?? false,
                  sensitivity: (globalSensitivity * 100).round(),
                  humanDetectionOnly: true,
                  minObjectSize: 0.1,
                  maxObjectSize: 1.0,
                  zones: camera.capabilities?.motionZones ?? [],
                );
                
                final success = await _motionDetectionService.configureMotionDetection(
                  camera,
                  config,
                );
                
                Navigator.of(context).pop();
                
                if (success) {
                  _showNotification(
                    NotificationData(
                      cameraId: camera.id,
                      message: 'Sensibilidade configurada para ${(globalSensitivity * 100).round()}%',
                      time: 'agora',
                      statusColor: Colors.green,
                    ),
                  );
                } else {
                  _showNotification(
                    NotificationData(
                      cameraId: camera.id,
                      message: 'Erro ao configurar sensibilidade',
                      time: 'agora',
                      statusColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // fvp.registerWith() já foi chamado em main.dart com opções específicas
    
    // Configurar listener para notificações de eventos
    _notificationService.notificationsStream.listen((cameraNotifications) {
      if (mounted) {
        // Converter notificações de câmera para NotificationData
        for (final cameraNotif in cameraNotifications) {
          if (!cameraNotif.isRead) {
            _showNotification(
              NotificationData(
                cameraId: int.tryParse(cameraNotif.cameraId) ?? 0,
                message: cameraNotif.message,
                time: _formatTime(cameraNotif.timestamp),
                statusColor: _getNotificationColor(cameraNotif.type),
              ),
            );
            // Marcar como lida para evitar duplicatas
            _notificationService.markAsRead(cameraNotif.id);
          }
        }
      }
    });
    
    // Adia a carga das câmeras para depois do primeiro frame, garantindo que a UI inicial renderize primeiro
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        // Carrega preferência de detecção ONVIF em background
        try {
          final prefs = await SharedPreferences.getInstance();
          setState(() {
            _onvifDetectionEnabled = prefs.getBool('onvif_detection_enabled') ?? true;
          });
        } catch (_) {}
        _loadPersistedCameras();
      }
    });
  }

  @override
  void dispose() {
    _ipController.dispose();

    // Parar monitoramento de eventos para todas as câmeras
    for (final camera in cameras) {
      _notificationService.stopEventMonitoring(camera.id.toString());
    }

    // Cancela todos os timers de health-check
    for (final t in _healthCheckTimers.values) {
      t?.cancel();
    }
    _healthCheckTimers.clear();

    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // Converte mensagens de erro técnicas em descrições amigáveis ao usuário
  String _friendlyPlaybackError(Object e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('401') || msg.contains('unauthorized') || msg.contains('403') || msg.contains('auth')) {
      return 'Credenciais inválidas ou acesso negado (verifique usuário/senha).';
    }
    if (msg.contains('404') || msg.contains('not found') || msg.contains('notfound')) {
      return 'Caminho RTSP incorreto ou stream inexistente.';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'Tempo de conexão esgotado. A câmera pode estar offline ou a rede instável.';
    }
    if (msg.contains('host lookup') || msg.contains('failed host lookup') || msg.contains('dns') || msg.contains('name lookup')) {
      return 'Falha de DNS/host. Verifique o endereço IP ou nome do host.';
    }
    if (msg.contains('connection refused') || msg.contains('refused')) {
      return 'Conexão recusada. Verifique a porta (RTSP geralmente 554) e se o serviço RTSP está habilitado.';
    }
    if (msg.contains('handshake') || msg.contains('tls') || msg.contains('ssl')) {
      return 'Falha no handshake TLS/SSL. Prefira rtsp:// (não TLS) e a porta correta.';
    }
    if (msg.contains('unsupported') || msg.contains('format') || msg.contains('codec')) {
      return 'Formato/codec não suportado pelo player. Tente usar o substream em H.264.';
    }
    if (msg.contains('network') || msg.contains('i/o error')) {
      return 'Erro de rede ao acessar o stream. Verifique a conexão.';
    }

    return 'Erro ao reproduzir o stream.'; // fallback genérico
  }

  Future<void> _runAndSaveCapabilitiesDetection(int cameraId, Onvif onvif) async {
    try {
      final caps = await _detectOnvifCapabilities(onvif).timeout(const Duration(seconds: 15));
      if (caps == null) return;
      final idx = cameras.indexWhere((c) => c.id == cameraId);
      if (idx == -1) return;
      setState(() {
        final current = cameras[idx];
        cameras[idx] = CameraData(
          id: current.id,
          name: current.name,
          isLive: current.isLive,
          statusColor: current.statusColor,
          uniqueColor: current.uniqueColor,
          icon: current.icon,
          streamUrl: current.streamUrl,
          username: current.username,
          password: current.password,
          port: current.port,
          transport: current.transport,
          capabilities: caps,
        );
      });
      _persistCameras();
      // DEBUG: Capacidades ONVIF detectadas e salvas para câmera $cameraId
    } catch (e) {
      // DEBUG: Falha ao detectar capacidades ONVIF: $e
    }
  }

  Future<void> _initializeVideoPlayer(CameraData camera) async {
    setState(() {
      _loadingVideo.add(camera.id);
    });

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(camera.streamUrl));
      await controller.initialize();
      
      // Conecta proativamente o serviço PTZ
      final ptzService = OnvifPtzService();
      await ptzService.connect(camera);

      // Log da razão de aspecto real do stream
      try {
        final ar = controller.value.aspectRatio;
        String label = '';
        const candidates = {
          '16:9': 16 / 9,
          '4:3': 4 / 3,
          '1:1': 1.0,
          '3:2': 3 / 2,
          '16:10': 16 / 10,
          '5:4': 5 / 4,
        };
        double bestDiff = 999;
        String bestKey = '';
        for (final e in candidates.entries) {
          final diff = (ar - e.value).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            bestKey = e.key;
          }
        }
        final approx = bestDiff < 0.03 ? bestKey : '${ar.toStringAsFixed(3)}:1';
        // DEBUG: "${camera.name}" aspectRatio=$ar (~$approx)
      } catch (_) {}

      // Inicializa métricas
      _bufferingEvents[camera.id] = _bufferingEvents[camera.id] ?? 0;
      _errorEvents[camera.id] = _errorEvents[camera.id] ?? 0;
      _reconnects[camera.id] = _reconnects[camera.id] ?? 0;
      _lastKnownPosition[camera.id] = Duration.zero;
      _lastProgressAt[camera.id] = DateTime.now();

      // Listener para telemetria e progresso
      controller.addListener(() {
        final value = controller.value;
        if (value.isBuffering) {
          _bufferingEvents[camera.id] = (_bufferingEvents[camera.id] ?? 0) + 1;
        }
        // Atualiza progresso
        final pos = value.position;
        if (pos != _lastKnownPosition[camera.id]) {
          _lastKnownPosition[camera.id] = pos;
          _lastProgressAt[camera.id] = DateTime.now();
        }
        // Erros
        if (value.hasError) {
          _errorEvents[camera.id] = (_errorEvents[camera.id] ?? 0) + 1;
        }
      });

      // Health-check periódico
      _healthCheckTimers[camera.id]?.cancel();
      _healthCheckTimers[camera.id] = Timer.periodic(const Duration(seconds: 2), (t) async {
        final ctrl = _videoControllers[camera.id];
        if (ctrl == null) return;
        final v = ctrl.value;
        final stalledByTime = DateTime.now().difference(_lastProgressAt[camera.id] ?? DateTime.now()) > const Duration(seconds: 5);
        final stalledByBuffer = v.isBuffering && stalledByTime;

        if (!v.isInitialized || v.hasError || stalledByBuffer) {
          try {
            await ctrl.play();
          } catch (_) {}
          // Se continuar ruim após tentar play, reinicializa
          if (!v.isInitialized || v.hasError || DateTime.now().difference(_lastProgressAt[camera.id] ?? DateTime.now()) > const Duration(seconds: 8)) {
            _reconnects[camera.id] = (_reconnects[camera.id] ?? 0) + 1;
            _stopVideoPlayer(camera.id);
            _initializeVideoPlayer(camera);
          }
        }
      });

      if (mounted) {
        setState(() {
          _videoControllers[camera.id] = controller;
          _loadingVideo.remove(camera.id);
        });
        controller.play();
        
        // Atualiza status para online se o player inicializou
        _updateCameraStatus(camera.id, isLive: true, statusColor: const Color(0xFF4CAF50));
      }
    } catch (e) {
      final friendly = _friendlyPlaybackError(e);
      if (mounted) {
        setState(() {
          _loadingVideo.remove(camera.id);
        });
        // Atualiza status para offline
        _updateCameraStatus(camera.id, isLive: false, statusColor: const Color(0xFFFF5722));
        
        // Mostrar notificação de erro
        _showNotification(
          NotificationData(
            cameraId: camera.id,
            message: '${camera.name}: $friendly',
            time: 'agora',
            statusColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _stopVideoPlayer(int cameraId) {
    final controller = _videoControllers[cameraId];
    if (controller != null) {
      controller.dispose();
      setState(() {
        _videoControllers.remove(cameraId);
      });
    }
  }

  Future<void> _loadPersistedCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cameras');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> data = json.decode(jsonStr);
        final loaded = data.map((e) => CameraData.fromJson(Map<String, dynamic>.from(e))).toList();
        setState(() {
          cameras.clear();
          cameras.addAll(loaded);
        });
        // Após carregar, inicia o streaming de forma escalonada para evitar picos de CPU
        const int baseDelayMs = 200; // leve atraso inicial para não competir com o build
        const int stepDelayMs = 400; // atraso incremental entre câmeras
        final toInit = List<CameraData>.from(loaded);
        for (var i = 0; i < toInit.length; i++) {
          final cam = toInit[i];
          final delay = Duration(milliseconds: baseDelayMs + i * stepDelayMs);
          Future.delayed(delay, () => _initializeVideoPlayer(cam));
          
          // Iniciar monitoramento de eventos para detecção de pessoas
          final eventDelay = Duration(milliseconds: baseDelayMs + 1000 + i * stepDelayMs);
          Future.delayed(eventDelay, () async {
            try {
              final success = await _notificationService.startEventMonitoring(cam);
              if (success) {
                print('Event monitoring started for ${cam.name}');
              }
            } catch (e) {
              print('Failed to start event monitoring for ${cam.name}: $e');
            }
          });
        }

        // Dispara detecção de capacidades via ONVIF em background para câmeras sem capacidades
        try {
          if (_onvifDetectionEnabled) {
            final camsNeedingCaps = toInit.where((c) => c.capabilities == null).toList();
            const int detectBaseMs = 500; // atraso base para começar detecções
            const int detectStepMs = 600; // atraso incremental para cada câmera
            for (var i = 0; i < camsNeedingCaps.length; i++) {
              final cam = camsNeedingCaps[i];
              final host = Uri.tryParse(cam.streamUrl)?.host ?? '';
              final user = cam.username ?? '';
              final pass = cam.password ?? '';
              if (host.isEmpty || user.isEmpty || pass.isEmpty) continue; // precisa de host e credenciais
              final delay = Duration(milliseconds: detectBaseMs + i * detectStepMs);
              Future.delayed(delay, () async {
                final ports = <int>[80, 8080, 8000, 8899];
                for (final p in ports) {
                  try {
                    final onvif = await Onvif.connect(
                      host: '$host:$p',
                      username: user,
                      password: pass,
                    ).timeout(const Duration(seconds: 6));
                    if (_onvifDetectionEnabled) {
                      unawaited(_runAndSaveCapabilitiesDetection(cam.id, onvif));
                    }
                    break; // dispara apenas uma vez
                  } catch (_) {
                    continue;
                  }
                }
              });
            }
          }
        } catch (_) {
          // silencioso
        }
      }
    } catch (e) {
      // ignore
    }
  }

  /// Força re-detecção de capacidades ONVIF em todas as câmeras
  Future<void> _forceCapabilitiesDetection() async {
    if (!_onvifDetectionEnabled) return;
    
    for (var i = 0; i < cameras.length; i++) {
      final cam = cameras[i];
      final host = Uri.tryParse(cam.streamUrl)?.host ?? '';
      final user = cam.username ?? '';
      final pass = cam.password ?? '';
      if (host.isEmpty || user.isEmpty || pass.isEmpty) continue;
      
      final delay = Duration(milliseconds: 500 + i * 600);
      Future.delayed(delay, () async {
        final ports = <int>[80, 8080, 8000, 8899];
        for (final p in ports) {
          try {
            final onvif = await Onvif.connect(
              host: '$host:$p',
              username: user,
              password: pass,
            ).timeout(const Duration(seconds: 6));
            await _runAndSaveCapabilitiesDetection(cam.id, onvif);
            break;
          } catch (_) {
            continue;
          }
        }
      });
    }
  }

  Future<void> _persistCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = cameras.map((c) => c.toJson()).toList();
      await prefs.setString('cameras', json.encode(data));
    } catch (e) {
      // ignore
    }
  }

  void _showNotification(NotificationData notification) {
    setState(() {
      notifications.insert(0, notification);
    });
    _persistCameras();
  }

  // Formatar timestamp para exibição
  String _formatTime(DateTime timestamp) {
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

  // Obter cor da notificação baseada no tipo
  Color _getNotificationColor(String type) {
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

  // Executa comandos PTZ/Zoom via serviço ONVIF
  Future<void> _executePtzCommand(CameraData camera, String command) async {
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

  // Alterna mute/unmute do áudio do player associado
  Future<void> _toggleMute(CameraData camera) async {
    final controller = _videoControllers[camera.id];
    final ok = await _audioService.toggleMute(controller);
    if (ok) {
      setState(() {
        _audioMuted[camera.id] = (controller?.value.volume == 0.0);
      });
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
    if (mounted) setState(() {});
  }

  // Exibe controles avançados de câmera (PTZ/Zoom/Áudio)
  void _showCameraControls(CameraData camera) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final controller = _videoControllers[camera.id];
        final hasVideo = controller?.value.isInitialized ?? false;
        final hasCreds = (camera.username?.isNotEmpty == true) && (camera.password?.isNotEmpty == true);
        final allowPTZ = (camera.capabilities?.hasPTZ == true) || hasCreds;
        final allowAudio = hasVideo;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.control_camera, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    'Controles avançados - ${camera.name}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (allowPTZ) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _executePtzCommand(camera, 'up'),
                      icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _executePtzCommand(camera, 'left'),
                      icon: const Icon(Icons.keyboard_arrow_left, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _executePtzCommand(camera, 'right'),
                      icon: const Icon(Icons.keyboard_arrow_right, color: Colors.white),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _executePtzCommand(camera, 'down'),
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _executePtzCommand(camera, 'zoom_in'),
                      icon: const Icon(Icons.zoom_in, color: Colors.white),
                      label: const Text('Zoom In', style: TextStyle(color: Colors.white)),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF2A2A2A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () => _executePtzCommand(camera, 'zoom_out'),
                      icon: const Icon(Icons.zoom_out, color: Colors.white),
                      label: const Text('Zoom Out', style: TextStyle(color: Colors.white)),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF2A2A2A),
                      ),
                    ),
                  ],
                ),
              ] else
                const Text('PTZ não disponível. Adicione usuário e senha ONVIF nas configurações para habilitar.', style: TextStyle(color: Color(0xFF9E9E9E))),
              const SizedBox(height: 12),
              // Botões de Gravação Automática
              _buildAutoRecordingButtons(camera),
              const SizedBox(height: 12),
              if (allowAudio)
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: () => _toggleMute(camera),
                    icon: Icon(
                      ((_videoControllers[camera.id]?.value.volume ?? 1) > 0)
                          ? Icons.volume_up
                          : Icons.volume_off,
                      color: Colors.white,
                    ),
                    label: Text(
                      ((_videoControllers[camera.id]?.value.volume ?? 1) > 0)
                          ? 'Desativar áudio'
                          : 'Ativar áudio',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: TextButton.styleFrom(backgroundColor: const Color(0xFF2A2A2A)),
                  ),
                )
              else
                const Text('Inicie o vídeo para controlar o áudio.', style: TextStyle(color: Color(0xFF9E9E9E))),
            ],
          ),
        );
      },
    );
  }

  // Normaliza uma URL de stream (ex.: adiciona porta padrão RTSP 554 quando ausente e evita ":0").
  // Também injeta credenciais na URL caso não estejam presentes.
  String _normalizeStreamUrl(String url, {String? username, String? password, String transport = 'tcp'}) {
    try {
      final uri = Uri.parse(url);
      final scheme = uri.scheme.toLowerCase();

      // Determina userInfo (credenciais) somente se não existirem na URL
      final hasCredsInUrl = uri.userInfo.isNotEmpty || url.contains('@');
      final userInfo = hasCredsInUrl
          ? uri.userInfo
          : ((username != null && username.isNotEmpty && password != null && password.isNotEmpty)
              ? _encodeCredentials(username, password)
              : '');

      // Define porta padrão apenas se ausente ou 0
      int? port;
      if (uri.hasPort && uri.port > 0) {
        port = uri.port;
      } else {
        if (scheme == 'rtsp') {
          port = 554;
        } else if (scheme == 'https') {
          port = 443;
        } else if (scheme == 'http') {
          port = 80;
        } else {
          port = null; // desconhecido
        }
      }

      // Se for RTSP e caminho estiver vazio ou raiz, proponha um caminho padrão
      String path = uri.path.isEmpty || uri.path == '/' ? '/cam/realmonitor' : uri.path;
      String? query = uri.query.isNotEmpty ? uri.query : null;
      if (scheme == 'rtsp') {
        // Se o caminho padrão for realmonitor e não tiver subtype, usar subtype=1 (substream) por padrão
        final hasSubtype = query?.contains('subtype=') ?? false;
        if (path.contains('realmonitor') && !hasSubtype) {
          query = 'channel=1&subtype=1';
        }
        // Preferir transporte TCP interleaved (quando player suporta)
        // Alguns players aceitam "rtsp_transport=tcp" como parâmetro não padrão
        final tr = (transport.toLowerCase() == 'udp') ? 'udp' : 'tcp';
        if (query == null) {
          query = 'rtsp_transport=$tr';
        } else if (!query.contains('rtsp_transport=')) {
          query = '$query&rtsp_transport=$tr';
        } else {
          // substitui valor existente
          query = query.replaceAll(RegExp(r'rtsp_transport=([^&]*)'), 'rtsp_transport=$tr');
        }
      }

      final normalized = Uri(
        scheme: uri.scheme.isEmpty ? 'rtsp' : uri.scheme,
        userInfo: userInfo,
        host: uri.host,
        port: port,
        path: path,
        query: query,
        fragment: uri.fragment.isEmpty ? null : uri.fragment,
      ).toString();
      return normalized;
    } catch (_) {
      return url; // Em caso de erro, retorna original
    }
  }

  void _updateCameraStatus(int cameraId, {required bool isLive, required Color statusColor}) {
    final idx = cameras.indexWhere((c) => c.id == cameraId);
    if (idx != -1) {
      setState(() {
        final current = cameras[idx];
        cameras[idx] = CameraData(
          id: current.id,
          name: current.name,
          isLive: isLive,
          statusColor: statusColor,
          uniqueColor: current.uniqueColor,
          icon: current.icon,
          streamUrl: current.streamUrl,
          username: current.username,
          password: current.password,
          port: current.port,
          transport: current.transport,
          capabilities: current.capabilities,
        );
      });
      _persistCameras();
    }
  }

  Future<void> _scanOnvifDevices() async {
    setState(() {
      _isScanning = true;
      _scanError = null;
      _discovered = [];
    });
    
    bool multicastWorked = false;
    
    try {
      // Tenta descoberta multicast primeiro
      final multicastProbe = MulticastProbe();
      await multicastProbe.probe();
      setState(() {
        _discovered = multicastProbe.onvifDevices;
      });
      multicastWorked = true;
      
      // Se não encontrou dispositivos via multicast, tenta descoberta manual
      if (_discovered.isEmpty) {
        await _manualIpScan();
      }
    } catch (e) {
      String errorStr = e.toString().toLowerCase();
      
      // Verifica se é o erro específico de multicast no Android
      if (errorStr.contains('failed to create datagram socket') || 
          errorStr.contains('connection refused') ||
          errorStr.contains('errno') ||
          errorStr.contains('socketexception')) {
        // Multicast não suportado no dispositivo. Usando descoberta manual...
        
        // Pula direto para descoberta manual sem mostrar erro
        try {
          await _manualIpScan();
        } catch (manualError) {
          setState(() {
            _scanError = 'Erro na descoberta manual: $manualError';
          });
        }
      } else {
        // Outro tipo de erro
        setState(() {
          _scanError = 'Erro na descoberta: $e';
        });
      }
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _manualIpScan() async {
    // Obtém a rede local (assumindo 192.168.1.x)
    final List<String> commonRanges = [
      '192.168.1.',
      '192.168.0.',
      '10.0.0.',
      '172.16.0.',
    ];
    
    List<dynamic> foundDevices = [];
    
    for (String range in commonRanges) {
      for (int i = 1; i <= 254; i++) {
        final ip = '$range$i';
        try {
          // Tenta conectar na porta padrão ONVIF (80)
          final onvif = await Onvif.connect(
            host: ip,
            username: '', // sem credenciais
            password: '', // sem credenciais
          ).timeout(const Duration(seconds: 2));
          
          final deviceInfo = await onvif.deviceManagement.getDeviceInformation()
              .timeout(const Duration(seconds: 2));
          
          // Se chegou até aqui, é um dispositivo ONVIF
          foundDevices.add({
            'name': deviceInfo.model ?? 'ONVIF Device',
            'hardware': deviceInfo.manufacturer ?? 'Unknown',
            'xAddr': 'http://$ip/onvif/device_service',
            'ip': ip,
          });
          
          // Dispositivo ONVIF encontrado em $ip: ${deviceInfo.model}
        } catch (e) {
          // Ignora erros - dispositivo não é ONVIF ou não está acessível
          continue;
        }
        
        // Para não sobrecarregar a rede
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      // Se já encontrou dispositivos, para de procurar
      if (foundDevices.isNotEmpty) break;
    }
    
    setState(() {
      _discovered = foundDevices;
    });
  }

  Future<void> _testSpecificIp() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _scanError = 'Digite um IP válido';
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _scanError = null;
      _discovered = [];
    });

    try {
      final onvif = await Onvif.connect(
        host: ip,
        username: '', // sem credenciais
        password: '', // sem credenciais
      ).timeout(const Duration(seconds: 5));
      final deviceInfo = await onvif.deviceManagement.getDeviceInformation()
          .timeout(const Duration(seconds: 5));

      setState(() {
        _discovered = [{
          'name': deviceInfo.model ?? 'ONVIF Device',
          'hardware': deviceInfo.manufacturer ?? 'Unknown',
          'xAddr': 'http://$ip/onvif/device_service',
          'ip': ip,
        }];
      });
    } catch (e) {
      setState(() {
        _scanError = 'Erro ao conectar com $ip: $e';
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _addDiscoveredAsCamera(dynamic m) async {
    // Solicita credenciais para o dispositivo ONVIF
    await _showOnvifCredentialsDialog(m);
  }

  Future<void> _showOnvifCredentialsDialog(dynamic m) async {
    final nameController = TextEditingController();
    final userController = TextEditingController();
    final passController = TextEditingController();
    final selectedTransport = ValueNotifier<String>('tcp');
    
    final deviceName = m.name?.isNotEmpty == true ? m.name! : (m.hardware ?? 'ONVIF Device');
    nameController.text = deviceName;
    
    // Não preencher credenciais automaticamente por segurança
    // Deixe os campos vazios e use apenas dicas descritivas

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Credenciais ONVIF',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Para conectar ao dispositivo ONVIF, informe as credenciais:',
                  style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nome da câmera',
                    labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF3A3A3A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4CAF50)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: userController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Usuário',
                    hintText: 'Usuário da câmera',
                    labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF3A3A3A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4CAF50)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha',
                    hintText: 'Senha da câmera',
                    labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF3A3A3A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4CAF50)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: selectedTransport,
                  builder: (context, value, _) {
                    return DropdownButtonFormField<String>(
                      value: value,
                      dropdownColor: const Color(0xFF2A2A2A),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Transporte RTSP',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF3A3A3A)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4CAF50)),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'tcp', child: Text('TCP (padrão)')),
                        DropdownMenuItem(value: 'udp', child: Text('UDP')),
                      ],
                      onChanged: (v) { if (v != null) selectedTransport.value = v; },
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'name': nameController.text.trim(),
                  'username': userController.text.trim(),
                  'password': passController.text.trim(),
                  'transport': selectedTransport.value,
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
              child: const Text('Conectar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await _connectToOnvifDevice(m, result);
    }
  }

  Future<void> _connectToOnvifDevice(dynamic m, Map<String, String> credentials) async {
    // DEBUG: Iniciando conexão ONVIF para dispositivo: $m
    
    // Obtém IP e xAddr do objeto descoberto
    String ip = '';
    String? xAddr;
    
    try {
      if (m is Map) {
        ip = (m['ip'] as String?) ?? '';
        xAddr = (m['xAddr'] as String?);
        // Tentativas adicionais para campos alternativos
        xAddr ??= (m['xAddrs'] as String?);
        xAddr ??= (m['XAddrs'] as String?);
        xAddr ??= (m['xaddr'] as String?);
        // Se xAddrs vier como lista
        if (xAddr == null && m['xAddrs'] is List && (m['xAddrs'] as List).isNotEmpty) {
          xAddr = (m['xAddrs'] as List).first.toString();
        }
        // Fallbacks para IP em objetos Map
        if (ip.isEmpty) {
          ip = (m['host'] as String?)
              ?? (m['address'] as String?)
              ?? (m['ipv4'] as String?)
              ?? (m['ipV4'] as String?)
              ?? (m['hostname'] as String?)
              ?? '';
        }
      } else {
        // Acesso dinâmico com proteção
        try { ip = (m.ip as String?) ?? ip; } catch (_) {}
        try { xAddr = (m.xAddr as String?); } catch (_) {}
        // Tentativas adicionais para campos alternativos
        if (xAddr == null || xAddr.isEmpty) {
          try {
            final dynamic xa = (m as dynamic).xAddrs;
            if (xa != null) {
              if (xa is String && xa.isNotEmpty) {
                xAddr = xa.split(RegExp(r'\s+')).first;
              } else if (xa is List && xa.isNotEmpty) {
                xAddr = xa.first.toString();
              }
            }
          } catch (_) {}
          try { final h = (m as dynamic).host; if (h is String && h.isNotEmpty) ip = h; } catch (_) {}
          try { final a = (m as dynamic).address; if (a is String && a.isNotEmpty) ip = a; } catch (_) {}
          try { final v4 = (m as dynamic).ipv4; if (v4 is String && v4.isNotEmpty) ip = v4; } catch (_) {}
        }
      }
      // Sanitização e normalização básica
      ip = ip.trim();
      if (xAddr != null) xAddr = xAddr.trim();

      // Se o IP vier como URL completa, extrai apenas o host
      if (ip.isNotEmpty) {
        Uri? parsed;
        if (ip.contains('://')) {
          parsed = Uri.tryParse(ip);
        } else if (ip.contains('/') || ip.contains(':')) {
          // Tenta interpretar como URL sem esquema
          parsed = Uri.tryParse('http://$ip');
        }
        if (parsed != null && parsed.host.isNotEmpty) {
          ip = parsed.host;
        }
      }

      // Se ainda não houver xAddr mas temos IP, cria um padrão
      if ((xAddr == null || xAddr.isEmpty) && ip.isNotEmpty) {
        xAddr = 'http://$ip/onvif/device_service';
      }

      // DEBUG: IP extraído (normalizado): $ip, xAddr (final): $xAddr
    } catch (e) {
      // DEBUG: Erro ao extrair IP/xAddr: $e
      ip = '';
      xAddr = null;
    }
    
    // Fallback: tenta extrair o host a partir do xAddr
    if (ip.isEmpty && xAddr != null && xAddr.isNotEmpty) {
      final uri = Uri.tryParse(xAddr);
      if (uri != null && uri.host.isNotEmpty) {
        ip = uri.host;
        // DEBUG: IP extraído do xAddr: $ip
      }
    }

    // Fallback final: tenta extrair URL/host a partir do toString() do objeto
    if (ip.isEmpty && (xAddr == null || xAddr.isEmpty)) {
      final s = m.toString();
      final match = RegExp(r'(https?://[^\s]+)', caseSensitive: false).firstMatch(s);
      if (match != null) {
        final url = match.group(1)!;
        final uri = Uri.tryParse(url);
        if (uri != null && uri.host.isNotEmpty) {
          ip = uri.host;
          xAddr = url;
          // DEBUG: IP/xAddr derivados de toString(): ip=$ip, xAddr=$xAddr
        }
      }
    }

    final deviceName = credentials['name']!;
    final username = credentials['username']!;
    final password = credentials['password']!;

    if (ip.isEmpty) {
      // DEBUG: Erro - IP vazio após todas as tentativas
      _showNotification(NotificationData(
        cameraId: 0,
        message: 'Erro: IP do dispositivo não encontrado',
        time: 'agora',
        statusColor: Colors.red,
      ));
      return;
    }

    // Mostra indicador de carregamento
    setState(() {
      _isScanning = true;
    });

    // Determina a porta e baseUri baseado no xAddr descoberto
    List<Map<String, dynamic>> connectionAttempts = [];
    
    if (xAddr != null && xAddr.isNotEmpty) {
      try {
        final xAddrUri = Uri.parse(xAddr);
        final discoveredPort = xAddrUri.port != 0 ? xAddrUri.port : (xAddrUri.scheme == 'https' ? 443 : 80);
        // DEBUG: Porta descoberta no xAddr: $discoveredPort
        
        // Primeira tentativa: usar a porta descoberta no xAddr
        connectionAttempts.add({
          'host': '${xAddrUri.host}:$discoveredPort',
          'baseUri': xAddr,
          'description': 'xAddr descoberto ($discoveredPort)'
        });
        
        // Segunda tentativa: apenas IP descoberto na porta padrão
        connectionAttempts.add({
          'host': xAddrUri.host,
          'baseUri': null,
          'description': 'IP descoberto (porta padrão)'
        });
      } catch (e) {
        // DEBUG: Erro ao processar xAddr: $e
      }
    }
    
    // Fallback: tenta portas ONVIF comuns
    final List<int> onvifPorts = [80, 8080, 8000, 8899];
    for (int port in onvifPorts) {
      bool alreadyAdded = connectionAttempts.any((attempt) => 
        attempt['host'].toString().endsWith(':$port'));
      if (!alreadyAdded) {
        connectionAttempts.add({
          'host': '$ip:$port',
          'baseUri': null,
          'description': 'fallback porta $port'
        });
      }
    }
    
    Exception? lastException;
    
    for (var attempt in connectionAttempts) {
      final hostWithPort = attempt['host'] as String;
      final baseUri = attempt['baseUri'] as String?;
      final description = attempt['description'] as String;
      
      // DEBUG: Tentando conectar em $hostWithPort ($description) com usuário: $username
      
      try {
        // Conecta ao dispositivo ONVIF
        late final Onvif onvif;
        
        if (baseUri != null) {
          // DEBUG: Usando baseUri: $baseUri
          // Usa host:porta diretamente para Onvif.connect
          final hostForConnect = hostWithPort;
          onvif = await Onvif.connect(
            host: hostForConnect,
            username: username,
            password: password,
          ).timeout(const Duration(seconds: 12));
        } else {
          // DEBUG: Usando host: $hostWithPort
          // Usa host:porta diretamente para Onvif.connect
          final hostForConnect = hostWithPort;
          onvif = await Onvif.connect(
            host: hostForConnect,
            username: username,
            password: password,
          ).timeout(const Duration(seconds: 12));
        }

        // DEBUG: Conexão ONVIF estabelecida, obtendo perfis...
        
        // Obtém perfis de mídia
        final profiles = await onvif.media.getProfiles()
            .timeout(const Duration(seconds: 10));

        if (profiles.isEmpty) {
          throw Exception('Nenhum perfil de mídia encontrado no dispositivo');
        }

        // DEBUG: ${profiles.length} perfis encontrados

        // Usa o primeiro perfil disponível
        final profile = profiles.first;
        String streamUrl;

        try {
          // DEBUG: Obtendo URI de stream do perfil: ${profile.name}
          // Tenta obter a URI de stream usando ONVIF
          final streamUriResult = await onvif.media.getStreamUri(profile.token)
              .timeout(const Duration(seconds: 10));
          streamUrl = streamUriResult;
          // DEBUG: Stream URI obtida: $streamUrl
        } catch (e) {
          // Se getStreamUri falhar, constrói URL RTSP padrão
          // DEBUG: Erro ao obter stream URI, usando URL padrão: $e
          streamUrl = 'rtsp://$username:$password@$ip:554/cam/realmonitor?channel=1&subtype=1';
        }

        // Normaliza a URL de stream antes de adicionar a câmera
        final normalizedUrl = _normalizeStreamUrl(streamUrl, username: username, password: password, transport: (credentials['transport'] ?? 'tcp'));
        // DEBUG: URL normalizada: $normalizedUrl
        
        // Cria nova câmera
        final nextId = (cameras.isEmpty ? 1 : (cameras.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1));
        final newCamera = CameraData(
          id: nextId,
          name: deviceName,
          isLive: false,
          statusColor: const Color(0xFF888888),
          uniqueColor: Color(CameraData.generateUniqueColor(nextId)),
          icon: Icons.videocam_outlined,
          streamUrl: normalizedUrl,
          username: username,
          password: password,
          port: 554, // Porta RTSP padrão
          transport: (credentials['transport'] ?? 'tcp'),
          capabilities: null,
        );

        setState(() {
          cameras.add(newCamera);
          // Inicializar detecção de movimento para a nova câmera
          _motionDetectionEnabled[newCamera.id] = false;
          _motionDetectionService.startMotionDetection(newCamera);
          notifications.insert(
            0,
            NotificationData(
              cameraId: nextId,
              message: 'Câmera ONVIF adicionada: $deviceName',
              time: 'agora',
              statusColor: const Color(0xFF4CAF50),
            ),
          );
        });

        // DEBUG: Câmera adicionada com sucesso, ID: $nextId
        _persistCameras();
        
        // Dispara detecção de capacidades em background (não bloqueia UI)
          if (_onvifDetectionEnabled) {
            unawaited(_runAndSaveCapabilitiesDetection(nextId, onvif));
          }
        
        // Inicia streaming da nova câmera
        _initializeVideoPlayer(newCamera);
        
        // Sucesso - sai do loop de tentativas e remove da lista de descobertos
        setState(() {
          _isScanning = false;
          _discovered.removeWhere((d) {
            try {
              if (identical(d, m)) return true;
              String? dx;
              try {
                dx = (d is Map)
                    ? (d['xAddr'] ?? d['xAddrs'] ?? d['XAddrs'] ?? d['xaddr'])?.toString()
                    : (d as dynamic).xAddr as String?;
              } catch (_) {}
              if (dx == null || dx.isEmpty) {
                try {
                  final xa = (d as dynamic).xAddrs;
                  if (xa is String && xa.isNotEmpty) {
                    dx = xa.split(RegExp(r'\s+')).first;
                  } else if (xa is List && xa.isNotEmpty) {
                    dx = xa.first.toString();
                  }
                } catch (_) {}
              }
              String dip = '';
              try {
                dip = (d is Map)
                    ? ((d['ip'] ?? d['host'] ?? d['address'] ?? d['ipv4'] ?? d['ipV4'] ?? d['hostname'])?.toString() ?? '')
                    : ((d as dynamic).ip as String? ?? '');
              } catch (_) {}
              bool matchIp = dip.isNotEmpty && dip == ip;
              bool matchX = (dx != null && xAddr != null && dx == xAddr);
              return matchIp || matchX;
            } catch (_) {
              return false;
            }
          });
        });
        return;

      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        // DEBUG: Falha na tentativa ($description - $hostWithPort): ${e.toString()}
        
        // Se é erro de autenticação, não tenta outras portas
        final errorMsg = e.toString().toLowerCase();
        if (errorMsg.contains('unauthorized') || errorMsg.contains('authentication') || 
            errorMsg.contains('401') || errorMsg.contains('forbidden')) {
          // DEBUG: Erro de autenticação detectado, parando tentativas
          break;
        }
        
        // Continua para próxima tentativa
        continue;
      }
    }
    
    // Se chegou aqui, todas as tentativas falharam
    setState(() {
      _isScanning = false;
    });
    
    // DEBUG: Todas as tentativas de conexão falharam
    String errorMsg = 'Falha na conexão';
    if (lastException != null) {
      final exceptionStr = lastException.toString().toLowerCase();
      if (exceptionStr.contains('timeout')) {
        errorMsg = 'Timeout - dispositivo não respondeu';
      } else if (exceptionStr.contains('unauthorized') || exceptionStr.contains('authentication')) {
        errorMsg = 'Credenciais inválidas';
      } else if (exceptionStr.contains('connection refused')) {
        errorMsg = 'Conexão recusada - verifique IP/porta';
      } else if (exceptionStr.contains('host unreachable')) {
        errorMsg = 'Dispositivo inacessível na rede';
      } else {
        errorMsg = 'Erro: ${lastException.toString()}';
      }
    }
    
    _showNotification(NotificationData(
      cameraId: 0,
      message: errorMsg,
      time: 'agora',
      statusColor: Colors.red,
    ));
  }

  void _showSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Configurações',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: StatefulBuilder(
            builder: (context, setLocalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    value: _onvifDetectionEnabled,
                    onChanged: (v) async {
                      setLocalState(() {});
                      setState(() { _onvifDetectionEnabled = v; });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('onvif_detection_enabled', v);
                    },
                    title: const Text('Detecção ONVIF em segundo plano', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    subtitle: const Text('Quando ativada, a aplicação tentará detectar capacidades ONVIF automaticamente para câmeras sem capacidades conhecidas.', style: TextStyle(color: Color(0xFF9E9E9E))),
                    activeColor: const Color(0xFF4CAF50),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _forceCapabilitiesDetection();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Iniciando re-detecção de capacidades ONVIF...'),
                            backgroundColor: Color(0xFF4CAF50),
                          ),
                        );
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('Re-detectar Capacidades ONVIF', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use esta opção se as funcionalidades de gravação não estão aparecendo nas câmeras.',
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar', style: TextStyle(color: Colors.white70)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Removido título 'Devices & Cameras'
                  // const Expanded(
                  //   flex: 3,
                  //   child: Text(
                  //     'Devices &\nCameras',
                  //     style: TextStyle(
                  //       fontSize: 29,
                  //       fontWeight: FontWeight.w800,
                  //       color: Colors.white,
                  //       height: 0.96,
                  //       letterSpacing: -0.8,
                  //     ),
                  //   ),
                  // ),
                  // const SizedBox(width: 14),

                  // Removida a pequena caixa de pesquisa adjacente
                  // Expanded(
                  //   flex: 2,
                  //   child: Container(
                  //     height: 40,
                  //     decoration: BoxDecoration(
                  //       color: const Color(0xFF2A2A2A),
                  //       borderRadius: BorderRadius.circular(20),
                  //     ),
                  //     child: const TextField(
                  //       decoration: InputDecoration(
                  //         hintText: 'Search',
                  //         hintStyle: TextStyle(
                  //           color: Color(0xFF666666),
                  //           fontSize: 13,
                  //           fontWeight: FontWeight.w400,
                  //         ),
                  //         prefixIcon: Icon(
                  //           Icons.search,
                  //           color: Color(0xFF666666),
                  //           size: 18,
                  //         ),
                  //         border: InputBorder.none,
                  //         contentPadding: EdgeInsets.symmetric(vertical: 10),
                  //       ),
                  //       style: TextStyle(color: Colors.white, fontSize: 13),
                  //     ),
                  //   ),
                  // ),

                  // Mantém o botão de adição (+)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      tooltip: 'Adicionar câmera',
                      onPressed: _showAddCameraDialog,
                      icon: const Icon(Icons.add, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Mantém o botão 'Descobrir'
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextButton.icon(
                      onPressed: _isScanning ? null : _scanOnvifDevices,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering, color: Colors.white70, size: 18),
                      label: Text(
                        _isScanning ? 'Buscando...' : 'Descobrir',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Botão de Configurações
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      tooltip: 'Configurações',
                      onPressed: _showSettingsDialog,
                      icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
                    ),
                  ),

                  // Campo de pesquisa/IP removido conforme solicitado
                ],
              ),
              const SizedBox(height: 12),
              if (_scanError != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF402222), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Erro na descoberta: $_scanError',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_discovered.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Dispositivos ONVIF encontrados',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3A3A3A)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (_, i) {
                      final m = _discovered[i];
                      final title = (m.name?.isNotEmpty == true ? m.name! : (m.hardware ?? 'ONVIF Device'));
                      final subtitle = m.xAddr ?? 'sem xAddr';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        leading: const Icon(Icons.router, color: Colors.white70),
                        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        trailing: TextButton(
                          onPressed: () => _addDiscoveredAsCamera(m),
                          child: const Text('Adicionar', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w800)),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF3A3A3A)),
                    itemCount: _discovered.length,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Layout dinâmico dos cards das câmeras ou placeholder
                      _buildCameraGrid(),
                      const SizedBox(height: 28),
                      // Seção de Notificações (posição fixa visualmente por conta do placeholder de altura fixa acima)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Notificações',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Lista de notificações
                      ...notifications.map((notification) => _buildNotificationItem(notification)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraGrid() {
    final int cameraCount = cameras.length;

    // Quando não há câmeras, exibimos um placeholder de altura fixa (364px)
    // para manter a seção de Notificações na mesma posição vertical original.
    if (cameraCount == 0) {
      return _buildEmptyCamerasPlaceholder();
    }

    // Layout scrollable com câmeras empilhadas verticalmente
    return SizedBox(
      height: cameraCount == 1 ? 300 : 600, // Altura fixa para permitir scroll interno
      child: SingleChildScrollView(
        child: Column(
          children: cameras.asMap().entries.map((entry) {
            final index = entry.key;
            final camera = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                children: [
                  if (index > 0) const SizedBox(height: 14),
                  _buildCameraCard(camera, isLarge: cameraCount == 1),
                  // Ícones de funcionalidades fora dos cards
                  const SizedBox(height: 8),
                  _buildExternalControlsRow(camera),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Placeholder para quando não existem câmeras cadastradas
  Widget _buildEmptyCamerasPlaceholder() {
    return Container(
      height: 364, // altura fixa para manter as notificações na mesma posição
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A3A), width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_outlined, color: Color(0xFF888888), size: 52),
            const SizedBox(height: 12),
            const Text(
              'Nenhuma câmera adicionada',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Toque para adicionar uma câmera real (RTSP/HTTP)',
              style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                onPressed: _showAddCameraDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Adicionar câmera',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Exibe diálogo para adicionar uma nova câmera
  void _showAddCameraDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final portController = TextEditingController();
    final userController = TextEditingController();
    final passController = TextEditingController();
    final selectedTransport = ValueNotifier<String>('tcp');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Adicionar câmera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nome da câmera',
                      labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: urlController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'IP ou domínio',
                      labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Informe o IP ou domínio';
                      final input = v.trim();
                      final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
                      final hostRegex = RegExp(r'^[a-zA-Z0-9.-]+$');
                      if (ipRegex.hasMatch(input) || hostRegex.hasMatch(input)) return null;
                      return 'Informe um IP (ex: 192.168.1.100) ou domínio válido';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: portController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Porta (RTSP padrão 554)',
                      labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null; // opcional
                      final p = int.tryParse(v.trim());
                      if (p == null || p <= 0 || p > 65535) return 'Porta inválida';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: portController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Porta (RTSP padrão 554)',
                      labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: userController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Usuário (opcional)',
                      labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Senha (opcional)',
                      labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: selectedTransport,
                    builder: (context, value, _) {
                      return DropdownButtonFormField<String>(
                        value: value,
                        dropdownColor: const Color(0xFF2A2A2A),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Transporte RTSP',
                          labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'tcp', child: Text('TCP (padrão)')),
                          DropdownMenuItem(value: 'udp', child: Text('UDP')),
                        ],
                        onChanged: (v) { if (v != null) selectedTransport.value = v; },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  // DEBUG: Iniciando adição manual de câmera
                  
                  final nextId = (cameras.isEmpty ? 0 : cameras.map((c) => c.id).reduce((a, b) => a > b ? a : b)) + 1;
                  
                  // Constrói a URL RTSP a partir de host/IP, porta e credenciais
                  final host = urlController.text.trim();
                  final portText = portController.text.trim();
                  final int port = portText.isEmpty ? 554 : int.parse(portText);
                  final user = userController.text.trim();
                  final pass = passController.text.trim();
                  final auth = (user.isNotEmpty && pass.isNotEmpty) ? '${_encodeCredentials(user, pass)}@' : '';
                  final String draftUrl = 'rtsp://$auth$host:$port/cam/realmonitor?channel=1&subtype=1';
                  final String finalUrl = _normalizeStreamUrl(draftUrl, username: user.isNotEmpty ? user : null, password: pass.isNotEmpty ? pass : null, transport: selectedTransport.value);
                  
                  // DEBUG: URL construída: $finalUrl
                  // DEBUG: Host: $host, Porta: $port, Usuário: ${user.isEmpty ? 'vazio' : user}
                  
                  final newCamera = CameraData(
                    id: nextId,
                    name: nameController.text.trim(),
                    isLive: false,
                    statusColor: const Color(0xFF4CAF50),
                    uniqueColor: Color(CameraData.generateUniqueColor(nextId)),
                    icon: Icons.videocam,
                    streamUrl: finalUrl,
                    username: user.isEmpty ? null : user,
                    password: pass.isEmpty ? null : pass,
                    port: port,
                    transport: selectedTransport.value,
                    capabilities: null,
                  );
                  
                  setState(() {
                    cameras.add(newCamera);
                    notifications.insert(
                      0,
                      NotificationData(
                        cameraId: newCamera.id,
                        message: 'Câmera adicionada: ${newCamera.name}',
                        time: 'agora',
                        statusColor: newCamera.statusColor,
                      ),
                    );
                  });
                  _persistCameras();
                  
                  // Tenta detecção de capacidades via ONVIF em background (se possível)
                  () async {
                    try {
                      final String host = urlController.text.trim();
                      final String user = userController.text.trim();
                      final String pass = passController.text.trim();
                      // Tenta portas comuns ONVIF rapidamente
                      final ports = <int>[80, 8080, 8000, 8899];
                      for (final p in ports) {
                        try {
                          final onvif = await Onvif.connect(
                            host: '$host:$p',
                            username: user,
                            password: pass,
                          ).timeout(const Duration(seconds: 6));
                          if (_onvifDetectionEnabled) {
                            unawaited(_runAndSaveCapabilitiesDetection(newCamera.id, onvif));
                          }
                          break; // dispara apenas uma vez
                        } catch (_) {
                          continue;
                        }
                      }
                    } catch (e) {
                      // silencioso
                    }
                  }();
                  
                  // DEBUG: Câmera adicionada com ID: ${newCamera.id}, iniciando streaming...
                  // Inicia o streaming assim que a câmera é adicionada
                  _initializeVideoPlayer(newCamera);
                  Navigator.of(context).pop();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
  }

  // Linha de controles de funcionalidades externa aos cards
  Widget _buildExternalControlsRow(CameraData camera) {
    final controller = _videoControllers[camera.id];
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
              onTap: () => _showPTZControls(camera),
            ),
            const SizedBox(width: 12),
            // Controle de Áudio
            _buildControlIcon(
              icon: _audioMuted[camera.id] == true ? Icons.volume_off : Icons.volume_up,
              isSupported: hasVideo,
              onTap: () => _toggleMute(camera),
            ),
            const SizedBox(width: 12),
            // Detecção de Movimento
            _buildControlIcon(
              icon: _motionDetectionEnabled[camera.id] == true ? Icons.motion_photos_on : Icons.motion_photos_off,
              isSupported: camera.capabilities?.hasMotionDetection == true,
              onTap: () => _showMotionDetectionSettings(camera),
            ),
            const SizedBox(width: 12),
            // Modo Noturno
            _buildControlIcon(
              icon: (_nightModeEnabled[camera.id] ?? false) ? Icons.nightlight : Icons.nightlight_outlined,
              isSupported: camera.capabilities?.hasNightVision == true,
              onTap: () => _showNightModeSettings(camera),
            ),
            const SizedBox(width: 12),
            // Gravação Automática
            _buildControlIcon(
              icon: Icons.smart_display,
              isSupported: true, // Sempre disponível
              onTap: () => _showAutoRecordingSettings(camera),
            ),
            const SizedBox(width: 12),
            // Notificações
            _buildControlIcon(
              icon: (_notificationsEnabled[camera.id] ?? true) ? Icons.notifications : Icons.notifications_off,
              isSupported: camera.capabilities?.hasNotifications == true,
              onTap: () => _showNotificationSettings(camera),
            ),
            const SizedBox(width: 12),
            // Cartão SD - Gravações
            _buildControlIcon(
              icon: Icons.sd_card,
              isSupported: camera.capabilities?.hasPlayback == true || camera.capabilities?.hasRecordingSearch == true,
              onTap: () => _showSDCardRecordings(camera),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraCard(CameraData camera, {bool isLarge = false}) {
    return CameraCardWidget(
       camera: camera,
       controller: _videoControllers[camera.id],
       isLoading: _loadingVideo.contains(camera.id),
       isLarge: isLarge,
       recordingService: _recordingService,
       onPlayPause: () {
         final hasVideo = _videoControllers[camera.id]?.value.isInitialized ?? false;
         if (hasVideo) {
           _stopVideoPlayer(camera.id);
         } else if (!_loadingVideo.contains(camera.id)) {
           _initializeVideoPlayer(camera);
         }
       },
     );
  }

  void _removeCamera(int cameraId) {
    setState(() {
      cameras.removeWhere((c) => c.id == cameraId);
    });
    _stopVideoPlayer(cameraId);
    _persistCameras();
  }

  // Exibe interface para acessar gravações do cartão SD
  void _showSDCardRecordings(CameraData camera) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return _buildSDCardRecordingsContent(camera, scrollController);
          },
        );
      },
    );
  }

  Widget _buildSDCardRecordingsContent(CameraData camera, ScrollController scrollController) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sd_card, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gravações do Cartão SD - ${camera.name}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Filtros de data
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filtros de Busca',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _selectDate(context, true),
                        icon: const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                        label: const Text('Data Início', style: TextStyle(color: Colors.white70)),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF3A3A3A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _selectDate(context, false),
                        icon: const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                        label: const Text('Data Fim', style: TextStyle(color: Colors.white70)),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF3A3A3A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _searchSDCardRecordings(camera),
                  icon: const Icon(Icons.search, color: Colors.white),
                  label: const Text('Buscar Gravações', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Lista de gravações
          Expanded(
            child: FutureBuilder<List<RecordingInfo>>(
              future: _getSDCardRecordings(camera),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.blue),
                        SizedBox(height: 16),
                        Text(
                          'Buscando gravações...',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Erro ao buscar gravações:\n${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Tentar Novamente'),
                        ),
                      ],
                    ),
                  );
                }
                
                final recordings = snapshot.data ?? [];
                
                if (recordings.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.video_library_outlined, color: Colors.white54, size: 48),
                        SizedBox(height: 16),
                        Text(
                          'Nenhuma gravação encontrada',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Verifique se há gravações no cartão SD\nou ajuste os filtros de busca',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                
                return ListView.builder(
                  controller: scrollController,
                  itemCount: recordings.length,
                  itemBuilder: (context, index) {
                    final recording = recordings[index];
                    return _buildRecordingItem(camera, recording);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
   }

  // Seleciona data para filtros de busca
  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate 
        ? (_searchStartDate ?? DateTime.now().subtract(const Duration(days: 7)))
        : (_searchEndDate ?? DateTime.now()),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Color(0xFF2A2A2A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _searchStartDate = picked;
        } else {
          _searchEndDate = picked;
        }
      });
    }
  }

  // Busca gravações no cartão SD com filtros
  Future<void> _searchSDCardRecordings(CameraData camera) async {
    try {
      final startDate = _searchStartDate ?? DateTime.now().subtract(const Duration(days: 7));
      final endDate = _searchEndDate ?? DateTime.now();
      
      final playbackService = OnvifPlaybackService(acceptSelfSigned: camera.acceptSelfSigned);
      final recordings = await playbackService.searchRecordings(
        camera,
        startTime: startDate,
        endTime: endDate,
      );
      
      // Força rebuild do FutureBuilder
      setState(() {});
      
      if (recordings.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhuma gravação encontrada no período selecionado'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar gravações: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Obtém gravações do cartão SD
  Future<List<RecordingInfo>> _getSDCardRecordings(CameraData camera) async {
    try {
      final startDate = _searchStartDate ?? DateTime.now().subtract(const Duration(days: 1));
      final endDate = _searchEndDate ?? DateTime.now();
      
      final playbackService = OnvifPlaybackService(acceptSelfSigned: camera.acceptSelfSigned);
      return await playbackService.searchRecordings(
        camera,
        startTime: startDate,
        endTime: endDate,
      );
    } catch (e) {
      throw Exception('Falha ao acessar gravações: $e');
    }
  }

  // Constrói item de gravação na lista
  Widget _buildRecordingItem(CameraData camera, RecordingInfo recording) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.play_circle_outline, color: Colors.blue),
        ),
        title: Text(
          recording.filename,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Início: ${_formatDateTime(recording.startTime)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Duração: ${_formatDuration(recording.duration)} • Tamanho: ${_formatFileSize(recording.sizeBytes)}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white70),
          color: const Color(0xFF2A2A2A),
          onSelected: (value) {
            switch (value) {
              case 'play':
                _playSDCardRecording(camera, recording);
                break;
              case 'download':
                _downloadSDCardRecording(camera, recording);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'play',
              child: Row(
                children: [
                  Icon(Icons.play_arrow, color: Colors.white70, size: 16),
                  SizedBox(width: 8),
                  Text('Reproduzir', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            if (camera.capabilities?.hasRecordingDownload == true)
              const PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download, color: Colors.white70, size: 16),
                    SizedBox(width: 8),
                    Text('Baixar', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
          ],
        ),
        onTap: () => _playSDCardRecording(camera, recording),
      ),
    );
  }

  // Reproduz gravação do cartão SD
  Future<void> _playSDCardRecording(CameraData camera, RecordingInfo recording) async {
    try {
      // Navegar diretamente para o player de vídeo
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerWidget(
            camera: camera,
            recording: recording,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reproduzir gravação: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Baixa gravação do cartão SD
  Future<void> _downloadSDCardRecording(CameraData camera, RecordingInfo recording) async {
    try {
      final playbackService = OnvifPlaybackService(acceptSelfSigned: camera.acceptSelfSigned);
      final success = await playbackService.downloadRecording(
        camera,
        recording,
        '/storage/emulated/0/Download/${recording.filename}',
      );
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download iniciado com sucesso'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao baixar gravação: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Formata data e hora
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // Formata duração
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  // Formata tamanho do arquivo
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }

  void _editCamera(CameraData camera) {
    // Similar to add camera but prefilled
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: camera.name);
    final parsed = Uri.tryParse(camera.streamUrl);
    final preHost = (parsed != null && parsed.host.isNotEmpty) ? parsed.host : camera.streamUrl;
    final prePort = (parsed != null && parsed.hasPort)
        ? parsed.port.toString()
        : (camera.port?.toString() ?? '');
    final preUserFromUrl = (parsed != null && parsed.userInfo.isNotEmpty) ? parsed.userInfo.split(':').first : '';
    final prePassFromUrl = (parsed != null && parsed.userInfo.contains(':')) ? parsed.userInfo.split(':').last : '';
    final urlController = TextEditingController(text: preHost);
    final portController = TextEditingController(text: prePort);
    final userController = TextEditingController(text: (camera.username ?? preUserFromUrl));
    final passController = TextEditingController(text: (camera.password ?? prePassFromUrl));
    final selectedTransport = ValueNotifier<String>(camera.transport ?? 'tcp');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          bool acceptSelfSigned = camera.acceptSelfSigned;
          return AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Editar câmera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nome da câmera',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'IP ou domínio',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Informe o IP ou domínio';
                        final input = v.trim();
                        final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
                        final hostRegex = RegExp(r'^[a-zA-Z0-9.-]+$');
                        if (ipRegex.hasMatch(input) || hostRegex.hasMatch(input)) return null;
                        return 'Informe um IP (ex: 192.168.1.100) ou domínio válido';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: userController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Usuário (opcional)',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Senha (opcional)',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Aceitar certificados HTTPS autoassinados', style: TextStyle(color: Colors.white)),
                      value: acceptSelfSigned,
                      onChanged: (value) {
                        setState(() {
                          acceptSelfSigned = value;
                        });
                      },
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
            ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  // Constrói a URL RTSP a partir de host/IP, porta e credenciais (porta padrão 554)
                  final host = urlController.text.trim();
                  final portText = portController.text.trim();
                  final int port = portText.isEmpty ? 554 : int.parse(portText);
                  final user = userController.text.trim();
                  final pass = passController.text.trim();
                  final auth = (user.isNotEmpty && pass.isNotEmpty) ? '${_encodeCredentials(user, pass)}@' : '';
                  final String draftUrl = 'rtsp://$auth$host:$port/cam/realmonitor?channel=1&subtype=1';
                  final String finalUrl = _normalizeStreamUrl(draftUrl, username: user.isNotEmpty ? user : null, password: pass.isNotEmpty ? pass : null, transport: selectedTransport.value);

                  _updateCamera(
                    camera.id,
                    nameController.text.trim(),
                    finalUrl,
                    user.isEmpty ? null : user,
                    pass.isEmpty ? null : pass,
                    acceptSelfSigned: acceptSelfSigned,
                  );
                  Navigator.of(context).pop();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
              child: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );
  }

  void _updateCamera(int id, String name, String url, String? username, String? password, {required bool acceptSelfSigned}) {
    final idx = cameras.indexWhere((c) => c.id == id);
    if (idx >= 0) {
      _stopVideoPlayer(id); // Para o vídeo antes de atualizar
      setState(() {
        final current = cameras[idx];
        final parsed = Uri.tryParse(url);
        final newPort = parsed?.hasPort == true
            ? parsed!.port
            : (parsed?.scheme == 'rtsp' ? 554 : null);
        final newTransport = parsed?.queryParameters['rtsp_transport'] ?? current.transport;
        
        // Verifica se host ou credenciais mudaram (potencial necessidade de redetecção)
        final oldHost = Uri.tryParse(current.streamUrl)?.host ?? '';
        final newHost = parsed?.host ?? '';
        final oldUser = current.username ?? '';
        final newUser = username ?? '';
        final oldPass = current.password ?? '';
        final newPass = password ?? '';
        final hostChanged = oldHost != newHost;
        final credentialsChanged = oldUser != newUser || oldPass != newPass;
        
        cameras[idx] = CameraData(
          id: id,
          name: name,
          isLive: false,
          statusColor: const Color(0xFF888888),
          uniqueColor: current.uniqueColor,
          icon: Icons.videocam_outlined,
          streamUrl: url,
          username: username,
          password: password,
          port: newPort,
          transport: newTransport,
          capabilities: hostChanged ? null : current.capabilities, // limpa se host mudou
          acceptSelfSigned: acceptSelfSigned,
        );
        
        // Se host ou credenciais mudaram, relança detecção de capacidades
        if (hostChanged || credentialsChanged) {
          Future.delayed(const Duration(milliseconds: 800), () async {
            try {
              final host = newHost;
              final user = newUser;
              final pass = newPass;
              if (host.isEmpty || user.isEmpty || pass.isEmpty) return;
              final ports = <int>[80, 8080, 8000, 8899];
              for (final p in ports) {
                try {
                  final onvif = await Onvif.connect(
                    host: '$host:$p',
                    username: user,
                    password: pass,
                  ).timeout(const Duration(seconds: 6));
                  if (_onvifDetectionEnabled) {
                    unawaited(_runAndSaveCapabilitiesDetection(id, onvif));
                  }
                  break;
                } catch (_) {
                  continue;
                }
              }
            } catch (_) {
              // silencioso
            }
          });
        }
      });
      _showNotification(
        NotificationData(
          cameraId: id,
          message: 'Câmera atualizada: $name',
          time: 'agora',
          statusColor: const Color(0xFF4CAF50),
        ),
      );
      _persistCameras();
      // Reinicia o player com a nova configuração para evitar stream parado
      final updatedCam = cameras[idx];
      _initializeVideoPlayer(updatedCam);
    }
  }

  Widget _buildNotificationItem(NotificationData notification) {
    final CameraData camera = cameras.firstWhere(
      (c) => c.id == notification.cameraId,
      orElse: () => CameraData(
        id: notification.cameraId,
        name: 'Camera ${notification.cameraId}',
        isLive: false,
        statusColor: const Color(0xFF888888),
        uniqueColor: Color(CameraData.generateUniqueColor(notification.cameraId)),
        icon: Icons.videocam,
        streamUrl: '',
        username: null,
        password: null,
        port: null,
      ),
    );
    final Color color = camera.uniqueColor;
    final String cameraName = camera.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Indicador de cor da câmera
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cameraName,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      notification.time,
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  // Indicador de streaming discreto com animação
  Widget _buildStreamingIndicator(CameraData camera, bool hasVideo, bool isLoading) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasVideo
            ? camera.uniqueColor
            : (isLoading
                ? const Color(0xFFFFAB00)
                : Colors.grey),
        boxShadow: hasVideo
            ? [
                BoxShadow(
                  color: camera.uniqueColor.withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: hasVideo
          ? TweenAnimationBuilder<double>(
              duration: const Duration(seconds: 2),
              tween: Tween(begin: 0.3, end: 1.0),
              builder: (context, value, child) {
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: camera.uniqueColor.withValues(alpha: value),
                  ),
                );
              },
              onEnd: () {
                // Reinicia a animação
                if (mounted) {
                  setState(() {});
                }
              },
            )
          : null,
    );
  }



  // Ícone de controle individual
  Widget _buildControlIcon({
    required IconData icon,
    required bool isSupported,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isSupported ? onTap : () => _showUnsupportedFeatureMessage(),
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

  // Exibir controles PTZ
  void _showPTZControls(CameraData camera) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: Text(
            'Controles PTZ - ${camera.name}',
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Favoritos de posição
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Posições Favoritas:',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<PtzPosition>>(
                        future: _ptzFavoritesService.getFavoritePositions(camera.id),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                            return Wrap(
                              spacing: 8,
                              children: snapshot.data!.map((position) => 
                                ElevatedButton(
                                  onPressed: () async {
                                    final success = await _ptzFavoritesService.goToFavoritePosition(camera, position);
                                    if (success) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Movendo para ${position.name}')),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  ),
                                  child: Text(position.name, style: const TextStyle(fontSize: 12)),
                                )
                              ).toList(),
                            );
                          }
                          return const Text('Nenhuma posição salva', style: TextStyle(color: Colors.white70));
                        },
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _saveFavoritePosition(camera),
                        icon: const Icon(Icons.bookmark_add, size: 16),
                        label: const Text('Salvar Posição Atual'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Controles direcionais
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _sendPTZCommand(camera, 'up'),
                      icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 32),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _sendPTZCommand(camera, 'left'),
                      icon: const Icon(Icons.keyboard_arrow_left, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 40),
                    IconButton(
                      onPressed: () => _sendPTZCommand(camera, 'right'),
                      icon: const Icon(Icons.keyboard_arrow_right, color: Colors.white, size: 32),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _sendPTZCommand(camera, 'down'),
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Controles de zoom
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () => _sendPTZCommand(camera, 'zoom_in'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                      child: const Text('Zoom +'),
                    ),
                    ElevatedButton(
                      onPressed: () => _sendPTZCommand(camera, 'zoom_out'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                      child: const Text('Zoom -'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Enviar comando PTZ
  void _sendPTZCommand(CameraData camera, String command) {
    _executePtzCommand(camera, command);
  }

  // Salvar posição favorita de PTZ
  void _saveFavoritePosition(CameraData camera) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Salvar Posição Favorita',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Digite um nome para esta posição:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Ex: Entrada Principal',
                hintStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final success = await _ptzFavoritesService.saveFavoritePosition(
                  camera: camera,
                  name: name,
                );
                Navigator.of(context).pop();
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Posição "$name" salva com sucesso!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Erro ao salvar posição. Verifique a conexão com a câmera.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // Exibir configurações de detecção de movimento
  void _showMotionDetectionSettings(CameraData camera) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: Text(
            'Detecção de Movimento - ${camera.name}',
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configurações de detecção de movimento:',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Ativar detecção', style: TextStyle(color: Colors.white)),
                  value: _motionDetectionEnabled[camera.id] ?? false,
                  onChanged: (value) async {
                    final success = await _motionDetectionService.toggleMotionDetection(
                      camera.id.toString(),
                      value,
                    );
                    if (success) {
                      setDialogState(() {
                        _motionDetectionEnabled[camera.id] = value;
                      });
                      setState(() {
                        _motionDetectionEnabled[camera.id] = value;
                      });
                      _showNotification(
                        NotificationData(
                          cameraId: camera.id,
                          message: '${camera.name}: Detecção de movimento ${value ? 'ativada' : 'desativada'}.',
                          time: 'agora',
                          statusColor: value ? Colors.green : Colors.orange,
                        ),
                      );
                    } else {
                      _showNotification(
                        NotificationData(
                          cameraId: camera.id,
                          message: '${camera.name}: Erro ao ${value ? 'ativar' : 'desativar'} detecção.',
                          time: 'agora',
                          statusColor: Colors.red,
                        ),
                      );
                    }
                  },
                  activeColor: Colors.blue,
                ),
                const Divider(color: Colors.white24),
                const Text(
                  'Áreas de Detecção',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (camera.capabilities?.motionZones.isNotEmpty == true)
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      itemCount: camera.capabilities?.motionZones.length ?? 0,
                      itemBuilder: (context, index) {
                        final zone = camera.capabilities?.motionZones[index];
                        if (zone == null) return const SizedBox.shrink();
                        return ListTile(
                          leading: Icon(
                            zone.isExclusionZone ? Icons.block : Icons.visibility,
                            color: zone.isEnabled ? Colors.green : Colors.grey,
                          ),
                          title: Text(
                            zone.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            zone.isExclusionZone ? 'Área ignorada' : 'Área monitorada',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: Switch(
                            value: zone.isEnabled,
                            onChanged: (value) async {
                              final updatedZone = MotionDetectionZone(
                                id: zone.id,
                                name: zone.name,
                                points: zone.points,
                                isEnabled: value,
                                isExclusionZone: zone.isExclusionZone,
                                sensitivity: zone.sensitivity,
                              );
                              _motionDetectionService.updateDetectionZone(
                                camera.id.toString(),
                                updatedZone,
                              );
                              // Método updateDetectionZone é void, então assumimos sucesso
                              setDialogState(() {
                                camera.capabilities?.motionZones[index] = updatedZone;
                              });
                              _showNotification(
                                NotificationData(
                                  cameraId: camera.id,
                                  message: 'Área "${zone.name}" ${value ? 'ativada' : 'desativada'}',
                                  time: 'agora',
                                  statusColor: Colors.blue,
                                ),
                              );
                            },
                            activeColor: Colors.green,
                          ),
                        );
                      },
                    ),
                  )
                else
                  const Text(
                    'Nenhuma área configurada',
                    style: TextStyle(color: Colors.white54),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showAddDetectionZone(camera, setDialogState),
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar Área'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _configureMotionSensitivity(camera, setDialogState),
                        icon: const Icon(Icons.tune),
                        label: const Text('Sensibilidade'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Exibir configurações de modo noturno
  void _showNightModeSettings(CameraData camera) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: Text(
            'Modo Noturno - ${camera.name}',
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configurações de visão noturna:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Modo noturno automático', style: TextStyle(color: Colors.white)),
                value: _nightModeEnabled[camera.id] ?? false,
                onChanged: (value) async {
                  final success = await _nightModeService.toggleNightMode(
                    camera,
                    value,
                  );
                  if (success) {
                    setDialogState(() {
                      _nightModeEnabled[camera.id] = value;
                    });
                    setState(() {
                      _nightModeEnabled[camera.id] = value;
                      // Note: camera.capabilities.nightModeEnabled não é um setter válido
                    });
                    _showNotification(
                      NotificationData(
                        cameraId: camera.id,
                        message: '${camera.name}: Modo noturno ${value ? 'ativado' : 'desativado'}.',
                        time: 'agora',
                        statusColor: value ? Colors.green : Colors.orange,
                      ),
                    );
                  } else {
                    _showNotification(
                      NotificationData(
                        cameraId: camera.id,
                        message: '${camera.name}: Erro ao ${value ? 'ativar' : 'desativar'} modo noturno.',
                        time: 'agora',
                        statusColor: Colors.red,
                      ),
                    );
                  }
                },
                activeColor: Colors.blue,
              ),
              SwitchListTile(
                title: const Text('Luz infravermelha', style: TextStyle(color: Colors.white)),
                value: _irLightEnabled[camera.id] ?? false,
                onChanged: (value) async {
                  final success = await _nightModeService.toggleIRLights(
                    camera,
                    value,
                  );
                  if (success) {
                    setDialogState(() {
                      _irLightEnabled[camera.id] = value;
                    });
                    setState(() {
                      _irLightEnabled[camera.id] = value;
                      // Note: camera.capabilities.irLightsEnabled não é um setter válido
                    });
                    _showNotification(
                      NotificationData(
                        cameraId: camera.id,
                        message: '${camera.name}: Luz IR ${value ? 'ativada' : 'desativada'}.',
                        time: 'agora',
                        statusColor: value ? Colors.green : Colors.orange,
                      ),
                    );
                  } else {
                    _showNotification(
                      NotificationData(
                        cameraId: camera.id,
                        message: '${camera.name}: Erro ao ${value ? 'ativar' : 'desativar'} luz IR.',
                        time: 'agora',
                        statusColor: Colors.red,
                      ),
                    );
                  }
                },
                activeColor: Colors.blue,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }



  // Exibir configurações de notificações
  void _showNotificationSettings(CameraData camera) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: Text(
            'Notificações - ${camera.name}',
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configurações de notificações:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Notificações push', style: TextStyle(color: Colors.white)),
                value: _notificationsEnabled[camera.id] ?? true,
                onChanged: (value) {
                  setDialogState(() {
                    _notificationsEnabled[camera.id] = value;
                  });
                  setState(() {
                    _notificationsEnabled[camera.id] = value;
                  });
                  _showNotification(
                    NotificationData(
                      cameraId: camera.id,
                      message: '${camera.name}: Notificações ${value ? 'ativadas' : 'desativadas'}.',
                      time: 'agora',
                      statusColor: value ? Colors.green : Colors.orange,
                    ),
                  );
                },
                activeColor: Colors.blue,
              ),
              SwitchListTile(
                title: const Text('Email de alerta', style: TextStyle(color: Colors.white)),
                value: _recordingEnabled[camera.id] ?? false,
                onChanged: (value) {
                  setDialogState(() {
                    _recordingEnabled[camera.id] = value;
                  });
                  setState(() {
                    _recordingEnabled[camera.id] = value;
                  });
                  _showNotification(
                    NotificationData(
                      cameraId: camera.id,
                      message: '${camera.name}: Email de alerta ${value ? 'ativado' : 'desativado'}.',
                      time: 'agora',
                      statusColor: value ? Colors.green : Colors.orange,
                    ),
                  );
                },
                activeColor: Colors.blue,
              ),
              const Text(
                'Frequência: Imediata\nTipo: Movimento detectado',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Exibir mensagem de funcionalidade não suportada
  void _showUnsupportedFeatureMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Esta funcionalidade não é suportada por esta câmera.'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

// Classes de dados movidas para ../models/camera_models.dart

class NotificationData {
  final int cameraId;
  final String message;
  final String time;
  final Color statusColor;

  NotificationData({
    required this.cameraId,
    required this.message,
    required this.time,
    required this.statusColor,
  });
}

// Extensão para métodos de gravação automática
extension AutoRecordingMethods on _DevicesAndCamerasScreenState {
  // Constrói os botões de gravação automática
  Widget _buildAutoRecordingButtons(CameraData camera) {
    return Column(
      children: [
        // Primeira linha de botões
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showAutoRecordingSettings(camera);
                  },
                  icon: const Icon(Icons.settings, color: Colors.white, size: 18),
                  label: const Text('Configurações', style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2A),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showRecordedVideos(camera);
                  },
                  icon: const Icon(Icons.video_library, color: Colors.white, size: 18),
                  label: const Text('Vídeos', style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2A),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Segunda linha de botões
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextButton.icon(
                  onPressed: () => _toggleAutoRecording(camera),
                  icon: Icon(
                    _isAutoRecordingEnabled(camera) ? Icons.stop : Icons.play_arrow,
                    color: _isAutoRecordingEnabled(camera) ? Colors.red : Colors.green,
                    size: 18,
                  ),
                  label: Text(
                    _isAutoRecordingEnabled(camera) ? 'Parar' : 'Iniciar',
                    style: TextStyle(
                      color: _isAutoRecordingEnabled(camera) ? Colors.red : Colors.green,
                      fontSize: 12,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2A),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextButton.icon(
                  onPressed: () => _showRecordingStatus(camera),
                  icon: const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  label: const Text('Status', style: TextStyle(color: Colors.blue, fontSize: 12)),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2A),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Mostra as configurações de gravação automática
  void _showAutoRecordingSettings(CameraData camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AutoRecordingSettingsPage(camera: camera),
      ),
    );
  }

  // Mostra os vídeos gravados
  void _showRecordedVideos(CameraData camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecordedVideosPage(camera: camera),
      ),
    );
  }

  // Alterna o estado da gravação automática
  Future<void> _toggleAutoRecording(CameraData camera) async {
    try {
      if (_isAutoRecordingEnabled(camera)) {
        await _autoRecordingService.stopAutoRecording(camera.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gravação automática parada para ${camera.name}'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        await _autoRecordingService.startAutoRecording(camera);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gravação automática iniciada para ${camera.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      setState(() {}); // Atualiza a UI
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao alterar gravação automática: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Verifica se a gravação automática está habilitada
  bool _isAutoRecordingEnabled(CameraData camera) {
    return _autoRecordingService.isAutoRecordingActive(camera.id);
  }

  // Mostra o status da gravação
  void _showRecordingStatus(CameraData camera) async {
    final stats = await _autoRecordingService.getRecordingStats(camera.id);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          'Status da Gravação - ${camera.name}',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusRow('Status:', _isAutoRecordingEnabled(camera) ? 'Ativo' : 'Inativo'),
            _buildStatusRow('Total de Gravações:', '${stats.totalRecordings}'),
            _buildStatusRow('Espaço Usado:', '${stats.totalSizeMB} MB'),
            _buildStatusRow('Última Gravação:', stats.newestRecording != null 
                ? '${stats.newestRecording!.day}/${stats.newestRecording!.month}/${stats.newestRecording!.year} ${stats.newestRecording!.hour}:${stats.newestRecording!.minute.toString().padLeft(2, '0')}'
                : 'Nenhuma'),
            _buildStatusRow('Gravações Mais Antigas:', stats.oldestRecording != null 
                ? '${stats.oldestRecording!.day}/${stats.oldestRecording!.month}/${stats.oldestRecording!.year}'
                : 'Nenhuma'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  // Constrói uma linha de status
  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}