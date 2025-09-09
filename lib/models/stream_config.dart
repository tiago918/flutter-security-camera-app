/// Enums para configuração de stream
enum VideoCodec {
  h264,
  h265,
  mjpeg,
  mpeg4;

  String get displayName {
    switch (this) {
      case VideoCodec.h264:
        return 'H.264';
      case VideoCodec.h265:
        return 'H.265';
      case VideoCodec.mjpeg:
        return 'MJPEG';
      case VideoCodec.mpeg4:
        return 'MPEG-4';
    }
  }

  String get mimeType {
    switch (this) {
      case VideoCodec.h264:
        return 'video/avc';
      case VideoCodec.h265:
        return 'video/hevc';
      case VideoCodec.mjpeg:
        return 'video/mjpeg';
      case VideoCodec.mpeg4:
        return 'video/mp4v-es';
    }
  }
}

enum AudioCodec {
  aac,
  mp3,
  pcm,
  g711a,
  g711u;

  String get displayName {
    switch (this) {
      case AudioCodec.aac:
        return 'AAC';
      case AudioCodec.mp3:
        return 'MP3';
      case AudioCodec.pcm:
        return 'PCM';
      case AudioCodec.g711a:
        return 'G.711 A-law';
      case AudioCodec.g711u:
        return 'G.711 μ-law';
    }
  }

  String get mimeType {
    switch (this) {
      case AudioCodec.aac:
        return 'audio/aac';
      case AudioCodec.mp3:
        return 'audio/mpeg';
      case AudioCodec.pcm:
        return 'audio/pcm';
      case AudioCodec.g711a:
        return 'audio/g711-alaw';
      case AudioCodec.g711u:
        return 'audio/g711-ulaw';
    }
  }
}

enum StreamQuality {
  low,
  medium,
  high,
  ultra;

  String get displayName {
    switch (this) {
      case StreamQuality.low:
        return 'Baixa';
      case StreamQuality.medium:
        return 'Média';
      case StreamQuality.high:
        return 'Alta';
      case StreamQuality.ultra:
        return 'Ultra';
    }
  }

  String get resolution {
    switch (this) {
      case StreamQuality.low:
        return '640x480';
      case StreamQuality.medium:
        return '1280x720';
      case StreamQuality.high:
        return '1920x1080';
      case StreamQuality.ultra:
        return '3840x2160';
    }
  }

  int get bitrate {
    switch (this) {
      case StreamQuality.low:
        return 500000; // 500 kbps
      case StreamQuality.medium:
        return 2000000; // 2 Mbps
      case StreamQuality.high:
        return 5000000; // 5 Mbps
      case StreamQuality.ultra:
        return 15000000; // 15 Mbps
    }
  }

  int get frameRate {
    switch (this) {
      case StreamQuality.low:
        return 15;
      case StreamQuality.medium:
        return 25;
      case StreamQuality.high:
        return 30;
      case StreamQuality.ultra:
        return 60;
    }
  }
}

/// Configuração de stream de vídeo
class StreamConfig {
  final VideoCodec videoCodec;
  final AudioCodec? audioCodec;
  final String resolution;
  final int bitrate;
  final int frameRate;
  final bool audioEnabled;
  final StreamQuality quality;
  final int bufferSize;
  final int controlPort;
  final Map<String, dynamic> customSettings;

  const StreamConfig({
    required this.videoCodec,
    this.audioCodec,
    required this.resolution,
    required this.bitrate,
    required this.frameRate,
    this.audioEnabled = false,
    this.quality = StreamQuality.medium,
    this.bufferSize = 1024,
    this.controlPort = 554,
    this.customSettings = const {},
  });

  /// Construtor para qualidade predefinida
  factory StreamConfig.fromQuality(
    StreamQuality quality, {
    VideoCodec videoCodec = VideoCodec.h264,
    AudioCodec? audioCodec,
    bool audioEnabled = false,
    Map<String, dynamic> customSettings = const {},
  }) {
    return StreamConfig(
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      resolution: quality.resolution,
      bitrate: quality.bitrate,
      frameRate: quality.frameRate,
      audioEnabled: audioEnabled,
      quality: quality,
      customSettings: customSettings,
    );
  }

  /// Construtor personalizado
  factory StreamConfig.custom({
    required VideoCodec videoCodec,
    AudioCodec? audioCodec,
    required String resolution,
    required int bitrate,
    required int frameRate,
    bool audioEnabled = false,
    Map<String, dynamic> customSettings = const {},
  }) {
    return StreamConfig(
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      resolution: resolution,
      bitrate: bitrate,
      frameRate: frameRate,
      audioEnabled: audioEnabled,
      quality: StreamQuality.medium, // Default
      customSettings: customSettings,
    );
  }

  factory StreamConfig.fromJson(Map<String, dynamic> json) {
    return StreamConfig(
      videoCodec: VideoCodec.values.firstWhere(
        (e) => e.name == json['videoCodec'],
        orElse: () => VideoCodec.h264,
      ),
      audioCodec: json['audioCodec'] != null
          ? AudioCodec.values.firstWhere(
              (e) => e.name == json['audioCodec'],
              orElse: () => AudioCodec.aac,
            )
          : null,
      resolution: json['resolution'] as String,
      bitrate: json['bitrate'] as int,
      frameRate: json['frameRate'] as int,
      audioEnabled: json['audioEnabled'] as bool? ?? false,
      quality: StreamQuality.values.firstWhere(
        (e) => e.name == json['quality'],
        orElse: () => StreamQuality.medium,
      ),
      bufferSize: json['bufferSize'] as int? ?? 1024,
      controlPort: json['controlPort'] as int? ?? 554,
      customSettings: Map<String, dynamic>.from(json['customSettings'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'videoCodec': videoCodec.name,
      'audioCodec': audioCodec?.name,
      'resolution': resolution,
      'bitrate': bitrate,
      'frameRate': frameRate,
      'audioEnabled': audioEnabled,
      'quality': quality.name,
      'bufferSize': bufferSize,
      'controlPort': controlPort,
      'customSettings': customSettings,
    };
  }

  StreamConfig copyWith({
    VideoCodec? videoCodec,
    AudioCodec? audioCodec,
    String? resolution,
    int? bitrate,
    int? frameRate,
    bool? audioEnabled,
    StreamQuality? quality,
    int? bufferSize,
    int? controlPort,
    Map<String, dynamic>? customSettings,
  }) {
    return StreamConfig(
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      resolution: resolution ?? this.resolution,
      bitrate: bitrate ?? this.bitrate,
      frameRate: frameRate ?? this.frameRate,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      quality: quality ?? this.quality,
      bufferSize: bufferSize ?? this.bufferSize,
      controlPort: controlPort ?? this.controlPort,
      customSettings: customSettings ?? this.customSettings,
    );
  }

  /// Verifica se a configuração é válida
  bool get isValid {
    return bitrate > 0 &&
           frameRate > 0 &&
           resolution.isNotEmpty &&
           resolution.contains('x');
  }

  /// Obtém largura da resolução
  int get width {
    final parts = resolution.split('x');
    return parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
  }

  /// Obtém altura da resolução
  int get height {
    final parts = resolution.split('x');
    return parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  }

  /// Calcula taxa de bits por pixel
  double get bitsPerPixel {
    final totalPixels = width * height;
    return totalPixels > 0 ? bitrate / totalPixels.toDouble() : 0.0;
  }

  /// Verifica se suporta áudio
  bool get supportsAudio => audioCodec != null && audioEnabled;

  @override
  String toString() {
    return 'StreamConfig(videoCodec: $videoCodec, audioCodec: $audioCodec, '
           'resolution: $resolution, bitrate: $bitrate, frameRate: $frameRate, '
           'audioEnabled: $audioEnabled, quality: $quality)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StreamConfig &&
           other.videoCodec == videoCodec &&
           other.audioCodec == audioCodec &&
           other.resolution == resolution &&
           other.bitrate == bitrate &&
           other.frameRate == frameRate &&
           other.audioEnabled == audioEnabled &&
           other.quality == quality;
  }

  @override
  int get hashCode {
    return Object.hash(
      videoCodec,
      audioCodec,
      resolution,
      bitrate,
      frameRate,
      audioEnabled,
      quality,
    );
  }
}

/// Configurações de stream predefinidas
class StreamPresets {
  static const StreamConfig lowQuality = StreamConfig(
    videoCodec: VideoCodec.h264,
    resolution: '640x480',
    bitrate: 500000,
    frameRate: 15,
    quality: StreamQuality.low,
  );

  static const StreamConfig mediumQuality = StreamConfig(
    videoCodec: VideoCodec.h264,
    resolution: '1280x720',
    bitrate: 2000000,
    frameRate: 25,
    quality: StreamQuality.medium,
  );

  static const StreamConfig highQuality = StreamConfig(
    videoCodec: VideoCodec.h264,
    resolution: '1920x1080',
    bitrate: 5000000,
    frameRate: 30,
    quality: StreamQuality.high,
  );

  static const StreamConfig ultraQuality = StreamConfig(
    videoCodec: VideoCodec.h265,
    resolution: '3840x2160',
    bitrate: 15000000,
    frameRate: 60,
    quality: StreamQuality.ultra,
  );

  static const StreamConfig audioEnabled = StreamConfig(
    videoCodec: VideoCodec.h264,
    audioCodec: AudioCodec.aac,
    resolution: '1280x720',
    bitrate: 2000000,
    frameRate: 25,
    audioEnabled: true,
    quality: StreamQuality.medium,
  );

  /// Lista de todas as configurações predefinidas
  static List<StreamConfig> get all => [
        lowQuality,
        mediumQuality,
        highQuality,
        ultraQuality,
        audioEnabled,
      ];

  /// Obtém configuração por qualidade
  static StreamConfig getByQuality(StreamQuality quality) {
    switch (quality) {
      case StreamQuality.low:
        return lowQuality;
      case StreamQuality.medium:
        return mediumQuality;
      case StreamQuality.high:
        return highQuality;
      case StreamQuality.ultra:
        return ultraQuality;
    }
  }
}