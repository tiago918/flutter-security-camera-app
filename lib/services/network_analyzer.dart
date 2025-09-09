import 'dart:io';
import 'dart:typed_data';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Modelo para informações de rede
class LocalNetworkInfo {
  final String? wifiName;
  final String? wifiIP;
  final String? wifiGateway;
  final String? wifiSubnet;
  final String? wifiBSSID;
  final List<String> ipRange;
  final String cidr;
  
  LocalNetworkInfo({
    this.wifiName,
    this.wifiIP,
    this.wifiGateway,
    this.wifiSubnet,
    this.wifiBSSID,
    required this.ipRange,
    required this.cidr,
  });
  
  @override
  String toString() {
    return 'NetworkInfo(name: $wifiName, ip: $wifiIP, gateway: $wifiGateway, subnet: $wifiSubnet, cidr: $cidr, range: ${ipRange.length} IPs)';
  }
}

/// Service para análise automática de rede local
class NetworkAnalyzer {
  static final NetworkAnalyzer _instance = NetworkAnalyzer._internal();
  factory NetworkAnalyzer() => _instance;
  NetworkAnalyzer._internal();
  
  final LocalNetworkInfo _networkInfo = LocalNetworkInfo(ipRange: [], cidr: '');
  final Connectivity _connectivity = Connectivity();
  
  /// Obtém informações completas da rede atual (alias)
  Future<LocalNetworkInfo?> getNetworkInfo() async {
    return await getCurrentNetworkInfo();
  }

  /// Calcula CIDR público
  String calculateCIDR(String ip, String subnet) {
    return _calculateCIDR(ip, subnet);
  }

  /// Gera range de IPs público
  List<String> generateIPRange(String cidr) {
    try {
      final parts = cidr.split('/');
      if (parts.length != 2) return [];
      
      final ip = parts[0];
      final prefixLength = int.parse(parts[1]);
      
      // Converte prefix length para máscara de sub-rede
      final mask = _prefixLengthToSubnetMask(prefixLength);
      return _generateIPRange(ip, mask);
    } catch (e) {
      print('NetworkAnalyzer: Erro ao gerar range do CIDR: $e');
      return [];
    }
  }

  /// Converte prefix length para máscara de sub-rede
  String _prefixLengthToSubnetMask(int prefixLength) {
    if (prefixLength < 0 || prefixLength > 32) {
      return '255.255.255.0'; // Fallback
    }
    
    int mask = (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
    return '${(mask >> 24) & 0xFF}.${(mask >> 16) & 0xFF}.${(mask >> 8) & 0xFF}.${mask & 0xFF}';
  }

  /// Obtém informações completas da rede atual
  Future<LocalNetworkInfo?> getCurrentNetworkInfo() async {
    try {
      // Verifica conectividade
      final connectivityResult = await _connectivity.checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.wifi)) {
        print('NetworkAnalyzer: Não conectado ao WiFi');
        return null;
      }
      
      // Obtém informações básicas da rede
      final networkInfoPlus = NetworkInfo();
      final wifiName = await networkInfoPlus.getWifiName();
      final wifiIP = await networkInfoPlus.getWifiIP();
      final wifiGateway = await networkInfoPlus.getWifiGatewayIP();
      final wifiSubnet = await networkInfoPlus.getWifiSubmask();
      final wifiBSSID = await networkInfoPlus.getWifiBSSID();
      
      if (wifiIP == null || wifiGateway == null) {
        print('NetworkAnalyzer: Não foi possível obter IP ou Gateway');
        return null;
      }
      
      // Calcula CIDR e range de IPs
      final cidr = _calculateCIDR(wifiIP, wifiSubnet ?? '255.255.255.0');
      final ipRange = _generateIPRange(wifiIP, wifiSubnet ?? '255.255.255.0');
      
      return LocalNetworkInfo(
        wifiName: wifiName,
        wifiIP: wifiIP,
        wifiGateway: wifiGateway,
        wifiSubnet: wifiSubnet,
        wifiBSSID: wifiBSSID,
        ipRange: ipRange,
        cidr: cidr,
      );
      
    } catch (e) {
      print('NetworkAnalyzer: Erro ao obter informações de rede: $e');
      return null;
    }
  }
  
  /// Calcula CIDR baseado no IP e máscara de sub-rede
  String _calculateCIDR(String ip, String subnet) {
    try {
      final subnetParts = subnet.split('.');
      int cidrBits = 0;
      
      for (String part in subnetParts) {
        int octet = int.parse(part);
        cidrBits += _countBits(octet);
      }
      
      final ipParts = ip.split('.');
      final networkIP = _calculateNetworkAddress(ipParts, subnetParts);
      
      return '$networkIP/$cidrBits';
    } catch (e) {
      print('NetworkAnalyzer: Erro ao calcular CIDR: $e');
      return '$ip/24'; // Fallback para /24
    }
  }
  
  /// Conta bits em um octeto
  int _countBits(int octet) {
    int count = 0;
    while (octet > 0) {
      count += octet & 1;
      octet >>= 1;
    }
    return count;
  }
  
  /// Calcula endereço de rede
  String _calculateNetworkAddress(List<String> ipParts, List<String> subnetParts) {
    List<int> networkParts = [];
    
    for (int i = 0; i < 4; i++) {
      int ipOctet = int.parse(ipParts[i]);
      int subnetOctet = int.parse(subnetParts[i]);
      networkParts.add(ipOctet & subnetOctet);
    }
    
    return networkParts.join('.');
  }
  
  /// Gera range de IPs baseado no IP atual e máscara
  List<String> _generateIPRange(String ip, String subnet) {
    try {
      final ipParts = ip.split('.').map(int.parse).toList();
      final subnetParts = subnet.split('.').map(int.parse).toList();
      
      // Calcula endereço de rede e broadcast
      final networkParts = <int>[];
      final broadcastParts = <int>[];
      
      for (int i = 0; i < 4; i++) {
        networkParts.add(ipParts[i] & subnetParts[i]);
        broadcastParts.add(networkParts[i] | (255 - subnetParts[i]));
      }
      
      // Gera lista de IPs válidos (excluindo rede e broadcast)
      final ipList = <String>[];
      
      // Para redes /24 (mais comum)
      if (subnet == '255.255.255.0') {
        for (int i = 1; i < 255; i++) {
          ipList.add('${networkParts[0]}.${networkParts[1]}.${networkParts[2]}.$i');
        }
      } else {
        // Para outras máscaras, implementação mais complexa
        ipList.addAll(_generateComplexIPRange(networkParts, broadcastParts));
      }
      
      return ipList;
    } catch (e) {
      print('NetworkAnalyzer: Erro ao gerar range de IPs: $e');
      // Fallback: gera range /24 baseado no IP atual
      final parts = ip.split('.');
      final baseIP = '${parts[0]}.${parts[1]}.${parts[2]}';
      return List.generate(254, (i) => '$baseIP.${i + 1}');
    }
  }
  
  /// Gera range de IPs para máscaras complexas
  List<String> _generateComplexIPRange(List<int> network, List<int> broadcast) {
    final ipList = <String>[];
    
    // Implementação simplificada para máscaras não /24
    // Pode ser expandida conforme necessário
    for (int a = network[0]; a <= broadcast[0]; a++) {
      for (int b = (a == network[0] ? network[1] : 0); 
           b <= (a == broadcast[0] ? broadcast[1] : 255); b++) {
        for (int c = (a == network[0] && b == network[1] ? network[2] : 0);
             c <= (a == broadcast[0] && b == broadcast[1] ? broadcast[2] : 255); c++) {
          for (int d = (a == network[0] && b == network[1] && c == network[2] ? network[3] + 1 : 1);
               d < (a == broadcast[0] && b == broadcast[1] && c == broadcast[2] ? broadcast[3] : 255); d++) {
            ipList.add('$a.$b.$c.$d');
            // Limita para evitar listas muito grandes
            if (ipList.length >= 1000) return ipList;
          }
        }
      }
    }
    
    return ipList;
  }
  
  /// Verifica se um IP está na mesma rede
  bool isIPInNetwork(String targetIP, LocalNetworkInfo networkInfo) {
    try {
      return networkInfo.ipRange.contains(targetIP);
    } catch (e) {
      print('NetworkAnalyzer: Erro ao verificar IP na rede: $e');
      return false;
    }
  }
  
  /// Obtém interfaces de rede disponíveis
  Future<List<NetworkInterface>> getNetworkInterfaces() async {
    try {
      return await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
    } catch (e) {
      print('NetworkAnalyzer: Erro ao obter interfaces de rede: $e');
      return [];
    }
  }
  
  /// Monitora mudanças de conectividade
  Stream<ConnectivityResult> get connectivityStream => _connectivity.onConnectivityChanged.map((results) => results.first);
}