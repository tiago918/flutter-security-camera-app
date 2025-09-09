// Exemplo de Implementação do Protocolo da Câmera de Segurança
// Baseado na análise dos dados de interceptação IP

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class CameraProtocol {
  // Constantes do protocolo
  static const int HEADER = 0xff000000;
  static const int LOGIN_CMD = 0x00010000;
  static const int GET_RECORD_CMD = 0x00020000;
  static const int START_PLAYBACK_CMD = 0x00030000;
  static const int PTZ_CMD = 0x00040000;
  
  static const int CONTROL_PORT = 34567;
  static const int STREAM_PORT = 2223;
  
  Socket? _controlSocket;
  Socket? _streamSocket;
  String? _cameraIp;
  bool _isAuthenticated = false;
  
  // Construtor
  CameraProtocol(String cameraIp) {
    _cameraIp = cameraIp;
  }
  
  /// Conecta à câmera na porta de controle
  Future<bool> connect() async {
    try {
      _controlSocket = await Socket.connect(_cameraIp!, CONTROL_PORT);
      print('Conectado à câmera em $_cameraIp:$CONTROL_PORT');
      return true;
    } catch (e) {
      print('Erro ao conectar: $e');
      return false;
    }
  }
  
  /// Constrói um comando seguindo o protocolo identificado
  List<int> _buildCommand(int commandId, Map<String, dynamic> payload) {
    // Converte payload para JSON
    String jsonPayload = jsonEncode(payload);
    List<int> payloadBytes = utf8.encode(jsonPayload);
    
    // Cria buffer com cabeçalho + payload
    ByteData buffer = ByteData(12 + payloadBytes.length);
    
    // Cabeçalho fixo (4 bytes)
    buffer.setUint32(0, HEADER, Endian.big);
    
    // ID do comando (4 bytes, little endian)
    buffer.setUint32(4, commandId, Endian.little);
    
    // Tamanho do payload (4 bytes, little endian)
    buffer.setUint32(8, payloadBytes.length, Endian.little);
    
    // Combina cabeçalho + payload
    List<int> command = buffer.buffer.asUint8List().toList();
    command.addAll(payloadBytes);
    
    return command;
  }
  
  /// Envia comando e aguarda resposta
  Future<Map<String, dynamic>?> _sendCommand(List<int> command) async {
    if (_controlSocket == null) {
      print('Socket não conectado');
      return null;
    }
    
    try {
      // Envia comando
      _controlSocket!.add(command);
      await _controlSocket!.flush();
      
      // Aguarda resposta (implementação simplificada)
      await Future.delayed(Duration(milliseconds: 500));
      
      // Em implementação real, seria necessário ler e parsear a resposta
      // Por enquanto, retorna sucesso simulado
      return {'Ret': 100, 'SessionID': '0x12345678'};
      
    } catch (e) {
      print('Erro ao enviar comando: $e');
      return null;
    }
  }
  
  /// Realiza autenticação na câmera
  Future<bool> authenticate(String username, String password) async {
    if (_controlSocket == null) {
      print('Não conectado à câmera');
      return false;
    }
    
    try {
      // Gera hash MD5 da senha conforme protocolo
      String passwordHash = md5.convert(utf8.encode(password)).toString();
      
      // Monta payload de login conforme documentação
      Map<String, dynamic> loginPayload = {
        'EncryptType': 'MD5',
        'LoginType': 'DVRIP-Web',
        'PassWord': passwordHash,
        'UserName': username,
      };
      
      // Constrói e envia comando de login
      List<int> loginCommand = _buildCommand(LOGIN_CMD, loginPayload);
      Map<String, dynamic>? response = await _sendCommand(loginCommand);
      
      // Verifica resposta de sucesso
      if (response != null && response['Ret'] == 100) {
        _isAuthenticated = true;
        print('Autenticação realizada com sucesso');
        return true;
      } else {
        print('Falha na autenticação');
        return false;
      }
      
    } catch (e) {
      print('Erro durante autenticação: $e');
      return false;
    }
  }
  
  /// Obtém lista de gravações
  Future<List<Map<String, dynamic>>?> getRecordList({
    int channel = 0,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (!_isAuthenticated) {
      print('Não autenticado');
      return null;
    }
    
    try {
      // Formata datas conforme protocolo
      String startTimeStr = '${startTime.year.toString().padLeft(4, '0')}-'
          '${startTime.month.toString().padLeft(2, '0')}-'
          '${startTime.day.toString().padLeft(2, '0')} '
          '${startTime.hour.toString().padLeft(2, '0')}:'
          '${startTime.minute.toString().padLeft(2, '0')}:'
          '${startTime.second.toString().padLeft(2, '0')}';
      
      String endTimeStr = '${endTime.year.toString().padLeft(4, '0')}-'
          '${endTime.month.toString().padLeft(2, '0')}-'
          '${endTime.day.toString().padLeft(2, '0')} '
          '${endTime.hour.toString().padLeft(2, '0')}:'
          '${endTime.minute.toString().padLeft(2, '0')}:'
          '${endTime.second.toString().padLeft(2, '0')}';
      
      // Monta payload conforme protocolo identificado
      Map<String, dynamic> payload = {
        'Cmd': 'GetRecord',
        'Channel': channel,
        'StartTime': startTimeStr,
        'EndTime': endTimeStr,
      };
      
      // Envia comando
      List<int> command = _buildCommand(GET_RECORD_CMD, payload);
      Map<String, dynamic>? response = await _sendCommand(command);
      
      if (response != null && response['Ret'] == 100) {
        // Em implementação real, parsear lista de arquivos da resposta
        return [
          {
            'FileName': 'record_001.mp4',
            'StartTime': startTimeStr,
            'EndTime': endTimeStr,
            'Size': 1024000,
          }
        ];
      }
      
      return null;
      
    } catch (e) {
      print('Erro ao obter lista de gravações: $e');
      return null;
    }
  }
  
  /// Inicia reprodução de vídeo gravado
  Future<bool> startPlayback({
    int channel = 0,
    required DateTime startTime,
  }) async {
    if (!_isAuthenticated) {
      print('Não autenticado');
      return false;
    }
    
    try {
      // Formata data/hora
      String startTimeStr = '${startTime.year.toString().padLeft(4, '0')}-'
          '${startTime.month.toString().padLeft(2, '0')}-'
          '${startTime.day.toString().padLeft(2, '0')} '
          '${startTime.hour.toString().padLeft(2, '0')}:'
          '${startTime.minute.toString().padLeft(2, '0')}:'
          '${startTime.second.toString().padLeft(2, '0')}';
      
      // Monta payload
      Map<String, dynamic> payload = {
        'Cmd': 'StartPlayback',
        'Channel': channel,
        'StartTime': startTimeStr,
      };
      
      // Envia comando
      List<int> command = _buildCommand(START_PLAYBACK_CMD, payload);
      Map<String, dynamic>? response = await _sendCommand(command);
      
      return response != null && response['Ret'] == 100;
      
    } catch (e) {
      print('Erro ao iniciar reprodução: $e');
      return false;
    }
  }
  
  /// Controla movimento PTZ da câmera
  Future<bool> controlPTZ({
    int channel = 0,
    required String direction, // 'Up', 'Down', 'Left', 'Right', 'ZoomIn', 'ZoomOut'
    int speed = 5, // 1-10
  }) async {
    if (!_isAuthenticated) {
      print('Não autenticado');
      return false;
    }
    
    try {
      // Monta payload para controle PTZ
      Map<String, dynamic> payload = {
        'Cmd': 'PTZ',
        'Channel': channel,
        'Direction': direction,
        'Speed': speed,
      };
      
      // Envia comando
      List<int> command = _buildCommand(PTZ_CMD, payload);
      Map<String, dynamic>? response = await _sendCommand(command);
      
      return response != null && response['Ret'] == 100;
      
    } catch (e) {
      print('Erro no controle PTZ: $e');
      return false;
    }
  }
  
  /// Conecta ao stream de vídeo
  Future<bool> connectVideoStream() async {
    try {
      _streamSocket = await Socket.connect(_cameraIp!, STREAM_PORT);
      print('Conectado ao stream de vídeo em $_cameraIp:$STREAM_PORT');
      
      // Configura listener para dados do stream
      _streamSocket!.listen(
        (List<int> data) {
          // Processa dados do stream de vídeo
          print('Recebidos ${data.length} bytes do stream');
        },
        onError: (error) {
          print('Erro no stream: $error');
        },
        onDone: () {
          print('Stream finalizado');
        },
      );
      
      return true;
      
    } catch (e) {
      print('Erro ao conectar stream: $e');
      return false;
    }
  }
  
  /// Desconecta da câmera
  Future<void> disconnect() async {
    try {
      await _controlSocket?.close();
      await _streamSocket?.close();
      _isAuthenticated = false;
      print('Desconectado da câmera');
    } catch (e) {
      print('Erro ao desconectar: $e');
    }
  }
  
  /// Getter para status de autenticação
  bool get isAuthenticated => _isAuthenticated;
}

// Exemplo de uso
void main() async {
  // Cria instância do protocolo
  CameraProtocol camera = CameraProtocol('82.115.15.137');
  
  try {
    // Conecta à câmera
    bool connected = await camera.connect();
    if (!connected) {
      print('Falha ao conectar');
      return;
    }
    
    // Autentica
    bool authenticated = await camera.authenticate('admin', 'password123');
    if (!authenticated) {
      print('Falha na autenticação');
      return;
    }
    
    // Obtém lista de gravações
    DateTime hoje = DateTime.now();
    DateTime ontem = hoje.subtract(Duration(days: 1));
    
    List<Map<String, dynamic>>? recordings = await camera.getRecordList(
      startTime: ontem,
      endTime: hoje,
    );
    
    if (recordings != null) {
      print('Encontradas ${recordings.length} gravações');
      for (var record in recordings) {
        print('Arquivo: ${record['FileName']}');
      }
    }
    
    // Controla PTZ
    await camera.controlPTZ(direction: 'Up', speed: 3);
    await Future.delayed(Duration(seconds: 2));
    await camera.controlPTZ(direction: 'Left', speed: 5);
    
    // Conecta stream de vídeo
    await camera.connectVideoStream();
    
    // Aguarda um pouco para receber dados
    await Future.delayed(Duration(seconds: 10));
    
  } finally {
    // Desconecta
    await camera.disconnect();
  }
}

// Classe auxiliar para gerenciar múltiplas câmeras
class CameraManager {
  Map<String, CameraProtocol> _cameras = {};
  
  /// Adiciona uma câmera
  void addCamera(String id, String ip) {
    _cameras[id] = CameraProtocol(ip);
  }
  
  /// Obtém câmera por ID
  CameraProtocol? getCamera(String id) {
    return _cameras[id];
  }
  
  /// Conecta todas as câmeras
  Future<Map<String, bool>> connectAll() async {
    Map<String, bool> results = {};
    
    for (String id in _cameras.keys) {
      CameraProtocol camera = _cameras[id]!;
      results[id] = await camera.connect();
    }
    
    return results;
  }
  
  /// Desconecta todas as câmeras
  Future<void> disconnectAll() async {
    for (CameraProtocol camera in _cameras.values) {
      await camera.disconnect();
    }
  }
}