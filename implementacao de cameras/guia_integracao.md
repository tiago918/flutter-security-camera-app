# Guia de Integração - Protocolo da Câmera de Segurança

## Visão Geral

Este guia fornece instruções detalhadas para integrar o protocolo da câmera de segurança em seu aplicativo Flutter existente, baseado na análise completa dos dados de interceptação IP.

## 1. Preparação do Ambiente

### 1.1 Dependências
Adicione as seguintes dependências ao seu `pubspec.yaml`:

```yaml
dependencies:
  crypto: ^3.0.3          # Para hash MD5
  convert: ^3.1.1         # Para conversão de dados
  typed_data: ^1.3.2      # Para manipulação binária
  video_player: ^2.7.2    # Para reprodução de vídeo
  provider: ^6.0.5        # Para gerenciamento de estado
  logger: ^2.0.2+1        # Para logs
```

### 1.2 Permissões

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Este app precisa acessar a rede local para conectar às câmeras</string>
```

## 2. Estrutura de Arquivos

Crie a seguinte estrutura no seu projeto:

```
lib/
├── services/
│   ├── camera_protocol.dart
│   ├── camera_manager.dart
│   └── network_service.dart
├── models/
│   ├── camera_model.dart
│   ├── recording_model.dart
│   └── ptz_command.dart
├── providers/
│   └── camera_provider.dart
├── widgets/
│   ├── camera_viewer.dart
│   ├── ptz_controls.dart
│   └── recording_list.dart
└── screens/
    ├── camera_screen.dart
    └── settings_screen.dart
```

## 3. Implementação Passo a Passo

### 3.1 Modelo de Dados da Câmera

Crie `lib/models/camera_model.dart`:

```dart
class CameraModel {
  final String id;
  final String name;
  final String ip;
  final String username;
  final String password;
  final bool isConnected;
  final bool isAuthenticated;
  
  CameraModel({
    required this.id,
    required this.name,
    required this.ip,
    required this.username,
    required this.password,
    this.isConnected = false,
    this.isAuthenticated = false,
  });
  
  CameraModel copyWith({
    String? id,
    String? name,
    String? ip,
    String? username,
    String? password,
    bool? isConnected,
    bool? isAuthenticated,
  }) {
    return CameraModel(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      username: username ?? this.username,
      password: password ?? this.password,
      isConnected: isConnected ?? this.isConnected,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}
```

### 3.2 Provider para Gerenciamento de Estado

Crie `lib/providers/camera_provider.dart`:

```dart
import 'package:flutter/foundation.dart';
import '../models/camera_model.dart';
import '../services/camera_protocol.dart';

class CameraProvider extends ChangeNotifier {
  final Map<String, CameraModel> _cameras = {};
  final Map<String, CameraProtocol> _protocols = {};
  
  List<CameraModel> get cameras => _cameras.values.toList();
  
  void addCamera(CameraModel camera) {
    _cameras[camera.id] = camera;
    _protocols[camera.id] = CameraProtocol(camera.ip);
    notifyListeners();
  }
  
  Future<bool> connectCamera(String cameraId) async {
    final protocol = _protocols[cameraId];
    final camera = _cameras[cameraId];
    
    if (protocol == null || camera == null) return false;
    
    try {
      bool connected = await protocol.connect();
      if (connected) {
        bool authenticated = await protocol.authenticate(
          camera.username, 
          camera.password
        );
        
        _cameras[cameraId] = camera.copyWith(
          isConnected: connected,
          isAuthenticated: authenticated,
        );
        
        notifyListeners();
        return authenticated;
      }
    } catch (e) {
      debugPrint('Erro ao conectar câmera $cameraId: $e');
    }
    
    return false;
  }
  
  Future<void> disconnectCamera(String cameraId) async {
    final protocol = _protocols[cameraId];
    final camera = _cameras[cameraId];
    
    if (protocol != null && camera != null) {
      await protocol.disconnect();
      _cameras[cameraId] = camera.copyWith(
        isConnected: false,
        isAuthenticated: false,
      );
      notifyListeners();
    }
  }
  
  CameraProtocol? getProtocol(String cameraId) {
    return _protocols[cameraId];
  }
}
```

### 3.3 Widget de Visualização da Câmera

Crie `lib/widgets/camera_viewer.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/camera_provider.dart';
import '../models/camera_model.dart';
import 'ptz_controls.dart';

class CameraViewer extends StatefulWidget {
  final String cameraId;
  
  const CameraViewer({Key? key, required this.cameraId}) : super(key: key);
  
  @override
  _CameraViewerState createState() => _CameraViewerState();
}

class _CameraViewerState extends State<CameraViewer> {
  @override
  Widget build(BuildContext context) {
    return Consumer<CameraProvider>(builder: (context, provider, child) {
      final cameras = provider.cameras;
      final camera = cameras.firstWhere(
        (c) => c.id == widget.cameraId,
        orElse: () => throw Exception('Câmera não encontrada'),
      );
      
      return Column(
        children: [
          // Área de vídeo
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.grey),
              ),
              child: camera.isAuthenticated
                  ? _buildVideoPlayer(camera)
                  : _buildConnectionStatus(camera),
            ),
          ),
          
          // Controles PTZ
          if (camera.isAuthenticated)
            Expanded(
              flex: 1,
              child: PTZControls(cameraId: widget.cameraId),
            ),
          
          // Status e controles de conexão
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatusChip('Conectado', camera.isConnected),
                _buildStatusChip('Autenticado', camera.isAuthenticated),
                ElevatedButton(
                  onPressed: camera.isConnected
                      ? () => provider.disconnectCamera(camera.id)
                      : () => provider.connectCamera(camera.id),
                  child: Text(camera.isConnected ? 'Desconectar' : 'Conectar'),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
  
  Widget _buildVideoPlayer(CameraModel camera) {
    // Implementar player de vídeo RTSP/stream
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam, size: 64, color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Stream de ${camera.name}',
            style: TextStyle(color: Colors.white),
          ),
          Text(
            '${camera.ip}:2223',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
  
  Widget _buildConnectionStatus(CameraModel camera) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            camera.isConnected ? Icons.wifi : Icons.wifi_off,
            size: 64,
            color: camera.isConnected ? Colors.green : Colors.red,
          ),
          SizedBox(height: 16),
          Text(
            camera.isConnected ? 'Conectado' : 'Desconectado',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          Text(
            camera.ip,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusChip(String label, bool status) {
    return Chip(
      label: Text(label),
      backgroundColor: status ? Colors.green : Colors.red,
      labelStyle: TextStyle(color: Colors.white),
    );
  }
}
```

### 3.4 Controles PTZ

Crie `lib/widgets/ptz_controls.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/camera_provider.dart';

class PTZControls extends StatefulWidget {
  final String cameraId;
  
  const PTZControls({Key? key, required this.cameraId}) : super(key: key);
  
  @override
  _PTZControlsState createState() => _PTZControlsState();
}

class _PTZControlsState extends State<PTZControls> {
  double _speed = 5.0;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Controles PTZ', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 16),
          
          // Controles direcionais
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  _buildPTZButton(Icons.keyboard_arrow_up, 'Up'),
                  Row(
                    children: [
                      _buildPTZButton(Icons.keyboard_arrow_left, 'Left'),
                      SizedBox(width: 20),
                      _buildPTZButton(Icons.keyboard_arrow_right, 'Right'),
                    ],
                  ),
                  _buildPTZButton(Icons.keyboard_arrow_down, 'Down'),
                ],
              ),
              
              // Controles de zoom
              Column(
                children: [
                  _buildPTZButton(Icons.zoom_in, 'ZoomIn'),
                  SizedBox(height: 20),
                  _buildPTZButton(Icons.zoom_out, 'ZoomOut'),
                ],
              ),
            ],
          ),
          
          SizedBox(height: 16),
          
          // Controle de velocidade
          Row(
            children: [
              Text('Velocidade: '),
              Expanded(
                child: Slider(
                  value: _speed,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _speed.round().toString(),
                  onChanged: (value) {
                    setState(() {
                      _speed = value;
                    });
                  },
                ),
              ),
              Text(_speed.round().toString()),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildPTZButton(IconData icon, String direction) {
    return Consumer<CameraProvider>(builder: (context, provider, child) {
      return GestureDetector(
        onTapDown: (_) => _sendPTZCommand(provider, direction),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      );
    });
  }
  
  void _sendPTZCommand(CameraProvider provider, String direction) async {
    final protocol = provider.getProtocol(widget.cameraId);
    if (protocol != null) {
      await protocol.controlPTZ(
        direction: direction,
        speed: _speed.round(),
      );
    }
  }
}
```

## 4. Integração no App Principal

### 4.1 Configuração do Provider

No seu `main.dart`, adicione o provider:

```dart
import 'package:provider/provider.dart';
import 'providers/camera_provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CameraProvider()),
        // Seus outros providers existentes
      ],
      child: MyApp(),
    ),
  );
}
```

### 4.2 Tela de Câmera

Crie `lib/screens/camera_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/camera_provider.dart';
import '../models/camera_model.dart';
import '../widgets/camera_viewer.dart';

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  @override
  void initState() {
    super.initState();
    _initializeCameras();
  }
  
  void _initializeCameras() {
    final provider = Provider.of<CameraProvider>(context, listen: false);
    
    // Adicione suas câmeras aqui
    provider.addCamera(CameraModel(
      id: 'camera1',
      name: 'Câmera Principal',
      ip: '82.115.15.137', // IP da sua câmera
      username: 'admin',
      password: 'sua_senha',
    ));
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Câmeras de Segurança'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              // Navegar para tela de configurações
            },
          ),
        ],
      ),
      body: Consumer<CameraProvider>(builder: (context, provider, child) {
        if (provider.cameras.isEmpty) {
          return Center(
            child: Text('Nenhuma câmera configurada'),
          );
        }
        
        return PageView.builder(
          itemCount: provider.cameras.length,
          itemBuilder: (context, index) {
            final camera = provider.cameras[index];
            return CameraViewer(cameraId: camera.id);
          },
        );
      }),
    );
  }
}
```

## 5. Configurações Avançadas

### 5.1 Tratamento de Erros

Implemente tratamento robusto de erros:

```dart
try {
  bool success = await cameraProtocol.authenticate(username, password);
  if (!success) {
    // Mostrar erro de autenticação
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Falha na autenticação')),
    );
  }
} on SocketException catch (e) {
  // Erro de rede
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Erro de conexão: ${e.message}')),
  );
} catch (e) {
  // Outros erros
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Erro inesperado: $e')),
  );
}
```

### 5.2 Persistência de Configurações

Use `shared_preferences` para salvar configurações:

```dart
import 'package:shared_preferences/shared_preferences.dart';

class CameraSettings {
  static const String _camerasKey = 'cameras';
  
  static Future<void> saveCameras(List<CameraModel> cameras) async {
    final prefs = await SharedPreferences.getInstance();
    final camerasJson = cameras.map((c) => {
      'id': c.id,
      'name': c.name,
      'ip': c.ip,
      'username': c.username,
      'password': c.password, // Considere criptografar
    }).toList();
    
    await prefs.setString(_camerasKey, jsonEncode(camerasJson));
  }
  
  static Future<List<CameraModel>> loadCameras() async {
    final prefs = await SharedPreferences.getInstance();
    final camerasString = prefs.getString(_camerasKey);
    
    if (camerasString == null) return [];
    
    final camerasJson = jsonDecode(camerasString) as List;
    return camerasJson.map((json) => CameraModel(
      id: json['id'],
      name: json['name'],
      ip: json['ip'],
      username: json['username'],
      password: json['password'],
    )).toList();
  }
}
```

## 6. Testes

### 6.1 Teste de Conectividade

```dart
void testCameraConnection() async {
  final camera = CameraProtocol('82.115.15.137');
  
  try {
    bool connected = await camera.connect();
    print('Conexão: $connected');
    
    if (connected) {
      bool authenticated = await camera.authenticate('admin', 'password');
      print('Autenticação: $authenticated');
    }
  } finally {
    await camera.disconnect();
  }
}
```

## 7. Próximos Passos

1. **Implementar reprodução de vídeo RTSP**
2. **Adicionar suporte para múltiplas câmeras**
3. **Implementar gravação local**
4. **Adicionar notificações push**
5. **Otimizar performance de rede**
6. **Implementar cache de configurações**
7. **Adicionar testes unitários**

## 8. Considerações de Segurança

- **Nunca armazene senhas em texto plano**
- **Use HTTPS quando possível**
- **Implemente timeout para conexões**
- **Valide todos os inputs do usuário**
- **Considere usar certificados SSL/TLS**

## 9. Troubleshooting

### Problemas Comuns:

1. **Erro de conexão**: Verifique IP e porta
2. **Falha na autenticação**: Confirme usuário/senha
3. **Stream não funciona**: Verifique porta 2223
4. **PTZ não responde**: Verifique se câmera suporta PTZ

### Logs Úteis:

```dart
import 'package:logger/logger.dart';

final logger = Logger();

// Use em pontos críticos
logger.d('Conectando à câmera ${camera.ip}');
logger.e('Erro na autenticação: $error');
logger.i('PTZ comando enviado: $direction');
```

Este guia fornece uma base sólida para integrar o protocolo da câmera em seu aplicativo Flutter existente. Adapte conforme necessário para suas necessidades específicas.