import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/camera_models.dart';
import 'onvif_recording_service.dart';

/// Serviço para obter URL de playback e realizar download de gravações
/// Tenta múltiplas estratégias: URLs presentes no metadata, padrões HTTP comuns
/// de diversos fabricantes e fallback para RTSP (quando aplicável).
class OnvifPlaybackService {
  static const Duration _httpTimeout = Duration(seconds: 12);

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

  final bool _acceptSelfSigned;
  final http.Client _client;

  OnvifPlaybackService({bool? acceptSelfSigned})
      : _acceptSelfSigned = acceptSelfSigned ?? _defaultAcceptSelfSigned,
        _client = _buildHttpClient(acceptSelfSigned ?? _defaultAcceptSelfSigned);

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
    try {
      // 1) Se há URL no metadata, priorize
      final meta = recording.metadata ?? const {};
      final metaUrl = _firstNonEmpty([
        meta['playbackUrl'],
        meta['rtspUrl'],
        meta['httpUrl'],
        meta['url'],
        recording.thumbnailUrl, // alguns sistemas reutilizam este campo como link
      ]);
      if (metaUrl is String && metaUrl.isNotEmpty) {
        return _withCredentialsIfNeeded(metaUrl, camera.username, camera.password);
      }

      // 2) Tentar construir URLs HTTP comuns de playback/download
      final candidates = _candidateDownloadUrls(camera, recording);
      for (final url in candidates) {
        if (await _isHttpUrlReachable(url, camera.username, camera.password)) {
          return url; // Player suporta http(s)
        }
      }

      // 3) Fallback: RTSP simples (não garante playback de gravação, mas tenta)
      final rtsp = _candidateRtspUrlFromStream(camera);
      if (rtsp != null && await _isRtspReachable(rtsp)) {
        return rtsp;
      }

      return null;
    } catch (e) {
      // Log silencioso
      // ignore: avoid_print
      print('OnvifPlaybackService.getPlaybackUrl error: $e');
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
      if (!(uri.scheme == 'http' || uri.scheme == 'https')) return false;

      final headers = <String, String>{};
      if (user != null && user.isNotEmpty && pass != null && pass.isNotEmpty) {
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
      }

      final resp = await _client.head(uri, headers: headers).timeout(_httpTimeout);
      if (resp.statusCode == 200) return true;

      // Alguns servidores não suportam HEAD; tentar GET com Range pequeno
      final respGet = await _client.get(uri, headers: {
        ...headers,
        'Range': 'bytes=0-15',
      }).timeout(_httpTimeout);
      return respGet.statusCode == 200 || respGet.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryDownloadUrl(String url, String savePath, {String? user, String? pass}) async {
    try {
      final uri = Uri.parse(url);
      if (!(uri.scheme == 'http' || uri.scheme == 'https')) return false;

      final headers = <String, String>{
        'User-Agent': 'CameraApp/1.0 (+PlaybackService)'
      };
      if (user != null && user.isNotEmpty && pass != null && pass.isNotEmpty) {
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
      }

      final resp = await _client.get(uri, headers: headers).timeout(const Duration(minutes: 2));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        final file = File(savePath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(resp.bodyBytes);
        return true;
      }
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('PlaybackService: download failed for $url -> $e');
      return false;
    }
  }

  Future<bool> _tryFtpDownloadUrl(String url, String savePath, {String? user, String? pass}) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'ftp') return false;
      final host = uri.host;
      final port = uri.hasPort && uri.port != 0 ? uri.port : 21;
      final username = (user ?? uri.userInfo.split(':').first).isNotEmpty
          ? (user ?? uri.userInfo.split(':').first)
          : 'anonymous';
      final password = (pass ?? (uri.userInfo.contains(':') ? uri.userInfo.split(':').last : ''))
              .isNotEmpty
          ? (pass ?? (uri.userInfo.contains(':') ? uri.userInfo.split(':').last : 'anonymous@'))
          : 'anonymous@';
      final remotePath = uri.path.isNotEmpty
          ? uri.path
          : (uri.pathSegments.isNotEmpty ? '/${uri.pathSegments.last}' : '');
      if (remotePath.isEmpty) return false;

      final control = await Socket.connect(host, port, timeout: const Duration(seconds: 6));
      final ctrlBuffer = StringBuffer();
      final ctrlDone = Completer<void>();
      control.listen((data) {
        ctrlBuffer.write(utf8.decode(data, allowMalformed: true));
      }, onDone: () => ctrlDone.complete(), onError: (_) => ctrlDone.complete());

      Future<String> readCtrl([Duration timeout = const Duration(seconds: 2)]) async {
        await Future.any([
          Future.delayed(timeout),
          ctrlDone.future,
        ]);
        final s = ctrlBuffer.toString();
        ctrlBuffer.clear();
        return s;
      }

      void writeCtrl(String c) => control.add(utf8.encode('$c\r\n'));

      // Banner inicial
      await readCtrl();

      // Autenticação
      writeCtrl('USER $username');
      final r1 = await readCtrl();
      if (!r1.startsWith('331') && !r1.startsWith('230')) {
        try { control.destroy(); } catch (_) {}
        return false;
      }
      if (r1.startsWith('331')) {
        writeCtrl('PASS $password');
        final r2 = await readCtrl();
        if (!r2.startsWith('230')) {
          try { control.destroy(); } catch (_) {}
          return false;
        }
      }

      // Modo binário
      writeCtrl('TYPE I');
      await readCtrl();

      // Tentar EPSV primeiro (melhor em NAT/IPv6)
      int? dataPort;
      String dataHost = host;
      writeCtrl('EPSV');
      final epsv = await readCtrl();
      if (epsv.startsWith('229')) {
        final m = RegExp(r"\(\|\|\|(\d+)\|\)").firstMatch(epsv);
        if (m != null) {
          dataPort = int.tryParse(m.group(1)!);
        }
      }

      // Fallback para PASV
      if (dataPort == null) {
        writeCtrl('PASV');
        final pasv = await readCtrl();
        final m = RegExp(r"\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)").firstMatch(pasv);
        if (m == null) {
          try { control.destroy(); } catch (_) {}
          return false;
        }
        final ip = '${m.group(1)}.${m.group(2)}.${m.group(3)}.${m.group(4)}';
        final p1 = int.parse(m.group(5)!);
        final p2 = int.parse(m.group(6)!);
        dataPort = (p1 * 256) + p2;
        // Alguns servidores retornam IP privado; use o host original nesses casos
        dataHost = _isPrivateIPv4(ip) ? host : ip;
      }

      // Conecta canal de dados
      Socket data;
      try {
        data = await Socket.connect(dataHost, dataPort!, timeout: const Duration(seconds: 6));
      } catch (_) {
        // Alguns servidores só aceitam conexão após 150; tentar depois do RETR
        data = await Socket.connect(dataHost, dataPort!, timeout: const Duration(seconds: 6));
      }

      // Preparar escrita em arquivo
      final file = File(savePath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      int received = 0;
      final dataDone = Completer<void>();
      data.listen((chunk) {
        received += chunk.length;
        sink.add(chunk);
      }, onDone: () async {
        await sink.flush();
        await sink.close();
        dataDone.complete();
      }, onError: (e) async {
        try { await sink.close(); } catch (_) {}
        dataDone.complete();
      });

      // Solicitar arquivo
      writeCtrl('RETR $remotePath');
      final pre = await readCtrl(const Duration(seconds: 4)); // 150/125 esperado

      // Aguarda transferência
      await dataDone.future.timeout(const Duration(minutes: 2), onTimeout: () async {
        try { data.destroy(); } catch (_) {}
      });

      // Resposta final
      final post = await readCtrl(const Duration(seconds: 4)); // 226 esperado

      try { control.destroy(); } catch (_) {}
      try { data.destroy(); } catch (_) {}

      return received > 0 && (pre.contains('150') || pre.contains('125')) && post.contains('226');
    } catch (e) {
      // ignore: avoid_print
      print('PlaybackService: FTP download failed for $url -> $e');
      return false;
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
      final socket = await Socket.connect(uri.host, uri.port == 0 ? 554 : uri.port, timeout: const Duration(seconds: 4));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  dynamic _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}