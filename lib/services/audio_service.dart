import 'package:video_player/video_player.dart';

class AudioService {
  const AudioService();

  Future<bool> toggleMute(VideoPlayerController? controller) async {
    try {
      if (controller == null) return false;
      final currentVolume = controller.value.volume;
      final newVolume = currentVolume > 0 ? 0.0 : 1.0;
      await controller.setVolume(newVolume);
      return true;
    } catch (e) {
      return false;
    }
  }
}