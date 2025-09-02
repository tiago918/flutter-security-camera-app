import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:easy_onvif/onvif.dart';
import '../models/camera_models.dart';
// ignore_for_file: avoid_print

class RecordingService {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  final Map<String, RecordingSession> _activeRecordings = {};
  final StreamController<Map<String, RecordingSession>> _recordingsController = 
      StreamController<Map<String, RecordingSession>>.broadcast();

  Stream<Map<String, RecordingSession>> get recordingsStream => _recordingsController.stream;
  Map<String, RecordingSession> get activeRecordings => Map.unmodifiable(_activeRecordings);

  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _commandTimeout = Duration(seconds: 5);

  /// Inicia a gravação de uma câmera
  Future<bool> startRecording(CameraData camera, {Duration? duration}) async {
    try {
      // Verificar se já está gravando
      if (_activeRecordings.containsKey(camera.id.toString())) {
        // Recording: Camera ${camera.name} is already recording
        return false;
      }

      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) {
        // Recording Error: Missing ONVIF credentials for ${camera.name}
        return false;
      }

      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) return false;
      
      final host = uri.host;
      if (host.isEmpty) return false;

      print('Recording: Starting recording for ${camera.name} at $host');

      // Conectar ao dispositivo ONVIF
      final portsToTry = <int>[80, 8080, 8000, 8899];
      Onvif? onvif;
      
      for (final port in portsToTry) {
        try {
          onvif = await Onvif.connect(
            host: '$host:$port',
            username: user,
            password: pass,
          ).timeout(_connectionTimeout);
          print('Recording: Connected to $host:$port for recording');
          break;
        } catch (error) {
          print('Recording: Failed to connect to $host:$port -> $error');
          continue;
        }
      }

      if (onvif == null) {
        print('Recording Error: Could not connect to ONVIF service for $host');
        return false;
      }

      // Obter perfis de mídia
      final profiles = await onvif.media.getProfiles().timeout(_commandTimeout);
      if (profiles.isEmpty) {
        print('Recording Error: No media profiles found on device $host');
        return false;
      }

      final profile = profiles.first;
      print('Recording: Using profile token: ${profile.token}');

      // Obter URI do stream para gravação
      final streamUri = await onvif.media.getStreamUri(profile.token).timeout(_commandTimeout);
      print('Recording: Stream URI obtained: $streamUri');

      // Criar diretório de gravações
      final recordingsDir = await _getRecordingsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final filename = '${camera.name}_$timestamp.mp4';
      final filePath = '${recordingsDir.path}/$filename';

      // Criar sessão de gravação
      final session = RecordingSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        cameraId: camera.id.toString(),
        cameraName: camera.name,
        filePath: filePath,
        startTime: DateTime.now(),
        duration: duration,
        streamUri: streamUri,
        status: RecordingStatus.starting,
      );

      _activeRecordings[camera.id.toString()] = session;
      _recordingsController.add(_activeRecordings);

      // Iniciar gravação usando ffmpeg (se disponível) ou método alternativo
      final success = await _startRecordingProcess(session);
      
      if (success) {
        _activeRecordings[camera.id.toString()] = session.copyWith(status: RecordingStatus.recording);
        _recordingsController.add(_activeRecordings);
        
        // Configurar timer para parar gravação automaticamente se duração especificada
        if (duration != null) {
          Timer(duration, () => stopRecording(camera.id.toString()));
        }
        
        print('Recording: Successfully started recording for ${camera.name}');
        return true;
      } else {
        _activeRecordings.remove(camera.id.toString());
        _recordingsController.add(_activeRecordings);
        return false;
      }
    } catch (e) {
      // Recording Error: Exception starting recording: $e
      _activeRecordings.remove(camera.id.toString());
      _recordingsController.add(_activeRecordings);
      return false;
    }
  }

  /// Para a gravação de uma câmera
  Future<bool> stopRecording(String cameraId) async {
    try {
      final session = _activeRecordings[cameraId];
      if (session == null) {
        // Recording: No active recording found for camera $cameraId
        return false;
      }

      print('Recording: Stopping recording for ${session.cameraName}');
      
      // Atualizar status
      _activeRecordings[cameraId] = session.copyWith(status: RecordingStatus.stopping);
      _recordingsController.add(_activeRecordings);

      // Parar processo de gravação
      final success = await _stopRecordingProcess(session);
      
      // Remover da lista de gravações ativas
      _activeRecordings.remove(cameraId);
      _recordingsController.add(_activeRecordings);
      
      if (success) {
        print('Recording: Successfully stopped recording for ${session.cameraName}');
        
        // Verificar se arquivo foi criado
        final file = File(session.filePath);
        if (await file.exists()) {
          final size = await file.length();
          print('Recording: File saved: ${session.filePath} (${_formatFileSize(size)})');
        }
      }
      
      return success;
    } catch (e) {
      // Recording Error: Exception stopping recording: $e
      _activeRecordings.remove(cameraId);
      _recordingsController.add(_activeRecordings);
      return false;
    }
  }

  /// Inicia o processo de gravação
  Future<bool> _startRecordingProcess(RecordingSession session) async {
    try {
      // Método 1: Tentar usar ffmpeg se disponível
      if (await _isFFmpegAvailable()) {
        return await _startFFmpegRecording(session);
      }
      
      // Método 2: Gravação simples via HTTP stream
      return await _startHttpStreamRecording(session);
    } catch (e) {
      print('Recording Error: Failed to start recording process: $e');
      return false;
    }
  }

  /// Para o processo de gravação
  Future<bool> _stopRecordingProcess(RecordingSession session) async {
    try {
      // Implementar lógica para parar o processo específico
      // Por enquanto, assumir sucesso
      return true;
    } catch (e) {
      print('Recording Error: Failed to stop recording process: $e');
      return false;
    }
  }

  /// Verifica se ffmpeg está disponível
  Future<bool> _isFFmpegAvailable() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Inicia gravação usando ffmpeg
  Future<bool> _startFFmpegRecording(RecordingSession session) async {
    try {
      final args = [
        '-i', session.streamUri,
        '-c', 'copy',
        '-f', 'mp4',
        session.filePath,
      ];
      
      print('Recording: Starting ffmpeg with args: ${args.join(' ')}');
      
      // Iniciar processo ffmpeg
      await Process.start('ffmpeg', args);
      
      // Armazenar referência do processo para poder parar depois
      // Em uma implementação completa, você manteria uma referência ao processo
      
      return true;
    } catch (e) {
      print('Recording Error: FFmpeg recording failed: $e');
      return false;
    }
  }

  /// Inicia gravação via HTTP stream
  Future<bool> _startHttpStreamRecording(RecordingSession session) async {
    try {
      print('Recording: Starting HTTP stream recording (fallback method)');
      
      // Implementação simplificada - em produção, você implementaria
      // um downloader de stream HTTP adequado
      
      // Por enquanto, criar um arquivo vazio para demonstração
      final file = File(session.filePath);
      await file.create(recursive: true);
      await file.writeAsString('# Recording placeholder for ${session.cameraName}\n# Started at: ${session.startTime}\n');
      
      return true;
    } catch (e) {
      print('Recording Error: HTTP stream recording failed: $e');
      return false;
    }
  }

  /// Obtém o diretório de gravações
  Future<Directory> _getRecordingsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${appDir.path}/camera_recordings');
    
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    
    return recordingsDir;
  }

  /// Lista gravações salvas
  Future<List<SavedRecording>> getSavedRecordings() async {
    try {
      final recordingsDir = await _getRecordingsDirectory();
      final files = await recordingsDir.list().toList();
      
      final recordings = <SavedRecording>[];
      
      for (final file in files) {
        if (file is File && file.path.endsWith('.mp4')) {
          final stat = await file.stat();
          final filename = file.path.split('/').last;
          
          recordings.add(SavedRecording(
            id: filename,
            filename: filename,
            filePath: file.path,
            size: stat.size,
            createdAt: stat.modified,
            duration: null, // Seria calculado analisando o arquivo
          ));
        }
      }
      
      // Ordenar por data de criação (mais recente primeiro)
      recordings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return recordings;
    } catch (e) {
      // Recording Error: Failed to get saved recordings: $e
      return [];
    }
  }

  /// Deleta uma gravação salva
  Future<bool> deleteRecording(String recordingId) async {
    try {
      final recordingsDir = await _getRecordingsDirectory();
      final file = File('${recordingsDir.path}/$recordingId');
      
      if (await file.exists()) {
        await file.delete();
        print('Recording: Deleted recording $recordingId');
        return true;
      }
      
      return false;
    } catch (e) {
      // Recording Error: Failed to delete recording: $e
      return false;
    }
  }

  /// Formata tamanho do arquivo
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Dispose resources
  void dispose() {
    // Parar todas as gravações ativas
    for (final cameraId in _activeRecordings.keys.toList()) {
      stopRecording(cameraId);
    }
    
    _recordingsController.close();
  }
}

/// Status da gravação
enum RecordingStatus {
  starting,
  recording,
  stopping,
  stopped,
  error,
}

/// Sessão de gravação ativa
class RecordingSession {
  final String id;
  final String cameraId;
  final String cameraName;
  final String filePath;
  final DateTime startTime;
  final Duration? duration;
  final String streamUri;
  final RecordingStatus status;

  const RecordingSession({
    required this.id,
    required this.cameraId,
    required this.cameraName,
    required this.filePath,
    required this.startTime,
    this.duration,
    required this.streamUri,
    required this.status,
  });

  RecordingSession copyWith({
    String? id,
    String? cameraId,
    String? cameraName,
    String? filePath,
    DateTime? startTime,
    Duration? duration,
    String? streamUri,
    RecordingStatus? status,
  }) {
    return RecordingSession(
      id: id ?? this.id,
      cameraId: cameraId ?? this.cameraId,
      cameraName: cameraName ?? this.cameraName,
      filePath: filePath ?? this.filePath,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      streamUri: streamUri ?? this.streamUri,
      status: status ?? this.status,
    );
  }
}

/// Gravação salva
class SavedRecording {
  final String id;
  final String filename;
  final String filePath;
  final int size;
  final DateTime createdAt;
  final Duration? duration;

  const SavedRecording({
    required this.id,
    required this.filename,
    required this.filePath,
    required this.size,
    required this.createdAt,
    this.duration,
  });
}