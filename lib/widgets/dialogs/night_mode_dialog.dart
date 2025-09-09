import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/services.dart';

class NightModeDialog extends StatefulWidget {
  final CameraModel camera;
  final NightModeService nightModeService;

  const NightModeDialog({
    super.key,
    required this.camera,
    required this.nightModeService,
  });

  @override
  State<NightModeDialog> createState() => _NightModeDialogState();
}

class _NightModeDialogState extends State<NightModeDialog> {
  bool _isNightModeEnabled = false;
  bool _autoModeEnabled = true;
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 6, minute: 0);
  double _irIntensity = 50.0;
  double _sensitivity = 75.0;
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await widget.nightModeService.getNightModeSettings(widget.camera.id);
      setState(() {
        _isNightModeEnabled = settings['enabled'] ?? false;
        _autoModeEnabled = settings['autoMode'] ?? true;
        _irIntensity = (settings['irIntensity'] ?? 50.0).toDouble();
        _sensitivity = (settings['sensitivity'] ?? 75.0).toDouble();
        
        if (settings['startTime'] != null) {
          final startParts = settings['startTime'].split(':');
          _startTime = TimeOfDay(
            hour: int.parse(startParts[0]),
            minute: int.parse(startParts[1]),
          );
        }
        
        if (settings['endTime'] != null) {
          final endParts = settings['endTime'].split(':');
          _endTime = TimeOfDay(
            hour: int.parse(endParts[0]),
            minute: int.parse(endParts[1]),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar configurações: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      await widget.nightModeService.setNightModeEnabled(
        widget.camera.id,
        _isNightModeEnabled,
      );
      
      await widget.nightModeService.configureNightMode(
        widget.camera.id,
        {
          'enabled': _isNightModeEnabled,
          'autoMode': _autoModeEnabled,
          'startTime': '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
          'endTime': '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
          'irIntensity': _irIntensity,
          'sensitivity': _sensitivity,
        },
      );
      
      setState(() => _hasChanges = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configurações salvas com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar configurações: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime ? _startTime : _endTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
        _hasChanges = true;
      });
    }
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.nightlight, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Modo Noturno - ${widget.camera.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Enable Night Mode
                      SwitchListTile(
                        title: const Text('Ativar Modo Noturno'),
                        subtitle: const Text('Habilita visão noturna infravermelha'),
                        value: _isNightModeEnabled,
                        onChanged: (value) {
                          setState(() => _isNightModeEnabled = value);
                          _markChanged();
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      if (_isNightModeEnabled) ..[
                        // Auto Mode
                        SwitchListTile(
                          title: const Text('Modo Automático'),
                          subtitle: const Text('Ativa automaticamente baseado no horário'),
                          value: _autoModeEnabled,
                          onChanged: (value) {
                            setState(() => _autoModeEnabled = value);
                            _markChanged();
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        if (_autoModeEnabled) ..[
                          // Time Schedule
                          Text(
                            'Horário de Ativação',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          
                          Row(
                            children: [
                              Expanded(
                                child: Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.wb_twilight),
                                    title: const Text('Início'),
                                    subtitle: Text(_startTime.format(context)),
                                    onTap: () => _selectTime(context, true),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.wb_sunny),
                                    title: const Text('Fim'),
                                    subtitle: Text(_endTime.format(context)),
                                    onTap: () => _selectTime(context, false),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                        
                        // IR Intensity
                        Text(
                          'Intensidade do Infravermelho',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.lightbulb_outline),
                                    const SizedBox(width: 8),
                                    Text('${_irIntensity.round()}%'),
                                    const Spacer(),
                                    Text(
                                      _irIntensity < 30 ? 'Baixa' : 
                                      _irIntensity < 70 ? 'Média' : 'Alta',
                                      style: TextStyle(
                                        color: _irIntensity < 30 ? Colors.blue : 
                                               _irIntensity < 70 ? Colors.orange : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: _irIntensity,
                                  min: 0,
                                  max: 100,
                                  divisions: 20,
                                  onChanged: (value) {
                                    setState(() => _irIntensity = value);
                                    _markChanged();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Sensitivity
                        Text(
                          'Sensibilidade de Luz',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.visibility),
                                    const SizedBox(width: 8),
                                    Text('${_sensitivity.round()}%'),
                                    const Spacer(),
                                    Text(
                                      _sensitivity < 30 ? 'Baixa' : 
                                      _sensitivity < 70 ? 'Média' : 'Alta',
                                      style: TextStyle(
                                        color: _sensitivity < 30 ? Colors.blue : 
                                               _sensitivity < 70 ? Colors.orange : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: _sensitivity,
                                  min: 0,
                                  max: 100,
                                  divisions: 20,
                                  onChanged: (value) {
                                    setState(() => _sensitivity = value);
                                    _markChanged();
                                  },
                                ),
                                const Text(
                                  'Maior sensibilidade ativa o modo noturno mais cedo',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 24),
            
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _hasChanges && !_isLoading ? _saveSettings : null,
                  child: _isLoading 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}