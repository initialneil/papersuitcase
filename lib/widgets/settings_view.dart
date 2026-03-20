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

            _SectionHeader(title: 'Account'),
            _SettingBox(
              child: appState.isLoggedIn
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Account info
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor:
                                    Theme.of(context).colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.person,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      appState.currentUser?.email ?? 'Unknown',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: appState.userTier == 'pro'
                                            ? Colors.amber.withValues(alpha: 0.2)
                                            : Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        appState.userTier.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: appState.userTier == 'pro'
                                              ? Colors.amber.shade800
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .outline,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Chat usage
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.chat_outlined,
                                size: 20,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${appState.llmCallsThisMonth} / ${appState.llmCallsLimit} calls this month',
                              ),
                              const Spacer(),
                              SizedBox(
                                width: 100,
                                child: LinearProgressIndicator(
                                  value: appState.llmCallsLimit > 0
                                      ? (appState.llmCallsThisMonth /
                                              appState.llmCallsLimit)
                                          .clamp(0.0, 1.0)
                                      : 0,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Sync status
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.sync,
                                size: 20,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                appState.lastSyncedAt != null
                                    ? 'Last synced: ${_formatSyncTime(appState.lastSyncedAt!)}'
                                    : 'Not synced yet',
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: appState.isSyncing
                                    ? null
                                    : () => appState.triggerSync(),
                                child: Text(
                                  appState.isSyncing
                                      ? 'Syncing...'
                                      : 'Sync now',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (appState.isSyncing && appState.syncProgress.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appState.syncProgress,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (appState.syncTotal > 0) ...[
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: appState.syncCurrent / appState.syncTotal,
                                  ),
                                ],
                                const SizedBox(height: 4),
                              ],
                            ),
                          ),
                        const Divider(height: 1),
                        // Sign out
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => appState.signOut(),
                              icon: const Icon(Icons.logout, size: 18),
                              label: const Text('Sign out'),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 32,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Not signed in',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Sign in to sync, get recommendations, and chat with papers',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton(
                            onPressed: () => appState.resetSkipAuth(),
                            child: const Text('Sign in'),
                          ),
                        ],
                      ),
                    ),
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

  String _formatSyncTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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
