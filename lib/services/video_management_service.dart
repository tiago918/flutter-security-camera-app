import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serviço para gerenciamento de vídeos gravados
class VideoManagementService {
  static final VideoManagementService _instance = VideoManagementService._internal();
  factory VideoManagementService() => _instance;
  VideoManagementService._internal();

  final StreamController<VideoManagementEvent> _eventController = StreamController<VideoManagementEvent>.broadcast();
  Stream<VideoManagementEvent> get eventStream => _eventController.stream;

  /// Obtém lista de vídeos gravados para uma câmera
  Future<List<RecordedVideo>> getRecordedVideos(int cameraId) async {
    try {
      final recordingsDir = await _getRecordingsDirectory();
      final files = await recordingsDir.list().where((entity) => 
        entity is File && 
        entity.path.contains('camera_${cameraId}_') &&
        (entity.path.endsWith('.mp4') || entity.path.endsWith('.avi'))
      ).cast<File>().toList();
      
      final videos = <RecordedVideo>[];
      
      for (final file in files) {
        final stats = await file.stat();
        final filename = file.path.split(Platform.pathSeparator).last;
        
        // Extrair timestamp do nome do arquivo
        final timestampMatch = RegExp(r'_(\d{8}_\d{6})_').firstMatch(filename);
        DateTime? recordingTime;
        
        if (timestampMatch != null) {
          final timestampStr = timestampMatch.group(1)!;
          try {
            recordingTime = DateTime.parse(
              '${timestampStr.substring(0, 4)}-${timestampStr.substring(4, 6)}-${timestampStr.substring(6, 8)}T'
              '${timestampStr.substring(9, 11)}:${timestampStr.substring(11, 13)}:${timestampStr.substring(13, 15)}'
            );
          } catch (e) {
            recordingTime = stats.modified;
          }
        } else {
          recordingTime = stats.modified;
        }
        
        // Extrair duração do nome do arquivo (se disponível)
        final durationMatch = RegExp(r'_dur(\d+)s_').firstMatch(filename);
        int? durationSeconds;
        if (durationMatch != null) {
          durationSeconds = int.tryParse(durationMatch.group(1)!);
        }
        
        videos.add(RecordedVideo(
          id: filename.hashCode.toString(),
          cameraId: cameraId,
          filename: filename,
          filePath: file.path,
          recordingTime: recordingTime,
          fileSize: stats.size,
          durationSeconds: durationSeconds,
          format: file.path.split('.').last.toUpperCase(),
          thumbnailPath: await _getThumbnailPath(file.path),
        ));
      }
      
      // Ordenar por data de gravação (mais recentes primeiro)
      videos.sort((a, b) => b.recordingTime.compareTo(a.recordingTime));
      
      return videos;
    } catch (e) {
      print('Video Management Error: Failed to get recorded videos for camera $cameraId: $e');
      return [];
    }
  }

  /// Obtém vídeo específico por ID
  Future<RecordedVideo?> getVideoById(String videoId) async {
    try {
      final recordingsDir = await _getRecordingsDirectory();
      final files = await recordingsDir.list().where((entity) => 
        entity is File && entity.path.hashCode.toString() == videoId
      ).cast<File>().toList();
      
      if (files.isEmpty) return null;
      
      final file = files.first;
      final stats = await file.stat();
      final filename = file.path.split(Platform.pathSeparator).last;
      
      // Extrair informações do arquivo
      final cameraIdMatch = RegExp(r'camera_(\d+)_').firstMatch(filename);
      final cameraId = cameraIdMatch != null ? int.parse(cameraIdMatch.group(1)!) : 0;
      
      return RecordedVideo(
        id: videoId,
        cameraId: cameraId,
        filename: filename,
        filePath: file.path,
        recordingTime: stats.modified,
        fileSize: stats.size,
        durationSeconds: null,
        format: file.path.split('.').last.toUpperCase(),
        thumbnailPath: await _getThumbnailPath(file.path),
      );
    } catch (e) {
      print('Video Management Error: Failed to get video by ID $videoId: $e');
      return null;
    }
  }

  /// Exclui um vídeo específico
  Future<bool> deleteVideo(String videoId) async {
    try {
      final video = await getVideoById(videoId);
      if (video == null) {
        print('Video Management Error: Video not found: $videoId');
        return false;
      }
      
      final file = File(video.filePath);
      if (await file.exists()) {
        await file.delete();
        
        // Deletar thumbnail se existir
        if (video.thumbnailPath != null) {
          final thumbnailFile = File(video.thumbnailPath!);
          if (await thumbnailFile.exists()) {
            await thumbnailFile.delete();
          }
        }
        
        _eventController.add(VideoManagementEvent(
          type: VideoManagementEventType.videoDeleted,
          videoId: videoId,
          cameraId: video.cameraId,
          message: 'Vídeo ${video.filename} excluído com sucesso',
          timestamp: DateTime.now(),
        ));
        
        print('Video Management: Deleted video ${video.filename}');
        return true;
      }
      
      return false;
    } catch (e) {
      print('Video Management Error: Failed to delete video $videoId: $e');
      _eventController.add(VideoManagementEvent(
        type: VideoManagementEventType.error,
        videoId: videoId,
        cameraId: 0,
        message: 'Erro ao excluir vídeo: $e',
        timestamp: DateTime.now(),
      ));
      return false;
    }
  }

  /// Exclui múltiplos vídeos
  Future<int> deleteMultipleVideos(List<String> videoIds) async {
    int deletedCount = 0;
    
    for (final videoId in videoIds) {
      if (await deleteVideo(videoId)) {
        deletedCount++;
      }
    }
    
    _eventController.add(VideoManagementEvent(
      type: VideoManagementEventType.bulkDelete,
      videoId: null,
      cameraId: 0,
      message: '$deletedCount de ${videoIds.length} vídeos excluídos',
      timestamp: DateTime.now(),
    ));
    
    return deletedCount;
  }

  /// Exclui todos os vídeos de uma câmera
  Future<int> deleteAllVideosForCamera(int cameraId) async {
    final videos = await getRecordedVideos(cameraId);
    final videoIds = videos.map((v) => v.id).toList();
    return await deleteMultipleVideos(videoIds);
  }

  /// Exclui vídeos mais antigos que uma data específica
  Future<int> deleteVideosOlderThan(int cameraId, DateTime cutoffDate) async {
    final videos = await getRecordedVideos(cameraId);
    final oldVideos = videos.where((v) => v.recordingTime.isBefore(cutoffDate)).toList();
    final videoIds = oldVideos.map((v) => v.id).toList();
    return await deleteMultipleVideos(videoIds);
  }

  /// Obtém estatísticas de armazenamento
  Future<VideoStorageStats> getStorageStats(int? cameraId) async {
    try {
      final recordingsDir = await _getRecordingsDirectory();
      final files = await recordingsDir.list().where((entity) {
        if (entity is! File) return false;
        if (cameraId != null && !entity.path.contains('camera_${cameraId}_')) return false;
        return entity.path.endsWith('.mp4') || entity.path.endsWith('.avi');
      }).cast<File>().toList();
      
      int totalSize = 0;
      int totalCount = files.length;
      DateTime? oldestVideo;
      DateTime? newestVideo;
      
      for (final file in files) {
        final stats = await file.stat();
        totalSize += stats.size;
        
        if (oldestVideo == null || stats.modified.isBefore(oldestVideo)) {
          oldestVideo = stats.modified;
        }
        if (newestVideo == null || stats.modified.isAfter(newestVideo)) {
          newestVideo = stats.modified;
        }
      }
      
      return VideoStorageStats(
        totalVideos: totalCount,
        totalSizeBytes: totalSize,
        totalSizeMB: (totalSize / (1024 * 1024)).round(),
        oldestVideo: oldestVideo,
        newestVideo: newestVideo,
        averageFileSizeMB: totalCount > 0 ? (totalSize / totalCount / (1024 * 1024)).round() : 0,
      );
    } catch (e) {
      print('Video Management Error: Failed to get storage stats: $e');
      return const VideoStorageStats(
        totalVideos: 0,
        totalSizeBytes: 0,
        totalSizeMB: 0,
        oldestVideo: null,
        newestVideo: null,
        averageFileSizeMB: 0,
      );
    }
  }

  /// Gera thumbnail para um vídeo (placeholder - implementar com FFmpeg)
  Future<String?> _getThumbnailPath(String videoPath) async {
    try {
      // TODO: Implementar geração real de thumbnail com FFmpeg
      // Por enquanto, retornar null (sem thumbnail)
      return null;
    } catch (e) {
      print('Video Management Error: Failed to get thumbnail path: $e');
      return null;
    }
  }

  /// Obtém diretório de gravações
  Future<Directory> _getRecordingsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${appDir.path}/camera_recordings');
    
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    
    return recordingsDir;
  }

  /// Obtém diretório de thumbnails


  /// Exporta vídeo para galeria do dispositivo
  Future<bool> exportVideoToGallery(String videoId) async {
    try {
      final video = await getVideoById(videoId);
      if (video == null) return false;
      
      // TODO: Implementar exportação para galeria
      // Usar plugin como gallery_saver ou similar
      
      _eventController.add(VideoManagementEvent(
        type: VideoManagementEventType.videoExported,
        videoId: videoId,
        cameraId: video.cameraId,
        message: 'Vídeo exportado para galeria',
        timestamp: DateTime.now(),
      ));
      
      return true;
    } catch (e) {
      print('Video Management Error: Failed to export video $videoId: $e');
      return false;
    }
  }

  /// Compartilha vídeo
  Future<bool> shareVideo(String videoId) async {
    try {
      final video = await getVideoById(videoId);
      if (video == null) return false;
      
      // TODO: Implementar compartilhamento
      // Usar plugin como share_plus
      
      _eventController.add(VideoManagementEvent(
        type: VideoManagementEventType.videoShared,
        videoId: videoId,
        cameraId: video.cameraId,
        message: 'Vídeo compartilhado',
        timestamp: DateTime.now(),
      ));
      
      return true;
    } catch (e) {
      print('Video Management Error: Failed to share video $videoId: $e');
      return false;
    }
  }

  /// Implementa gravação cíclica - remove vídeos antigos quando necessário
  Future<void> performCyclicCleanup(int cameraId, {int maxSizeMB = 1000}) async {
    try {
      final videos = await getRecordedVideos(cameraId);
      if (videos.isEmpty) return;

      // Calcula o tamanho total atual
      int totalSizeBytes = videos.fold(0, (sum, video) => sum + video.fileSize);
      int maxSizeBytes = maxSizeMB * 1024 * 1024;

      if (totalSizeBytes <= maxSizeBytes) return;

      // Ordena por data (mais antigos primeiro)
      videos.sort((a, b) => a.recordingTime.compareTo(b.recordingTime));

      // Remove vídeos antigos até ficar abaixo do limite (mantém 80% do limite)
      int targetSizeBytes = (maxSizeBytes * 0.8).round();
      
      for (final video in videos) {
        if (totalSizeBytes <= targetSizeBytes) break;
        
        await deleteVideo(video.id);
        totalSizeBytes -= video.fileSize;
        print('Vídeo removido pela gravação cíclica: ${video.filename}');
      }
      
      // Salva estatísticas da limpeza
      await _saveCyclicCleanupStats(cameraId, videos.length - (await getRecordedVideos(cameraId)).length);
    } catch (e) {
      print('Erro na limpeza cíclica: $e');
    }
  }

  /// Verifica se é necessário fazer limpeza cíclica antes de gravar
  Future<bool> shouldPerformCyclicCleanup(int cameraId, int newVideoSizeMB, {int maxSizeMB = 1000}) async {
    try {
      final videos = await getRecordedVideos(cameraId);
      int totalSizeBytes = videos.fold(0, (sum, video) => sum + video.fileSize);
      int newVideoSizeBytes = newVideoSizeMB * 1024 * 1024;
      int maxSizeBytes = maxSizeMB * 1024 * 1024;
      
      return (totalSizeBytes + newVideoSizeBytes) > maxSizeBytes;
    } catch (e) {
      print('Erro ao verificar necessidade de limpeza cíclica: $e');
      return false;
    }
  }

  /// Salva estatísticas da limpeza cíclica
  Future<void> _saveCyclicCleanupStats(int cameraId, int videosRemoved) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'cyclic_cleanup_stats_$cameraId';
      final stats = {
        'lastCleanup': DateTime.now().toIso8601String(),
        'videosRemoved': videosRemoved,
        'totalCleanups': (prefs.getInt('${key}_total') ?? 0) + 1,
      };
      
      await prefs.setString(key, stats.toString());
      await prefs.setInt('${key}_total', stats['totalCleanups'] as int);
    } catch (e) {
      print('Erro ao salvar estatísticas de limpeza cíclica: $e');
    }
  }

  /// Obtém estatísticas da limpeza cíclica
  Future<Map<String, dynamic>> getCyclicCleanupStats(int cameraId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'cyclic_cleanup_stats_$cameraId';
      final totalCleanups = prefs.getInt('${key}_total') ?? 0;
      
      return {
        'lastCleanup': null,
        'videosRemoved': 0,
        'totalCleanups': totalCleanups,
      };
    } catch (e) {
      print('Erro ao obter estatísticas de limpeza cíclica: $e');
      return {
        'lastCleanup': null,
        'videosRemoved': 0,
        'totalCleanups': 0,
      };
    }
  }

  /// Dispose resources
  void dispose() {
    _eventController.close();
  }
}

/// Modelo de vídeo gravado
class RecordedVideo {
  final String id;
  final int cameraId;
  final String filename;
  final String filePath;
  final DateTime recordingTime;
  final int fileSize; // bytes
  final int? durationSeconds;
  final String format; // MP4, AVI, etc.
  final String? thumbnailPath;

  const RecordedVideo({
    required this.id,
    required this.cameraId,
    required this.filename,
    required this.filePath,
    required this.recordingTime,
    required this.fileSize,
    required this.durationSeconds,
    required this.format,
    required this.thumbnailPath,
  });

  String get fileSizeMB => (fileSize / (1024 * 1024)).toStringAsFixed(1);
  
  String get durationFormatted {
    if (durationSeconds == null) return 'Desconhecida';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cameraId': cameraId,
      'filename': filename,
      'filePath': filePath,
      'recordingTime': recordingTime.toIso8601String(),
      'fileSize': fileSize,
      'durationSeconds': durationSeconds,
      'format': format,
      'thumbnailPath': thumbnailPath,
    };
  }

  factory RecordedVideo.fromJson(Map<String, dynamic> json) {
    return RecordedVideo(
      id: json['id'] ?? '',
      cameraId: json['cameraId'] ?? 0,
      filename: json['filename'] ?? '',
      filePath: json['filePath'] ?? '',
      recordingTime: DateTime.parse(json['recordingTime'] ?? DateTime.now().toIso8601String()),
      fileSize: json['fileSize'] ?? 0,
      durationSeconds: json['durationSeconds'],
      format: json['format'] ?? 'MP4',
      thumbnailPath: json['thumbnailPath'],
    );
  }
}

/// Evento de gerenciamento de vídeo
class VideoManagementEvent {
  final VideoManagementEventType type;
  final String? videoId;
  final int cameraId;
  final String message;
  final DateTime timestamp;

  const VideoManagementEvent({
    required this.type,
    required this.videoId,
    required this.cameraId,
    required this.message,
    required this.timestamp,
  });
}

/// Tipos de eventos de gerenciamento de vídeo
enum VideoManagementEventType {
  videoDeleted,
  bulkDelete,
  videoExported,
  videoShared,
  error,
}

/// Estatísticas de armazenamento de vídeos
class VideoStorageStats {
  final int totalVideos;
  final int totalSizeBytes;
  final int totalSizeMB;
  final DateTime? oldestVideo;
  final DateTime? newestVideo;
  final int averageFileSizeMB;

  const VideoStorageStats({
    required this.totalVideos,
    required this.totalSizeBytes,
    required this.totalSizeMB,
    required this.oldestVideo,
    required this.newestVideo,
    required this.averageFileSizeMB,
  });
}