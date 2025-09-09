import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Configurações gráficas adaptativas para otimizar renderização de vídeo
/// baseado nas capacidades do hardware do dispositivo
class GraphicsConfig {
  static const int _minBufferSize = 1024 * 1024; // 1MB
  static const int _maxBufferSize = 8 * 1024 * 1024; // 8MB
  static const int _defaultBufferSize = 2 * 1024 * 1024; // 2MB

  /// Obtém configurações otimizadas baseadas no hardware do dispositivo
  static Future<Map<String, dynamic>> getOptimalSettings() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return _getAndroidOptimalSettings(androidInfo);
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return _getIOSOptimalSettings(iosInfo);
      }
    } catch (e) {
      debugPrint('Erro ao obter informações do dispositivo: $e');
    }
    
    return _getDefaultSettings();
  }

  /// Configurações otimizadas para dispositivos Android
  static Map<String, dynamic> _getAndroidOptimalSettings(AndroidDeviceInfo androidInfo) {
    final sdkInt = androidInfo.version.sdkInt;
    final totalMemory = _estimateMemoryFromModel(androidInfo.model);
    final isLowEnd = _isLowEndDevice(androidInfo);
    
    return {
      'useHardwareAcceleration': _supportsHardwareAcceleration(androidInfo),
      'bufferSize': _getOptimalBufferSize(totalMemory, isLowEnd),
      'renderingMode': _getOptimalRenderingMode(androidInfo),
      'textureFormat': _getSupportedTextureFormat(sdkInt),
      'maxConcurrentStreams': isLowEnd ? 1 : 2,
      'enableGPUDecoding': !isLowEnd && sdkInt >= 21,
      'useExoPlayer': sdkInt >= 16,
      'enableSurfaceView': true,
      'pixelFormat': _getOptimalPixelFormat(androidInfo),
      'compressionLevel': isLowEnd ? 'high' : 'medium',
    };
  }

  /// Configurações otimizadas para dispositivos iOS
  static Map<String, dynamic> _getIOSOptimalSettings(IosDeviceInfo iosInfo) {
    final isOldDevice = _isOldIOSDevice(iosInfo);
    
    return {
      'useHardwareAcceleration': true,
      'bufferSize': isOldDevice ? _minBufferSize : _defaultBufferSize,
      'renderingMode': 'metal',
      'textureFormat': 'bgra8888',
      'maxConcurrentStreams': isOldDevice ? 1 : 3,
      'enableGPUDecoding': true,
      'useAVPlayer': true,
      'enableMetalRenderer': !isOldDevice,
      'pixelFormat': 'yuv420p',
      'compressionLevel': isOldDevice ? 'high' : 'low',
    };
  }

  /// Configurações padrão para dispositivos não identificados
  static Map<String, dynamic> _getDefaultSettings() {
    return {
      'useHardwareAcceleration': false,
      'bufferSize': _defaultBufferSize,
      'renderingMode': 'software',
      'textureFormat': 'rgba8888',
      'maxConcurrentStreams': 1,
      'enableGPUDecoding': false,
      'pixelFormat': 'yuv420p',
      'compressionLevel': 'medium',
    };
  }

  /// Verifica se o dispositivo suporta aceleração por hardware
  static bool _supportsHardwareAcceleration(AndroidDeviceInfo androidInfo) {
    final sdkInt = androidInfo.version.sdkInt;
    final isEmulator = androidInfo.isPhysicalDevice == false;
    
    // Desabilitar aceleração em emuladores e versões muito antigas
    if (isEmulator || sdkInt < 16) {
      return false;
    }
    
    // Verificar se há problemas conhecidos com GPU específicas
    final model = androidInfo.model.toLowerCase();
    final problematicModels = ['generic', 'sdk', 'emulator'];
    
    return !problematicModels.any((problem) => model.contains(problem));
  }

  /// Calcula o tamanho ótimo do buffer baseado na memória disponível
  static int _getOptimalBufferSize(int totalMemoryMB, bool isLowEnd) {
    if (isLowEnd || totalMemoryMB < 1024) {
      return _minBufferSize;
    } else if (totalMemoryMB < 2048) {
      return _defaultBufferSize;
    } else if (totalMemoryMB < 4096) {
      return 4 * 1024 * 1024; // 4MB
    } else {
      return _maxBufferSize;
    }
  }

  /// Determina o modo de renderização ótimo
  static String _getOptimalRenderingMode(AndroidDeviceInfo androidInfo) {
    final sdkInt = androidInfo.version.sdkInt;
    final isLowEnd = _isLowEndDevice(androidInfo);
    
    if (isLowEnd || sdkInt < 18) {
      return 'software';
    } else if (sdkInt >= 21) {
      return 'hardware';
    } else {
      return 'hybrid';
    }
  }

  /// Obtém o formato de textura suportado
  static String _getSupportedTextureFormat(int sdkInt) {
    if (sdkInt >= 21) {
      return 'yuv420p'; // Mais eficiente para hardware moderno
    } else if (sdkInt >= 16) {
      return 'rgba8888';
    } else {
      return 'rgb565'; // Fallback para dispositivos muito antigos
    }
  }

  /// Obtém o formato de pixel ótimo
  static String _getOptimalPixelFormat(AndroidDeviceInfo androidInfo) {
    final sdkInt = androidInfo.version.sdkInt;
    
    if (sdkInt >= 21 && !_isLowEndDevice(androidInfo)) {
      return 'yuv420p';
    } else {
      return 'rgb24';
    }
  }

  /// Verifica se é um dispositivo de baixo desempenho
  static bool _isLowEndDevice(AndroidDeviceInfo androidInfo) {
    final sdkInt = androidInfo.version.sdkInt;
    final model = androidInfo.model.toLowerCase();
    
    // Critérios para dispositivos de baixo desempenho
    if (sdkInt < 21) return true;
    
    // Modelos conhecidos de baixo desempenho
    final lowEndKeywords = [
      'go', 'lite', 'mini', 'entry', 'basic',
      'sm-j', 'sm-a0', 'sm-a1', // Samsung Galaxy J/A series antigas
      'moto e', 'moto g4', 'moto g5', // Motorola entry level
    ];
    
    return lowEndKeywords.any((keyword) => model.contains(keyword));
  }

  /// Verifica se é um dispositivo iOS antigo
  static bool _isOldIOSDevice(IosDeviceInfo iosInfo) {
    final model = iosInfo.model.toLowerCase();
    
    // Dispositivos iOS considerados antigos
    final oldModels = [
      'iphone 5', 'iphone 6', 'iphone se',
      'ipad 2', 'ipad 3', 'ipad 4',
      'ipod touch'
    ];
    
    return oldModels.any((oldModel) => model.contains(oldModel));
  }

  /// Estima a memória total baseada no modelo do dispositivo
  static int _estimateMemoryFromModel(String model) {
    final modelLower = model.toLowerCase();
    
    // Estimativas baseadas em modelos conhecidos
    if (modelLower.contains('flagship') || modelLower.contains('pro')) {
      return 8192; // 8GB
    } else if (modelLower.contains('plus') || modelLower.contains('max')) {
      return 6144; // 6GB
    } else if (modelLower.contains('lite') || modelLower.contains('go')) {
      return 1024; // 1GB
    } else {
      return 3072; // 3GB (padrão)
    }
  }

  /// Configurações específicas para diferentes cenários de uso
  static Map<String, dynamic> getConfigForScenario(String scenario) {
    switch (scenario) {
      case 'single_stream':
        return {
          'maxConcurrentStreams': 1,
          'bufferSize': _defaultBufferSize,
          'compressionLevel': 'low',
        };
      
      case 'multiple_streams':
        return {
          'maxConcurrentStreams': 4,
          'bufferSize': _minBufferSize,
          'compressionLevel': 'high',
        };
      
      case 'recording':
        return {
          'maxConcurrentStreams': 1,
          'bufferSize': _maxBufferSize,
          'compressionLevel': 'medium',
          'enableGPUDecoding': true,
        };
      
      case 'low_bandwidth':
        return {
          'maxConcurrentStreams': 1,
          'bufferSize': _minBufferSize,
          'compressionLevel': 'high',
          'useHardwareAcceleration': false,
        };
      
      default:
        return _getDefaultSettings();
    }
  }

  /// Detecta problemas gráficos em tempo real
  static bool hasGraphicsIssues(String errorMessage) {
    final graphicsErrors = [
      'graphicbufferallocator',
      'ahardwarebuffer',
      'failed to allocate',
      'gralloc',
      'adreno',
      'gpu',
      'opengl',
      'egl',
    ];
    
    final errorLower = errorMessage.toLowerCase();
    return graphicsErrors.any((error) => errorLower.contains(error));
  }

  /// Obtém configurações de fallback para problemas gráficos
  static Map<String, dynamic> getFallbackSettings() {
    return {
      'useHardwareAcceleration': false,
      'bufferSize': _minBufferSize,
      'renderingMode': 'software',
      'textureFormat': 'rgb565',
      'maxConcurrentStreams': 1,
      'enableGPUDecoding': false,
      'pixelFormat': 'rgb24',
      'compressionLevel': 'high',
      'useSoftwareDecoder': true,
    };
  }
}

/// Enumeração para diferentes modos de renderização
enum RenderingMode {
  software,
  hardware,
  hybrid,
  metal, // iOS apenas
}

/// Enumeração para formatos de textura
enum TextureFormat {
  rgb565,
  rgba8888,
  bgra8888,
  yuv420p,
  nv21,
}

/// Enumeração para níveis de compressão
enum CompressionLevel {
  low,
  medium,
  high,
}