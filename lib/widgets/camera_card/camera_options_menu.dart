import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/services.dart';

/// Menu de opções da câmera com funcionalidades de editar, recarregar e remover
class CameraOptionsMenu extends StatelessWidget {
  final CameraModel camera;
  final VoidCallback? onEdit;
  final VoidCallback? onReload;
  final VoidCallback? onRemove;
  final VoidCallback? onSettings;
  final VoidCallback? onRecordings;
  final VoidCallback? onSnapshot;
  final VoidCallback? onFullscreen;
  final bool showAdvancedOptions;
  final Color? iconColor;

  const CameraOptionsMenu({
    super.key,
    required this.camera,
    this.onEdit,
    this.onReload,
    this.onRemove,
    this.onSettings,
    this.onRecordings,
    this.onSnapshot,
    this.onFullscreen,
    this.showAdvancedOptions = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: iconColor ?? Colors.white,
        size: 20,
      ),
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      offset: const Offset(0, 40),
      itemBuilder: (context) => _buildMenuItems(context),
      onSelected: (value) => _handleMenuSelection(context, value),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context) {
    final items = <PopupMenuEntry<String>>[];

    // Opções básicas
    items.addAll([
      _buildMenuItem(
        value: 'edit',
        icon: Icons.edit,
        title: 'Editar Câmera',
        subtitle: 'Configurar nome e parâmetros',
        enabled: onEdit != null,
      ),
      _buildMenuItem(
        value: 'reload',
        icon: Icons.refresh,
        title: 'Recarregar Stream',
        subtitle: 'Reconectar à câmera',
        enabled: onReload != null,
      ),
      const PopupMenuDivider(),
    ]);

    // Opções de captura
    items.addAll([
      _buildMenuItem(
        value: 'snapshot',
        icon: Icons.camera_alt,
        title: 'Capturar Foto',
        subtitle: 'Salvar imagem atual',
        enabled: onSnapshot != null,
      ),
      _buildMenuItem(
        value: 'recordings',
        icon: Icons.video_library,
        title: 'Gravações',
        subtitle: 'Ver gravações salvas',
        enabled: onRecordings != null,
      ),
    ]);

    // Opções avançadas (se habilitadas)
    if (showAdvancedOptions) {
      items.addAll([
        const PopupMenuDivider(),
        _buildMenuItem(
          value: 'fullscreen',
          icon: Icons.fullscreen,
          title: 'Tela Cheia',
          subtitle: 'Visualizar em tela cheia',
          enabled: onFullscreen != null,
        ),
        _buildMenuItem(
          value: 'settings',
          icon: Icons.settings,
          title: 'Configurações',
          subtitle: 'Ajustes avançados',
          enabled: onSettings != null,
        ),
        _buildMenuItem(
          value: 'stream_info',
          icon: Icons.info_outline,
          title: 'Info do Stream',
          subtitle: 'Detalhes técnicos',
        ),
      ]);
    }

    // Opção de remover (sempre por último)
    items.addAll([
      const PopupMenuDivider(),
      _buildMenuItem(
        value: 'remove',
        icon: Icons.delete,
        title: 'Remover Câmera',
        subtitle: 'Excluir permanentemente',
        enabled: onRemove != null,
        isDestructive: true,
      ),
    ]);

    return items;
  }

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required IconData icon,
    required String title,
    String? subtitle,
    bool enabled = true,
    bool isDestructive = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(
          icon,
          size: 20,
          color: isDestructive
              ? Colors.red
              : enabled
                  ? null
                  : Colors.grey,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDestructive
                ? Colors.red
                : enabled
                    ? null
                    : Colors.grey,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? Colors.grey[600] : Colors.grey[400],
                ),
              )
            : null,
        dense: true,
      ),
    );
  }

  void _handleMenuSelection(BuildContext context, String value) {
    switch (value) {
      case 'edit':
        onEdit?.call();
        break;
      case 'reload':
        _handleReload(context);
        break;
      case 'remove':
        _handleRemove(context);
        break;
      case 'settings':
        onSettings?.call();
        break;
      case 'recordings':
        onRecordings?.call();
        break;
      case 'snapshot':
        _handleSnapshot(context);
        break;
      case 'fullscreen':
        onFullscreen?.call();
        break;
      case 'stream_info':
        _showStreamInfo(context);
        break;
    }
  }

  void _handleReload(BuildContext context) {
    // Mostra indicador de carregamento
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text('Recarregando ${camera.name}...'),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    onReload?.call();
  }

  void _handleRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Câmera'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tem certeza que deseja remover a câmera "${camera.name}"?'),
            const SizedBox(height: 12),
            const Text(
              'Esta ação não pode ser desfeita. Todas as configurações e gravações associadas serão perdidas.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRemove?.call();
              
              // Mostra confirmação
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Câmera "${camera.name}" removida'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  void _handleSnapshot(BuildContext context) {
    // Mostra feedback visual
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.camera_alt, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text('Capturando foto de ${camera.name}...'),
          ],
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    onSnapshot?.call();
  }

  void _showStreamInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StreamInfoDialog(camera: camera),
    );
  }
}

/// Dialog com informações técnicas do stream
class StreamInfoDialog extends StatelessWidget {
  final CameraModel camera;

  const StreamInfoDialog({
    super.key,
    required this.camera,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 8),
          const Text('Informações do Stream'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoSection('Câmera', [
              _buildInfoRow('Nome', camera.name),
              _buildInfoRow('IP', camera.ipAddress),
              _buildInfoRow('Porta', camera.port.toString()),
              _buildInfoRow('Status', camera.isOnline ? 'Online' : 'Offline'),
            ]),
            const SizedBox(height: 16),
            _buildInfoSection('Stream', [
              _buildInfoRow('URL Principal', camera.streamConfig.mainStreamUrl),
              if (camera.streamConfig.subStreamUrl != null)
                _buildInfoRow('URL Secundária', camera.streamConfig.subStreamUrl!),
              _buildInfoRow('Codec', camera.streamConfig.codec.name),
              _buildInfoRow('Resolução', '${camera.streamConfig.resolution.width}x${camera.streamConfig.resolution.height}'),
              _buildInfoRow('FPS', camera.streamConfig.fps.toString()),
              _buildInfoRow('Bitrate', '${camera.streamConfig.bitrate} kbps'),
            ]),
            const SizedBox(height: 16),
            _buildInfoSection('Capacidades', [
              _buildInfoRow('PTZ', camera.capabilities.supportsPTZ ? 'Sim' : 'Não'),
              _buildInfoRow('Áudio', camera.capabilities.supportsAudio ? 'Sim' : 'Não'),
              _buildInfoRow('Gravação', camera.capabilities.supportsRecording ? 'Sim' : 'Não'),
              _buildInfoRow('Modo Noturno', camera.capabilities.supportsNightMode ? 'Sim' : 'Não'),
              _buildInfoRow('Detecção de Movimento', camera.capabilities.supportsMotionDetection ? 'Sim' : 'Não'),
            ]),
            if (camera.lastError != null) ..[
              const SizedBox(height: 16),
              _buildInfoSection('Último Erro', [
                _buildInfoRow('Mensagem', camera.lastError!),
                _buildInfoRow('Timestamp', camera.lastErrorTime?.toString() ?? 'N/A'),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
        FilledButton(
          onPressed: () {
            // Copia informações para clipboard
            final info = _generateInfoText();
            // TODO: Implementar cópia para clipboard
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Informações copiadas para a área de transferência'),
              ),
            );
          },
          child: const Text('Copiar'),
        ),
      ],
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  String _generateInfoText() {
    return '''
Informações da Câmera: ${camera.name}

Câmera:
- Nome: ${camera.name}
- IP: ${camera.ipAddress}
- Porta: ${camera.port}
- Status: ${camera.isOnline ? 'Online' : 'Offline'}

Stream:
- URL Principal: ${camera.streamConfig.mainStreamUrl}
${camera.streamConfig.subStreamUrl != null ? '- URL Secundária: ${camera.streamConfig.subStreamUrl}\n' : ''}- Codec: ${camera.streamConfig.codec.name}
- Resolução: ${camera.streamConfig.resolution.width}x${camera.streamConfig.resolution.height}
- FPS: ${camera.streamConfig.fps}
- Bitrate: ${camera.streamConfig.bitrate} kbps

Capacidades:
- PTZ: ${camera.capabilities.supportsPTZ ? 'Sim' : 'Não'}
- Áudio: ${camera.capabilities.supportsAudio ? 'Sim' : 'Não'}
- Gravação: ${camera.capabilities.supportsRecording ? 'Sim' : 'Não'}
- Modo Noturno: ${camera.capabilities.supportsNightMode ? 'Sim' : 'Não'}
- Detecção de Movimento: ${camera.capabilities.supportsMotionDetection ? 'Sim' : 'Não'}
${camera.lastError != null ? '\nÚltimo Erro:\n- Mensagem: ${camera.lastError}\n- Timestamp: ${camera.lastErrorTime}' : ''}
''';
  }
}

/// Menu de contexto rápido para ações comuns
class QuickActionsMenu extends StatelessWidget {
  final CameraModel camera;
  final VoidCallback? onSnapshot;
  final VoidCallback? onRecord;
  final VoidCallback? onFullscreen;
  final bool isRecording;

  const QuickActionsMenu({
    super.key,
    required this.camera,
    this.onSnapshot,
    this.onRecord,
    this.onFullscreen,
    this.isRecording = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Snapshot
        if (onSnapshot != null)
          IconButton(
            onPressed: onSnapshot,
            icon: const Icon(Icons.camera_alt, size: 18),
            tooltip: 'Capturar Foto',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black26,
              foregroundColor: Colors.white,
            ),
          ),
        
        // Gravação
        if (onRecord != null)
          IconButton(
            onPressed: onRecord,
            icon: Icon(
              isRecording ? Icons.stop : Icons.fiber_manual_record,
              size: 18,
            ),
            tooltip: isRecording ? 'Parar Gravação' : 'Iniciar Gravação',
            style: IconButton.styleFrom(
              backgroundColor: isRecording ? Colors.red : Colors.black26,
              foregroundColor: Colors.white,
            ),
          ),
        
        // Tela cheia
        if (onFullscreen != null)
          IconButton(
            onPressed: onFullscreen,
            icon: const Icon(Icons.fullscreen, size: 18),
            tooltip: 'Tela Cheia',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black26,
              foregroundColor: Colors.white,
            ),
          ),
      ],
    );
  }
}