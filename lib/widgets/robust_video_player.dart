import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models/camera_device.dart';

/// Player de vídeo robusto com fallbacks para problemas gráficos
/// Resolve problemas de GraphicBufferAllocator e AdrenoUtils identificados nos logs
class RobustVideoPlayer extends StatefulWidget {
  final CameraDevice device;
  final String? streamUrl;
  final VoidCallback? onError;
  final VoidCallback? onConnected;
  
  const RobustVideoPlayer({
    Key? key,
    required this.device,
    this.streamUrl,
    this.onError,
    this.onConnected,
  }) : super(key: key);
  
  @override
  State<RobustVideoPlayer> createState() => _RobustVideoPlayerState();
}

class _RobustVideoPlayerState extends State<RobustVideoPlayer> {
  VideoPlayerController? _controller;
  String? _currentStreamUrl;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _retryCount = 0;
  Timer? _retryTimer;
  Timer? _healthCheckTimer;
  
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 5);
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  
  // URLs de fallback para diferentes protocolos
  final List<String> _fallbackUrls = [];
  int _currentUrlIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _generateFallbackUrls();
    _initializePlayer();
  }
  
  @override
  void dispose() {
    _retryTimer?.cancel();
    _healthCheckTimer?.cancel();
    _disposeController();
    super.dispose();
  }
  
  /// Gera URLs de fallback para diferentes protocolos e portas
  void _generateFallbackUrls() {
    final device = widget.device;
    
    // URL principal fornecida
    if (widget.streamUrl != null) {
      _fallbackUrls.add(widget.streamUrl!);
    }
    
    // URLs RTSP padrão
    if (device.protocol == 'RTSP' || device.port == 554) {
      _fallbackUrls.addAll([
        'rtsp://${device.ip}:${device.port}/stream1',
        'rtsp://${device.ip}:${device.port}/stream0',
        'rtsp://${device.ip}:${device.port}/live',
        'rtsp://${device.ip}:${device.port}/h264',
        'rtsp://${device.ip}:${device.port}/video',
        'rtsp://${device.ip}:${device.port}/',
      ]);
    }
    
    // URLs HTTP para streaming
    if (device.protocol == 'HTTP' || [80, 8080, 8000].contains(device.port)) {
      _fallbackUrls.addAll([
        'http://${device.ip}:${device.port}/video.mjpg',
        'http://${device.ip}:${device.port}/mjpg/video.mjpg',
        'http://${device.ip}:${device.port}/videostream.cgi',
        'http://${device.ip}:${device.port}/video.cgi',
      ]);
    }
    
    print('[RobustPlayer] URLs de fallback geradas: ${_fallbackUrls.length}');
  }
  
  /// Inicializa o player com fallbacks
  Future<void> _initializePlayer() async {
    if (_fallbackUrls.isEmpty) {
      _setError('Nenhuma URL de stream disponível');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    
    await _tryNextUrl();
  }
  
  /// Tenta a próxima URL da lista de fallback
  Future<void> _tryNextUrl() async {
    if (_currentUrlIndex >= _fallbackUrls.length) {
      _setError('Todas as URLs de fallback falharam');
      return;
    }
    
    final url = _fallbackUrls[_currentUrlIndex];
    print('[RobustPlayer] Tentando URL: $url');
    
    try {
      await _createController(url);
    } catch (e) {
      print('[RobustPlayer] Erro na URL $url: $e');
      _currentUrlIndex++;
      
      if (_currentUrlIndex < _fallbackUrls.length) {
        // Tentar próxima URL após delay
        await Future.delayed(const Duration(seconds: 2));
        await _tryNextUrl();
      } else {
        _setError('Falha em todas as URLs: $e');
      }
    }
  }
  
  /// Cria e configura o controller de vídeo
  Future<void> _createController(String url) async {
    await _disposeController();
    
    _currentStreamUrl = url;
    
    try {
      // Configurar controller com opções robustas
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
        httpHeaders: {
          'User-Agent': 'CameraApp/1.0',
          'Connection': 'keep-alive',
        },
      );
      
      // Configurar listeners antes da inicialização
      _controller!.addListener(_onPlayerStateChanged);
      
      // Inicializar com timeout
      await _controller!.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Timeout na inicialização do player', const Duration(seconds: 15));
        },
      );
      
      // Verificar se o vídeo tem dimensões válidas
      if (_controller!.value.size.width == 0 || _controller!.value.size.height == 0) {
        throw Exception('Vídeo sem dimensões válidas');
      }
      
      // Iniciar reprodução
      await _controller!.play();
      
      setState(() {
        _isLoading = false;
        _hasError = false;
        _retryCount = 0;
      });
      
      // Iniciar monitoramento de saúde
      _startHealthCheck();
      
      widget.onConnected?.call();
      print('[RobustPlayer] Player inicializado com sucesso: $url');
      
    } catch (e) {
      print('[RobustPlayer] Erro na criação do controller: $e');
      await _disposeController();
      rethrow;
    }
  }
  
  /// Monitora mudanças no estado do player
  void _onPlayerStateChanged() {
    if (_controller == null) return;
    
    final value = _controller!.value;
    
    // Detectar erros
    if (value.hasError) {
      print('[RobustPlayer] Erro detectado no player: ${value.errorDescription}');
      _handlePlayerError(value.errorDescription ?? 'Erro desconhecido');
    }
    
    // Detectar buffering excessivo
    if (value.isBuffering) {
      print('[RobustPlayer] Player em buffering...');
    }
  }
  
  /// Trata erros do player com retry automático
  void _handlePlayerError(String error) {
    print('[RobustPlayer] Tratando erro: $error');
    
    if (_retryCount < _maxRetries) {
      _retryCount++;
      print('[RobustPlayer] Tentativa de retry $_{_retryCount}/$_maxRetries');
      
      _retryTimer = Timer(_retryDelay, () {
        _tryNextUrl();
      });
    } else {
      _setError('Erro após $_maxRetries tentativas: $error');
    }
  }
  
  /// Inicia monitoramento de saúde da conexão
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) {
      _performHealthCheck();
    });
  }
  
  /// Verifica saúde da conexão
  void _performHealthCheck() {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('[RobustPlayer] Health check: Player não inicializado');
      _handlePlayerError('Player perdeu inicialização');
      return;
    }
    
    // Verificar se o vídeo está progredindo
    final position = _controller!.value.position;
    final duration = _controller!.value.duration;
    
    if (duration.inSeconds > 0 && position == duration) {
      print('[RobustPlayer] Health check: Stream pode ter terminado');
      // Para streams ao vivo, isso pode indicar problema
      if (_currentStreamUrl?.contains('rtsp://') == true) {
        _handlePlayerError('Stream RTSP interrompido');
      }
    }
  }
  
  /// Define estado de erro
  void _setError(String message) {
    setState(() {
      _isLoading = false;
      _hasError = true;
      _errorMessage = message;
    });
    
    widget.onError?.call();
    print('[RobustPlayer] Erro final: $message');
  }
  
  /// Descarta o controller atual
  Future<void> _disposeController() async {
    if (_controller != null) {
      _controller!.removeListener(_onPlayerStateChanged);
      await _controller!.dispose();
      _controller = null;
    }
  }
  
  /// Força retry manual
  void retry() {
    _retryCount = 0;
    _currentUrlIndex = 0;
    _initializePlayer();
  }
  
  /// Tenta próxima URL manualmente
  void tryNextUrl() {
    _currentUrlIndex++;
    _retryCount = 0;
    _tryNextUrl();
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _buildPlayerContent(),
      ),
    );
  }
  
  Widget _buildPlayerContent() {
    if (_isLoading) {
      return _buildLoadingWidget();
    }
    
    if (_hasError) {
      return _buildErrorWidget();
    }
    
    if (_controller != null && _controller!.value.isInitialized) {
      return _buildVideoWidget();
    }
    
    return _buildLoadingWidget();
  }
  
  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          const SizedBox(height: 16),
          Text(
            'Conectando ao stream...',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (_currentStreamUrl != null) ..[
            const SizedBox(height: 8),
            Text(
              'URL: ${_currentStreamUrl!.length > 50 ? '${_currentStreamUrl!.substring(0, 50)}...' : _currentStreamUrl!}',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Erro no Stream',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: retry,
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Tentar Novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              if (_currentUrlIndex < _fallbackUrls.length - 1)
                ElevatedButton.icon(
                  onPressed: tryNextUrl,
                  icon: Icon(Icons.skip_next, size: 16),
                  label: Text('Próxima URL'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildVideoWidget() {
    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
        // Overlay com informações de debug (apenas em desenvolvimento)
        if (const bool.fromEnvironment('dart.vm.product') == false)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'URL: ${_currentUrlIndex + 1}/${_fallbackUrls.length}',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }
}