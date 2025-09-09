import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:udp/udp.dart';
import 'package:xml/xml.dart';

/// Modelo para dispositivo descoberto via WS-Discovery
class WSDiscoveryDevice {
  final String address;
  final String? endpointReference;
  final List<String> types;
  final List<String> scopes;
  final String? xAddrs;
  final int? metadataVersion;
  final DateTime discoveredAt;
  
  WSDiscoveryDevice({
    required this.address,
    this.endpointReference,
    required this.types,
    required this.scopes,
    this.xAddrs,
    this.metadataVersion,
    required this.discoveredAt,
  });
  
  /// Verifica se é um dispositivo ONVIF
  bool get isOnvifDevice {
    return types.any((type) => 
        type.contains('NetworkVideoTransmitter') ||
        type.contains('Device') ||
        type.contains('onvif'));
  }
  
  /// Extrai IP do xAddrs
  String? get deviceIP {
    if (xAddrs == null) return null;
    
    try {
      final uri = Uri.parse(xAddrs!);
      return uri.host;
    } catch (e) {
      // Tenta extrair IP usando regex
      final ipRegex = RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})');
      final match = ipRegex.firstMatch(xAddrs!);
      return match?.group(1);
    }
  }
  
  /// Método para obter IP (alias para deviceIP)
  String? getIPAddress() => deviceIP;
  
  /// Nome do dispositivo (extraído dos scopes ou tipos)
  String get name {
    // Tenta extrair nome dos scopes
    for (final scope in scopes) {
      if (scope.contains('name=')) {
        final nameMatch = RegExp(r'name=([^/]+)').firstMatch(scope);
        if (nameMatch != null) {
          return Uri.decodeComponent(nameMatch.group(1)!);
        }
      }
    }
    
    // Se não encontrar nome, usa tipo do dispositivo
    if (types.isNotEmpty) {
      final type = types.first;
      if (type.contains('NetworkVideoTransmitter')) {
        return 'Câmera ONVIF';
      }
    }
    
    return 'Dispositivo WS-Discovery';
  }
  
  /// Fabricante do dispositivo (extraído dos scopes)
  String get manufacturer {
    for (final scope in scopes) {
      if (scope.contains('mfr=')) {
        final mfrMatch = RegExp(r'mfr=([^/]+)').firstMatch(scope);
        if (mfrMatch != null) {
          return Uri.decodeComponent(mfrMatch.group(1)!);
        }
      }
    }
    return 'Desconhecido';
  }
  
  /// Modelo do dispositivo (extraído dos scopes)
  String get model {
    for (final scope in scopes) {
      if (scope.contains('model=')) {
        final modelMatch = RegExp(r'model=([^/]+)').firstMatch(scope);
        if (modelMatch != null) {
          return Uri.decodeComponent(modelMatch.group(1)!);
        }
      }
    }
    return 'Desconhecido';
  }
  
  /// Verifica se é dispositivo ONVIF (método)
  bool isONVIFDevice() => isOnvifDevice;
  
  @override
  String toString() {
    return 'WSDiscoveryDevice(address: $address, ip: $deviceIP, types: $types, onvif: $isOnvifDevice)';
  }
}

/// Service para descoberta WS-Discovery (Web Services Dynamic Discovery)
class WSDiscoveryService {
  static const String _multicastAddress = '239.255.255.250';
  static const int _multicastPort = 3702;
  static const Duration _defaultTimeout = Duration(seconds: 10);
  
  final StreamController<WSDiscoveryDevice> _deviceController = StreamController.broadcast();
  final List<WSDiscoveryDevice> _discoveredDevices = [];
  
  UDP? _udpSocket;
  bool _isDiscovering = false;
  Timer? _timeoutTimer;
  
  /// Stream de dispositivos descobertos
  Stream<WSDiscoveryDevice> get deviceStream => _deviceController.stream;
  
  /// Lista de dispositivos descobertos
  List<WSDiscoveryDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  
  /// Inicia descoberta WS-Discovery
  Future<List<WSDiscoveryDevice>> discover({
    Duration timeout = _defaultTimeout,
    List<String>? targetTypes,
  }) async {
    if (_isDiscovering) {
      throw StateError('Descoberta já está em andamento');
    }
    
    _isDiscovering = true;
    _discoveredDevices.clear();
    
    try {
      print('WSDiscoveryService: Iniciando descoberta WS-Discovery...');
      
      // Cria socket UDP
      _udpSocket = await UDP.bind(Endpoint.any(port: const Port(0)));
      
      // Configura listener para respostas
      _udpSocket!.asStream().listen((Datagram? datagram) {
        if (datagram != null) {
          _handleResponse(datagram);
        }
      });
      
      // Envia probe multicast
      await _sendProbe(targetTypes);
      
      // Configura timeout
      final completer = Completer<List<WSDiscoveryDevice>>();
      _timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(_discoveredDevices);
        }
      });
      
      return await completer.future;
      
    } catch (e) {
      print('WSDiscoveryService: Erro na descoberta: $e');
      return [];
    } finally {
      await _cleanup();
    }
  }
  
  /// Envia probe multicast para descoberta
  Future<void> _sendProbe(List<String>? targetTypes) async {
    try {
      final probeMessage = _buildProbeMessage(targetTypes);
      final data = utf8.encode(probeMessage);
      
      final endpoint = Endpoint.multicast(
        InternetAddress(_multicastAddress),
        port: Port(_multicastPort),
      );
      
      await _udpSocket!.send(data, endpoint);
      print('WSDiscoveryService: Probe enviado para $_multicastAddress:$_multicastPort');
      
    } catch (e) {
      print('WSDiscoveryService: Erro ao enviar probe: $e');
    }
  }
  
  /// Constrói mensagem de probe WS-Discovery
  String _buildProbeMessage(List<String>? targetTypes) {
    final messageId = 'urn:uuid:${_generateUUID()}';
    final timestamp = DateTime.now().toUtc().toIso8601String();
    
    final typesElement = targetTypes != null && targetTypes.isNotEmpty
        ? '<d:Types>${targetTypes.join(' ')}</d:Types>'
        : '<d:Types>dn:NetworkVideoTransmitter</d:Types>';
    
    return '''
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope 
    xmlns:soap="http://www.w3.org/2003/05/soap-envelope" 
    xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing" 
    xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" 
    xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
  <soap:Header>
    <wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</wsa:Action>
    <wsa:MessageID>$messageId</wsa:MessageID>
    <wsa:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>
  </soap:Header>
  <soap:Body>
    <d:Probe>
      $typesElement
    </d:Probe>
  </soap:Body>
</soap:Envelope>''';
  }
  
  /// Manipula respostas recebidas
  void _handleResponse(Datagram datagram) {
    try {
      final response = utf8.decode(datagram.data);
      final device = _parseProbeMatch(response, datagram.address.address);
      
      if (device != null) {
        _discoveredDevices.add(device);
        _deviceController.add(device);
        print('WSDiscoveryService: Dispositivo descoberto: ${device.deviceIP}');
      }
      
    } catch (e) {
      print('WSDiscoveryService: Erro ao processar resposta: $e');
    }
  }
  
  /// Faz parse da resposta ProbeMatch
  WSDiscoveryDevice? _parseProbeMatch(String xmlResponse, String sourceAddress) {
    try {
      final document = XmlDocument.parse(xmlResponse);
      
      // Procura por ProbeMatch ou Hello
      final probeMatch = document.findAllElements('ProbeMatch').firstOrNull ??
                        document.findAllElements('Hello').firstOrNull;
      
      if (probeMatch == null) return null;
      
      // Extrai informações do dispositivo
      final endpointRef = probeMatch.findElements('EndpointReference')
          .firstOrNull?.findElements('Address').firstOrNull?.innerText;
      
      final typesElement = probeMatch.findElements('Types').firstOrNull;
      final types = typesElement?.innerText.split(' ').where((s) => s.isNotEmpty).toList() ?? [];
      
      final scopesElement = probeMatch.findElements('Scopes').firstOrNull;
      final scopes = scopesElement?.innerText.split(' ').where((s) => s.isNotEmpty).toList() ?? [];
      
      final xAddrsElement = probeMatch.findElements('XAddrs').firstOrNull;
      final xAddrs = xAddrsElement?.innerText.trim();
      
      final metadataVersionElement = probeMatch.findElements('MetadataVersion').firstOrNull;
      final metadataVersion = metadataVersionElement != null 
          ? int.tryParse(metadataVersionElement.innerText) 
          : null;
      
      return WSDiscoveryDevice(
        address: sourceAddress,
        endpointReference: endpointRef,
        types: types,
        scopes: scopes,
        xAddrs: xAddrs,
        metadataVersion: metadataVersion,
        discoveredAt: DateTime.now(),
      );
      
    } catch (e) {
      print('WSDiscoveryService: Erro ao fazer parse da resposta: $e');
      return null;
    }
  }
  
  /// Descobre dispositivos ONVIF especificamente (alias)
  Future<List<WSDiscoveryDevice>> discoverONVIFDevices({
    Duration timeout = _defaultTimeout,
  }) async {
    return await discoverOnvifDevices(timeout: timeout);
  }

  /// Descobre dispositivos ONVIF especificamente
  Future<List<WSDiscoveryDevice>> discoverOnvifDevices({
    Duration timeout = _defaultTimeout,
  }) async {
    final devices = await discover(
      timeout: timeout,
      targetTypes: [
        'dn:NetworkVideoTransmitter',
        'tds:Device',
        'dn:Device',
      ],
    );
    
    return devices.where((device) => device.isOnvifDevice).toList();
  }
  
  /// Descobre todos os tipos de dispositivos
  Future<List<WSDiscoveryDevice>> discoverAllDevices({
    Duration timeout = _defaultTimeout,
  }) async {
    return await discover(timeout: timeout);
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
  
  /// Gera UUID simples
  String _generateUUID() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return '$random-${random.hashCode.abs()}-${random.toString().hashCode.abs()}';
  }
  
  /// Verifica se um IP específico responde a WS-Discovery
  Future<WSDiscoveryDevice?> probeSpecificDevice(
    String ipAddress, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      print('WSDiscoveryService: Testando WS-Discovery em $ipAddress');
      
      // Cria socket UDP temporário
      final socket = await UDP.bind(Endpoint.any(port: const Port(0)));
      WSDiscoveryDevice? foundDevice;
      
      // Listener para resposta
      final subscription = socket.asStream().listen((datagram) {
        if (datagram?.address.address == ipAddress) {
          final response = utf8.decode(datagram!.data);
          foundDevice = _parseProbeMatch(response, ipAddress);
        }
      });
      
      // Envia probe unicast
      final probeMessage = _buildProbeMessage(null);
      final data = utf8.encode(probeMessage);
      final endpoint = Endpoint.unicast(
        InternetAddress(ipAddress),
        port: Port(_multicastPort),
      );
      
      await socket.send(data, endpoint);
      
      // Aguarda resposta
      await Future.delayed(timeout);
      
      // Cleanup
      await subscription.cancel();
      socket.close();
      
      return foundDevice;
      
    } catch (e) {
      print('WSDiscoveryService: Erro ao testar $ipAddress: $e');
      return null;
    }
  }
  
  /// Obtém estatísticas da descoberta
  Map<String, dynamic> getStatistics() {
    final onvifDevices = _discoveredDevices.where((d) => d.isOnvifDevice).length;
    final uniqueIPs = _discoveredDevices
        .map((d) => d.deviceIP)
        .where((ip) => ip != null)
        .toSet()
        .length;
    
    return {
      'totalDevices': _discoveredDevices.length,
      'onvifDevices': onvifDevices,
      'uniqueIPs': uniqueIPs,
      'isDiscovering': _isDiscovering,
    };
  }
  
  /// Dispose do service
  void dispose() {
    _cleanup();
    _deviceController.close();
  }
}

/// Extensão para adicionar firstOrNull ao Iterable
extension IterableFirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}