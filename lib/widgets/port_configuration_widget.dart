import 'package:flutter/material.dart';
import '../models/camera_models.dart';
import '../services/fast_camera_discovery_service.dart';

/// Widget para configuração avançada de portas de câmeras
class PortConfigurationWidget extends StatefulWidget {
  final CameraPortConfiguration? initialConfiguration;
  final String? host;
  final String? username;
  final String? password;
  final Function(CameraPortConfiguration) onConfigurationChanged;
  final bool showAdvancedOptions;

  const PortConfigurationWidget({
    super.key,
    this.initialConfiguration,
    this.host,
    this.username,
    this.password,
    required this.onConfigurationChanged,
    this.showAdvancedOptions = false,
  });

  @override
  State<PortConfigurationWidget> createState() => _PortConfigurationWidgetState();
}

class _PortConfigurationWidgetState extends State<PortConfigurationWidget> {
  late CameraPortConfiguration _configuration;
  bool _isDetecting = false;
  bool _showAdvanced = false;
  String? _detectionResult;

  @override
  void initState() {
    super.initState();
    _configuration = widget.initialConfiguration ?? CameraPortConfiguration();
    _showAdvanced = widget.showAdvancedOptions;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabeçalho com botão de detecção automática
        Row(
          children: [
            const Text(
              'Configuração de Portas',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (widget.host != null && widget.host!.isNotEmpty)
              _buildAutoDetectButton(),
          ],
        ),
        const SizedBox(height: 12),
        
        // Configurações básicas
        _buildBasicConfiguration(),
        
        const SizedBox(height: 12),
        
        // Botão para mostrar/ocultar configurações avançadas
        TextButton.icon(
          onPressed: () {
            setState(() {
              _showAdvanced = !_showAdvanced;
            });
          },
          icon: Icon(
            _showAdvanced ? Icons.expand_less : Icons.expand_more,
            color: const Color(0xFF4CAF50),
          ),
          label: Text(
            _showAdvanced ? 'Ocultar configurações avançadas' : 'Mostrar configurações avançadas',
            style: const TextStyle(color: Color(0xFF4CAF50)),
          ),
        ),
        
        // Configurações avançadas (expansível)
        if (_showAdvanced) ...[
          const SizedBox(height: 12),
          _buildAdvancedConfiguration(),
        ],
        
        // Resultado da detecção
        if (_detectionResult != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF4CAF50), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF4CAF50), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _detectionResult!,
                    style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAutoDetectButton() {
    return ElevatedButton.icon(
      onPressed: _isDetecting ? null : _performAutoDetection,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: _isDetecting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.search, size: 16),
      label: Text(
        _isDetecting ? 'Detectando...' : 'Auto-detectar',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildBasicConfiguration() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildPortField(
                'Porta HTTP',
                _configuration.httpPort,
                (value) => _updateConfiguration(
                  _configuration.copyWith(httpPort: value),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPortField(
                'Porta RTSP',
                _configuration.rtspPort,
                (value) => _updateConfiguration(
                  _configuration.copyWith(rtspPort: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildPortField(
                'Porta ONVIF',
                _configuration.onvifPort,
                (value) => _updateConfiguration(
                  _configuration.copyWith(onvifPort: value),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildProtocolDropdown(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdvancedConfiguration() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Configurações Avançadas',
          style: TextStyle(
            color: Color(0xFF9E9E9E),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildPortField(
                'Porta Proprietária',
                _configuration.proprietaryPort,
                (value) => _updateConfiguration(
                  _configuration.copyWith(proprietaryPort: value),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPortField(
                'Porta Alternativa',
                _configuration.alternativePort,
                (value) => _updateConfiguration(
                  _configuration.copyWith(alternativePort: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text(
            'Usar HTTPS',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            'Usar conexão segura quando disponível',
            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
          ),
          value: _configuration.useHttps,
          onChanged: (value) => _updateConfiguration(
            _configuration.copyWith(useHttps: value),
          ),
          activeColor: const Color(0xFF4CAF50),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text(
            'Aceitar Certificados Autoassinados',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            'Permitir conexões HTTPS com certificados não verificados',
            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
          ),
          value: _configuration.acceptSelfSigned,
          onChanged: (value) => _updateConfiguration(
            _configuration.copyWith(acceptSelfSigned: value),
          ),
          activeColor: const Color(0xFF4CAF50),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildPortField(String label, int value, Function(int) onChanged) {
    final controller = TextEditingController(text: value.toString());
    
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
        border: const OutlineInputBorder(),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF3A3A3A)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF4CAF50)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Informe a porta';
        final port = int.tryParse(v.trim());
        if (port == null || port <= 0 || port > 65535) return 'Porta inválida';
        return null;
      },
      onChanged: (v) {
        final port = int.tryParse(v.trim());
        if (port != null && port > 0 && port <= 65535) {
          onChanged(port);
        }
      },
    );
  }

  Widget _buildProtocolDropdown() {
    return DropdownButtonFormField<String>(
      value: _configuration.preferredProtocol,
      dropdownColor: const Color(0xFF2A2A2A),
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        labelText: 'Protocolo Preferido',
        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
        border: OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF3A3A3A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF4CAF50)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'onvif', child: Text('ONVIF')),
        DropdownMenuItem(value: 'proprietary', child: Text('Proprietário')),
        DropdownMenuItem(value: 'auto', child: Text('Automático')),
      ],
      onChanged: (value) {
        if (value != null) {
          _updateConfiguration(
            _configuration.copyWith(preferredProtocol: value),
          );
        }
      },
    );
  }

  void _updateConfiguration(CameraPortConfiguration newConfiguration) {
    setState(() {
      _configuration = newConfiguration;
    });
    widget.onConfigurationChanged(newConfiguration);
  }

  Future<void> _performAutoDetection() async {
    if (widget.host == null || widget.host!.isEmpty) {
      setState(() {
        _detectionResult = 'Host não informado para detecção automática';
      });
      return;
    }

    setState(() {
      _isDetecting = true;
      _detectionResult = null;
    });

    try {
      // Executar detecção de protocolo
      final result = await FastCameraDiscoveryService.detectProtocol(
        widget.host!,
        username: widget.username,
        password: widget.password,
        timeout: const Duration(seconds: 10),
      );

      if (result['isSuccessful'] == true) {
        // Aplicar configuração otimizada
        final optimizedConfig = await FastCameraDiscoveryService.createOptimizedConfiguration(
          widget.host!,
          username: widget.username,
          password: widget.password,
        );

        // Converter Map para CameraPortConfiguration
        final config = CameraPortConfiguration(
          onvifPort: optimizedConfig['onvifPort'] ?? 80,
          httpPort: optimizedConfig['httpPort'] ?? 80,
          rtspPort: optimizedConfig['rtspPort'] ?? 554,
          proprietaryPort: optimizedConfig['proprietaryPort'] ?? 8080,
          alternativePort: optimizedConfig['alternativePort'] ?? 8000,
          useHttps: optimizedConfig['useHttps'] ?? false,
          acceptSelfSigned: optimizedConfig['acceptSelfSigned'] ?? true,
          preferredProtocol: optimizedConfig['preferredProtocol'] ?? 'auto',
        );

        _updateConfiguration(config);

        final protocols = result['supportedProtocols'] as List<String>? ?? [];
        setState(() {
          _detectionResult = 'Detecção concluída! '
              'Protocolo: ${protocols.join(", ")}. '
              'Portas configuradas automaticamente.';
        });
      } else {
        setState(() {
          _detectionResult = 'Não foi possível detectar protocolos suportados. '
              'Verifique o host e as credenciais.';
        });
      }
    } catch (e) {
      setState(() {
        _detectionResult = 'Erro na detecção automática: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isDetecting = false;
      });
    }
  }
}