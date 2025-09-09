import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/camera_model.dart';
import '../services/camera_service.dart';
import '../services/notification_service.dart';
import '../dialogs/add_camera_dialog.dart';
import '../dialogs/edit_camera_dialog.dart';
import '../widgets/camera_grid.dart';
import '../widgets/camera_controls.dart';
import '../widgets/notification_panel.dart';
import 'settings_screen.dart';
import 'camera_diagnostics_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final CameraService _cameraService = CameraService.instance;
  final NotificationService _notificationService = NotificationService.instance;
  
  List<CameraModel> _cameras = [];
  List<CameraNotification> _notifications = [];
  CameraModel? _selectedCamera;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    try {
      await _loadCameras();
      await _loadNotifications();
      _setupListeners();
    } catch (e) {
      debugPrint('Erro ao inicializar tela principal: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCameras() async {
    try {
      if (mounted) {
        setState(() {
          _cameras = _cameraService.cameras;
          if (_cameras.isNotEmpty && _selectedCamera == null) {
            _selectedCamera = _cameras.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar câmeras: $e');
    }
  }

  Future<void> _loadNotifications() async {
    try {
      if (mounted) {
        setState(() {
          _notifications = _notificationService.notifications;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar notificações: $e');
    }
  }

  void _setupListeners() {
    // Listener para mudanças nas câmeras
    _cameraService.onCameraStatusChanged = (camera) {
      if (mounted) {
        _loadCameras();
      }
    };

    // Listener para novas notificações
    _notificationService.onNotificationAdded = (notification) {
      if (mounted) {
        setState(() {
          _notifications.insert(0, notification);
        });
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sistema de Câmeras'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _onAddCamera,
            tooltip: 'Adicionar Câmera',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCameras,
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.medical_services),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CameraDiagnosticsScreen(),
                ),
              );
            },
            tooltip: 'Diagnóstico de Câmeras',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
            tooltip: 'Configurações',
          ),
        ],
      ),
      body: Row(
        children: [
          // Grid de câmeras (lado esquerdo)
              Expanded(
                flex: 2,
                child: _cameras.isEmpty
                    ? _buildEmptyState()
                    : CameraGrid(
                        cameras: _cameras,
                        selectedCamera: _selectedCamera,
                        onCameraSelected: (camera) {
                          setState(() {
                            _selectedCamera = camera;
                          });
                        },
                        onCameraEdit: _editCamera,
                        onCameraRemove: (camera) => _removeCamera(camera),
                      ),
              ),
          
          // Painel lateral direito
          Expanded(
            flex: 1,
            child: Column(
              children: [
                // Controles da câmera selecionada
                if (_selectedCamera != null)
                  Expanded(
                    flex: 2,
                    child: CameraControls(
                      cameraId: _selectedCamera!.id,
                      onControlAction: _handlePtzControl,
                    ),
                  ),
                
                // Painel de notificações
                Expanded(
                  flex: 1,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.videocam_off,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma câmera conectada',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Toque no botão + para adicionar uma câmera',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _onAddCamera,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar Câmera'),
          ),
        ],
      ),
    );
  }





  // Método para adicionar câmera
  void _onAddCamera() {
    showDialog(
      context: context,
      builder: (context) => AddCameraDialog(
        onAdd: (camera) async {
          try {
              await _cameraService.addCamera(camera);
              // Removed proprietary protocol connection - cameras will use RTSP directly
              // await _cameraService.connectToCamera(camera);
              await _loadCameras();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Câmera adicionada com sucesso'),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erro ao adicionar câmera: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  // Métodos de callback para os widgets
  void _editCamera(CameraModel camera) async {
    final result = await showDialog<CameraModel>(
      context: context,
      builder: (context) => EditCameraDialog(camera: camera),
    );
    
    if (result != null) {
      await _cameraService.updateCamera(result);
      await _loadCameras();
    }
  }

  void _removeCamera(CameraModel camera) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Câmera'),
        content: Text('Deseja remover a câmera "${camera.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _cameraService.removeCamera(camera.id);
      if (_selectedCamera?.id == camera.id) {
        setState(() {
          _selectedCamera = null;
        });
      }
      await _loadCameras();
    }
  }

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
      final camera = _cameras.firstWhere(
        (c) => c.id == notification.cameraId,
        orElse: () => _cameras.first,
      );
      setState(() {
        _selectedCamera = camera;
      });
    }
  }

  void _dismissNotification(String notificationId) async {
    _notificationService.removeNotification(notificationId);
    await _loadNotifications();
  }

  @override
  void dispose() {
    // Limpar listeners
    _cameraService.onCameraStatusChanged = null;
    _notificationService.onNotificationAdded = null;
    super.dispose();
  }
}