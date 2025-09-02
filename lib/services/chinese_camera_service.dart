import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/camera_models.dart';

/// Serviço para protocolos específicos de câmeras chinesas
class ChineseCameraService {
  static const int _timeout = 10;
  
  /// Descobrir gravações usando protocolos de câmeras chinesas
  Future<List<RecordingInfo>> discoverRecordings(String host, String user, String pass, {
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      print('CHINESE CAMERA DEBUG: Starting discovery for $host');
      final recordings = <RecordingInfo>[];
      
      // Método 1: Protocolo XMEye/ICSEE
      final xmeyeRecordings = await _discoverXMEyeRecordings(host, user, pass, startTime, endTime);
      recordings.addAll(xmeyeRecordings);
      
      // Método 2: Protocolo NetSDK (Dahua)
      final netsdkRecordings = await _discoverNetSDKRecordings(host, user, pass, startTime, endTime);
      recordings.addAll(netsdkRecordings);
      
      // Método 3: Protocolo Hikvision ISAPI
      final hikvisionRecordings = await _discoverHikvisionRecordings(host, user, pass, startTime, endTime);
      recordings.addAll(hikvisionRecordings);
      
      // Método 4: Protocolo Xiongmai
      final xiongmaiRecordings = await _discoverXiongmaiRecordings(host, user, pass, startTime, endTime);
      recordings.addAll(xiongmaiRecordings);
      
      print('CHINESE CAMERA DEBUG: Total recordings found: ${recordings.length}');
      return recordings;
    } catch (e) {
      print('CHINESE CAMERA DEBUG ERROR: Discovery failed: $e');
      return [];
    }
  }
  
  /// Descobrir gravações usando protocolo XMEye/ICSEE
  Future<List<RecordingInfo>> _discoverXMEyeRecordings(String host, String user, String pass, DateTime startTime, DateTime endTime) async {
    try {
      print('XMEYE DEBUG: Trying XMEye protocol for $host');
      final recordings = <RecordingInfo>[];
      
      // URLs comuns do protocolo XMEye
      final xmeyeEndpoints = [
        '/cgi-bin/recordManager.cgi?action=find&name=*',
        '/cgi-bin/mediaFileFind.cgi?action=factory.create',
        '/cgi-bin/RPC_Loadfile',
        '/web/cgi-bin/hi3510/param.cgi?cmd=getserverinfo',
        '/cgi-bin/hi3510/param.cgi?cmd=getrecord',
      ];
      
      for (final endpoint in xmeyeEndpoints) {
        try {
          final response = await http.get(
            Uri.parse('http://$host$endpoint'),
            headers: {
              'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
              'User-Agent': 'XMEye Client/1.0',
            },
          ).timeout(Duration(seconds: _timeout));
          
          if (response.statusCode == 200) {
            final endpointRecordings = _parseXMEyeResponse(response.body, startTime, endTime);
            recordings.addAll(endpointRecordings);
          }
        } catch (e) {
          print('XMEYE DEBUG: Endpoint $endpoint failed: $e');
          continue;
        }
      }
      
      return recordings;
    } catch (e) {
      print('XMEYE DEBUG ERROR: XMEye discovery failed: $e');
      return [];
    }
  }
  
  /// Descobrir gravações usando protocolo NetSDK (Dahua)
  Future<List<RecordingInfo>> _discoverNetSDKRecordings(String host, String user, String pass, DateTime startTime, DateTime endTime) async {
    try {
      print('NETSDK DEBUG: Trying NetSDK protocol for $host');
      final recordings = <RecordingInfo>[];
      
      // Endpoints NetSDK comuns
      final netsdkEndpoints = [
        '/cgi-bin/recordManager.cgi?action=find&name=*&startTime=${_formatDateTime(startTime)}&endTime=${_formatDateTime(endTime)}',
        '/cgi-bin/mediaFileFind.cgi?action=factory.create&name=MediaFileFind',
        '/cgi-bin/RPC_Loadfile',
        '/cgi-bin/configManager.cgi?action=getConfig&name=RecordMode',
        '/cgi-bin/devVideoInput.cgi?action=getCaps',
      ];
      
      for (final endpoint in netsdkEndpoints) {
        try {
          final response = await http.get(
            Uri.parse('http://$host$endpoint'),
            headers: {
              'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
              'User-Agent': 'NetSDK Client/1.0',
            },
          ).timeout(Duration(seconds: _timeout));
          
          if (response.statusCode == 200) {
            final endpointRecordings = _parseNetSDKResponse(response.body, startTime, endTime);
            recordings.addAll(endpointRecordings);
          }
        } catch (e) {
          print('NETSDK DEBUG: Endpoint $endpoint failed: $e');
          continue;
        }
      }
      
      return recordings;
    } catch (e) {
      print('NETSDK DEBUG ERROR: NetSDK discovery failed: $e');
      return [];
    }
  }
  
  /// Descobrir gravações usando protocolo Hikvision ISAPI
  Future<List<RecordingInfo>> _discoverHikvisionRecordings(String host, String user, String pass, DateTime startTime, DateTime endTime) async {
    try {
      print('HIKVISION DEBUG: Trying Hikvision ISAPI for $host');
      final recordings = <RecordingInfo>[];
      
      // Endpoints ISAPI da Hikvision
      final isapiEndpoints = [
        '/ISAPI/ContentMgmt/search',
        '/ISAPI/ContentMgmt/record/tracks/101',
        '/ISAPI/System/deviceInfo',
        '/ISAPI/Streaming/channels',
        '/ISAPI/Event/notification/alertStream',
      ];
      
      for (final endpoint in isapiEndpoints) {
        try {
          final response = await http.get(
            Uri.parse('http://$host$endpoint'),
            headers: {
              'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
              'User-Agent': 'Hikvision Client/1.0',
            },
          ).timeout(Duration(seconds: _timeout));
          
          if (response.statusCode == 200) {
            final endpointRecordings = _parseHikvisionResponse(response.body, startTime, endTime);
            recordings.addAll(endpointRecordings);
          }
        } catch (e) {
          print('HIKVISION DEBUG: Endpoint $endpoint failed: $e');
          continue;
        }
      }
      
      return recordings;
    } catch (e) {
      print('HIKVISION DEBUG ERROR: Hikvision discovery failed: $e');
      return [];
    }
  }
  
  /// Descobrir gravações usando protocolo Xiongmai
  Future<List<RecordingInfo>> _discoverXiongmaiRecordings(String host, String user, String pass, DateTime startTime, DateTime endTime) async {
    try {
      print('XIONGMAI DEBUG: Trying Xiongmai protocol for $host');
      final recordings = <RecordingInfo>[];
      
      // Endpoints Xiongmai comuns
      final xiongmaiEndpoints = [
        '/cgi-bin/hi3510/param.cgi?cmd=getrecord',
        '/cgi-bin/hi3510/param.cgi?cmd=getserverinfo',
        '/web/cgi-bin/hi3510/param.cgi?cmd=getrecord',
        '/cgi-bin/recordManager.cgi?action=find',
        '/RPC2_Login',
      ];
      
      for (final endpoint in xiongmaiEndpoints) {
        try {
          final response = await http.get(
            Uri.parse('http://$host$endpoint'),
            headers: {
              'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
              'User-Agent': 'Xiongmai Client/1.0',
            },
          ).timeout(Duration(seconds: _timeout));
          
          if (response.statusCode == 200) {
            final endpointRecordings = _parseXiongmaiResponse(response.body, startTime, endTime);
            recordings.addAll(endpointRecordings);
          }
        } catch (e) {
          print('XIONGMAI DEBUG: Endpoint $endpoint failed: $e');
          continue;
        }
      }
      
      return recordings;
    } catch (e) {
      print('XIONGMAI DEBUG ERROR: Xiongmai discovery failed: $e');
      return [];
    }
  }
  
  /// Parse resposta XMEye
  List<RecordingInfo> _parseXMEyeResponse(String response, DateTime startTime, DateTime endTime) {
    try {
      final recordings = <RecordingInfo>[];
      
      // Padrões comuns de arquivos XMEye
      final patterns = [
        RegExp(r'(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.h264', caseSensitive: false),
        RegExp(r'(\d{8}_\d{6})\.mp4', caseSensitive: false),
        RegExp(r'rec_(\d{14})\.avi', caseSensitive: false),
      ];
      
      for (final pattern in patterns) {
        final matches = pattern.allMatches(response);
        for (final match in matches) {
          final filename = match.group(0) ?? '';
          final timestamp = match.group(1) ?? '';
          
          final recording = _createRecordingFromMatch(filename, timestamp, 'XMEye');
          if (recording != null && _isInTimeRange(recording.startTime, startTime, endTime)) {
            recordings.add(recording);
          }
        }
      }
      
      return recordings;
    } catch (e) {
      print('XMEYE DEBUG ERROR: Failed to parse XMEye response: $e');
      return [];
    }
  }
  
  /// Parse resposta NetSDK
  List<RecordingInfo> _parseNetSDKResponse(String response, DateTime startTime, DateTime endTime) {
    try {
      final recordings = <RecordingInfo>[];
      
      // Padrões comuns de arquivos NetSDK/Dahua
      final patterns = [
        RegExp(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.dav', caseSensitive: false),
        RegExp(r'(\d{8}_\d{6})\.h264', caseSensitive: false),
        RegExp(r'ch\d+_(\d{14})\.mp4', caseSensitive: false),
      ];
      
      for (final pattern in patterns) {
        final matches = pattern.allMatches(response);
        for (final match in matches) {
          final filename = match.group(0) ?? '';
          final timestamp = match.group(1) ?? '';
          
          final recording = _createRecordingFromMatch(filename, timestamp, 'NetSDK');
          if (recording != null && _isInTimeRange(recording.startTime, startTime, endTime)) {
            recordings.add(recording);
          }
        }
      }
      
      return recordings;
    } catch (e) {
      print('NETSDK DEBUG ERROR: Failed to parse NetSDK response: $e');
      return [];
    }
  }
  
  /// Parse resposta Hikvision
  List<RecordingInfo> _parseHikvisionResponse(String response, DateTime startTime, DateTime endTime) {
    try {
      final recordings = <RecordingInfo>[];
      
      // Padrões comuns de arquivos Hikvision
      final patterns = [
        RegExp(r'ch\d+_(\d{8}_\d{6})\.mp4', caseSensitive: false),
        RegExp(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.h264', caseSensitive: false),
        RegExp(r'rec_(\d{14})\.avi', caseSensitive: false),
      ];
      
      for (final pattern in patterns) {
        final matches = pattern.allMatches(response);
        for (final match in matches) {
          final filename = match.group(0) ?? '';
          final timestamp = match.group(1) ?? '';
          
          final recording = _createRecordingFromMatch(filename, timestamp, 'Hikvision');
          if (recording != null && _isInTimeRange(recording.startTime, startTime, endTime)) {
            recordings.add(recording);
          }
        }
      }
      
      return recordings;
    } catch (e) {
      print('HIKVISION DEBUG ERROR: Failed to parse Hikvision response: $e');
      return [];
    }
  }
  
  /// Parse resposta Xiongmai
  List<RecordingInfo> _parseXiongmaiResponse(String response, DateTime startTime, DateTime endTime) {
    try {
      final recordings = <RecordingInfo>[];
      
      // Padrões comuns de arquivos Xiongmai
      final patterns = [
        RegExp(r'(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.h264', caseSensitive: false),
        RegExp(r'(\d{8}_\d{6})\.avi', caseSensitive: false),
        RegExp(r'rec_(\d{14})\.mp4', caseSensitive: false),
      ];
      
      for (final pattern in patterns) {
        final matches = pattern.allMatches(response);
        for (final match in matches) {
          final filename = match.group(0) ?? '';
          final timestamp = match.group(1) ?? '';
          
          final recording = _createRecordingFromMatch(filename, timestamp, 'Xiongmai');
          if (recording != null && _isInTimeRange(recording.startTime, startTime, endTime)) {
            recordings.add(recording);
          }
        }
      }
      
      return recordings;
    } catch (e) {
      print('XIONGMAI DEBUG ERROR: Failed to parse Xiongmai response: $e');
      return [];
    }
  }
  
  /// Criar RecordingInfo a partir de match
  RecordingInfo? _createRecordingFromMatch(String filename, String timestamp, String type) {
    try {
      DateTime? recordingTime;
      
      // Tentar extrair timestamp do nome do arquivo
      if (timestamp.contains('-') && timestamp.contains('_')) {
        // Formato: 2024-01-15_14-30-45
        final parts = timestamp.split('_');
        if (parts.length == 2) {
          final datePart = parts[0];
          final timePart = parts[1].replaceAll('-', ':');
          recordingTime = DateTime.tryParse('${datePart}T$timePart');
        }
      } else if (timestamp.contains(' ')) {
        // Formato: 2024-01-15 14:30:45
        recordingTime = DateTime.tryParse(timestamp);
      } else if (timestamp.contains('T')) {
        // Formato ISO: 2024-01-15T14:30:45
        recordingTime = DateTime.tryParse(timestamp);
      } else if (timestamp.length == 8) {
        // Formato: 20240115
        final year = int.tryParse(timestamp.substring(0, 4));
        final month = int.tryParse(timestamp.substring(4, 6));
        final day = int.tryParse(timestamp.substring(6, 8));
        if (year != null && month != null && day != null) {
          recordingTime = DateTime(year, month, day);
        }
      } else if (timestamp.length == 14) {
        // Formato: 20240115143045
        final year = int.tryParse(timestamp.substring(0, 4));
        final month = int.tryParse(timestamp.substring(4, 6));
        final day = int.tryParse(timestamp.substring(6, 8));
        final hour = int.tryParse(timestamp.substring(8, 10));
        final minute = int.tryParse(timestamp.substring(10, 12));
        final second = int.tryParse(timestamp.substring(12, 14));
        if (year != null && month != null && day != null && hour != null && minute != null && second != null) {
          recordingTime = DateTime(year, month, day, hour, minute, second);
        }
      }
      
      recordingTime ??= DateTime.now();
      
      return RecordingInfo(
        id: '${type.toLowerCase()}_${filename.hashCode}',
        filename: filename,
        startTime: recordingTime,
        endTime: recordingTime.add(Duration(minutes: 30)), // Duração estimada
        duration: Duration(minutes: 30),
        sizeBytes: 0,
        recordingType: type,
      );
    } catch (e) {
      print('CHINESE CAMERA DEBUG ERROR: Failed to create recording from match: $e');
      return null;
    }
  }
  
  /// Verificar se a gravação está no intervalo de tempo
  bool _isInTimeRange(DateTime recordingTime, DateTime startTime, DateTime endTime) {
    return recordingTime.isAfter(startTime.subtract(Duration(hours: 1))) &&
           recordingTime.isBefore(endTime.add(Duration(hours: 1)));
  }
  
  /// Formatar DateTime para string
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}