import 'package:easy_onvif/onvif.dart';
import 'package:easy_onvif/shared.dart';
import '../models/camera_models.dart';

class OnvifPtzService {
  const OnvifPtzService();
  
  static const Duration _connectionTimeout = Duration(seconds: 5);
  static const Duration _commandTimeout = Duration(seconds: 2);
  static final Map<String, Onvif> _onvifCache = {};
  static final Map<String, String> _profileTokenCache = {};
  static final Map<String, String> _endpointCache = {};
  static final Map<String, bool> _busy = {};
  static const List<int> _defaultPorts = [80, 8080, 8000, 8899];

  Future<void> connect(CameraData camera) async {
    final user = camera.username?.trim() ?? '';
    final pass = camera.password?.trim() ?? '';
    if (user.isEmpty || pass.isEmpty) {
      print('PTZ Info: Missing ONVIF credentials for pre-connection: ${camera.name}');
      return;
    }
    final uri = Uri.tryParse(camera.streamUrl);
    if (uri == null) {
      print('PTZ Info: Invalid stream URL for pre-connection: ${camera.streamUrl}');
      return;
    }
    final host = uri.host;
    if (host.isEmpty) {
      print('PTZ Info: Cannot extract host from URL for pre-connection: ${camera.streamUrl}');
      return;
    }
    await _getOrConnectOnvif(host, user, pass);
  }

  Future<bool> executePtzCommand(CameraData camera, String command) async {
    try {
      // Validações iniciais
      if (camera.streamUrl.isEmpty) {
        print('PTZ Error: Stream URL is empty');
        return false;
      }
      if (command.isEmpty) {
        print('PTZ Error: Command is empty');
        return false;
      }

      // Exige credenciais ONVIF válidas
      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) {
        print('PTZ Error: Missing ONVIF credentials for ${camera.name}');
        return false;
      }

      // Extrai host da URL de stream para conectar ONVIF
      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) {
        print('PTZ Error: Invalid stream URL format: ${camera.streamUrl}');
        return false;
      }

      final host = uri.host;
      if (host.isEmpty) {
        print('PTZ Error: Cannot extract host from URL: ${camera.streamUrl}');
        return false;
      }

      final key = '$host|$user';

      // Obter/estabelecer sessão ONVIF cacheada
      final onvif = await _getOrConnectOnvif(host, user, pass);
      if (onvif == null) {
        print('PTZ Error: Could not connect to ONVIF on $host');
        return false;
      }

      // Obter token de perfil com PTZ (cacheado)
      final profileToken = await _getOrFetchProfileToken(onvif, key);
      if (profileToken == null || profileToken.isEmpty) {
        print('PTZ Error: No valid media profile token for $host');
        return false;
      }

      // Evita enfileirar múltiplos comandos; para movimento anterior se necessário
      if (_busy[key] == true) {
        try { await onvif.ptz.stop(profileToken).timeout(_commandTimeout); } catch (_) {}
      }
      _busy[key] = true;
      try {
        await _executePtzMovement(onvif, profileToken, command.toLowerCase()).timeout(_commandTimeout);
      } catch (e) {
        if (e.toString().contains('TimeoutException')) {
          print('PTZ Error: Timeout executing command $command on $host');
        } else {
          print('PTZ Error: Failed to execute command $command on $host: $e');
        }
        return false;
      } finally {
        _busy[key] = false;
      }

      // Para o movimento rapidamente para resposta mais ágil
      Future.delayed(const Duration(milliseconds: 150), () async {
        try {
          await onvif.ptz.stop(profileToken).timeout(_commandTimeout);
        } catch (_) {}
      });

      return true;
    } on Exception catch (e) {
      print('PTZ Error: Exception executing command $command: ${e.toString()}');
      return false;
    } catch (e) {
      print('PTZ Error: Unexpected error executing command $command: $e');
      return false;
    }
  }

  Future<Onvif?> _getOrConnectOnvif(String host, String user, String pass) async {
    final key = '$host|$user';
    if (_onvifCache.containsKey(key)) return _onvifCache[key];

    // Tenta endpoint cacheado primeiro
    final cachedEndpoint = _endpointCache[key];
    if (cachedEndpoint != null) {
      try {
        final onvif = await Onvif.connect(host: cachedEndpoint, username: user, password: pass)
            .timeout(_connectionTimeout);
        _onvifCache[key] = onvif;
        return onvif;
      } catch (_) {
        // se falhar, limpa cache do endpoint e tenta portas padrão
        _endpointCache.remove(key);
      }
    }

    for (final p in _defaultPorts) {
      final endpoint = '$host:$p';
      try {
        final onvif = await Onvif.connect(host: endpoint, username: user, password: pass)
            .timeout(_connectionTimeout);
        _onvifCache[key] = onvif;
        _endpointCache[key] = endpoint;
        return onvif;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<String?> _getOrFetchProfileToken(Onvif onvif, String key) async {
    final cached = _profileTokenCache[key];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final profiles = await onvif.media.getProfiles().timeout(_commandTimeout);
      if (profiles.isEmpty) return null;

      // tenta escolher um perfil com PTZ
      String chosen = profiles.first.token;
      for (final prof in profiles) {
        try {
          await onvif.ptz.getConfiguration(prof.token).timeout(_commandTimeout);
          chosen = prof.token;
          break;
        } catch (_) {
          continue;
        }
      }
      _profileTokenCache[key] = chosen;
      return chosen;
    } catch (_) {
      return null;
    }
  }

  Future<void> _executePtzMovement(Onvif onvif, String profileToken, String command) async {
    switch (command) {
      case 'up':
        await onvif.ptz.continuousMove(
          profileToken,
          velocity: PtzSpeed(
            panTilt: Vector2D(x: 0.0, y: 0.5),
          ),
        );
        break;
      case 'down':
        await onvif.ptz.continuousMove(
          profileToken,
          velocity: PtzSpeed(
            panTilt: Vector2D(x: 0.0, y: -0.5),
          ),
        );
        break;
      case 'left':
        await onvif.ptz.continuousMove(
          profileToken,
          velocity: PtzSpeed(
            panTilt: Vector2D(x: 0.5, y: 0.0),
          ),
        );
        break;
      case 'right':
        await onvif.ptz.continuousMove(
          profileToken,
          velocity: PtzSpeed(
            panTilt: Vector2D(x: -0.5, y: 0.0),
          ),
        );
        break;
      case 'zoomin':
      case 'zoom_in':
        // Zoom real será implementado quando a API suportar Vector1D; por ora mantemos comportamento atual.
        await Future.delayed(Duration(milliseconds: 120));
        break;
      case 'zoomout':
      case 'zoom_out':
        await Future.delayed(Duration(milliseconds: 120));
        break;
      default:
        throw Exception('Unknown PTZ command: $command');
    }
  }
}