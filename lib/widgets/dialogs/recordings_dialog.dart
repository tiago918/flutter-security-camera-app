import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/services.dart';

class RecordingsDialog extends StatefulWidget {
  final CameraModel camera;
  final Function(Recording)? onPlayRecording;
  final Function(Recording)? onDownloadRecording;
  final Function(Recording)? onDeleteRecording;

  const RecordingsDialog({
    super.key,
    required this.camera,
    this.onPlayRecording,
    this.onDownloadRecording,
    this.onDeleteRecording,
  });

  @override
  State<RecordingsDialog> createState() => _RecordingsDialogState();
}

class _RecordingsDialogState extends State<RecordingsDialog> {
  List<Recording> _recordings = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';
  DateTime? _selectedDate;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    
    try {
      // Simular carregamento de gravações
      await Future.delayed(const Duration(seconds: 1));
      
      // Dados simulados
      _recordings = [
        Recording(
          id: '1',
          cameraId: widget.camera.id,
          fileName: 'motion_detection_001.mp4',
          filePath: '/recordings/motion_detection_001.mp4',
          startTime: DateTime.now().subtract(const Duration(hours: 2)),
          endTime: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)),
          duration: const Duration(minutes: 15),
          fileSize: 125000000, // 125MB
          recordingType: RecordingType.motion,
          thumbnailPath: '/thumbnails/motion_001.jpg',
        ),
        Recording(
          id: '2',
          cameraId: widget.camera.id,
          fileName: 'scheduled_002.mp4',
          filePath: '/recordings/scheduled_002.mp4',
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          endTime: DateTime.now().subtract(const Duration(days: 1)).add(const Duration(hours: 1)),
          duration: const Duration(hours: 1),
          fileSize: 500000000, // 500MB
          recordingType: RecordingType.scheduled,
          thumbnailPath: '/thumbnails/scheduled_002.jpg',
        ),
        Recording(
          id: '3',
          cameraId: widget.camera.id,
          fileName: 'manual_003.mp4',
          filePath: '/recordings/manual_003.mp4',
          startTime: DateTime.now().subtract(const Duration(days: 2)),
          endTime: DateTime.now().subtract(const Duration(days: 2)).add(const Duration(minutes: 30)),
          duration: const Duration(minutes: 30),
          fileSize: 250000000, // 250MB
          recordingType: RecordingType.manual,
          thumbnailPath: '/thumbnails/manual_003.jpg',
        ),
      ];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar gravações: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Recording> get _filteredRecordings {
    var filtered = _recordings.where((recording) {
      // Filtro por tipo
      if (_selectedFilter != 'all') {
        switch (_selectedFilter) {
          case 'motion':
            if (recording.recordingType != RecordingType.motion) return false;
            break;
          case 'scheduled':
            if (recording.recordingType != RecordingType.scheduled) return false;
            break;
          case 'manual':
            if (recording.recordingType != RecordingType.manual) return false;
            break;
        }
      }
      
      // Filtro por data
      if (_selectedDate != null) {
        final recordingDate = DateTime(
          recording.startTime.year,
          recording.startTime.month,
          recording.startTime.day,
        );
        final filterDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
        );
        if (!recordingDate.isAtSameMomentAs(filterDate)) return false;
      }
      
      // Filtro por busca
      if (_searchController.text.isNotEmpty) {
        final query = _searchController.text.toLowerCase();
        if (!recording.fileName.toLowerCase().contains(query)) return false;
      }
      
      return true;
    }).toList();
    
    // Ordenar por data (mais recente primeiro)
    filtered.sort((a, b) => b.startTime.compareTo(a.startTime));
    
    return filtered;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  IconData _getRecordingTypeIcon(RecordingType type) {
    switch (type) {
      case RecordingType.motion:
        return Icons.motion_photos_on;
      case RecordingType.scheduled:
        return Icons.schedule;
      case RecordingType.manual:
        return Icons.radio_button_checked;
    }
  }

  Color _getRecordingTypeColor(RecordingType type) {
    switch (type) {
      case RecordingType.motion:
        return Colors.orange;
      case RecordingType.scheduled:
        return Colors.blue;
      case RecordingType.manual:
        return Colors.green;
    }
  }

  String _getRecordingTypeLabel(RecordingType type) {
    switch (type) {
      case RecordingType.motion:
        return 'Movimento';
      case RecordingType.scheduled:
        return 'Agendada';
      case RecordingType.manual:
        return 'Manual';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.video_library,
                  color: Theme.of(context).primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gravações',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.camera.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Filters
            Row(
              children: [
                // Search
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Buscar gravações...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Type Filter
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedFilter,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos')),
                      DropdownMenuItem(value: 'motion', child: Text('Movimento')),
                      DropdownMenuItem(value: 'scheduled', child: Text('Agendada')),
                      DropdownMenuItem(value: 'manual', child: Text('Manual')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedFilter = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                
                // Date Filter
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => _selectedDate = date);
                    }
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _selectedDate != null
                        ? '${_selectedDate!.day}/${_selectedDate!.month}'
                        : 'Data',
                  ),
                ),
                if (_selectedDate != null)
                  IconButton(
                    onPressed: () => setState(() => _selectedDate = null),
                    icon: const Icon(Icons.clear, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _filteredRecordings.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.video_library_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhuma gravação encontrada',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredRecordings.length,
                          itemBuilder: (context, index) {
                            final recording = _filteredRecordings[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  width: 60,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    Icons.play_circle_outline,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        recording.fileName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getRecordingTypeColor(recording.recordingType).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _getRecordingTypeIcon(recording.recordingType),
                                            size: 12,
                                            color: _getRecordingTypeColor(recording.recordingType),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _getRecordingTypeLabel(recording.recordingType),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: _getRecordingTypeColor(recording.recordingType),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${recording.startTime.day}/${recording.startTime.month} ${recording.startTime.hour.toString().padLeft(2, '0')}:${recording.startTime.minute.toString().padLeft(2, '0')}',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Icon(
                                          Icons.timer,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDuration(recording.duration),
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Icon(
                                          Icons.storage,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatFileSize(recording.fileSize),
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'play':
                                        widget.onPlayRecording?.call(recording);
                                        break;
                                      case 'download':
                                        widget.onDownloadRecording?.call(recording);
                                        break;
                                      case 'delete':
                                        _showDeleteConfirmation(recording);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'play',
                                      child: Row(
                                        children: [
                                          Icon(Icons.play_arrow),
                                          SizedBox(width: 8),
                                          Text('Reproduzir'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'download',
                                      child: Row(
                                        children: [
                                          Icon(Icons.download),
                                          SizedBox(width: 8),
                                          Text('Download'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Excluir', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => widget.onPlayRecording?.call(recording),
                              ),
                            );
                          },
                        ),
            ),
            
            // Footer
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '${_filteredRecordings.length} gravação(ões) encontrada(s)',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Recording recording) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir a gravação "${recording.fileName}"?\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDeleteRecording?.call(recording);
              setState(() {
                _recordings.removeWhere((r) => r.id == recording.id);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Gravação excluída com sucesso'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
}