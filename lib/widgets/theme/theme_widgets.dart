import 'package:flutter/material.dart';
import '../../services/services.dart';
import 'package:provider/provider.dart';

// Theme Mode Selector
class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modo do Tema',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ...ThemeMode.values.map((mode) {
                  return RadioListTile<ThemeMode>(
                    title: Text(_getThemeModeLabel(mode)),
                    subtitle: Text(_getThemeModeDescription(mode)),
                    value: mode,
                    groupValue: themeService.themeMode,
                    onChanged: (value) {
                      if (value != null) {
                        themeService.setThemeMode(value);
                      }
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Sistema';
      case ThemeMode.light:
        return 'Claro';
      case ThemeMode.dark:
        return 'Escuro';
    }
  }

  String _getThemeModeDescription(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Segue a configuração do sistema';
      case ThemeMode.light:
        return 'Sempre tema claro';
      case ThemeMode.dark:
        return 'Sempre tema escuro';
    }
  }
}

// Accent Color Picker
class AccentColorPicker extends StatelessWidget {
  const AccentColorPicker({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cor de Destaque',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ThemeService.predefinedColors.map((color) {
                    final isSelected = themeService.accentColor.value == color.value;
                    return GestureDetector(
                      onTap: () => themeService.setAccentColor(color),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  width: 3,
                                )
                              : null,
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                color: color.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showCustomColorPicker(context, themeService),
                  icon: const Icon(Icons.palette),
                  label: const Text('Cor Personalizada'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCustomColorPicker(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (context) => CustomColorPickerDialog(
        initialColor: themeService.accentColor,
        onColorSelected: (color) => themeService.setAccentColor(color),
      ),
    );
  }
}

// Camera Color Manager
class CameraColorManager extends StatelessWidget {
  const CameraColorManager({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Cores das Câmeras',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      onPressed: () => _showAddCameraColorDialog(context, themeService),
                      icon: const Icon(Icons.add),
                      tooltip: 'Adicionar cor de câmera',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (themeService.cameraColors.isEmpty)
                  const Text(
                    'Nenhuma cor de câmera personalizada configurada.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  )
                else
                  ...themeService.cameraColors.entries.map((entry) {
                    return ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: entry.value,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text('Câmera ${entry.key}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _showEditCameraColorDialog(
                              context,
                              themeService,
                              entry.key,
                              entry.value,
                            ),
                            icon: const Icon(Icons.edit),
                            tooltip: 'Editar cor',
                          ),
                          IconButton(
                            onPressed: () => _confirmRemoveCameraColor(
                              context,
                              themeService,
                              entry.key,
                            ),
                            icon: const Icon(Icons.delete),
                            tooltip: 'Remover cor',
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddCameraColorDialog(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (context) => AddCameraColorDialog(
        onColorAdded: (cameraId, color) {
          themeService.setCameraColor(cameraId, color);
        },
      ),
    );
  }

  void _showEditCameraColorDialog(
    BuildContext context,
    ThemeService themeService,
    String cameraId,
    Color currentColor,
  ) {
    showDialog(
      context: context,
      builder: (context) => CustomColorPickerDialog(
        initialColor: currentColor,
        title: 'Editar Cor da Câmera $cameraId',
        onColorSelected: (color) => themeService.setCameraColor(cameraId, color),
      ),
    );
  }

  void _confirmRemoveCameraColor(
    BuildContext context,
    ThemeService themeService,
    String cameraId,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Cor da Câmera'),
        content: Text('Deseja remover a cor personalizada da câmera $cameraId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              themeService.removeCameraColor(cameraId);
              Navigator.of(context).pop();
            },
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }
}

// Custom Color Picker Dialog
class CustomColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final String title;
  final Function(Color) onColorSelected;

  const CustomColorPickerDialog({
    super.key,
    required this.initialColor,
    this.title = 'Selecionar Cor',
    required this.onColorSelected,
  });

  @override
  State<CustomColorPickerDialog> createState() => _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<CustomColorPickerDialog> {
  late Color _selectedColor;
  late double _hue;
  late double _saturation;
  late double _lightness;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    final hsl = HSLColor.fromColor(_selectedColor);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color preview
            Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: _selectedColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            // Hue slider
            _buildSlider(
              'Matiz',
              _hue,
              0,
              360,
              (value) {
                setState(() {
                  _hue = value;
                  _updateColor();
                });
              },
            ),
            // Saturation slider
            _buildSlider(
              'Saturação',
              _saturation,
              0,
              1,
              (value) {
                setState(() {
                  _saturation = value;
                  _updateColor();
                });
              },
            ),
            // Lightness slider
            _buildSlider(
              'Luminosidade',
              _lightness,
              0,
              1,
              (value) {
                setState(() {
                  _lightness = value;
                  _updateColor();
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onColorSelected(_selectedColor);
            Navigator.of(context).pop();
          },
          child: const Text('Selecionar'),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _updateColor() {
    _selectedColor = HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness).toColor();
  }
}

// Add Camera Color Dialog
class AddCameraColorDialog extends StatefulWidget {
  final Function(String, Color) onColorAdded;

  const AddCameraColorDialog({
    super.key,
    required this.onColorAdded,
  });

  @override
  State<AddCameraColorDialog> createState() => _AddCameraColorDialogState();
}

class _AddCameraColorDialogState extends State<AddCameraColorDialog> {
  final _cameraIdController = TextEditingController();
  Color _selectedColor = Colors.blue;

  @override
  void dispose() {
    _cameraIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Cor da Câmera'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _cameraIdController,
            decoration: const InputDecoration(
              labelText: 'ID da Câmera',
              hintText: 'Ex: camera_01',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Cor: '),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showColorPicker(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _selectedColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _showColorPicker,
                child: const Text('Alterar'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _canAdd() ? _addColor : null,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }

  bool _canAdd() {
    return _cameraIdController.text.trim().isNotEmpty;
  }

  void _addColor() {
    widget.onColorAdded(_cameraIdController.text.trim(), _selectedColor);
    Navigator.of(context).pop();
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => CustomColorPickerDialog(
        initialColor: _selectedColor,
        title: 'Selecionar Cor da Câmera',
        onColorSelected: (color) {
          setState(() {
            _selectedColor = color;
          });
        },
      ),
    );
  }
}

// Theme Preview Widget
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visualização do Tema',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.videocam,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Câmera Principal',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      Switch(
                        value: true,
                        onChanged: null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: null,
                          child: const Text('Gravar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: null,
                          child: const Text('Snapshot'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}