import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

class SettingsState {
  final ThemeMode themeMode;
  final int jpegQuality;
  final bool saveOriginal;
  final String exportFormat;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.jpegQuality = 90,
    this.saveOriginal = true,
    this.exportFormat = 'jpeg',
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    int? jpegQuality,
    bool? saveOriginal,
    String? exportFormat,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      jpegQuality: jpegQuality ?? this.jpegQuality,
      saveOriginal: saveOriginal ?? this.saveOriginal,
      exportFormat: exportFormat ?? this.exportFormat,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());
  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);
  void setJpegQuality(int q) => state = state.copyWith(jpegQuality: q);
  void setSaveOriginal(bool v) => state = state.copyWith(saveOriginal: v);
  void setExportFormat(String f) => state = state.copyWith(exportFormat: f);
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
    (ref) => SettingsNotifier());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(label: 'Appearance'),
          _SettingTile(
            icon: Icons.dark_mode_outlined,
            title: 'Theme',
            subtitle: _themeName(settings.themeMode),
            onTap: () => _showThemePicker(context, notifier, settings.themeMode),
          ),
          _SectionHeader(label: 'Export'),
          _SettingTile(
            icon: Icons.image_outlined,
            title: 'Export format',
            subtitle: settings.exportFormat.toUpperCase(),
            onTap: () => _showFormatPicker(context, notifier, settings.exportFormat),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.high_quality_outlined, size: 22, color: Colors.grey),
                    const SizedBox(width: 16),
                    const Expanded(child: Text('JPEG Quality', style: TextStyle(fontSize: 15))),
                    Text('${settings.jpegQuality}%',
                        style: const TextStyle(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
                Slider(
                  value: settings.jpegQuality.toDouble(),
                  min: 50, max: 100, divisions: 10,
                  activeColor: AppTheme.primary,
                  onChanged: settings.exportFormat == 'jpeg'
                      ? (v) => notifier.setJpegQuality(v.round()) : null,
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.save_outlined),
            title: const Text('Keep original photo'),
            subtitle: const Text('Save edited copy alongside original'),
            value: settings.saveOriginal,
            activeColor: AppTheme.primary,
            onChanged: notifier.setSaveOriginal,
          ),
          _SectionHeader(label: 'Privacy'),
          _InfoTile(icon: Icons.wifi_off_outlined, title: 'No internet access', subtitle: 'This app never connects to the internet', iconColor: Colors.green),
          _InfoTile(icon: Icons.person_off_outlined, title: 'No account required', subtitle: 'Open and edit instantly — no login ever', iconColor: Colors.green),
          _InfoTile(icon: Icons.cloud_off_outlined, title: 'No cloud uploads', subtitle: 'All your photos stay on your device only', iconColor: Colors.green),
          _InfoTile(icon: Icons.analytics_outlined, title: 'No tracking or analytics', subtitle: 'Zero data is collected or shared', iconColor: Colors.green),
          _SectionHeader(label: 'About'),
          _SettingTile(icon: Icons.info_outlined, title: 'Version', subtitle: '1.0.0 — Phase 1', onTap: null),
          _SettingTile(icon: Icons.gavel_outlined, title: 'Open source licences', onTap: () => showLicensePage(context: context)),
          _SettingTile(icon: Icons.star_outline_rounded, title: 'Rate on Play Store', subtitle: 'Enjoying PixelVault? Leave us a review!', onTap: () {}),
          const SizedBox(height: 32),
          const Center(
            child: Text('PixelVault — Free. Offline. Private. Forever.',
                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _themeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system: return 'Follow system';
      case ThemeMode.light: return 'Light';
      case ThemeMode.dark: return 'Dark';
    }
  }

  void _showThemePicker(BuildContext context, SettingsNotifier notifier, ThemeMode current) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Choose theme', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ...ThemeMode.values.map((mode) => ListTile(
            leading: Icon(mode == ThemeMode.dark ? Icons.dark_mode : mode == ThemeMode.light ? Icons.light_mode : Icons.brightness_auto),
            title: Text(_themeName(mode)),
            trailing: mode == current ? const Icon(Icons.check, color: AppTheme.primary) : null,
            onTap: () { notifier.setThemeMode(mode); Navigator.pop(context); },
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showFormatPicker(BuildContext context, SettingsNotifier notifier, String current) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Export format', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ListTile(
            leading: const Icon(Icons.image_outlined), title: const Text('JPEG'),
            subtitle: const Text('Smaller file size, adjustable quality'),
            trailing: current == 'jpeg' ? const Icon(Icons.check, color: AppTheme.primary) : null,
            onTap: () { notifier.setExportFormat('jpeg'); Navigator.pop(context); },
          ),
          ListTile(
            leading: const Icon(Icons.image), title: const Text('PNG'),
            subtitle: const Text('Lossless quality, larger file size'),
            trailing: current == 'png' ? const Icon(Icons.check, color: AppTheme.primary) : null,
            onTap: () { notifier.setExportFormat('png'); Navigator.pop(context); },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(label.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary, letterSpacing: 0.8)),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  const _SettingTile({required this.icon, required this.title, this.subtitle, this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey.shade600),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 12)) : null,
      trailing: onTap != null ? const Icon(Icons.chevron_right, color: Colors.grey) : null,
      onTap: onTap,
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  const _InfoTile({required this.icon, required this.title, required this.subtitle, required this.iconColor});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    );
  }
}
