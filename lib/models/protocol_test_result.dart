/// Resultado do teste de protocolo de câmera
class ProtocolTestResult {
  final bool isSupported;
  final String protocol;
  final int? port;
  final String? error;
  final Map<String, dynamic>? additionalInfo;

  const ProtocolTestResult({
    required this.isSupported,
    required this.protocol,
    this.port,
    this.error,
    this.additionalInfo,
  });

  /// Cria um resultado de sucesso
  factory ProtocolTestResult.success({
    required String protocol,
    int? port,
    Map<String, dynamic>? additionalInfo,
  }) {
    return ProtocolTestResult(
      isSupported: true,
      protocol: protocol,
      port: port,
      additionalInfo: additionalInfo,
    );
  }

  /// Cria um resultado de falha
  factory ProtocolTestResult.failure({
    required String protocol,
    String? error,
  }) {
    return ProtocolTestResult(
      isSupported: false,
      protocol: protocol,
      error: error,
    );
  }

  /// Converte para JSON
  Map<String, dynamic> toJson() {
    return {
      'isSupported': isSupported,
      'protocol': protocol,
      'port': port,
      'error': error,
      'additionalInfo': additionalInfo,
    };
  }

  /// Cria a partir de JSON
  factory ProtocolTestResult.fromJson(Map<String, dynamic> json) {
    return ProtocolTestResult(
      isSupported: json['isSupported'] ?? false,
      protocol: json['protocol'] ?? '',
      port: json['port'],
      error: json['error'],
      additionalInfo: json['additionalInfo'],
    );
  }

  @override
  String toString() {
    return 'ProtocolTestResult(isSupported: $isSupported, protocol: $protocol, port: $port, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProtocolTestResult &&
        other.isSupported == isSupported &&
        other.protocol == protocol &&
        other.port == port &&
        other.error == error;
  }

  @override
  int get hashCode {
    return isSupported.hashCode ^
        protocol.hashCode ^
        port.hashCode ^
        error.hashCode;
  }
}