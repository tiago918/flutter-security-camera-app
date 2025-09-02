import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/camera_models.dart';
import '../services/video_management_service.dart';
import '../services/auto_recording_service.dart';
import '../services/onvif_playback_service.dart';
import '../widgets/video_player_widget.dart';

class RecordedVideosPage extends StatefulWidget {
  final CameraData camera;

  const RecordedVideosPage({
    super.key,
    required this.camera,
  });

  @override
  State<RecordedVideosPage> createState() => _RecordedVideosPageState();
}

class _RecordedVideosPageState extends State<RecordedVideosPage> {
  final VideoManagementService _videoService = VideoManagementService();
  final AutoRecordingService _autoRecordingService = AutoRecordingService();
  final OnvifPlaybackService _playbackService = OnvifPlaybackService(acceptSelfSigned: widget.camera.acceptSelfSigned);
  
  List<RecordedVideo> _videos = [];
  List<RecordingInfo> _onvifRecordings = [];
  VideoStorageStats? _storageStats;
  AutoRecordingStats? _recordingStats;
  bool _isLoading = true;
  bool _isSelectionMode = false;
  Set<String> _selectedVideos = {};
  String _sortBy = 'date'; // date, size, duration
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _loadStats();
  }

  Future<void> _loadVideos() async {
    try {
      final videos = await _videoService.getRecordedVideos(widget.camera.id);
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
      _sortVideos();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Erro ao carregar vídeos: $e');
    }
  }

  Future<void> _loadStats() async {
    try {
      final storageStats = await _videoService.getStorageStats(widget.camera.id);
      final recordingStats = await _autoRecordingService.getRecordingStats(widget.camera.id);
      
      setState(() {
        _storageStats = storageStats;
        _recordingStats = recordingStats;
      });
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  void _sortVideos() {
    setState(() {
      _videos.sort((a, b) {
        int comparison;
        switch (_sortBy) {
          case 'size':
            comparison = a.fileSize.compareTo(b.fileSize);
            break;
          case 'duration':
            final aDuration = a.durationSeconds ?? 0;
            final bDuration = b.durationSeconds ?? 0;
            comparison = aDuration.compareTo(bDuration);
            break;
          case 'date':
          default:
            comparison = a.recordingTime.compareTo(b.recordingTime);
            break;
        }
        return _sortAscending ? comparison : -comparison;
      });
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedVideos.clear();
      }
    });
  }

  void _toggleVideoSelection(String videoId) {
    setState(() {
      if (_selectedVideos.contains(videoId)) {
        _selectedVideos.remove(videoId);
      } else {
        _selectedVideos.add(videoId);
      }
    });
  }

  void _selectAllVideos() {
    setState(() {
      _selectedVideos = _videos.map((v) => v.id).toSet();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedVideos.clear();
    });
  }

  Future<void> _deleteSelectedVideos() async {
    if (_selectedVideos.isEmpty) return;
    
    final confirmed = await _showConfirmDialog(
      'Excluir Vídeos',
      'Tem certeza que deseja excluir ${_selectedVideos.length} vídeo(s) selecionado(s)?\n\nEsta ação não pode ser desfeita.',
    );
    
    if (confirmed) {
      try {
        final deletedCount = await _videoService.deleteMultipleVideos(_selectedVideos.toList());
        _showSuccessSnackBar('$deletedCount vídeo(s) excluído(s) com sucesso');
        
        setState(() {
          _selectedVideos.clear();
          _isSelectionMode = false;
        });
        
        await _loadVideos();
        await _loadStats();
      } catch (e) {
        _showErrorSnackBar('Erro ao excluir vídeos: $e');
      }
    }
  }

  Future<void> _deleteVideo(RecordedVideo video) async {
    final confirmed = await _showConfirmDialog(
      'Excluir Vídeo',
      'Tem certeza que deseja excluir o vídeo "${video.filename}"?\n\nEsta ação não pode ser desfeita.',
    );
    
    if (confirmed) {
      try {
        final success = await _videoService.deleteVideo(video.id);
        if (success) {
          _showSuccessSnackBar('Vídeo excluído com sucesso');
          await _loadVideos();
          await _loadStats();
        } else {
          _showErrorSnackBar('Falha ao excluir vídeo');
        }
      } catch (e) {
        _showErrorSnackBar('Erro ao excluir vídeo: $e');
      }
    }
  }

  Future<void> _playVideo(RecordedVideo video) async {
    // Converter RecordedVideo para RecordingInfo
     final recording = RecordingInfo(
       id: video.filename,
       filename: video.filename,
       startTime: video.recordingTime,
       endTime: video.recordingTime.add(Duration(seconds: video.durationSeconds ?? 0)),
       duration: Duration(seconds: video.durationSeconds ?? 0),
       sizeBytes: video.fileSize,
       recordingType: 'Motion', // Assumir tipo padrão
     );
    
    // Navegar para o player de vídeo
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerWidget(
          camera: widget.camera,
          recording: recording,
          localVideoPath: video.filePath, // Se disponível
        ),
      ),
    );
  }

  Future<void> _shareVideo(RecordedVideo video) async {
    try {
      final success = await _videoService.shareVideo(video.id);
      if (success) {
        _showSuccessSnackBar('Vídeo compartilhado');
      } else {
        _showErrorSnackBar('Falha ao compartilhar vídeo');
      }
    } catch (e) {
      _showErrorSnackBar('Erro ao compartilhar vídeo: $e');
    }
  }

  Future<void> _exportVideo(RecordedVideo video) async {
    try {
      final success = await _videoService.exportVideoToGallery(video.id);
      if (success) {
        _showSuccessSnackBar('Vídeo exportado para galeria');
      } else {
        _showErrorSnackBar('Falha ao exportar vídeo');
      }
    } catch (e) {
      _showErrorSnackBar('Erro ao exportar vídeo: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadVideo(RecordedVideo video) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Iniciando download: ${video.filename}'),
          duration: const Duration(seconds: 2),
        ),
      );
      
      final playbackService = OnvifPlaybackService(acceptSelfSigned: widget.camera.acceptSelfSigned);
      
      // Converter RecordedVideo para RecordingInfo
       final recording = RecordingInfo(
         id: video.filename,
         filename: video.filename,
         startTime: video.recordingTime,
         endTime: video.recordingTime.add(Duration(seconds: video.durationSeconds ?? 0)),
         duration: Duration(seconds: video.durationSeconds ?? 0),
         sizeBytes: video.fileSize,
         recordingType: 'Motion',
       );
      
      // Definir caminho de download
      final downloadPath = '/storage/emulated/0/Download/${video.filename}';
      
      // Tentar baixar o vídeo
      final success = await playbackService.downloadRecording(
        widget.camera,
        recording,
        downloadPath,
      );
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download concluído: ${video.filename}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha no download: ${video.filename}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro no download: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vídeos - ${widget.camera.name}'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAllVideos,
              tooltip: 'Selecionar todos',
            ),
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSelection,
              tooltip: 'Limpar seleção',
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedVideos.isNotEmpty ? _deleteSelectedVideos : null,
              tooltip: 'Excluir selecionados',
            ),
          ] else ...[
            PopupMenuButton<String>(
              onSelected: (value) {
                setState(() {
                  _sortBy = value;
                });
                _sortVideos();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'date',
                  child: Text('Ordenar por Data'),
                ),
                const PopupMenuItem(
                  value: 'size',
                  child: Text('Ordenar por Tamanho'),
                ),
                const PopupMenuItem(
                  value: 'duration',
                  child: Text('Ordenar por Duração'),
                ),
              ],
            ),
            IconButton(
              icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
              onPressed: () {
                setState(() {
                  _sortAscending = !_sortAscending;
                });
                _sortVideos();
              },
              tooltip: _sortAscending ? 'Crescente' : 'Decrescente',
            ),
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: _toggleSelectionMode,
              tooltip: 'Modo seleção',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadVideos();
              _loadStats();
            },
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_storageStats != null) _buildStatsCard(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _videos.isEmpty
                    ? _buildEmptyState()
                    : _buildVideosList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              icon: Icons.video_library,
              label: 'Vídeos',
              value: '${_storageStats!.totalVideos}',
            ),
            _buildStatItem(
              icon: Icons.storage,
              label: 'Tamanho',
              value: '${_storageStats!.totalSizeMB} MB',
            ),
            if (_storageStats!.newestVideo != null)
              _buildStatItem(
                icon: Icons.access_time,
                label: 'Último',
                value: DateFormat('dd/MM HH:mm').format(_storageStats!.newestVideo!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.blue[800]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum vídeo gravado',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Os vídeos gravados automaticamente\naparecerão aqui',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // Formata data e hora de forma clara
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final videoDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    String dateStr;
    if (videoDate == today) {
      dateStr = 'Hoje';
    } else if (videoDate == yesterday) {
      dateStr = 'Ontem';
    } else {
      dateStr = '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
    }
    
    final timeStr = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    return '$dateStr às $timeStr';
  }

  Widget _buildVideosList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final video = _videos[index];
        final isSelected = _selectedVideos.contains(video.id);
        
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            leading: _isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleVideoSelection(video.id),
                  )
                : CircleAvatar(
                    backgroundColor: Colors.blue[800],
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                    ),
                  ),
            title: Text(
              DateFormat('dd/MM/yyyy HH:mm:ss').format(video.recordingTime),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDateTime(video.recordingTime),
                  style: const TextStyle(color: Colors.blue, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text('Tamanho: ${video.fileSizeMB} MB'),
                if (video.durationSeconds != null)
                  Text('Duração: ${video.durationFormatted}'),
                Text('Formato: ${video.format}'),
              ],
            ),
            trailing: _isSelectionMode
                ? null
                : PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'play':
                          _playVideo(video);
                          break;
                        case 'share':
                          _shareVideo(video);
                          break;
                        case 'export':
                          _exportVideo(video);
                          break;
                        case 'download':
                          _downloadVideo(video);
                          break;
                        case 'delete':
                          _deleteVideo(video);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'play',
                        child: ListTile(
                          leading: Icon(Icons.play_arrow),
                          title: Text('Reproduzir'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                          leading: Icon(Icons.share),
                          title: Text('Compartilhar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          leading: Icon(Icons.download),
                          title: Text('Exportar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'download',
                        child: ListTile(
                          leading: Icon(Icons.file_download),
                          title: Text('Baixar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete, color: Colors.red),
                          title: Text('Excluir', style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
            onTap: _isSelectionMode
                ? () => _toggleVideoSelection(video.id)
                : () => _playVideo(video),
            selected: isSelected,
          ),
        );
      },
    );
  }
}