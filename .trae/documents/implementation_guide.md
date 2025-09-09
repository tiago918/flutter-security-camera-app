# Guia de Implementação - Redesign do App de Câmeras

## 1. Visão Geral das Modificações

Este documento detalha as modificações específicas necessárias em cada arquivo do projeto para implementar o redesign solicitado.

## 2. Modificações na Navegação Principal

### 2.1 Arquivo: `lib/screens/app_main_screen.dart`

**Modificações necessárias:**
- Remover MainScreen da lista de telas
- Alterar índice inicial para 0 (DevicesAndCamerasScreen)
- Reduzir BottomNavigationBar para 3 itens

```dart
// ANTES: 4 telas incluindo MainScreen
final List<Widget> _screens = const [
  MainScreen(),
  DevicesAndCamerasScreen(),
  AccessControlScreen(),
  SettingsScreen(),
];

// DEPOIS: 3 telas, DevicesAndCamerasScreen como inicial
final List<Widget> _screens = const [
  DevicesAndCamerasScreen(), // Nova tela inicial
  AccessControlScreen(),
  SettingsScreen(),
];

// ANTES: 4 itens no BottomNavigationBar
items: const [
  BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Início'),
  BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Câmeras'),
  BottomNavigationBarItem(icon: Icon(Icons.security), label: 'Acesso'),
  BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Configurações'),
],

// DEPOIS: 3 itens no BottomNavigationBar
items: const [
  BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Câmeras'),
  BottomNavigationBarItem(icon: Icon(Icons.security), label: 'Acesso'),
  BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Configurações'),
],
```

## 3. Modificações na Tela de Câmeras

### 3.1 Arquivo: `lib/screens/devices_and_cameras_screen.dart`

**Modificações necessárias:**
- Adicionar painel de notificações na parte inferior
- Mover botões do AppBar para área mais visível
- Adicionar botão "Descobrir"
- Integrar NotificationPanel da MainScreen

```dart
// Estrutura modificada do build method
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Câmeras de Segurança'),
      backgroundColor: Colors.grey[900],
      // Remover actions do AppBar
    ),
    body: Column(
      children: [
        // Nova seção de botões no topo
        _buildActionButtons(),
        
        // Grid de câmeras existente (mantido)
        Expanded(
          flex: 2,
          child: _buildCameraGrid(),
        ),
        
        // Novo painel de notificações na parte inferior
        Expanded(
          flex: 1,
          child: _buildNotificationPanel(),
        ),
      ],
    ),
  );
}

// Novo método para botões de ação
Widget _buildActionButtons() {
  return Container(
    padding: const EdgeInsets.all(16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: _showAddCameraDialog,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _discoverDevices,
          icon: const Icon(Icons.search),
          label: const Text('Descobrir'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
}

// Novo método para painel de notificações
Widget _buildNotificationPanel() {
  return Container(
    decoration: BoxDecoration(
      color: Colors.grey[850],
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Notificações',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Consumer<NotificationService>(
            builder: (context, notificationService, child) {
              return EnhancedNotificationPanel(
                notifications: _getEnhancedNotifications(notificationService.notifications),
                onNotificationTap: _handleNotificationTap,
                onNotificationDismiss: _handleNotificationDismiss,
              );
            },
          ),
        ),
      ],
    ),
  );
}
```

## 4. Criação de Novos Componentes

### 4.1 Arquivo: `lib/widgets/enhanced_camera_card.dart` (NOVO)

```dart
import 'package:flutter/material.dart';
import '../models/camera_data.dart';
import '../models/camera_controls.dart';
import 'camera_controls_bar.dart';

class EnhancedCameraCard extends StatelessWidget {
  final CameraData camera;
  final CameraControls controls;
  final VoidCallback onMenuTap;
  final Function(String) onControlTap;
  final VoidCallback onStreamTap;

  const EnhancedCameraCard({
    Key? key,
    required this.camera,
    required this.controls,
    required this.onMenuTap,
    required this.onControlTap,
    required this.onStreamTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[800],
      child: Column(
        children: [
          // Header com nome da câmera e menu
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  camera.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) => _handleMenuAction(value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'reload',
                      child: Row(
                        children: [
                          Icon(Icons.refresh, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Recarregar stream', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Editar câmera', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Remover câmera', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Player de vídeo (mantém proporção atual)
          Expanded(
            child: GestureDetector(
              onTap: onStreamTap,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildVideoPlayer(),
              ),
            ),
          ),
          
          // Barra de controles na parte inferior
          CameraControlsBar(
            camera: camera,
            controls: controls,
            onControlTap: onControlTap,
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    // Implementação do player mantendo a lógica atual
    // mas com melhorias de performance e tratamento de erros
    return Container(
      child: camera.isLive
          ? _buildLiveStream()
          : _buildOfflineIndicator(),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'reload':
        onControlTap('reload_stream');
        break;
      case 'edit':
        onControlTap('edit_camera');
        break;
      case 'remove':
        onControlTap('remove_camera');
        break;
    }
  }
}
```

### 4.2 Arquivo: `lib/widgets/camera_controls_bar.dart` (NOVO)

```dart
import 'package:flutter/material.dart';
import '../models/camera_data.dart';
import '../models/camera_controls.dart';

class CameraControlsBar extends StatelessWidget {
  final CameraData camera;
  final CameraControls controls;
  final Function(String) onControlTap;

  const CameraControlsBar({
    Key? key,
    required this.camera,
    required this.controls,
    required this.onControlTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: Icons.control_camera,
            isActive: false,
            onTap: () => onControlTap('ptz'),
            tooltip: 'Controle PTZ',
          ),
          _buildControlButton(
            icon: controls.audioMuted ? Icons.volume_off : Icons.volume_up,
            isActive: !controls.audioMuted,
            onTap: () => onControlTap('audio'),
            tooltip: 'Som',
          ),
          _buildControlButton(
            icon: Icons.motion_photos_on,
            isActive: controls.motionDetectionEnabled,
            onTap: () => onControlTap('motion'),
            tooltip: 'Detecção de movimento',
          ),
          _buildControlButton(
            icon: Icons.nightlight,
            isActive: controls.nightModeEnabled,
            onTap: () => onControlTap('night_mode'),
            tooltip: 'Modo noturno',
          ),
          _buildControlButton(
            icon: Icons.lightbulb,
            isActive: controls.irLightEnabled,
            onTap: () => onControlTap('ir_light'),
            tooltip: 'Luz infravermelha',
          ),
          _buildControlButton(
            icon: Icons.wb_incandescent,
            isActive: controls.visibleLightEnabled,
            onTap: () => onControlTap('visible_light'),
            tooltip: 'Luz visível',
          ),
          _buildControlButton(
            icon: Icons.notifications,
            isActive: controls.notificationsEnabled,
            onTap: () => onControlTap('notifications'),
            tooltip: 'Notificações',
          ),
          _buildControlButton(
            icon: Icons.video_library,
            isActive: false,
            onTap: () => onControlTap('recordings'),
            tooltip: 'Vídeos gravados',
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            color: isActive ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            icon,
            color: isActive ? Colors.white : Colors.grey[400],
            size: 20,
          ),
        ),
      ),
    );
  }
}
```

### 4.3 Arquivo: `lib/models/camera_controls.dart` (NOVO)

```dart
class CameraControls {
  final int cameraId;
  bool audioMuted;
  bool motionDetectionEnabled;
  bool nightModeEnabled;
  bool irLightEnabled;
  bool visibleLightEnabled;
  bool notificationsEnabled;
  
  CameraControls({
    required this.cameraId,
    this.audioMuted = false,
    this.motionDetectionEnabled = true,
    this.nightModeEnabled = false,
    this.irLightEnabled = false,
    this.visibleLightEnabled = false,
    this.notificationsEnabled = true,
  });
  
  Map<String, dynamic> toJson() => {
    'cameraId': cameraId,
    'audioMuted': audioMuted,
    'motionDetectionEnabled': motionDetectionEnabled,
    'nightModeEnabled': nightModeEnabled,
    'irLightEnabled': irLightEnabled,
    'visibleLightEnabled': visibleLightEnabled,
    'notificationsEnabled': notificationsEnabled,
  };
  
  factory CameraControls.fromJson(Map<String, dynamic> json) => CameraControls(
    cameraId: json['cameraId'],
    audioMuted: json['audioMuted'] ?? false,
    motionDetectionEnabled: json['motionDetectionEnabled'] ?? true,
    nightModeEnabled: json['nightModeEnabled'] ?? false,
    irLightEnabled: json['irLightEnabled'] ?? false,
    visibleLightEnabled: json['visibleLightEnabled'] ?? false,
    notificationsEnabled: json['notificationsEnabled'] ?? true,
  );
  
  CameraControls copyWith({
    int? cameraId,
    bool? audioMuted,
    bool? motionDetectionEnabled,
    bool? nightModeEnabled,
    bool? irLightEnabled,
    bool? visibleLightEnabled,
    bool? notificationsEnabled,
  }) {
    return CameraControls(
      cameraId: cameraId ?? this.cameraId,
      audioMuted: audioMuted ?? this.audioMuted,
      motionDetectionEnabled: motionDetectionEnabled ?? this.motionDetectionEnabled,
      nightModeEnabled: nightModeEnabled ?? this.nightModeEnabled,
      irLightEnabled: irLightEnabled ?? this.irLightEnabled,
      visibleLightEnabled: visibleLightEnabled ?? this.visibleLightEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }
}
```

## 5. Modificações nos Serviços

### 5.1 Arquivo: `lib/services/camera_service.dart`

**Adicionar novos métodos para controles:**

```dart
// Adicionar ao CameraService existente
class CameraService extends ChangeNotifier {
  // ... código existente mantido ...
  
  // Novos métodos para controles
  Future<void> toggleCameraControl(int cameraId, String controlType, bool value) async {
    try {
      final camera = _cameras.firstWhere((c) => c.id == cameraId);
      
      switch (controlType) {
        case 'audio':
          await _sendOnvifCommand(camera, 'SetAudioOutputMute', {'Mute': value});
          break;
        case 'motion':
          await _sendOnvifCommand(camera, 'SetMotionDetection', {'Enabled': value});
          break;
        case 'night_mode':
          await _sendOnvifCommand(camera, 'SetIrCutFilter', {'IrCutFilter': value ? 'OFF' : 'ON'});
          break;
        case 'ir_light':
          await _sendOnvifCommand(camera, 'SetIrLights', {'Enabled': value});
          break;
        case 'visible_light':
          await _sendOnvifCommand(camera, 'SetWhiteLight', {'Enabled': value});
          break;
      }
      
      notifyListeners();
    } catch (e) {
      print('Erro ao controlar câmera: $e');
    }
  }
  
  Future<void> sendPTZCommand(int cameraId, String direction) async {
    try {
      final camera = _cameras.firstWhere((c) => c.id == cameraId);
      await _sendOnvifCommand(camera, 'ContinuousMove', {
        'ProfileToken': 'Profile_1',
        'Velocity': _getPTZVelocity(direction),
      });
    } catch (e) {
      print('Erro no comando PTZ: $e');
    }
  }
  
  Future<List<Recording>> getCameraRecordings(int cameraId) async {
    try {
      final camera = _cameras.firstWhere((c) => c.id == cameraId);
      // Implementar busca de gravações no cartão SD da câmera
      return await _fetchRecordingsFromCamera(camera);
    } catch (e) {
      print('Erro ao buscar gravações: $e');
      return [];
    }
  }
  
  Future<void> reloadCameraStream(int cameraId) async {
    try {
      final cameraIndex = _cameras.indexWhere((c) => c.id == cameraId);
      if (cameraIndex != -1) {
        _cameras[cameraIndex] = _cameras[cameraIndex].copyWith(isLive: false);
        notifyListeners();
        
        // Aguardar um momento antes de reconectar
        await Future.delayed(const Duration(seconds: 2));
        
        _cameras[cameraIndex] = _cameras[cameraIndex].copyWith(isLive: true);
        notifyListeners();
      }
    } catch (e) {
      print('Erro ao recarregar stream: $e');
    }
  }
}
```

## 6. Melhorias no Player de Vídeo

### 6.1 Arquivo: `lib/widgets/camera_stream_widget.dart`

**Modificações para melhor performance e tratamento de erros:**

```dart
// Adicionar ao widget existente
class CameraStreamWidget extends StatefulWidget {
  // ... código existente ...
  
  @override
  State<CameraStreamWidget> createState() => _CameraStreamWidgetState();
}

class _CameraStreamWidgetState extends State<CameraStreamWidget> {
  // ... código existente mantido ...
  
  // Melhorias no tratamento de erros
  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }
  
  Future<void> _initializePlayer() async {
    try {
      if (widget.camera.streamUrl.isNotEmpty) {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.camera.streamUrl),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
        
        await _controller!.initialize();
        
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _hasError = false;
          });
          
          _controller!.play();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Erro ao conectar: ${e.toString()}';
        });
      }
    }
  }
  
  // Método para reconexão automática
  void _attemptReconnection() {
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_hasError && mounted) {
        _initializePlayer();
      } else {
        timer.cancel();
      }
    });
  }
}
```

## 7. Resumo das Modificações

### Arquivos a serem modificados:
1. `lib/screens/app_main_screen.dart` - Remover MainScreen, ajustar navegação
2. `lib/screens/devices_and_cameras_screen.dart` - Adicionar notificações e botões
3. `lib/widgets/camera_stream_widget.dart` - Melhorar player de vídeo
4. `lib/services/camera_service.dart` - Adicionar métodos de controle

### Arquivos a serem criados:
1. `lib/widgets/enhanced_camera_card.dart` - Card aprimorado com controles
2. `lib/widgets/camera_controls_bar.dart` - Barra de controles
3. `lib/models/camera_controls.dart` - Modelo de dados para controles
4. `lib/widgets/enhanced_notification_panel.dart` - Painel aprimorado

### Funcionalidades implementadas:
- ✅ Remoção da página inicial
- ✅ Movimentação das notificações
- ✅ Reorganização dos botões
- ✅ Controles do player de câmera
- ✅ Menu de opções da câmera
- ✅ Melhorias no player de vídeo

Todas as modificações preservam a estrutura existente e adicionam apenas as funcionalidades solicitadas.