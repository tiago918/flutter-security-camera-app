import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/services.dart';

class PTZControlButton extends StatefulWidget {
  final CameraModel camera;
  final VoidCallback? onPressed;
  final bool showQuickControls;
  final double size;

  const PTZControlButton({
    Key? key,
    required this.camera,
    this.onPressed,
    this.showQuickControls = false,
    this.size = 20,
  }) : super(key: key);

  @override
  State<PTZControlButton> createState() => _PTZControlButtonState();
}

class _PTZControlButtonState extends State<PTZControlButton>
    with TickerProviderStateMixin {
  final PTZService _ptzService = PTZService();
  bool _isPressed = false;
  bool _showQuickControls = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.camera.capabilities.ptz.isSupported) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        if (widget.showQuickControls) {
          _toggleQuickControls();
        } else {
          widget.onPressed?.call();
        }
      },
      onLongPress: widget.showQuickControls ? null : _toggleQuickControls,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Botão principal
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _isPressed ? _pulseAnimation.value : 1.0,
                child: _buildMainButton(),
              );
            },
          ),
          
          // Controles rápidos
          if (_showQuickControls)
            _buildQuickControls(),
        ],
      ),
    );
  }

  Widget _buildMainButton() {
    return Tooltip(
      message: 'Controle PTZ',
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _isPressed 
              ? Theme.of(context).primaryColor.withOpacity(0.3)
              : Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          border: _isPressed 
              ? Border.all(color: Theme.of(context).primaryColor)
              : null,
        ),
        child: Icon(
          Icons.control_camera,
          color: _isPressed 
              ? Theme.of(context).primaryColor
              : Colors.white,
          size: widget.size,
        ),
      ),
    );
  }

  Widget _buildQuickControls() {
    return Positioned(
      top: -60,
      left: -40,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(60),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            // Controles direcionais
            _buildDirectionalControl(PTZDirection.up, 0, -30, Icons.keyboard_arrow_up),
            _buildDirectionalControl(PTZDirection.down, 0, 30, Icons.keyboard_arrow_down),
            _buildDirectionalControl(PTZDirection.left, -30, 0, Icons.keyboard_arrow_left),
            _buildDirectionalControl(PTZDirection.right, 30, 0, Icons.keyboard_arrow_right),
            
            // Controles de zoom
            _buildZoomControl(true, -20, -20, Icons.add),
            _buildZoomControl(false, 20, -20, Icons.remove),
            
            // Botão de parada no centro
            _buildStopControl(),
            
            // Botão de fechar
            Positioned(
              top: 5,
              right: 5,
              child: GestureDetector(
                onTap: _toggleQuickControls,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionalControl(
    PTZDirection direction,
    double offsetX,
    double offsetY,
    IconData icon,
  ) {
    return Positioned(
      left: 60 + offsetX - 15,
      top: 60 + offsetY - 15,
      child: GestureDetector(
        onTapDown: (_) => _startPTZMovement(direction),
        onTapUp: (_) => _stopPTZMovement(),
        onTapCancel: _stopPTZMovement,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.7),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControl(
    bool zoomIn,
    double offsetX,
    double offsetY,
    IconData icon,
  ) {
    return Positioned(
      left: 60 + offsetX - 12,
      top: 60 + offsetY - 12,
      child: GestureDetector(
        onTapDown: (_) => _startZoom(zoomIn),
        onTapUp: (_) => _stopPTZMovement(),
        onTapCancel: _stopPTZMovement,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildStopControl() {
    return Positioned(
      left: 60 - 10,
      top: 60 - 10,
      child: GestureDetector(
        onTap: _stopPTZMovement,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.stop,
            color: Colors.white,
            size: 12,
          ),
        ),
      ),
    );
  }

  void _toggleQuickControls() {
    setState(() {
      _showQuickControls = !_showQuickControls;
      if (_showQuickControls) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    });
  }

  void _startPTZMovement(PTZDirection direction) {
    setState(() {
      _isPressed = true;
    });
    
    final command = PTZCommand.move(
      direction: direction,
      speed: PTZSpeed.medium,
    );
    
    _ptzService.sendPTZCommand(widget.camera.id, command).then((success) {
      if (!success) {
        _showError('Falha ao executar comando PTZ');
      }
    });
  }

  void _startZoom(bool zoomIn) {
    setState(() {
      _isPressed = true;
    });
    
    final command = zoomIn 
        ? PTZCommand.zoomIn(speed: PTZSpeed.medium)
        : PTZCommand.zoomOut(speed: PTZSpeed.medium);
    
    _ptzService.sendPTZCommand(widget.camera.id, command).then((success) {
      if (!success) {
        _showError('Falha ao executar comando de zoom');
      }
    });
  }

  void _stopPTZMovement() {
    setState(() {
      _isPressed = false;
    });
    
    final command = PTZCommand.stop();
    _ptzService.sendPTZCommand(widget.camera.id, command);
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

/// Widget para controle PTZ completo em dialog
class PTZControlDialog extends StatefulWidget {
  final CameraModel camera;

  const PTZControlDialog({
    Key? key,
    required this.camera,
  }) : super(key: key);

  @override
  State<PTZControlDialog> createState() => _PTZControlDialogState();
}

class _PTZControlDialogState extends State<PTZControlDialog> {
  final PTZService _ptzService = PTZService();
  PTZSpeed _currentSpeed = PTZSpeed.medium;
  int _selectedPreset = 1;
  bool _isAutoScanEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 350,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Título
            Row(
              children: [
                Icon(
                  Icons.control_camera,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Controle PTZ - ${widget.camera.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Controle direcional
            _buildDirectionalPad(),
            
            const SizedBox(height: 20),
            
            // Controles de velocidade
            _buildSpeedControl(),
            
            const SizedBox(height: 20),
            
            // Controles de preset
            _buildPresetControls(),
            
            const SizedBox(height: 20),
            
            // Controles especiais
            _buildSpecialControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionalPad() {
    return Container(
      width: 200,
      height: 200,
      child: Stack(
        children: [
          // Fundo circular
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.3),
                width: 2,
              ),
            ),
          ),
          
          // Controles direcionais
          _buildPadButton(PTZDirection.up, 100 - 25, 20, Icons.keyboard_arrow_up),
          _buildPadButton(PTZDirection.down, 100 - 25, 160, Icons.keyboard_arrow_down),
          _buildPadButton(PTZDirection.left, 20, 100 - 25, Icons.keyboard_arrow_left),
          _buildPadButton(PTZDirection.right, 160, 100 - 25, Icons.keyboard_arrow_right),
          
          // Zoom in/out
          _buildZoomButton(true, 140, 40, Icons.add),
          _buildZoomButton(false, 140, 140, Icons.remove),
          
          // Botão de parada central
          Positioned(
            left: 100 - 20,
            top: 100 - 20,
            child: GestureDetector(
              onTap: () => _sendPTZCommand(PTZCommand.stop()),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.stop,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPadButton(
    PTZDirection direction,
    double left,
    double top,
    IconData icon,
  ) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTapDown: (_) => _sendPTZCommand(PTZCommand.move(
          direction: direction,
          speed: _currentSpeed,
        )),
        onTapUp: (_) => _sendPTZCommand(PTZCommand.stop()),
        onTapCancel: () => _sendPTZCommand(PTZCommand.stop()),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.7),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildZoomButton(
    bool zoomIn,
    double left,
    double top,
    IconData icon,
  ) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTapDown: (_) => _sendPTZCommand(zoomIn 
            ? PTZCommand.zoomIn(speed: _currentSpeed)
            : PTZCommand.zoomOut(speed: _currentSpeed)),
        onTapUp: (_) => _sendPTZCommand(PTZCommand.stop()),
        onTapCancel: () => _sendPTZCommand(PTZCommand.stop()),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Velocidade',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: PTZSpeed.values.map((speed) {
            final isSelected = _currentSpeed == speed;
            return GestureDetector(
              onTap: () => setState(() => _currentSpeed = speed),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? Theme.of(context).primaryColor
                      : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  speed.name.toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : null,
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPresetControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Presets',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButton<int>(
                value: _selectedPreset,
                isExpanded: true,
                items: List.generate(8, (index) => index + 1)
                    .map((preset) => DropdownMenuItem(
                      value: preset,
                      child: Text('Preset $preset'),
                    ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedPreset = value);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _sendPTZCommand(
                PTZCommand.gotoPreset(presetId: _selectedPreset),
              ),
              child: const Text('Ir'),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () => _sendPTZCommand(
                PTZCommand.setPreset(presetId: _selectedPreset),
              ),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpecialControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Controles Especiais',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: () => _sendPTZCommand(PTZCommand.autoFocus()),
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Foco Auto'),
            ),
            ElevatedButton.icon(
              onPressed: _toggleAutoScan,
              icon: Icon(_isAutoScanEnabled ? Icons.stop : Icons.360),
              label: Text(_isAutoScanEnabled ? 'Parar Scan' : 'Auto Scan'),
            ),
          ],
        ),
      ],
    );
  }

  void _sendPTZCommand(PTZCommand command) {
    _ptzService.sendPTZCommand(widget.camera.id, command).then((success) {
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao executar comando PTZ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  void _toggleAutoScan() {
    setState(() {
      _isAutoScanEnabled = !_isAutoScanEnabled;
    });
    
    final command = _isAutoScanEnabled 
        ? PTZCommand.startAutoScan()
        : PTZCommand.stopAutoScan();
    
    _sendPTZCommand(command);
  }
}