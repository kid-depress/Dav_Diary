import 'package:diary/app/app_state.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _remoteDirController = TextEditingController();

  bool _loaded = false;
  bool _obscurePassword = true;
  ConflictStrategy _conflictStrategy = ConflictStrategy.lastWriteWins;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    final appState = context.read<DiaryAppState>();
    final config = appState.webDavConfig;
    _urlController.text = config.serverUrl;
    _userController.text = config.username;
    _passwordController.text = config.password;
    _remoteDirController.text = config.remoteDir;
    _conflictStrategy = config.conflictStrategy;
    _loaded = true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _remoteDirController.dispose();
    super.dispose();
  }

  Future<bool> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return false;
    }
    final appState = context.read<DiaryAppState>();
    final messenger = ScaffoldMessenger.of(context);
    final config = WebDavConfig(
      serverUrl: _urlController.text.trim(),
      username: _userController.text.trim(),
      password: _passwordController.text.trim(),
      remoteDir: _remoteDirController.text.trim().isEmpty
          ? '/diary'
          : _remoteDirController.text.trim(),
      conflictStrategy: _conflictStrategy,
    );
    await appState.updateWebDavConfig(config);
    if (!mounted) {
      return false;
    }
    messenger.showSnackBar(const SnackBar(content: Text('配置已保存')));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DiaryAppState>(
      builder: (context, appState, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            Text('外观', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {appState.themeMode},
              onSelectionChanged: (selection) {
                appState.setThemeMode(selection.first);
              },
            ),
            const SizedBox(height: 20),
            Text('WebDAV', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'https://dav.example.com',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? '必填'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _userController,
                    decoration: const InputDecoration(labelText: '用户名'),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? '必填'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? '必填'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _remoteDirController,
                    decoration: const InputDecoration(labelText: '远端目录'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ConflictStrategy>(
                    initialValue: _conflictStrategy,
                    decoration: const InputDecoration(labelText: '冲突策略'),
                    items: const [
                      DropdownMenuItem(
                        value: ConflictStrategy.lastWriteWins,
                        child: Text('最后修改者优先'),
                      ),
                      DropdownMenuItem(
                        value: ConflictStrategy.keepBoth,
                        child: Text('保留两个副本'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _conflictStrategy = value);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (appState.lastSyncAt != null)
              Text(
                '上次同步：${DateFormat('yyyy-MM-dd HH:mm').format(appState.lastSyncAt!)}',
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _saveConfig,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
                OutlinedButton.icon(
                  onPressed: appState.syncing
                      ? null
                      : () async {
                          final okToContinue = await _saveConfig();
                          if (!okToContinue || !context.mounted) {
                            return;
                          }
                          try {
                            final ok = await appState.testWebDavConnection();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok ? '连接成功' : '连接失败',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('连接失败：$e')),
                            );
                          }
                        },
                  icon: const Icon(Icons.network_check_outlined),
                  label: const Text('测试连接'),
                ),
                FilledButton.tonalIcon(
                  onPressed: appState.syncing
                      ? null
                      : () async {
                          final okToContinue = await _saveConfig();
                          if (!okToContinue || !context.mounted) {
                            return;
                          }
                          final result = await appState.syncNow();
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${result.message} 上传:${result.uploaded} 下载:${result.downloaded} 冲突:${result.conflicts}',
                              ),
                            ),
                          );
                        },
                  icon: appState.syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(appState.syncing ? '同步中...' : '立即同步'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
