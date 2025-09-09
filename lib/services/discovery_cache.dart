import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Modelo para dispositivo em cache
class CachedDevice {
  final String ip;
  final String? name;
  final String? manufacturer;
  final String protocol;
  final List<int> ports;
  final DateTime discoveredAt;
  final DateTime lastSeen;
  final int responseTime; // em millisegundos
  final bool isOnline;
  final Map<String, dynamic> metadata;
  
  CachedDevice({
    required this.ip,
    this.name,
    this.manufacturer,
    required this.protocol,
    required this.ports,
    required this.discoveredAt,
    required this.lastSeen,
    required this.responseTime,
    required this.isOnline,
    this.metadata = const {},
  });
  
  /// Cria uma cópia com campos atualizados
  CachedDevice copyWith({
    String? ip,
    String? name,
    String? manufacturer,
    String? protocol,
    List<int>? ports,
    DateTime? discoveredAt,
    DateTime? lastSeen,
    int? responseTime,
    bool? isOnline,
    Map<String, dynamic>? metadata,
  }) {
    return CachedDevice(
      ip: ip ?? this.ip,
      name: name ?? this.name,
      manufacturer: manufacturer ?? this.manufacturer,
      protocol: protocol ?? this.protocol,
      ports: ports ?? this.ports,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      lastSeen: lastSeen ?? this.lastSeen,
      responseTime: responseTime ?? this.responseTime,
      isOnline: isOnline ?? this.isOnline,
      metadata: metadata ?? this.metadata,
    );
  }
  
  /// Converte para JSON
  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'name': name,
      'manufacturer': manufacturer,
      'protocol': protocol,
      'ports': ports,
      'discoveredAt': discoveredAt.millisecondsSinceEpoch,
      'lastSeen': lastSeen.millisecondsSinceEpoch,
      'responseTime': responseTime,
      'isOnline': isOnline,
      'metadata': metadata,
    };
  }
  
  /// Cria a partir de JSON
  factory CachedDevice.fromJson(Map<String, dynamic> json) {
    return CachedDevice(
      ip: json['ip'] as String,
      name: json['name'] as String?,
      manufacturer: json['manufacturer'] as String?,
      protocol: json['protocol'] as String,
      ports: List<int>.from(json['ports'] as List),
      discoveredAt: DateTime.fromMillisecondsSinceEpoch(json['discoveredAt'] as int),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int),
      responseTime: json['responseTime'] as int,
      isOnline: json['isOnline'] as bool,
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
    );
  }
  
  /// Verifica se o dispositivo está expirado
  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(lastSeen) > maxAge;
  }
  
  /// Calcula prioridade baseada em fatores
  double get priority {
    final now = DateTime.now();
    final ageHours = now.difference(lastSeen).inHours;
    final responseFactor = 1000.0 / (responseTime + 100); // Menor tempo = maior prioridade
    final ageFactor = 1.0 / (ageHours + 1); // Mais recente = maior prioridade
    final onlineFactor = isOnline ? 2.0 : 0.5;
    
    return responseFactor * ageFactor * onlineFactor;
  }
  
  @override
  String toString() {
    return 'CachedDevice(ip: $ip, name: $name, protocol: $protocol, online: $isOnline, responseTime: ${responseTime}ms)';
  }
}

/// Service para cache inteligente de descoberta de dispositivos
class DiscoveryCache {
  static final DiscoveryCache _instance = DiscoveryCache._internal();
  factory DiscoveryCache() => _instance;
  DiscoveryCache._internal();
  
  static const String _cacheKey = 'discovery_cache';
  static const Duration _defaultMaxAge = Duration(hours: 24);
  static const Duration _defaultCleanupInterval = Duration(hours: 6);
  
  final Map<String, CachedDevice> _cache = {};
  final StreamController<List<CachedDevice>> _cacheController = StreamController.broadcast();
  Timer? _cleanupTimer;
  bool _isInitialized = false;
  
  /// Stream de mudanças no cache
  Stream<List<CachedDevice>> get cacheStream => _cacheController.stream;
  
  /// Inicializa o cache
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _loadFromStorage();
      _startCleanupTimer();
      _isInitialized = true;
      print('DiscoveryCache: Inicializado com ${_cache.length} dispositivos');
    } catch (e) {
      print('DiscoveryCache: Erro ao inicializar: $e');
    }
  }
  
  /// Adiciona ou atualiza dispositivo no cache (alias para addDevice)
  Future<void> addOrUpdateDevice(CachedDevice device) async {
    await addDevice(device);
  }

  /// Adiciona ou atualiza dispositivo no cache
  Future<void> addDevice(CachedDevice device) async {
    try {
      final existing = _cache[device.ip];
      
      if (existing != null) {
        // Atualiza dispositivo existente
        _cache[device.ip] = existing.copyWith(
          name: device.name ?? existing.name,
          manufacturer: device.manufacturer ?? existing.manufacturer,
          protocol: device.protocol,
          ports: device.ports,
          lastSeen: device.lastSeen,
          responseTime: device.responseTime,
          isOnline: device.isOnline,
          metadata: {...existing.metadata, ...device.metadata},
        );
      } else {
        // Adiciona novo dispositivo
        _cache[device.ip] = device;
      }
      
      await _saveToStorage();
      _notifyListeners();
      
      print('DiscoveryCache: Dispositivo ${device.ip} adicionado/atualizado');
    } catch (e) {
      print('DiscoveryCache: Erro ao adicionar dispositivo: $e');
    }
  }
  
  /// Obtém dispositivo do cache
  CachedDevice? getDevice(String ip) {
    return _cache[ip];
  }
  
  /// Obtém todos os dispositivos do cache
  List<CachedDevice> getAllDevices({bool onlineOnly = false}) {
    final devices = _cache.values.toList();
    
    if (onlineOnly) {
      return devices.where((d) => d.isOnline).toList();
    }
    
    return devices;
  }
  
  /// Obtém dispositivos por protocolo
  List<CachedDevice> getDevicesByProtocol(String protocol) {
    return _cache.values
        .where((d) => d.protocol.toLowerCase() == protocol.toLowerCase())
        .toList();
  }
  
  /// Obtém dispositivos ordenados por prioridade
  List<CachedDevice> getDevicesByPriority({int? limit}) {
    final devices = _cache.values.toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    
    if (limit != null && limit > 0) {
      return devices.take(limit).toList();
    }
    
    return devices;
  }
  
  /// Marca dispositivo como offline
  Future<void> markDeviceOffline(String ip) async {
    final device = _cache[ip];
    if (device != null) {
      _cache[ip] = device.copyWith(isOnline: false);
      await _saveToStorage();
      _notifyListeners();
    }
  }
  
  /// Remove dispositivo do cache
  Future<void> removeDevice(String ip) async {
    if (_cache.remove(ip) != null) {
      await _saveToStorage();
      _notifyListeners();
      print('DiscoveryCache: Dispositivo $ip removido');
    }
  }
  
  /// Limpa dispositivos expirados
  Future<int> cleanupExpiredDevices({Duration? maxAge}) async {
    final age = maxAge ?? _defaultMaxAge;
    final toRemove = <String>[];
    
    for (final entry in _cache.entries) {
      if (entry.value.isExpired(age)) {
        toRemove.add(entry.key);
      }
    }
    
    for (final ip in toRemove) {
      _cache.remove(ip);
    }
    
    if (toRemove.isNotEmpty) {
      await _saveToStorage();
      _notifyListeners();
      print('DiscoveryCache: ${toRemove.length} dispositivos expirados removidos');
    }
    
    return toRemove.length;
  }
  
  /// Limpa todo o cache
  Future<void> clearCache() async {
    _cache.clear();
    await _saveToStorage();
    _notifyListeners();
    print('DiscoveryCache: Cache limpo');
  }
  
  /// Calcula timeout adaptativo baseado no histórico
  Duration getAdaptiveTimeout(String ip, {Duration defaultTimeout = const Duration(seconds: 5)}) {
    final device = _cache[ip];
    
    if (device == null) {
      return defaultTimeout;
    }
    
    // Calcula timeout baseado no tempo de resposta histórico
    final baseTimeout = Duration(milliseconds: device.responseTime * 2);
    final minTimeout = Duration(milliseconds: 1000);
    final maxTimeout = Duration(seconds: 30);
    
    if (baseTimeout < minTimeout) return minTimeout;
    if (baseTimeout > maxTimeout) return maxTimeout;
    
    return baseTimeout;
  }
  
  /// Obtém estatísticas do cache (alias para getStatistics)
  Future<Map<String, dynamic>> getStats() async {
    return getStatistics();
  }

  /// Obtém estatísticas do cache
  Map<String, dynamic> getStatistics() {
    final devices = _cache.values.toList();
    final onlineDevices = devices.where((d) => d.isOnline).length;
    final protocols = devices.map((d) => d.protocol).toSet();
    final avgResponseTime = devices.isEmpty 
        ? 0 
        : devices.map((d) => d.responseTime).reduce((a, b) => a + b) / devices.length;
    
    return {
      'totalDevices': devices.length,
      'onlineDevices': onlineDevices,
      'offlineDevices': devices.length - onlineDevices,
      'protocols': protocols.toList(),
      'averageResponseTime': avgResponseTime.round(),
      'cacheSize': _calculateCacheSize(),
    };
  }
  
  /// Carrega cache do armazenamento
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString(_cacheKey);
      
      if (cacheData != null) {
        final Map<String, dynamic> data = jsonDecode(cacheData);
        
        for (final entry in data.entries) {
          try {
            _cache[entry.key] = CachedDevice.fromJson(entry.value);
          } catch (e) {
            print('DiscoveryCache: Erro ao carregar dispositivo ${entry.key}: $e');
          }
        }
      }
    } catch (e) {
      print('DiscoveryCache: Erro ao carregar do armazenamento: $e');
    }
  }
  
  /// Salva cache no armazenamento
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> data = {};
      
      for (final entry in _cache.entries) {
        data[entry.key] = entry.value.toJson();
      }
      
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (e) {
      print('DiscoveryCache: Erro ao salvar no armazenamento: $e');
    }
  }
  
  /// Inicia timer de limpeza automática
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_defaultCleanupInterval, (_) {
      cleanupExpiredDevices();
    });
  }
  
  /// Notifica listeners sobre mudanças
  void _notifyListeners() {
    if (!_cacheController.isClosed) {
      _cacheController.add(getAllDevices());
    }
  }
  
  /// Calcula tamanho do cache em bytes (aproximado)
  int _calculateCacheSize() {
    try {
      final data = _cache.map((k, v) => MapEntry(k, v.toJson()));
      return jsonEncode(data).length;
    } catch (e) {
      return 0;
    }
  }
  
  /// Dispose do cache
  void dispose() {
    _cleanupTimer?.cancel();
    _cacheController.close();
    _isInitialized = false;
  }
}