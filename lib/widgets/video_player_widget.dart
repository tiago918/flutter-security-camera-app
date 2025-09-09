import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:fvp/fvp.dart' as fvp;
import '../models/camera_models.dart';
import '../services/logging_service.dart';
import '../services/onvif_playback_service.dart';

/// Enum para tipos de player disponíveis
enum VideoPlayerType { standard, fvp }

/// Widget para reprodução de vídeos gravados das câmeras com suporte a múltiplos players
class VideoPlayerWidget extends StatefulWidget {
  final CameraData camera;
  final RecordingInfo recording;
  final String? localVideoPath;
  final VideoPlayerType? preferredPlayer;
  final bool enableAutoReconnect;
  final Duration reconnectInterval;
  final int maxReconnectAttempts;

  const VideoPlayerWidget({
    super.key,
    required this.camera,
    required this.recording,
    this.localVideoPath,
    this.preferredPlayer,
    this.enableAutoReconnect = true,
    this.reconnectInterval = const Duration(seconds: 5),
    this.maxReconnectAttempts = 3,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  late final OnvifPlaybackService _playbackService;
  
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _isControlsVisible = true;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _isBuffering = false;
  bool _showControls = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  // Melhorias para múltiplos players e reconexão
  VideoPlayerType _currentPlayerType = VideoPlayerType.standard;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _controlsTimer;
  String? _currentVideoPath;
  DateTime? _lastStatusLog;
  
  // Logs detalhados
  final List<String> _debugLogs = [];
  
  // Configurações específicas para RTSP
  static const Duration _rtspTimeout = Duration(seconds: 45);
  static const Duration _initTimeout = Duration(seconds: 60);
  static const Duration _bufferDuration = Duration(seconds: 5);
  static const int _maxBufferSize = 10 * 1024 * 1024; // 10MB
  static const int _maxRetryAttempts = 5;
  static const Duration _retryDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _playbackService = OnvifPlaybackService(acceptSelfSigned: widget.camera.acceptSelfSigned);
    
    // Inicializar FVP
    fvp.registerWith();
    
    // Definir player preferido
    _currentPlayerType = widget.preferredPlayer ?? VideoPlayerType.standard;
    
    _addDebugLog('Iniciando VideoPlayerWidget com player: $_currentPlayerType');
    _initializePlayer();
  }

  @override
  void dispose() {
    _addDebugLog('Disposing VideoPlayerWidget');
    _controller?.dispose();
    _reconnectTimer?.cancel();
    _controlsTimer?.cancel();
    super.dispose();
  }

  /// Adiciona log de debug com timestamp
  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] $message';
    _debugLogs.add(logEntry);
    print('VideoPlayer Debug: $logEntry');
    
    // Manter apenas os últimos 50 logs
    if (_debugLogs.length > 50) {
      _debugLogs.removeAt(0);
    }
  }

  // Seleciona automaticamente o tipo de player com base na URL
  VideoPlayerType _decidePlayerType(String path) {
    final lower = path.toLowerCase();
    final isStream = lower.startsWith('rtsp://') ||
        lower.contains('.m3u8') || // HLS
        lower.contains('mjpeg') ||
        lower.contains('mjpg');
    return isStream ? VideoPlayerType.fvp : VideoPlayerType.standard;
  }

  /// Gera URLs alternativas para fallback de diferentes protocolos
  List<String> _generateFallbackUrls(String originalUrl) {
    final urls = <String>[originalUrl];
    final camera = widget.camera;
    
    // Se a URL original não funcionar, tentar outras variações
    if (originalUrl.startsWith('rtsp://')) {
      // Tentar HTTP como fallback
      urls.add('http://${camera.getHost()}:${camera.port}/video');
      urls.add('http://${camera.getHost()}:${camera.port}/mjpeg');
      urls.add('http://${camera.getHost()}:${camera.port}/stream');
      urls.add('http://${camera.getHost()}:${camera.port}/live');
      urls.add('http://${camera.getHost()}:${camera.port}/axis-cgi/mjpg/video.cgi');
    } else if (originalUrl.startsWith('http://')) {
      // Tentar RTSP como fallback
      urls.add('rtsp://${camera.getHost()}:554/stream1');
      urls.add('rtsp://${camera.getHost()}:554/live');
      urls.add('rtsp://${camera.getHost()}:554/video');
      urls.add('rtsp://${camera.getHost()}:554/cam/realmonitor?channel=1&subtype=0');
    }
    
    // Adicionar variações com diferentes portas comuns
    final commonPorts = [80, 8080, 554, 1935, 8554];
    for (final port in commonPorts) {
      if (port != camera.port) {
        urls.add('http://${camera.getHost()}:$port/video');
        urls.add('rtsp://${camera.getHost()}:$port/stream1');
      }
    }
    
    return urls.toSet().toList(); // Remove duplicatas
  }

  /// Valida se a URL do stream é válida
  bool _isValidStreamUrl(String url) {
    if (url.isEmpty) return false;
    
    // Verificar se é um arquivo local
    if (!url.startsWith('http') && !url.startsWith('rtsp') && !url.startsWith('/')) {
      return File(url).existsSync();
    }
    
    // Verificar URLs de rede
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'rtsp');
    } catch (e) {
      _addDebugLog('URL inválida: $url - $e');
      return false;
    }
  }

  /// Constrói headers HTTP otimizados para o player
  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'User-Agent': 'Flutter Video Player/1.0',
      'Connection': 'keep-alive',
      'Cache-Control': 'no-cache',
    };
    
    // Adicionar autenticação se disponível
    if (widget.camera.username?.isNotEmpty == true && widget.camera.password?.isNotEmpty == true) {
      final credentials = '${widget.camera.username}:${widget.camera.password}';
      final encoded = base64Encode(utf8.encode(credentials));
      headers['Authorization'] = 'Basic $encoded';
      _addDebugLog('Adicionando autenticação básica para ${widget.camera.username}');
    }
    
    return headers;
  }

  /// Inicializa o player com suporte a múltiplos engines e fallback automático
  Future<void> _initializePlayer({int retryCount = 0}) async {
    final playerId = '${widget.camera.name}_${DateTime.now().millisecondsSinceEpoch}';
    
    await LoggingService.instance.videoPlayer(
       'Iniciando inicialização do player (retry: $retryCount)',
       playerId: playerId,
     );
    
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = null;
        _isReconnecting = false;
      });

      _addDebugLog('Iniciando inicialização do player (tentativa ${_reconnectAttempts + 1}, retry: $retryCount)');
      
      String? videoPath = widget.localVideoPath;
      
      // Se não temos um arquivo local, tentar obter URL de playback ou baixar
      if (videoPath == null) {
        _addDebugLog('Obtendo URL de playback para gravação: ${widget.recording.id}');
        
        // Primeiro, tentar obter URL de playback RTSP com timeout aumentado
        try {
          final playbackUrl = await _playbackService.getPlaybackUrl(
            widget.camera,
            widget.recording,
          ).timeout(_rtspTimeout);
          
          if (playbackUrl != null && playbackUrl.isNotEmpty) {
            videoPath = playbackUrl;
            _addDebugLog('URL de playback obtida: $playbackUrl');
       }
        } catch (e) {
          _addDebugLog('Erro ao obter URL de playback: $e');
        }
        
        // Se não conseguiu URL de playback, tentar baixar o arquivo
        if (videoPath == null) {
          _addDebugLog('Tentando baixar gravação como fallback');
          try {
            final tempDir = Directory.systemTemp;
            final tempPath = '${tempDir.path}/temp_${widget.recording.id}_${DateTime.now().millisecondsSinceEpoch}.mp4';
            
            final success = await _playbackService.downloadRecording(
              widget.camera,
              widget.recording,
              tempPath,
            ).timeout(_rtspTimeout);
            
            if (success && await File(tempPath).exists()) {
              videoPath = tempPath;
              _addDebugLog('Gravação baixada com sucesso: $tempPath');
            } else {
              _addDebugLog('Falha ao baixar gravação');
            }
          } catch (e) {
            _addDebugLog('Erro ao baixar gravação: $e');
          }
        }
      }

      if (videoPath == null || videoPath.isEmpty) {
        throw Exception('Não foi possível obter o vídeo para reprodução. Verifique a conectividade com a câmera.');
      }

      // Validar URL antes de prosseguir
      if (!_isValidStreamUrl(videoPath)) {
        throw Exception('URL de vídeo inválida: $videoPath');
      }

      // Escolha mínima: Forçar FVP para streams (RTSP/HLS/MJPEG) e manter padrão para arquivo MP4/local
      if (widget.preferredPlayer == null) {
        final decided = _decidePlayerType(videoPath);
        if (_currentPlayerType != decided) {
          _currentPlayerType = decided;
          _addDebugLog('Player selecionado automaticamente: $_currentPlayerType para URL: ${videoPath.length > 80 ? videoPath.substring(0, 80) + '...' : videoPath}');
        }
      }

      _currentVideoPath = videoPath;
      _addDebugLog('Inicializando player $_currentPlayerType com: ${videoPath.length > 100 ? '${videoPath.substring(0, 100)}...' : videoPath}');
      
      // Tentar inicializar com o player atual
      await LoggingService.instance.videoPlayer(
           'Tentando player $_currentPlayerType',
           playerId: playerId,
         );
      
      await _initializeWithCurrentPlayer(videoPath);
      
      await LoggingService.instance.videoPlayer(
           'Player $_currentPlayerType inicializado com sucesso',
           playerId: playerId,
         );
      
    } catch (e) {
      _addDebugLog('Erro na inicialização: $e');
      
      await LoggingService.instance.videoPlayer(
           'Falha no player $_currentPlayerType: $e',
           playerId: playerId,
           isError: true,
         );
      
      // Implementar retry automático com timeout progressivo
      if (retryCount < _maxRetryAttempts) {
        final delay = Duration(seconds: _retryDelay.inSeconds * (retryCount + 1));
        _addDebugLog('Tentando novamente em ${delay.inSeconds}s (retry ${retryCount + 1}/$_maxRetryAttempts)');
        
        await Future.delayed(delay);
        if (mounted) {
          return _initializePlayer(retryCount: retryCount + 1);
        }
      }
      
      // Tentar fallback com URLs alternativas e diferentes players
      if (_currentVideoPath != null) {
        final fallbackUrls = _generateFallbackUrls(_currentVideoPath!);
        _addDebugLog('Tentando ${fallbackUrls.length} URLs de fallback');
        
        for (int i = 1; i < fallbackUrls.length; i++) {
          final fallbackUrl = fallbackUrls[i];
          _addDebugLog('Tentando URL de fallback ${i + 1}/${fallbackUrls.length}: $fallbackUrl');
          
          // Alternar entre players para cada URL
          final playerType = i % 2 == 0 ? VideoPlayerType.standard : VideoPlayerType.fvp;
          _currentPlayerType = playerType;
          
          await LoggingService.instance.videoPlayer(
               'Tentando fallback URL $i com player $playerType',
               playerId: playerId,
             );
          
          try {
            await _initializeWithCurrentPlayer(fallbackUrl);
            _currentVideoPath = fallbackUrl;
            
            await LoggingService.instance.videoPlayer(
                'Fallback URL $i com player $playerType bem-sucedido',
                playerId: playerId,
               );
            
            return;
          } catch (fallbackError) {
            _addDebugLog('Erro no fallback URL $i: $fallbackError');
            
            await LoggingService.instance.videoPlayer(
                'Erro no fallback URL $i: $fallbackError',
                playerId: playerId,
                isError: true,
               );
            
            // Tentar voltar para o player padrão com configurações diferentes
            _currentPlayerType = VideoPlayerType.standard;
          }
        }
        
        // Se chegou aqui, todos os fallbacks falharam
        _addDebugLog('Todos os fallbacks falharam, definindo estado de erro');
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = _getDetailedErrorMessage(e);
        });
        
        // Tentar reconexão automática se habilitada
        if (widget.enableAutoReconnect && _reconnectAttempts < widget.maxReconnectAttempts) {
          _scheduleReconnectWithFallback();
        } else if (_reconnectAttempts >= widget.maxReconnectAttempts) {
          _addDebugLog('Máximo de tentativas de reconexão atingido');
        }
      }
    }
  }

  /// Inicializa o player padrão
  Future<void> _initializeStandardPlayer(String videoPath) async {
    final playerId = '${widget.camera.name}_standard';
    
    _addDebugLog('Inicializando player padrão com: $videoPath');
    
    await LoggingService.instance.videoPlayer(
       'Configurando VideoPlayerController padrão',
       playerId: playerId,
     );
    
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(videoPath),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
        httpHeaders: {
          'User-Agent': 'Flutter Video Player',
          'Connection': 'keep-alive',
        },
      );
      
      await LoggingService.instance.videoPlayer(
         'Iniciando inicialização do controller (timeout: 60s)',
         playerId: playerId,
       );
      
      await _controller!.initialize().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('Timeout na inicialização do player padrão', const Duration(seconds: 60));
        },
      );
      
      _controller!.addListener(_videoListener);
      
      setState(() {
        _isLoading = false;
        _duration = _controller!.value.duration;
      });
      
      _addDebugLog('Player padrão inicializado com sucesso');
      
      await LoggingService.instance.videoPlayer(
         'Player padrão configurado com sucesso',
         playerId: playerId,
       );
      
    } catch (e) {
      _addDebugLog('Erro no player padrão: $e');
      
      await LoggingService.instance.videoPlayer(
         'Erro na configuração do player padrão: $e',
         playerId: playerId,
         isError: true,
       );
      
      rethrow;
    }
  }

  /// Inicializa o player com o tipo especificado
  Future<void> _initializeWithCurrentPlayer(String videoPath) async {
    _controller?.dispose();
    _controller = null;
    
    final playerId = '${widget.camera.name}_${_currentPlayerType.toString().split('.').last}';
    
    await LoggingService.instance.videoPlayback(
       'Inicializando player com URL',
       cameraId: widget.camera.name,
       url: videoPath,
     );
    
    try {
      // Configurar o controller baseado no tipo de player
      if (_currentPlayerType == VideoPlayerType.fvp) {
        _addDebugLog('Configurando FVP player');
        
        // Configurações específicas para FVP e RTSP
        if (videoPath.startsWith('rtsp')) {
          // Para RTSP, usar configurações otimizadas
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(videoPath),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: true,
              allowBackgroundPlayback: false,
            ),
            httpHeaders: _buildHeaders(),
          );
        } else if (videoPath.startsWith('http')) {
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(videoPath),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: true,
              allowBackgroundPlayback: false,
            ),
            httpHeaders: _buildHeaders(),
          );
        } else {
          // Verificar se o arquivo existe antes de tentar reproduzir
          final file = File(videoPath);
          if (!await file.exists()) {
            throw Exception('Arquivo de vídeo não encontrado: $videoPath');
          }
          _controller = VideoPlayerController.file(file);
        }
      } else {
        _addDebugLog('Configurando player padrão');
        
        // Player padrão
        if (videoPath.startsWith('http') || videoPath.startsWith('rtsp')) {
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(videoPath),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
              allowBackgroundPlayback: false,
            ),
            httpHeaders: _buildHeaders(),
          );
        } else {
          // Verificar se o arquivo existe antes de tentar reproduzir
          final file = File(videoPath);
          if (!await file.exists()) {
            throw Exception('Arquivo de vídeo não encontrado: $videoPath');
          }
          _controller = VideoPlayerController.file(file);
        }
      }

      if (_controller == null) {
        throw Exception('Falha ao criar controller do player');
      }

      _addDebugLog('Controller criado, iniciando inicialização...');
      
      // Inicializar com timeout aumentado
      await _controller!.initialize().timeout(_initTimeout);
      
      if (!_controller!.value.isInitialized) {
        throw Exception('Player não foi inicializado corretamente');
      }
      
      _controller!.addListener(_videoListener);
      
      setState(() {
        _isLoading = false;
        _duration = _controller!.value.duration;
        _reconnectAttempts = 0; // Reset contador de reconexão
      });
      
      _addDebugLog('Player inicializado com sucesso. Duração: $_duration, AspectRatio: ${_controller!.value.aspectRatio}');
      
      await LoggingService.instance.videoPlayer(
         'Player inicializado e pronto para reprodução',
         playerId: playerId,
       );
      
      // Auto-play com verificação
      if (_controller!.value.isInitialized) {
        await _controller!.play();
        setState(() {
          _isPlaying = true;
        });
        _addDebugLog('Reprodução iniciada automaticamente');
      }
      
    } catch (e) {
      _addDebugLog('Erro na inicialização do controller: $e');
      _controller?.dispose();
      _controller = null;
      rethrow;
    }
  }

  /// Agenda uma tentativa de reconexão
  void _scheduleReconnect() {
    if (!widget.enableAutoReconnect || _reconnectAttempts >= widget.maxReconnectAttempts) {
      _addDebugLog('Reconexão não será agendada. AutoReconnect: ${widget.enableAutoReconnect}, Tentativas: $_reconnectAttempts/${widget.maxReconnectAttempts}');
      return;
    }
    
    _reconnectAttempts++;
    _addDebugLog('Agendando reconexão (tentativa $_reconnectAttempts/${widget.maxReconnectAttempts}) em ${widget.reconnectInterval.inSeconds}s');
    
    setState(() {
      _isReconnecting = true;
    });
    
    _reconnectTimer?.cancel();
    
    // Usar delay progressivo: primeira tentativa imediata, depois aumentar o delay
    final delay = _reconnectAttempts == 1 
        ? _retryDelay 
        : Duration(seconds: widget.reconnectInterval.inSeconds * _reconnectAttempts);
    
    _reconnectTimer = Timer(delay, () {
      if (mounted) {
        _addDebugLog('Executando tentativa de reconexão $_reconnectAttempts após ${delay.inSeconds}s');
        _initializePlayer();
      }
    });
  }

  /// Agenda reconexão com fallback automático entre players
  void _scheduleReconnectWithFallback() {
    if (!widget.enableAutoReconnect || _reconnectAttempts >= widget.maxReconnectAttempts) {
      _addDebugLog('Reconexão com fallback não será agendada. AutoReconnect: ${widget.enableAutoReconnect}, Tentativas: $_reconnectAttempts/${widget.maxReconnectAttempts}');
      return;
    }
    
    _reconnectAttempts++;
    _addDebugLog('Agendando reconexão com fallback (tentativa $_reconnectAttempts/${widget.maxReconnectAttempts})');
    
    setState(() {
      _isReconnecting = true;
    });
    
    _reconnectTimer?.cancel();
    
    // Delay progressivo
    final delay = _reconnectAttempts == 1 
        ? _retryDelay 
        : Duration(seconds: widget.reconnectInterval.inSeconds * _reconnectAttempts);
    
    _reconnectTimer = Timer(delay, () {
      if (mounted) {
        _addDebugLog('Executando reconexão com fallback após ${delay.inSeconds}s');
        
        // A cada 2 tentativas, tentar trocar o tipo de player
        if (_reconnectAttempts % 2 == 0) {
          final currentType = _currentPlayerType;
          _currentPlayerType = currentType == VideoPlayerType.standard 
              ? VideoPlayerType.fvp 
              : VideoPlayerType.standard;
          _addDebugLog('Fazendo fallback de $currentType para $_currentPlayerType');
        }
        
        _initializePlayer();
      }
    });
  }

  Future<void> _videoListener() async {
    if (_controller != null && mounted) {
      final value = _controller!.value;
      final playerId = '${widget.camera.name}_${_currentPlayerType.toString().split('.').last}';
      
      // Detectar erros do player
      if (value.hasError) {
        final errorDesc = value.errorDescription ?? 'Erro desconhecido no player';
        _addDebugLog('Erro detectado no player: $errorDesc');
        
        await LoggingService.instance.videoPlayer(
           'Erro detectado no player: $errorDesc',
           playerId: playerId,
           isError: true,
         );
        
        setState(() {
          _hasError = true;
          _errorMessage = _getDetailedErrorMessage(errorDesc);
          _isLoading = false;
        });
        
        // Tentar reconexão automática com fallback de player
        if (widget.enableAutoReconnect && _reconnectAttempts < widget.maxReconnectAttempts) {
          _scheduleReconnectWithFallback();
        } else {
          _addDebugLog('Reconexão automática não será executada');
        }
        return;
      }
      
      // Verificar se o player parou inesperadamente (possível problema de rede)
      if (value.isInitialized && !value.isPlaying && !value.isBuffering && 
          _isPlaying && value.position == _position && 
          value.position < value.duration) {
        _addDebugLog('Player parou inesperadamente. Tentando retomar reprodução...');
        
        await LoggingService.instance.videoPlayer(
           'Player parou inesperadamente',
           playerId: playerId,
         );
        
        // Tentar retomar a reprodução
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && _controller != null && _controller!.value.isInitialized) {
            _controller!.play();
          }
        });
      }
      
      // Log de mudanças de estado de reprodução
      if (value.isPlaying != _isPlaying) {
        await LoggingService.instance.videoPlayer(
           value.isPlaying ? 'Reprodução iniciada' : 'Reprodução pausada',
           playerId: playerId,
         );
      }
      
      // Log de buffering
      if (value.isBuffering != _isBuffering) {
        await LoggingService.instance.videoPlayer(
           value.isBuffering ? 'Iniciando buffering' : 'Buffering concluído',
           playerId: playerId,
         );
      }
      
      // Se estava reconectando e agora está funcionando, limpar estado
      if (_isReconnecting && value.isInitialized && value.isPlaying) {
        _addDebugLog('Reconexão bem-sucedida!');
        await LoggingService.instance.videoPlayer(
           'Reconexão bem-sucedida',
           playerId: playerId,
         );
      }
      
      setState(() {
         _position = value.position;
         _isPlaying = value.isPlaying;
         _isBuffering = value.isBuffering;
         
         // Se estava reconectando e agora está funcionando, limpar estado
         if (_isReconnecting && value.isInitialized && value.isPlaying) {
           _isReconnecting = false;
           _reconnectAttempts = 0;
         }
       });
       
       // Log de status periodicamente (a cada 30 segundos)
       final now = DateTime.now();
       if (_lastStatusLog == null || now.difference(_lastStatusLog!).inSeconds >= 30) {
         _lastStatusLog = now;
         _addDebugLog('Status: Playing=${value.isPlaying}, Position=${value.position}, Duration=${value.duration}, Buffering=${value.isBuffering}, Size=${value.size}');
       }
       
       // Auto-hide controls after 3 seconds of inactivity
       if (_showControls && value.isPlaying) {
         _controlsTimer?.cancel();
         _controlsTimer = Timer(const Duration(seconds: 3), () {
           if (mounted) {
             setState(() {
               _showControls = false;
             });
           }
         });
       }
    }
  }

  /// Alterna entre play e pause
  void _togglePlayPause() {
    if (_controller != null && _controller!.value.isInitialized) {
      _addDebugLog('Alternando play/pause. Estado atual: $_isPlaying');
      
      if (_isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    }
  }

  /// Alterna o mute do áudio
  void _toggleMute() {
    if (_controller != null && _controller!.value.isInitialized) {
      setState(() {
        _isMuted = !_isMuted;
        _controller!.setVolume(_isMuted ? 0.0 : 1.0);
      });
      _addDebugLog('Mute alternado: $_isMuted');
    }
  }

  /// Navega para uma posição específica no vídeo
  void _seekTo(Duration position) {
    if (_controller != null && _controller!.value.isInitialized) {
      _addDebugLog('Navegando para posição: $position');
      _controller!.seekTo(position);
    }
  }

  /// Reinicia o player (retry)
  void _retry() {
    _addDebugLog('Tentativa manual de reinicialização');
    _reconnectAttempts = 0; // Reset contador
    _initializePlayer();
  }

  /// Alterna a visibilidade dos controles
    void _toggleControls() {
      setState(() {
        _showControls = !_showControls;
      });
      _addDebugLog('Controles ${_showControls ? 'mostrados' : 'ocultados'}');
    }

  /// Força o uso de um player específico
  void _switchPlayer(VideoPlayerType playerType) {
    if (_currentPlayerType != playerType) {
      _addDebugLog('Alternando para player: $playerType');
      _currentPlayerType = playerType;
      _retry();
    }
  }

  /// Obtém informações de debug do player
  Map<String, dynamic> _getPlayerInfo() {
    return {
      'currentPlayer': _currentPlayerType.toString(),
      'isInitialized': _controller?.value.isInitialized ?? false,
      'hasError': _hasError,
      'errorMessage': _errorMessage,
      'isReconnecting': _isReconnecting,
      'reconnectAttempts': _reconnectAttempts,
      'maxReconnectAttempts': widget.maxReconnectAttempts,
      'videoPath': _currentVideoPath,
      'position': _position.toString(),
      'duration': _duration.toString(),
      'isPlaying': _isPlaying,
      'isBuffering': _isBuffering,
      'isMuted': _isMuted,
      'debugLogsCount': _debugLogs.length,
      'aspectRatio': _controller?.value.aspectRatio,
      'size': _controller?.value.size.toString(),
    };
  }
  
  /// Gera uma mensagem de erro detalhada baseada no tipo de exceção
  String _getDetailedErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    // Erros de conexão e rede
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return 'Timeout na conexão (${widget.camera.getHost()}). Verifique se a câmera está online e acessível.';
    } else if (errorStr.contains('connection refused') || errorStr.contains('refused')) {
      return 'Conexão recusada pela câmera. Verifique se o serviço está ativo na porta ${widget.camera.port}.';
    } else if (errorStr.contains('network') || errorStr.contains('unreachable')) {
      return 'Erro de rede. Verifique sua conexão e se a câmera (${widget.camera.getHost()}) está acessível.';
    } else if (errorStr.contains('host') && errorStr.contains('not found')) {
      return 'Host não encontrado. Verifique o endereço IP da câmera: ${widget.camera.getHost()}';
    }
    
    // Erros de protocolo e stream
    else if (errorStr.contains('rtsp') || errorStr.contains('554')) {
      return 'Erro no stream RTSP. Verifique se a câmera suporta RTSP na porta ${widget.camera.port}.';
    } else if (errorStr.contains('http') && (errorStr.contains('404') || errorStr.contains('not found'))) {
      return 'Stream HTTP não encontrado. Verifique o caminho do stream da câmera.';
    } else if (errorStr.contains('http') && errorStr.contains('401')) {
      return 'Não autorizado. Verifique as credenciais da câmera.';
    } else if (errorStr.contains('http') && errorStr.contains('403')) {
      return 'Acesso negado pela câmera. Verifique as permissões do usuário.';
    }
    
    // Erros de arquivo e formato
    else if (errorStr.contains('file') && errorStr.contains('not found')) {
      return 'Arquivo de vídeo não encontrado. Verifique se o arquivo existe.';
    } else if (errorStr.contains('format') || errorStr.contains('codec')) {
      return 'Formato de vídeo não suportado. Tente usar um player diferente.';
    } else if (errorStr.contains('permission') || errorStr.contains('access denied')) {
      return 'Sem permissão para acessar o arquivo ou stream.';
    }
    
    // Erros de autenticação
    else if (errorStr.contains('authentication') || errorStr.contains('unauthorized')) {
      return 'Falha na autenticação. Verifique usuário e senha da câmera.';
    } else if (errorStr.contains('credentials') || errorStr.contains('login')) {
      return 'Credenciais inválidas. Verifique o usuário e senha configurados.';
    }
    
    // Erros específicos do player
    else if (errorStr.contains('player') && errorStr.contains('initialize')) {
      return 'Falha na inicialização do player. Tentando player alternativo...';
    } else if (errorStr.contains('buffer') || errorStr.contains('buffering')) {
      return 'Problema de buffering. Verifique a qualidade da conexão de rede.';
    }
    
    // Erro genérico com informações úteis
    else {
      return 'Erro: ${errorStr.length > 100 ? '${errorStr.substring(0, 100)}...' : errorStr}';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.recording.filename),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: _buildVideoPlayer(),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Carregando vídeo...',
            style: TextStyle(color: Colors.white),
          ),
        ],
      );
    }

    if (_hasError) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Erro ao carregar vídeo',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Erro desconhecido',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Informações de debug
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Player atual: ${_currentPlayerType.toString().split('.').last}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'Tentativas de reconexão: $_reconnectAttempts/${widget.maxReconnectAttempts}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (_currentVideoPath != null)
                  Text(
                    'URL: ${_currentVideoPath!.length > 50 ? '${_currentVideoPath!.substring(0, 50)}...' : _currentVideoPath!}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _retry,
                child: const Text('Tentar novamente'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () => _switchPlayer(
                  _currentPlayerType == VideoPlayerType.standard 
                    ? VideoPlayerType.fvp 
                    : VideoPlayerType.standard
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: Text(
                  'Usar ${_currentPlayerType == VideoPlayerType.standard ? 'FVP' : 'Padrão'}'
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video player
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
          
          // Controls overlay
          if (_showControls)
            _buildControlsOverlay(),
            
          // Indicador de reconexão
          if (_isReconnecting)
            _buildReconnectingIndicator(),
            
          // Indicador de buffering
          if (_isBuffering)
            _buildBufferingIndicator(),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
          color: Colors.black.withValues(alpha: 0.3),
      child: Column(
        children: [
          // Top info bar
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.camera.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Gravação: ${widget.recording.startTime.day.toString().padLeft(2, '0')}/${widget.recording.startTime.month.toString().padLeft(2, '0')}/${widget.recording.startTime.year} ${widget.recording.startTime.hour.toString().padLeft(2, '0')}:${widget.recording.startTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Center play/pause button
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _togglePlayPause,
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
          
          const Spacer(),
          
          // Bottom controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Progress bar
                Row(
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _duration.inMilliseconds > 0
                              ? _position.inMilliseconds / _duration.inMilliseconds
                              : 0.0,
                          onChanged: (value) {
                            final position = Duration(
                              milliseconds: (value * _duration.inMilliseconds).round(),
                            );
                            _seekTo(position);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _toggleMute,
                      icon: Icon(
                        _isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      onPressed: _togglePlayPause,
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      onPressed: () {
                        // Implementar fullscreen se necessário
                      },
                      icon: const Icon(
                        Icons.fullscreen,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Widget indicador de reconexão
  Widget _buildReconnectingIndicator() {
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Reconectando... ($_reconnectAttempts/${widget.maxReconnectAttempts})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget indicador de buffering
  Widget _buildBufferingIndicator() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3,
          ),
          SizedBox(height: 8),
          Text(
            'Carregando...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}