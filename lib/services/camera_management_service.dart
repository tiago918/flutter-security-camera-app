import 'dart:async';
import '../models/camera_models.dart';

/// Serviço para gerenciamento de câmeras
class CameraManagementService {
  static final CameraManagementService _instance = CameraManagementService._internal();
  factory CameraManagementService() => _instance;
  CameraManagementService._internal();

  final List<CameraData> _cameras = [];
  final StreamController<List<CameraData>> _camerasController = StreamController<List<CameraData>>.broadcast();

  /// Stream de câmeras
  Stream<List<CameraData>> get camerasStream => _camerasController.stream;

  /// Lista de câmeras
  List<CameraData> get cameras => List.unmodifiable(_cameras);

  /// Callback para notificar mudanças nas câmeras
  Function(List<CameraData>)? onCamerasChanged;

  /// Adiciona uma nova câmera
  Future<bool> addCamera(CameraData camera) async {
    try {
      // Verifica se já existe uma câmera com o mesmo ID
      if (_cameras.any((c) => c.id == camera.id)) {
        print('Câmera com ID ${camera.id} já existe');
        return false;
      }

      _cameras.add(camera);
      _notifyCamerasChanged();
      print('Câmera ${camera.name} adicionada com sucesso');
      return true;
    } catch (e) {
      print('Erro ao adicionar câmera: $e');
      return false;
    }
  }

  /// Remove uma câmera
  Future<bool> removeCamera(String cameraId) async {
    try {
      final index = _cameras.indexWhere((c) => c.id.toString() == cameraId);
      if (index == -1) {
        print('Câmera com ID $cameraId não encontrada');
        return false;
      }

      final camera = _cameras.removeAt(index);
      _notifyCamerasChanged();
      print('Câmera ${camera.name} removida com sucesso');
      return true;
    } catch (e) {
      print('Erro ao remover câmera: $e');
      return false;
    }
  }

  /// Atualiza uma câmera existente
  Future<bool> updateCamera(CameraData updatedCamera) async {
    try {
      final index = _cameras.indexWhere((c) => c.id == updatedCamera.id);
      if (index == -1) {
        print('Câmera com ID ${updatedCamera.id} não encontrada');
        return false;
      }

      _cameras[index] = updatedCamera;
      _notifyCamerasChanged();
      print('Câmera ${updatedCamera.name} atualizada com sucesso');
      return true;
    } catch (e) {
      print('Erro ao atualizar câmera: $e');
      return false;
    }
  }

  /// Obtém uma câmera por ID
  CameraData? getCameraById(String cameraId) {
    try {
      return _cameras.firstWhere((c) => c.id.toString() == cameraId);
    } catch (e) {
      return null;
    }
  }

  /// Obtém câmeras por tipo (baseado no protocolo preferido)
  List<CameraData> getCamerasByType(String type) {
    return _cameras.where((c) => c.portConfiguration.preferredProtocol.toLowerCase() == type.toLowerCase()).toList();
  }

  /// Obtém câmeras online
  List<CameraData> getOnlineCameras() {
    // Esta implementação seria integrada com o CameraHealthService
    return _cameras; // Por enquanto retorna todas
  }

  /// Obtém câmeras offline
  List<CameraData> getOfflineCameras() {
    // Esta implementação seria integrada com o CameraHealthService
    return []; // Por enquanto retorna lista vazia
  }

  /// Carrega câmeras salvas
  Future<void> loadSavedCameras() async {
    try {
      // Implementação para carregar câmeras do armazenamento local
      // Por enquanto não faz nada
      print('Carregando câmeras salvas...');
    } catch (e) {
      print('Erro ao carregar câmeras salvas: $e');
    }
  }

  /// Salva câmeras
  Future<void> saveCameras() async {
    try {
      // Implementação para salvar câmeras no armazenamento local
      // Por enquanto não faz nada
      print('Salvando câmeras...');
    } catch (e) {
      print('Erro ao salvar câmeras: $e');
    }
  }

  /// Testa conexão com uma câmera
  Future<bool> testCameraConnection(CameraData camera) async {
    try {
      // Implementação básica de teste de conexão
      print('Testando conexão com câmera ${camera.name}');
      
      // Aqui seria implementada a lógica real de teste
      // Por enquanto simula sucesso
      await Future.delayed(Duration(seconds: 1));
      return true;
    } catch (e) {
      print('Erro ao testar conexão: $e');
      return false;
    }
  }

  /// Notifica mudanças nas câmeras
  void _notifyCamerasChanged() {
    _camerasController.add(_cameras);
    onCamerasChanged?.call(_cameras);
  }

  /// Limpa todas as câmeras
  void clearAllCameras() {
    _cameras.clear();
    _notifyCamerasChanged();
  }

  /// Dispose do serviço
  void dispose() {
    _camerasController.close();
    onCamerasChanged = null;
  }
}