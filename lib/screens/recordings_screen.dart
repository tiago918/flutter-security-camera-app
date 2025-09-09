import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../widgets/dialogs/dialogs.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen>
    with TickerProviderStateMixin {
  final RecordingService _recordingService = RecordingService();
  
  List<Recording> _recordings = [];
  List<Recording> _filteredRecordings = [];
  List<Recording> _selectedRecordings = [];
  
  String _searchQuery = '';
  String _selectedCamera = 'Todas';
  String _sortBy = 'Data (Mais Recente)';
  bool _isSelectionMode = false;
  bool _isLoading = true;
  
  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;
  
  final List<String> _sortOptions = [
    'Data (Mais Recente)',
    'Data (Mais Antiga)',
    'Duração (Maior)',
    'Duração (Menor)',
    'Tamanho (Maior)',
    'Tamanho (Menor)',
    'Nome (A-Z)',
    'Nome (Z-A)',
  ];
  
  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _loadRecordings();
  }
  
  @override
  void dispose() {
    _fabAnimationController.dispose();
    super.dispose();
  }
  
  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    
    try {
      // TODO: Carregar gravações do serviço
      await Future.delayed(const Duration(seconds: 1)); // Simular carregamento
      
      // Dados de exemplo
      _recordings = [
        Recording(
          id: '1',
          cameraId: 'cam1',
          cameraName: 'Câmera Entrada',
          fileName: 'entrada_20240115_143022.mp4',
          filePath: '/storage/recordings/entrada_20240115_143022.mp4',
          startTime: DateTime.now().subtract(const Duration(hours: 2)),
          endTime: DateTime.now().subtract(const Duration(hours: 2, minutes: -5)),
          duration: const Duration(minutes: 5),
          fileSize: 45 * 1024 * 1024, // 45 MB
          recordingType: RecordingType.motion,
          thumbnailPath: '/storage/thumbnails/entrada_20240115_143022.jpg',
        ),
        Recording(
          id: '2',
          cameraId: 'cam2',
          cameraName: 'Câmera Garagem',
          fileName: 'garagem_20240115_120000.mp4',
          filePath: '/storage/recordings/garagem_20240115_120000.mp4',
          startTime: DateTime.now().subtract(const Duration(hours: 5)),
          endTime: DateTime.now().subtract(const Duration(hours: 5, minutes: -10)),
          duration: const Duration(minutes: 10),
          fileSize: 89 * 1024 * 1024, // 89 MB
          recordingType: RecordingType.manual,
          thumbnailPath: '/storage/thumbnails/garagem_20240115_120000.jpg',
        ),
        Recording(
          id: '3',
          cameraId: 'cam1',
          cameraName: 'Câmera Entrada',
          fileName: 'entrada_20240114_220000.mp4',
          filePath: '/storage/recordings/entrada_20240114_220000.mp4',
          startTime: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
          endTime: DateTime.now().subtract(const Duration(days: 1, hours: 2, minutes: -3)),
          duration: const Duration(minutes: 3),
          fileSize: 28 * 1024 * 1024, // 28 MB
          recordingType: RecordingType.scheduled,
          thumbnailPath: '/storage/thumbnails/entrada_20240114_220000.jpg',
        ),
      ];
      
      _applyFilters();
    } catch (e) {
      _showSnackBar('Erro ao carregar gravações: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  void _applyFilters() {
    _filteredRecordings = _recordings.where((recording) {
      // Filtro por câmera
      if (_selectedCamera != 'Todas' && recording.cameraName != _selectedCamera) {
        return false;
      }
      
      // Filtro por busca
      if (_searchQuery.isNotEmpty) {
        return recording.fileName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               recording.cameraName.toLowerCase().contains(_searchQuery.toLowerCase());
      }
      
      return true;
    }).toList();
    
    // Aplicar ordenação
    _sortRecordings();
    
    setState(() {});
  }
  
  void _sortRecordings() {
    switch (_sortBy) {
      case 'Data (Mais Recente)':
        _filteredRecordings.sort((a, b) => b.startTime.compareTo(a.startTime));
        break;
      case 'Data (Mais Antiga)':
        _filteredRecordings.sort((a, b) => a.startTime.compareTo(b.startTime));
        break;
      case 'Duração (Maior)':
        _filteredRecordings.sort((a, b) => b.duration.compareTo(a.duration));
        break;
      case 'Duração (Menor)':
        _filteredRecordings.sort((a, b) => a.duration.compareTo(b.duration));
        break;
      case 'Tamanho (Maior)':
        _filteredRecordings.sort((a, b) => b.fileSize.compareTo(a.fileSize));
        break;
      case 'Tamanho (Menor)':
        _filteredRecordings.sort((a, b) => a.fileSize.compareTo(b.fileSize));
        break;
      case 'Nome (A-Z)':
        _filteredRecordings.sort((a, b) => a.fileName.compareTo(b.fileName));
        break;
      case 'Nome (Z-A)':
        _filteredRecordings.sort((a, b) => b.fileName.compareTo(a.fileName));
        break;
    }
  }
  
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedRecordings.clear();
        _fabAnimationController.reverse();
      } else {
        _fabAnimationController.forward();
      }
    });
  }
  
  void _toggleRecordingSelection(Recording recording) {
    setState(() {
      if (_selectedRecordings.contains(recording)) {
        _selectedRecordings.remove(recording);
      } else {
        _selectedRecordings.add(recording);
      }
      
      if (_selectedRecordings.isEmpty && _isSelectionMode) {
        _toggleSelectionMode();
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedRecordings.length} selecionadas')
            : const Text('Gravações'),
        elevation: 0,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _selectedRecordings.isNotEmpty
                      ? _deleteSelectedRecordings
                      : null,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _showSearchDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: _showFilterDialog,
                ),
                PopupMenuButton<String>(
                  onSelected: _handleMenuAction,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: Icon(Icons.refresh),
                        title: Text('Atualizar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'select',
                      child: ListTile(
                        leading: Icon(Icons.checklist),
                        title: Text('Selecionar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'storage',
                      child: ListTile(
                        leading: Icon(Icons.storage),
                        title: Text('Armazenamento'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: _isSelectionMode
          ? ScaleTransition(
              scale: _fabAnimation,
              child: FloatingActionButton.extended(
                onPressed: _shareSelectedRecordings,
                icon: const Icon(Icons.share),
                label: const Text('Compartilhar'),
              ),
            )
          : null,
    );
  }
  
  Widget _buildBody() {
    if (_filteredRecordings.isEmpty) {
      return _buildEmptyState();
    }
    
    return Column(
      children: [
        _buildSummaryCard(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _filteredRecordings.length,
            itemBuilder: (context, index) {
              final recording = _filteredRecordings[index];
              return _buildRecordingCard(recording);
            },
          ),
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
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma gravação encontrada',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedCamera != 'Todas'
                ? 'Tente ajustar os filtros de busca'
                : 'As gravações aparecerão aqui quando disponíveis',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_searchQuery.isNotEmpty || _selectedCamera != 'Todas')
            FilledButton.tonal(
              onPressed: _clearFilters,
              child: const Text('Limpar Filtros'),
            ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCard() {
    final totalSize = _filteredRecordings.fold<int>(
      0,
      (sum, recording) => sum + recording.fileSize,
    );
    
    final totalDuration = _filteredRecordings.fold<Duration>(
      Duration.zero,
      (sum, recording) => sum + recording.duration,
    );
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryItem(
                'Gravações',
                '${_filteredRecordings.length}',
                Icons.video_library,
              ),
            ),
            Expanded(
              child: _buildSummaryItem(
                'Duração Total',
                _formatDuration(totalDuration),
                Icons.access_time,
              ),
            ),
            Expanded(
              child: _buildSummaryItem(
                'Tamanho Total',
                _formatFileSize(totalSize),
                Icons.storage,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }
  
  Widget _buildRecordingCard(Recording recording) {
    final isSelected = _selectedRecordings.contains(recording);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _isSelectionMode
            ? _toggleRecordingSelection(recording)
            : _playRecording(recording),
        onLongPress: () {
          if (!_isSelectionMode) {
            _toggleSelectionMode();
          }
          _toggleRecordingSelection(recording);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleRecordingSelection(recording),
                  ),
                ),
              _buildThumbnail(recording),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            recording.cameraName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        _buildRecordingTypeChip(recording.recordingType),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(recording.startTime),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(recording.duration),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.storage,
                          size: 16,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatFileSize(recording.fileSize),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_isSelectionMode)
                PopupMenuButton<String>(
                  onSelected: (action) => _handleRecordingAction(action, recording),
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
                      value: 'download',
                      child: ListTile(
                        leading: Icon(Icons.download),
                        title: Text('Download'),
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
                      value: 'info',
                      child: ListTile(
                        leading: Icon(Icons.info),
                        title: Text('Informações'),
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
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildThumbnail(Recording recording) {
    return Container(
      width: 80,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceVariant,
      ),
      child: Stack(
        children: [
          // TODO: Carregar thumbnail real
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                ],
              ),
            ),
          ),
          Center(
            child: Icon(
              Icons.play_circle_filled,
              color: Colors.white,
              size: 24,
            ),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(recording.duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRecordingTypeChip(RecordingType type) {
    Color color;
    String label;
    IconData icon;
    
    switch (type) {
      case RecordingType.motion:
        color = Colors.orange;
        label = 'Movimento';
        icon = Icons.motion_photos_on;
        break;
      case RecordingType.manual:
        color = Colors.blue;
        label = 'Manual';
        icon = Icons.radio_button_checked;
        break;
      case RecordingType.scheduled:
        color = Colors.green;
        label = 'Agendada';
        icon = Icons.schedule;
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buscar Gravações'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Digite o nome da câmera ou arquivo...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
              _applyFilters();
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _applyFilters();
              });
              Navigator.pop(context);
            },
            child: const Text('Limpar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
  
  void _showFilterDialog() {
    final cameras = ['Todas'] + _recordings.map((r) => r.cameraName).toSet().toList();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtros'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCamera,
              decoration: const InputDecoration(
                labelText: 'Câmera',
                border: OutlineInputBorder(),
              ),
              items: cameras.map((camera) {
                return DropdownMenuItem(
                  value: camera,
                  child: Text(camera),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCamera = value!;
                  _applyFilters();
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _sortBy,
              decoration: const InputDecoration(
                labelText: 'Ordenar por',
                border: OutlineInputBorder(),
              ),
              items: _sortOptions.map((option) {
                return DropdownMenuItem(
                  value: option,
                  child: Text(option),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _sortBy = value!;
                  _applyFilters();
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _clearFilters,
            child: const Text('Limpar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
  
  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedCamera = 'Todas';
      _sortBy = 'Data (Mais Recente)';
      _applyFilters();
    });
    Navigator.pop(context);
  }
  
  void _selectAll() {
    setState(() {
      if (_selectedRecordings.length == _filteredRecordings.length) {
        _selectedRecordings.clear();
      } else {
        _selectedRecordings = List.from(_filteredRecordings);
      }
    });
  }
  
  void _handleMenuAction(String action) {
    switch (action) {
      case 'refresh':
        _loadRecordings();
        break;
      case 'select':
        _toggleSelectionMode();
        break;
      case 'storage':
        _showStorageInfo();
        break;
    }
  }
  
  void _handleRecordingAction(String action, Recording recording) {
    switch (action) {
      case 'play':
        _playRecording(recording);
        break;
      case 'download':
        _downloadRecording(recording);
        break;
      case 'share':
        _shareRecording(recording);
        break;
      case 'info':
        _showRecordingInfo(recording);
        break;
      case 'delete':
        _deleteRecording(recording);
        break;
    }
  }
  
  void _playRecording(Recording recording) {
    // TODO: Implementar reprodução de vídeo
    _showSnackBar('Reproduzindo: ${recording.fileName}');
  }
  
  void _downloadRecording(Recording recording) {
    // TODO: Implementar download
    _showSnackBar('Download iniciado: ${recording.fileName}');
  }
  
  void _shareRecording(Recording recording) {
    // TODO: Implementar compartilhamento
    _showSnackBar('Compartilhando: ${recording.fileName}');
  }
  
  void _shareSelectedRecordings() {
    // TODO: Implementar compartilhamento múltiplo
    _showSnackBar('Compartilhando ${_selectedRecordings.length} gravações');
  }
  
  void _deleteRecording(Recording recording) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Gravação'),
        content: Text('Deseja excluir a gravação "${recording.fileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _recordings.remove(recording);
                _applyFilters();
              });
              _showSnackBar('Gravação excluída');
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
  
  void _deleteSelectedRecordings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Gravações'),
        content: Text(
          'Deseja excluir ${_selectedRecordings.length} gravações selecionadas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                for (final recording in _selectedRecordings) {
                  _recordings.remove(recording);
                }
                _selectedRecordings.clear();
                _applyFilters();
              });
              _toggleSelectionMode();
              _showSnackBar('Gravações excluídas');
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
  
  void _showRecordingInfo(Recording recording) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Informações da Gravação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Câmera:', recording.cameraName),
            _buildInfoRow('Arquivo:', recording.fileName),
            _buildInfoRow('Data/Hora:', _formatDateTime(recording.startTime)),
            _buildInfoRow('Duração:', _formatDuration(recording.duration)),
            _buildInfoRow('Tamanho:', _formatFileSize(recording.fileSize)),
            _buildInfoRow('Tipo:', _getRecordingTypeLabel(recording.recordingType)),
            _buildInfoRow('Caminho:', recording.filePath),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
  
  void _showStorageInfo() {
    final totalSize = _recordings.fold<int>(
      0,
      (sum, recording) => sum + recording.fileSize,
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Informações de Armazenamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total de gravações: ${_recordings.length}'),
            Text('Espaço usado: ${_formatFileSize(totalSize)}'),
            const SizedBox(height: 16),
            const Text('Distribuição por tipo:'),
            const SizedBox(height: 8),
            ..._getRecordingTypeStats(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
  
  List<Widget> _getRecordingTypeStats() {
    final stats = <RecordingType, int>{};
    for (final recording in _recordings) {
      stats[recording.recordingType] = (stats[recording.recordingType] ?? 0) + 1;
    }
    
    return stats.entries.map((entry) {
      return Text(
        '• ${_getRecordingTypeLabel(entry.key)}: ${entry.value}',
      );
    }).toList();
  }
  
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
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
  
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  String _getRecordingTypeLabel(RecordingType type) {
    switch (type) {
      case RecordingType.motion:
        return 'Detecção de Movimento';
      case RecordingType.manual:
        return 'Gravação Manual';
      case RecordingType.scheduled:
        return 'Gravação Agendada';
    }
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}