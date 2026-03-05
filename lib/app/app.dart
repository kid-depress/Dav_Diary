import 'package:diary/app/app_state.dart';
import 'package:diary/data/database/app_database.dart';
import 'package:diary/data/repositories/diary_repository.dart';
import 'package:diary/data/repositories/settings_repository.dart';
import 'package:diary/services/sync_service.dart';
import 'package:diary/ui/home/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

class DiaryAppBootstrap extends StatefulWidget {
  const DiaryAppBootstrap({super.key});

  @override
  State<DiaryAppBootstrap> createState() => _DiaryAppBootstrapState();
}

class _DiaryAppBootstrapState extends State<DiaryAppBootstrap> {
  late final DiaryAppState _appState;
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    final diaryRepository = DiaryRepository(AppDatabase.instance);
    final settingsRepository = SettingsRepository();
    final syncService = SyncService(diaryRepository, settingsRepository);
    _appState = DiaryAppState(
      diaryRepository: diaryRepository,
      settingsRepository: settingsRepository,
      syncService: syncService,
    );
    _initFuture = _appState.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        return ChangeNotifierProvider<DiaryAppState>.value(
          value: _appState,
          child: Consumer<DiaryAppState>(
            builder: (context, appState, _) {
              return MaterialApp(
                title: '日记',
                debugShowCheckedModeBanner: false,
                locale: const Locale('zh', 'CN'),
                supportedLocales: const [
                  Locale('zh', 'CN'),
                  Locale('en', 'US'),
                ],
                themeMode: appState.themeMode,
                theme: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF1A936F),
                  ),
                ),
                darkTheme: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF1A936F),
                    brightness: Brightness.dark,
                  ),
                ),
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  FlutterQuillLocalizations.delegate,
                ],
                home: const HomeShell(),
              );
            },
          ),
        );
      },
    );
  }
}
