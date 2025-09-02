import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class AuthService {
  static const String _isAuthenticatedKey = 'is_authenticated';
  static const String _usernameKey = 'stored_username';
  static const String _passwordHashKey = 'stored_password_hash';
  static const String _sessionTimeoutKey = 'session_timeout';
  
  // Configurações padrão internas (apenas para primeira execução)
  static const String _defaultUsername = 'admin';
  static const String _defaultPassword = 'admin123';
  static const int sessionTimeoutMinutes = 30;
  
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  
  AuthService._();
  
  // Verifica se o usuário está autenticado
  Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    final isAuth = prefs.getBool(_isAuthenticatedKey) ?? false;
    
    if (!isAuth) return false;
    
    // Verifica se a sessão expirou
    final sessionTimeout = prefs.getInt(_sessionTimeoutKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    if (now > sessionTimeout) {
      await logout();
      return false;
    }
    
    return true;
  }
  
  // Verifica se está em modo guest (não autenticado)
  Future<bool> isGuestMode() async {
    return !(await isAuthenticated());
  }
  
  // Realiza login
  Future<bool> login(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Verifica se existem credenciais salvas
    final storedUsername = prefs.getString(_usernameKey);
    final storedPasswordHash = prefs.getString(_passwordHashKey);
    
    String validUsername;
    String validPasswordHash;
    
    if (storedUsername == null || storedPasswordHash == null) {
      // Primeira vez - usar credenciais padrão internas
      validUsername = _defaultUsername;
      validPasswordHash = _hashPassword(_defaultPassword);
      
      // Salvar credenciais padrão
      await prefs.setString(_usernameKey, validUsername);
      await prefs.setString(_passwordHashKey, validPasswordHash);
    } else {
      validUsername = storedUsername;
      validPasswordHash = storedPasswordHash;
    }
    
    // Verificar credenciais
    if (username == validUsername && _hashPassword(password) == validPasswordHash) {
      // Login bem-sucedido
      await prefs.setBool(_isAuthenticatedKey, true);
      
      // Definir timeout da sessão
      final timeout = DateTime.now().add(const Duration(minutes: sessionTimeoutMinutes));
      await prefs.setInt(_sessionTimeoutKey, timeout.millisecondsSinceEpoch);
      
      return true;
    }
    
    return false;
  }
  
  // Realiza logout
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isAuthenticatedKey, false);
    await prefs.remove(_sessionTimeoutKey);
  }
  
  // Altera senha
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    final prefs = await SharedPreferences.getInstance();
    final storedPasswordHash = prefs.getString(_passwordHashKey);
    
    if (storedPasswordHash == null) return false;
    
    // Verifica senha atual
    if (_hashPassword(currentPassword) != storedPasswordHash) {
      return false;
    }
    
    // Salva nova senha
    await prefs.setString(_passwordHashKey, _hashPassword(newPassword));
    return true;
  }
  
  // Obtém nome de usuário atual
  Future<String> getCurrentUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey) ?? _defaultUsername;
  }
  
  // Renova sessão
  Future<void> renewSession() async {
    if (await isAuthenticated()) {
      final prefs = await SharedPreferences.getInstance();
      final timeout = DateTime.now().add(const Duration(minutes: sessionTimeoutMinutes));
      await prefs.setInt(_sessionTimeoutKey, timeout.millisecondsSinceEpoch);
    }
  }
  
  // Hash da senha usando SHA-256
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  // Verifica se funcionalidade requer autenticação
  bool requiresAuthentication(String feature) {
    const restrictedFeatures = {
      'ptz_control',
      'recording',
      'motion_detection',
      'night_mode',
      'audio_control',
      'camera_settings',
      'add_camera',
      'remove_camera',
      'access_control',
      'security_settings',
      'notifications',
      'playback',
      'auto_recording'
    };
    
    return restrictedFeatures.contains(feature);
  }
}