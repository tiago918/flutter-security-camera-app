/// Constantes de portas para diferentes fabricantes de câmeras
/// Baseado no plano técnico de melhorias do app de câmeras
class CameraPorts {
  /// Portas HTTP comuns para câmeras IP
  static const List<int> httpPorts = [
    8899,  // Porta prioritária para câmeras (comum em muitas câmeras IP)
    // 80 removida - muito comum em roteadores e outros dispositivos
    8080,  // HTTP alternativo
    8081,  // HTTP alternativo
    8000,  // HTTP alternativo
    8008,  // HTTP alternativo
    8888,  // HTTP alternativo
    9000,  // HTTP alternativo
    81,    // HTTP alternativo
    82,    // HTTP alternativo
    83,    // HTTP alternativo
    8082,  // HTTP alternativo
    8083,  // HTTP alternativo
    8084,  // HTTP alternativo
    8085,  // HTTP alternativo
    8086,  // HTTP alternativo
    8087,  // HTTP alternativo
    8088,  // HTTP alternativo
    8089,  // HTTP alternativo
    8090,  // HTTP alternativo
    8091,  // HTTP alternativo
    8092,  // HTTP alternativo
    8093,  // HTTP alternativo
    8094,  // HTTP alternativo
    8095,  // HTTP alternativo
    8096,  // HTTP alternativo
    8097,  // HTTP alternativo
    8098,  // HTTP alternativo
    8099,  // HTTP alternativo
  ];
  
  // Portas RTSP (priorizadas para descoberta rápida)
  static const List<int> rtspPorts = [
    554, 8554, 1935, 7001, 5554, 8000, 8080
  ];
  
  // Portas ONVIF
  static const List<int> onvifPorts = [
    8080, 8000, 8899, 554, 8554, 3702  // 80 removida - muito comum em roteadores
  ];
  
  /// Portas mais comuns (primeira prioridade no scan)
  static const List<int> mostCommonPorts = [
    8899,  // Porta prioritária para câmeras IP
    // 80 removida - muito comum em roteadores
    554,   // RTSP
    8080,  // HTTP alternativo
    8081,  // HTTP alternativo
    37777, // Dahua
    34567, // Hikvision
    8000,  // HTTP alternativo
    9000,  // HTTP alternativo
  ];
  
  // Portas RTSP prioritárias para fallback quando mDNS falha
  static const List<int> rtspPriorityPorts = [
    554, 8554, 1935
  ];
  
  // Portas Proprietárias por Fabricante
  static const Map<String, List<int>> proprietaryPorts = {
    'hikvision': [8000, 554, 8080],  // 80 removida
    'dahua': [37777, 554, 8080],     // 80 removida
    'axis': [554, 8080, 8000],       // 80 removida
    'foscam': [88, 554, 8080],       // 80 removida
    'tp-link': [554, 8080, 9000],    // 80 removida
    'xiaomi': [554, 8080, 8000],     // 80 removida
    'reolink': [554, 9000, 8000],    // 80 removida
    'amcrest': [554, 37777, 8080],   // 80 removida
    'generic': [554, 8080, 8899, 34567, 37777, 9000, 6036]  // 80 removida
  };
  
  // Timeouts otimizados por tipo de scan
  static const Map<String, int> scanTimeouts = {
    'fast': 2, // Para portas RTSP prioritárias
    'common': 3, // Para portas comuns
    'rtsp': 5, // Para todas as portas RTSP
    'full': 10, // Para scan completo
  };
  
  /// Retorna todas as portas únicas combinadas
  static List<int> getAllPorts() {
    final allPorts = <int>{};
    allPorts.addAll(httpPorts);
    allPorts.addAll(rtspPorts);
    allPorts.addAll(onvifPorts);
    
    // Adicionar portas proprietárias
    for (final ports in proprietaryPorts.values) {
      allPorts.addAll(ports);
    }
    
    return allPorts.toList()..sort();
  }
  
  /// Retorna portas específicas para um fabricante
  static List<int> getPortsForManufacturer(String manufacturer) {
    final manufacturerKey = manufacturer.toLowerCase();
    return proprietaryPorts[manufacturerKey] ?? proprietaryPorts['generic']!;
  }
  
  /// Retorna portas priorizadas para descoberta rápida
  /// Prioriza portas RTSP primeiro, depois outras portas comuns (excluindo duplicatas)
  static List<int> getFastDiscoveryPorts() {
    final prioritizedPorts = <int>[];
    
    // Primeiro: portas RTSP prioritárias
    prioritizedPorts.addAll(rtspPriorityPorts);
    
    // Segundo: portas comuns que não são RTSP
    for (final port in mostCommonPorts) {
      if (!rtspPriorityPorts.contains(port)) {
        prioritizedPorts.add(port);
      }
    }
    
    return prioritizedPorts;
  }
  
  /// Verifica se uma porta é considerada de streaming (RTSP)
  static bool isStreamingPort(int port) {
    return rtspPorts.contains(port);
  }
  
  /// Verifica se uma porta é considerada de interface web
  static bool isWebInterfacePort(int port) {
    return httpPorts.contains(port);
  }
  
  /// Verifica se uma porta é considerada ONVIF
  static bool isOnvifPort(int port) {
    return onvifPorts.contains(port);
  }
  
  /// Retorna portas ordenadas dinamicamente por probabilidade de serem câmeras reais
  /// Considera fatores como: tipo de protocolo, exclusividade para câmeras, histórico
  static List<int> getDynamicPriorityPorts() {
    final portScores = <int, double>{};
    
    // Pontuação base para portas RTSP (alta probabilidade de câmera)
    for (final port in rtspPorts) {
      portScores[port] = (portScores[port] ?? 0) + 10.0;
    }
    
    // Pontuação extra para portas RTSP prioritárias
    for (final port in rtspPriorityPorts) {
      portScores[port] = (portScores[port] ?? 0) + 5.0;
    }
    
    // Pontuação para portas proprietárias específicas de câmeras
    const cameraSpecificPorts = [37777, 34567, 8899, 6036]; // Dahua, Hikvision, etc.
    for (final port in cameraSpecificPorts) {
      portScores[port] = (portScores[port] ?? 0) + 8.0;
    }
    
    // Pontuação para portas ONVIF
    for (final port in onvifPorts) {
      portScores[port] = (portScores[port] ?? 0) + 6.0;
    }
    
    // Pontuação reduzida para portas HTTP comuns (podem ser roteadores)
    const commonWebPorts = [8080, 8000, 9000];
    for (final port in commonWebPorts) {
      portScores[port] = (portScores[port] ?? 0) + 3.0;
    }
    
    // Penalização para porta 80 (muito comum em dispositivos não-câmera)
    portScores[80] = (portScores[80] ?? 0) - 5.0;
    
    // Ordena por pontuação (maior primeiro)
    final sortedPorts = portScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedPorts.map((entry) => entry.key).toList();
  }
  
  /// Retorna portas otimizadas para descoberta inteligente
  /// Combina priorização dinâmica com descoberta rápida
  static List<int> getIntelligentDiscoveryPorts() {
    final dynamicPorts = getDynamicPriorityPorts();
    final fastPorts = getFastDiscoveryPorts();
    
    // Combina mantendo a ordem dinâmica, mas garantindo que portas rápidas estejam incluídas
    final intelligentPorts = <int>[];
    
    // Primeiro: portas com alta pontuação dinâmica
    for (final port in dynamicPorts.take(10)) { // Top 10 portas mais prováveis
      intelligentPorts.add(port);
    }
    
    // Segundo: adiciona portas rápidas que não estão na lista
    for (final port in fastPorts) {
      if (!intelligentPorts.contains(port)) {
        intelligentPorts.add(port);
      }
    }
    
    return intelligentPorts;
  }
}