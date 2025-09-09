import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/services.dart';

class NightModeButton extends StatefulWidget {
  final CameraModel camera;
  final bool isEnabled;
  final VoidCallback? onPressed;
  final double size;
  final bool showLabel;

  const NightModeButton({
    Key? key,
    required this.camera,
    this.isEnabled = false,
    this.onPressed,
    this.size = 20,
    this.showLabel = false,
  }) : super(key: key);

  @override
  State<NightModeButton> createState() => _NightModeButtonState();
}

class _NightModeButtonState extends State<NightModeButton>
    with TickerProviderStateMixin {
  final NightModeService _nightModeService = NightModeService();
  bool _isLoading = false;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));
    
    if (widget.isEnabled) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(NightModeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEnabled != oldWidget.isEnabled) {
      if (widget.isEnabled) {
        _glowController.repeat(reverse: true);
      } else {
        _glowController.stop();
        _glowController.reset();
      }
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.camera.capabilities.nightVision) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _isLoading ? null : _toggleNightMode,
      onLongPress: _showNightModeDialog,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.isEnabled 
                  ? Colors.indigo.withOpacity(0.3 * _glowAnimation.value)
                  : Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
              border: widget.isEnabled 
                  ? Border.all(
                      color: Colors.indigo.withOpacity(_glowAnimation.value),
                      width: 2,
                    )
                  : null,
              boxShadow: widget.isEnabled 
                  ? [
                      BoxShadow(
                        color: Colors.indigo.withOpacity(0.3 * _glowAnimation.value),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: _isLoading
                ? SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.isEnabled ? Colors.indigo : Colors.white,
                      ),
                    ),
                  )
                : _buildIcon(),
          );
        },
      ),
    );
  }

  Widget _buildIcon() {
    return Tooltip(
      message: widget.isEnabled ? 'Desativar modo noturno' : 'Ativar modo noturno',
      child: widget.showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isEnabled ? Icons.nights_stay : Icons.wb_sunny,
                  color: widget.isEnabled ? Colors.indigo : Colors.white,
                  size: widget.size,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.isEnabled ? 'Noturno' : 'Diurno',
                  style: TextStyle(
                    color: widget.isEnabled ? Colors.indigo : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          : Icon(
              widget.isEnabled ? Icons.nights_stay : Icons.wb_sunny,
              color: widget.isEnabled ? Colors.indigo : Colors.white,
              size: widget.size,
            ),
    );
  }

  void _toggleNightMode() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _nightModeService.toggleNightMode(
        widget.camera.id,
        !widget.isEnabled,
      );

      if (success) {
        widget.onPressed?.call();
        _showFeedback(
          widget.isEnabled 
              ? 'Modo noturno desativado'
              : 'Modo noturno ativado',
          isSuccess: true,
        );
      } else {
        _showFeedback(
          'Falha ao alterar modo noturno',
          isSuccess: false,
        );
      }
    } catch (e) {
      _showFeedback(
        'Erro ao alterar modo noturno: $e',
        isSuccess: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showNightModeDialog() {
    showDialog(
      context: context,
      builder: (context) => NightModeDialog(camera: widget.camera),
    );
  }

  void _showFeedback(String message, {required bool isSuccess}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.error,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: isSuccess ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

/// Dialog para configurações avançadas do modo noturno
class NightModeDialog extends StatefulWidget {
  final CameraModel camera;

  const NightModeDialog({
    Key? key,
    required this.camera,
  }) : super(key: key);

  @override
  State<NightModeDialog> createState() => _NightModeDialogState();
}

class _NightModeDialogState extends State<NightModeDialog> {
  final NightModeService _nightModeService = NightModeService();
  
  bool _autoModeEnabled = true;
  bool _irLedEnabled = true;
  double _sensitivity = 50.0;
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 6, minute: 0);
  NightModeType _selectedMode = NightModeType.auto;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
            Row(
              children: [
                Icon(
                  Icons.nights_stay,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Configurações do Modo Noturno',
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
            
            // Modo de operação
            _buildModeSelection(),
            
            const SizedBox(height: 16),
            
            // Configurações automáticas
            if (_selectedMode == NightModeType.auto) ..[
              _buildAutoModeSettings(),
              const SizedBox(height: 16),
            ],
            
            // Configurações por horário
            if (_selectedMode == NightModeType.scheduled) ..[
              _buildScheduleSettings(),
              const SizedBox(height: 16),
            ],
            
            // Configurações de LED IR
            _buildIRSettings(),
            
            const SizedBox(height: 20),
            
            // Botões de ação
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modo de Operação',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...NightModeType.values.map((mode) {
          return RadioListTile<NightModeType>(
            title: Text(_getModeTitle(mode)),
            subtitle: Text(_getModeDescription(mode)),
            value: mode,
            groupValue: _selectedMode,
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedMode = value);
              }
            },
          );
        }).toList(),
      ],
    );
  }

  Widget _buildAutoModeSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sensibilidade do Sensor',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Baixa'),
            Expanded(
              child: Slider(
                value: _sensitivity,
                min: 0,
                max: 100,
                divisions: 10,
                label: '${_sensitivity.round()}%',
                onChanged: (value) {
                  setState(() => _sensitivity = value);
                },
              ),
            ),
            const Text('Alta'),
          ],
        ),
      ],
    );
  }

  Widget _buildScheduleSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Horário de Ativação',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ListTile(
                title: const Text('Início'),
                subtitle: Text(_formatTime(_startTime)),
                trailing: const Icon(Icons.access_time),
                onTap: () => _selectTime(true),
              ),
            ),
            Expanded(
              child: ListTile(
                title: const Text('Fim'),
                subtitle: Text(_formatTime(_endTime)),
                trailing: const Icon(Icons.access_time),
                onTap: () => _selectTime(false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIRSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LED Infravermelho',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Ativar LED IR'),
          subtitle: const Text('Iluminação infravermelha para visão noturna'),
          value: _irLedEnabled,
          onChanged: (value) {
            setState(() => _irLedEnabled = value);
          },
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveSettings,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }

  String _getModeTitle(NightModeType mode) {
    switch (mode) {
      case NightModeType.auto:
        return 'Automático';
      case NightModeType.manual:
        return 'Manual';
      case NightModeType.scheduled:
        return 'Agendado';
      case NightModeType.disabled:
        return 'Desabilitado';
    }
  }

  String _getModeDescription(NightModeType mode) {
    switch (mode) {
      case NightModeType.auto:
        return 'Ativa automaticamente baseado na luminosidade';
      case NightModeType.manual:
        return 'Controle manual do modo noturno';
      case NightModeType.scheduled:
        return 'Ativa em horários específicos';
      case NightModeType.disabled:
        return 'Modo noturno sempre desabilitado';
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _loadCurrentSettings() async {
    // Carrega configurações atuais da câmera
    // Esta é uma implementação simulada
    setState(() {
      _autoModeEnabled = true;
      _irLedEnabled = true;
      _sensitivity = 50.0;
      _selectedMode = NightModeType.auto;
    });
  }

  void _selectTime(bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime ? _startTime : _endTime,
    );
    
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final config = NightModeConfig(
        mode: _selectedMode,
        autoModeEnabled: _autoModeEnabled,
        irLedEnabled: _irLedEnabled,
        sensitivity: _sensitivity / 100,
        startTime: _startTime,
        endTime: _endTime,
      );

      final success = await _nightModeService.configureNightMode(
        widget.camera.id,
        config,
      );

      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configurações salvas com sucesso'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _showError('Falha ao salvar configurações');
      }
    } catch (e) {
      _showError('Erro ao salvar configurações: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Enums e classes auxiliares
enum NightModeType {
  auto,
  manual,
  scheduled,
  disabled,
}

class NightModeConfig {
  final NightModeType mode;
  final bool autoModeEnabled;
  final bool irLedEnabled;
  final double sensitivity;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  const NightModeConfig({
    required this.mode,
    required this.autoModeEnabled,
    required this.irLedEnabled,
    required this.sensitivity,
    required this.startTime,
    required this.endTime,
  });
}