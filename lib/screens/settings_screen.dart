import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../services/notification_service.dart';
import '../models/notification_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ThemeService _themeService = ThemeService.instance;
  final NotificationService _notificationService = NotificationService.instance;
  
  bool _isDarkMode = false;
  bool _notificationsEnabled = true;
  Map<NotificationType, bool> _enabledNotificationTypes = {};
  Map<NotificationPriority, bool> _enabledNotificationPriorities = {};
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _isDarkMode = _themeService.isDarkMode;
      _notificationsEnabled = _notificationService.isEnabled;
      _enabledNotificationTypes = Map.from(_notificationService.enabledTypes);
      _enabledNotificationPriorities = Map.from(_notificationService.enabledPriorities);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Seção de Aparência
          _buildSectionHeader('Aparência'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Modo Escuro'),
                  subtitle: const Text('Ativar tema escuro'),
                  value: _isDarkMode,
                  onChanged: (value) {
                    setState(() {
                      _isDarkMode = value;
                    });
                    _themeService.setDarkMode(value);
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Seção de Notificações
          _buildSectionHeader('Notificações'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Notificações'),
                  subtitle: const Text('Ativar notificações do sistema'),
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _notificationsEnabled = value;
                    });
                    _notificationService.setEnabled(value);
                  },
                ),
                
                if (_notificationsEnabled) ..._buildNotificationSettings(),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Seção de Sistema
          _buildSectionHeader('Sistema'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('Limpar Cache'),
                  subtitle: const Text('Remove dados temporários'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showClearCacheDialog,
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Limpar Notificações'),
                  subtitle: const Text('Remove todas as notificações'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showClearNotificationsDialog,
                ),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('Sobre'),
                  subtitle: const Text('Informações do aplicativo'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showAboutDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  List<Widget> _buildNotificationSettings() {
    return [
      const Divider(),
      
      // Tipos de notificação
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tipos de Notificação',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...NotificationType.values.map((type) => CheckboxListTile(
              title: Text(_getNotificationTypeDisplayName(type)),
              value: _enabledNotificationTypes[type] ?? true,
              onChanged: (value) {
                setState(() {
                  _enabledNotificationTypes[type] = value ?? true;
                });
                _notificationService.setTypeEnabled(type, value ?? true);
              },
            )),
          ],
        ),
      ),
      
      const Divider(),
      
      // Prioridades de notificação
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prioridades de Notificação',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...NotificationPriority.values.map((priority) => CheckboxListTile(
              title: Text(_getNotificationPriorityDisplayName(priority)),
              value: _enabledNotificationPriorities[priority] ?? true,
              onChanged: (value) {
                setState(() {
                  _enabledNotificationPriorities[priority] = value ?? true;
                });
                _notificationService.setPriorityEnabled(priority, value ?? true);
              },
            )),
          ],
        ),
      ),
    ];
  }

  String _getNotificationTypeDisplayName(NotificationType type) {
    switch (type) {
      case NotificationType.motion:
        return 'Detecção de Movimento';
      case NotificationType.recording:
        return 'Gravação';
      case NotificationType.connection:
        return 'Conexão';
      case NotificationType.system:
        return 'Sistema';
      case NotificationType.alert:
        return 'Alerta';
      case NotificationType.info:
        return 'Informação';
    }
  }

  String _getNotificationPriorityDisplayName(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.low:
        return 'Baixa';
      case NotificationPriority.medium:
        return 'Média';
      case NotificationPriority.high:
        return 'Alta';
      case NotificationPriority.critical:
        return 'Crítica';
    }
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar Cache'),
        content: const Text(
          'Isso irá remover todos os dados temporários do aplicativo. '
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              // Implementar limpeza de cache
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cache limpo com sucesso'),
                ),
              );
            },
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  void _showClearNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar Notificações'),
        content: const Text(
          'Isso irá remover todas as notificações. '
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              _notificationService.clearAll();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notificações removidas com sucesso'),
                ),
              );
            },
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Sistema de Câmeras',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(
        Icons.security,
        size: 48,
      ),
      children: [
        const Text(
          'Sistema completo de monitoramento por câmeras de segurança '
          'com controle PTZ, detecção de movimento e gravação.',
        ),
      ],
    );
  }
}