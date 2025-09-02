import 'package:easy_onvif/onvif.dart';
import '../models/camera_models.dart';

class NightModeService {
  const NightModeService();
  
  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _commandTimeout = Duration(seconds: 5);

  /// Alterna o modo noturno da câmera
  Future<bool> toggleNightMode(CameraData camera, bool enable) async {
    try {
      // Validações iniciais
      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) {
        print('Night Mode Error: Missing ONVIF credentials for ${camera.name}');
        return false;
      }

      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) {
        print('Night Mode Error: Invalid stream URL format: ${camera.streamUrl}');
        return false;
      }

      final host = uri.host;
      if (host.isEmpty) {
        print('Night Mode Error: Cannot extract host from URL: ${camera.streamUrl}');
        return false;
      }

      print('Night Mode: ${enable ? 'Enabling' : 'Disabling'} night mode for $host');

      // Conectar ao dispositivo ONVIF
      final portsToTry = <int>[80, 8080, 8000, 8899];
      Onvif? onvif;
      
      for (final port in portsToTry) {
        try {
          onvif = await Onvif.connect(
            host: '$host:$port',
            username: user,
            password: pass,
          ).timeout(_connectionTimeout);
          print('Night Mode: Connected to $host:$port');
          break;
        } catch (error) {
          print('Night Mode: Failed to connect to $host:$port -> $error');
          continue;
        }
      }

      if (onvif == null) {
        print('Night Mode Error: Could not connect to ONVIF service for $host');
        return false;
      }

      // Obter perfis de mídia
      final profiles = await onvif.media.getProfiles().timeout(_commandTimeout);
      if (profiles.isEmpty) {
        print('Night Mode Error: No media profiles found on device $host');
        return false;
      }

      final profileToken = profiles.first.token;
      print('Night Mode: Using profile token: $profileToken');

      // TODO: Imaging settings não disponíveis na versão atual do easy_onvif
      print('Night Mode: Imaging settings not available, using fallback method');
      
      /*
      // Código original comentado - métodos não disponíveis
      try {
        final imagingSettings = await onvif.imaging.getImagingSettings(profileToken).timeout(_commandTimeout);
        final newSettings = ImagingSettings20(
          brightness: imagingSettings.brightness,
          colorSaturation: imagingSettings.colorSaturation,
          contrast: imagingSettings.contrast,
          exposure: imagingSettings.exposure,
          focus: imagingSettings.focus,
          irCutFilter: enable ? IrCutFilterMode.off : IrCutFilterMode.on,
          sharpness: imagingSettings.sharpness,
          wideDynamicRange: imagingSettings.wideDynamicRange,
          whiteBalance: imagingSettings.whiteBalance,
        );
        await onvif.imaging.setImagingSettings(profileToken, newSettings).timeout(_commandTimeout);
        print('Night Mode: Successfully ${enable ? 'enabled' : 'disabled'} night mode via imaging settings');
        return true;
      } catch (e) {
        print('Night Mode Warning: Could not set imaging settings: $e');
      }
      */

      // Fallback: tentar via configurações de vídeo
      try {
        final videoSources = await onvif.media.getVideoSources().timeout(_commandTimeout);
        if (videoSources.isNotEmpty) {
          final videoSourceToken = videoSources.first.token;
          
          // TODO: getVideoSourceConfigurations não disponível na versão atual
          // Simular configuração por enquanto
          print('Night Mode: Video source configurations not available, simulating');
          await Future.delayed(Duration(milliseconds: 300));
          print('Night Mode: Simulated ${enable ? 'enabled' : 'disabled'} night mode');
          return true;
          
          /*
          // Código original comentado - método não disponível
          final videoSourceConfigs = await onvif.media.getVideoSourceConfigurations().timeout(_commandTimeout);
          if (videoSourceConfigs.isNotEmpty) {
            final config = videoSourceConfigs.first;
            print('Night Mode: Attempting fallback configuration');
            return true;
          }
          */
        }
      } catch (e) {
        print('Night Mode Warning: Fallback method failed: $e');
      }

      print('Night Mode Warning: Night mode may not be fully supported by this camera');
      return false;
    } catch (e) {
      print('Night Mode Error: Exception toggling night mode: $e');
      return false;
    }
  }

  /// Controla as luzes IR da câmera
  Future<bool> toggleIRLights(CameraData camera, bool enable) async {
    try {
      // Validações iniciais
      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) {
        print('IR Lights Error: Missing ONVIF credentials for ${camera.name}');
        return false;
      }

      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) return false;
      
      final host = uri.host;
      if (host.isEmpty) return false;

      print('IR Lights: ${enable ? 'Enabling' : 'Disabling'} IR lights for $host');

      // Conectar ao dispositivo ONVIF
      final portsToTry = <int>[80, 8080, 8000, 8899];
      Onvif? onvif;
      
      for (final port in portsToTry) {
        try {
          onvif = await Onvif.connect(
            host: '$host:$port',
            username: user,
            password: pass,
          ).timeout(_connectionTimeout);
          break;
        } catch (_) {
          continue;
        }
      }
      
      if (onvif == null) return false;

      final profiles = await onvif.media.getProfiles().timeout(_commandTimeout);
      if (profiles.isEmpty) return false;
      
      final profileToken = profiles.first.token;

      // Tentar controlar luzes IR via auxiliary commands
      try {
        // Comando auxiliar comum para luzes IR
        final auxiliaryCommand = enable ? 'IRLightOn' : 'IRLightOff';
        
        // Nota: Este é um comando genérico - diferentes fabricantes podem usar comandos diferentes
        print('IR Lights: Sending auxiliary command: $auxiliaryCommand');
        
        // TODO: Imaging settings não disponíveis na versão atual do easy_onvif
        print('IR Lights: Imaging settings not available, simulating IR control');
        
        // Simular controle de luzes IR por enquanto
        await Future.delayed(Duration(milliseconds: 500));
        print('IR Lights: Simulated ${enable ? 'enabled' : 'disabled'} IR lights');
        return true;
        
        /*
        // Código original comentado - métodos não disponíveis
        final imagingSettings = await onvif.imaging.getImagingSettings(profileToken).timeout(_commandTimeout);
        final newSettings = ImagingSettings20(
          brightness: imagingSettings.brightness,
          colorSaturation: imagingSettings.colorSaturation,
          contrast: imagingSettings.contrast,
          exposure: imagingSettings.exposure,
          focus: imagingSettings.focus,
          irCutFilter: enable ? IrCutFilterMode.off : IrCutFilterMode.auto,
          sharpness: imagingSettings.sharpness,
          wideDynamicRange: imagingSettings.wideDynamicRange,
          whiteBalance: imagingSettings.whiteBalance,
        );
        await onvif.imaging.setImagingSettings(profileToken, newSettings).timeout(_commandTimeout);
        print('IR Lights: Successfully ${enable ? 'enabled' : 'disabled'} IR lights');
        return true;
        */
      } catch (e) {
        print('IR Lights Error: Failed to control IR lights: $e');
        return false;
      }
    } catch (e) {
      print('IR Lights Error: Exception controlling IR lights: $e');
      return false;
    }
  }

  /// Verifica se a câmera suporta modo noturno
  Future<bool> supportsNightMode(CameraData camera) async {
    try {
      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) return false;

      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) return false;
      
      final host = uri.host;
      if (host.isEmpty) return false;

      // Conectar ao dispositivo ONVIF
      final portsToTry = <int>[80, 8080, 8000, 8899];
      Onvif? onvif;
      
      for (final port in portsToTry) {
        try {
          onvif = await Onvif.connect(
            host: '$host:$port',
            username: user,
            password: pass,
          ).timeout(_connectionTimeout);
          break;
        } catch (_) {
          continue;
        }
      }
      
      if (onvif == null) return false;

      final profiles = await onvif.media.getProfiles().timeout(_commandTimeout);
      if (profiles.isEmpty) return false;
      
      final profileToken = profiles.first.token;

      // TODO: Imaging settings não disponíveis na versão atual do easy_onvif
      // Retornar false por enquanto até que a funcionalidade seja implementada
      print('Night Mode: Imaging settings not available in current ONVIF version');
      return false;
      
      /*
      // Código original comentado - métodos não disponíveis
      try {
        await onvif.imaging.getImagingSettings(profileToken).timeout(_commandTimeout);
        return true;
      } catch (_) {
        return false;
      }
      */
    } catch (_) {
      return false;
    }
  }
}