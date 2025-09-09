import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:fvp/fvp.dart' as fvp;

import '../models/models.dart';
import '../services/logging_service.dart';

/// Enum para tipos de player disponíveis
enum LivePlayerType { standard, fvp }

/// Widget para reprodução de streams RTSP ao vivo das câmeras
class LiveStreamPlayer extends StatefulWidget {
  final CameraModel camera;
  final String streamUrl;
  final LivePlayerType? preferredPlayer;
  final bool enableAutoReconnect;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  final Function(String)? onPlayerStateChanged;
  final Function(String)? onError;

  const LiveStreamPlayer({
    super.key,
    required this.camera,
    required this.streamUrl,
    this.preferredPlayer,
    this.enableAutoReconnect = true,
    this.reconnectDelay = const Duration(seconds: 3),
    this.maxReconnectAttempts = 5,
    this.onPlayerStateChanged,
    this.onError,
  });

  @override
  State<LiveStreamPlayer> createState() => _LiveStreamPlayerState();
}

class _LiveStreamPlayerState extends State<LiveStreamPlayer> {
  VideoPlayerController? _controller;
  
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  
  LivePlayerType _currentPlayerType = LivePlayerType.fvp;
  String? _currentStreamUrl;
  
  // Logs detalhados
  final List<String> _debugLogs = [];
  
  // Configurações específicas para RTSP
  static const Duration _rtspTimeout = Duration(seconds: 30);
  static const Duration _initTimeout = Duration(seconds: 45);
  static const int _maxRetryAttempts = 3;

  @override
  void initState() {
    super.initState();
    // Configurar FVP com opções otimizadas para RTSP
    fvp.registerWith(options: {
      'platforms': ['windows', 'linux', 'macos', 'android', 'ios'],
      'lowLatency': 2, // Para live streams
      'player': {
        'rtsp_transport': 'tcp', // Forçar TCP para RTSP
        'buffer_time': '1000000', // 1 segundo de buffer (em microsegundos)
        'timeout': '30000000', // 30 segundos de timeout
        'reconnect': '1', // Habilitar reconexão automática
        'reconnect_delay_max': '5', // Delay máximo de reconexão
      },
      'global': {
        'demux.buffer.ranges': '1', // Cache para streams HTTP
      },
    });
    
    // Definir player preferido (FVP é melhor para RTSP)
    _currentPlayerType = widget.preferredPlayer ?? LivePlayerType.fvp;
    _currentStreamUrl = widget.streamUrl;
    
    _addDebugLog('Iniciando LiveStreamPlayer com player: $_currentPlayerType');
    _addDebugLog('Stream URL: $_currentStreamUrl');
    
    _initializePlayer();
  }

  @override
  void dispose() {
    _addDebugLog('Disposing LiveStreamPlayer');
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  /// Adiciona log de debug com timestamp
  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final cameraName = widget.camera?.name ?? 'Unknown';
    final streamUrl = widget.streamUrl ?? 'No URL';
    final logEntry = '[$timestamp] $message';
    _debugLogs.add(logEntry);
    print('LiveStreamPlayer($cameraName): $logEntry');
    print('LiveStreamPlayer($cameraName): Stream URL: $streamUrl');
    
    // Manter apenas os últimos 30 logs
    if (_debugLogs.length > 30) {
      _debugLogs.removeAt(0);
    }
  }

  void _addErrorLog(String error, [dynamic exception]) {
    final timestamp = DateTime.now().toIso8601String();
    final cameraName = widget.camera?.name ?? 'Unknown';
    final streamUrl = widget.streamUrl ?? 'No URL';
    print('[$timestamp] ERROR LiveStreamPlayer($cameraName): $error');
    print('[$timestamp] ERROR LiveStreamPlayer($cameraName): Stream URL: $streamUrl');
    if (exception != null) {
      print('[$timestamp] ERROR LiveStreamPlayer($cameraName): Exception: $exception');
    }
  }

  /// Inicializa o player com a URL do stream
  Future<void> _initializePlayer({int retryCount = 0}) async {
    final playerId = '${widget.camera.name}_live_${DateTime.now().millisecondsSinceEpoch}';
    
    await LoggingService.instance.videoPlayer(
      'Iniciando inicialização do live stream (retry: $retryCount)',
      playerId: playerId,
      state: 'initializing'
    );
    
    try {
      _addDebugLog('=== INICIANDO INICIALIZAÇÃO DO PLAYER ===');
      _addDebugLog('Player preferido: ${widget.preferredPlayer}');
      _addDebugLog('Tentativa: ${_reconnectAttempts + 1}/${widget.maxReconnectAttempts}');
      _addDebugLog('Retry count: $retryCount/$_maxRetryAttempts');
      
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = null;
        _isReconnecting = false;
      });
      
      if (_currentStreamUrl == null || _currentStreamUrl!.isEmpty) {
        throw Exception('URL do stream não definida ou vazia');
      }

      _addDebugLog('Validando URL do stream...');
      if (!_isValidStreamUrl(_currentStreamUrl!)) {
        throw Exception('URL de stream inválida: $_currentStreamUrl');
      }

      _addDebugLog('URL validada com sucesso: $_currentStreamUrl');
      _addDebugLog('Inicializando player $_currentPlayerType...');
      
      // Tentar inicializar com o player atual
      await LoggingService.instance.videoPlayer(
          'Tentando player $_currentPlayerType',
          playerId: playerId
        );
      
      await _initializeWithCurrentPlayer(_currentStreamUrl!);
      
      await LoggingService.instance.videoPlayer(
          'Player $_currentPlayerType inicializado com sucesso',
          playerId: playerId
        );
      
      _addDebugLog('=== INICIALIZAÇÃO CONCLUÍDA COM SUCESSO ===');
      
      // Notificar mudança de estado
      widget.onPlayerStateChanged?.call('initialized');
      
    } catch (e) {
      _addErrorLog('Falha na inicialização do player', e);
      
      await LoggingService.instance.videoPlayer(
          'Falha no player $_currentPlayerType: $e',
          playerId: playerId,
          isError: true
        );
      
      // Implementar retry automático
      if (retryCount < _maxRetryAttempts) {
        final delay = Duration(seconds: widget.reconnectDelay.inSeconds * (retryCount + 1));
        _addDebugLog('Tentando novamente em ${delay.inSeconds}s (retry ${retryCount + 1}/$_maxRetryAttempts)');
        
        await Future.delayed(delay);
        if (mounted) {
          return _initializePlayer(retryCount: retryCount + 1);
        }
      }
      
      // Tentar alternar player como fallback
      if (_currentPlayerType == LivePlayerType.fvp) {
        _addDebugLog('Tentando fallback para player standard');
        _currentPlayerType = LivePlayerType.standard;
        
        await LoggingService.instance.videoPlayer(
           'Tentando fallback para player padrão',
           playerId: playerId
         );
        
        try {
          await _initializeWithCurrentPlayer(_currentStreamUrl!);
          
          await LoggingService.instance.videoPlayer(
             'Fallback para player padrão bem-sucedido',
             playerId: playerId
           );
          
          widget.onPlayerStateChanged?.call('fallback_success');
          return;
        } catch (fallbackError) {
          _addErrorLog('Erro no fallback para player standard', fallbackError);
        }
      }
      
      // Se chegou aqui, todos os fallbacks falharam
      _addErrorLog('Todos os fallbacks falharam, definindo estado de erro');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = _getDetailedErrorMessage(e);
      });
      
      // Notificar erro
      widget.onError?.call(_errorMessage ?? e.toString());
      
      // Tentar reconexão automática se habilitada
      if (widget.enableAutoReconnect && _reconnectAttempts < widget.maxReconnectAttempts) {
        _addDebugLog('Agendando tentativa de reconexão...');
        _scheduleReconnect();
      } else {
        _addErrorLog('Máximo de tentativas atingido. Parando tentativas de reconexão.');
      }
    }
  }

  /// Inicializa o player com o tipo especificado
  Future<void> _initializeWithCurrentPlayer(String streamUrl) async {
    _addDebugLog('=== INICIALIZANDO COM PLAYER: $_currentPlayerType ===');
    _addDebugLog('Stream URL: $streamUrl');
    
    try {
      // Limpar controller anterior se existir
      if (_controller != null) {
        _addDebugLog('Limpando controller anterior...');
        _controller?.removeListener(_videoListener);
        await _controller?.dispose();
        _controller = null;
      }
      
      final playerId = '${widget.camera.name}_${_currentPlayerType.toString().split('.').last}';
      
      await LoggingService.instance.videoPlayback(
         'Inicializando player com stream URL',
         cameraId: widget.camera.name,
         url: streamUrl
       );
      
      _addDebugLog('Criando novo VideoPlayerController...');
      
      // Configurar o controller baseado no tipo de player
      if (_currentPlayerType == LivePlayerType.fvp) {
        await _initializeFvpPlayer(streamUrl);
      } else {
        await _initializeStandardPlayer(streamUrl);
      }
      
      _addDebugLog('Controller criado com sucesso');
      _addDebugLog('Iniciando inicialização do controller...');
      
      // Adicionar listener para monitorar o estado
      _controller!.addListener(_videoListener);
      
      // Inicializar o controller com timeout
      await _controller!.initialize().timeout(_initTimeout);
      
      if (!mounted) {
        _addDebugLog('Widget desmontado durante inicialização');
        return;
      }
      
      _addDebugLog('Controller inicializado com sucesso!');
      _addDebugLog('Duração do vídeo: ${_controller!.value.duration}');
      _addDebugLog('Tamanho do vídeo: ${_controller!.value.size}');
      _addDebugLog('Taxa de aspecto: ${_controller!.value.aspectRatio}');
      
      setState(() {
        _isLoading = false;
        _hasError = false;
        _errorMessage = null;
      });
      
      // Iniciar reprodução automaticamente
      _addDebugLog('Iniciando reprodução automática...');
      await _controller!.play();
      _addDebugLog('Player inicializado e reprodução iniciada com sucesso');
      
      _addDebugLog('=== PLAYER INICIALIZADO COM SUCESSO ===');
      
    } catch (e) {
      _addErrorLog('Erro crítico ao inicializar controller', e);
      
      // Limpar controller em caso de erro
      if (_controller != null) {
        try {
          _controller?.removeListener(_videoListener);
          await _controller?.dispose();
        } catch (disposeError) {
          _addErrorLog('Erro ao limpar controller após falha', disposeError);
        }
        _controller = null;
      }
      
      rethrow;
    }
  }

  /// Inicializa o player FVP (melhor para RTSP)
  Future<void> _initializeFvpPlayer(String streamUrl) async {
    _addDebugLog('=== INICIALIZANDO FVP PLAYER ===');
    _addDebugLog('Stream URL para FVP: $streamUrl');
    
    try {
      // Configurar FVP para RTSP com configurações otimizadas
      _addDebugLog('Criando Player FVP com configurações otimizadas...');
      
      // Usar FVP com configurações específicas para RTSP
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: _buildHeaders(),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );
      
      _addDebugLog('FVP Controller criado com sucesso');
      _addDebugLog('Configurações aplicadas: Headers otimizados, VideoPlayerOptions configuradas');
      
    } catch (e) {
      _addErrorLog('Erro crítico ao criar FVP Player', e);
      rethrow;
    }
  }

  /// Inicializa o player padrão
  Future<void> _initializeStandardPlayer(String streamUrl) async {
    _addDebugLog('=== INICIALIZANDO STANDARD PLAYER ===');
    _addDebugLog('Stream URL para Standard: $streamUrl');
    
    try {
      _addDebugLog('Criando VideoPlayerController padrão...');
      
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
          // Configurações adicionais para melhor compatibilidade
        ),
        httpHeaders: _buildHeaders(),
      );
      
      _addDebugLog('Standard Controller criado com sucesso');
      _addDebugLog('Headers HTTP configurados para melhor compatibilidade');
      
    } catch (e) {
      _addErrorLog('Erro crítico ao criar Standard Player', e);
      rethrow;
    }
  }

  /// Constrói headers HTTP otimizados para o player
  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'User-Agent': 'Flutter Live Stream Player/1.0',
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

  /// Valida se a URL do stream é válida
  bool _isValidStreamUrl(String url) {
    _addDebugLog('Validando URL: $url');
    
    try {
      final uri = Uri.parse(url);
      
      _addDebugLog('URI parseada - Scheme: ${uri.scheme}, Host: ${uri.host}, Port: ${uri.port}');
      
      // Verificar se tem scheme válido
      if (!uri.hasScheme) {
        _addDebugLog('ERRO: URL não possui scheme');
        return false;
      }
      
      // Verificar schemes suportados
      final validSchemes = ['rtsp', 'http', 'https', 'rtmp'];
      if (!validSchemes.contains(uri.scheme.toLowerCase())) {
        _addDebugLog('ERRO: Scheme não suportado: ${uri.scheme}');
        return false;
      }
      
      // Verificar se tem host
      if (!uri.hasAuthority || uri.host.isEmpty) {
        _addDebugLog('ERRO: URL não possui host válido');
        return false;
      }
      
      _addDebugLog('URL validada com sucesso');
      return true;
      
    } catch (e) {
      _addDebugLog('ERRO ao validar URL: $e');
      return false;
    }
  }

  /// Listener para monitorar o estado do vídeo
  void _videoListener() async {
    if (_controller != null && mounted) {
      final value = _controller!.value;
      final playerId = '${widget.camera.name}_${_currentPlayerType.toString().split('.').last}';
      
      // Detectar erros do player
      if (value.hasError) {
        final errorDesc = value.errorDescription ?? 'Erro desconhecido no player';
        _addDebugLog('Erro detectado no player: $errorDesc');
        
        await LoggingService.instance.videoPlayer(
          'Erro no player: $errorDesc',
          playerId: playerId,
          state: 'error',
          isError: true
        );
        
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = _getDetailedErrorMessage(Exception(errorDesc));
            _isLoading = false;
          });
          
          widget.onError?.call(_errorMessage!);
          
          // Tentar reconexão se habilitada
          if (widget.enableAutoReconnect && _reconnectAttempts < widget.maxReconnectAttempts) {
            _scheduleReconnect();
          }
        }
      }
    }
  }

  /// Agenda uma tentativa de reconexão
  void _scheduleReconnect() {
    if (_isReconnecting) return;
    
    _reconnectAttempts++;
    _addDebugLog('Agendando reconexão (tentativa $_reconnectAttempts/${widget.maxReconnectAttempts})');
    
    setState(() {
      _isReconnecting = true;
    });
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(widget.reconnectDelay, () {
      if (mounted && _reconnectAttempts <= widget.maxReconnectAttempts) {
        _addDebugLog('Executando reconexão...');
        _initializePlayer();
      }
    });
  }

  /// Obtém uma mensagem de erro detalhada
  String _getDetailedErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('timeout')) {
      return 'Timeout na conexão. Verifique a rede e tente novamente.';
    } else if (errorStr.contains('connection') || errorStr.contains('network')) {
      return 'Erro de conexão. Verifique se a câmera está acessível.';
    } else if (errorStr.contains('unauthorized') || errorStr.contains('401')) {
      return 'Não autorizado. Verifique as credenciais da câmera.';
    } else if (errorStr.contains('forbidden') || errorStr.contains('403')) {
      return 'Acesso negado pela câmera. Verifique as permissões.';
    } else if (errorStr.contains('not found') || errorStr.contains('404')) {
      return 'Stream não encontrado. Verifique a URL da câmera.';
    } else if (errorStr.contains('rtsp')) {
      return 'Erro no protocolo RTSP. Tente uma URL diferente.';
    }
    
    return 'Erro no player: ${error.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: _buildPlayerContent(),
    );
  }

  Widget _buildPlayerContent() {
    if (_isLoading || _isReconnecting) {
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            _isReconnecting ? 'Reconectando...' : 'Carregando stream...',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          if (_reconnectAttempts > 0)
            Text(
              'Tentativa $_reconnectAttempts/${widget.maxReconnectAttempts}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          const Text(
            'Erro no Stream',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Erro desconhecido',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              _reconnectAttempts = 0;
              _initializePlayer();
            },
            child: const Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoWidget() {
    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}