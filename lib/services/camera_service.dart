import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/camera_model.dart';
import '../models/camera_models.dart';
import '../models/models.dart';
import '../models/camera_status.dart';
import '../models/notification_model.dart';
import '../models/stream_config.dart';
import '../services/hybrid_camera_detection_service.dart';
import '../services/proprietary_protocol_service.dart';
import '../services/unified_onvif_service.dart';

class CameraService {
  static final CameraService _instance = CameraService._internal();
  static CameraService get instance => _instance;
  factory CameraService() => _instance;
  CameraService._internal();

  final Map<String, Socket?> _connections = {};
  final Map<String, StreamController<Map<String, dynamic>>> _responseStreams = {};
  final Map<String, Timer?> _heartbeatTimers = {};
  final Map<String, DateTime> _lastHeartbeat = {};
  final List<CameraModel> _cameras = [];
  final Map<int, CameraModel> _connectedCameras = {};
  final StreamController<List<CameraModel>> _cameraStreamController = StreamController<List<CameraModel>>.broadcast();

  List<CameraModel> get cameras => List.unmodifiable(_cameras);
  Stream<List<CameraModel>> get cameraStream => _cameraStreamController.stream;

  Function(CameraModel)? _onCameraStatusChanged;


  // Setters para callbacks
  set onCameraStatusChanged(Function(CameraModel)? callback) {
    _onCameraStatusChanged = callback;
  }

  /// Notifica listeners sobre mudanças na lista de câmeras
  void _notifyListeners() {
    _cameraStreamController.add(List.unmodifiable(_cameras));
  }

  /// Adiciona uma nova câmera
  Future<void> addCamera(CameraModel camera) async {
    if (!_cameras.any((c) => c.id == camera.id)) {
      _cameras.add(camera);
      await _saveCameras();
      _notifyListeners();
    }
  }

  /// Atualiza uma câmera existente
  Future<void> updateCamera(CameraModel camera) async {
    final index = _cameras.indexWhere((c) => c.id == camera.id);
    if (index != -1) {
      _cameras[index] = camera;
      await _saveCameras();
      _notifyListeners();
    }
  }

  /// Remove uma câmera
  Future<void> removeCamera(String cameraId) async {
    await disconnectFromCamera(cameraId);
    _cameras.removeWhere((c) => c.id == cameraId);
    await _saveCameras();
  }

  /// Conecta à câmera usando detecção automática de protocolo
  Future<bool> connectToCamera(CameraModel camera) async {
    try {
      // Fecha conexão existente se houver
      await disconnectFromCamera(camera.id.toString());

      print('Iniciando conexão com ${camera.name} (${camera.ipAddress})');
      print('Detectando protocolo suportado...');

      // Detecta automaticamente o protocolo suportado
      final detectionResult = await HybridCameraDetectionService.detectProtocol(
        camera.ipAddress,
        username: camera.username,
        password: camera.password,
      );

      print('Protocolo detectado: ${detectionResult.detectedProtocol}');
      print('ONVIF suportado: ${detectionResult.onvifSupported}');
      print('Proprietário suportado: ${detectionResult.proprietarySupported}');

      // Detecção automática de protocolo - prioriza ONVIF
      bool connected = false;

      // 1. Primeiro tenta ONVIF (protocolo padrão moderno)
      if (detectionResult.onvifSupported) {
        print('Tentando conexão ONVIF para ${camera.name}...');
        final onvifService = UnifiedOnvifService();
        // Converter CameraModel para CameraData
        final cameraData = CameraData(
          id: int.parse(camera.id),
          name: camera.name,
          isLive: camera.status == CameraStatus.online,
          statusColor: Colors.green,
          uniqueColor: Colors.blue,
          icon: Icons.camera,
          streamUrl: 'rtsp://${camera.ipAddress}:${camera.port}${camera.rtspPath ?? '/'}',
          username: camera.username,
          password: camera.password,
          port: camera.port,
          host: camera.ipAddress,
          portConfiguration: const CameraPortConfiguration(),
        );
        connected = await onvifService.connect(cameraData);
        
        if (connected) {
          print('Conectado via ONVIF com sucesso!');
          print('ONVIF conectado com sucesso na porta ${detectionResult.portConfiguration.onvifPort}');
          return true;
        } else {
          print('ONVIF falhou, tentando RTSP direto para ${camera.name}...');
        }
      }

      // 2. Se ONVIF falhar, tenta RTSP direto
      if (!connected) {
        print('Tentando RTSP direto para ${camera.name}...');
        connected = await _testRtspConnection(camera);
        
        if (connected) {
          print('Conexão RTSP direta estabelecida!');
          return true;
        }
      }

      // 3. Como último recurso, tenta protocolo proprietário (para câmeras chinesas antigas)
      if (detectionResult.proprietarySupported && !connected) {
        print('RTSP falhou, tentando protocolo proprietário para ${camera.name}...');
        connected = await _connectUsingProprietaryProtocol(camera, detectionResult.portConfiguration);
        
        if (connected) {
          print('Conectado via protocolo proprietário com sucesso!');
          return true;
        }
      }

      print('Falha ao conectar com ${camera.name} - todos os protocolos falharam');
      return false;

    } catch (e) {
      print('Erro ao conectar à câmera ${camera.name}: $e');
      await disconnectFromCamera(camera.id.toString());
      return false;
    }
  }

  // Método para conectar usando ONVIF
  Future<bool> _connectUsingOnvif(CameraModel camera) async {
    try {
      final onvifService = UnifiedOnvifService();
      // Converter CameraModel para CameraData
      final cameraData = CameraData(
        id: int.parse(camera.id),
        name: camera.name,
        isLive: camera.status == CameraStatus.online,
        statusColor: Colors.green,
        uniqueColor: Colors.blue,
        icon: Icons.camera,
        streamUrl: 'rtsp://${camera.ipAddress}:${camera.port}${camera.rtspPath ?? '/'}',
        username: camera.username,
        password: camera.password,
        port: camera.port,
        host: camera.ipAddress,
        portConfiguration: const CameraPortConfiguration(),
      );
      return await onvifService.connect(cameraData);
    } catch (e) {
      print('Erro na conexão ONVIF: $e');
      return false;
    }
  }

  /// Conecta usando protocolo proprietário (fallback)
  Future<bool> _connectUsingProprietaryProtocol(CameraModel camera, dynamic config) async {
    try {
      // Cria nova conexão TCP usando a porta proprietária detectada
      final socket = await Socket.connect(
        camera.ipAddress,
        config?.proprietaryPort ?? 8000,
        timeout: const Duration(seconds: 10),
      );

      _connections[camera.id.toString()] = socket;
      _setupSocketListener(camera.id.toString(), socket);
      _startHeartbeat(camera.id.toString());

      // Tenta autenticar usando protocolo proprietário
      final authResult = await authenticate(camera);
      if (!authResult) {
        await disconnectFromCamera(camera.id.toString());
        return false;
      }

      // Atualiza a porta de controle
      print('Protocolo proprietário conectado com sucesso na porta ${config?.proprietaryPort ?? 8000}');
      return true;
    } catch (e) {
      print('Erro na conexão proprietária: $e');
      return false;
    }
  }

  /// Testa conexão RTSP direta
  Future<bool> _testRtspConnection(CameraModel camera) async {
    try {
      // Testa conectividade na porta RTSP padrão (554)
      final socket = await Socket.connect(
        camera.ipAddress,
        554,
        timeout: const Duration(seconds: 5),
      );
      
      // Envia comando RTSP OPTIONS para testar
      final rtspRequest = 'OPTIONS rtsp://${camera.ipAddress}:554/ RTSP/1.0\r\n'
          'CSeq: 1\r\n'
          'User-Agent: Camera-App\r\n\r\n';
      
      socket.write(rtspRequest);
      await socket.flush();
      
      // Aguarda resposta por 3 segundos
      final completer = Completer<String>();
      late StreamSubscription subscription;
      
      subscription = socket.cast<List<int>>().transform(utf8.decoder).listen(
        (data) {
          if (!completer.isCompleted) {
            completer.complete(data);
            subscription.cancel();
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.complete('');
          }
        },
      );
      
      final response = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => '',
      );
      
      socket.close();
      
      // Verifica se recebeu resposta RTSP válida
      if (response.contains('RTSP/1.0') && response.contains('200')) {
        print('Conexão RTSP direta estabelecida na porta 554');
        return true;
      }
      
      return false;
    } catch (e) {
      print('Erro no teste RTSP: $e');
      return false;
    }
  }

  /// Desconecta da câmera
  Future<void> disconnectFromCamera(dynamic cameraId) async {
    try {
      final cameraIdStr = cameraId.toString();
      
      // Desconecta do serviço ONVIF se estiver usando
      final onvifService = UnifiedOnvifService();
      await onvifService.disconnect(cameraIdStr);

      // Para o heartbeat
      _heartbeatTimers[cameraIdStr]?.cancel();
      _heartbeatTimers.remove(cameraIdStr);
      _lastHeartbeat.remove(cameraIdStr);

      // Fecha o stream de resposta
      await _responseStreams[cameraIdStr]?.close();
      _responseStreams.remove(cameraIdStr);

      // Fecha a conexão socket
      await _connections[cameraIdStr]?.close();
      _connections.remove(cameraIdStr);

      // Remove da lista de câmeras conectadas
      _connectedCameras.remove(cameraId);

      print('Desconectado da câmera $cameraId');
    } catch (e) {
      print('Erro ao desconectar da câmera $cameraId: $e');
    }
  }

  /// Autentica com a câmera usando MD5
  Future<bool> authenticate(CameraModel camera) async {
    try {
      final nonce = _generateNonce();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Gera hash MD5 da senha
      final passwordHash = md5.convert(utf8.encode(camera.password ?? '')).toString();
      
      // Cria hash de autenticação
      final authString = '${camera.username}:$passwordHash:$nonce:$timestamp';
      final authHash = md5.convert(utf8.encode(authString)).toString();

      final authCommand = {
        'Command': 'LOGIN',
        'EncryptType': 'MD5',
        'LoginType': 'DVRIP-Web',
        'UserName': camera.username,
        'PassWord': authHash,
        'Nonce': nonce,
        'Timestamp': timestamp,
      };

      final response = await sendCommand(camera.id.toString(), authCommand);
      
      if (response != null && response['Ret'] == 100) {
        print('Autenticação bem-sucedida para câmera ${camera.name}');
        return true;
      } else {
        print('Falha na autenticação para câmera ${camera.name}');
        return false;
      }
    } catch (e) {
      print('Erro durante autenticação da câmera ${camera.name}: $e');
      return false;
    }
  }

  /// Envia comando para a câmera
  Future<Map<String, dynamic>?> sendCommand(
    dynamic cameraId,
    Map<String, dynamic> command,
  ) async {
    final cameraIdStr = cameraId.toString();
    final socket = _connections[cameraIdStr];
    if (socket == null) {
      print('Câmera $cameraIdStr não está conectada');
      return null;
    }

    try {
      // Serializa o comando
      final jsonCommand = jsonEncode(command);
      final commandBytes = utf8.encode(jsonCommand);
      
      // Cria header (12 bytes)
      final header = _buildCommandHeader(commandBytes.length);
      
      // Envia header + payload
      socket.add(header);
      socket.add(commandBytes);
      await socket.flush();

      // Aguarda resposta
      final response = await _waitForResponse(cameraIdStr);
      return response;
    } catch (e) {
      print('Erro ao enviar comando para câmera $cameraIdStr: $e');
      return null;
    }
  }

  /// Constrói header do comando (12 bytes)
  List<int> _buildCommandHeader(int payloadLength) {
    final header = List<int>.filled(12, 0);
    
    // Magic number (4 bytes)
    header[0] = 0xFF;
    header[1] = 0x01;
    header[2] = 0x00;
    header[3] = 0x00;
    
    // Payload length (4 bytes, little endian)
    header[4] = payloadLength & 0xFF;
    header[5] = (payloadLength >> 8) & 0xFF;
    header[6] = (payloadLength >> 16) & 0xFF;
    header[7] = (payloadLength >> 24) & 0xFF;
    
    // Reserved (4 bytes)
    header[8] = 0x00;
    header[9] = 0x00;
    header[10] = 0x00;
    header[11] = 0x00;
    
    return header;
  }

  /// Configura listener do socket
  void _setupSocketListener(String cameraId, Socket socket) {
    _responseStreams[cameraId] = StreamController<Map<String, dynamic>>.broadcast();
    
    socket.listen(
      (data) => _handleSocketData(cameraId, data),
      onError: (error) {
        print('Erro no socket da câmera $cameraId: $error');
        disconnectFromCamera(cameraId);
      },
      onDone: () {
        print('Conexão com câmera $cameraId foi fechada');
        disconnectFromCamera(cameraId);
      },
    );
  }

  /// Processa dados recebidos do socket
  void _handleSocketData(String cameraId, List<int> data) {
    try {
      // Verifica se tem header completo (12 bytes)
      if (data.length < 12) return;
      
      // Extrai tamanho do payload do header
      final payloadLength = data[4] | 
                           (data[5] << 8) | 
                           (data[6] << 16) | 
                           (data[7] << 24);
      
      // Verifica se tem payload completo
      if (data.length < 12 + payloadLength) return;
      
      // Extrai payload
      final payloadBytes = data.sublist(12, 12 + payloadLength);
      final payloadString = utf8.decode(payloadBytes);
      
      // Decodifica JSON
      final response = jsonDecode(payloadString) as Map<String, dynamic>;
      
      // Adiciona ao stream de resposta
      _responseStreams[cameraId]?.add(response);
      
      // Atualiza último heartbeat se for resposta de heartbeat
      if (response['Command'] == 'HEARTBEAT') {
        _lastHeartbeat[cameraId] = DateTime.now();
      }
    } catch (e) {
      print('Erro ao processar dados da câmera $cameraId: $e');
    }
  }

  /// Aguarda resposta da câmera
  Future<Map<String, dynamic>?> _waitForResponse(
    String cameraId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final stream = _responseStreams[cameraId];
    if (stream == null) return null;

    try {
      return await stream.stream.first.timeout(timeout);
    } catch (e) {
      print('Timeout aguardando resposta da câmera $cameraId');
      return null;
    }
  }

  /// Inicia heartbeat para manter conexão viva
  void _startHeartbeat(String cameraId) {
    _heartbeatTimers[cameraId] = Timer.periodic(
      const Duration(seconds: 30),
      (timer) async {
        final heartbeatCommand = {
          'Command': 'HEARTBEAT',
          'Timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        await sendCommand(cameraId, heartbeatCommand);
        
        // Verifica se recebeu heartbeat recentemente
        final lastHeartbeat = _lastHeartbeat[cameraId];
        if (lastHeartbeat != null) {
          final timeSinceLastHeartbeat = DateTime.now().difference(lastHeartbeat);
          if (timeSinceLastHeartbeat.inMinutes > 2) {
            print('Câmera $cameraId não responde ao heartbeat');
            await disconnectFromCamera(cameraId);
          }
        }
      },
    );
  }

  /// Gera nonce para autenticação
  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return base64.encode(bytes);
  }

  /// Verifica se a câmera está conectada
  bool isConnected(String cameraId) {
    return _connections[cameraId] != null;
  }

  /// Obtém status da conexão
  Map<String, dynamic> getConnectionStatus(String cameraId) {
    final isConnected = this.isConnected(cameraId);
    final lastHeartbeat = _lastHeartbeat[cameraId];
    
    return {
      'connected': isConnected,
      'lastHeartbeat': lastHeartbeat?.toIso8601String(),
      'timeSinceLastHeartbeat': lastHeartbeat != null
          ? DateTime.now().difference(lastHeartbeat).inSeconds
          : null,
    };
  }

  /// Obtém informações da câmera
  Future<Map<String, dynamic>?> getCameraInfo(String cameraId) async {
    final command = {
      'Command': 'GET_DEVICE_INFO',
      'Timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    return await sendCommand(cameraId, command);
  }

  /// Obtém capacidades da câmera
  Future<Map<String, dynamic>?> getCameraCapabilities(String cameraId) async {
    final command = {
      'Command': 'GET_CAPABILITIES',
      'Timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    return await sendCommand(cameraId, command);
  }

  /// Configura stream da câmera
  Future<bool> configureStream(
    String cameraId,
    StreamConfig streamConfig,
  ) async {
    final command = {
      'Command': 'SET_STREAM_CONFIG',
      'VideoCodec': streamConfig.videoCodec.name,
      'AudioCodec': streamConfig.audioCodec?.name,
      'Resolution': streamConfig.resolution,
      'Bitrate': streamConfig.bitrate,
      'FrameRate': streamConfig.frameRate,
      'AudioEnabled': streamConfig.audioEnabled,
      'Timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    final response = await sendCommand(cameraId, command);
    return response != null && response['Ret'] == 100;
  }

  /// Desconecta de todas as câmeras
  Future<void> disconnectAll() async {
    final cameraIds = List<String>.from(_connections.keys);
    for (final cameraId in cameraIds) {
      await disconnectFromCamera(cameraId);
    }
  }

  /// Conecta a uma câmera (método público)
  Future<bool> connectCamera(CameraModel camera) async {
    final result = await connectToCamera(camera);
    if (result) {
      final index = _cameras.indexWhere((c) => c.id == camera.id);
      if (index != -1) {
        _cameras[index] = camera.copyWith(status: CameraStatus.online);
        _onCameraStatusChanged?.call(_cameras[index]);
      }
    }
    return result;
  }

  /// Desconecta de uma câmera (método público)
  Future<void> disconnectCamera(String cameraId) async {
    await disconnectFromCamera(cameraId);
    final index = _cameras.indexWhere((c) => c.id == cameraId);
    if (index != -1) {
      _cameras[index] = _cameras[index].copyWith(status: CameraStatus.offline);
      _onCameraStatusChanged?.call(_cameras[index]);
    }
  }

  /// Obtém lista de câmeras conectadas
  List<String> getConnectedCameras() {
    return _connections.keys.where((id) => _connections[id] != null).toList();
  }

  /// Salva câmeras no SharedPreferences
  Future<void> _saveCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final camerasJson = _cameras.map((c) => c.toJson()).toList();
      await prefs.setString('cameras', jsonEncode(camerasJson));
    } catch (e) {
      print('Erro ao salvar câmeras: $e');
    }
  }

  /// Carrega câmeras do SharedPreferences
  Future<void> loadCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final camerasString = prefs.getString('cameras');
      if (camerasString != null) {
        final List<dynamic> camerasJson = jsonDecode(camerasString);
        _cameras.clear();
        _cameras.addAll(
          camerasJson.map((json) => CameraModel.fromJson(json)).toList(),
        );
        _notifyListeners();
      }
    } catch (e) {
      print('Erro ao carregar câmeras: $e');
    }
  }

  /// Dispose do serviço
  void dispose() {
    disconnectAll();
  }
}