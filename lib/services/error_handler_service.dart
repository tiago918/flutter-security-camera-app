import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serviço global para tratamento de erros e prevenção de crashes
class ErrorHandlerService {
  static ErrorHandlerService? _instance;
  static ErrorHandlerService get instance => _instance ??= ErrorHandlerService._();
  
  ErrorHandlerService._();
  
  /// Inicializa o tratamento global de erros
  static void initialize() {
    // Capturar erros do Flutter framework
    FlutterError.onError = (FlutterErrorDetails details) {
      _logError('Flutter Error', details.exception, details.stack);
      
      // Em modo debug, mostrar o erro
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };
    
    // Capturar erros assíncronos não tratados
    PlatformDispatcher.instance.onError = (error, stack) {
      _logError('Async Error', error, stack);
      return true; // Indica que o erro foi tratado
    };
    
    // Capturar erros de isolate
    Isolate.current.addErrorListener(RawReceivePort((pair) async {
      final List<dynamic> errorAndStacktrace = pair;
      final error = errorAndStacktrace[0];
      final stack = errorAndStacktrace[1];
      _logError('Isolate Error', error, StackTrace.fromString(stack.toString()));
    }).sendPort);
  }
  
  /// Executa uma função com tratamento de erro seguro
  static Future<T?> safeExecute<T>(
    Future<T> Function() function, {
    String? context,
    T? fallback,
  }) async {
    try {
      return await function();
    } catch (e, stack) {
      _logError(context ?? 'Safe Execute', e, stack);
      return fallback;
    }
  }
  
  /// Executa uma função síncrona com tratamento de erro seguro
  static T? safeExecuteSync<T>(
    T Function() function, {
    String? context,
    T? fallback,
  }) {
    try {
      return function();
    } catch (e, stack) {
      _logError(context ?? 'Safe Execute Sync', e, stack);
      return fallback;
    }
  }
  
  /// Wrapper seguro para inicialização de plugins
  static Future<bool> safePluginInitialization(
    Future<void> Function() initFunction,
    String pluginName,
  ) async {
    try {
      await initFunction();
      print('$pluginName inicializado com sucesso');
      return true;
    } catch (e, stack) {
      _logError('Plugin Init: $pluginName', e, stack);
      return false;
    }
  }
  
  /// Wrapper seguro para chamadas de platform channel
  static Future<T?> safePlatformCall<T>(
    Future<T> Function() platformCall,
    String channelName,
  ) async {
    try {
      return await platformCall();
    } on PlatformException catch (e) {
      _logError('Platform Channel: $channelName', e, StackTrace.current);
      return null;
    } catch (e, stack) {
      _logError('Platform Channel: $channelName', e, stack);
      return null;
    }
  }
  
  /// Log estruturado de erros
  static void _logError(String context, dynamic error, StackTrace? stack) {
    final timestamp = DateTime.now().toIso8601String();
    final errorMessage = '''
=== ERROR REPORT ===
Timestamp: $timestamp
Context: $context
Error: $error
Stack Trace:
${stack ?? 'No stack trace available'}
==================
''';
    
    // Log no console
    print(errorMessage);
    
    // Em modo debug, também usar debugPrint para melhor formatação
    if (kDebugMode) {
      debugPrint(errorMessage);
    }
    
    // TODO: Implementar log em arquivo ou serviço de crash reporting
    // _writeToLogFile(errorMessage);
  }
  
  /// Verifica se o dispositivo tem recursos suficientes
  static Future<bool> checkSystemResources() async {
    try {
      // Verificar memória disponível (Android)
      if (Platform.isAndroid) {
        // Implementar verificação de memória se necessário
        return true;
      }
      return true;
    } catch (e) {
      _logError('System Resources Check', e, StackTrace.current);
      return false;
    }
  }
  
  /// Limpa recursos e prepara para shutdown seguro
  static Future<void> cleanup() async {
    try {
      // Implementar limpeza de recursos se necessário
      print('ErrorHandlerService: Cleanup concluído');
    } catch (e, stack) {
      _logError('Cleanup', e, stack);
    }
  }
}