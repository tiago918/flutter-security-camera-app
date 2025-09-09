# Suporte a Câmeras com Múltiplas Portas de Comunicação

## 1. Visão Geral do Problema

Atualmente, o sistema assume que toda comunicação ONVIF ocorre através de uma única porta (geralmente 80, 8080, 8000 ou 8899). Porém, algumas câmeras IP utilizam arquiteturas de comunicação mais complexas:

- **HTTP/Web Interface**: Porta 80 ou 8080
- **ONVIF Services**: Porta 8899 ou 2020
- **Media Streaming**: Porta 34567 ou 554
- **Event Notifications**: Porta diferente
- **Protocolo Proprietário**: Porta 34567 (câmeras chinesas)

Este documento detalha como implementar suporte a essas câmeras mantendo compatibilidade total com câmeras de porta única, incluindo suporte ao protocolo binário proprietário usado por muitas câmeras chinesas.

## 2. Análise do Sistema Atual

### 2.1 Estrutura Atual
O sistema atual usa:
- `CameraData.port`: Porta única opcional
- Tentativa sequencial de portas padrão: `[80, 8080, 8000, 8899]`
- Cache de conexões ONVIF por host+usuário

### 2.2 Limitações Identificadas
- Não suporta portas específicas por serviço
- Detecção automática limitada a portas ONVIF
- Interface não permite configuração granular

## 3. Modelo de Dados Estendido

### 3.1 Nova Classe: CameraPortConfiguration

```dart
class CameraPortConfiguration {
  final int? httpPort;        // Porta para interface web (80, 8080)
  final int? onvifPort;       // Porta para serviços ONVIF (8899, 2020)
  final int? mediaPort;       // Porta para streaming (554, 34567)
  final int? eventPort;       // Porta para eventos/notificações
  final int? proprietaryPort; // Porta para protocolo proprietário (34567)
  final String protocolType;  // Tipo: 'onvif', 'proprietary', 'hybrid'
  final bool autoDetect;      // Se deve tentar detecção automática
  final List<int> fallbackPorts; // Portas para tentar se específicas falharem

  const CameraPortConfiguration({
    this.httpPort,
    this.onvifPort,
    this.mediaPort,
    this.eventPort,
    this.proprietaryPort,
    this.protocolType = 'onvif',
    this.autoDetect = true,
    this.fallbackPorts = const [80, 8080, 8000, 8899, 2020, 554, 34567],
  });

  // Retorna a porta ONVIF preferida ou null para auto-detecção
  int? get preferredOnvifPort => onvifPort;
  
  // Retorna todas as portas para tentar ONVIF
  List<int> get onvifPortsToTry {
    final ports = <int>[];
    if (onvifPort != null) ports.add(onvifPort!);
    if (autoDetect) {
      ports.addAll(fallbackPorts.where((p) => p != onvifPort));
    }
    return ports;
  }

  Map<String, dynamic> toJson() => {
    'httpPort': httpPort,
    'onvifPort': onvifPort,
    'mediaPort': mediaPort,
    'eventPort': eventPort,
    'proprietaryPort': proprietaryPort,
    'protocolType': protocolType,
    'autoDetect': autoDetect,
    'fallbackPorts': fallbackPorts,
  };

  factory CameraPortConfiguration.fromJson(Map<String, dynamic> json) => 
    CameraPortConfiguration(
      httpPort: json['httpPort'] as int?,
      onvifPort: json['onvifPort'] as int?,
      mediaPort: json['mediaPort'] as int?,
      eventPort: json['eventPort'] as int?,
      proprietaryPort: json['proprietaryPort'] as int?,
      protocolType: json['protocolType'] as String? ?? 'onvif',
      autoDetect: json['autoDetect'] as bool? ?? true,
      fallbackPorts: List<int>.from(json['fallbackPorts'] as List? ?? 
        [80, 8080, 8000, 8899, 2020, 554, 34567]),
    );
}
```

### 3.2 Modificação em CameraData

```dart
class CameraData {
  // ... campos existentes ...
  final CameraPortConfiguration? portConfig; // Nova configuração de portas
  
  // Método de compatibilidade - retorna porta única se configurada
  int? get legacyPort => portConfig?.onvifPort ?? port;
  
  // Retorna portas ONVIF para tentar
  List<int> get onvifPortsToTry {
    if (portConfig != null) {
      return portConfig!.onvifPortsToTry;
    }
    // Fallback para comportamento atual
    if (port != null) return [port!];
    return [80, 8080, 8000, 8899];
  }
}
```

## 4. Estratégia de Detecção Automática

### 4.1 Novo Serviço: CameraPortDetectionService

```dart
class CameraPortDetectionService {
  static const Duration _portTimeout = Duration(seconds: 3);
  
  /// Detecta configuração de portas para uma câmera
  Future<CameraPortConfiguration?> detectPortConfiguration(
    String host, 
    String username, 
    String password
  ) async {
    final results = await Future.wait([
      _detectHttpPort(host),
      _detectOnvifPort(host, username, password),
      _detectMediaPort(host),
    ]);
    
    final httpPort = results[0] as int?;
    final onvifPort = results[1] as int?;
    final mediaPort = results[2] as int?;
    
    // Se encontrou portas específicas, cria configuração
    if (httpPort != null || onvifPort != null || mediaPort != null) {
      return CameraPortConfiguration(
        httpPort: httpPort,
        onvifPort: onvifPort,
        mediaPort: mediaPort,
        autoDetect: false, // Desabilita auto-detecção se encontrou específicas
      );
    }
    
    return null; // Usa detecção padrão
  }
  
  Future<int?> _detectHttpPort(String host) async {
    final commonHttpPorts = [80, 8080, 8000, 8888];
    
    for (final port in commonHttpPorts) {
      try {
        final socket = await Socket.connect(host, port, timeout: _portTimeout);
        await socket.close();
        
        // Verifica se responde HTTP
        final response = await http.get(
          Uri.parse('http://$host:$port'),
          headers: {'User-Agent': 'CameraApp/1.0'},
        ).timeout(_portTimeout);
        
        if (response.statusCode < 500) {
          return port;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
  
  Future<int?> _detectOnvifPort(String host, String user, String pass) async {
    final commonOnvifPorts = [8899, 2020, 80, 8080];
    
    for (final port in commonOnvifPorts) {
      try {
        final onvif = await Onvif.connect(
          host: '$host:$port',
          username: user,
          password: pass,
        ).timeout(_portTimeout);
        
        // Testa se realmente é ONVIF
        await onvif.deviceManagement.getCapabilities().timeout(_portTimeout);
        return port;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
  
  Future<int?> _detectMediaPort(String host) async {
    final commonMediaPorts = [554, 34567, 8554, 1935];
    
    for (final port in commonMediaPorts) {
      try {
        final socket = await Socket.connect(host, port, timeout: _portTimeout);
        await socket.close();
        return port;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
```

## 5. Protocolo Binário Proprietário (Câmeras Chinesas)

### 5.1 Visão Geral do Protocolo

Muitas câmeras IP chinesas utilizam um protocolo binário proprietário na porta 34567 para funcionalidades avançadas como:
- Listagem de vídeos gravados
- Reprodução de vídeo
- Controle PTZ avançado
- Configurações específicas do fabricante

### 5.2 Protocolo DVRIP-Web

O protocolo DVRIP-Web é amplamente utilizado por câmeras IP chinesas e segue um padrão específico de autenticação e comunicação:

#### Características do Protocolo:
- **Porta**: 34567 (TCP)
- **Autenticação**: Hash MD5 da senha
- **Formato**: Binário com payload JSON
- **Tipo de Login**: "DVRIP-Web"
- **Criptografia**: "MD5"

#### Exemplo de Implementação Completa:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class DVRIPCameraService {
  Future<bool> loginDVRIP(String host, String username, String password) async {
    try {
      final socket = await Socket.connect(host, 34567, timeout: Duration(seconds: 10));
      
      // Hash MD5 da senha
      final passwordHash = md5.convert(utf8.encode(password)).toString();
      
      // Payload JSON do protocolo DVRIP-Web
      final loginPayload = {
        "EncryptType": "MD5",
        "LoginType": "DVRIP-Web",
        "PassWord": passwordHash,
        "UserName": username,
      };
      
      // Construção do pacote binário
      final jsonString = json.encode(loginPayload);
      final jsonBytes = utf8.encode(jsonString);
      
      final header = Uint8List.fromList([0xff, 0x00, 0x00, 0x00]);
      final commandId = Uint8List.fromList([0x00, 0x01, 0x00, 0x00]);
      final payloadLength = ByteData(4)..setUint32(0, jsonBytes.length, Endian.little);
      
      final loginCommand = BytesBuilder()
        ..add(header)
        ..add(commandId)
        ..add(payloadLength.buffer.asUint8List())
        ..add(jsonBytes);
      
      // Envio do comando
      socket.add(loginCommand.toBytes());
      await socket.flush();
      
      // Aguarda resposta
      await for (var data in socket) {
        final response = utf8.decode(data);
        print('Resposta da câmera: $response');
        
        // Verifica se login foi bem-sucedido
        if (response.contains('"Ret":100')) {
          print('Login DVRIP-Web bem-sucedido!');
          socket.destroy();
          return true;
        }
      }
      
      socket.destroy();
      return false;
    } catch (e) {
      print('Erro no login DVRIP-Web: $e');
      return false;
    }
  }
}
```

### 5.3 Estrutura de Comandos

Todos os comandos seguem a estrutura binária:

```
[Header: 4 bytes] [Command ID: 4 bytes] [Payload Length: 4 bytes] [Reserved: 4 bytes] [JSON Payload: N bytes]
```

- **Header**: Sempre `0xFF000000` (4 bytes, big-endian)
- **Command ID**: Identificador do comando (4 bytes, little-endian)
- **Payload Length**: Tamanho do payload JSON (4 bytes, little-endian)
- **Reserved**: Campo reservado, sempre 0 (4 bytes)
- **JSON Payload**: Dados do comando em formato JSON UTF-8

### 5.4 Comandos Principais

#### Login (0x00010000) - Protocolo DVRIP-Web

O protocolo de login utiliza o padrão DVRIP-Web com hash MD5 da senha:

```json
{
  "EncryptType": "MD5",
  "LoginType": "DVRIP-Web",
  "PassWord": "<md5-hash-of-password>",
  "UserName": "<username>"
}
```

**Importante**: A senha deve ser convertida para hash MD5 antes do envio. Por exemplo:
- Senha original: `123456`
- Hash MD5: `e10adc3949ba59abbe56e057f20f883e`

**Resposta de Sucesso**: O login é bem-sucedido quando a resposta contém `"Ret":100`.

#### GetRecordList (0x00020000)
```json
{
  "channel": 0,
  "startTime": "2024-01-01 00:00:00",
  "endTime": "2024-01-01 23:59:59",
  "recordType": "all"
}
```

#### StartPlayback (0x00030000)
```json
{
  "channel": 0,
  "fileName": "record_20240101_120000.mp4",
  "startTime": "2024-01-01 12:00:00",
  "streamType": "main"
}
```

#### PTZControl (0x00040000)
```json
{
  "channel": 0,
  "command": "up",
  "speed": 5,
  "duration": 1000
}
```

### 5.5 Novo Serviço: ProprietaryProtocolService

```dart
class ProprietaryProtocolService {
  static const int _headerValue = 0xFF000000;
  static const Duration _commandTimeout = Duration(seconds: 10);
  
  Socket? _socket;
  String? _sessionId;
  
  // Importações necessárias para MD5
  // import 'dart:convert';
  // import 'dart:io';
  // import 'dart:typed_data';
  // import 'package:crypto/crypto.dart';
  
  /// Conecta ao protocolo proprietário
  Future<bool> connect(String host, int port, String username, String password) async {
    try {
      _socket = await Socket.connect(host, port, timeout: _commandTimeout);
      return await _login(username, password);
    } catch (e) {
      print('Erro ao conectar protocolo proprietário: $e');
      return false;
    }
  }
  
  /// Realiza login no sistema usando protocolo DVRIP-Web
  Future<bool> _login(String username, String password) async {
    // Converte senha para hash MD5 (protocolo DVRIP-Web)
    final passwordHash = md5.convert(utf8.encode(password)).toString();
    
    final loginData = {
      'EncryptType': 'MD5',
      'LoginType': 'DVRIP-Web',
      'PassWord': passwordHash,
      'UserName': username,
    };
    
    final response = await _sendCommand(0x00010000, loginData);
    if (response != null && response['Ret'] == 100) {
      _sessionId = response['SessionID'];
      return true;
    }
    return false;
  }
  
  /// Lista gravações disponíveis
  Future<List<RecordingInfo>?> getRecordList({
    int channel = 0,
    required DateTime startTime,
    required DateTime endTime,
    String recordType = 'all',
  }) async {
    final requestData = {
      'channel': channel,
      'startTime': _formatDateTime(startTime),
      'endTime': _formatDateTime(endTime),
      'recordType': recordType,
      'sessionId': _sessionId,
    };
    
    final response = await _sendCommand(0x00020000, requestData);
    if (response != null && response['recordings'] != null) {
      return (response['recordings'] as List)
          .map((r) => RecordingInfo.fromProprietaryJson(r))
          .toList();
    }
    return null;
  }
  
  /// Inicia reprodução de gravação
  Future<String?> startPlayback({
    int channel = 0,
    required String fileName,
    required DateTime startTime,
    String streamType = 'main',
  }) async {
    final requestData = {
      'channel': channel,
      'fileName': fileName,
      'startTime': _formatDateTime(startTime),
      'streamType': streamType,
      'sessionId': _sessionId,
    };
    
    final response = await _sendCommand(0x00030000, requestData);
    return response?['playbackUrl'];
  }
  
  /// Controle PTZ avançado
  Future<bool> ptzControl({
    int channel = 0,
    required String command,
    int speed = 5,
    int duration = 1000,
  }) async {
    final requestData = {
      'channel': channel,
      'command': command,
      'speed': speed,
      'duration': duration,
      'sessionId': _sessionId,
    };
    
    final response = await _sendCommand(0x00040000, requestData);
    return response?['result'] == 'success';
  }
  
  /// Envia comando binário
  Future<Map<String, dynamic>?> _sendCommand(int commandId, Map<String, dynamic> data) async {
    if (_socket == null) return null;
    
    try {
      // Serializa JSON
      final jsonPayload = utf8.encode(json.encode(data));
      final payloadLength = jsonPayload.length;
      
      // Constrói pacote binário
      final packet = ByteData(16 + payloadLength);
      packet.setUint32(0, _headerValue, Endian.big);           // Header
      packet.setUint32(4, commandId, Endian.little);           // Command ID
      packet.setUint32(8, payloadLength, Endian.little);       // Payload Length
      packet.setUint32(12, 0, Endian.little);                 // Reserved
      
      // Adiciona payload JSON
      final buffer = packet.buffer.asUint8List();
      buffer.setRange(16, 16 + payloadLength, jsonPayload);
      
      // Envia comando
      _socket!.add(buffer);
      
      // Aguarda resposta
      final responseData = await _socket!.first.timeout(_commandTimeout);
      return _parseResponse(responseData);
    } catch (e) {
      print('Erro ao enviar comando $commandId: $e');
      return null;
    }
  }
  
  /// Analisa resposta binária
  Map<String, dynamic>? _parseResponse(Uint8List data) {
    if (data.length < 16) return null;
    
    final packet = ByteData.sublistView(data);
    final header = packet.getUint32(0, Endian.big);
    
    if (header != _headerValue) return null;
    
    final payloadLength = packet.getUint32(8, Endian.little);
    if (data.length < 16 + payloadLength) return null;
    
    final jsonBytes = data.sublist(16, 16 + payloadLength);
    final jsonString = utf8.decode(jsonBytes);
    
    try {
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      print('Erro ao decodificar resposta JSON: $e');
      return null;
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
  
  /// Desconecta do serviço
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
    _sessionId = null;
  }
}
```

### 5.5 Extensão do RecordingInfo

```dart
extension RecordingInfoProprietary on RecordingInfo {
  factory RecordingInfo.fromProprietaryJson(Map<String, dynamic> json) {
    return RecordingInfo(
      fileName: json['fileName'] ?? '',
      startTime: DateTime.tryParse(json['startTime'] ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(json['endTime'] ?? '') ?? DateTime.now(),
      fileSize: json['fileSize'] ?? 0,
      channel: json['channel'] ?? 0,
      recordType: json['recordType'] ?? 'unknown',
    );
  }
}
```

## 6. Estratégia Híbrida ONVIF + Protocolo Proprietário

### 6.1 Detecção Automática Inteligente

```dart
class HybridCameraDetectionService {
  static const Duration _detectionTimeout = Duration(seconds: 5);
  
  /// Detecta o melhor protocolo para a câmera
  Future<CameraPortConfiguration?> detectOptimalProtocol(
    String host, 
    String username, 
    String password
  ) async {
    // Tenta ONVIF primeiro (mais padronizado)
    final onvifResult = await _detectOnvifCapabilities(host, username, password);
    
    // Tenta protocolo proprietário em paralelo
    final proprietaryResult = await _detectProprietaryProtocol(host, username, password);
    
    // Determina a melhor estratégia
    return _selectOptimalConfiguration(onvifResult, proprietaryResult);
  }
  
  Future<OnvifDetectionResult?> _detectOnvifCapabilities(
    String host, String username, String password
  ) async {
    final commonOnvifPorts = [8899, 2020, 80, 8080];
    
    for (final port in commonOnvifPorts) {
      try {
        final onvif = await Onvif.connect(
          host: '$host:$port',
          username: username,
          password: password,
        ).timeout(_detectionTimeout);
        
        // Testa capacidades ONVIF
        final capabilities = await onvif.deviceManagement.getCapabilities()
            .timeout(_detectionTimeout);
        
        return OnvifDetectionResult(
          port: port,
          hasMedia: capabilities.media != null,
          hasPTZ: capabilities.ptz != null,
          hasEvents: capabilities.events != null,
          hasRecording: capabilities.recording != null,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }
  
  Future<ProprietaryDetectionResult?> _detectProprietaryProtocol(
    String host, String username, String password
  ) async {
    final proprietaryService = ProprietaryProtocolService();
    
    try {
      // Tenta conectar na porta padrão do protocolo proprietário
      final connected = await proprietaryService.connect(host, 34567, username, password);
      
      if (connected) {
        // Testa funcionalidades disponíveis
        final hasRecordings = await _testRecordingCapability(proprietaryService);
        final hasPTZ = await _testPTZCapability(proprietaryService);
        
        return ProprietaryDetectionResult(
          port: 34567,
          hasRecordings: hasRecordings,
          hasPTZ: hasPTZ,
          hasAdvancedFeatures: true,
        );
      }
    } catch (e) {
      print('Protocolo proprietário não detectado: $e');
    } finally {
      await proprietaryService.disconnect();
    }
    
    return null;
  }
  
  Future<bool> _testRecordingCapability(ProprietaryProtocolService service) async {
    try {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final recordings = await service.getRecordList(
        startTime: yesterday,
        endTime: DateTime.now(),
      );
      return recordings != null;
    } catch (_) {
      return false;
    }
  }
  
  Future<bool> _testPTZCapability(ProprietaryProtocolService service) async {
    try {
      // Testa comando PTZ simples (sem movimento real)
      return await service.ptzControl(
        command: 'stop',
        speed: 0,
        duration: 0,
      );
    } catch (_) {
      return false;
    }
  }
  
  CameraPortConfiguration _selectOptimalConfiguration(
    OnvifDetectionResult? onvif,
    ProprietaryDetectionResult? proprietary,
  ) {
    // Se ambos estão disponíveis, usa estratégia híbrida
    if (onvif != null && proprietary != null) {
      return CameraPortConfiguration(
        onvifPort: onvif.port,
        proprietaryPort: proprietary.port,
        protocolType: 'hybrid',
        autoDetect: false,
      );
    }
    
    // Se apenas ONVIF está disponível
    if (onvif != null) {
      return CameraPortConfiguration(
        onvifPort: onvif.port,
        protocolType: 'onvif',
        autoDetect: false,
      );
    }
    
    // Se apenas protocolo proprietário está disponível
    if (proprietary != null) {
      return CameraPortConfiguration(
        proprietaryPort: proprietary.port,
        protocolType: 'proprietary',
        autoDetect: false,
      );
    }
    
    // Fallback para detecção automática padrão
    return CameraPortConfiguration(
      protocolType: 'onvif',
      autoDetect: true,
    );
  }
}

class OnvifDetectionResult {
  final int port;
  final bool hasMedia;
  final bool hasPTZ;
  final bool hasEvents;
  final bool hasRecording;
  
  const OnvifDetectionResult({
    required this.port,
    required this.hasMedia,
    required this.hasPTZ,
    required this.hasEvents,
    required this.hasRecording,
  });
}

class ProprietaryDetectionResult {
  final int port;
  final bool hasRecordings;
  final bool hasPTZ;
  final bool hasAdvancedFeatures;
  
  const ProprietaryDetectionResult({
    required this.port,
    required this.hasRecordings,
    required this.hasPTZ,
    required this.hasAdvancedFeatures,
  });
}
```

### 6.2 Gerenciador de Conexão Híbrida

```dart
class HybridCameraConnectionManager {
  static final Map<String, ProprietaryProtocolService> _proprietaryConnections = {};
  static final Map<String, Onvif> _onvifConnections = {};
  
  /// Conecta usando a estratégia apropriada
  static Future<CameraConnection?> connectToCamera(CameraData camera) async {
    final config = camera.portConfig;
    if (config == null) {
      // Fallback para conexão ONVIF tradicional
      final onvif = await _connectOnvifLegacy(camera);
      return onvif != null ? CameraConnection.onvifOnly(onvif) : null;
    }
    
    switch (config.protocolType) {
      case 'hybrid':
        return await _connectHybrid(camera, config);
      case 'proprietary':
        return await _connectProprietary(camera, config);
      case 'onvif':
      default:
        return await _connectOnvif(camera, config);
    }
  }
  
  static Future<CameraConnection?> _connectHybrid(
    CameraData camera, 
    CameraPortConfiguration config
  ) async {
    final host = _extractHost(camera.streamUrl);
    if (host == null) return null;
    
    // Conecta ambos os protocolos
    final onvifFuture = _connectOnvifWithConfig(camera, config);
    final proprietaryFuture = _connectProprietaryWithConfig(camera, config);
    
    final results = await Future.wait([onvifFuture, proprietaryFuture]);
    final onvif = results[0] as Onvif?;
    final proprietary = results[1] as ProprietaryProtocolService?;
    
    if (onvif != null || proprietary != null) {
      return CameraConnection.hybrid(onvif, proprietary);
    }
    
    return null;
  }
  
  static Future<Onvif?> _connectOnvifWithConfig(
    CameraData camera, 
    CameraPortConfiguration config
  ) async {
    final host = _extractHost(camera.streamUrl);
    if (host == null || config.onvifPort == null) return null;
    
    final key = '${host}:${config.onvifPort}|${camera.username}';
    if (_onvifConnections.containsKey(key)) {
      return _onvifConnections[key];
    }
    
    try {
      final onvif = await Onvif.connect(
        host: '$host:${config.onvifPort}',
        username: camera.username ?? '',
        password: camera.password ?? '',
      ).timeout(const Duration(seconds: 5));
      
      _onvifConnections[key] = onvif;
      return onvif;
    } catch (e) {
      print('Erro ao conectar ONVIF: $e');
      return null;
    }
  }
  
  static Future<ProprietaryProtocolService?> _connectProprietaryWithConfig(
    CameraData camera, 
    CameraPortConfiguration config
  ) async {
    final host = _extractHost(camera.streamUrl);
    if (host == null || config.proprietaryPort == null) return null;
    
    final key = '$host:${config.proprietaryPort}';
    if (_proprietaryConnections.containsKey(key)) {
      return _proprietaryConnections[key];
    }
    
    final service = ProprietaryProtocolService();
    final connected = await service.connect(
      host, 
      config.proprietaryPort!, 
      camera.username ?? '', 
      camera.password ?? ''
    );
    
    if (connected) {
      _proprietaryConnections[key] = service;
      return service;
    }
    
    return null;
  }
  
  static String? _extractHost(String streamUrl) {
    final uri = Uri.tryParse(streamUrl);
    return uri?.host;
  }
}

/// Representa uma conexão de câmera que pode usar múltiplos protocolos
class CameraConnection {
  final Onvif? onvif;
  final ProprietaryProtocolService? proprietary;
  final String type;
  
  const CameraConnection._(
    this.onvif, 
    this.proprietary, 
    this.type
  );
  
  factory CameraConnection.onvifOnly(Onvif onvif) => 
    CameraConnection._(onvif, null, 'onvif');
  
  factory CameraConnection.proprietaryOnly(ProprietaryProtocolService proprietary) => 
    CameraConnection._(null, proprietary, 'proprietary');
  
  factory CameraConnection.hybrid(Onvif? onvif, ProprietaryProtocolService? proprietary) => 
    CameraConnection._(onvif, proprietary, 'hybrid');
  
  bool get hasOnvif => onvif != null;
  bool get hasProprietary => proprietary != null;
  bool get isHybrid => hasOnvif && hasProprietary;
}
```

## 7. Interface de Configuração Manual

### 7.1 Widget: AdvancedPortConfigurationDialog

```dart
class AdvancedPortConfigurationDialog extends StatefulWidget {
  final CameraPortConfiguration? initialConfig;
  final Function(CameraPortConfiguration?) onConfigChanged;
  
  const AdvancedPortConfigurationDialog({
    Key? key,
    this.initialConfig,
    required this.onConfigChanged,
  }) : super(key: key);
}

class _AdvancedPortConfigurationDialogState extends State<AdvancedPortConfigurationDialog> {
  late TextEditingController _httpPortController;
  late TextEditingController _onvifPortController;
  late TextEditingController _mediaPortController;
  late TextEditingController _eventPortController;
  bool _autoDetect = true;
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configuração Avançada de Portas'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Detecção Automática'),
              subtitle: const Text('Tentar detectar portas automaticamente'),
              value: _autoDetect,
              onChanged: (value) => setState(() => _autoDetect = value),
            ),
            const Divider(),
            _buildPortField('HTTP/Web', _httpPortController, '80, 8080'),
            _buildPortField('ONVIF', _onvifPortController, '8899, 2020'),
            _buildPortField('Mídia/Stream', _mediaPortController, '554, 34567'),
            _buildPortField('Eventos', _eventPortController, 'Opcional'),
            const SizedBox(height: 16),
            const Text(
              'Deixe em branco para usar detecção automática para essa porta específica.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => widget.onConfigChanged(null),
          child: const Text('Usar Padrão'),
        ),
        ElevatedButton(
          onPressed: _saveConfiguration,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
  
  Widget _buildPortField(String label, TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '$label (Porta)',
          hintText: hint,
          border: const OutlineInputBorder(),
          enabled: !_autoDetect,
        ),
      ),
    );
  }
}
```

## 6. Modificações nos Serviços ONVIF

### 6.1 Atualização do OnvifPtzService

```dart
class OnvifPtzService {
  // ... código existente ...
  
  Future<Onvif?> _getOrConnectOnvifWithPortConfig(
    String host, 
    String user, 
    String pass,
    CameraPortConfiguration? portConfig
  ) async {
    final key = '$host|$user';
    if (_onvifCache.containsKey(key)) return _onvifCache[key];

    // Usa configuração de portas se disponível
    final portsToTry = portConfig?.onvifPortsToTry ?? _defaultPorts;
    
    for (final port in portsToTry) {
      final endpoint = '$host:$port';
      try {
        final onvif = await Onvif.connect(
          host: endpoint, 
          username: user, 
          password: pass
        ).timeout(_connectionTimeout);
        
        _onvifCache[key] = onvif;
        _endpointCache[key] = endpoint;
        return onvif;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
  
  // Método atualizado que usa configuração de portas
  Future<bool> executePtzCommandWithPortConfig(
    CameraData camera, 
    String command
  ) async {
    // ... validações existentes ...
    
    final onvif = await _getOrConnectOnvifWithPortConfig(
      host, 
      user, 
      pass, 
      camera.portConfig
    );
    
    // ... resto da implementação ...
  }
}
```

### 6.2 Padrão para Outros Serviços

Todos os serviços ONVIF devem ser atualizados seguindo o mesmo padrão:
- `MotionDetectionService`
- `NightModeService`
- `NotificationService`
- `RecordingService`
- `OnvifCapabilitiesService`

## 7. Estratégia de Fallback

### 7.1 Compatibilidade com Sistema Atual

```dart
class CameraConnectionManager {
  /// Conecta usando nova configuração ou fallback para método atual
  static Future<Onvif?> connectToCamera(CameraData camera) async {
    final user = camera.username?.trim() ?? '';
    final pass = camera.password?.trim() ?? '';
    
    if (user.isEmpty || pass.isEmpty) return null;
    
    final uri = Uri.tryParse(camera.streamUrl);
    if (uri == null) return null;
    
    final host = uri.host;
    if (host.isEmpty) return null;
    
    // Usa nova configuração se disponível
    if (camera.portConfig != null) {
      return _connectWithPortConfig(host, user, pass, camera.portConfig!);
    }
    
    // Fallback para método atual
    return _connectLegacy(host, user, pass, camera.port);
  }
  
  static Future<Onvif?> _connectWithPortConfig(
    String host,
    String user, 
    String pass,
    CameraPortConfiguration config
  ) async {
    for (final port in config.onvifPortsToTry) {
      try {
        return await Onvif.connect(
          host: '$host:$port',
          username: user,
          password: pass,
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        continue;
      }
    }
    return null;
  }
  
  static Future<Onvif?> _connectLegacy(
    String host,
    String user,
    String pass,
    int? specificPort
  ) async {
    final portsToTry = specificPort != null 
      ? [specificPort] 
      : [80, 8080, 8000, 8899];
      
    for (final port in portsToTry) {
      try {
        return await Onvif.connect(
          host: '$host:$port',
          username: user,
          password: pass,
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
```

## 8. Implementação Gradual

### 8.1 Fase 1: Estrutura Base
1. Criar `CameraPortConfiguration` com suporte a protocolo proprietário
2. Adicionar campo `portConfig` em `CameraData`
3. Implementar serialização/deserialização
4. Manter compatibilidade total com sistema atual

### 8.2 Fase 2: Protocolo Proprietário
1. Implementar `ProprietaryProtocolService`
2. Criar estrutura de comandos binários
3. Implementar comandos básicos (Login, GetRecordList, PTZControl)
4. Testes com câmeras chinesas

### 8.3 Fase 3: Detecção Híbrida
1. Implementar `HybridCameraDetectionService`
2. Adicionar detecção automática ONVIF + proprietário
3. Implementar `HybridCameraConnectionManager`
4. Testar estratégia de fallback inteligente

### 8.4 Fase 4: Interface Manual
1. Criar `AdvancedPortConfigurationDialog` com opções de protocolo
2. Integrar na tela de edição de câmera
3. Adicionar seleção de tipo de protocolo
4. Validação de portas e protocolos

### 8.5 Fase 5: Atualização dos Serviços
1. Atualizar todos os serviços ONVIF para usar conexão híbrida
2. Implementar serviços específicos do protocolo proprietário
3. Testes extensivos com diferentes tipos de câmeras
4. Otimização de performance e cache

## 9. Casos de Teste

### 9.1 Cenários de Compatibilidade
- ✅ Câmera com porta única (comportamento atual)
- ✅ Câmera sem configuração específica (auto-detecção)
- ✅ Câmera com múltiplas portas configuradas
- ✅ Câmera com algumas portas específicas e outras auto-detectadas
- ✅ Câmera apenas ONVIF (protocolo padrão)
- ✅ Câmera apenas protocolo proprietário (câmeras chinesas)
- ✅ Câmera híbrida (ONVIF + protocolo proprietário)

### 9.2 Cenários de Protocolo Proprietário
- ✅ Login bem-sucedido no protocolo proprietário
- ✅ Listagem de gravações via protocolo proprietário
- ✅ Controle PTZ via protocolo proprietário
- ✅ Reprodução de vídeo via protocolo proprietário
- ✅ Fallback para ONVIF quando protocolo proprietário falha

### 9.3 Cenários de Falha
- ✅ Porta ONVIF específica não responde → fallback para auto-detecção
- ✅ Protocolo proprietário não responde → usar apenas ONVIF
- ✅ Ambos os protocolos falham → comportamento atual (erro de conexão)
- ✅ Configuração inválida → usar padrões do sistema
- ✅ Comando proprietário inválido → log de erro e continuação

## 10. Benefícios da Implementação

1. **Compatibilidade Total**: Sistema atual continua funcionando sem alterações
2. **Suporte a Câmeras Chinesas**: Protocolo proprietário para funcionalidades avançadas
3. **Estratégia Híbrida**: Combina ONVIF padrão com protocolo proprietário
4. **Detecção Inteligente**: Identifica automaticamente o melhor protocolo
5. **Flexibilidade**: Suporte a arquiteturas complexas de câmeras
6. **Interface Amigável**: Configuração avançada opcional
7. **Performance**: Cache de configurações e conexões bem-sucedidas
8. **Funcionalidades Avançadas**: Listagem de gravações, reprodução e PTZ avançado
9. **Fallback Robusto**: Sistema de fallback inteligente entre protocolos
10. **Manutenibilidade**: Código organizado, extensível e bem documentado

### 10.1 Impacto no Mercado Brasileiro

Esta implementação aumenta significativamente a compatibilidade do aplicativo com câmeras IP disponíveis no mercado brasileiro, especialmente:

- **Câmeras Chinesas**: Suporte completo via protocolo proprietário
- **Câmeras Híbridas**: Aproveitamento máximo de funcionalidades
- **Câmeras Padrão**: Manutenção da compatibilidade ONVIF
- **Câmeras Antigas**: Fallback para detecção automática

Esta implementação permite suporte completo a câmeras com múltiplas portas e protocolos, mantendo total compatibilidade com o sistema existente e adicionando funcionalidades avançadas para câmeras que suportam protocolo proprietário.