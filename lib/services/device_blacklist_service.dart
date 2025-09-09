import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Serviço para gerenciar blacklist de dispositivos que não são câmeras
class DeviceBlacklistService {
  static final DeviceBlacklistService _instance = DeviceBlacklistService._internal();
  factory DeviceBlacklistService() => _instance;
  DeviceBlacklistService._internal();

  /// Lista de fabricantes conhecidos que NÃO são câmeras
  static const Set<String> _nonCameraManufacturers = {
    // Roteadores
    'tp-link', 'tplink', 'tp link',
    'linksys',
    'netgear',
    'asus',
    'dlink', 'd-link', 'd link',
    'belkin',
    'cisco',
    'ubiquiti',
    'mikrotik',
    'buffalo',
    'zyxel',
    'tenda',
    'mercusys',
    'huawei router', 'huawei wifi',
    
    // Impressoras
    'hp', 'hewlett-packard', 'hewlett packard',
    'canon',
    'epson',
    'brother',
    'samsung printer', 'samsung scx',
    'lexmark',
    'xerox',
    'ricoh',
    'kyocera',
    'oki', 'okidata',
    
    // Smart TVs e Media Players
    'samsung tv', 'samsung smart',
    'lg tv', 'lg smart',
    'sony tv', 'sony bravia',
    'tcl tv',
    'roku',
    'apple tv',
    'chromecast',
    'fire tv',
    'nvidia shield',
    
    // Outros dispositivos
    'raspberry pi',
    'arduino',
    'esp32', 'esp8266',
    'sonos',
    'philips hue',
    'amazon echo', 'alexa',
    'google home', 'google nest',
    'nas synology', 'qnap',
  };

  /// Lista de nomes de dispositivos que NÃO são câmeras
  static const Set<String> _nonCameraDeviceNames = {
    // Roteadores
    'router', 'roteador',
    'wifi', 'wireless',
    'access point', 'ap',
    'gateway',
    'modem',
    'repeater', 'repetidor',
    'extender',
    
    // Impressoras
    'printer', 'impressora',
    'scanner',
    'multifunction', 'multifuncional',
    'laserjet',
    'inkjet',
    'deskjet',
    'officejet',
    
    // Smart Home
    'smart tv', 'tv',
    'chromecast',
    'roku',
    'fire stick',
    'apple tv',
    'media player',
    'streaming device',
    
    // Outros
    'nas',
    'server', 'servidor',
    'workstation',
    'desktop',
    'laptop',
    'tablet',
    'smartphone',
    'smart speaker',
    'voice assistant',
  };

  /// Lista de tipos de serviço que NÃO são câmeras
  static const Set<String> _nonCameraServiceTypes = {
    '_printer._tcp',
    '_ipp._tcp',
    '_airplay._tcp',
    '_googlecast._tcp',
    '_spotify-connect._tcp',
    '_workstation._tcp',
    '_smb._tcp',
    '_afpovertcp._tcp',
    '_ssh._tcp',
    '_telnet._tcp',
    '_ftp._tcp',
    '_nfs._tcp',
    '_upnp._tcp',
    '_dlna._tcp',
  };

  /// Lista de palavras-chave em respostas HTTP que indicam NÃO ser câmera
  static const Set<String> _nonCameraHttpKeywords = {
    // Roteadores
    'router configuration',
    'wireless settings',
    'network settings',
    'router admin',
    'wifi configuration',
    'access point',
    'gateway settings',
    'dhcp settings',
    'port forwarding',
    'firewall settings',
    
    // Impressoras
    'printer status',
    'print queue',
    'scanner settings',
    'ink levels',
    'toner levels',
    'paper settings',
    'print settings',
    
    // Smart TVs
    'smart tv',
    'media player',
    'streaming device',
    'netflix',
    'youtube',
    'amazon prime',
    
    // Outros
    'file server',
    'nas settings',
    'workstation',
    'desktop computer',
  };

  /// Lista de portas que são comumente usadas por dispositivos que NÃO são câmeras
  static const Map<int, Set<String>> _nonCameraPortServices = {
    21: {'ftp'},
    22: {'ssh'},
    23: {'telnet'},
    25: {'smtp'},
    53: {'dns'},
    80: {'router', 'printer', 'nas'}, // Nota: 80 pode ser câmera também
    110: {'pop3'},
    139: {'netbios'},
    143: {'imap'},
    443: {'https'}, // Genérico demais
    445: {'smb'},
    515: {'printer'},
    631: {'ipp', 'printer'},
    993: {'imaps'},
    995: {'pop3s'},
    5000: {'upnp'},
    8080: {'router', 'nas'}, // Nota: 8080 pode ser câmera também
    9100: {'printer'},
  };

  /// Verifica se um dispositivo está na blacklist baseado no fabricante
  bool isBlacklistedManufacturer(String? manufacturer) {
    if (manufacturer == null || manufacturer.isEmpty) return false;
    
    final lowerManufacturer = manufacturer.toLowerCase().trim();
    return _nonCameraManufacturers.any((blocked) => 
        lowerManufacturer.contains(blocked) || blocked.contains(lowerManufacturer));
  }

  /// Verifica se um dispositivo está na blacklist baseado no nome
  bool isBlacklistedDeviceName(String? deviceName) {
    if (deviceName == null || deviceName.isEmpty) return false;
    
    final lowerName = deviceName.toLowerCase().trim();
    return _nonCameraDeviceNames.any((blocked) => 
        lowerName.contains(blocked) || blocked.contains(lowerName));
  }

  /// Verifica se um tipo de serviço está na blacklist
  bool isBlacklistedServiceType(String? serviceType) {
    if (serviceType == null || serviceType.isEmpty) return false;
    
    final lowerType = serviceType.toLowerCase().trim();
    return _nonCameraServiceTypes.contains(lowerType);
  }

  /// Verifica se uma resposta HTTP indica que NÃO é uma câmera
  bool isNonCameraHttpResponse(String? httpResponse) {
    if (httpResponse == null || httpResponse.isEmpty) return false;
    
    final lowerResponse = httpResponse.toLowerCase();
    return _nonCameraHttpKeywords.any((keyword) => lowerResponse.contains(keyword));
  }

  /// Verifica se uma porta/serviço indica que NÃO é uma câmera
  bool isNonCameraPortService(int port, String? serviceName, {String? ip}) {
    // REGRA ESPECIAL: Se é porta 80 e IP é gateway, SEMPRE filtrar
    if (port == 80 && ip != null && _isGatewayIP(ip)) {
      print('DEBUG BLACKLIST: Porta 80 em gateway $ip - SEMPRE FILTRADO');
      return true;
    }
    
    final portServices = _nonCameraPortServices[port];
    if (portServices == null) return false;
    
    if (serviceName == null || serviceName.isEmpty) {
      // Se não temos nome do serviço, só consideramos blacklist para portas muito específicas
      // Incluindo porta 80 para gateways (já verificado acima)
      return [21, 22, 23, 25, 53, 110, 139, 143, 445, 515, 631, 993, 995, 9100].contains(port);
    }
    
    final lowerServiceName = serviceName.toLowerCase();
    return portServices.any((service) => lowerServiceName.contains(service));
  }

  /// Check if IP address is likely a gateway/router
  bool _isGatewayIP(String ip) {
    try {
      final parts = ip.split('.');
      if (parts.length != 4) return false;
      
      // Check for common gateway patterns
      // Most routers use .1 as the last octet (192.168.1.1, 192.168.0.1, etc.)
      if (parts[3] == '1') {
        // Additional validation for private IP ranges
        final firstOctet = int.tryParse(parts[0]);
        final secondOctet = int.tryParse(parts[1]);
        
        if (firstOctet == 192 && secondOctet == 168) {
          return true; // 192.168.x.1
        }
        if (firstOctet == 10) {
          return true; // 10.x.x.1
        }
        if (firstOctet == 172 && secondOctet != null && secondOctet >= 16 && secondOctet <= 31) {
          return true; // 172.16-31.x.1
        }
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Public method to check if IP address is likely a gateway/router
  bool isGatewayIP(String ip) {
    return _isGatewayIP(ip);
  }

  /// Static method for backward compatibility
  static bool isBlacklisted(String ip, {
    String? manufacturer,
    String? deviceName,
    String? serviceType,
    String? httpResponse,
  }) {
    final instance = DeviceBlacklistService();
    
    // Check if IP is a gateway/router (typically ends with .1)
    if (instance._isGatewayIP(ip)) {
      print('DEBUG BLACKLIST: IP $ip identificado como gateway/roteador - FILTRADO');
      return true;
    }

    final shouldFilter = instance.shouldFilterDevice(
      manufacturer: manufacturer,
      deviceName: deviceName,
      serviceType: serviceType,
      httpResponse: httpResponse,
    );
    
    if (shouldFilter) {
      print('DEBUG BLACKLIST: Dispositivo $ip filtrado por outros critérios');
    } else {
      print('DEBUG BLACKLIST: Dispositivo $ip PASSOU pela blacklist');
    }
    
    return shouldFilter;
  }

  /// Análise completa se um dispositivo deve ser filtrado
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
    // PRIMEIRA VERIFICAÇÃO: Se é um gateway/roteador (prioridade máxima)
    if (ip != null && _isGatewayIP(ip)) {
      print('DEBUG BLACKLIST: IP $ip identificado como gateway/roteador no shouldFilterDevice - FILTRADO');
      return true;
    }

    // Verifica fabricante
    if (isBlacklistedManufacturer(manufacturer)) {
      return true;
    }

    // Verifica nome do dispositivo
    if (isBlacklistedDeviceName(deviceName)) {
      return true;
    }

    // Verifica tipo de serviço
    if (isBlacklistedServiceType(serviceType)) {
      return true;
    }

    // Verifica resposta HTTP
    if (isNonCameraHttpResponse(httpResponse)) {
      return true;
    }

    // Verifica porta/serviço (passando IP para verificação especial de gateway)
    if (port != null && isNonCameraPortService(port, serviceName, ip: ip)) {
      print('DEBUG BLACKLIST: Porta $port filtrada para IP $ip');
      return true;
    }

    // Verifica registros TXT para indicadores de não-câmera
    if (txtRecords != null) {
      for (final entry in txtRecords.entries) {
        final key = entry.key.toLowerCase();
        final value = entry.value.toLowerCase();
        
        // Verifica se há indicadores de router/printer nos TXT records
        if ((key.contains('device') || key.contains('type') || key.contains('model')) &&
            (value.contains('router') || value.contains('printer') || value.contains('nas'))) {
          return true;
        }
      }
    }

    return false;
  }

  /// Obtém estatísticas da blacklist
  Map<String, int> getBlacklistStats() {
    return {
      'manufacturers': _nonCameraManufacturers.length,
      'deviceNames': _nonCameraDeviceNames.length,
      'serviceTypes': _nonCameraServiceTypes.length,
      'httpKeywords': _nonCameraHttpKeywords.length,
      'portServices': _nonCameraPortServices.length,
    };
  }
}