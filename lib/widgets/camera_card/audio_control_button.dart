import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/services.dart';

class AudioControlButton extends StatefulWidget {
  final CameraModel camera;
  final bool isMuted;
  final double volume;
  final VoidCallback? onMuteToggle;
  final ValueChanged<double>? onVolumeChanged;
  final double size;
  final bool showLabel;
  final bool showVolumeSlider;

  const AudioControlButton({
    Key? key,
    required this.camera,
    this.isMuted = false,
    this.volume = 0.5,
    this.onMuteToggle,
    this.onVolumeChanged,
    this.size = 20,
    this.showLabel = false,
    this.showVolumeSlider = false,
  }) : super(key: key);

  @override
  State<AudioControlButton> createState() => _AudioControlButtonState();
}

class _AudioControlButtonState extends State<AudioControlButton>
    with TickerProviderStateMixin {
  final CameraService _cameraService = CameraService();
  bool _isLoading = false;
  bool _showVolumeSlider = false;
  late AnimationController _volumeController;
  late Animation<double> _volumeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _volumeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _volumeAnimation = CurvedAnimation(
      parent: _volumeController,
      curve: Curves.easeInOut,
    );
    
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
    
    if (widget.showVolumeSlider) {
      _showVolumeSlider = true;
      _volumeController.forward();
    }
  }

  @override
  void didUpdateWidget(AudioControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showVolumeSlider != oldWidget.showVolumeSlider) {
      if (widget.showVolumeSlider) {
        _showVolumeSlider = true;
        _volumeController.forward();
      } else {
        _volumeController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _showVolumeSlider = false;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _volumeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.camera.capabilities.audioSupport) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _isLoading ? null : _toggleMute,
      onLongPress: _showAudioDialog,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: !widget.isMuted && widget.volume > 0 ? _pulseAnimation.value : 1.0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.isMuted 
                    ? Colors.red.withOpacity(0.3)
                    : Colors.green.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.isMuted ? Colors.red : Colors.green,
                  width: 1,
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: widget.size,
                      height: widget.size,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.isMuted ? Colors.red : Colors.green,
                        ),
                      ),
                    )
                  : _buildIcon(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIcon() {
    IconData iconData;
    Color iconColor;
    
    if (widget.isMuted) {
      iconData = Icons.volume_off;
      iconColor = Colors.red;
    } else if (widget.volume == 0) {
      iconData = Icons.volume_mute;
      iconColor = Colors.orange;
    } else if (widget.volume < 0.3) {
      iconData = Icons.volume_down;
      iconColor = Colors.green;
    } else if (widget.volume < 0.7) {
      iconData = Icons.volume_up;
      iconColor = Colors.green;
    } else {
      iconData = Icons.volume_up;
      iconColor = Colors.green;
      // Inicia animação de pulso para volume alto
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    }

    return Tooltip(
      message: widget.isMuted ? 'Ativar áudio' : 'Silenciar áudio',
      child: widget.showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconData,
                  color: iconColor,
                  size: widget.size,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.isMuted ? 'Mudo' : '${(widget.volume * 100).round()}%',
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_showVolumeSlider) ..[
                  const SizedBox(width: 8),
                  _buildVolumeSlider(),
                ],
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconData,
                  color: iconColor,
                  size: widget.size,
                ),
                if (_showVolumeSlider) ..[
                  const SizedBox(height: 4),
                  _buildVolumeSlider(),
                ],
              ],
            ),
    );
  }

  Widget _buildVolumeSlider() {
    return AnimatedBuilder(
      animation: _volumeAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _volumeAnimation.value,
          child: Opacity(
            opacity: _volumeAnimation.value,
            child: SizedBox(
              width: widget.showLabel ? 100 : 20,
              height: widget.showLabel ? 20 : 100,
              child: widget.showLabel
                  ? Slider(
                      value: widget.volume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      onChanged: widget.isMuted ? null : _onVolumeChanged,
                      activeColor: Colors.green,
                      inactiveColor: Colors.grey,
                    )
                  : RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        value: widget.volume,
                        min: 0.0,
                        max: 1.0,
                        divisions: 10,
                        onChanged: widget.isMuted ? null : _onVolumeChanged,
                        activeColor: Colors.green,
                        inactiveColor: Colors.grey,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  void _toggleMute() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _cameraService.setAudioMute(
        widget.camera.id,
        !widget.isMuted,
      );

      if (success) {
        widget.onMuteToggle?.call();
        _showFeedback(
          widget.isMuted 
              ? 'Áudio ativado'
              : 'Áudio silenciado',
          isSuccess: true,
        );
      } else {
        _showFeedback(
          'Falha ao alterar áudio',
          isSuccess: false,
        );
      }
    } catch (e) {
      _showFeedback(
        'Erro ao alterar áudio: $e',
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

  void _onVolumeChanged(double value) async {
    widget.onVolumeChanged?.call(value);
    
    try {
      await _cameraService.setAudioVolume(
        widget.camera.id,
        value,
      );
    } catch (e) {
      _showFeedback(
        'Erro ao alterar volume: $e',
        isSuccess: false,
      );
    }
  }

  void _showAudioDialog() {
    showDialog(
      context: context,
      builder: (context) => AudioControlDialog(camera: widget.camera),
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

/// Dialog para configurações avançadas de áudio
class AudioControlDialog extends StatefulWidget {
  final CameraModel camera;

  const AudioControlDialog({
    Key? key,
    required this.camera,
  }) : super(key: key);

  @override
  State<AudioControlDialog> createState() => _AudioControlDialogState();
}

class _AudioControlDialogState extends State<AudioControlDialog> {
  final CameraService _cameraService = CameraService();
  
  bool _isMuted = false;
  double _volume = 0.5;
  double _micVolume = 0.5;
  bool _micEnabled = false;
  bool _noiseReduction = true;
  bool _echoCancellation = true;
  AudioQuality _audioQuality = AudioQuality.medium;
  AudioCodec _audioCodec = AudioCodec.aac;
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
        width: 450,
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
                  Icons.volume_up,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Configurações de Áudio',
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
            
            // Controles de volume
            _buildVolumeControls(),
            
            const SizedBox(height: 16),
            
            // Configurações de microfone
            if (widget.camera.capabilities.twoWayAudio) ..[
              _buildMicrophoneSettings(),
              const SizedBox(height: 16),
            ],
            
            // Configurações de qualidade
            _buildQualitySettings(),
            
            const SizedBox(height: 16),
            
            // Configurações avançadas
            _buildAdvancedSettings(),
            
            const SizedBox(height: 20),
            
            // Botões de ação
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Volume de Reprodução',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              _isMuted ? Icons.volume_off : Icons.volume_up,
              color: _isMuted ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _isMuted ? 0 : _volume,
                min: 0,
                max: 1,
                divisions: 20,
                label: _isMuted ? 'Mudo' : '${(_volume * 100).round()}%',
                onChanged: (value) {
                  setState(() {
                    _volume = value;
                    _isMuted = value == 0;
                  });
                },
              ),
            ),
            Text('${(_volume * 100).round()}%'),
          ],
        ),
        SwitchListTile(
          title: const Text('Silenciar áudio'),
          value: _isMuted,
          onChanged: (value) {
            setState(() => _isMuted = value);
          },
        ),
      ],
    );
  }

  Widget _buildMicrophoneSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Microfone (Áudio Bidirecional)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Ativar microfone'),
          subtitle: const Text('Permite comunicação bidirecional'),
          value: _micEnabled,
          onChanged: (value) {
            setState(() => _micEnabled = value);
          },
        ),
        if (_micEnabled) ..[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.mic),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _micVolume,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: '${(_micVolume * 100).round()}%',
                  onChanged: (value) {
                    setState(() => _micVolume = value);
                  },
                ),
              ),
              Text('${(_micVolume * 100).round()}%'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildQualitySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qualidade de Áudio',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<AudioQuality>(
          value: _audioQuality,
          decoration: const InputDecoration(
            labelText: 'Qualidade',
            border: OutlineInputBorder(),
          ),
          items: AudioQuality.values.map((quality) {
            return DropdownMenuItem(
              value: quality,
              child: Text(_getQualityName(quality)),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _audioQuality = value);
            }
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<AudioCodec>(
          value: _audioCodec,
          decoration: const InputDecoration(
            labelText: 'Codec',
            border: OutlineInputBorder(),
          ),
          items: AudioCodec.values.map((codec) {
            return DropdownMenuItem(
              value: codec,
              child: Text(codec.name.toUpperCase()),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _audioCodec = value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildAdvancedSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configurações Avançadas',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Redução de ruído'),
          subtitle: const Text('Remove ruídos de fundo do áudio'),
          value: _noiseReduction,
          onChanged: (value) {
            setState(() => _noiseReduction = value);
          },
        ),
        SwitchListTile(
          title: const Text('Cancelamento de eco'),
          subtitle: const Text('Reduz eco na comunicação bidirecional'),
          value: _echoCancellation,
          onChanged: (value) {
            setState(() => _echoCancellation = value);
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

  String _getQualityName(AudioQuality quality) {
    switch (quality) {
      case AudioQuality.low:
        return 'Baixa (32 kbps)';
      case AudioQuality.medium:
        return 'Média (64 kbps)';
      case AudioQuality.high:
        return 'Alta (128 kbps)';
      case AudioQuality.lossless:
        return 'Sem perdas (256 kbps)';
    }
  }

  void _loadCurrentSettings() async {
    // Carrega configurações atuais da câmera
    // Esta é uma implementação simulada
    setState(() {
      _isMuted = false;
      _volume = 0.5;
      _micVolume = 0.5;
      _micEnabled = false;
      _noiseReduction = true;
      _echoCancellation = true;
      _audioQuality = AudioQuality.medium;
      _audioCodec = AudioCodec.aac;
    });
  }

  void _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final config = AudioConfig(
        volume: _volume,
        isMuted: _isMuted,
        micVolume: _micVolume,
        micEnabled: _micEnabled,
        noiseReduction: _noiseReduction,
        echoCancellation: _echoCancellation,
        quality: _audioQuality,
        codec: _audioCodec,
      );

      final success = await _cameraService.configureAudio(
        widget.camera.id,
        config,
      );

      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configurações de áudio salvas com sucesso'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _showError('Falha ao salvar configurações de áudio');
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
enum AudioQuality {
  low,
  medium,
  high,
  lossless,
}

class AudioConfig {
  final double volume;
  final bool isMuted;
  final double micVolume;
  final bool micEnabled;
  final bool noiseReduction;
  final bool echoCancellation;
  final AudioQuality quality;
  final AudioCodec codec;

  const AudioConfig({
    required this.volume,
    required this.isMuted,
    required this.micVolume,
    required this.micEnabled,
    required this.noiseReduction,
    required this.echoCancellation,
    required this.quality,
    required this.codec,
  });
}