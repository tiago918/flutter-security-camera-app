/// Modelo simplificado para dispositivos de câmera descobertos
/// Usado pelos serviços de descoberta e validação
class CameraDevice {
  final String ip;
  final int port;
  final String name;
  final String? manufacturer;
  final String? model;
  final String? protocol;
  final bool isValidated;
  final DateTime? discoveredAt;
  final Map<String, dynamic>? metadata;
  
  const CameraDevice({
    required this.ip,
    required this.port,
    required this.name,
    this.manufacturer,
    this.model,
    this.protocol,
    this.isValidated = false,
    this.discoveredAt,
    this.metadata,
  });
  
  /// Cria uma cópia com campos atualizados
  CameraDevice copyWith({
    String? ip,
    int? port,
    String? name,
    String? manufacturer,
    String? model,
    String? protocol,
    bool? isValidated,
    DateTime? discoveredAt,
    Map<String, dynamic>? metadata,
  }) {
    return CameraDevice(
      ip: ip ?? this.ip,
      port: port ?? this.port,
      name: name ?? this.name,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      protocol: protocol ?? this.protocol,
      isValidated: isValidated ?? this.isValidated,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      metadata: metadata ?? this.metadata,
    );
  }
  
  /// Converte para Map
  Map<String, dynamic> toMap() {
    return {
      'ip': ip,
      'port': port,
      'name': name,
      'manufacturer': manufacturer,
      'model': model,
      'protocol': protocol,
      'isValidated': isValidated,
      'discoveredAt': discoveredAt?.toIso8601String(),
      'metadata': metadata,
    };
  }
  
  /// Cria a partir de Map
  factory CameraDevice.fromMap(Map<String, dynamic> map) {
    return CameraDevice(
      ip: map['ip'] ?? '',
      port: map['port'] ?? 80,
      name: map['name'] ?? 'Unknown Device',
      manufacturer: map['manufacturer'],
      model: map['model'],
      protocol: map['protocol'],
      isValidated: map['isValidated'] ?? false,
      discoveredAt: map['discoveredAt'] != null 
          ? DateTime.parse(map['discoveredAt']) 
          : null,
      metadata: map['metadata'],
    );
  }
  
  /// Gera URL base para o dispositivo
  String get baseUrl {
    final scheme = (protocol?.toLowerCase() == 'https' || port == 443) ? 'https' : 'http';
    return '$scheme://$ip:$port';
  }
  
  /// Gera URL RTSP padrão
  String get rtspUrl {
    return 'rtsp://$ip:$port/stream';
  }
  
  /// Gera URL RTSP com credenciais
  String getRtspUrl({String? username, String? password, String? path}) {
    final auth = (username != null && password != null) ? '$username:$password@' : '';
    final streamPath = path ?? '/stream';
    return 'rtsp://$auth$ip:$port$streamPath';
  }
  
  /// Gera URL HTTP com credenciais
  String getHttpUrl({String? username, String? password, String? path}) {
    final scheme = (protocol?.toLowerCase() == 'https' || port == 443) ? 'https' : 'http';
    final auth = (username != null && password != null) ? '$username:$password@' : '';
    final requestPath = path ?? '/';
    return '$scheme://$auth$ip:$port$requestPath';
  }
  
  /// Verifica se é um dispositivo RTSP
  bool get isRtspDevice {
    return protocol?.toLowerCase() == 'rtsp' || 
           port == 554 || 
           port == 8554 || 
           port == 1935;
  }
  
  /// Verifica se é um dispositivo HTTP
  bool get isHttpDevice {
    return protocol?.toLowerCase() == 'http' || 
           protocol?.toLowerCase() == 'https' || 
           port == 80 || 
           port == 443 || 
           port == 8080;
  }
  
  /// Verifica se é um dispositivo ONVIF
  bool get isOnvifDevice {
    return protocol?.toLowerCase() == 'onvif' || 
           port == 80 || 
           port == 8080 || 
           port == 3702;
  }
  
  /// Identificador único do dispositivo
  String get uniqueId => '$ip:$port';
  
  /// Descrição legível do dispositivo
  String get description {
    final parts = <String>[name];
    
    if (manufacturer != null) {
      parts.add(manufacturer!);
    }
    
    if (model != null) {
      parts.add(model!);
    }
    
    parts.add('$ip:$port');
    
    return parts.join(' - ');
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is CameraDevice &&
        other.ip == ip &&
        other.port == port;
  }
  
  @override
  int get hashCode => ip.hashCode ^ port.hashCode;
  
  @override
  String toString() {
    return 'CameraDevice(ip: $ip, port: $port, name: $name, manufacturer: $manufacturer, protocol: $protocol)';
  }
}

/// Extensões úteis para listas de CameraDevice
extension CameraDeviceListExtensions on List<CameraDevice> {
  /// Filtra por protocolo
  List<CameraDevice> whereProtocol(String protocol) {
    return where((device) => device.protocol?.toLowerCase() == protocol.toLowerCase()).toList();
  }
  
  /// Filtra por fabricante
  List<CameraDevice> whereManufacturer(String manufacturer) {
    return where((device) => 
        device.manufacturer?.toLowerCase().contains(manufacturer.toLowerCase()) == true
    ).toList();
  }
  
  /// Filtra por porta
  List<CameraDevice> wherePort(int port) {
    return where((device) => device.port == port).toList();
  }
  
  /// Filtra dispositivos validados
  List<CameraDevice> get validated {
    return where((device) => device.isValidated).toList();
  }
  
  /// Filtra dispositivos RTSP
  List<CameraDevice> get rtspDevices {
    return where((device) => device.isRtspDevice).toList();
  }
  
  /// Filtra dispositivos HTTP
  List<CameraDevice> get httpDevices {
    return where((device) => device.isHttpDevice).toList();
  }
  
  /// Filtra dispositivos ONVIF
  List<CameraDevice> get onvifDevices {
    return where((device) => device.isOnvifDevice).toList();
  }
  
  /// Remove duplicatas baseado em IP:porta
  List<CameraDevice> get unique {
    final seen = <String>{};
    return where((device) {
      final id = device.uniqueId;
      if (seen.contains(id)) {
        return false;
      }
      seen.add(id);
      return true;
    }).toList();
  }
  
  /// Ordena por IP
  List<CameraDevice> get sortedByIp {
    final copy = List<CameraDevice>.from(this);
    copy.sort((a, b) {
      final aOctets = a.ip.split('.').map(int.parse).toList();
      final bOctets = b.ip.split('.').map(int.parse).toList();
      
      for (int i = 0; i < 4; i++) {
        final comparison = aOctets[i].compareTo(bOctets[i]);
        if (comparison != 0) return comparison;
      }
      
      return a.port.compareTo(b.port);
    });
    return copy;
  }
}