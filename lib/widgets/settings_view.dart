import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import '../providers/app_state.dart';
import '../models/settings_enums.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Settings',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),

            _SectionHeader(title: 'Appearance'),
            _SettingBox(
              child: Column(
                children: [
                  _ThemeOption(
                    title: 'Light',
                    icon: Icons.light_mode_outlined,
                    isSelected: appState.themeMode == ThemeMode.light,
                    onTap: () => appState.setThemeMode(ThemeMode.light),
                  ),
                  const Divider(height: 1),
                  _ThemeOption(
                    title: 'Dark',
                    icon: Icons.dark_mode_outlined,
                    isSelected: appState.themeMode == ThemeMode.dark,
                    onTap: () => appState.setThemeMode(ThemeMode.dark),
                  ),
                  const Divider(height: 1),
                  _ThemeOption(
                    title: 'System',
                    icon: Icons.settings_brightness_outlined,
                    isSelected: appState.themeMode == ThemeMode.system,
                    onTap: () => appState.setThemeMode(ThemeMode.system),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            _SectionHeader(title: 'PDF Viewer'),
            _SettingBox(
              child: Column(
                children: [
                  _RadioOption<PdfReaderType>(
                    title: 'Embedded Viewer',
                    subtitle: 'Open papers inside the application',
                    value: PdfReaderType.embedded,
                    groupValue: appState.pdfReaderType,
                    onChanged: (val) => appState.setPdfReaderType(val!),
                  ),
                  const Divider(height: 1),
                  _RadioOption<PdfReaderType>(
                    title: 'System Default',
                    subtitle: 'Use the default application for PDF files',
                    value: PdfReaderType.system,
                    groupValue: appState.pdfReaderType,
                    onChanged: (val) => appState.setPdfReaderType(val!),
                  ),
                  const Divider(height: 1),
                  _RadioOption<PdfReaderType>(
                    title: 'Custom Application',
                    subtitle: 'Specify a custom application to open PDFs',
                    value: PdfReaderType.custom,
                    groupValue: appState.pdfReaderType,
                    onChanged: (val) => appState.setPdfReaderType(val!),
                  ),
                  if (appState.pdfReaderType == PdfReaderType.custom) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              appState.customPdfAppPath ??
                                  'No application selected',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: appState.customPdfAppPath == null
                                        ? Theme.of(context).colorScheme.outline
                                        : null,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton(
                            onPressed: () => _pickCustomApp(context, appState),
                            child: const Text('Browse'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickCustomApp(BuildContext context, AppState appState) async {
    const XTypeGroup typeGroup = XTypeGroup(
      label: 'Applications',
      extensions: ['app', 'exe'],
    );
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[typeGroup],
    );
    if (file != null) {
      await appState.setCustomPdfAppPath(file.path);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.outline,
          letterSpacing: 1.2,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SettingBox extends StatelessWidget {
  final Widget child;
  const _SettingBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Theme.of(context).colorScheme.primary : null,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(
                Icons.check,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _RadioOption<T> extends StatelessWidget {
  final String title;
  final String subtitle;
  final T value;
  final T groupValue;
  final ValueChanged<T?> onChanged;

  const _RadioOption({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<T>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
