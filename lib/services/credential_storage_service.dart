import 'dart:convert';
import 'package:encrypted_shared_preferences/encrypted_shared_preferences.dart';
import '../models/credentials.dart';

class CredentialStorageService {
  static final CredentialStorageService _instance = CredentialStorageService._internal();
  factory CredentialStorageService() => _instance;
  CredentialStorageService._internal();

  late final EncryptedSharedPreferences _prefs;
  bool _initialized = false;

  /// Inicializa o serviço de armazenamento seguro
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      _prefs = EncryptedSharedPreferences();
      _initialized = true;
    } catch (e) {
      throw Exception('Falha ao inicializar armazenamento seguro: $e');
    }
  }

  /// Verifica se o serviço foi inicializado
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('CredentialStorageService não foi inicializado. Chame initialize() primeiro.');
    }
  }

  /// Salva credenciais para uma câmera específica
  Future<void> saveCredentials(String cameraId, Credentials credentials) async {
    _ensureInitialized();
    
    try {
      final key = _getCredentialKey(cameraId);
      final jsonString = jsonEncode(credentials.toJson());
      await _prefs.setString(key, jsonString);
    } catch (e) {
      throw Exception('Falha ao salvar credenciais para câmera $cameraId: $e');
    }
  }

  /// Recupera credenciais para uma câmera específica
  Future<Credentials?> getCredentials(String cameraId) async {
    _ensureInitialized();
    
    try {
      final key = _getCredentialKey(cameraId);
      final jsonString = await _prefs.getString(key);
      
      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }
      
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return Credentials.fromJson(jsonMap);
    } catch (e) {
      throw Exception('Falha ao recuperar credenciais para câmera $cameraId: $e');
    }
  }

  /// Remove credenciais para uma câmera específica
  Future<void> removeCredentials(String cameraId) async {
    _ensureInitialized();
    
    try {
      final key = _getCredentialKey(cameraId);
      await _prefs.remove(key);
    } catch (e) {
      throw Exception('Falha ao remover credenciais para câmera $cameraId: $e');
    }
  }

  /// Verifica se existem credenciais salvas para uma câmera
  Future<bool> hasCredentials(String cameraId) async {
    _ensureInitialized();
    
    try {
      final key = _getCredentialKey(cameraId);
      final value = await _prefs.getString(key);
      return value != null && value.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Lista todas as câmeras que possuem credenciais salvas
  Future<List<String>> getCameraIdsWithCredentials() async {
    _ensureInitialized();
    
    try {
      final keys = await _prefs.getKeys();
      final cameraIds = <String>[];
      
      for (final key in keys) {
        if (key.startsWith(_credentialPrefix)) {
          final cameraId = key.substring(_credentialPrefix.length);
          cameraIds.add(cameraId);
        }
      }
      
      return cameraIds;
    } catch (e) {
      throw Exception('Falha ao listar câmeras com credenciais: $e');
    }
  }

  /// Atualiza credenciais existentes
  Future<void> updateCredentials(String cameraId, Credentials credentials) async {
    await saveCredentials(cameraId, credentials);
  }

  /// Remove todas as credenciais armazenadas
  Future<void> clearAllCredentials() async {
    _ensureInitialized();
    
    try {
      final keys = await _prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_credentialPrefix)) {
          await _prefs.remove(key);
        }
      }
    } catch (e) {
      throw Exception('Falha ao limpar todas as credenciais: $e');
    }
  }

  /// Salva configurações globais de autenticação
  Future<void> saveGlobalAuthSettings(Map<String, dynamic> settings) async {
    _ensureInitialized();
    
    try {
      final jsonString = jsonEncode(settings);
      await _prefs.setString(_globalAuthKey, jsonString);
    } catch (e) {
      throw Exception('Falha ao salvar configurações globais de autenticação: $e');
    }
  }

  /// Recupera configurações globais de autenticação
  Future<Map<String, dynamic>?> getGlobalAuthSettings() async {
    _ensureInitialized();
    
    try {
      final jsonString = await _prefs.getString(_globalAuthKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }
      
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Falha ao recuperar configurações globais de autenticação: $e');
    }
  }

  /// Exporta credenciais para backup (criptografado)
  Future<String> exportCredentials() async {
    _ensureInitialized();
    
    try {
      final cameraIds = await getCameraIdsWithCredentials();
      final exportData = <String, Map<String, dynamic>>{};
      
      for (final cameraId in cameraIds) {
        final credentials = await getCredentials(cameraId);
        if (credentials != null) {
          exportData[cameraId] = credentials.toJson();
        }
      }
      
      return jsonEncode({
        'version': '1.0',
        'timestamp': DateTime.now().toIso8601String(),
        'credentials': exportData,
      });
    } catch (e) {
      throw Exception('Falha ao exportar credenciais: $e');
    }
  }

  /// Importa credenciais de backup
  Future<void> importCredentials(String backupData, {bool overwrite = false}) async {
    _ensureInitialized();
    
    try {
      final data = jsonDecode(backupData) as Map<String, dynamic>;
      final credentialsData = data['credentials'] as Map<String, dynamic>;
      
      for (final entry in credentialsData.entries) {
        final cameraId = entry.key;
        final credentialJson = entry.value as Map<String, dynamic>;
        
        // Verifica se já existe e se deve sobrescrever
        if (!overwrite && await hasCredentials(cameraId)) {
          continue;
        }
        
        final credentials = Credentials.fromJson(credentialJson);
        await saveCredentials(cameraId, credentials);
      }
    } catch (e) {
      throw Exception('Falha ao importar credenciais: $e');
    }
  }

  /// Valida integridade das credenciais armazenadas
  Future<Map<String, bool>> validateStoredCredentials() async {
    _ensureInitialized();
    
    final results = <String, bool>{};
    
    try {
      final cameraIds = await getCameraIdsWithCredentials();
      
      for (final cameraId in cameraIds) {
        try {
          final credentials = await getCredentials(cameraId);
          results[cameraId] = credentials != null && 
                             credentials.username.isNotEmpty && 
                             credentials.password.isNotEmpty;
        } catch (e) {
          results[cameraId] = false;
        }
      }
    } catch (e) {
      // Em caso de erro geral, retorna mapa vazio
    }
    
    return results;
  }

  // Constantes privadas
  static const String _credentialPrefix = 'camera_credentials_';
  static const String _globalAuthKey = 'global_auth_settings';

  /// Gera chave única para credenciais de uma câmera
  String _getCredentialKey(String cameraId) {
    return '$_credentialPrefix$cameraId';
  }

  /// Limpa cache e reinicializa o serviço
  Future<void> reset() async {
    _initialized = false;
    await initialize();
  }
}