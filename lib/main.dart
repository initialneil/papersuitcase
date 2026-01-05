import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/app_state.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: 'PaperSuitecase',
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const PaperSuitecaseApp());
}

class PaperSuitecaseApp extends StatelessWidget {
  const PaperSuitecaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppState()..initialize(),
      builder: (context, child) {
        return MaterialApp(
          title: 'PaperSuitecase',
          debugShowCheckedModeBanner: false,
          themeMode: context.watch<AppState>().themeMode,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          home: const _AppShell(),
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    const primaryColor = Color(0xFF007AFF); // macOS Blue
    const surfaceColor = Color(0xFFFFFFFF);
    const scaffoldColor = Color(0xFFF5F5F7); // macOS Light Gray background

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        surface: surfaceColor,
        onSurface: Colors.black,
        outline: Colors.grey.withOpacity(0.3),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: scaffoldColor,
      fontFamily: 'SF Pro Display',
      cardTheme: const CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.all(0),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.withOpacity(0.2),
        space: 1,
      ),
      // macOS style buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const primaryColor = Color(0xFF0A84FF); // macOS Dark Mode Blue
    const surfaceColor = Color(0xFF2C2C2E); // Card background
    const scaffoldColor = Color(0xFF1C1C1E); // Window background

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        surface: surfaceColor,
        onSurface: Colors.white,
        outline: Colors.white.withOpacity(0.1),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: scaffoldColor,
      fontFamily: 'SF Pro Display',
      cardTheme: const CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.all(0),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.1),
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

/// App shell with window title bar
class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Custom title bar for macOS
          _TitleBar(),

          // Main content
          const Expanded(child: MainScreen()),
        ],
      ),
    );
  }
}

/// Custom title bar widget
class _TitleBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        windowManager.startDragging();
      },
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
          ),
        ),
        child: Stack(
          children: [
            // Traffic lights spacing (left side)
            const SizedBox(width: 80),

            // Centered title
            Center(
              child: Text(
                'PaperSuitecase',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
