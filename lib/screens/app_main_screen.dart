import 'package:flutter/material.dart';

import '../models/camera_status.dart';
import '../models/notification_model.dart';
import '../services/camera_service.dart';
import '../services/notification_service.dart';
import '../widgets/camera_grid.dart';
import '../widgets/notification_panel.dart';
import '../widgets/camera_controls.dart';

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
  bool _isLoading = true;
  String? _selectedCameraId;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    try {
      // Carregar câmeras salvas
      await _loadCameras();
      
      // Carregar notificações
      _notifications = _notificationService.getAllNotifications();
      
      // Configurar listeners
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
    // Simular carregamento de câmeras
    _cameras = [
      CameraModel(
        id: 'camera_1',
        name: 'Câmera Frontal',
        ipAddress: '192.168.1.100',
        port: 8000,
        username: 'admin',
        password: 'admin123',
        status: CameraStatus.online,
        isRecording: false,
        motionDetectionEnabled: true,
        nightModeEnabled: false,
        audioEnabled: true,
        customColor: Colors.blue,
      ),
      CameraModel(
        id: 'camera_2',
        name: 'Câmera Lateral',
        ipAddress: '192.168.1.101',
        port: 8000,
        username: 'admin',
        password: 'admin123',
        status: CameraStatus.offline,
        isRecording: false,
        motionDetectionEnabled: false,
        nightModeEnabled: true,
        audioEnabled: false,
        customColor: Colors.green,
      ),
    ];
  }

  void _setupListeners() {
    // Listener para notificações
    _notificationService.notificationStream.listen((notification) {
      if (mounted) {
        setState(() {
          _notifications = _notificationService.getAllNotifications();
        });
      }
    });
  }

  void _onCameraSelected(String cameraId) {
    setState(() {
      _selectedCameraId = cameraId;
    });
  }

  void _onCameraEdit(CameraModel camera) {
    // Implementar edição de câmera
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${camera.name}'),
        content: const Text('Funcionalidade de edição será implementada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _onCameraRemove(CameraModel camera) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Câmera'),
        content: Text('Deseja remover a câmera "${camera.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _cameras.removeWhere((c) => c.id == camera.id);
              });
              Navigator.of(context).pop();
            },
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  void _onAddCamera() {
    // Implementar adição de câmera
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar Câmera'),
        content: const Text('Funcionalidade de adição será implementada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
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
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navegar para configurações
            },
            tooltip: 'Configurações',
          ),
        ],
      ),
      body: Row(
        children: [
          // Grid de câmeras
          Expanded(
            flex: 3,
            child: CameraGrid(
              cameras: _cameras,
              selectedCameraId: _selectedCameraId,
              onCameraSelected: _onCameraSelected,
              onCameraEdit: _onCameraEdit,
              onCameraRemove: _onCameraRemove,
            ),
          ),
          
          // Painel lateral
          Container(
            width: 300,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            child: Column(
              children: [
                // Controles da câmera selecionada
                if (_selectedCameraId != null)
                  Expanded(
                    flex: 2,
                    child: CameraControls(
                      camera: _cameras.firstWhere(
                        (c) => c.id == _selectedCameraId,
                      ),
                      onCameraUpdated: (updatedCamera) {
                        setState(() {
                          final index = _cameras.indexWhere(
                            (c) => c.id == updatedCamera.id,
                          );
                          if (index != -1) {
                            _cameras[index] = updatedCamera;
                          }
                        });
                      },
                    ),
                  ),
                
                // Painel de notificações
                Expanded(
                  flex: 3,
                  child: NotificationPanel(
                    notifications: _notifications,
                    onNotificationRead: (notificationId) {
                      _notificationService.markAsRead(notificationId);
                      setState(() {
                        _notifications = _notificationService.getAllNotifications();
                      });
                    },
                    onNotificationRemove: (notificationId) {
                      _notificationService.removeNotification(notificationId);
                      setState(() {
                        _notifications = _notificationService.getAllNotifications();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}