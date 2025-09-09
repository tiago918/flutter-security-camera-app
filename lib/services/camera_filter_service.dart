import 'dart:async';
import '../models/camera_models.dart';

class CameraFilterService {
  static final CameraFilterService _instance = CameraFilterService._internal();
  factory CameraFilterService() => _instance;
  CameraFilterService._internal();

  // Controlador de stream para notificar mudanças nos filtros
  final StreamController<List<CameraData>> _filteredCamerasController = 
      StreamController<List<CameraData>>.broadcast();
  
  Stream<List<CameraData>> get filteredCameras => _filteredCamerasController.stream;

  // Lista original de câmeras
  List<CameraData> _allCameras = [];
  
  // Lista filtrada de câmeras
  List<CameraData> _filteredCameras = [];
  
  // Filtros ativos
  String _searchQuery = '';
  bool _onlineOnlyFilter = false;
  bool _recordingOnlyFilter = false;
  bool _motionDetectionOnlyFilter = false;
  CameraSortBy _sortBy = CameraSortBy.name;
  bool _sortAscending = true;

  // Getters para os filtros atuais
  String get searchQuery => _searchQuery;
  bool get onlineOnlyFilter => _onlineOnlyFilter;
  bool get recordingOnlyFilter => _recordingOnlyFilter;
  bool get motionDetectionOnlyFilter => _motionDetectionOnlyFilter;
  CameraSortBy get sortBy => _sortBy;
  bool get sortAscending => _sortAscending;
  
  List<CameraData> get filteredCamerasData => List.unmodifiable(_filteredCameras);
  List<CameraData> get allCameras => List.unmodifiable(_allCameras);

  // Atualizar lista de câmeras
  void updateCameras(List<CameraData> cameras) {
    _allCameras = List.from(cameras);
    _applyFilters();
  }

  // Definir filtro de busca por texto
  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase().trim();
    _applyFilters();
  }

  // Filtro por status removido - propriedade não existe no CameraData atual

  // Definir filtro apenas online
  void setOnlineOnlyFilter(bool onlineOnly) {
    _onlineOnlyFilter = onlineOnly;
    _applyFilters();
  }

  // Definir filtro apenas gravando
  void setRecordingOnlyFilter(bool recordingOnly) {
    _recordingOnlyFilter = recordingOnly;
    _applyFilters();
  }

  // Definir filtro apenas com detecção de movimento
  void setMotionDetectionOnlyFilter(bool motionDetectionOnly) {
    _motionDetectionOnlyFilter = motionDetectionOnly;
    _applyFilters();
  }

  // Definir ordenação
  void setSorting(CameraSortBy sortBy, {bool? ascending}) {
    _sortBy = sortBy;
    if (ascending != null) {
      _sortAscending = ascending;
    }
    _applyFilters();
  }

  // Alternar direção da ordenação
  void toggleSortDirection() {
    _sortAscending = !_sortAscending;
    _applyFilters();
  }

  // Limpar todos os filtros
  void clearAllFilters() {
    _searchQuery = '';
    _onlineOnlyFilter = false;
    _recordingOnlyFilter = false;
    _motionDetectionOnlyFilter = false;
    _sortBy = CameraSortBy.name;
    _sortAscending = true;
    _applyFilters();
  }

  // Aplicar todos os filtros
  void _applyFilters() {
    List<CameraData> filtered = List.from(_allCameras);

    // Filtro de busca por texto
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((camera) {
        return camera.name.toLowerCase().contains(_searchQuery) ||
               (camera.host?.toLowerCase().contains(_searchQuery) ?? false) ||
               (camera.streamUrl?.toLowerCase().contains(_searchQuery) ?? false);
      }).toList();
    }

    // Filtros removidos - propriedades não existem no CameraData atual

    // Aplicar ordenação
    _sortCameras(filtered);

    _filteredCameras = filtered;
    _filteredCamerasController.add(_filteredCameras);
  }

  // Ordenar câmeras
  void _sortCameras(List<CameraData> cameras) {
    cameras.sort((a, b) {
      int comparison = 0;
      
      switch (_sortBy) {
        case CameraSortBy.name:
          comparison = a.name.compareTo(b.name);
          break;
        case CameraSortBy.host:
          comparison = (a.host ?? '').compareTo(b.host ?? '');
          break;
        case CameraSortBy.status:
        case CameraSortBy.lastSeen:
        case CameraSortBy.addedDate:
          // Propriedades não disponíveis no CameraData atual
          comparison = a.name.compareTo(b.name);
          break;
      }
      
      return _sortAscending ? comparison : -comparison;
    });
  }

  // Obter estatísticas das câmeras
  CameraStatistics getStatistics() {
    final total = _allCameras.length;
    
    return CameraStatistics(
      total: total,
      online: 0, // Propriedade não disponível
      offline: 0, // Propriedade não disponível
      error: 0, // Propriedade não disponível
      recording: 0, // Propriedade não disponível
      motionDetection: 0, // Propriedade não disponível
      filtered: _filteredCameras.length,
    );
  }

  // Buscar câmeras por critérios específicos
  List<CameraData> searchCameras({
    String? nameContains,
    String? hostContains,
  }) {
    return _allCameras.where((camera) {
      if (nameContains != null && 
          !camera.name.toLowerCase().contains(nameContains.toLowerCase())) {
        return false;
      }
      
      if (hostContains != null && 
          !(camera.host?.toLowerCase().contains(hostContains.toLowerCase()) ?? false)) {
        return false;
      }
      
      return true;
    }).toList();
  }

  // Métodos removidos - propriedades não existem no CameraData atual

  // Dispose do serviço
  void dispose() {
    _filteredCamerasController.close();
  }
}

/// Enum para tipos de ordenação
enum CameraSortBy {
  name,
  host,
  status,
  lastSeen,
  addedDate,
}

/// Classe para estatísticas das câmeras
class CameraStatistics {
  final int total;
  final int online;
  final int offline;
  final int error;
  final int recording;
  final int motionDetection;
  final int filtered;

  CameraStatistics({
    required this.total,
    required this.online,
    required this.offline,
    required this.error,
    required this.recording,
    required this.motionDetection,
    required this.filtered,
  });

  @override
  String toString() {
    return 'CameraStatistics(total: $total, online: $online, offline: $offline, error: $error, recording: $recording, motionDetection: $motionDetection, filtered: $filtered)';
  }
}