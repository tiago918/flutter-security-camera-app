import 'dart:async';
import 'dart:io';
import 'package:easy_onvif/onvif.dart';
import '../models/camera_models.dart';

class CameraHealthService {
  final Map<String, Timer> _healthCheckTimers = {};
  final Map<String, bool> _cameraStatus = {};
  
  // Callbacks para notificar mudanças de status
  Function(String cameraId, bool isOnline)? onStatusChanged;
  Function(String cameraId, bool isOnline)? onHealthChanged;
  
  /// Inicia o monitoramento de health check para uma câmera
  void startHealthCheck(CameraData camera) {
    // Para qualquer timer existente para esta câmera
    stopHealthCheck(camera.id.toString());
    
    // Inicia um novo timer
    _healthCheckTimers[camera.id.toString()] = Timer.periodic(
      const Duration(seconds: 30),
      (timer) => _performHealthCheck(camera),
    );
    
    // Executa o primeiro check imediatamente
    _performHealthCheck(camera);
  }
  
  /// Para o monitoramento de health check para uma câmera
  void stopHealthCheck(String cameraId) {
    _healthCheckTimers[cameraId]?.cancel();
    _healthCheckTimers.remove(cameraId);
    _cameraStatus.remove(cameraId);
  }
  
  /// Para todos os health checks
  void stopAllHealthChecks() {
    for (var timer in _healthCheckTimers.values) {
      timer.cancel();
    }
    _healthCheckTimers.clear();
    _cameraStatus.clear();
  }
  
  /// Executa um health check para uma câmera específica
  Future<void> _performHealthCheck(CameraData camera) async {
    bool isOnline = false;
    
    try {
      if (camera.capabilities?.hasEvents == true) {
        // Para câmeras ONVIF, testa a conexão ONVIF
        isOnline = await _checkOnvifHealth(camera);
      } else {
        // Para câmeras RTSP, testa a conectividade básica
        isOnline = await _checkRtspHealth(camera);
      }
    } catch (e) {
      isOnline = false;
    }
    
    // Atualiza o status se mudou
    if (_cameraStatus[camera.id.toString()] != isOnline) {
      _cameraStatus[camera.id.toString()] = isOnline;
      onStatusChanged?.call(camera.id.toString(), isOnline);
      onHealthChanged?.call(camera.id.toString(), isOnline);
    }
  }
  
  /// Verifica a saúde de uma câmera ONVIF
  Future<bool> _checkOnvifHealth(CameraData camera) async {
    try {
      final onvif = await Onvif.connect(
        host: camera.getHost(),
        username: camera.username ?? '',
        password: camera.password ?? '',
      ).timeout(const Duration(seconds: 10));
      
      // Tenta obter informações básicas do dispositivo
      await onvif.deviceManagement.getDeviceInformation()
          .timeout(const Duration(seconds: 5));
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Verifica a saúde de uma câmera RTSP
  Future<bool> _checkRtspHealth(CameraData camera) async {
    try {
      // Testa conectividade TCP básica com o IP da câmera
      final socket = await Socket.connect(
        camera.getHost(),
        554, // Porta RTSP padrão
        timeout: const Duration(seconds: 5),
      );
      
      await socket.close();
      return true;
    } catch (e) {
      // Se a porta 554 falhar, tenta a porta 80
      try {
        final socket = await Socket.connect(
          camera.getHost(),
          80,
          timeout: const Duration(seconds: 5),
        );
        
        await socket.close();
        return true;
      } catch (e2) {
        return false;
      }
    }
  }
  
  /// Obtém o status atual de uma câmera
  bool? getCameraStatus(String cameraId) {
    return _cameraStatus[cameraId];
  }
  
  /// Verifica se uma câmera está sendo monitorada
  bool isMonitoring(String cameraId) {
    return _healthCheckTimers.containsKey(cameraId);
  }
  
  /// Executa um health check manual para uma câmera
  Future<bool> checkCameraHealth(CameraData camera) async {
    try {
      if (camera.capabilities?.hasEvents == true) {
        return await _checkOnvifHealth(camera);
      } else {
        return await _checkRtspHealth(camera);
      }
    } catch (e) {
      return false;
    }
  }
  
  /// Limpa todos os recursos
  void dispose() {
    stopAllHealthChecks();
    onStatusChanged = null;
    onHealthChanged = null;
  }
}