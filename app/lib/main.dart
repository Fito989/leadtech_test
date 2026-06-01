import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/config/app_config.dart';
import 'data/repositories/chat_repository_impl.dart';
import 'domain/repositories/chat_repository.dart';
import 'features/chat/cubit/chat_cubit.dart';
import 'features/chat/view/chat_page.dart';

void main() {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.backendBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'Content-Type': 'application/json'},
  ));
  final ChatRepository repository = ChatRepositoryImpl(dio);
  runApp(CvScreenerApp(repository: repository));
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C8CFF),
    brightness: brightness,
  );
  final shadow = Colors.black.withValues(alpha: isDark ? 0.55 : 0.18);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0E1014) : scheme.surface,
    shadowColor: shadow,
    appBarTheme: AppBarTheme(
      elevation: 3,
      scrolledUnderElevation: 3,
      shadowColor: shadow,
      backgroundColor: isDark ? const Color(0xFF161A21) : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1B2027) : scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(26),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 3,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    chipTheme: ChipThemeData(
      elevation: 2,
      shadowColor: shadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

class CvScreenerApp extends StatelessWidget {
  const CvScreenerApp({super.key, required this.repository});

  final ChatRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CV Screener',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: BlocProvider(
        create: (_) => ChatCubit(repository),
        child: const ChatPage(),
      ),
    );
  }
}
