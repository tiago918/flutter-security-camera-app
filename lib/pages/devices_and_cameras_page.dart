import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/camera_models.dart';
import '../services/camera_service.dart';
import '../models/camera_status.dart';
import '../models/notification_model.dart';
import '../models/credentials.dart';
import '../models/connection_log.dart';
import '../services/camera_management_service.dart';
import '../services/camera_service.dart';
import '../services/notification_service.dart';
import '../services/camera_state_service.dart';
import '../services/fast_camera_discovery_service.dart';
import '../services/camera_health_service.dart';
import '../services/camera_filter_service.dart';
import '../services/night_mode_service.dart';
import '../services/auto_recording_service.dart';
import '../services/onvif_ptz_service.dart';
import '../services/audio_service.dart';
import '../services/ptz_favorites_service.dart';
import '../services/recording_service.dart';
import '../services/motion_detection_service.dart';
import '../services/video_management_service.dart';
import '../services/camera_connection_manager.dart';
import '../services/auto_reconnection_service.dart';
import '../services/onvif_service.dart';
import '../services/integrated_logging_service.dart';
import '../constants/rtsp_constants.dart';
import '../widgets/camera_dialogs.dart';
import '../widgets/dialogs/add_camera_dialog.dart';
import '../widgets/camera_controls.dart';
import '../widgets/notification_panel.dart';
import 'devices_and_cameras/widgets/camera_grid_widget.dart';

class DevicesAndCamerasScreen extends StatefulWidget {
  const DevicesAndCamerasScreen({super.key});

  @override
  State<DevicesAndCamerasScreen> createState() => _DevicesAndCamerasScreenState();
}

class _DevicesAndCamerasScreenState extends State<DevicesAndCamerasScreen> {
  // Lista de câmeras
  final List<CameraData> cameras = <CameraData>[];
  
  // Lista de notificações
  final List<NotificationData> notifications = [];
  
  // Preferência para detecção ONVIF
  bool _onvifDetectionEnabled = true;
  
  // Estado da descoberta avançada
  bool _isDiscovering = false;
  bool _isConnecting = false;
  String? _discoveryError;
  List<Map<String, dynamic>> _discoveredDevices = [];
  DiscoveryProgress? _currentProgress;
  
  // Câmera selecionada e notificações
  CameraData? _selectedCamera;
  List<CameraNotification> _notifications = [];
  
  // Serviços
  final CameraHealthService _healthService = CameraHealthService();
  final CameraStateService _stateService = CameraStateService();
  final CameraFilterService _filterService = CameraFilterService();
  final OnvifPtzService _ptzService = OnvifPtzService();
  final AudioService _audioService = AudioService();
  final PtzFavoritesService _ptzFavoritesService = PtzFavoritesService();
  final NightModeService _nightModeService = NightModeService();
  final NotificationService _notificationService = NotificationService();
  final RecordingService _recordingService = RecordingService();
  final MotionDetectionService _motionDetectionService = MotionDetectionService();
  final AutoRecordingService _autoRecordingService = AutoRecordingService();
  final VideoManagementService _videoManagementService = VideoManagementService();
  late CameraConnectionManager _connectionManager;
  late AutoReconnectionService _reconnectionService;
  late ONVIFService _onvifService;
  late IntegratedLoggingService _loggingService;
  Map<String, ConnectionStatus> _connectionStates = {};
  
  // Estados dos controles por câmera
  final Map<int, bool> _audioMuted = {};
  final Map<int, bool> _motionDetectionEnabled = {};
  final Map<int, bool> _nightModeEnabled = {};
  final Map<int, bool> _irLightEnabled = {};
  final Map<int, bool> _recordingEnabled = {};
  final Map<int, bool> _notificationsEnabled = {};
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadPersistedCameras();
    _setupNotificationListener();
    _loadNotifications();
  }
  
  /// Carrega câmeras persistidas do CameraService
  Future<void> _loadPersistedCamerasFromService() async {
    try {
      print('DEBUG: Carregando câmeras persistidas do CameraService');
      // Usar o método de carregamento padrão por enquanto
      await _loadPersistedCameras();
    } catch (e) {
      print('ERRO: Falha ao carregar câmeras persistidas: $e');
    }
  }





  /// Obtém cor do status baseada no CameraStatus
  Color _getStatusColor(CameraStatus status) {
    switch (status) {
      case CameraStatus.online:
        return const Color(0xFF4CAF50);
      case CameraStatus.offline:
        return const Color(0xFFF44336);
      case CameraStatus.connecting:
        return const Color(0xFFFF9800);
      case CameraStatus.error:
        return const Color(0xFFF44336);
      default:
        return const Color(0xFF888888);
    }
  }
  

  
  void _initializeServices() async {
    // Inicializar o serviço de descoberta rápida
    await FastCameraDiscoveryService.initialize();
    
    // Inicializar serviços de conexão e logging
    _connectionManager = CameraConnectionManager();
    _reconnectionService = AutoReconnectionService();
    _onvifService = ONVIFService();
    _loggingService = IntegratedLoggingService();
    
    await _connectionManager.initialize();
    await _reconnectionService.initialize();
    await _onvifService.initialize();
    await _loggingService.initialize();
    
    // Configurar listener para progresso de descoberta
    FastCameraDiscoveryService.discoveryProgressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _currentProgress = progress;
          _isDiscovering = !progress.isComplete;
          _discoveryError = null;
          
          debugPrint('🔄 Progresso da descoberta: ${progress.phase} - ${progress.current}/${progress.total}');
          if (progress.currentDevice != null) {
            debugPrint('📱 Dispositivo atual: ${progress.currentDevice}');
          }
          
          // Quando a descoberta estiver completa, obter dispositivos do cache
          if (progress.isComplete) {
            _loadDiscoveredDevices();
          }
        });
      }
    });
    
    _healthService.onHealthChanged = (cameraId, isHealthy) {
      if (mounted) {
        setState(() {
          // Atualizar status de saúde da câmera
        });
      }
    };
    
    _stateService.onStateChanged = (cameraId) {
      if (mounted) {
        setState(() {
          // Atualizar estado da câmera
        });
      }
    };
    
    _setupConnectionMonitoring();
  }
  
  void _disposeServices() {
    FastCameraDiscoveryService.dispose();
    _stateService.dispose();
    _healthService.dispose();
    _notificationService.dispose();
    _connectionManager.dispose();
    _reconnectionService.dispose();
    _onvifService.dispose();
    _loggingService.dispose();
  }
  
  Future<void> _loadPersistedCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final camerasJson = prefs.getString('cameras');
      if (camerasJson != null) {
        final List<dynamic> camerasList = json.decode(camerasJson);
        setState(() {
          cameras.clear();
          cameras.addAll(
            camerasList.map((json) => CameraData.fromJson(json)).toList(),
          );
        });
        
        // Inicializar serviços para câmeras carregadas
        for (final camera in cameras) {
          _stateService.initializeCamera(camera.id.toString());
          _healthService.startHealthCheck(camera);
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar câmeras: $e');
    }
  }
  
  Future<void> _persistCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final camerasJson = json.encode(
        cameras.map((camera) => camera.toJson()).toList(),
      );
      await prefs.setString('cameras', camerasJson);
    } catch (e) {
      debugPrint('Erro ao salvar câmeras: $e');
    }
  }
  
  void _setupNotificationListener() {
    // Setup notification listener
    _notificationService.onNotificationAdded = (notification) {
      _loadNotifications();
    };
  }
  
  Future<void> _loadNotifications() async {
    final notifications = _notificationService.getNotifications();
    setState(() {
      _notifications = notifications;
    });
  }
  
  void _showNotification(NotificationData notification) {
    // Show motion detection notification
    _notificationService.addNotification(
      CameraNotification.motionDetected(
        cameraId: notification.cameraId.toString(),
        cameraName: cameras.firstWhere(
          (c) => c.id.toString() == notification.cameraId.toString(), 
          orElse: () => const CameraData(
            id: 0, 
            name: 'Desconhecida', 
            isLive: false, 
            statusColor: Colors.grey, 
            uniqueColor: Colors.grey, 
            icon: Icons.videocam, 
            streamUrl: ''
          )
        ).name,
      ),
    );
  }
  
  // Helper para chamar setState com segurança
  void safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // Métodos para obter estados de loading e callbacks de play/pause
  Map<int, bool> _getLoadingStates() {
    final Map<int, bool> loadingStates = {};
    for (final camera in cameras) {
      loadingStates[camera.id] = _stateService.isLoading(camera.id.toString());
    }
    return loadingStates;
  }

  Map<int, VoidCallback> _getPlayPauseCallbacks() {
    final Map<int, VoidCallback> callbacks = {};
    for (final camera in cameras) {
      callbacks[camera.id] = () {
        final isPlaying = _stateService.isPlaying(camera.id.toString());
        if (isPlaying) {
          _stateService.pauseVideo(camera.id.toString());
        } else {
          _stateService.playVideo(camera.id.toString());
        }
      };
    }
    return callbacks;
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _showAddCameraDialog(),
            tooltip: 'Adicionar Câmera',
          ),
          Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: ElevatedButton.icon(
                onPressed: _isDiscovering ? null : _startAdvancedDiscovery,
                icon: _isDiscovering 
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      )
                    : const Icon(Icons.search, size: 18),
                label: Text(_isDiscovering ? 'Descobrindo...' : 'Descobrir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDiscovering 
                      ? const Color(0xFF2A2A2A).withOpacity(0.6)
                      : const Color(0xFF2A2A2A),
                  foregroundColor: _isDiscovering 
                      ? Colors.white70 
                      : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              _showSettingsDialog();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Status da descoberta avançada
          if (_isDiscovering && _currentProgress != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.blue.withOpacity(0.1),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Descoberta avançada: ${_currentProgress!.phase}',
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _currentProgress!.total > 0 ? _currentProgress!.current / _currentProgress!.total : 0,
                    backgroundColor: Colors.blue.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_currentProgress!.current}/${_currentProgress!.total} - ${_currentProgress!.discoveredCameras.length} dispositivos encontrados',
                    style: const TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                  if (_currentProgress!.currentDevice != null)
                    Text(
                      'Analisando: ${_currentProgress!.currentDevice}',
                      style: const TextStyle(color: Colors.blue, fontSize: 11),
                    ),
                ],
              ),
            ),
          
          // Erro de descoberta
          if (_discoveryError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.red.withValues(alpha: 0.1),
              child: Text(
                _discoveryError!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          
          // Dispositivos descobertos
          if (_discoveredDevices.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dispositivos encontrados: ${_discoveredDevices.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...(_discoveredDevices.map((device) => 
                    Card(
                      color: const Color(0xFF2A2A2A),
                      child: ListTile(
                        leading: Icon(
                          device['isCamera'] == true ? Icons.videocam : Icons.device_hub,
                          color: device['isCamera'] == true ? Colors.blue : Colors.orange,
                        ),
                        title: Text(
                          device['name'] ?? 'Dispositivo Desconhecido',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'IP: ${device['ip']}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            if (device['manufacturer'] != null)
                              Text(
                                'Fabricante: ${device['manufacturer']}',
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            if (device['protocols'] != null && device['protocols'].isNotEmpty)
                              Text(
                                'Protocolos: ${device['protocols'].join(', ')}',
                                style: const TextStyle(color: Colors.green, fontSize: 12),
                              ),
                          ],
                        ),
                        trailing: device['isCamera'] == true
                            ? ElevatedButton(
                                onPressed: () => _connectToDiscoveredDevice(device),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                child: const Text('Conectar'),
                              )
                            : null,
                      ),
                    ),
                  )),
                ],
              ),
            ),
          
          // Conteúdo principal
          Expanded(
            child: Column(
              children: [
                // Área superior com grid de câmeras e controles
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      // Grid de câmeras (lado esquerdo)
                      Expanded(
                        flex: 2,
                        child: cameras.isEmpty
                            ? _buildEmptyCamerasPlaceholder()
                            : CameraGridWidget(
                                cameras: cameras,
                                selectedCamera: _selectedCamera,
                                onCameraSelected: (camera) {
                                  setState(() {
                                    _selectedCamera = camera;
                                  });
                                },
                                onAddCamera: () => _showAddCameraDialog(),
                                onCameraEdit: _editCamera,
                                onCameraRemove: (camera) => _removeCamera(camera.id),
                                connectionManager: _connectionManager,
                                reconnectionService: _reconnectionService,
                                connectionStates: _connectionStates,
                              ),
                      ),
                      
                      // Controles da câmera selecionada (lado direito)
                      if (_selectedCamera != null)
                        Expanded(
                          flex: 1,
                          child: CameraControls(
                            cameraId: _selectedCamera!.id.toString(),
                            onControlAction: _handlePtzControl,
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Painel de notificações na parte inferior
                Container(
                  height: 200,
                  margin: const EdgeInsets.only(top: 16),
                  child: NotificationPanel(
                    notifications: _notifications,
                    onNotificationTap: _handleNotificationTap,
                    onNotificationDismiss: _dismissNotification,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyCamerasPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.videocam_off,
            size: 80,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma câmera configurada',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione uma câmera para começar a monitorar',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddCameraDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar Câmera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _showAddCameraDialog() async {
    print('DEBUG: Abrindo diálogo de adição de câmera');
    
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AddCameraDialog(),
      );
      
      if (result == true) {
        print('DEBUG: Câmera adicionada com sucesso, recarregando lista');
        
        // Recarregar as câmeras persistidas
        await _loadPersistedCameras();
        
        // Atualizar o estado
        if (mounted) {
          setState(() {
            // A lista já foi atualizada pelo _loadPersistedCameras
          });
          
          // Mostrar confirmação
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Câmera adicionada e carregada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        print('DEBUG: Lista de câmeras atualizada - Total: ${cameras.length}');
      }
    } catch (e) {
      print('ERRO: Falha ao abrir diálogo de adição: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir diálogo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  void _addCamera(
    String name,
    String host,
    String port,
    String username,
    String password,
    String transport,
    bool acceptSelfSigned,
    CameraPortConfiguration? portConfiguration,
  ) {
    final int cameraPort = int.tryParse(port) ?? 554;
    final auth = (username.isNotEmpty && password.isNotEmpty)
        ? '${RtspConstants.encodeCredentials(username, password)}@'
        : '';
    final String streamUrl = 'rtsp://$auth$host:$cameraPort/cam/realmonitor?channel=1&subtype=1';
    
    final camera = CameraData(
      id: DateTime.now().millisecondsSinceEpoch,
      name: name,
      isLive: false,
      statusColor: const Color(0xFF888888),
      uniqueColor: Color(CameraData.generateUniqueColor(DateTime.now().millisecondsSinceEpoch)),
      icon: Icons.videocam_outlined,
      streamUrl: streamUrl,
      username: username.isEmpty ? null : username,
      password: password.isEmpty ? null : password,
      port: cameraPort,
      transport: transport,
      acceptSelfSigned: acceptSelfSigned,
      portConfiguration: portConfiguration,
    );
    
    setState(() {
      cameras.add(camera);
    });
    
    // Configurar reconexão automática para a nova câmera
    if (username.isNotEmpty && password.isNotEmpty) {
      final credentials = Credentials(
        username: username,
        password: password,
      );
      _reconnectionService.configureCameraReconnection(
        camera.id.toString(),
        [streamUrl],
        credentials,
      );
    }

    // Log da adição da câmera
    _loggingService.logConnection(
      camera.id.toString(),
      '$host:$port',
      'info',
      'Câmera adicionada ao sistema',
    );
    
    _stateService.initializeCamera(camera.id.toString());
    _healthService.startHealthCheck(camera);
    _persistCameras();
    
    _showNotification(
      NotificationData(
        cameraId: camera.id,
        message: 'Câmera adicionada: $name',
        time: 'agora',
        statusColor: const Color(0xFF4CAF50),
      ),
    );
  }
  
  Future<void> _loadDiscoveredDevices() async {
    try {
      final cachedDevices = await FastCameraDiscoveryService.getCachedDevices();
      print('DEBUG: Carregando ${cachedDevices.length} dispositivos do cache');
      
      int cameraCount = 0;
      int totalDevices = cachedDevices.length;
      
      setState(() {
        _discoveredDevices = cachedDevices.where((device) {
          // Determinar se é uma câmera baseado nos metadados
          bool isCamera = false;
          List<String> protocols = [];
          
          if (device['metadata'] != null) {
            // Verificar protocolos nos metadados
            if (device['metadata'].containsKey('protocols')) {
              protocols = List<String>.from(device['metadata']['protocols'] ?? []);
            }
            
            // Lógica mais flexível para identificação de câmeras
            if (device['protocol'] == 'ONVIF' || 
                device['protocol'] == 'RTSP' ||
                device['protocol'] == 'HTTP' ||
                protocols.contains('ONVIF') ||
                protocols.contains('RTSP') ||
                protocols.contains('HTTP') ||
                protocols.contains('WS-Discovery') ||
                protocols.contains('Unknown') || // Aceita dispositivos em portas comuns mesmo sem protocolo identificado
                (device['metadata'].containsKey('isCameraDevice') && device['metadata']['isCameraDevice'] == true) ||
                (device['metadata'].containsKey('isMediaDevice') && device['metadata']['isMediaDevice'] == true) ||
                (device['metadata'].containsKey('hasCameraServices') && device['metadata']['hasCameraServices'] == true) ||
                (device['metadata'].containsKey('priority') && (device['metadata']['priority'] ?? 0) >= 9)) {
              isCamera = true;
            }
            
            // Se tem porta comum de câmera, considera como câmera
            if (!isCamera && device['ports'] != null) {
              final ports = List<int>.from(device['ports']);
              final commonCameraPorts = [80, 554, 8080, 8081, 8000, 8888, 8899, 9000, 10080, 37777, 34567];
              if (ports.any((port) => commonCameraPorts.contains(port))) {
                isCamera = true;
              }
            }
            
            // Verificar se tem serviços de mídia específicos de câmera
            if (device['metadata'].containsKey('services')) {
              final services = device['metadata']['services'] as List<dynamic>? ?? [];
              for (var service in services) {
                if (service.toString().toLowerCase().contains('camera') ||
                    service.toString().toLowerCase().contains('video') ||
                    service.toString().toLowerCase().contains('media')) {
                  isCamera = true;
                  break;
                }
              }
            }
          }
          
          // Se não tem metadados mas o protocolo indica câmera
          if (!isCamera && (device['protocol'] == 'ONVIF' || device['protocol'] == 'WS-Discovery')) {
            isCamera = true;
          }
          
          // Filtrar apenas dispositivos que são câmeras
          if (isCamera) {
            cameraCount++;
            print('DEBUG: CÂMERA ENCONTRADA - ${device['name']} (${device['ip']}) - protocol: ${device['protocol']}, protocols: $protocols');
              return true;
            } else {
             print('DEBUG: DISPOSITIVO IGNORADO (não é câmera) - ${device['name']} (${device['ip']}) - protocol: ${device['protocol']}');
            return false;
          }
        }).map((device) {
          List<String> protocols = [];
          if (device['metadata'] != null && device['metadata'].containsKey('protocols')) {
            protocols = List<String>.from(device['metadata']['protocols'] ?? []);
          }
          
          return {
            'name': device['name'],
            'ip': device['ip'],
            'manufacturer': device['manufacturer'],
            'protocol': device['protocol'],
            'protocols': protocols,
            'ports': device['ports'],
            'isOnline': device['isOnline'],
            'metadata': device['metadata'],
            'isCamera': true, // Todos os dispositivos aqui são câmeras
          };
        }).toList();
      });
      
      print('DEBUG: ===== RELATÓRIO DE DESCOBERTA =====');
      print('DEBUG: Total de dispositivos encontrados: $totalDevices');
      print('DEBUG: Câmeras identificadas: $cameraCount');
      print('DEBUG: Dispositivos não-câmera filtrados: ${totalDevices - cameraCount}');
      print('DEBUG: =====================================');
      
      // Mostrar mensagem informativa ao usuário
      if (cameraCount > 0) {
        _showNotification(NotificationData(
          cameraId: 0,
          message: 'Descoberta concluída: $cameraCount câmera(s) encontrada(s)',
          time: 'agora',
          statusColor: const Color(0xFF4CAF50), // Verde para sucesso
        ));
      } else if (totalDevices > 0) {
        _showNotification(NotificationData(
          cameraId: 0,
          message: 'Descoberta concluída: $totalDevices dispositivo(s) encontrado(s), mas nenhuma câmera identificada',
          time: 'agora',
          statusColor: const Color(0xFFFF9800), // Laranja para aviso
        ));
      } else {
        _showNotification(NotificationData(
          cameraId: 0,
          message: 'Descoberta concluída: Nenhum dispositivo encontrado na rede',
          time: 'agora',
          statusColor: const Color(0xFFF44336), // Vermelho para erro
        ));
      }
    } catch (e) {
      setState(() {
        _discoveryError = 'Erro ao carregar dispositivos: $e';
      });
    }
  }
  
  Future<void> _startAdvancedDiscovery() async {
    try {
      setState(() {
        _isDiscovering = true;
        _discoveryError = null;
        _discoveredDevices.clear();
      });
      
      // Mostrar mensagem de início da descoberta
      _showNotification(NotificationData(
        cameraId: 0,
        message: 'Iniciando descoberta de câmeras na rede...',
        time: 'agora',
        statusColor: const Color(0xFF2196F3), // Azul para informação
      ));
      
      await FastCameraDiscoveryService.discover();
    } catch (e) {
      setState(() {
        _isDiscovering = false;
        _discoveryError = 'Erro na descoberta: $e';
      });
      
      // Mostrar mensagem de erro na descoberta
      _showNotification(NotificationData(
        cameraId: 0,
        message: 'Erro na descoberta de câmeras: $e',
        time: 'agora',
        statusColor: const Color(0xFFF44336), // Vermelho para erro
      ));
    }
  }
  
  void _connectToOnvifDevice(Map<String, dynamic> device) async {
    final credentials = await CameraDialogs.showOnvifCredentialsDialog(
      context,
      device['name'] ?? 'Dispositivo ONVIF',
    );
    
    if (credentials != null) {
      // Implementar conexão ao dispositivo ONVIF
      final ip = device['xAddr']?.toString().split('://')[1].split(':')[0] ?? device['ip']?.toString() ?? '';
      await FastCameraDiscoveryService.connectToDevice(
        ip,
        credentials.username,
        credentials.password,
      );
    }
  }
  
  Future<void> _connectToDiscoveredDevice(Map<String, dynamic> device) async {
    try {
      setState(() {
        _isConnecting = true;
      });

      final String? ip = device['ip'];
      if (ip == null) {
        _showNotification(NotificationData(
          cameraId: 0,
          message: 'Erro: IP do dispositivo não encontrado',
          time: 'agora',
          statusColor: Colors.red,
        ));
        return;
      }

      print('DEBUG: Conectando ao dispositivo descoberto: ${device['name']} ($ip)');
      
      // Primeiro, tentar conectar sem credenciais
      bool needsAuth = await _checkIfDeviceNeedsAuth(device);
      
      String? username;
      String? password;
      
      if (needsAuth) {
        // Mostrar diálogo de credenciais
        final credentials = await _showCredentialsDialog(
          deviceName: device['name'] ?? 'Dispositivo Descoberto',
          deviceIp: ip,
        );
        if (credentials == null) {
          // Usuário cancelou
          return;
        }
        username = credentials['username'];
        password = credentials['password'];
      }
      
      // Determinar porta baseada nos protocolos disponíveis
      String port = '554'; // Padrão RTSP
      
      if (device['protocols'] != null) {
        final protocols = List<String>.from(device['protocols']);
        print('Protocolos disponíveis: $protocols');
        if (protocols.contains('ONVIF')) {
          port = '80';
        } else if (protocols.contains('RTSP')) {
          port = '554';
        }
      }
      
      // Construir URL RTSP com ou sem credenciais
      final auth = (username != null && password != null) ? '$username:$password@' : '';
      final streamUrl = 'rtsp://$auth$ip:$port/cam/realmonitor?channel=1&subtype=0';
      
      print('DEBUG: URL RTSP construída: $streamUrl');

      // Criar nova câmera com as informações do dispositivo descoberto
      final camera = CameraData(
        id: DateTime.now().millisecondsSinceEpoch,
        name: device['name'] ?? 'Câmera Descoberta',
        isLive: false,
        statusColor: const Color(0xFF888888),
        uniqueColor: Color(CameraData.generateUniqueColor(DateTime.now().millisecondsSinceEpoch)),
        icon: Icons.videocam_outlined,
        streamUrl: streamUrl,
        username: username,
        password: password,
        port: int.tryParse(port) ?? 554,
        transport: 'tcp',
        acceptSelfSigned: false,
      );

      setState(() {
        cameras.add(camera);
      });
      
      _stateService.initializeCamera(camera.id.toString());
      _healthService.startHealthCheck(camera);
      await _persistCameras();
      
      print('DEBUG: Dispositivo conectado e salvo com sucesso');

      _showNotification(NotificationData(
        cameraId: camera.id,
        message: 'Câmera "${camera.name}" adicionada com sucesso!',
        time: 'agora',
        statusColor: const Color(0xFF4CAF50),
      ));
      
    } catch (e) {
      print('ERRO: Falha ao conectar ao dispositivo: $e');
      _showNotification(NotificationData(
        cameraId: 0,
        message: 'Erro ao conectar dispositivo: $e',
        time: 'agora',
        statusColor: Colors.red,
      ));
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }
  
  void _editCamera(CameraData camera) {
    CameraDialogs.showEditCameraDialog(
      context,
      title: 'Editar Câmera',
      initialName: camera.name,
      initialHost: camera.getHost(),
      initialPort: camera.port?.toString() ?? '554',
      initialUsername: camera.username ?? '',
      initialPassword: camera.password ?? '',
      initialTransport: camera.transport,
      initialAcceptSelfSigned: camera.acceptSelfSigned,
      initialPortConfiguration: camera.portConfiguration,
      onSave: (result) {
        _updateCamera(
          camera.id,
          result.name,
          result.host,
          result.port,
          result.username,
          result.password,
          result.transport,
          result.acceptSelfSigned,
          result.portConfiguration,
        );
      },
    );
  }
  
  void _updateCamera(
    int id,
    String name,
    String host,
    String port,
    String username,
    String password,
    String transport,
    bool acceptSelfSigned,
    CameraPortConfiguration? portConfiguration,
  ) {
    final idx = cameras.indexWhere((c) => c.id == id);
    if (idx >= 0) {
      final int cameraPort = int.tryParse(port) ?? 554;
      final auth = (username.isNotEmpty && password.isNotEmpty)
          ? '${RtspConstants.encodeCredentials(username, password)}@'
          : '';
      final String streamUrl = 'rtsp://$auth$host:$cameraPort/cam/realmonitor?channel=1&subtype=1';
      
      setState(() {
        final current = cameras[idx];
        cameras[idx] = CameraData(
          id: id,
          name: name,
          isLive: false,
          statusColor: const Color(0xFF888888),
          uniqueColor: current.uniqueColor,
          icon: Icons.videocam_outlined,
          streamUrl: streamUrl,
          username: username.isEmpty ? null : username,
          password: password.isEmpty ? null : password,
          port: cameraPort,
          transport: transport,
          capabilities: current.capabilities,
          acceptSelfSigned: acceptSelfSigned,
          portConfiguration: portConfiguration ?? current.portConfiguration,
        );
      });
      
      _persistCameras();
      
      _showNotification(
        NotificationData(
          cameraId: id,
          message: 'Câmera atualizada: $name',
          time: 'agora',
          statusColor: const Color(0xFF4CAF50),
        ),
      );
    }
  }
  
  void _removeCamera(int id) {
    setState(() {
      cameras.removeWhere((c) => c.id == id);
    });
    
    _stateService.disposeCamera(id.toString());
    _healthService.stopHealthCheck(id.toString());
    _persistCameras();
  }
  
  void _showCameraSettings(CameraData camera) {
    // Implementar diálogo de configurações da câmera
  }

  Widget _buildCameraControlsRow(CameraData camera) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: () => _editCamera(camera),
          icon: const Icon(Icons.edit, color: Colors.blue),
          tooltip: 'Editar câmera',
        ),
        IconButton(
          onPressed: () => _showCameraSettings(camera),
          icon: const Icon(Icons.settings, color: Colors.grey),
          tooltip: 'Configurações',
        ),
        IconButton(
          onPressed: () => _removeCamera(camera.id),
          icon: const Icon(Icons.delete, color: Colors.red),
          tooltip: 'Remover câmera',
        ),
      ],
    );
  }
  
  void _showSettingsDialog() {
    CameraDialogs.showSettingsDialog(
      context,
      backgroundOnvifDetection: _onvifDetectionEnabled,
      onBackgroundDetectionChanged: (enabled) {
        setState(() {
          _onvifDetectionEnabled = enabled;
        });
      },
      onForceCapabilitiesDetection: () {
        // Implementar re-detecção de capacidades
      },
    );
  }
  
  /// Verifica se o dispositivo precisa de autenticação
  Future<bool> _checkIfDeviceNeedsAuth(Map<String, dynamic> device) async {
    try {
      final String? ip = device['ip'];
      if (ip == null) return false;
      
      // Tentar conectar sem credenciais primeiro
      final testUrl = 'rtsp://$ip:554/cam/realmonitor?channel=1&subtype=0';
      print('DEBUG: Testando conexão sem credenciais: $testUrl');
      
      // Simular teste de conexão (em uma implementação real, você faria uma conexão RTSP de teste)
      // Por enquanto, assumir que dispositivos com certas características precisam de auth
      final deviceName = device['name']?.toString().toLowerCase() ?? '';
      
      // Heurística: se o dispositivo tem "secure" no nome ou é de certas marcas, provavelmente precisa de auth
      if (deviceName.contains('secure') || 
          deviceName.contains('hikvision') || 
          deviceName.contains('dahua') ||
          deviceName.contains('axis')) {
        print('DEBUG: Dispositivo provavelmente requer autenticação baseado no nome');
        return true;
      }
      
      print('DEBUG: Dispositivo provavelmente não requer autenticação');
      return false;
    } catch (e) {
      print('DEBUG: Erro ao verificar autenticação, assumindo que precisa: $e');
      return true; // Em caso de erro, assumir que precisa de auth
    }
  }

  /// Mostra diálogo para inserir credenciais da câmera descoberta
  Future<Map<String, String>?> _showCredentialsDialog({
    required String deviceName,
    required String deviceIp,
  }) async {
    final TextEditingController usernameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    bool obscurePassword = true;
    
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.videocam, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Conectar Câmera',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dispositivo: $deviceName',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'IP: $deviceIp',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Credenciais (opcional):',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Usuário',
                        hintText: 'admin',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        hintText: 'Digite a senha da câmera',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Você pode conectar sem credenciais primeiro. Se necessário, edite a câmera depois para adicionar usuário e senha.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(null);
                  },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop({
                      'username': usernameController.text.trim(),
                      'password': passwordController.text.trim(),
                    });
                  },
                  child: const Text('Conectar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  // Métodos de controle PTZ e notificações
  void _handlePtzControl(String cameraId, String direction) async {
    if (_selectedCamera != null) {
      // Implementar controle PTZ
      print('PTZ Control: $direction for camera ${_selectedCamera!.name}');
    }
  }

  void _handleZoomControl(String action) async {
    if (_selectedCamera != null) {
      // Implementar controle de zoom
      print('Zoom Control: $action for camera ${_selectedCamera!.name}');
    }
  }

  void _toggleRecording() async {
    if (_selectedCamera != null) {
      // Implementar toggle de gravação
      print('Toggle recording for camera ${_selectedCamera!.name}');
    }
  }

  void _handleNotificationTap(CameraNotification notification) async {
    // Marcar como lida
    _notificationService.markAsRead(notification.id);
    await _loadNotifications();
    
    // Navegar para a câmera relacionada se aplicável
    if (notification.cameraId != null) {
      try {
        final camera = cameras.firstWhere(
          (c) => c.id.toString() == notification.cameraId,
        );
        setState(() {
          _selectedCamera = camera;
        });
      } catch (e) {
        // Câmera não encontrada, não fazer nada
        print('Câmera com ID ${notification.cameraId} não encontrada');
      }
    }
  }

  void _dismissNotification(String notificationId) async {
    _notificationService.removeNotification(notificationId);
    await _loadNotifications();
  }
  
  /// Configura monitoramento de conexões
  void _setupConnectionMonitoring() {
    // Configurar listeners para mudanças de estado de conexão
    _connectionManager.onConnectionStateChanged = (cameraId, state) {
      if (mounted) {
        setState(() {
          _connectionStates[cameraId] = state;
        });
      }
    };
  }

  /// Conecta uma câmera usando o sistema de conexão integrado
  Future<void> _connectCamera(CameraModel camera) async {
    try {
      setState(() {
        _loadingStates[camera.id] = true;
      });

      final credentials = Credentials(
        username: camera.username,
        password: camera.password,
      );

      // Tentar conectar usando o gerenciador de conexões
      final result = await _connectionManager.connectToCamera(
        camera.id,
        camera.host,
        camera.port,
        credentials,
        transport: camera.transport,
      );

      if (result.isSuccess) {
        setState(() {
          camera.status = CameraStatus.connected;
          camera.lastSeen = DateTime.now();
        });
        
        await _persistCameras();
        _showNotification('Conectado à câmera "${camera.name}"');
      } else {
        setState(() {
          camera.status = CameraStatus.disconnected;
        });
        
        _showNotification('Falha ao conectar: ${result.error}');
      }
    } catch (e) {
      setState(() {
        camera.status = CameraStatus.error;
      });
      
      _showNotification('Erro na conexão: $e');
    } finally {
      setState(() {
        _loadingStates[camera.id] = false;
      });
    }
  }

  @override
  void dispose() {
    _disposeServices();
    // Limpar listeners
    _notificationService.onNotificationAdded = null;
    super.dispose();
  }
}