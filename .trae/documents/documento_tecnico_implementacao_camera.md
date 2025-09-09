# Documento Técnico - Implementação Completa do App de Câmeras

## 1. Visão Geral do Projeto

Este documento detalha a implementação completa das funcionalidades solicitadas para o aplicativo de câmeras de segurança, incluindo:

* Botões de controle do player de vídeo

* Sistema de notificações organizadas por câmera

* Menu de opções do card de câmera

* Correções de formato/codec do player

* Arquitetura modular baseada no protocolo proprietário identificado

## 2. Arquitetura do Sistema

### 2.1 Estrutura de Arquivos Proposta

```
lib/
├── core/
│   ├── constants/
│   │   ├── camera_constants.dart
│   │   └── ui_constants.dart
│   ├── protocols/
│   │   ├── camera_protocol.dart
│   │   └── stream_protocol.dart
│   └── utils/
│       ├── codec_utils.dart
│       └── network_utils.dart
├── models/
│   ├── camera_model.dart
│   ├── notification_model.dart
│   ├── recording_model.dart
│   ├── ptz_command_model.dart
│   └── stream_config_model.dart
├── services/
│   ├── camera_service.dart
│   ├── notification_service.dart
│   ├── recording_service.dart
│   ├── ptz_service.dart
│   ├── audio_service.dart
│   ├── motion_detection_service.dart
│   └── night_mode_service.dart
├── providers/
│   ├── camera_provider.dart
│   ├── notification_provider.dart
│   ├── player_provider.dart
│   └── settings_provider.dart
├── widgets/
│   ├── camera_card/
│   │   ├── camera_card.dart
│   │   ├── camera_options_menu.dart
│   │   └── camera_status_indicator.dart
│   ├── player/
│   │   ├── video_player_widget.dart
│   │   ├── player_controls.dart
│   │   └── codec_error_handler.dart
│   ├── controls/
│   │   ├── ptz_control_button.dart
│   │   ├── audio_control_button.dart
│   │   ├── motion_detection_button.dart
│   │   ├── night_mode_button.dart
│   │   ├── notification_button.dart
│   │   └── recordings_button.dart
│   ├── notifications/
│   │   ├── notification_list.dart
│   │   ├── notification_item.dart
│   │   └── camera_notification_badge.dart
│   └── dialogs/
│       ├── ptz_control_dialog.dart
│       ├── night_mode_dialog.dart
│       ├── recordings_dialog.dart
│       └── camera_edit_dialog.dart
└── screens/
    ├── camera_main_screen.dart
    ├── camera_detail_screen.dart
    └── settings_screen.dart
```

### 2.2 Protocolo de Comunicação

Baseado na análise dos arquivos fornecidos, o sistema utiliza:

* **Porta 34567**: Comandos de controle (protocolo proprietário)

* **Porta 2223**: Stream de vídeo

* **Porta 8899**: Interface web de configuração

* **IP Remoto**: 82.115.15.137 (servidor da fabricante)

* **IP Local**: 192.168.3.49 (acesso direto)

## 3. Modelos de Dados

### 3.1 Camera Model

```dart
// lib/models/camera_model.dart
class CameraModel {
  final String id;
  final String name;
  final String ip;
  final String username;
  final String password;
  final Color themeColor;
  final bool isConnected;
  final bool isAuthenticated;
  final bool isStreaming;
  final CameraCapabilities capabilities;
  final StreamConfig streamConfig;
  
  CameraModel({
    required this.id,
    required this.name,
    required this.ip,
    required this.username,
    required this.password,
    required this.themeColor,
    this.isConnected = false,
    this.isAuthenticated = false,
    this.isStreaming = false,
    required this.capabilities,
    required this.streamConfig,
  });
}

class CameraCapabilities {
  final bool supportsPTZ;
  final bool supportsAudio;
  final bool supportsMotionDetection;
  final bool supportsNightMode;
  final bool supportsIRLight;
  final bool supportsVisibleLight;
  final bool supportsRecording;
  
  CameraCapabilities({
    this.supportsPTZ = false,
    this.supportsAudio = false,
    this.supportsMotionDetection = false,
    this.supportsNightMode = false,
    this.supportsIRLight = false,
    this.supportsVisibleLight = false,
    this.supportsRecording = false,
  });
}
```

### 3.2 Notification Model

```dart
// lib/models/notification_model.dart
class CameraNotification {
  final String id;
  final String cameraId;
  final String cameraName;
  final Color cameraColor;
  final NotificationType type;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? metadata;
  
  CameraNotification({
    required this.id,
    required this.cameraId,
    required this.cameraName,
    required this.cameraColor,
    required this.type,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.metadata,
  });
}

enum NotificationType {
  motionDetected,
  connectionLost,
  connectionRestored,
  recordingStarted,
  recordingStopped,
  codecError,
  authenticationFailed,
  streamError,
}
```

### 3.3 PTZ Command Model

```dart
// lib/models/ptz_command_model.dart
class PTZCommand {
  final String cameraId;
  final PTZAction action;
  final PTZDirection? direction;
  final int speed; // 1-10
  final int? zoomLevel;
  
  PTZCommand({
    required this.cameraId,
    required this.action,
    this.direction,
    this.speed = 5,
    this.zoomLevel,
  });
  
  Map<String, dynamic> toProtocolPayload() {
    return {
      'Cmd': 'PTZ',
      'Channel': 0,
      'Action': action.name,
      'Direction': direction?.name,
      'Speed': speed,
      if (zoomLevel != null) 'ZoomLevel': zoomLevel,
    };
  }
}

enum PTZAction {
  move,
  zoom,
  stop,
}

enum PTZDirection {
  up,
  down,
  left,
  right,
  upLeft,
  upRight,
  downLeft,
  downRight,
  zoomIn,
  zoomOut,
}
```

## 4. Serviços Especializados

### 4.1 Camera Service

```dart
// lib/services/camera_service.dart
class CameraService {
  static const int CONTROL_PORT = 34567;
  static const int STREAM_PORT = 2223;
  static const int WEB_PORT = 8899;
  
  Socket? _controlSocket;
  Socket? _streamSocket;
  
  Future<bool> connectCamera(CameraModel camera) async {
    try {
      // Conecta à porta de controle
      _controlSocket = await Socket.connect(camera.ip, CONTROL_PORT);
      
      // Autentica usando protocolo identificado
      bool authenticated = await _authenticate(camera);
      
      if (authenticated) {
        // Conecta ao stream de vídeo
        _streamSocket = await Socket.connect(camera.ip, STREAM_PORT);
        return true;
      }
      
      return false;
    } catch (e) {
      print('Erro ao conectar câmera: $e');
      return false;
    }
  }
  
  Future<bool> _authenticate(CameraModel camera) async {
    // Implementa protocolo de autenticação MD5 identificado
    final passwordHash = md5.convert(utf8.encode(camera.password)).toString();
    
    final loginPayload = {
      'EncryptType': 'MD5',
      'LoginType': 'DVRIP-Web',
      'PassWord': passwordHash,
      'UserName': camera.username,
    };
    
    final command = _buildCommand(0x00010000, loginPayload);
    _controlSocket?.add(command);
    
    // Aguarda resposta de autenticação
    // Implementar leitura da resposta
    return true; // Simplificado
  }
  
  List<int> _buildCommand(int commandId, Map<String, dynamic> payload) {
    // Implementa estrutura do protocolo identificado
    String jsonPayload = jsonEncode(payload);
    List<int> payloadBytes = utf8.encode(jsonPayload);
    
    ByteData buffer = ByteData(12 + payloadBytes.length);
    buffer.setUint32(0, 0xff000000, Endian.big); // Header
    buffer.setUint32(4, commandId, Endian.little); // Command ID
    buffer.setUint32(8, payloadBytes.length, Endian.little); // Payload length
    
    List<int> command = buffer.buffer.asUint8List().toList();
    command.addAll(payloadBytes);
    
    return command;
  }
}
```

### 4.2 PTZ Service

```dart
// lib/services/ptz_service.dart
class PTZService {
  final CameraService _cameraService;
  
  PTZService(this._cameraService);
  
  Future<bool> executePTZCommand(PTZCommand command) async {
    try {
      final payload = command.toProtocolPayload();
      final binaryCommand = _cameraService._buildCommand(0x00040000, payload);
      
      _cameraService._controlSocket?.add(binaryCommand);
      await _cameraService._controlSocket?.flush();
      
      return true;
    } catch (e) {
      print('Erro ao executar comando PTZ: $e');
      return false;
    }
  }
  
  Future<bool> moveCamera(String cameraId, PTZDirection direction, int speed) async {
    final command = PTZCommand(
      cameraId: cameraId,
      action: PTZAction.move,
      direction: direction,
      speed: speed,
    );
    
    return await executePTZCommand(command);
  }
  
  Future<bool> zoomCamera(String cameraId, PTZDirection zoomDirection, int level) async {
    final command = PTZCommand(
      cameraId: cameraId,
      action: PTZAction.zoom,
      direction: zoomDirection,
      zoomLevel: level,
    );
    
    return await executePTZCommand(command);
  }
  
  Future<bool> stopPTZ(String cameraId) async {
    final command = PTZCommand(
      cameraId: cameraId,
      action: PTZAction.stop,
    );
    
    return await executePTZCommand(command);
  }
}
```

### 4.3 Motion Detection Service

```dart
// lib/services/motion_detection_service.dart
class MotionDetectionService {
  final CameraService _cameraService;
  final NotificationService _notificationService;
  
  MotionDetectionService(this._cameraService, this._notificationService);
  
  Future<bool> enableMotionDetection(String cameraId, MotionSettings settings) async {
    try {
      final payload = {
        'Cmd': 'SetMotionDetection',
        'Channel': 0,
        'Enable': true,
        'Sensitivity': settings.sensitivity,
        'Areas': settings.detectionAreas.map((area) => area.toMap()).toList(),
      };
      
      final command = _cameraService._buildCommand(0x00050000, payload);
      _cameraService._controlSocket?.add(command);
      
      return true;
    } catch (e) {
      print('Erro ao ativar detecção de movimento: $e');
      return false;
    }
  }
  
  Future<bool> disableMotionDetection(String cameraId) async {
    try {
      final payload = {
        'Cmd': 'SetMotionDetection',
        'Channel': 0,
        'Enable': false,
      };
      
      final command = _cameraService._buildCommand(0x00050000, payload);
      _cameraService._controlSocket?.add(command);
      
      return true;
    } catch (e) {
      print('Erro ao desativar detecção de movimento: $e');
      return false;
    }
  }
  
  void _handleMotionDetected(String cameraId, Map<String, dynamic> data) {
    _notificationService.addNotification(
      CameraNotification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        cameraId: cameraId,
        cameraName: data['cameraName'] ?? 'Câmera',
        cameraColor: Color(data['cameraColor'] ?? 0xFF2196F3),
        type: NotificationType.motionDetected,
        message: 'Movimento detectado',
        timestamp: DateTime.now(),
        metadata: data,
      ),
    );
  }
}

class MotionSettings {
  final int sensitivity; // 1-10
  final List<DetectionArea> detectionAreas;
  
  MotionSettings({
    this.sensitivity = 5,
    this.detectionAreas = const [],
  });
}

class DetectionArea {
  final double x, y, width, height;
  
  DetectionArea({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }
}
```

### 4.4 Night Mode Service

```dart
// lib/services/night_mode_service.dart
class NightModeService {
  final CameraService _cameraService;
  
  NightModeService(this._cameraService);
  
  Future<bool> setNightMode(String cameraId, NightModeConfig config) async {
    try {
      final payload = {
        'Cmd': 'SetNightMode',
        'Channel': 0,
        'Mode': config.mode.name,
        'IRLightEnabled': config.irLightEnabled,
        'VisibleLightEnabled': config.visibleLightEnabled,
        'AutoSwitch': config.autoSwitch,
        'SwitchThreshold': config.switchThreshold,
      };
      
      final command = _cameraService._buildCommand(0x00060000, payload);
      _cameraService._controlSocket?.add(command);
      
      return true;
    } catch (e) {
      print('Erro ao configurar modo noturno: $e');
      return false;
    }
  }
  
  Future<bool> toggleIRLight(String cameraId, bool enabled) async {
    try {
      final payload = {
        'Cmd': 'SetIRLight',
        'Channel': 0,
        'Enable': enabled,
      };
      
      final command = _cameraService._buildCommand(0x00061000, payload);
      _cameraService._controlSocket?.add(command);
      
      return true;
    } catch (e) {
      print('Erro ao controlar luz IR: $e');
      return false;
    }
  }
  
  Future<bool> toggleVisibleLight(String cameraId, bool enabled) async {
    try {
      final payload = {
        'Cmd': 'SetVisibleLight',
        'Channel': 0,
        'Enable': enabled,
      };
      
      final command = _cameraService._buildCommand(0x00062000, payload);
      _cameraService._controlSocket?.add(command);
      
      return true;
    } catch (e) {
      print('Erro ao controlar luz visível: $e');
      return false;
    }
  }
}

class NightModeConfig {
  final NightMode mode;
  final bool irLightEnabled;
  final bool visibleLightEnabled;
  final bool autoSwitch;
  final int switchThreshold; // 0-100
  
  NightModeConfig({
    this.mode = NightMode.auto,
    this.irLightEnabled = true,
    this.visibleLightEnabled = false,
    this.autoSwitch = true,
    this.switchThreshold = 50,
  });
}

enum NightMode {
  auto,
  day,
  night,
}
```

### 4.5 Recording Service

```dart
// lib/services/recording_service.dart
class RecordingService {
  final CameraService _cameraService;
  
  RecordingService(this._cameraService);
  
  Future<List<Recording>> getRecordings(String cameraId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start = startDate ?? DateTime.now().subtract(Duration(days: 7));
      final end = endDate ?? DateTime.now();
      
      final payload = {
        'Cmd': 'GetRecordList',
        'Channel': 0,
        'StartTime': _formatDateTime(start),
        'EndTime': _formatDateTime(end),
        'EventType': 'All',
      };
      
      final command = _cameraService._buildCommand(0x00020000, payload);
      _cameraService._controlSocket?.add(command);
      
      // Aguarda resposta e parseia lista de gravações
      // Implementar leitura da resposta
      
      return []; // Simplificado
    } catch (e) {
      print('Erro ao obter gravações: $e');
      return [];
    }
  }
  
  Future<bool> startPlayback(String cameraId, Recording recording) async {
    try {
      final payload = {
        'Cmd': 'StartPlayback',
        'Channel': 0,
        'FileName': recording.fileName,
        'StartTime': _formatDateTime(recording.startTime),
      };
      
      final command = _cameraService._buildCommand(0x00030000, payload);
      _cameraService._controlSocket?.add(command);
      
      return true;
    } catch (e) {
      print('Erro ao iniciar reprodução: $e');
      return false;
    }
  }
  
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-'
           '${dateTime.month.toString().padLeft(2, '0')}-'
           '${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}:'
           '${dateTime.second.toString().padLeft(2, '0')}';
  }
}

class Recording {
  final String fileName;
  final DateTime startTime;
  final DateTime endTime;
  final int size;
  final RecordingType type;
  
  Recording({
    required this.fileName,
    required this.startTime,
    required this.endTime,
    required this.size,
    required this.type,
  });
}

enum RecordingType {
  continuous,
  motion,
  alarm,
  manual,
}
```

## 5. Widgets Especializados

### 5.1 Player Controls

```dart
// lib/widgets/controls/player_controls.dart
class PlayerControls extends StatelessWidget {
  final String cameraId;
  final CameraCapabilities capabilities;
  
  const PlayerControls({
    Key? key,
    required this.cameraId,
    required this.capabilities,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (capabilities.supportsPTZ)
            PTZControlButton(cameraId: cameraId),
          if (capabilities.supportsAudio)
            AudioControlButton(cameraId: cameraId),
          if (capabilities.supportsMotionDetection)
            MotionDetectionButton(cameraId: cameraId),
          if (capabilities.supportsNightMode)
            NightModeButton(cameraId: cameraId),
          NotificationButton(cameraId: cameraId),
          if (capabilities.supportsRecording)
            RecordingsButton(cameraId: cameraId),
        ],
      ),
    );
  }
}
```

### 5.2 PTZ Control Button

```dart
// lib/widgets/controls/ptz_control_button.dart
class PTZControlButton extends StatelessWidget {
  final String cameraId;
  
  const PTZControlButton({Key? key, required this.cameraId}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.control_camera, color: Colors.white),
      onPressed: () => _showPTZDialog(context),
      tooltip: 'Controle PTZ',
    );
  }
  
  void _showPTZDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => PTZControlDialog(cameraId: cameraId),
    );
  }
}
```

### 5.3 Night Mode Button

```dart
// lib/widgets/controls/night_mode_button.dart
class NightModeButton extends StatelessWidget {
  final String cameraId;
  
  const NightModeButton({Key? key, required this.cameraId}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Consumer<CameraProvider>(builder: (context, provider, child) {
      final camera = provider.getCamera(cameraId);
      final isNightMode = camera?.isNightModeEnabled ?? false;
      
      return IconButton(
        icon: Icon(
          isNightMode ? Icons.nightlight : Icons.wb_sunny,
          color: isNightMode ? Colors.blue : Colors.yellow,
        ),
        onPressed: () => _showNightModeDialog(context),
        tooltip: 'Modo Noturno',
      );
    });
  }
  
  void _showNightModeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => NightModeDialog(cameraId: cameraId),
    );
  }
}
```

### 5.4 Camera Options Menu

```dart
// lib/widgets/camera_card/camera_options_menu.dart
class CameraOptionsMenu extends StatelessWidget {
  final String cameraId;
  
  const CameraOptionsMenu({Key? key, required this.cameraId}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      child: PopupMenuButton<CameraAction>(
        icon: Icon(
          Icons.more_vert,
          color: Colors.white,
          shadows: [Shadow(color: Colors.black, blurRadius: 2)],
        ),
        onSelected: (action) => _handleAction(context, action),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: CameraAction.edit,
            child: Row(
              children: [
                Icon(Icons.edit, size: 20),
                SizedBox(width: 8),
                Text('Editar'),
              ],
            ),
          ),
          PopupMenuItem(
            value: CameraAction.reloadStream,
            child: Row(
              children: [
                Icon(Icons.refresh, size: 20),
                SizedBox(width: 8),
                Text('Recarregar Stream'),
              ],
            ),
          ),
          PopupMenuItem(
            value: CameraAction.remove,
            child: Row(
              children: [
                Icon(Icons.delete, size: 20, color: Colors.red),
                SizedBox(width: 8),
                Text('Remover Câmera', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _handleAction(BuildContext context, CameraAction action) {
    final provider = Provider.of<CameraProvider>(context, listen: false);
    
    switch (action) {
      case CameraAction.edit:
        _showEditDialog(context);
        break;
      case CameraAction.reloadStream:
        provider.reloadStream(cameraId);
        break;
      case CameraAction.remove:
        _showRemoveConfirmation(context, provider);
        break;
    }
  }
  
  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => CameraEditDialog(cameraId: cameraId),
    );
  }
  
  void _showRemoveConfirmation(BuildContext context, CameraProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remover Câmera'),
        content: Text('Tem certeza que deseja remover esta câmera?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              provider.removeCamera(cameraId);
              Navigator.pop(context);
            },
            child: Text('Remover', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

enum CameraAction {
  edit,
  reloadStream,
  remove,
}
```

### 5.5 Notification List

```dart
// lib/widgets/notifications/notification_list.dart
class NotificationList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(builder: (context, provider, child) {
      final notifications = provider.notifications;
      
      if (notifications.isEmpty) {
        return Center(
          child: Text(
            'Nenhuma notificação',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      
      // Agrupa notificações por câmera
      final groupedNotifications = _groupNotificationsByCamera(notifications);
      
      return ListView.builder(
        itemCount: groupedNotifications.length,
        itemBuilder: (context, index) {
          final cameraId = groupedNotifications.keys.elementAt(index);
          final cameraNotifications = groupedNotifications[cameraId]!;
          
          return CameraNotificationGroup(
            cameraId: cameraId,
            notifications: cameraNotifications,
          );
        },
      );
    });
  }
  
  Map<String, List<CameraNotification>> _groupNotificationsByCamera(
    List<CameraNotification> notifications,
  ) {
    final Map<String, List<CameraNotification>> grouped = {};
    
    for (final notification in notifications) {
      if (!grouped.containsKey(notification.cameraId)) {
        grouped[notification.cameraId] = [];
      }
      grouped[notification.cameraId]!.add(notification);
    }
    
    return grouped;
  }
}

class CameraNotificationGroup extends StatelessWidget {
  final String cameraId;
  final List<CameraNotification> notifications;
  
  const CameraNotificationGroup({
    Key? key,
    required this.cameraId,
    required this.notifications,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final firstNotification = notifications.first;
    
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho da câmera
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: firstNotification.cameraColor.withOpacity(0.1),
              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: firstNotification.cameraColor,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  firstNotification.cameraName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: firstNotification.cameraColor,
                  ),
                ),
                Spacer(),
                Text(
                  '${notifications.length} notificações',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          // Lista de notificações
          ...notifications.map((notification) => NotificationItem(
            notification: notification,
          )).toList(),
        ],
      ),
    );
  }
}
```

## 6. Correções de Codec

### 6.1 Codec Error Handler

```dart
// lib/widgets/player/codec_error_handler.dart
class CodecErrorHandler {
  static const List<String> SUPPORTED_CODECS = [
    'H.264',
    'H.265',
    'MJPEG',
    'MPEG-4',
  ];
  
  static Widget buildErrorWidget(String error, String cameraId) {
    if (error.contains('codec') || error.contains('format')) {
      return CodecErrorWidget(
        error: error,
        cameraId: cameraId,
        onRetry: () => _attemptCodecFix(cameraId),
      );
    }
    
    return GenericErrorWidget(error: error);
  }
  
  static Future<void> _attemptCodecFix(String cameraId) async {
    // Tenta diferentes configurações de codec
    final configs = [
      StreamConfig(codec: 'H.264', resolution: '1920x1080'),
      StreamConfig(codec: 'H.264', resolution: '1280x720'),
      StreamConfig(codec: 'MJPEG', resolution: '1280x720'),
      StreamConfig(codec: 'MPEG-4', resolution: '640x480'),
    ];
    
    for (final config in configs) {
      try {
        await _applyStreamConfig(cameraId, config);
        break; // Se funcionou, para aqui
      } catch (e) {
        continue; // Tenta próxima configuração
      }
    }
  }
  
  static Future<void> _applyStreamConfig(String cameraId, StreamConfig config) async {
    // Implementa mudança de configuração via protocolo
    final payload = {
      'Cmd': 'SetStreamConfig',
      'Channel': 0,
      'Codec': config.codec,
      'Resolution': config.resolution,
      'Bitrate': config.bitrate,
      'FPS': config.fps,
    };
    
    // Envia comando para câmera
    // Implementar envio via CameraService
  }
}

class CodecErrorWidget extends StatelessWidget {
  final String error;
  final String cameraId;
  final VoidCallback onRetry;
  
  const CodecErrorWidget({
    Key? key,
    required this.error,
    required this.cameraId,
    required this.onRetry,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.orange,
          ),
          SizedBox(height: 16),
          Text(
            'Formato/codec não suportado pelo player',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Tentando usar o substream em H.264',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }
}

Possíveis Melhorias
1. Configuração da StreamConfig
dart
// O código atual não mostra a implementação completa
StreamConfig(codec: 'H.264', resolution: '1920x1080')
Sugestão: Adicionar propriedades bitrate e fps:

dart
class StreamConfig {
  final String codec;
  final String resolution;
  final int bitrate;
  final int fps;
  
  StreamConfig({
    required this.codec,
    required this.resolution,
    this.bitrate = 2000000, // 2Mbps padrão
    this.fps = 25,
  });
}
2. Logging e Feedback
dart
static Future<void> _attemptCodecFix(String cameraId) async {
  for (final config in configs) {
    try {
      print('Tentando codec: ${config.codec} - ${config.resolution}');
      await _applyStreamConfig(cameraId, config);
      print('Sucesso com: ${config.codec}');
      break;
    } catch (e) {
      print('Falhou: ${config.codec} - $e');
      continue;
    }
  }
}
3. Implementação do CameraService
dart
static Future<void> _applyStreamConfig(String cameraId, StreamConfig config) async {
  final payload = {
    'Cmd': 'SetStreamConfig',
    'Channel': 0,
    'Codec': config.codec,
    'Resolution': config.resolution,
    'Bitrate': config.bitrate,
    'FPS': config.fps,
  };
  
  try {
    await CameraService.sendCommand(cameraId, payload);
    // Aguardar confirmação ou timeout
    await Future.delayed(Duration(seconds: 2));
  } catch (e) {
    throw Exception('Falha ao aplicar configuração: $e');
  }
}
4. Estado de Loading
Adicionar indicador visual durante tentativas:

dart
class CodecErrorWidget extends StatefulWidget {
  // ... propriedades existentes
  
  @override
  _CodecErrorWidgetState createState() => _CodecErrorWidgetState();
}

class _CodecErrorWidgetState extends State<CodecErrorWidget> {
  bool isRetrying = false;
  
  void _handleRetry() async {
    setState(() => isRetrying = true);
    await widget.onRetry();
    if (mounted) setState(() => isRetrying = false);
  }
  
  @override
  Widget build(BuildContext context) {
    // ... código existente
    ElevatedButton(
      onPressed: isRetrying ? null : _handleRetry,
      child: isRetrying 
        ? CircularProgressIndicator(color: Colors.white)
        : Text('Tentar Novamente'),
    ),
  }
}
5. Tratamento de Casos Específicos
dart
static Widget buildErrorWidget(String error, String cameraId) {
  if (error.contains('codec') || error.contains('format')) {
    return CodecErrorWidget(
      error: error,
      cameraId: cameraId,
      onRetry: () => _attemptCodecFix(cameraId),
    );
  } else if (error.contains('network') || error.contains('timeout')) {
    return NetworkErrorWidget(error: error, cameraId: cameraId);
  }
  
  return GenericErrorWidget(error: error);
}
Considerações de Performance
Cache de configurações bem-sucedidas por câmera

Timeout adequado para cada tentativa

Limit de tentativas para evitar loops infinitos
```

## 7. Integração e Configuração

### 7.1 Main Provider Setup

```dart
// lib/main.dart
void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CameraProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MyApp(),
    ),
  );
```

### 7.2 Camera Provider

```dart
// lib/providers/camera_provider.dart
class CameraProvider extends ChangeNotifier {
  final Map<String, CameraModel> _cameras = {};
  final Map<String, CameraService> _services = {};
  final PTZService _ptzService = PTZService();
  final MotionDetectionService _motionService = MotionDetectionService();
  final NightModeService _nightModeService = NightModeService();
  final RecordingService _recordingService = RecordingService();
  
  List<CameraModel> get cameras => _cameras.values.toList();
  
  void addCamera(CameraModel camera) {
    _cameras[camera.id] = camera;
    _services[camera.id] = CameraService();
    notifyListeners();
  }
  
  Future<bool> connectCamera(String cameraId) async {
    final camera = _cameras[cameraId];
    final service = _services[cameraId];
    
    if (camera == null || service == null) return false;
    
    try {
      bool connected = await service.connectCamera(camera);
      if (connected) {
        _cameras[cameraId] = camera.copyWith(isConnected: true);
        notifyListeners();
      }
      return connected;
    } catch (e) {
      print('Erro ao conectar câmera: $e');
      return false;
    }
  }
  
  Future<void> reloadStream(String cameraId) async {
    final service = _services[cameraId];
    if (service != null) {
      await service.reconnectStream();
      notifyListeners();
    }
  }
  
  void removeCamera(String cameraId) {
    _cameras.remove(cameraId);
    _services[cameraId]?.disconnect();
    _services.remove(cameraId);
    notifyListeners();
  }
  
  // Métodos para controles específicos
  Future<bool> executePTZCommand(String cameraId, PTZCommand command) async {
    return await _ptzService.executePTZCommand(command);
  }
  
  Future<bool> toggleMotionDetection(String cameraId, bool enabled) async {
    if (enabled) {
      return await _motionService.enableMotionDetection(
        cameraId,
        MotionSettings(),
      );
    } else {
      return await _motionService.disableMotionDetection(cameraId);
    }
  }
  
  Future<bool> setNightMode(String cameraId, NightModeConfig config) async {
    return await _nightModeService.setNightMode(cameraId, config);
  }
  
  Future<List<Recording>> getRecordings(String cameraId) async {
    return await _recordingService.getRecordings(cameraId);
  }
}

Possíveis Melhorias
1. Tratamento de Erros Mais Robusto

class CameraProvider extends ChangeNotifier {
  // ... código existente
  
  Future<CameraConnectionResult> connectCamera(String cameraId) async {
    final camera = _cameras[cameraId];
    final service = _services[cameraId];
    
    if (camera == null || service == null) {
      return CameraConnectionResult.failure('Câmera não encontrada');
    }
    
    try {
      bool connected = await service.connectCamera(camera);
      if (connected) {
        _cameras[cameraId] = camera.copyWith(
          isConnected: true,
          lastConnectionAttempt: DateTime.now(),
        );
        notifyListeners();
        return CameraConnectionResult.success();
      }
      
      return CameraConnectionResult.failure('Falha na conexão');
    } catch (e) {
      _cameras[cameraId] = camera.copyWith(
        isConnected: false,
        lastError: e.toString(),
        lastConnectionAttempt: DateTime.now(),
      );
      notifyListeners();
      return CameraConnectionResult.failure('Erro: ${e.toString()}');
    }
  }
}

class CameraConnectionResult {
  final bool success;
  final String? error;
  
  CameraConnectionResult._(this.success, this.error);
  
  factory CameraConnectionResult.success() => CameraConnectionResult._(true, null);
  factory CameraConnectionResult.failure(String error) => CameraConnectionResult._(false, error);
}

class CameraProvider extends ChangeNotifier {
  final Set<String> _loadingCameras = {};
  final Map<String, String?> _errors = {};
  
  bool isCameraLoading(String cameraId) => _loadingCameras.contains(cameraId);
  String? getCameraError(String cameraId) => _errors[cameraId];
  
  Future<bool> connectCamera(String cameraId) async {
    _loadingCameras.add(cameraId);
    _errors.remove(cameraId);
    notifyListeners();
    
    try {
      // ... lógica de conexão
      final result = await service.connectCamera(camera);
      
      if (result) {
        _cameras[cameraId] = camera.copyWith(isConnected: true);
      } else {
        _errors[cameraId] = 'Falha na conexão';
      }
      
      return result;
    } catch (e) {
      _errors[cameraId] = e.toString();
      return false;
    } finally {
      _loadingCameras.remove(cameraId);
      notifyListeners();
    }
  }
}
 Cleanup de Recursos
class CameraProvider extends ChangeNotifier {
  @override
  void dispose() {
    // Desconectar todos os serviços
    for (final service in _services.values) {
      service.disconnect();
    }
    _services.clear();
    _cameras.clear();
    super.dispose();
  }
  
  void removeCamera(String cameraId) {
    final service = _services[cameraId];
    service?.disconnect();
    
    _cameras.remove(cameraId);
    _services.remove(cameraId);
    _loadingCameras.remove(cameraId);
    _errors.remove(cameraId);
    
    notifyListeners();
  }
}
Estados de Loading e Feedback Visual
class CameraProvider extends ChangeNotifier {
  final Set<String> _loadingCameras = {};
  final Map<String, String?> _errors = {};
  
  bool isCameraLoading(String cameraId) => _loadingCameras.contains(cameraId);
  String? getCameraError(String cameraId) => _errors[cameraId];
  
  Future<bool> connectCamera(String cameraId) async {
    _loadingCameras.add(cameraId);
    _errors.remove(cameraId);
    notifyListeners();
    
    try {
      // ... lógica de conexão
      final result = await service.connectCamera(camera);
      
      if (result) {
        _cameras[cameraId] = camera.copyWith(isConnected: true);
      } else {
        _errors[cameraId] = 'Falha na conexão';
      }
      
      return result;
    } catch (e) {
      _errors[cameraId] = e.toString();
      return false;
    } finally {
      _loadingCameras.remove(cameraId);
      notifyListeners();
    }
  }
}
Método de Inicialização de Serviços
class CameraProvider extends ChangeNotifier {
  CameraService _createCameraService(CameraModel camera) {
    return CameraService(
      onError: (error) => _handleCameraError(camera.id, error),
      onStatusChanged: (status) => _handleStatusChange(camera.id, status),
    );
  }
  
  void addCamera(CameraModel camera) {
    _cameras[camera.id] = camera;
    _services[camera.id] = _createCameraService(camera);
    notifyListeners();
  }
  
  void _handleCameraError(String cameraId, String error) {
    _errors[cameraId] = error;
    final camera = _cameras[cameraId];
    if (camera != null) {
      _cameras[cameraId] = camera.copyWith(
        isConnected: false,
        lastError: error,
      );
    }
    notifyListeners();
  }
}
Batch Operations (Operações em Lote)
O Problema
Para conectar várias câmeras, é necessário chamar connectCamera() uma por uma.

A Solução
class CameraProvider extends ChangeNotifier {
  Future<Map<String, bool>> connectAllCameras() async {
    final results = <String, bool>{};
    
    for (final camera in cameras) {
      if (!camera.isConnected) {
        results[camera.id] = await connectCamera(camera.id);
      }
    }
    
    return results;
  }
  
  Future<void> disconnectAllCameras() async {
    for (final cameraId in _cameras.keys) {
      await _services[cameraId]?.disconnect();
      _cameras[cameraId] = _cameras[cameraId]!.copyWith(isConnected: false);
    }
    notifyListeners();
  }
}
Validação de Parâmetros
Future<bool> executePTZCommand(String cameraId, PTZCommand command) async {
  final camera = _cameras[cameraId];
  if (camera == null || !camera.isConnected) {
    throw CameraException('Câmera não conectada: $cameraId');
  }
  
  if (!camera.capabilities.supportsPTZ) {
    throw CameraException('Câmera não suporta PTZ: $cameraId');
  }
  
  return await _ptzService.executePTZCommand(command);
}
Sugestões Adicionais
Event System
class CameraProvider extends ChangeNotifier {
  final StreamController<CameraEvent> _eventController = StreamController.broadcast();
  
  Stream<CameraEvent> get events => _eventController.stream;
  
  void _emitEvent(CameraEvent event) {
    _eventController.add(event);
  }
}

Retry Logic
Future<bool> connectCameraWithRetry(String cameraId, {int maxRetries = 3}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    final success = await connectCamera(cameraId);
    if (success) return true;
    
    if (attempt < maxRetries) {
      await Future.delayed(Duration(seconds: attempt * 2));
    }
  }
  return false;
}

```

<br />

## 8. Considerações de Implementação

### 8.1 Segurança

* Criptografar credenciais armazenadas

* Implementar timeout para conexões

* Validar todos os inputs do usuário

* Usar HTTPS quando possível

### 8.2 Performance

* Implementar cache para configurações

* Otimizar streams de vídeo

* Usar connection pooling

* Implementar lazy loading

### 8.3 Tratamento de Erros

* Logs detalhados para debugging

* Fallback para diferentes codecs

* Retry automático para conexões

* Notificações de erro para usuário

### 8.4 Testes

* Testes unitários para serviços

* Testes de integração para protocolo

* Testes de UI para widgets

* Testes de performance para streams

## 9. Próximos Passos

1. **Implementar os serviços base** (CameraService, PTZService)
2. **Criar widgets de controle** seguindo o design especificado
3. **Integrar sistema de notificações** com cores por câmera
4. **Implementar correções de codec** com fallback automático
5. **Adicionar menu de opções** no card da câmera
6. **Testar conectividade** com diferentes tipos de câmera
7. **Otimizar performance** do streaming de vídeo
8. **Implementar persistência** de configurações

Este documento fornece uma base sólida para implementar todas as funcionalidades solicitadas de forma modular e escalável.
