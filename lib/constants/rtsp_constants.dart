/// Constantes relacionadas a URLs RTSP e protocolos de câmeras IP
class RtspConstants {
  // Lista de caminhos RTSP comuns para diferentes fabricantes (priorizando substreams)
  static const List<String> commonRtspPaths = [
    // Dahua/Hikvision - Substreams (menor latência) primeiro
    '/cam/realmonitor?channel=1&subtype=1', // substream
    '/cam/realmonitor?channel=1&subtype=0', // mainstream
    // Axis - Perfis de menor qualidade primeiro
    '/axis-media/media.amp',
    '/axis-media/media.amp?streamprofile=Mobile',
    '/axis-media/media.amp?streamprofile=Quality',
    // Foscam - Fluxos menores primeiro
    '/videoSub', // substream se disponível
    '/videoMain',
    '/video.cgi',
    // Generic ONVIF - Múltiplos perfis
    '/onvif/media_service/stream_1',
    '/onvif1',
    // TP-Link - Fluxos secundários primeiro
    '/stream2', // substream se disponível
    '/stream1',
    '/stream/1',
    // D-Link - Resoluções menores primeiro
    '/video.cgi?resolution=CIF',
    '/video.cgi?resolution=VGA',
    '/video1.mjpeg',
    // Vivotek
    '/live.sdp',
    // Amcrest
    '/cam/realmonitor?channel=1&subtype=1',
    // Reolink
    '/h264Preview_01_main',
    '/h264Preview_01_sub',
    // Genéricos
    '/',
    '/live',
    '/stream',
    '/media',
    '/video',
    '/mjpeg',
    '/h264',
    '/rtsp',
  ];

  // Portas ONVIF comuns
  static const List<int> onvifPorts = [80, 8080, 8000, 8899];

  // Porta RTSP padrão
  static const int defaultRtspPort = 554;

  // Ranges de IP comuns para descoberta manual
  static const List<String> commonIpRanges = [
    '192.168.1.',
    '192.168.0.',
    '10.0.0.',
    '172.16.0.',
  ];

  /// Codifica credenciais para URL RTSP
  static String encodeCredentials(String username, String password) {
    if (username.isEmpty && password.isEmpty) {
      return '';
    }
    return '$username:$password@';
  }

  /// Constrói URL RTSP completa
  static String buildRtspUrl({
    required String host,
    required int port,
    required String path,
    String username = '',
    String password = '',
  }) {
    final credentials = encodeCredentials(username, password);
    return 'rtsp://$credentials$host:$port$path';
  }
}