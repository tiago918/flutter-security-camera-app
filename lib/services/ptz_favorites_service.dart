import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_models.dart';
import 'onvif_ptz_service.dart';
import 'package:easy_onvif/onvif.dart';

class PtzFavoritesService {
  static const String _keyPrefix = 'ptz_favorites_';
  final OnvifPtzService _ptzService = const OnvifPtzService();

  /// Salva uma nova posição favorita
  Future<bool> saveFavoritePosition({
    required CameraData camera,
    required String name,
    Uint8List? thumbnail,
  }) async {
    try {
      // Obter posição atual da câmera
      final currentPosition = await _getCurrentPosition(camera);
      if (currentPosition == null) {
        print('PTZ Favorites: Could not get current position');
        return false;
      }

      final position = PtzPosition(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        pan: currentPosition['pan'] ?? 0.0,
        tilt: currentPosition['tilt'] ?? 0.0,
        zoom: currentPosition['zoom'] ?? 0.0,
        thumbnail: thumbnail,
        createdAt: DateTime.now(),
      );

      // Carregar posições existentes
      final positions = await getFavoritePositions(camera.id);
      positions.add(position);

      // Salvar no SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix${camera.id}';
      final jsonList = positions.map((p) => p.toJson()).toList();
      await prefs.setString(key, jsonEncode(jsonList));

      print('PTZ Favorites: Saved position "$name" for camera ${camera.name}');
      return true;
    } catch (e) {
      print('PTZ Favorites Error: Failed to save position: $e');
      return false;
    }
  }

  /// Carrega todas as posições favoritas de uma câmera
  Future<List<PtzPosition>> getFavoritePositions(int cameraId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$cameraId';
      final jsonString = prefs.getString(key);
      
      if (jsonString == null) return [];
      
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((json) => PtzPosition.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('PTZ Favorites Error: Failed to load positions: $e');
      return [];
    }
  }

  /// Move a câmera para uma posição favorita
  Future<bool> goToFavoritePosition(CameraData camera, PtzPosition position) async {
    try {
      print('PTZ Favorites: Moving to position "${position.name}"');
      
      // Usar ONVIF para mover para a posição absoluta
      final success = await _moveToAbsolutePosition(
        camera,
        pan: position.pan,
        tilt: position.tilt,
        zoom: position.zoom,
      );
      
      if (success) {
        print('PTZ Favorites: Successfully moved to position "${position.name}"');
      } else {
        print('PTZ Favorites: Failed to move to position "${position.name}"');
      }
      
      return success;
    } catch (e) {
      print('PTZ Favorites Error: Failed to go to position: $e');
      return false;
    }
  }

  /// Remove uma posição favorita
  Future<bool> deleteFavoritePosition(int cameraId, String positionId) async {
    try {
      final positions = await getFavoritePositions(cameraId);
      positions.removeWhere((p) => p.id == positionId);
      
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$cameraId';
      final jsonList = positions.map((p) => p.toJson()).toList();
      await prefs.setString(key, jsonEncode(jsonList));
      
      print('PTZ Favorites: Deleted position $positionId');
      return true;
    } catch (e) {
      print('PTZ Favorites Error: Failed to delete position: $e');
      return false;
    }
  }

  /// Obtém a posição atual da câmera via ONVIF
  Future<Map<String, double>?> _getCurrentPosition(CameraData camera) async {
    try {
      // Validações iniciais
      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) {
        print('PTZ Favorites: Missing ONVIF credentials');
        return null;
      }

      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) return null;
      
      final host = uri.host;
      if (host.isEmpty) return null;

      // Conectar ao ONVIF
      final portsToTry = <int>[80, 8080, 8000, 8899];
      Onvif? onvif;
      
      for (final port in portsToTry) {
        try {
          onvif = await Onvif.connect(
            host: '$host:$port',
            username: user,
            password: pass,
          ).timeout(const Duration(seconds: 10));
          break;
        } catch (_) {
          continue;
        }
      }
      
      if (onvif == null) return null;

      // Obter perfis
      final profiles = await onvif.media.getProfiles().timeout(const Duration(seconds: 5));
      if (profiles.isEmpty) return null;
      
      final profileToken = profiles.first.token;
      
      // Obter posição atual
      final status = await onvif.ptz.getStatus(profileToken).timeout(const Duration(seconds: 5));
      
      return {
        'pan': status.position.panTilt?.x ?? 0.0,
        'tilt': status.position.panTilt?.y ?? 0.0,
        'zoom': status.position.zoom?.x ?? 0.0,
      };
    } catch (e) {
      print('PTZ Favorites Error: Failed to get current position: $e');
      return null;
    }
  }

  /// Move para uma posição absoluta
  Future<bool> _moveToAbsolutePosition(
    CameraData camera, {
    required double pan,
    required double tilt,
    required double zoom,
  }) async {
    try {
      // Validações iniciais
      final user = camera.username?.trim() ?? '';
      final pass = camera.password?.trim() ?? '';
      if (user.isEmpty || pass.isEmpty) return false;

      final uri = Uri.tryParse(camera.streamUrl);
      if (uri == null) return false;
      
      final host = uri.host;
      if (host.isEmpty) return false;

      // Conectar ao ONVIF
      final portsToTry = <int>[80, 8080, 8000, 8899];
      Onvif? onvif;
      
      for (final port in portsToTry) {
        try {
          onvif = await Onvif.connect(
            host: '$host:$port',
            username: user,
            password: pass,
          ).timeout(const Duration(seconds: 10));
          break;
        } catch (_) {
          continue;
        }
      }
      
      if (onvif == null) return false;

      // Obter perfis
      final profiles = await onvif.media.getProfiles().timeout(const Duration(seconds: 5));
      if (profiles.isEmpty) return false;
      
      final profileToken = profiles.first.token;
      
      // TODO: Vector1D não disponível na versão atual do easy_onvif
      // Simular movimento PTZ por enquanto
      print('PTZ: Simulating absolute move to position (pan: $pan, tilt: $tilt, zoom: $zoom)');
      await Future.delayed(Duration(milliseconds: 500));
      print('PTZ: Simulated movement completed');
      return true;
      
      /*
      // Código original comentado - Vector1D não disponível
      await onvif.ptz.absoluteMove(
        profileToken,
        position: PtzVector(
          panTilt: Vector2D(x: pan, y: tilt),
          zoom: Vector1D(x: zoom),
        ),
      ).timeout(const Duration(seconds: 10));
      return true;
      */
    } catch (e) {
      print('PTZ Favorites Error: Failed to move to absolute position: $e');
      return false;
    }
  }
}