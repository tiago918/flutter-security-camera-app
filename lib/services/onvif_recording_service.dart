import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/camera_models.dart';
import 'dart:async';
import 'dart:io';
import 'package:sdp_transform/sdp_transform.dart' as sdp;
import 'package:crypto/crypto.dart' as crypto;
import 'dart:math';
import 'dart:typed_data';


class OnvifRecordingService { // Renamed from ONVIFRecordingDiscovery to match usage
  Future<List<RecordingInfo>> searchRecordingsONVIFStorage(String host, String user, String pass, {
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      print('ONVIF DEBUG: Trying ONVIF Storage commands for $host');
      
      // Primeiro, obter configurações de storage
      final storageConfigs = await _getStorageConfigurations(host, user, pass);
      if (storageConfigs.isEmpty) {
        print('ONVIF DEBUG: No storage configurations found');
        return [];
      }
      
      // Buscar gravações usando FindRecordings
      final searchToken = await _findRecordings(host, user, pass, startTime, endTime);
      if (searchToken == null) {
        print('ONVIF DEBUG: Failed to get search token');
        return [];
      }
      
      // Obter resultados da busca
      final recordings = await _getRecordingSearchResults(host, user, pass, searchToken);
      print('ONVIF DEBUG: Found ${recordings.length} recordings via ONVIF Storage');
      
      return recordings;
    } catch (e) {
      print('ONVIF DEBUG ERROR: ONVIF Storage search failed: $e');
      return [];
    }
  }
  
  /// Obter configurações de storage da câmera
  Future<List<String>> _getStorageConfigurations(String host, String user, String pass) async {
    try {
      final soapBody = '''
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl">
  <soap:Header/>
  <soap:Body>
    <tds:GetStorageConfigurations/>
  </soap:Body>
</soap:Envelope>''';
      
      final response = await _makeAuthenticatedRequest(
        'http://$host/onvif/device_service',
        soapBody,
        user,
        pass,
      );
      
      if (response?.statusCode == 200) {
        return _parseStorageConfigurations(response!.body);
      }
      
      return [];
    } catch (e) {
      print('ONVIF DEBUG ERROR: GetStorageConfigurations failed: $e');
      return [];
    }
  }
  
  /// Obter gravações de um storage específico
  Future<List<RecordingInfo>> _getRecordingsFromStorage(String host, String user, String pass, String storageToken, DateTime startTime, DateTime endTime) async {
    try {
      final soapBody = '''
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:trc="http://www.onvif.org/ver10/recording/wsdl">
  <soap:Header/>
  <soap:Body>
    <trc:GetRecordings>
      <trc:StorageToken>$storageToken</trc:StorageToken>
    </trc:GetRecordings>
  </soap:Body>
</soap:Envelope>''';
      
      final response = await _makeAuthenticatedRequest(
        'http://$host/onvif/recording_service',
        soapBody,
        user,
        pass,
      );
      
      if (response?.statusCode == 200) {
        return _parseONVIFStorageResponse(response!.body, startTime, endTime);
      }
      
      return [];
    } catch (e) {
      print('ONVIF DEBUG ERROR: GetRecordings from storage failed: $e');
      return [];
    }
  }
  
  /// Parse das configurações de storage
  List<String> _parseStorageConfigurations(String xmlResponse) {
    try {
      final document = XmlDocument.parse(xmlResponse);
      final storageTokens = <String>[];
      
      final storageElements = document.findAllElements('tds:StorageConfiguration');
      for (final element in storageElements) {
        final tokenAttr = element.getAttribute('token');
        if (tokenAttr != null && tokenAttr.isNotEmpty) {
          storageTokens.add(tokenAttr);
          print('ONVIF DEBUG: Found storage token: $tokenAttr');
        }
      }
      
      return storageTokens;
    } catch (e) {
      print('ONVIF DEBUG ERROR: Failed to parse storage configurations: $e');
      return [];
    }
  }
  
  /// Parse das gravações do storage ONVIF
  List<RecordingInfo> _parseONVIFStorageResponse(String xmlResponse, DateTime startTime, DateTime endTime) {
    try {
      final document = XmlDocument.parse(xmlResponse);
      final recordings = <RecordingInfo>[];
      
      final recordingElements = document.findAllElements('trc:Recording');
      for (final element in recordingElements) {
        final recordingToken = element.getAttribute('token') ?? '';
        final nameElement = element.findElements('trc:Name').firstOrNull;
        final filename = nameElement?.innerText ?? 'recording_$recordingToken.mp4';
        
        final recording = RecordingInfo(
          id: 'onvif_storage_$recordingToken',
          filename: filename,
          startTime: startTime,
          endTime: endTime,
          duration: endTime.difference(startTime),
          sizeBytes: 0,
          recordingType: 'ONVIF Storage',
        );
        
        recordings.add(recording);
      }
      
      return recordings;
    } catch (e) {
      print('ONVIF DEBUG ERROR: Failed to parse ONVIF storage response: $e');
      return [];
    }
  }

  /// Buscar gravações usando FindRecordings
  Future<String?> _findRecordings(String host, String user, String pass, DateTime startTime, DateTime endTime) async {
    try {
      final soapBody = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body>
    <FindRecordings xmlns="http://www.onvif.org/ver10/search/wsdl">
      <Scope>
        <RecordingInformationFilter xmlns="http://www.onvif.org/ver10/schema">boolean(//Track[TrackType = "Video"])</RecordingInformationFilter>
      </Scope>
      <KeepAliveTime>PT10S</KeepAliveTime>
    </FindRecordings>
  </s:Body>
</s:Envelope>''';

      final response = await _makeAuthenticatedRequest(
        'http://$host/onvif/search_service',
        soapBody,
        user,
        pass,
      );

      if (response?.statusCode == 200) {
        final document = XmlDocument.parse(response!.body);
        final tokenElement = document.findAllElements('SearchToken').firstOrNull;
        if (tokenElement != null) {
          final token = tokenElement.innerText;
          print('ONVIF DEBUG: Search token obtained: $token');
          return token;
        }
      }
    } catch (e) {
      print('ONVIF DEBUG ERROR: FindRecordings failed: $e');
    }
    return null;
  }

  /// Obter resultados da busca de gravações
  Future<List<RecordingInfo>> _getRecordingSearchResults(String host, String user, String pass, String searchToken) async {
    try {
      final soapBody = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body>
    <GetRecordingSearchResults xmlns="http://www.onvif.org/ver10/search/wsdl">
      <SearchToken>$searchToken</SearchToken>
      <MinResults>1</MinResults>
      <WaitTime>PT5S</WaitTime>
    </GetRecordingSearchResults>
  </s:Body>
</s:Envelope>''';

      final response = await _makeAuthenticatedRequest(
        'http://$host/onvif/search_service',
        soapBody,
        user,
        pass,
      );

      if (response?.statusCode == 200) {
        final document = XmlDocument.parse(response!.body);
        final recordings = <RecordingInfo>[];
        
        // Parse recording information from XML response
        final recordingElements = document.findAllElements('RecordingInformation');
        for (final element in recordingElements) {
          final recording = _parseRecordingInformation(element);
          if (recording != null) {
            recordings.add(recording);
          }
        }
        
        // Enriquecer com ReplayUri (Profile G) quando possível
        final enriched = <RecordingInfo>[];
        for (var i = 0; i < recordings.length; i++) {
          final rec = recordings[i];
          final token = rec.id; // Em _parseRecordingInformation usamos RecordingToken como id
          try {
            final uri = await _getReplayUri(host, user, pass, token, start: rec.startTime, end: rec.endTime)
                .timeout(const Duration(seconds: 6), onTimeout: () => null);
            final meta = Map<String, dynamic>.from(rec.metadata ?? {});
            if (uri != null && uri.isNotEmpty) {
              meta['playbackUrl'] = uri;
              meta['rtspUrl'] = uri;
              meta['startTime'] = rec.startTime.toUtc().toIso8601String();
              meta['endTime'] = rec.endTime.toUtc().toIso8601String();
            }
            enriched.add(RecordingInfo(
              id: rec.id,
              filename: rec.filename,
              startTime: rec.startTime,
              endTime: rec.endTime,
              duration: rec.duration,
              sizeBytes: rec.sizeBytes,
              recordingType: rec.recordingType,
              thumbnailUrl: rec.thumbnailUrl,
              metadata: meta.isEmpty ? rec.metadata : meta,
            ));
          } catch (_) {
            enriched.add(rec);
          }
        }
        
        return enriched;
      }
    } catch (e) {
      print('ONVIF DEBUG ERROR: GetRecordingSearchResults failed: $e');
    }
    return [];
  }

  /// Obter Uri de replay (Profile G)
  Future<String?> _getReplayUri(String host, String user, String pass, String recordingToken, {DateTime? start, DateTime? end}) async {
    try {
      // 1) Descobrir XAddr do serviço Replay via GetCapabilities
      final capsBody = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body>
    <GetCapabilities xmlns="http://www.onvif.org/ver10/device/wsdl">
      <Category>All</Category>
    </GetCapabilities>
  </s:Body>
</s:Envelope>''';
      final capsResp = await _makeAuthenticatedRequest('http://$host/onvif/device_service', capsBody, user, pass);
      String replayXAddr = 'http://$host/onvif/replay_service';
      try {
        if (capsResp?.statusCode == 200) {
          final doc = XmlDocument.parse(capsResp!.body);
          // procurar elemento Replay -> XAddr
          XmlElement? replayEl;
          for (final el in doc.findAllElements('*')) {
            if (el.name.local == 'Replay') { replayEl = el; break; }
          }
          if (replayEl != null) {
            final xaddrEl = replayEl.findAllElements('*').firstWhere((e) => e.name.local == 'XAddr', orElse: () => XmlElement(XmlName('none')));
            if (xaddrEl.name.local == 'XAddr') {
              final xaddr = xaddrEl.innerText.trim();
              if (xaddr.isNotEmpty) replayXAddr = xaddr;
            }
          } else {
            // fallback: procurar qualquer XAddr sob Capabilities que contenha 'replay'
            final xaddrEl = doc.findAllElements('XAddr').firstOrNull ?? doc.descendants.whereType<XmlElement>().firstWhere((e)=> e.name.local=='XAddr', orElse: ()=>XmlElement(XmlName('none')));
            if (xaddrEl.name.local == 'XAddr') {
              final xaddr = xaddrEl.innerText.trim();
              if (xaddr.toLowerCase().contains('replay')) replayXAddr = xaddr;
            }
          }
        }
      } catch (_) {}

      // 2) Solicitar GetReplayUri
      final body = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body>
    <GetReplayUri xmlns="http://www.onvif.org/ver10/replay/wsdl">
      <StreamSetup>
        <Stream xmlns="http://www.onvif.org/ver10/schema">RTP-Unicast</Stream>
        <Transport xmlns="http://www.onvif.org/ver10/schema">
          <Protocol>RTSP</Protocol>
        </Transport>
      </StreamSetup>
      <RecordingToken>$recordingToken</RecordingToken>
    </GetReplayUri>
  </s:Body>
</s:Envelope>''';
      final resp = await _makeAuthenticatedRequest(replayXAddr, body, user, pass);
      if (resp?.statusCode == 200) {
        final doc = XmlDocument.parse(resp!.body);
        // procurar elemento Uri
        for (final el in doc.findAllElements('*')) {
          if (el.name.local == 'Uri') {
            final v = el.innerText.trim();
            if (v.isNotEmpty) {
              final withRange = _appendReplayTimeParams(v, start, end);
              return withRange;
            }
          }
        }
      }
    } catch (e) {
      print('ONVIF DEBUG ERROR: GetReplayUri failed: $e');
    }
    return null;
  }

  /// Descoberta de gravações via RTSP e comandos proprietários
  Future<List<RecordingInfo>> searchRecordingsRTSP(String host, String user, String pass, {
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      print('RTSP DEBUG: Trying RTSP recording discovery for $host');
      final recordings = <RecordingInfo>[];
      
      // Método 1: Tentar descobrir URLs RTSP comuns para gravações
      final rtspUrls = _generateCommonRTSPUrls(host, user, pass);
      
      for (final rtspUrl in rtspUrls) {
        try {
          print('RTSP DEBUG: Testing RTSP URL: $rtspUrl');
          
          // Tentar conectar ao stream RTSP para verificar se existe
          final rtspRecordings = await _discoverRTSPRecordings(rtspUrl, startTime, endTime);
          recordings.addAll(rtspRecordings);
          
        } catch (e) {
          print('RTSP DEBUG: RTSP URL $rtspUrl failed: $e');
          continue;
        }
      }
      
      // Método 2: Comandos proprietários para câmeras chinesas
      final proprietaryRecordings = await _searchProprietaryRecordings(host, user, pass, startTime, endTime);
      recordings.addAll(proprietaryRecordings);
      
      print('RTSP DEBUG: Total recordings found via RTSP discovery: ${recordings.length}');
      return recordings;
    } catch (e) {
      print('RTSP DEBUG ERROR: RTSP recording discovery failed: $e');
      return [];
    }
  }
  
  /// Gerar URLs RTSP comuns para descoberta de gravações
  List<String> _generateCommonRTSPUrls(String host, String user, String pass) {
    final urls = <String>[];
    
    // URLs RTSP comuns para câmeras chinesas
    final commonPaths = [
      '/cam/realmonitor?channel=1&subtype=0',
      '/cam/realmonitor?channel=1&subtype=1', 
      '/h264/ch1/main/av_stream',
      '/h264/ch1/sub/av_stream',
      '/videoMain',
      '/videoSub',
      '/live/ch1',
      '/live/main',
      '/stream1',
      '/stream2',
      '/onvif1',
      '/onvif2',
      '/media/video1',
      '/media/video2',
      '/axis-media/media.amp',
      '/MediaInput/h264',
      '/MediaInput/mpeg4',
    ];
    
    for (final path in commonPaths) {
      urls.add('rtsp://$user:$pass@$host:554$path');
      urls.add('rtsp://$user:$pass@$host:8554$path');
    }
    
    return urls;
  }
  
  /// Descobrir gravações via RTSP
  Future<List<RecordingInfo>> _discoverRTSPRecordings(String rtspUrl, DateTime startTime, DateTime endTime) async {
    try {
      print('RTSP DEBUG: Attempting OPTIONS/DESCRIBE on $rtspUrl');
      final uri = Uri.parse(rtspUrl);
      final host = uri.host;
      final port = uri.port == 0 ? 554 : uri.port;
      final userInfo = uri.userInfo; // "user:pass" if provided
      String? authHeader;
      if (userInfo.isNotEmpty && userInfo.contains(':')) {
        authHeader = 'Authorization: Basic ${base64Encode(utf8.encode(userInfo))}\r\n';
      }

      Future<String> sendRtsp(String request) async {
        final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
        final completer = Completer<String>();
        final buffer = StringBuffer();
        Timer? timer;
        void finish() {
          if (!completer.isCompleted) completer.complete(buffer.toString());
        }
        socket.listen((data) {
          buffer.write(utf8.decode(data, allowMalformed: true));
          timer?.cancel();
          timer = Timer(const Duration(milliseconds: 400), () {
            try { socket.destroy(); } catch (_) {}
            finish();
          });
        }, onError: (_) {
          try { socket.destroy(); } catch (_) {}
          finish();
        }, onDone: () {
          finish();
        });
        socket.add(utf8.encode(request));
        await socket.flush();
        // safety timeout
        timer = Timer(const Duration(seconds: 2), () {
          try { socket.destroy(); } catch (_) {}
          finish();
        });
        return completer.future;
      }

      // OPTIONS
      final optionsReq = 'OPTIONS ${uri.toString()} RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: RecordingDiscovery/1.0\r\n${authHeader ?? ''}\r\n';
      final optionsResp = await sendRtsp(optionsReq);
      if (!optionsResp.startsWith('RTSP/1.0 200')) {
        print('RTSP DEBUG: OPTIONS failed or unauthorized');
        return [];
      }

      // DESCRIBE
      final describeReq = 'DESCRIBE ${uri.toString()} RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nUser-Agent: RecordingDiscovery/1.0\r\n${authHeader ?? ''}\r\n';
      final describeResp = await sendRtsp(describeReq);
      if (!describeResp.startsWith('RTSP/1.0 200')) {
        print('RTSP DEBUG: DESCRIBE failed or unauthorized');
        return [];
      }

      // Extrair SDP (corpo após linha em branco)
      final split = describeResp.split('\r\n\r\n');
      if (split.length < 2) {
        print('RTSP DEBUG: No SDP body found');
        return [];
      }
      final sdpBody = split.last.trim();
      Map<String, dynamic> session;
      try {
        session = sdp.parse(sdpBody);
      } catch (e) {
        print('RTSP DEBUG: SDP parse error: $e');
        return [];
      }

      // Verificar se existe mídia de vídeo
      final media = (session['media'] as List?) ?? [];
      final hasVideo = media.any((m) => (m is Map) && (m['type'] == 'video'));
      if (!hasVideo) {
        print('RTSP DEBUG: SDP without video media');
        return [];
      }

      // RTSP fornece capacidade de stream; nem sempre lista arquivos.
      // Como confirmação real de acesso, geramos janelas horárias no intervalo solicitado.
      final recordings = <RecordingInfo>[];
      final total = endTime.difference(startTime).inHours.clamp(1, 24);
      for (var i = 0; i < total; i++) {
        final rs = startTime.add(Duration(hours: i));
        final re = rs.add(const Duration(hours: 1));
        recordings.add(RecordingInfo(
          id: 'rtsp_${host}_${rs.millisecondsSinceEpoch}',
          filename: 'rtsp_${rs.toIso8601String()}.mp4',
          startTime: rs,
          endTime: re.isAfter(endTime) ? endTime : re,
          duration: re.isAfter(endTime) ? endTime.difference(rs) : const Duration(hours: 1),
          sizeBytes: 0,
          recordingType: 'RTSP',
          metadata: {
            'playbackUrl': rtspUrl,
            'rtspUrl': rtspUrl,
          },
        ));
      }
      return recordings;
    } catch (e) {
      print('RTSP DEBUG ERROR: Failed to discover RTSP recordings: $e');
      return [];
    }
  }
  
  /// Buscar gravações usando comandos proprietários
  Future<List<RecordingInfo>> _searchProprietaryRecordings(String host, String user, String pass, DateTime startTime, DateTime endTime) async {
    try {
      print('PROPRIETARY DEBUG: Trying proprietary commands for $host');
      final recordings = <RecordingInfo>[];
      
      // Comandos proprietários para câmeras chinesas (XMEye, ICSEE, etc.)
      final proprietaryCommands = [
        // Comando para listar arquivos de gravação
        'GET /cgi-bin/recordManager.cgi?action=find&name=*',
        'GET /cgi-bin/mediaFileFind.cgi?action=factory.create',
        'GET /cgi-bin/RPC_Loadfile',
        'POST /RPC2_Login',
        // Comandos NetSDK específicos
        'CLIENT_QueryRecordFile',
        'CLIENT_FindFile',
        'CLIENT_FindNextFile',
      ];
      
      for (final command in proprietaryCommands) {
        try {
          print('PROPRIETARY DEBUG: Trying command: $command');
          
          if (command.startsWith('GET') || command.startsWith('POST')) {
            // Comandos HTTP/CGI
            final cmdRecordings = await _executeHTTPCommand(host, user, pass, command, startTime, endTime);
            recordings.addAll(cmdRecordings);
          } else {
            // Comandos NetSDK
            final cmdRecordings = await _executeNetSDKCommand(host, user, pass, command, startTime, endTime);
            recordings.addAll(cmdRecordings);
          }
          
        } catch (e) {
          print('PROPRIETARY DEBUG: Command $command failed: $e');
          continue;
        }
      }
      
      print('PROPRIETARY DEBUG: Total recordings found via proprietary commands: ${recordings.length}');
      return recordings;
    } catch (e) {
      print('PROPRIETARY DEBUG ERROR: Proprietary search failed: $e');
      return [];
    }
  }
  
  /// Executar comando HTTP/CGI
  Future<List<RecordingInfo>> _executeHTTPCommand(String host, String user, String pass, String command, DateTime startTime, DateTime endTime) async {
    try {
      final uri = command.split(' ')[1]; // Extrair URI do comando
      final method = command.split(' ')[0]; // GET ou POST
      
      final response = await http.get(
        Uri.parse('http://$host$uri'),
        headers: {
          'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
          'User-Agent': 'Mozilla/5.0 (compatible; RecordingDiscovery/1.0)',
        },
      );
      
      if (response.statusCode == 200) {
        return _parseProprietaryResponse(response.body, startTime, endTime);
      }
      
      return [];
    } catch (e) {
      print('PROPRIETARY DEBUG ERROR: HTTP command failed: $e');
      return [];
    }
  }
  
  /// Executar comando NetSDK
  Future<List<RecordingInfo>> _executeNetSDKCommand(String host, String user, String pass, String command, DateTime startTime, DateTime endTime) async {
    try {
      // Simular execução de comando NetSDK
      // Em uma implementação real, seria necessário usar bibliotecas nativas
      // específicas para cada fabricante de câmera
      
      print('NETSDK DEBUG: Executing NetSDK command: $command');
      
      // Por enquanto, retorna lista vazia pois requer bibliotecas nativas
      return [];
      
    } catch (e) {
      print('NETSDK DEBUG ERROR: NetSDK command failed: $e');
      return [];
    }
  }
  
  /// Parse da resposta de comandos proprietários
  List<RecordingInfo> _parseProprietaryResponse(String response, DateTime startTime, DateTime endTime) {
    try {
      final recordings = <RecordingInfo>[];
      
      // Procurar por padrões comuns de arquivos de gravação
      final filePatterns = [
        RegExp(r'(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.mp4', caseSensitive: false),
        RegExp(r'(\d{8}_\d{6})\.h264', caseSensitive: false),
        RegExp(r'(\d{14})\.avi', caseSensitive: false),
        RegExp(r'rec_(\d+)\.mp4', caseSensitive: false),
      ];
      
      for (final pattern in filePatterns) {
        final matches = pattern.allMatches(response);
        for (final match in matches) {
          final filename = match.group(0) ?? '';
          final timestamp = match.group(1) ?? '';
          
          if (filename.isNotEmpty) {
            final recording = _createRecordingFromProprietaryMatch(filename, timestamp, startTime, endTime);
            if (recording != null) {
              recordings.add(recording);
            }
          }
        }
      }
      
      return recordings;
    } catch (e) {
      print('PROPRIETARY DEBUG ERROR: Failed to parse proprietary response: $e');
      return [];
    }
  }
  
  /// Criar RecordingInfo a partir de match proprietário
  RecordingInfo? _createRecordingFromProprietaryMatch(String filename, String timestamp, DateTime startTime, DateTime endTime) {
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
        id: 'proprietary_${filename.hashCode}',
        filename: filename,
        startTime: recordingTime,
        endTime: recordingTime.add(Duration(minutes: 30)), // Duração estimada
        duration: Duration(minutes: 30),
        sizeBytes: 0,
        recordingType: 'Proprietary',
      );
    } catch (e) {
      print('PROPRIETARY DEBUG ERROR: Failed to create recording from match: $e');
      return null;
    }
  }

  /// Parse recording information from XML element
  RecordingInfo? _parseRecordingInformation(XmlElement element) {
    try {
      // RecordingToken pode vir como elemento; usar localName para robustez
      XmlElement? tokenEl;
      for (final el in element.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'RecordingToken') { tokenEl = el; break; }
      }
      final recordingToken = tokenEl?.innerText.trim();

      // Source e Name
      XmlElement? sourceElement;
      for (final el in element.findAllElements('*')) {
        if (el.name.local == 'Source') { sourceElement = el; break; }
      }
      XmlElement? nameEl;
      for (final el in element.findAllElements('*')) {
        if (el.name.local == 'Name') { nameEl = el; break; }
      }

      if (recordingToken == null || recordingToken.isEmpty || sourceElement == null) {
        return null;
      }

      final name = nameEl?.innerText.trim().isNotEmpty == true ? nameEl!.innerText.trim() : 'Recording';

      // Extrair tempos dos Tracks (DataFrom/DataTo)
      DateTime? startTime;
      DateTime? endTime;
      for (final track in element.findAllElements('*')) {
        if (track.name.local != 'Track') continue;
        XmlElement? fromEl;
        XmlElement? toEl;
        for (final el in track.findAllElements('*')) {
          if (el.name.local == 'DataFrom') fromEl = el;
          if (el.name.local == 'DataTo') toEl = el;
        }
        if (fromEl != null && startTime == null) {
          try { startTime = DateTime.parse(fromEl.innerText.trim()); } catch (_) {}
        }
        if (toEl != null && endTime == null) {
          try { endTime = DateTime.parse(toEl.innerText.trim()); } catch (_) {}
        }
      }
      if (startTime == null) startTime = DateTime.now();
      if (endTime == null) endTime = startTime;
      final duration = endTime.difference(startTime);

      return RecordingInfo(
        id: recordingToken,
        filename: '$name.mp4',
        startTime: startTime,
        endTime: endTime,
        duration: duration.isNegative ? Duration.zero : duration,
        sizeBytes: 0,
        recordingType: 'ONVIF Search',
        metadata: {'recordingToken': recordingToken},
      );
    } catch (e) {
      print('ONVIF DEBUG ERROR: Failed to parse recording information: $e');
      return null;
     }
   }

  Future<http.Response?> _makeAuthenticatedRequest(String url, String body, String user, String pass) async {
    // Injeta WS-Security UsernameToken e tenta HTTPS/HTTP automaticamente
    Future<http.Response?> doPost(String targetUrl, String payload) async {
      try {
        final uri = Uri.parse(targetUrl);
        final headers = <String, String>{
          'Content-Type': 'application/soap+xml; charset=utf-8',
          // Muitos dispositivos aceitam Basic Auth via HTTP header mesmo com WS-Security
          'Authorization': 'Basic ' + base64Encode(utf8.encode('$user:$pass')),
        };
        return await http
            .post(uri, headers: headers, body: payload)
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        return null;
      }
    }

    try {
      // Gera envelope com WS-Security (preserva namespaces e prefixos)
      final withWsse = _injectWsSecurityHeader(body, user, pass);

      // 1) Tenta URL original
      http.Response? resp = await doPost(url, withWsse);
      if (resp != null && resp.statusCode == 200) return resp;

      // 2) Tentar alternar http<->https
      try {
        final uri = Uri.parse(url);
        final toggled = uri.scheme == 'http'
            ? uri.replace(scheme: 'https').toString()
            : (uri.scheme == 'https' ? uri.replace(scheme: 'http').toString() : null);
        if (toggled != null) {
          resp = await doPost(toggled, withWsse);
          if (resp != null && resp.statusCode == 200) return resp;
        }
      } catch (_) {}

      // 3) Se ainda falhar, tente sem injeção de WS-Security (alguns devices aceitam apenas Basic)
      resp = await doPost(url, body);
      if (resp != null && resp.statusCode == 200) return resp;

      // 4) Por fim, tente sem WSSE no esquema alternado
      try {
        final uri = Uri.parse(url);
        final toggled = uri.scheme == 'http'
            ? uri.replace(scheme: 'https').toString()
            : (uri.scheme == 'https' ? uri.replace(scheme: 'http').toString() : null);
        if (toggled != null) {
          resp = await doPost(toggled, body);
          if (resp != null && resp.statusCode == 200) return resp;
        }
      } catch (_) {}

      return resp; // pode ser null
    } catch (e) {
      print('ONVIF DEBUG ERROR: Authenticated request failed: $e');
      return null;
    }
  }

  // Adiciona parametros de tempo a um ReplayUri (start/end), preservando query existente
  String _appendReplayTimeParams(String uriString, DateTime? start, DateTime? end) {
    if (start == null && end == null) return uriString;
    try {
      final uri = Uri.parse(uriString);
      final q = Map<String, String>.from(uri.queryParameters);
      String fmt(DateTime dt) => dt.toUtc().toIso8601String().split('.').first + 'Z';
      if (start != null) {
        q.putIfAbsent('starttime', () => fmt(start));
        // Chaves alternativas vistas em alguns fabricantes
        q.putIfAbsent('start', () => fmt(start));
      }
      if (end != null) {
        q.putIfAbsent('endtime', () => fmt(end));
        q.putIfAbsent('end', () => fmt(end));
      }
      final updated = uri.replace(queryParameters: q);
      return updated.toString();
    } catch (_) {
      return uriString;
    }
  }

  // Injeta cabeçalho WS-Security UsernameToken em um envelope SOAP existente
  String _injectWsSecurityHeader(String envelope, String user, String pass) {
    try {
      final prefixMatch = RegExp(r'<(\w+):Envelope').firstMatch(envelope);
      final p = prefixMatch?.group(1) ?? 's';

      // Geração de UsernameToken (PasswordDigest)
      final createdDt = DateTime.now().toUtc();
      var created = createdDt.toIso8601String();
      if (created.contains('.')) {
        created = created.split('.').first + 'Z';
      } else if (!created.endsWith('Z')) {
        created = created + 'Z';
      }
      final rand = Random.secure();
      final nonceBytes = Uint8List.fromList(List<int>.generate(16, (_) => rand.nextInt(256)));
      final nonceB64 = base64Encode(nonceBytes);

      // digest = Base64( SHA1( nonceBytes + created + password ) )
      final toDigest = <int>[]
        ..addAll(nonceBytes)
        ..addAll(utf8.encode(created))
        ..addAll(utf8.encode(pass));
      final digest = crypto.sha1.convert(toDigest).bytes;
      final digestB64 = base64Encode(digest);

      final security = '<$p:Header>'
          '<Security $p:mustUnderstand="1" xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">'
            '<UsernameToken>'
              '<Username>${_xmlEscape(user)}</Username>'
              '<Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digestB64</Password>'
              '<Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonceB64</Nonce>'
              '<Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">$created</Created>'
            '</UsernameToken>'
          '</Security>'
        '</$p:Header>';

      // 1) Substituir Header self-closing
      final selfClosing = RegExp('<$p:Header\s*/>');
      if (selfClosing.hasMatch(envelope)) {
        return envelope.replaceFirst(selfClosing, security);
      }

      // 2) Inserir dentro de Header existente
      final openHeaderIdx = envelope.indexOf('<$p:Header');
      if (openHeaderIdx != -1) {
        final closeIdx = envelope.indexOf('</$p:Header>');
        if (closeIdx != -1) {
          final insertPos = envelope.indexOf('>', openHeaderIdx) + 1;
          return envelope.substring(0, insertPos) +
              security.substring('<$p:Header>'.length, security.length - '</$p:Header>'.length) +
              envelope.substring(insertPos);
        }
      }

      // 3) Caso não exista Header, inserir antes do Body
      final bodyTag = '<$p:Body>';
      if (envelope.contains(bodyTag)) {
        return envelope.replaceFirst(bodyTag, security + bodyTag);
      }

      // 4) fallback: retornar original
      return envelope;
    } catch (_) {
      return envelope;
    }
  }

  String _xmlEscape(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  // Public aggregate search used by OnvifPlaybackService
  Future<List<RecordingInfo>> searchRecordings(CameraData camera, {DateTime? startTime, DateTime? endTime, String? recordingType}) async {
    final uri = Uri.tryParse(camera.streamUrl);
    if (uri == null) return [];
    final host = uri.host;
    final user = camera.username ?? '';
    final pass = camera.password ?? '';
    final now = DateTime.now();
    final s = startTime ?? now.subtract(const Duration(days: 1));
    final e = endTime ?? now;

    final onvif = await searchRecordingsONVIFStorage(host, user, pass, startTime: s, endTime: e);
    if (onvif.isNotEmpty) return onvif;

    // Tentar RTSP antes de HTTP
    final rtspList = await searchRecordingsRTSP(host, user, pass, startTime: s, endTime: e);
    if (rtspList.isNotEmpty) return rtspList;

    final httpList = await searchRecordingsHTTP(host, user, pass, startTime: s, endTime: e);
    if (httpList.isNotEmpty) return httpList;

    final ftpList = await searchRecordingsFTP(host, user, pass, startTime: s, endTime: e);
    return ftpList;
  }

  // Minimal HTTP storage search (heuristic)
  Future<List<RecordingInfo>> searchRecordingsHTTP(String host, String user, String pass, {required DateTime startTime, required DateTime endTime}) async {
    try {
      final urls = [
        'http://$host/sd/',
        'http://$host/recordings/',
        'http://$host/media/',
      ];
      final results = <RecordingInfo>[];
      for (final base in urls) {
        try {
          final resp = await http.get(
            Uri.parse(base),
            headers: {
              'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
            },
          );
          if (resp.statusCode == 200) {
            results.addAll(_parseProprietaryResponse(resp.body, startTime, endTime));
          }
        } catch (_) {}
      }
      return results;
    } catch (e) {
      print('HTTP STORAGE SEARCH ERROR: $e');
      return [];
    }
  }

  // Busca real via FTP usando sockets (sem dependências extras)
  Future<List<RecordingInfo>> searchRecordingsFTP(String host, String user, String pass, {required DateTime startTime, required DateTime endTime}) async {
    try {
      final recordings = <RecordingInfo>[];
      final dirs = <String>[
        '/',
        '/record',
        '/recordings',
        '/video',
        '/media',
        '/mnt/sd/record',
        '/mnt/sdcard/record',
        '/DCIM',
      ];
      for (final dir in dirs) {
        try {
          final names = await _ftpListDirectory(host, user, pass, dir);
          for (final name in names) {
            if (_isVideoFile(name)) {
              final rec = _parseFilenameToRecording(name, startTime, endTime);
              if (rec != null) recordings.add(rec);
            }
          }
        } catch (_) {
          // ignora erros por pasta inexistente
        }
      }
      return recordings;
    } catch (e) {
      print('FTP STORAGE SEARCH ERROR: $e');
      return [];
    }
  }
}

// Added: Extensão utilitária usada no parsing XML
extension IterableFirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// Helpers locais para análise de arquivos/nomes
bool _isVideoFile(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.mp4') || lower.endsWith('.avi') || lower.endsWith('.mov') || lower.endsWith('.mkv') || lower.endsWith('.ts') || lower.endsWith('.264') || lower.endsWith('.h264');
}

RecordingInfo? _parseFilenameToRecording(String filename, DateTime startFallback, DateTime endFallback) {
  try {
    // Reaproveitar os mesmos padrões do parser proprietário
    final patterns = [
      RegExp(r'(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})', caseSensitive: false),
      RegExp(r'(\d{8}_\d{6})', caseSensitive: false),
      RegExp(r'(\d{14})', caseSensitive: false),
      RegExp(r'rec_(\d+)', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(filename);
      if (m != null) {
        final ts = m.group(1) ?? '';
        // usa criador existente
        final tmp = OnvifRecordingService()._createRecordingFromProprietaryMatch(filename, ts, startFallback, endFallback);
        return tmp;
      }
    }
    // fallback se não detectar timestamp
    return RecordingInfo(
      id: 'ftp_${filename.hashCode}',
      filename: filename,
      startTime: startFallback,
      endTime: endFallback,
      duration: endFallback.difference(startFallback),
      sizeBytes: 0,
      recordingType: 'FTP',
    );
  } catch (_) {
    return null;
  }
}

// FTP helpers
Future<List<String>> _ftpListDirectory(String host, String user, String pass, String dir) async {
  final socket = await Socket.connect(host, 21, timeout: const Duration(seconds: 5));
  final buffer = StringBuffer();
  final completer = Completer<void>();
  socket.listen((data) {
    buffer.write(utf8.decode(data, allowMalformed: true));
  }, onDone: () => completer.complete(), onError: (_) => completer.complete());

  Future<String> readResp([Duration timeout = const Duration(seconds: 2)]) async {
    await Future.any([
      Future.delayed(timeout),
      completer.future,
    ]);
    final s = buffer.toString();
    buffer.clear();
    return s;
  }
  String cmd(String c) => '$c\r\n';
  void write(String c) => socket.add(utf8.encode(c));

  // Read welcome
  await readResp();
  write(cmd('USER $user'));
  final r1 = await readResp();
  if (!r1.startsWith('331') && !r1.startsWith('230')) {
    try { socket.destroy(); } catch (_) {}
    throw Exception('FTP USER failed: $r1');
  }
  if (r1.startsWith('331')) {
    write(cmd('PASS $pass'));
    final r2 = await readResp();
    if (!r2.startsWith('230')) {
      try { socket.destroy(); } catch (_) {}
      throw Exception('FTP PASS failed: $r2');
    }
  }

  write(cmd('TYPE I'));
  await readResp();

  // Enter passive mode
  write(cmd('PASV'));
  final pasv = await readResp();
  final pasvMatch = RegExp(r"\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)").firstMatch(pasv);
  if (pasvMatch == null) {
    try { socket.destroy(); } catch (_) {}
    throw Exception('FTP PASV parse failed: $pasv');
  }
  final h1 = int.parse(pasvMatch.group(1)!);
  final h2 = int.parse(pasvMatch.group(2)!);
  final h3 = int.parse(pasvMatch.group(3)!);
  final h4 = int.parse(pasvMatch.group(4)!);
  final p1 = int.parse(pasvMatch.group(5)!);
  final p2 = int.parse(pasvMatch.group(6)!);
  final dataHost = '$h1.$h2.$h3.$h4';
  final dataPort = (p1 * 256) + p2;

  // Change to directory
  if (dir != '/' && dir.isNotEmpty) {
    write(cmd('CWD $dir'));
    await readResp();
  }

  final dataSocket = await Socket.connect(dataHost, dataPort, timeout: const Duration(seconds: 5));
  final dataBuffer = StringBuffer();
  final dataCompleter = Completer<void>();
  dataSocket.listen((d) {
    dataBuffer.write(utf8.decode(d, allowMalformed: true));
  }, onDone: () => dataCompleter.complete(), onError: (_) => dataCompleter.complete());

  write(cmd('LIST'));
  await dataCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () {});
  try { dataSocket.destroy(); } catch (_) {}
  await readResp(); // 226 transfer complete

  try { socket.destroy(); } catch (_) {}

  final lines = dataBuffer.toString().split('\n');
  final names = <String>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    // Try UNIX ls format: permissions links owner group size month day time name
    final idx = trimmed.indexOf(':');
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 9) {
      final name = parts.sublist(8).join(' ');
      names.add(name);
    } else if (idx != -1) {
      final name = trimmed.substring(idx + 3).trim();
      if (name.isNotEmpty) names.add(name);
    } else {
      // fallback: last token
      names.add(parts.last);
    }
  }
  return names;
}