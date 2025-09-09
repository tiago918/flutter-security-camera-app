import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/services.dart';

class PlayerControls extends StatefulWidget {
  final CameraModel camera;
  final VoidCallback? onFullscreen;
  final VoidCallback? onSnapshot;
  final VoidCallback? onRecord;
  final VoidCallback? onPTZControl;
  final VoidCallback? onNightMode;
  final VoidCallback? onAudioControl;
  final VoidCallback? onSettings;
  final bool isFullscreen;
  final bool isRecording;
  final bool isAudioEnabled;
  final bool isNightModeEnabled;
  final bool showAdvancedControls;

  const PlayerControls({
    Key? key,
    required this.camera,
    this.onFullscreen,
    this.onSnapshot,
    this.onRecord,
    this.onPTZControl,
    this.onNightMode,
    this.onAudioControl,
    this.onSettings,
    this.isFullscreen = false,
    this.isRecording = false,
    this.isAudioEnabled = true,
    this.isNightModeEnabled = false,
    this.showAdvancedControls = true,
  }) : super(key: key);

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls>
    with TickerProviderStateMixin {
  bool _isVisible = true;
  bool _isExpanded = false;
  late AnimationController _fadeController;
  late AnimationController _expandController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    
    _expandAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    ));
    
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _toggleVisibility() {
    setState(() {
      _isVisible = !_isVisible;
      if (_isVisible) {
        _fadeController.forward();
      } else {
        _fadeController.reverse();
      }
    });
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleVisibility,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.7),
            ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: _buildControls(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Controles principais
        _buildMainControls(),
        
        // Controles expandidos
        if (widget.showAdvancedControls)
          AnimatedBuilder(
            animation: _expandAnimation,
            builder: (context, child) {
              return SizeTransition(
                sizeFactor: _expandAnimation,
                child: _buildExpandedControls(),
              );
            },
          ),
        
        // Barra de status
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildMainControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Botão de snapshot
          _buildControlButton(
            icon: Icons.camera_alt,
            onPressed: widget.onSnapshot,
            tooltip: 'Capturar foto',
          ),
          
          // Botão de gravação
          _buildControlButton(
            icon: widget.isRecording ? Icons.stop : Icons.fiber_manual_record,
            onPressed: widget.onRecord,
            tooltip: widget.isRecording ? 'Parar gravação' : 'Iniciar gravação',
            isActive: widget.isRecording,
            activeColor: Colors.red,
          ),
          
          // Botão PTZ (se suportado)
          if (widget.camera.capabilities.ptz.isSupported)
            PTZControlButton(
              camera: widget.camera,
              onPressed: widget.onPTZControl,
            ),
          
          // Botão de modo noturno
          NightModeButton(
            camera: widget.camera,
            isEnabled: widget.isNightModeEnabled,
            onPressed: widget.onNightMode,
          ),
          
          // Botão de áudio
          AudioControlButton(
            camera: widget.camera,
            isEnabled: widget.isAudioEnabled,
            onPressed: widget.onAudioControl,
          ),
          
          // Botão de tela cheia
          _buildControlButton(
            icon: widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            onPressed: widget.onFullscreen,
            tooltip: widget.isFullscreen ? 'Sair da tela cheia' : 'Tela cheia',
          ),
          
          // Botão de expandir controles
          if (widget.showAdvancedControls)
            _buildControlButton(
              icon: _isExpanded ? Icons.expand_less : Icons.expand_more,
              onPressed: _toggleExpanded,
              tooltip: _isExpanded ? 'Menos controles' : 'Mais controles',
            ),
        ],
      ),
    );
  }

  Widget _buildExpandedControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Primeira linha de controles expandidos
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                icon: Icons.settings,
                onPressed: widget.onSettings,
                tooltip: 'Configurações',
              ),
              _buildControlButton(
                icon: Icons.refresh,
                onPressed: () => _refreshStream(),
                tooltip: 'Atualizar stream',
              ),
              _buildControlButton(
                icon: Icons.info_outline,
                onPressed: () => _showCameraInfo(),
                tooltip: 'Informações da câmera',
              ),
              _buildControlButton(
                icon: Icons.video_library,
                onPressed: () => _showRecordings(),
                tooltip: 'Gravações',
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Segunda linha - controles de qualidade
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildQualityButton('HD', StreamQuality.hd),
              _buildQualityButton('FHD', StreamQuality.fullHd),
              _buildQualityButton('4K', StreamQuality.uhd4k),
              _buildQualityButton('AUTO', null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Status da conexão
          Icon(
            Icons.circle,
            size: 8,
            color: _getConnectionStatusColor(),
          ),
          const SizedBox(width: 4),
          Text(
            _getConnectionStatusText(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
            ),
          ),
          
          const Spacer(),
          
          // Informações do stream
          if (widget.camera.streamConfig != null)
            Text(
              '${widget.camera.streamConfig!.resolution} • ${widget.camera.streamConfig!.fps}fps',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          
          const SizedBox(width: 8),
          
          // Indicador de gravação
          if (widget.isRecording)
            Row(
              children: [
                Icon(
                  Icons.fiber_manual_record,
                  size: 8,
                  color: Colors.red,
                ),
                const SizedBox(width: 2),
                const Text(
                  'REC',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    bool isActive = false,
    Color? activeColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isActive 
                  ? (activeColor ?? Theme.of(context).primaryColor).withOpacity(0.3)
                  : Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
              border: isActive 
                  ? Border.all(color: activeColor ?? Theme.of(context).primaryColor)
                  : null,
            ),
            child: Icon(
              icon,
              color: isActive 
                  ? (activeColor ?? Theme.of(context).primaryColor)
                  : Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityButton(String label, StreamQuality? quality) {
    final isSelected = widget.camera.streamConfig?.quality == quality;
    
    return GestureDetector(
      onTap: () => _changeStreamQuality(quality),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected 
              ? Theme.of(context).primaryColor.withOpacity(0.3)
              : Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: isSelected 
              ? Border.all(color: Theme.of(context).primaryColor)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected 
                ? Theme.of(context).primaryColor
                : Colors.white70,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Color _getConnectionStatusColor() {
    // Simula status da conexão baseado no estado da câmera
    if (widget.camera.isOnline) {
      return Colors.green;
    } else {
      return Colors.red;
    }
  }

  String _getConnectionStatusText() {
    if (widget.camera.isOnline) {
      return 'Online';
    } else {
      return 'Offline';
    }
  }

  void _refreshStream() {
    // Implementa refresh do stream
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Atualizando stream...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showCameraInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Informações - ${widget.camera.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IP: ${widget.camera.getHost()}'),
            Text('Modelo: ${widget.camera.model}'),
            Text('Firmware: ${widget.camera.firmwareVersion}'),
            Text('Status: ${widget.camera.isOnline ? "Online" : "Offline"}'),
            if (widget.camera.streamConfig != null) ..[
              const SizedBox(height: 8),
              const Text('Stream:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Resolução: ${widget.camera.streamConfig!.resolution}'),
              Text('FPS: ${widget.camera.streamConfig!.fps}'),
              Text('Codec: ${widget.camera.streamConfig!.videoCodec.name}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showRecordings() {
    // Implementa navegação para tela de gravações
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Abrindo gravações...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _changeStreamQuality(StreamQuality? quality) {
    // Implementa mudança de qualidade do stream
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Alterando qualidade para ${quality?.name ?? "AUTO"}...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}