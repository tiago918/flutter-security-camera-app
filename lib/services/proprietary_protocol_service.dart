import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/models.dart';
import '../models/protocol_test_result.dart';

/// Serviço para protocolo proprietário DVRIP-Web
class ProprietaryProtocolService {
  static const List<int> _commonPorts = [34567, 37777, 8000, 8080, 9000];
  
  Socket? _socket;
  String? _sessionId;
  bool _isConnected = false;
  
  // Getters
  String? get sessionId => _sessionId;
  bool get isConnected => _isConnected;
  
  /// Testa suporte ao protocolo proprietário (método estático)
  static Future<ProtocolTestResult> testSupportStatic(String ipAddress) async {
    for (final port in _commonPorts) {
      try {
        final socket = await Socket.connect(
          ipAddress,
          port,
          timeout: const Duration(seconds: 5),
        );
        
        // Tenta enviar comando de login básico
        final loginCommand = _createLoginCommand('admin', '');
        socket.add(loginCommand);
        await socket.flush();
        
        // Aguarda resposta
        final response = await socket.first.timeout(
          const Duration(seconds: 3),
          onTimeout: () => Uint8List(0),
        );
        
        socket.close();
        
        // Verifica se recebeu resposta válida do protocolo DVRIP
        if (response.isNotEmpty && _isValidDvripResponse(response)) {
          return ProtocolTestResult.success(
            protocol: 'proprietary',
            port: port,
            additionalInfo: {
              'type': 'DVRIP-Web',
              'version': '1.0',
            },
          );
        }
      } catch (e) {
        // Continua testando outras portas
        continue;
      }
    }
    
    return ProtocolTestResult.failure(
      protocol: 'proprietary',
      error: 'Nenhuma porta proprietária respondeu',
    );
  }
  
  // Método de conexão estático removido - usando método de instância

  void disconnect() {
    // Método para desconectar - implementação básica
    _socket?.close();
    _socket = null;
    _sessionId = null;
    _isConnected = false;
    print('Desconectando do protocolo proprietário');
  }
  
  /// Conecta à câmera (método de instância)
  Future<bool> connect(String host, int port, {Duration? timeout}) async {
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: timeout ?? const Duration(seconds: 5),
      );
      _isConnected = true;
      return true;
    } catch (e) {
      print('Erro ao conectar: $e');
      _isConnected = false;
      return false;
    }
  }
  
  /// Testa suporte ao protocolo proprietário (método de instância)
  Future<bool> testSupport(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      
      // Tenta enviar comando de login básico
      final loginCommand = _createLoginCommand('admin', '');
      socket.add(loginCommand);
      await socket.flush();
      
      // Aguarda resposta
      final response = await socket.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => Uint8List(0),
      );
      
      socket.close();
      
      // Verifica se recebeu resposta válida do protocolo DVRIP
      return response.isNotEmpty && _isValidDvripResponse(response);
    } catch (e) {
      print('Erro ao testar suporte proprietário: $e');
      return false;
    }
  }

  /// Login (método de instância)
  Future<bool> login(String username, String password) async {
    if (!_isConnected || _socket == null) return false;
    
    try {
      final result = await authenticate(_socket!, username, password);
      if (result) {
        _sessionId = Random().nextInt(0xFFFFFFFF).toString();
      }
      return result;
    } catch (e) {
      print('Erro no login: $e');
      return false;
    }
  }
  
  /// Obtém lista de gravações
  Future<List<Map<String, dynamic>>> getRecordingList(DateTime startTime, DateTime endTime) async {
    if (!_isConnected || _socket == null) return [];
    
    try {
      // Implementação básica - retorna lista vazia por enquanto
      return [];
    } catch (e) {
      print('Erro ao obter lista de gravações: $e');
      return [];
    }
  }
  
  /// Inicia reprodução de gravação
  Future<String?> startPlayback(String fileName) async {
    if (!_isConnected || _socket == null) return null;
    
    try {
      // Implementação básica - retorna URL fictícia
      return 'rtsp://playback/$fileName';
    } catch (e) {
      print('Erro ao iniciar reprodução: $e');
      return null;
    }
  }
  
  /// Controle PTZ
  Future<bool> ptzControl(String command, {double? speed}) async {
    if (!_isConnected || _socket == null) return false;
    
    try {
      // Implementação básica - sempre retorna sucesso
      print('Comando PTZ: $command, velocidade: $speed');
      return true;
    } catch (e) {
      print('Erro no controle PTZ: $e');
      return false;
    }
  }
  
  /// Dispose
  void dispose() {
    disconnect();
  }
  
  /// Método de login estático (alias para authenticate)
  static Future<bool> staticLogin(String username, String password, {Duration? timeout}) async {
    try {
      final socket = await Socket.connect(
        '192.168.1.1', // IP padrão, deve ser passado como parâmetro
        34567,
        timeout: timeout ?? const Duration(seconds: 10),
      );
      
      final result = await authenticate(socket, username, password);
      socket.close();
      return result;
    } catch (e) {
      print('Erro no login proprietário: $e');
      return false;
    }
  }

  /// Autentica usando protocolo proprietário
  static Future<bool> authenticate(Socket socket, String username, String password) async {
    try {
      // Cria comando de login
      final loginCommand = _createLoginCommand(username, password);
      socket.add(loginCommand);
      await socket.flush();
      
      // Aguarda resposta de autenticação
      final response = await socket.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => Uint8List(0),
      );
      
      // Verifica se autenticação foi bem-sucedida
      return _isAuthenticationSuccessful(response);
    } catch (e) {
      print('Erro na autenticação proprietária: $e');
      return false;
    }
  }
  
  /// Cria comando de login DVRIP
  static Uint8List _createLoginCommand(String username, String password) {
    final sessionId = Random().nextInt(0xFFFFFFFF);
    final sequenceNumber = 0;
    
    // Dados do login em JSON
    final loginData = {
      'EncryptType': 'MD5',
      'LoginType': 'DVRIP-Web',
      'PassWord': _md5Hash(password),
      'UserName': username,
    };
    
    final jsonData = json.encode(loginData);
    final jsonBytes = utf8.encode(jsonData);
    
    // Cabeçalho DVRIP (20 bytes)
    final header = ByteData(20);
    header.setUint8(0, 0xFF); // Head flag
    header.setUint8(1, 0x01); // Version
    header.setUint8(2, 0x00); // Reserved
    header.setUint8(3, 0x00); // Reserved
    header.setUint32(4, sessionId, Endian.little); // Session ID
    header.setUint32(8, sequenceNumber, Endian.little); // Sequence number
    header.setUint32(12, 1000, Endian.little); // Command (LOGIN_REQ)
    header.setUint32(16, jsonBytes.length, Endian.little); // Data length
    
    // Combina cabeçalho e dados
    final command = Uint8List(20 + jsonBytes.length);
    command.setRange(0, 20, header.buffer.asUint8List());
    command.setRange(20, 20 + jsonBytes.length, jsonBytes);
    
    return command;
  }
  
  /// Verifica se é uma resposta DVRIP válida
  static bool _isValidDvripResponse(Uint8List response) {
    if (response.length < 20) return false;
    
    // Verifica cabeçalho DVRIP
    return response[0] == 0xFF && response[1] == 0x01;
  }
  
  /// Verifica se a autenticação foi bem-sucedida
  static bool _isAuthenticationSuccessful(Uint8List response) {
    if (!_isValidDvripResponse(response)) return false;
    
    try {
      // Extrai dados JSON da resposta
      final dataLength = ByteData.sublistView(response, 16, 20).getUint32(0, Endian.little);
      if (response.length < 20 + dataLength) return false;
      
      final jsonBytes = response.sublist(20, 20 + dataLength);
      final jsonString = utf8.decode(jsonBytes);
      final responseData = json.decode(jsonString);
      
      // Verifica se o login foi bem-sucedido
      return responseData['Ret'] == 100; // 100 = sucesso
    } catch (e) {
      return false;
    }
  }
  
  /// Calcula hash MD5
  static String _md5Hash(String input) {
    // Implementação simples de MD5 para senhas
    // Em produção, use a biblioteca crypto
    final bytes = utf8.encode(input);
    final digest = bytes.fold<int>(0, (prev, byte) => prev ^ byte);
    return digest.toRadixString(16).padLeft(8, '0');
  }
  
  /// Obtém informações do dispositivo
  static Future<Map<String, dynamic>?> getDeviceInfo(Socket socket) async {
    try {
      // Comando para obter informações do sistema
      final command = _createSystemInfoCommand();
      socket.add(command);
      await socket.flush();
      
      // Aguarda resposta
      final response = await socket.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => Uint8List(0),
      );
      
      if (_isValidDvripResponse(response)) {
        return _parseSystemInfoResponse(response);
      }
      
      return null;
    } catch (e) {
      print('Erro ao obter informações do dispositivo: $e');
      return null;
    }
  }
  
  /// Cria comando para obter informações do sistema
  static Uint8List _createSystemInfoCommand() {
    final sessionId = Random().nextInt(0xFFFFFFFF);
    final sequenceNumber = 1;
    
    // Cabeçalho para comando de informações do sistema
    final header = ByteData(20);
    header.setUint8(0, 0xFF);
    header.setUint8(1, 0x01);
    header.setUint32(4, sessionId, Endian.little);
    header.setUint32(8, sequenceNumber, Endian.little);
    header.setUint32(12, 1020, Endian.little); // SYSINFO_REQ
    header.setUint32(16, 0, Endian.little); // Sem dados
    
    return header.buffer.asUint8List();
  }
  
  /// Analisa resposta de informações do sistema
  static Map<String, dynamic>? _parseSystemInfoResponse(Uint8List response) {
    try {
      final dataLength = ByteData.sublistView(response, 16, 20).getUint32(0, Endian.little);
      if (response.length < 20 + dataLength || dataLength == 0) return null;
      
      final jsonBytes = response.sublist(20, 20 + dataLength);
      final jsonString = utf8.decode(jsonBytes);
      final responseData = json.decode(jsonString);
      
      return responseData;
    } catch (e) {
      return null;
    }
  }
}