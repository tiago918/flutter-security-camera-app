import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/camera_models.dart';
import '../services/auto_recording_service.dart';
import '../services/motion_detection_service.dart';

class AutoRecordingSettingsPage extends StatefulWidget {
  final CameraData camera;

  const AutoRecordingSettingsPage({
    super.key,
    required this.camera,
  });

  @override
  State<AutoRecordingSettingsPage> createState() => _AutoRecordingSettingsPageState();
}

class _AutoRecordingSettingsPageState extends State<AutoRecordingSettingsPage> {
  final AutoRecordingService _autoRecordingService = AutoRecordingService();
  final MotionDetectionService _motionService = MotionDetectionService();
  
  AutoRecordingSettings? _settings;
  MotionDetectionConfig? _motionConfig;
  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _autoRecordingService.getAutoRecordingSettings(widget.camera.id);
      final motionConfig = await _motionService.getMotionDetectionConfig(widget.camera.id);
      
      setState(() {
        _settings = settings;
        _motionConfig = motionConfig;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Erro ao carregar configurações: $e');
    }
  }

  Future<void> _saveSettings() async {
    if (_settings == null || _motionConfig == null) return;
    
    try {
      await _autoRecordingService.saveAutoRecordingSettings(widget.camera.id, _settings!);
      await _motionService.saveMotionDetectionConfig(widget.camera.id.toString(), _motionConfig!);
      
      setState(() {
        _hasChanges = false;
      });
      
      _showSuccessSnackBar('Configurações salvas com sucesso!');
    } catch (e) {
      _showErrorSnackBar('Erro ao salvar configurações: $e');
    }
  }

  void _updateSettings(AutoRecordingSettings newSettings) {
    setState(() {
      _settings = newSettings;
      _hasChanges = true;
    });
  }

  void _updateMotionConfig(MotionDetectionConfig newConfig) {
    setState(() {
      _motionConfig = newConfig;
      _hasChanges = true;
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configurações - ${widget.camera.name}'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveSettings,
              tooltip: 'Salvar configurações',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _settings == null || _motionConfig == null
              ? const Center(child: Text('Erro ao carregar configurações'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGeneralSection(),
                      const SizedBox(height: 24),
                      _buildMotionDetectionSection(),
                      const SizedBox(height: 24),
                      _buildRecordingSection(),
                      const SizedBox(height: 24),
                      _buildStorageSection(),
                      const SizedBox(height: 24),
                      _buildAdvancedSection(),
                      const SizedBox(height: 32),
                      _buildActionButtons(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildGeneralSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configurações Gerais',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Gravação Automática'),
              subtitle: const Text('Ativar gravação quando movimento for detectado'),
              value: _settings!.enabled,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(enabled: value));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMotionDetectionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detecção de Movimento',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Detecção de Movimento'),
              subtitle: const Text('Ativar detecção de movimento'),
              value: _motionConfig!.enabled,
              onChanged: (value) {
                _updateMotionConfig(_motionConfig!.copyWith(enabled: value));
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Sensibilidade: ${_motionConfig!.sensitivity}%',
              style: const TextStyle(fontSize: 16),
            ),
            Slider(
              value: _motionConfig!.sensitivity.toDouble(),
              min: 10,
              max: 100,
              divisions: 18,
              label: '${_motionConfig!.sensitivity}%',
              onChanged: (value) {
                _updateMotionConfig(_motionConfig!.copyWith(sensitivity: value.round()));
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Menor valor = mais sensível (detecta movimentos menores)\n'
              'Maior valor = menos sensível (detecta apenas movimentos grandes)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configurações de Gravação',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Duração da Gravação'),
              subtitle: Text('${_settings!.recordingDuration} segundos'),
              trailing: SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: _settings!.recordingDuration.toString(),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) {
                    final duration = int.tryParse(value) ?? _settings!.recordingDuration;
                    if (duration >= 5 && duration <= 300) {
                      _updateSettings(_settings!.copyWith(recordingDuration: duration));
                    }
                  },
                  decoration: const InputDecoration(
                    suffixText: 's',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Pré-gravação'),
              subtitle: Text('${_settings!.preRecordingSeconds} segundos antes do movimento'),
              trailing: SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: _settings!.preRecordingSeconds.toString(),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) {
                    final duration = int.tryParse(value) ?? _settings!.preRecordingSeconds;
                    if (duration >= 0 && duration <= 30) {
                      _updateSettings(_settings!.copyWith(preRecordingSeconds: duration));
                    }
                  },
                  decoration: const InputDecoration(
                    suffixText: 's',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Pós-gravação'),
              subtitle: Text('${_settings!.postRecordingSeconds} segundos após o movimento'),
              trailing: SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: _settings!.postRecordingSeconds.toString(),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) {
                    final duration = int.tryParse(value) ?? _settings!.postRecordingSeconds;
                    if (duration >= 0 && duration <= 60) {
                      _updateSettings(_settings!.copyWith(postRecordingSeconds: duration));
                    }
                  },
                  decoration: const InputDecoration(
                    suffixText: 's',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Qualidade de Gravação'),
              subtitle: Text(_getQualityDescription(_settings!.recordingQuality)),
              trailing: DropdownButton<String>(
                value: _settings!.recordingQuality,
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Baixa')),
                  DropdownMenuItem(value: 'medium', child: Text('Média')),
                  DropdownMenuItem(value: 'high', child: Text('Alta')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _updateSettings(_settings!.copyWith(recordingQuality: value));
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Formato de Vídeo'),
              subtitle: Text(_settings!.recordingFormat.toUpperCase()),
              trailing: DropdownButton<String>(
                value: _settings!.recordingFormat,
                items: const [
                  DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                  DropdownMenuItem(value: 'avi', child: Text('AVI')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _updateSettings(_settings!.copyWith(recordingFormat: value));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Armazenamento',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Local de Armazenamento'),
              subtitle: Text(_getStorageLocationDescription(_settings!.storageLocation)),
              trailing: DropdownButton<String>(
                value: _settings!.storageLocation,
                items: const [
                  DropdownMenuItem(value: 'internal', child: Text('Interno')),
                  DropdownMenuItem(value: 'sdcard', child: Text('Cartão SD')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _updateSettings(_settings!.copyWith(storageLocation: value));
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Gravação Cíclica'),
              subtitle: const Text('Substituir gravações antigas quando o espaço estiver cheio'),
              value: _settings!.cyclicRecording,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(cyclicRecording: value));
              },
            ),
            if (_settings!.cyclicRecording) ...[
              const SizedBox(height: 8),
              ListTile(
                title: const Text('Limite de Armazenamento'),
                subtitle: Text('${_settings!.maxStorageMB} MB'),
                trailing: SizedBox(
                  width: 100,
                  child: TextFormField(
                    initialValue: _settings!.maxStorageMB.toString(),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      final storage = int.tryParse(value) ?? _settings!.maxStorageMB;
                      if (storage >= 100 && storage <= 10000) {
                        _updateSettings(_settings!.copyWith(maxStorageMB: storage));
                      }
                    },
                    decoration: const InputDecoration(
                      suffixText: 'MB',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configurações Avançadas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Zonas de Detecção'),
              subtitle: Text('${_motionConfig!.zones.where((z) => z.isEnabled).length} zonas ativas'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // TODO: Navegar para página de configuração de zonas
                _showInfoDialog('Configuração de Zonas', 
                    'A configuração de zonas de detecção será implementada em breve.');
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Teste de Detecção'),
              subtitle: const Text('Testar configurações de movimento'),
              trailing: const Icon(Icons.play_arrow),
              onTap: () {
                _testMotionDetection();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _hasChanges ? _saveSettings : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('Salvar Configurações'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              _loadSettings(); // Recarregar configurações originais
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('Cancelar'),
          ),
        ),
      ],
    );
  }

  String _getQualityDescription(String quality) {
    switch (quality) {
      case 'low':
        return 'Baixa qualidade (menor tamanho de arquivo)';
      case 'medium':
        return 'Qualidade média (balanceado)';
      case 'high':
        return 'Alta qualidade (maior tamanho de arquivo)';
      default:
        return 'Qualidade desconhecida';
    }
  }

  String _getStorageLocationDescription(String location) {
    switch (location) {
      case 'internal':
        return 'Armazenamento interno do dispositivo';
      case 'sdcard':
        return 'Cartão SD externo';
      default:
        return 'Local desconhecido';
    }
  }

  void _testMotionDetection() {
    _showInfoDialog('Teste de Detecção', 
        'Teste de detecção de movimento iniciado. Mova-se na frente da câmera para verificar se a detecção está funcionando.');
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}