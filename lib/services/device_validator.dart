import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/camera_ports.dart';
import '../models/camera_device.dart';
import '../models/mdns_device.dart';
import 'onvif_service.dart';
import 'device_identification_service.dart';

/// Sistema de validação multi-camadas para dispositivos de câmera
/// Evita conexões em portas incorretas e valida protocolos
class DeviceValidator {
  static final DeviceValidator _instance = DeviceValidator._internal();
  factory DeviceValidator() => _instance;
  DeviceValidator._internal();

  final ONVIFService _onvifService = ONVIFService();
  final DeviceIdentificationService _identificationService = DeviceIdentificationService();
  
  static const Duration _validationTimeout = Duration(seconds: 5);
  static const Duration _quickTimeout = Duration(seconds: 2);
  
  /// Valida um dispositivo em múltiplas camadas
  Future<ValidationResult> validateDevice(CameraDevice device, {MDNSDevice? mdnsDevice}) async {
    print('[DeviceValidator] Validando dispositivo ${device.ip}:${device.port}');
    
    final result = ValidationResult(device: device);
    
    // Camada 1: Validação de conectividade básica e blacklist
    final connectivityResult = await _validateConnectivity(device, mdnsDevice: mdnsDevice);
    result.addLayer('connectivity', connectivityResult);
    
    if (!connectivityResult.isValid) {
      result.finalResult = false;
      result.reason = 'Falha na conectividade básica';
      return result;
    }
    
    // Camada 2: Validação de protocolo
    final protocolResult = await _validateProtocol(device);
    result.addLayer('protocol', protocolResult);
    
    if (!protocolResult.isValid) {
      result.finalResult = false;
      result.reason = 'Protocolo incompatível ou incorreto';
      return result;
    }
    
    // Camada 3: Validação de serviço de câmera
    final cameraServiceResult = await _validateCameraService(device);
    result.addLayer('camera_service', cameraServiceResult);
    
    if (!cameraServiceResult.isValid) {
      result.finalResult = false;
      result.reason = 'Não é um serviço de câmera válido';
      return result;
    }
    
    // Camada 4: Validação de streaming (se RTSP)
    if (device.protocol == 'RTSP') {
      final streamingResult = await _validateStreaming(device);
      result.addLayer('streaming', streamingResult);
      
      if (!streamingResult.isValid) {
        result.finalResult = false;
        result.reason = 'Stream RTSP não disponível';
        return result;
      }
    }
    
    result.finalResult = true;
    result.reason = 'Dispositivo validado com sucesso';
    return result;
  }
  
  /// Camada 1: Validação de Conectividade
  /// Verifica se o dispositivo responde na rede e não está na blacklist
  Future<LayerResult> _validateConnectivity(CameraDevice device, {MDNSDevice? mdnsDevice}) async {
    // Primeiro identifica o tipo de dispositivo
    if (mdnsDevice != null) {
      final identification = await _identificationService.identifyDevice(
        ip: device.ip,
        port: device.port,
        manufacturer: mdnsDevice.manufacturer,
        deviceName: mdnsDevice.name,
        serviceType: mdnsDevice.serviceType,
        serviceName: mdnsDevice.serviceName,
        txtRecords: mdnsDevice.txtRecords,
      );
      
      print('[DeviceValidator] Dispositivo ${device.ip}:${device.port} identificado como: ${identification.deviceType}');
      
      // Se não é uma câmera, filtra
      if (identification.deviceType != DeviceType.camera) {
        return LayerResult(
          isValid: false,
          message: 'Dispositivo não é uma câmera (${identification.deviceType})',
          details: {
            'host': device.ip,
            'port': device.port,
            'device_type': identification.deviceType.toString(),
            'confidence': identification.confidence,
            'device_name': mdnsDevice.name,
            'manufacturer': mdnsDevice.manufacturer,
            'service_type': mdnsDevice.serviceType,
          },
        );
      }
    }
    
    try {
      final socket = await Socket.connect(
        device.ip, 
        device.port, 
        timeout: _quickTimeout
      );
      await socket.close();
      
      return LayerResult(
        isValid: true,
        message: 'Conectividade OK',
        details: {'connection_time': DateTime.now().toString()}
      );
    } catch (e) {
      return LayerResult(
        isValid: false,
        message: 'Falha na conectividade: $e',
        details: {'error': e.toString()}
      );
    }
  }
  
  /// Camada 2: Validação de protocolo
  Future<LayerResult> _validateProtocol(CameraDevice device) async {
    switch (device.protocol) {
      case 'HTTP':
        return await _validateHTTPProtocol(device);
      case 'RTSP':
        return await _validateRTSPProtocol(device);
      case 'ONVIF':
        return await _validateONVIFProtocol(device);
      default:
        return LayerResult(
          isValid: false,
          message: 'Protocolo desconhecido: ${device.protocol}',
          details: {'protocol': device.protocol}
        );
    }
  }
  
  /// Validação específica para protocolo HTTP
  Future<LayerResult> _validateHTTPProtocol(CameraDevice device) async {
    try {
      final url = 'http://${device.ip}:${device.port}/';
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'CameraApp/1.0'}
      ).timeout(_validationTimeout);
      
      final isCamera = _isLikelyCameraResponse(response);
      
      return LayerResult(
        isValid: isCamera,
        message: isCamera ? 'HTTP válido para câmera' : 'HTTP não é de câmera',
        details: {
          'status_code': response.statusCode,
          'content_type': response.headers['content-type'] ?? 'unknown',
          'server': response.headers['server'] ?? 'unknown'
        }
      );
    } catch (e) {
      return LayerResult(
        isValid: false,
        message: 'Falha na validação HTTP: $e',
        details: {'error': e.toString()}
      );
    }
  }
  
  /// Validação específica para protocolo RTSP
  Future<LayerResult> _validateRTSPProtocol(CameraDevice device) async {
    try {
      final socket = await Socket.connect(
        device.ip, 
        device.port, 
        timeout: _validationTimeout
      );
      
      // Enviar comando RTSP OPTIONS
      final rtspRequest = 'OPTIONS rtsp://${device.ip}:${device.port}/ RTSP/1.0\r\n'
                         'CSeq: 1\r\n'
                         'User-Agent: CameraApp/1.0\r\n'
                         '\r\n';
      
      socket.write(rtspRequest);
      
      final completer = Completer<String>();
      final buffer = StringBuffer();
      
      socket.listen(
        (data) {
          buffer.write(String.fromCharCodes(data));
          if (buffer.toString().contains('\r\n\r\n')) {
            completer.complete(buffer.toString());
          }
        },
        onError: (error) => completer.completeError(error),
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        }
      );
      
      final response = await completer.future.timeout(_validationTimeout);
      await socket.close();
      
      final isRTSP = response.contains('RTSP/1.0') && response.contains('200 OK');
      
      return LayerResult(
        isValid: isRTSP,
        message: isRTSP ? 'RTSP válido' : 'Resposta RTSP inválida',
        details: {
          'response_preview': response.substring(0, response.length > 200 ? 200 : response.length),
          'has_rtsp_header': response.contains('RTSP/1.0'),
          'has_ok_status': response.contains('200 OK')
        }
      );
    } catch (e) {
      return LayerResult(
        isValid: false,
        message: 'Falha na validação RTSP: $e',
        details: {'error': e.toString()}
      );
    }
  }
  
  /// Validação específica para protocolo ONVIF
  Future<LayerResult> _validateONVIFProtocol(CameraDevice device) async {
    try {
      final url = 'http://${device.ip}:${device.port}/onvif/device_service';
      final soapEnvelope = '''
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <tds:GetDeviceInformation xmlns:tds="http://www.onvif.org/ver10/device/wsdl"/>
  </soap:Body>
</soap:Envelope>''';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/soap+xml',
          'SOAPAction': 'http://www.onvif.org/ver10/device/wsdl/GetDeviceInformation'
        },
        body: soapEnvelope
      ).timeout(_validationTimeout);
      
      final isONVIF = response.statusCode == 200 && 
                     response.body.contains('GetDeviceInformationResponse');
      
      return LayerResult(
        isValid: isONVIF,
        message: isONVIF ? 'ONVIF válido' : 'Resposta ONVIF inválida',
        details: {
          'status_code': response.statusCode,
          'has_onvif_response': response.body.contains('GetDeviceInformationResponse')
        }
      );
    } catch (e) {
      return LayerResult(
        isValid: false,
        message: 'Falha na validação ONVIF: $e',
        details: {'error': e.toString()}
      );
    }
  }
  
  /// Camada 3: Validação de serviço de câmera
  Future<LayerResult> _validateCameraService(CameraDevice device) async {
    // Verificar se o dispositivo tem características de câmera
    final cameraIndicators = <String>[];
    
    try {
      if (device.protocol == 'HTTP') {
        final url = 'http://${device.ip}:${device.port}/';
        final response = await http.get(Uri.parse(url)).timeout(_quickTimeout);
        
        final body = response.body.toLowerCase();
        final headers = response.headers;
        
        // Verificação rigorosa para roteadores
        if (_isRouterResponse(response)) {
          return LayerResult(
            isValid: false,
            message: 'Dispositivo identificado como roteador/gateway',
            details: {
              'status_code': response.statusCode,
              'filtered_reason': 'router_detected',
              'response_size': response.body.length,
            }
          );
        }
        
        // Verifica se a resposta HTTP indica um dispositivo não-câmera
        if (_blacklistService.isNonCameraHttpResponse(response.body)) {
          return LayerResult(
            isValid: false,
            message: 'Dispositivo identificado como não-câmera pela resposta HTTP',
            details: {
              'status_code': response.statusCode,
              'filtered_reason': 'non_camera_http_response',
              'response_size': response.body.length,
            }
          );
        }
        
        // Verificar indicadores de câmera no conteúdo
        if (body.contains('camera') || body.contains('video') || body.contains('stream')) {
          cameraIndicators.add('content_keywords');
        }
        
        // Verificar headers específicos de câmeras
        if (headers['server']?.toLowerCase().contains('camera') == true ||
            headers['server']?.toLowerCase().contains('ipcam') == true) {
          cameraIndicators.add('server_header');
        }
      }
      
      // Verificar se a porta é típica de câmeras
      if (CameraPorts.isStreamingPort(device.port) || 
          CameraPorts.isOnvifPort(device.port)) {
        cameraIndicators.add('typical_camera_port');
      }
      
      final isCamera = cameraIndicators.isNotEmpty;
      
      return LayerResult(
        isValid: isCamera,
        message: isCamera ? 'Serviço de câmera detectado' : 'Não parece ser uma câmera',
        details: {
          'indicators': cameraIndicators,
          'indicator_count': cameraIndicators.length
        }
      );
    } catch (e) {
      return LayerResult(
        isValid: false,
        message: 'Erro na validação de serviço: $e',
        details: {'error': e.toString()}
      );
    }
  }
  
  /// Camada 4: Validação de streaming
  Future<LayerResult> _validateStreaming(CameraDevice device) async {
    try {
      // Para RTSP, tentar obter descrição do stream
      final socket = await Socket.connect(
        device.ip, 
        device.port, 
        timeout: _validationTimeout
      );
      
      final describeRequest = 'DESCRIBE rtsp://${device.ip}:${device.port}/ RTSP/1.0\r\n'
                             'CSeq: 2\r\n'
                             'Accept: application/sdp\r\n'
                             '\r\n';
      
      socket.write(describeRequest);
      
      final completer = Completer<String>();
      final buffer = StringBuffer();
      
      socket.listen(
        (data) {
          buffer.write(String.fromCharCodes(data));
          if (buffer.toString().contains('\r\n\r\n')) {
            completer.complete(buffer.toString());
          }
        },
        onError: (error) => completer.completeError(error)
      );
      
      final response = await completer.future.timeout(_validationTimeout);
      await socket.close();
      
      final hasStream = response.contains('200 OK') && 
                       (response.contains('video') || response.contains('audio'));
      
      return LayerResult(
        isValid: hasStream,
        message: hasStream ? 'Stream disponível' : 'Stream não disponível',
        details: {
          'has_ok_status': response.contains('200 OK'),
          'has_media_info': response.contains('video') || response.contains('audio')
        }
      );
    } catch (e) {
      return LayerResult(
        isValid: false,
        message: 'Erro na validação de streaming: $e',
        details: {'error': e.toString()}
      );
    }
  }
  
  /// Verifica se a resposta HTTP é de um roteador
  bool _isRouterResponse(http.Response response) {
    final body = response.body.toLowerCase();
    final server = response.headers['server']?.toLowerCase() ?? '';
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    
    // Indicadores específicos de roteadores
    final routerIndicators = [
      // Títulos comuns de roteadores
      '<title>router', '<title>wireless', '<title>tp-link', '<title>d-link',
      '<title>netgear', '<title>linksys', '<title>asus', '<title>tenda',
      '<title>mercusys', '<title>intelbras', '<title>multilaser',
      
      // Conteúdo específico de interface de roteador
      'wireless settings', 'router configuration', 'admin panel',
      'network settings', 'wifi settings', 'dhcp settings',
      'port forwarding', 'firewall settings', 'wan settings',
      'lan settings', 'wireless security', 'access control',
      
      // Fabricantes de roteadores
      'tp-link', 'd-link', 'netgear', 'linksys', 'asus router',
      'tenda router', 'mercusys', 'intelbras router',
      
      // URLs típicas de roteadores
      '/cgi-bin/luci', '/userRpm/', '/webpages/', '/goform/',
      '/boaform/', '/goahead/', '/cgi-bin/webproc',
    ];
    
    // Verificar se contém indicadores de roteador
    for (final indicator in routerIndicators) {
      if (body.contains(indicator)) {
        return true;
      }
    }
    
    // Verificar server headers típicos de roteadores
    final routerServers = [
      'lighttpd', 'boa', 'goahead', 'mini_httpd', 'thttpd',
      'webserver', 'router', 'embedded'
    ];
    
    for (final serverType in routerServers) {
      if (server.contains(serverType)) {
        // Verificação adicional: se tem conteúdo HTML típico de roteador
        if (body.contains('router') || body.contains('wireless') || 
            body.contains('admin') || body.contains('configuration')) {
          return true;
        }
      }
    }
    
    return false;
  }
  
  /// Verifica se a resposta HTTP é provavelmente de uma câmera
  bool _isLikelyCameraResponse(http.Response response) {
    final body = response.body.toLowerCase();
    final server = response.headers['server']?.toLowerCase() ?? '';
    
    // Palavras-chave que indicam câmera
    final cameraKeywords = [
      'camera', 'ipcam', 'webcam', 'video', 'stream', 'onvif',
      'hikvision', 'dahua', 'axis', 'foscam', 'surveillance'
    ];}]}}}
    
    return cameraKeywords.any((keyword) => 
      body.contains(keyword) || server.contains(keyword)
    );
  }

  /// Verifica se um dispositivo deve ser filtrado pela blacklist
  bool shouldFilterDevice({
    String? ip,
    String? manufacturer,
    String? deviceName,
    String? serviceType,
    String? httpResponse,
    int? port,
    String? serviceName,
    Map<String, String>? txtRecords,
  }) {
    return _blacklistService.shouldFilterDevice(
      ip: ip,
      manufacturer: manufacturer,
      deviceName: deviceName,
      serviceType: serviceType,
      httpResponse: httpResponse,
      port: port,
      serviceName: serviceName,
      txtRecords: txtRecords,
    );
  }

  /// Obtém estatísticas de validação
  Map<String, dynamic> getValidationStats() {
    return {
      'validation_timeout': _validationTimeout.inSeconds,
      'quick_timeout': _quickTimeout.inSeconds,
      'supported_protocols': ['HTTP', 'RTSP', 'ONVIF'],
      'blacklist_stats': _blacklistService.getBlacklistStats(),
    };
  }
}

/// Resultado da validação multi-camadas
class ValidationResult {
  final CameraDevice device;
  final Map<String, LayerResult> layers = {};
  bool finalResult = false;
  String reason = '';
  
  ValidationResult({required this.device});
  
  void addLayer(String layerName, LayerResult result) {
    layers[layerName] = result;
  }
  
  @override
  String toString() {
    return 'ValidationResult(device: ${device.ip}:${device.port}, '
           'result: $finalResult, reason: $reason, layers: ${layers.length})';
  }
}

/// Resultado de uma camada de validação
class LayerResult {
  final bool isValid;
  final String message;
  final Map<String, dynamic> details;
  
  LayerResult({
    required this.isValid,
    required this.message,
    this.details = const {}
  });
  
  @override
  String toString() {
    return 'LayerResult(valid: $isValid, message: $message)';
  }
}