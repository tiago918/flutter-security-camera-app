import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:udp/udp.dart';
import 'package:xml/xml.dart';

/// Modelo para dispositivo UPnP descoberto
class UPnPDevice {
  final String location;
  final String? server;
  final String? usn;
  final String? st;
  final String? ext;
  final int? maxAge;
  final DateTime discoveredAt;
  final String sourceAddress;
  
  // Informações do device description
  String? deviceType;
  String? friendlyName;
  String? manufacturer;
  String? manufacturerURL;
  String? modelDescription;
  String? modelName;
  String? modelNumber;
  String? modelURL;
  String? serialNumber;
  String? udn;
  String? presentationURL;
  List<UPnPServiceInfo> services = [];
  
  UPnPDevice({
    required this.location,
    this.server,
    this.usn,
    this.st,
    this.ext,
    this.maxAge,
    required this.discoveredAt,
    required this.sourceAddress,
  });
  
  /// Extrai IP do location URL
  String? get deviceIP {
    try {
      final uri = Uri.parse(location);
      return uri.host;
    } catch (e) {
      return null;
    }
  }
  
  /// Método para obter IP (alias para deviceIP)
  String? getIPAddress() => deviceIP;
  
  /// Verifica se é um dispositivo de mídia/câmera
  bool get isMediaDevice {
    if (deviceType == null) return false;
    
    final type = deviceType!.toLowerCase();
    return type.contains('mediaserver') ||
           type.contains('mediarenderer') ||
           type.contains('camera') ||
           type.contains('video') ||
           type.contains('nvr') ||
           type.contains('dvr');
  }
  
  /// Método para verificar se é dispositivo de mídia (para compatibilidade)
  bool isMediaDeviceMethod() => isMediaDevice;
  
  /// Verifica se tem serviços de câmera
  bool get hasCameraServices {
    return services.any((service) {
      final serviceType = service.serviceType?.toLowerCase() ?? '';
      return serviceType.contains('camera') ||
             serviceType.contains('video') ||
             serviceType.contains('imaging') ||
             serviceType.contains('media');
    });
  }
  
  @override
  String toString() {
    return 'UPnPDevice(ip: $deviceIP, name: $friendlyName, type: $deviceType, media: $isMediaDevice)';
  }
}

/// Modelo para serviço UPnP
class UPnPServiceInfo {
  final String? serviceType;
  final String? serviceId;
  final String? controlURL;
  final String? eventSubURL;
  final String? scpdURL;
  
  UPnPServiceInfo({
    this.serviceType,
    this.serviceId,
    this.controlURL,
    this.eventSubURL,
    this.scpdURL,
  });
  
  @override
  String toString() {
    return 'UPnPServiceInfo(type: $serviceType, id: $serviceId)';
  }
}

/// Service para descoberta UPnP (Universal Plug and Play)
class UPnPService {
  static const String _multicastAddress = '239.255.255.250';
  static const int _multicastPort = 1900;
  static const Duration _defaultTimeout = Duration(seconds: 15);
  
  final StreamController<UPnPDevice> _deviceController = StreamController.broadcast();
  final List<UPnPDevice> _discoveredDevices = [];
  final HttpClient _httpClient = HttpClient();
  
  UDP? _udpSocket;
  bool _isDiscovering = false;
  Timer? _timeoutTimer;
  
  /// Stream de dispositivos descobertos
  Stream<UPnPDevice> get deviceStream => _deviceController.stream;
  
  /// Lista de dispositivos descobertos
  List<UPnPDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  
  UPnPService() {
    _httpClient.connectionTimeout = Duration(seconds: 10);
  }
  
  /// Inicia descoberta UPnP
  Future<List<UPnPDevice>> discover({
    Duration timeout = _defaultTimeout,
    String searchTarget = 'upnp:rootdevice',
  }) async {
    if (_isDiscovering) {
      throw StateError('Descoberta já está em andamento');
    }
    
    _isDiscovering = true;
    _discoveredDevices.clear();
    
    try {
      print('UPnPService: Iniciando descoberta UPnP...');
      
      // Cria socket UDP
      _udpSocket = await UDP.bind(Endpoint.any(port: const Port(0)));
      
      // Configura listener para respostas
      _udpSocket!.asStream().listen((Datagram? datagram) {
        if (datagram != null) {
          _handleResponse(datagram);
        }
      });
      
      // Envia M-SEARCH multicast
      await _sendMSearch(searchTarget);
      
      // Configura timeout
      final completer = Completer<List<UPnPDevice>>();
      _timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(_discoveredDevices);
        }
      });
      
      return await completer.future;
      
    } catch (e) {
      print('UPnPService: Erro na descoberta: $e');
      return [];
    } finally {
      await _cleanup();
    }
  }
  
  /// Envia M-SEARCH multicast
  Future<void> _sendMSearch(String searchTarget) async {
    try {
      final message = _buildMSearchMessage(searchTarget);
      final data = utf8.encode(message);
      
      final endpoint = Endpoint.multicast(
        InternetAddress(_multicastAddress),
        port: Port(_multicastPort),
      );
      
      await _udpSocket!.send(data, endpoint);
      print('UPnPService: M-SEARCH enviado para $_multicastAddress:$_multicastPort');
      
      // Envia múltiplas vezes para aumentar chance de descoberta
      await Future.delayed(Duration(milliseconds: 100));
      await _udpSocket!.send(data, endpoint);
      
    } catch (e) {
      print('UPnPService: Erro ao enviar M-SEARCH: $e');
    }
  }
  
  /// Constrói mensagem M-SEARCH
  String _buildMSearchMessage(String searchTarget) {
    return 'M-SEARCH * HTTP/1.1\r\n'
           'HOST: $_multicastAddress:$_multicastPort\r\n'
           'MAN: "ssdp:discover"\r\n'
           'ST: $searchTarget\r\n'
           'MX: 3\r\n\r\n';
  }
  
  /// Manipula respostas SSDP
  void _handleResponse(Datagram datagram) {
    try {
      final response = utf8.decode(datagram.data);
      final device = _parseSSDPResponse(response, datagram.address.address);
      
      if (device != null) {
        // Verifica se já foi descoberto
        final existing = _discoveredDevices.firstWhere(
          (d) => d.location == device.location,
          orElse: () => device,
        );
        
        if (existing == device) {
          _discoveredDevices.add(device);
          
          // Busca informações detalhadas do dispositivo
          _fetchDeviceDescription(device);
        }
      }
      
    } catch (e) {
      print('UPnPService: Erro ao processar resposta: $e');
    }
  }
  
  /// Faz parse da resposta SSDP
  UPnPDevice? _parseSSDPResponse(String response, String sourceAddress) {
    try {
      final lines = response.split('\r\n');
      
      // Verifica se é uma resposta HTTP 200 OK
      if (!lines.first.contains('200 OK')) return null;
      
      String? location;
      String? server;
      String? usn;
      String? st;
      String? ext;
      int? maxAge;
      
      for (final line in lines) {
        final parts = line.split(': ');
        if (parts.length < 2) continue;
        
        final key = parts[0].toLowerCase();
        final value = parts.sublist(1).join(': ');
        
        switch (key) {
          case 'location':
            location = value;
            break;
          case 'server':
            server = value;
            break;
          case 'usn':
            usn = value;
            break;
          case 'st':
            st = value;
            break;
          case 'ext':
            ext = value;
            break;
          case 'cache-control':
            final maxAgeMatch = RegExp(r'max-age\s*=\s*(\d+)').firstMatch(value);
            if (maxAgeMatch != null) {
              maxAge = int.tryParse(maxAgeMatch.group(1)!);
            }
            break;
        }
      }
      
      if (location == null) return null;
      
      return UPnPDevice(
        location: location,
        server: server,
        usn: usn,
        st: st,
        ext: ext,
        maxAge: maxAge,
        discoveredAt: DateTime.now(),
        sourceAddress: sourceAddress,
      );
      
    } catch (e) {
      print('UPnPService: Erro ao fazer parse da resposta SSDP: $e');
      return null;
    }
  }
  
  /// Busca descrição detalhada do dispositivo
  Future<void> _fetchDeviceDescription(UPnPDevice device) async {
    try {
      final request = await _httpClient.getUrl(Uri.parse(device.location));
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final xmlData = await response.transform(utf8.decoder).join();
        _parseDeviceDescription(device, xmlData);
        
        _deviceController.add(device);
        print('UPnPService: Dispositivo descoberto: ${device.friendlyName} (${device.deviceIP})');
      }
      
    } catch (e) {
      print('UPnPService: Erro ao buscar descrição do dispositivo ${device.location}: $e');
      // Adiciona mesmo sem descrição detalhada
      _deviceController.add(device);
    }
  }
  
  /// Faz parse da descrição XML do dispositivo
  void _parseDeviceDescription(UPnPDevice device, String xmlData) {
    try {
      final document = XmlDocument.parse(xmlData);
      final deviceElement = document.findAllElements('device').firstOrNull;
      
      if (deviceElement == null) return;
      
      device.deviceType = deviceElement.findElements('deviceType').firstOrNull?.innerText;
      device.friendlyName = deviceElement.findElements('friendlyName').firstOrNull?.innerText;
      device.manufacturer = deviceElement.findElements('manufacturer').firstOrNull?.innerText;
      device.manufacturerURL = deviceElement.findElements('manufacturerURL').firstOrNull?.innerText;
      device.modelDescription = deviceElement.findElements('modelDescription').firstOrNull?.innerText;
      device.modelName = deviceElement.findElements('modelName').firstOrNull?.innerText;
      device.modelNumber = deviceElement.findElements('modelNumber').firstOrNull?.innerText;
      device.modelURL = deviceElement.findElements('modelURL').firstOrNull?.innerText;
      device.serialNumber = deviceElement.findElements('serialNumber').firstOrNull?.innerText;
      device.udn = deviceElement.findElements('UDN').firstOrNull?.innerText;
      device.presentationURL = deviceElement.findElements('presentationURL').firstOrNull?.innerText;
      
      // Parse services
      final serviceListElement = deviceElement.findElements('serviceList').firstOrNull;
      if (serviceListElement != null) {
        for (final serviceElement in serviceListElement.findElements('service')) {
          final service = UPnPServiceInfo(
            serviceType: serviceElement.findElements('serviceType').firstOrNull?.innerText,
            serviceId: serviceElement.findElements('serviceId').firstOrNull?.innerText,
            controlURL: serviceElement.findElements('controlURL').firstOrNull?.innerText,
            eventSubURL: serviceElement.findElements('eventSubURL').firstOrNull?.innerText,
            scpdURL: serviceElement.findElements('SCPDURL').firstOrNull?.innerText,
          );
          device.services.add(service);
        }
      }
      
    } catch (e) {
      print('UPnPService: Erro ao fazer parse da descrição XML: $e');
    }
  }
  
  /// Descobre dispositivos de mídia especificamente
  Future<List<UPnPDevice>> discoverMediaDevices({
    Duration timeout = _defaultTimeout,
  }) async {
    final allDevices = await discover(
      timeout: timeout,
      searchTarget: 'urn:schemas-upnp-org:device:MediaServer:1',
    );
    
    // Também busca por root devices e filtra por tipo
    final rootDevices = await discover(
      timeout: Duration(seconds: timeout.inSeconds ~/ 2),
      searchTarget: 'upnp:rootdevice',
    );
    
    final mediaDevices = <UPnPDevice>[];
    mediaDevices.addAll(allDevices);
    mediaDevices.addAll(rootDevices.where((device) => 
        device.isMediaDevice || device.hasCameraServices));
    
    // Remove duplicatas
    final uniqueDevices = <String, UPnPDevice>{};
    for (final device in mediaDevices) {
      uniqueDevices[device.location] = device;
    }
    
    return uniqueDevices.values.toList();
  }
  
  /// Descobre todos os tipos de dispositivos
  Future<List<UPnPDevice>> discoverAllDevices({
    Duration timeout = _defaultTimeout,
  }) async {
    final devices = <UPnPDevice>[];
    
    // Busca diferentes tipos de dispositivos
    final searchTargets = [
      'upnp:rootdevice',
      'urn:schemas-upnp-org:device:MediaServer:1',
      'urn:schemas-upnp-org:device:MediaRenderer:1',
      'ssdp:all',
    ];
    
    for (final target in searchTargets) {
      try {
        final targetDevices = await discover(
          timeout: Duration(seconds: timeout.inSeconds ~/ searchTargets.length),
          searchTarget: target,
        );
        devices.addAll(targetDevices);
      } catch (e) {
        print('UPnPService: Erro ao buscar $target: $e');
      }
    }
    
    // Remove duplicatas
    final uniqueDevices = <String, UPnPDevice>{};
    for (final device in devices) {
      uniqueDevices[device.location] = device;
    }
    
    return uniqueDevices.values.toList();
  }
  
  /// Para a descoberta atual
  Future<void> stopDiscovery() async {
    await _cleanup();
  }
  
  /// Limpa recursos
  Future<void> _cleanup() async {
    _isDiscovering = false;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    
    if (_udpSocket != null) {
      _udpSocket!.close();
      _udpSocket = null;
    }
  }
  
  /// Obtém estatísticas da descoberta
  Map<String, dynamic> getStatistics() {
    final mediaDevices = _discoveredDevices.where((d) => d.isMediaDevice).length;
    final cameraDevices = _discoveredDevices.where((d) => d.hasCameraServices).length;
    final uniqueIPs = _discoveredDevices
        .map((d) => d.deviceIP)
        .where((ip) => ip != null)
        .toSet()
        .length;
    
    return {
      'totalDevices': _discoveredDevices.length,
      'mediaDevices': mediaDevices,
      'cameraDevices': cameraDevices,
      'uniqueIPs': uniqueIPs,
      'isDiscovering': _isDiscovering,
    };
  }
  
  /// Dispose do service
  void dispose() {
    _cleanup();
    _deviceController.close();
    _httpClient.close();
  }
}

/// Extensão para adicionar firstOrNull ao Iterable
extension IterableFirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}