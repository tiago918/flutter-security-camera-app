import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/camera_models.dart';
import 'onvif_recording_service.dart';
import 'unified_onvif_service.dart';

/// Serviço para obter URL de playback e realizar download de gravações
/// Tenta múltiplas estratégias: URLs presentes no metadata, padrões HTTP comuns
/// de diversos fabricantes e fallback para RTSP (quando aplicável).
class OnvifPlaybackService {
  static const Duration _httpTimeout = Duration(seconds: 15);
  static const Duration _connectionTimeout = Duration(seconds: 8);
  static const Duration _downloadTimeout = Duration(minutes: 5);
  static const int _maxRetries = 3;

  // Delegação para buscas agregadas (ONVIF/HTTP/FTP/RTSP)
  final OnvifRecordingService _recordingService = OnvifRecordingService();

  // Suporte a HTTPS com certificado autoassinado (configurável)
  static bool _defaultAcceptSelfSigned = false;
  static Future<void> initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _defaultAcceptSelfSigned = prefs.getBool('accept_self_signed_https') ?? false;
  }
  static void setDefaultAcceptSelfSigned(bool value) {
    _defaultAcceptSelfSigned = value;
  }

  final http.Client _client;

  OnvifPlaybackService({bool? acceptSelfSigned})
      : _client = _buildHttpClient(acceptSelfSigned ?? _defaultAcceptSelfSigned);

  static http.Client _buildHttpClient(bool acceptSelfSigned) {
    if (acceptSelfSigned) {
      final ioHttp = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      return IOClient(ioHttp);
    }
    return http.Client();
  }

  // Exposto para páginas que já dependem de OnvifPlaybackService
  Future<List<RecordingInfo>> searchRecordings(
    CameraData camera, {
    DateTime? startTime,
    DateTime? endTime,
    String? recordingType,
  }) async {
    return _recordingService.searchRecordings(
      camera,
      startTime: startTime,
      endTime: endTime,
      recordingType: recordingType,
    );
  }

  /// Retorna uma URL que possa ser reproduzida pelo player (http/https/rtsp)
  /// Retorna null quando não for possível obter.
  Future<String?> getPlaybackUrl(CameraData camera, RecordingInfo recording) async {
    int retryCount = 0;
    
    while (retryCount < _maxRetries) {
      try {
        print('Playback: Getting URL for ${camera.name} recording ${recording.filename} (attempt ${retryCount + 1}/$_maxRetries)');

        // Primeiro tentar usando o UnifiedOnvifService
        final unifiedService = UnifiedOnvifService();
        try {
          await unifiedService.connect(camera).timeout(_connectionTimeout);
          
          // Tentar obter URL de playback através do serviço unificado
          final url = await _getPlaybackUrlUnified(unifiedService, camera, recording);
          await unifiedService.disconnect(camera.id.toString());
          
          if (url != null && await _validatePlaybackUrl(url, camera)) {
            print('Playback URL obtained and validated successfully via unified service for ${camera.name}');
            return url;
          }
        } catch (e) {
          print('Failed to get playback URL via unified service (attempt ${retryCount + 1}): $e');
          try {
            await unifiedService.disconnect(camera.id.toString());
          } catch (_) {}
        }
        
        // Fallback para método original
        final originalUrl = await _getPlaybackUrlOriginal(camera, recording);
        if (originalUrl != null && await _validatePlaybackUrl(originalUrl, camera)) {
          print('Playback URL obtained via original method for ${camera.name}');
          return originalUrl;
        }
        
        retryCount++;
        if (retryCount < _maxRetries) {
          print('Retrying playback URL retrieval in 2 seconds...');
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        print('OnvifPlaybackService.getPlaybackUrl error (attempt ${retryCount + 1}): $e');
        retryCount++;
        if (retryCount < _maxRetries) {
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
      }
    }
    
    print('Failed to get playback URL for ${camera.name} after $_maxRetries attempts');
    return null;
  }
  
  /// Obtém URL de playback usando UnifiedOnvifService
  Future<String?> _getPlaybackUrlUnified(UnifiedOnvifService service, CameraData camera, RecordingInfo recording) async {
    try {
      if (service.onvifConnection != null) {
        // TODO: Métodos de playback não disponíveis na versão atual do easy_onvif
        print('Playback: ONVIF playback methods not available, trying alternative approaches');
        
        // Fallback para método original
        return await _getPlaybackUrlOriginal(camera, recording);
      }
      return null;
    } catch (e) {
      print('Failed to get playback URL via unified service: $e');
      return null;
    }
  }
  
  /// Método original para obter URL de playback
  Future<String?> _getPlaybackUrlOriginal(CameraData camera, RecordingInfo recording) async {
    try {
      print('Trying original playback URL method for ${camera.name}');
      
      // 1) Se há URL no metadata, priorize e valide
      final meta = recording.metadata ?? const {};
      final metaUrl = _firstNonEmpty([
        meta['playbackUrl'],
        meta['rtspUrl'],
        meta['httpUrl'],
        meta['url'],
        recording.thumbnailUrl, // alguns sistemas reutilizam este campo como link
      ]);
      if (metaUrl is String && metaUrl.isNotEmpty) {
        final urlWithCreds = _withCredentialsIfNeeded(metaUrl, camera.username, camera.password);
        if (urlWithCreds != null) {
          print('Found metadata URL: $metaUrl');
          return urlWithCreds;
        }
      }

      // 2) Tentar construir URLs HTTP comuns de playback/download
      print('Trying candidate HTTP URLs for ${camera.name}');
      final candidates = _candidateDownloadUrls(camera, recording);
      for (int i = 0; i < candidates.length; i++) {
        final url = candidates[i];
        print('Testing HTTP URL ${i + 1}/${candidates.length}: ${_sanitizeUrlForLog(url)}');
        
        if (await _isHttpUrlReachable(url, camera.username, camera.password)) {
          print('HTTP URL is reachable: ${_sanitizeUrlForLog(url)}');
          return url; // Player suporta http(s)
        }
      }

      // 3) Fallback: RTSP simples (não garante playback de gravação, mas tenta)
      print('Trying RTSP fallback for ${camera.name}');
      final rtsp = _candidateRtspUrlFromStream(camera);
      if (rtsp != null) {
        print('Testing RTSP URL: ${_sanitizeUrlForLog(rtsp)}');
        if (await _isRtspReachable(rtsp)) {
          print('RTSP URL is reachable: ${_sanitizeUrlForLog(rtsp)}');
          return rtsp;
        }
      }

      print('No valid playback URL found for ${camera.name}');
      return null;
    } catch (e) {
      print('OnvifPlaybackService._getPlaybackUrlOriginal error: $e');
      return null;
    }
  }

  /// Faz download da gravação para [savePath].
  /// Retorna true em caso de sucesso.
  Future<bool> downloadRecording(
    CameraData camera,
    RecordingInfo recording,
    String savePath,
  ) async {
    try {
      // 1) Se já houver URL válida no metadata, tente primeiro
      final meta = recording.metadata ?? const {};
      final firstUrl = _firstNonEmpty([
        meta['downloadUrl'],
        meta['playbackUrl'],
        meta['httpUrl'],
        recording.thumbnailUrl,
      ]);
      if (firstUrl is String && firstUrl.isNotEmpty) {
        final uri = Uri.tryParse(firstUrl);
        if (uri != null) {
          if (uri.scheme == 'http' || uri.scheme == 'https') {
            final ok = await _tryDownloadUrl(
              _withCredentialsIfNeeded(firstUrl, camera.username, camera.password)!,
              savePath,
              user: camera.username,
              pass: camera.password,
            );
            if (ok) return true;
          } else if (uri.scheme == 'ftp') {
            final ok = await _tryFtpDownloadUrl(
              firstUrl,
              savePath,
              user: camera.username,
              pass: camera.password,
            );
            if (ok) return true;
          }
        }
      }

      // 2) Tentar lista extensa de padrões HTTP conhecidos
      final httpUrls = _candidateDownloadUrls(camera, recording);
      for (final url in httpUrls) {
        final ok = await _tryDownloadUrl(url, savePath, user: camera.username, pass: camera.password);
        if (ok) return true;
      }

      // 3) Tentar padrões FTP conhecidos
      final ftpUrls = _candidateFtpDownloadUrls(camera, recording);
      for (final url in ftpUrls) {
        final ok = await _tryFtpDownloadUrl(url, savePath, user: camera.username, pass: camera.password);
        if (ok) return true;
      }

      // 4) Como último recurso, baixar via stream ao vivo (não é a gravação original)
      final rtsp = _candidateRtspUrlFromStream(camera);
      if (rtsp != null) {
        // Não há suporte trivial de download RTSP aqui; evitamos simulação.
        // Poderíamos futuramente usar ffmpeg para gravar um trecho.
      }

      return false;
    } catch (e) {
      // ignore: avoid_print
      print('OnvifPlaybackService.downloadRecording error: $e');
      return false;
    }
  }

  // -------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------

  String? _withCredentialsIfNeeded(String url, String? user, String? pass) {
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) return url;
    try {
      final uri = Uri.parse(url);
      if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'rtsp') {
        // Incorporar credenciais na URL quando cabeçalho não é suportado pelo player
        final authUri = uri.replace(userInfo: '$user:$pass');
        return authUri.toString();
      }
      return url;
    } catch (_) {
      return url;
    }
  }

  List<String> _candidateDownloadUrls(CameraData camera, RecordingInfo recording) {
    final List<String> urls = [];

    try {
      final uri = Uri.parse(camera.streamUrl);
      final host = uri.host.isNotEmpty ? uri.host : camera.streamUrl;
      final port = (uri.hasPort && uri.port != 0) ? ':${uri.port}' : '';
      final scheme = uri.scheme.isNotEmpty ? (uri.scheme == 'rtsp' ? 'http' : uri.scheme) : 'http';
      final baseNoAuth = '$scheme://$host$port';

      // Padrões comuns (diversos fabricantes)
      final paths = <String>[
        '/recordings/${recording.filename}',
        '/record/${recording.filename}',
        '/sd/record/${recording.filename}',
        '/sdcard/rec/${recording.filename}',
        '/media/${recording.filename}',
        '/video/${recording.filename}',
        '/files/${recording.filename}',
        '/download/${recording.filename}',
        '/hdd/${recording.filename}',
        '/NVR/record/${recording.filename}',
        '/dav/${recording.filename}',
        '/mnt/sd/${recording.filename}',
        '/mnt/ide0/${recording.filename}',
        '/tmpfs/auto/tmp/${recording.filename}',
      ];

      for (final p in paths) {
        final raw = '$baseNoAuth$p';
        urls.add(_withCredentialsIfNeeded(raw, camera.username, camera.password) ?? raw);
      }
    } catch (_) {
      // Em caso de erro ao parsear, tente algo genérico
      final raw = 'http://${camera.streamUrl}/${recording.filename}';
      urls.add(_withCredentialsIfNeeded(raw, camera.username, camera.password) ?? raw);
    }

    // URLs vindas do metadata podem complementar
    final meta = recording.metadata ?? const {};
    for (final key in const ['downloadUrl', 'httpUrl', 'url']) {
      final v = meta[key];
      if (v is String && v.isNotEmpty) {
        urls.add(_withCredentialsIfNeeded(v, camera.username, camera.password) ?? v);
      }
    }

    // Se a thumbnailUrl aparenta ser arquivo de vídeo, incluir
    final thumb = (recording.thumbnailUrl ?? '').toLowerCase();
    if (RegExp(r'\.(mp4|mkv|ts|flv|avi)$').hasMatch(thumb)) {
      final v = recording.thumbnailUrl!;
      urls.add(_withCredentialsIfNeeded(v, camera.username, camera.password) ?? v);
    }

    // Remover duplicados preservando ordem
    final unique = <String>{};
    final dedup = <String>[];
    for (final u in urls) {
      if (unique.add(u)) dedup.add(u);
    }
    return dedup;
  }

  List<String> _candidateFtpDownloadUrls(CameraData camera, RecordingInfo recording) {
    final List<String> urls = [];
    try {
      final uri = Uri.parse(camera.streamUrl);
      final host = uri.host.isNotEmpty ? uri.host : camera.streamUrl;
      final port = (uri.hasPort && uri.port != 0) ? ':${uri.port}' : '';
      final base = 'ftp://$host$port';

      final paths = <String>[
        '/recordings/${recording.filename}',
        '/record/${recording.filename}',
        '/sd/record/${recording.filename}',
        '/sdcard/rec/${recording.filename}',
        '/media/${recording.filename}',
        '/video/${recording.filename}',
        '/files/${recording.filename}',
        '/download/${recording.filename}',
        '/hdd/${recording.filename}',
        '/NVR/record/${recording.filename}',
        '/dav/${recording.filename}',
        '/mnt/sd/${recording.filename}',
        '/mnt/ide0/${recording.filename}',
        '/tmpfs/auto/tmp/${recording.filename}',
        '/${recording.filename}',
      ];

      for (final p in paths) {
        urls.add('$base$p');
      }
    } catch (_) {
      urls.add('ftp://${camera.streamUrl}/${recording.filename}');
    }

    // URLs vindas do metadata podem complementar (se forem ftp)
    final meta = recording.metadata ?? const {};
    for (final key in const ['downloadUrl', 'url']) {
      final v = meta[key];
      if (v is String && v.startsWith('ftp://')) {
        urls.add(v);
      }
    }

    // Dedup
    final unique = <String>{};
    final dedup = <String>[];
    for (final u in urls) {
      if (unique.add(u)) dedup.add(u);
    }
    return dedup;
  }

  Future<bool> _isHttpUrlReachable(String url, String? user, String? pass) async {
    try {
      final uri = Uri.parse(url);
      if (!(uri.scheme == 'http' || uri.scheme == 'https')) {
        print('Invalid HTTP scheme for URL: ${_sanitizeUrlForLog(url)}');
        return false;
      }

      final headers = <String, String>{
        'User-Agent': 'CameraApp/1.0 (+PlaybackService)',
        'Accept': '*/*',
      };
      if (user != null && user.isNotEmpty && pass != null && pass.isNotEmpty) {
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
      }

      // Tentar HEAD primeiro (mais eficiente)
      try {
        final resp = await _client.head(uri, headers: headers).timeout(_httpTimeout);
        if (resp.statusCode == 200 || resp.statusCode == 206) {
          print('HTTP HEAD successful for: ${_sanitizeUrlForLog(url)}');
          return true;
        }
      } catch (e) {
        print('HTTP HEAD failed for ${_sanitizeUrlForLog(url)}: $e');
      }

      // Alguns servidores não suportam HEAD; tentar GET com Range pequeno
      try {
        final respGet = await _client.get(uri, headers: {
          ...headers,
          'Range': 'bytes=0-15',
        }).timeout(_httpTimeout);
        final success = respGet.statusCode == 200 || respGet.statusCode == 206;
        if (success) {
          print('HTTP GET with range successful for: ${_sanitizeUrlForLog(url)}');
        } else {
          print('HTTP GET failed with status ${respGet.statusCode} for: ${_sanitizeUrlForLog(url)}');
        }
        return success;
      } catch (e) {
        print('HTTP GET failed for ${_sanitizeUrlForLog(url)}: $e');
        return false;
      }
    } catch (e) {
      print('HTTP URL reachability check failed for ${_sanitizeUrlForLog(url)}: $e');
      return false;
    }
  }

  Future<bool> _tryDownloadUrl(String url, String savePath, {String? user, String? pass}) async {
    try {
      print('Attempting download from: ${_sanitizeUrlForLog(url)}');
      final uri = Uri.parse(url);
      if (!(uri.scheme == 'http' || uri.scheme == 'https')) {
        print('Invalid scheme for download URL: ${uri.scheme}');
        return false;
      }

      final headers = <String, String>{
        'User-Agent': 'CameraApp/1.0 (+PlaybackService)',
        'Accept': '*/*',
        'Connection': 'keep-alive',
      };
      if (user != null && user.isNotEmpty && pass != null && pass.isNotEmpty) {
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
      }

      final resp = await _client.get(uri, headers: headers).timeout(_downloadTimeout);
      print('Download response status: ${resp.statusCode}, Content-Length: ${resp.headers['content-length'] ?? 'unknown'}');
      
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        final file = File(savePath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(resp.bodyBytes);
        
        final fileSize = await file.length();
        print('Download successful: ${_sanitizeUrlForLog(url)} -> $savePath ($fileSize bytes)');
        return true;
      } else if (resp.statusCode != 200) {
        print('Download failed with HTTP ${resp.statusCode}: ${resp.reasonPhrase}');
      } else {
        print('Download failed: empty response body');
      }
      return false;
    } catch (e) {
      print('PlaybackService: download failed for ${_sanitizeUrlForLog(url)} -> $e');
      return false;
    }
  }

  Future<bool> _tryFtpDownloadUrl(String url, String savePath, {String? user, String? pass}) async {
    FTPConnect? ftpConnect;
    try {
      print('Attempting FTP download from: ${_sanitizeUrlForLog(url)}');
      final uri = Uri.parse(url);
      if (uri.scheme != 'ftp') {
        print('Invalid scheme for FTP download: ${uri.scheme}');
        return false;
      }

      final ftpUser = user ?? 'anonymous';
      final ftpPass = pass ?? 'anonymous';
      final ftpPort = uri.port == -1 ? 21 : uri.port;
      
      print('Connecting to FTP server: ${uri.host}:$ftpPort as $ftpUser');
      ftpConnect = FTPConnect(uri.host, port: ftpPort, user: ftpUser, pass: ftpPass);
      
      final connected = await ftpConnect.connect().timeout(_connectionTimeout);
      if (!connected) {
        print('Failed to connect to FTP server: ${uri.host}:$ftpPort');
        return false;
      }
      
      print('FTP connected, downloading file: ${uri.path}');
      final file = File(savePath);
      await file.parent.create(recursive: true);
      
      final downloadResult = await ftpConnect.downloadFile(uri.path, file).timeout(_downloadTimeout);
      
      if (downloadResult && await file.exists()) {
        final fileSize = await file.length();
        print('FTP download successful: ${_sanitizeUrlForLog(url)} -> $savePath ($fileSize bytes)');
      } else {
        print('FTP download failed: file not created or download returned false');
      }
      
      return downloadResult;
    } catch (e) {
      print('PlaybackService: FTP download failed for ${_sanitizeUrlForLog(url)} -> $e');
      return false;
    } finally {
      try {
        await ftpConnect?.disconnect();
      } catch (e) {
        print('Error disconnecting FTP: $e');
      }
    }
  }

  bool _isPrivateIPv4(String ip) {
    try {
      final parts = ip.split('.').map((e) => int.parse(e)).toList();
      if (parts.length != 4) return false;
      final a = parts[0], b = parts[1];
      if (a == 10) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 192 && b == 168) return true;
      if (a == 169 && b == 254) return true; // link-local
      return false;
    } catch (_) {
      return false;
    }
  }

  String? _candidateRtspUrlFromStream(CameraData camera) {
    try {
      final uri = Uri.parse(camera.streamUrl);
      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'rtsp';
      final host = uri.host.isNotEmpty ? uri.host : camera.streamUrl;

      // Se já é RTSP, apenas reintroduza credenciais se faltando
      if (scheme == 'rtsp') {
        final path = (uri.path.isNotEmpty && uri.path.startsWith('/')) ? uri.path : '/stream1';
        final port = (uri.hasPort && uri.port != 0) ? uri.port : 554;
        final built = Uri(
          scheme: 'rtsp',
          host: host,
          port: port,
          userInfo: (camera.username?.isNotEmpty == true && camera.password?.isNotEmpty == true)
              ? '${camera.username}:${camera.password}'
              : null,
          path: path.isNotEmpty ? path : '/stream1',
        );
        return built.toString();
      }

      // Transformar http->rtsp com caminhos comuns
      final rtspPort = 554;
      final candidates = <String>[
        'rtsp://$host:$rtspPort/Streaming/tracks/101',
        'rtsp://$host:$rtspPort/cam/realmonitor?channel=1&subtype=0',
        'rtsp://$host:$rtspPort/live/ch00_0',
        'rtsp://$host:$rtspPort/stream1',
        'rtsp://$host:$rtspPort/h264',
      ];
      final creds = (camera.username?.isNotEmpty == true && camera.password?.isNotEmpty == true)
          ? '${camera.username}:${camera.password}@'
          : '';
      return candidates.isNotEmpty ? candidates.first.replaceFirst('rtsp://', 'rtsp://$creds') : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isRtspReachable(String rtspUrl) async {
    try {
      final uri = Uri.parse(rtspUrl);
      final port = uri.port == 0 ? 554 : uri.port;
      print('Testing RTSP connection to ${uri.host}:$port');
      
      final socket = await Socket.connect(uri.host, port, timeout: _connectionTimeout);
      socket.destroy();
      print('RTSP connection successful to ${uri.host}:$port');
      return true;
    } catch (e) {
      print('RTSP connection failed for ${_sanitizeUrlForLog(rtspUrl)}: $e');
      return false;
    }
  }

  /// Valida se uma URL de playback é realmente utilizável
  Future<bool> _validatePlaybackUrl(String url, CameraData camera) async {
    try {
      final uri = Uri.parse(url);
      
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return await _isHttpUrlReachable(url, camera.username, camera.password);
      } else if (uri.scheme == 'rtsp') {
        return await _isRtspReachable(url);
      }
      
      return false;
    } catch (e) {
      print('URL validation failed for ${_sanitizeUrlForLog(url)}: $e');
      return false;
    }
  }
  
  /// Remove credenciais da URL para logs seguros
  String _sanitizeUrlForLog(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.hasAuthority && uri.userInfo.isNotEmpty) {
        return uri.replace(userInfo: '***:***').toString();
      }
      return url;
    } catch (_) {
      // Se não conseguir parsear, apenas ocultar possíveis credenciais
      return url.replaceAll(RegExp(r'://[^:]+:[^@]+@'), '://***:***@');
    }
  }

  dynamic _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}