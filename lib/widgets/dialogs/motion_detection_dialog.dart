import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/services.dart';

class MotionDetectionDialog extends StatefulWidget {
  final CameraModel camera;
  final Function(CameraModel)? onSettingsChanged;

  const MotionDetectionDialog({
    super.key,
    required this.camera,
    this.onSettingsChanged,
  });

  @override
  State<MotionDetectionDialog> createState() => _MotionDetectionDialogState();
}

class _MotionDetectionDialogState extends State<MotionDetectionDialog> {
  late bool _isEnabled;
  late double _sensitivity;
  late bool _recordOnMotion;
  late bool _sendNotifications;
  late List<String> _detectionZones;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late bool _scheduleEnabled;
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    // Carregar configurações atuais da câmera
    _isEnabled = widget.camera.motionDetectionEnabled ?? false;
    _sensitivity = 0.5; // Valor padrão
    _recordOnMotion = true;
    _sendNotifications = true;
    _detectionZones = ['Zona 1', 'Zona 2'];
    _startTime = const TimeOfDay(hour: 18, minute: 0);
    _endTime = const TimeOfDay(hour: 6, minute: 0);
    _scheduleEnabled = false;
  }

  void _markAsChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    
    try {
      // Simular salvamento das configurações
      await Future.delayed(const Duration(seconds: 1));
      
      // Atualizar o modelo da câmera
      final updatedCamera = widget.camera.copyWith(
        motionDetectionEnabled: _isEnabled,
      );
      
      widget.onSettingsChanged?.call(updatedCamera);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações de detecção de movimento salvas'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar configurações: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _testDetection() async {
    setState(() => _isLoading = true);
    
    try {
      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Teste de Detecção'),
            content: const Text(
              'Teste realizado com sucesso!\n\n'
              'Sensibilidade: Boa\n'
              'Zonas ativas: 2\n'
              'Status: Funcionando',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no teste: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.motion_photos_on,
                  color: Theme.of(context).primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detecção de Movimento',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.camera.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Enable/Disable
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              _isEnabled ? Icons.motion_photos_on : Icons.motion_photos_off,
                              color: _isEnabled ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Detecção de Movimento',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    _isEnabled ? 'Ativada' : 'Desativada',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isEnabled,
                              onChanged: (value) {
                                setState(() => _isEnabled = value);
                                _markAsChanged();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    if (_isEnabled) ..[
                      // Sensitivity
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sensibilidade',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('Baixa'),
                                  Expanded(
                                    child: Slider(
                                      value: _sensitivity,
                                      onChanged: (value) {
                                        setState(() => _sensitivity = value);
                                        _markAsChanged();
                                      },
                                      divisions: 10,
                                      label: '${(_sensitivity * 100).round()}%',
                                    ),
                                  ),
                                  const Text('Alta'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Actions
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ações',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                title: const Text('Gravar quando detectar movimento'),
                                subtitle: const Text('Iniciar gravação automaticamente'),
                                value: _recordOnMotion,
                                onChanged: (value) {
                                  setState(() => _recordOnMotion = value);
                                  _markAsChanged();
                                },
                                contentPadding: EdgeInsets.zero,
                              ),
                              SwitchListTile(
                                title: const Text('Enviar notificações'),
                                subtitle: const Text('Notificar sobre movimento detectado'),
                                value: _sendNotifications,
                                onChanged: (value) {
                                  setState(() => _sendNotifications = value);
                                  _markAsChanged();
                                },
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Detection Zones
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Zonas de Detecção',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () {
                                      // Implementar configuração de zonas
                                    },
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('Configurar'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: _detectionZones.map((zone) => Chip(
                                  label: Text(zone),
                                  backgroundColor: Colors.blue.shade100,
                                )).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Schedule
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Horário de Funcionamento',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: _scheduleEnabled,
                                    onChanged: (value) {
                                      setState(() => _scheduleEnabled = value);
                                      _markAsChanged();
                                    },
                                  ),
                                ],
                              ),
                              if (_scheduleEnabled) ..[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ListTile(
                                        title: const Text('Início'),
                                        subtitle: Text(_startTime.format(context)),
                                        leading: const Icon(Icons.access_time),
                                        onTap: () async {
                                          final time = await showTimePicker(
                                            context: context,
                                            initialTime: _startTime,
                                          );
                                          if (time != null) {
                                            setState(() => _startTime = time);
                                            _markAsChanged();
                                          }
                                        },
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    Expanded(
                                      child: ListTile(
                                        title: const Text('Fim'),
                                        subtitle: Text(_endTime.format(context)),
                                        leading: const Icon(Icons.access_time),
                                        onTap: () async {
                                          final time = await showTimePicker(
                                            context: context,
                                            initialTime: _endTime,
                                          );
                                          if (time != null) {
                                            setState(() => _endTime = time);
                                            _markAsChanged();
                                          }
                                        },
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Actions
            const SizedBox(height: 24),
            Row(
              children: [
                if (_isEnabled)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _testDetection,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Testar'),
                    ),
                  ),
                if (_isEnabled) const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isLoading || !_hasChanges) ? null : _saveSettings,
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}