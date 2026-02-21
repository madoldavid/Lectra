import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'auth/supabase_auth/supabase_user_provider.dart';
import 'auth/supabase_auth/auth_util.dart';

import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/flutter_flow_util.dart';
import '/pages/reset_password_page/reset_password_page_widget.dart';
import '/services/notification_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoRouter.optionURLReflectsImperativeAPIs = true;
  usePathUrlStrategy();

  await SupaFlow.initialize();

  await FlutterFlowTheme.initialize();

  final appState = AppStateNotifier.instance;
  await appState.initializePersistedState();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (context) => appState),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  // This widget is the root of your application.
  @override
  State<MyApp> createState() => _MyAppState();

  // ignore: library_private_types_in_public_api
  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = FlutterFlowTheme.themeMode;

  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;

  late Stream<BaseAuthUser> userStream;
  StreamSubscription<AuthState>? _passwordRecoverySubscription;

  @override
  void initState() {
    super.initState();

    _appStateNotifier = AppStateNotifier.instance;
    // Seed router state immediately to avoid loading lock before first auth stream event.
    _appStateNotifier
        .update(LectraSupabaseUser(SupaFlow.client.auth.currentUser));
    _router = createRouter(_appStateNotifier);
    userStream = lectraSupabaseUserStream()
      ..listen((user) {
        _appStateNotifier.update(user);
        NotificationSyncService.instance.handleAuthChanged();
      });
    _passwordRecoverySubscription =
        SupaFlow.client.auth.onAuthStateChange.listen((authState) {
      if (authState.event != AuthChangeEvent.passwordRecovery) {
        return;
      }
      final currentLocation = _router.getCurrentLocation();
      if (currentLocation.startsWith(ResetPasswordPageWidget.routePath)) {
        return;
      }
      _router.pushNamed(ResetPasswordPageWidget.routeName);
    });
    jwtTokenStream.listen((_) {});
    NotificationSyncService.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_appStateNotifier.showSplashImage) {
        _appStateNotifier.stopShowingSplashImage();
      }
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (_appStateNotifier.showSplashImage) {
        _appStateNotifier.stopShowingSplashImage();
      }
    });
  }

  @override
  void dispose() {
    _passwordRecoverySubscription?.cancel();
    NotificationSyncService.instance.stop();
    super.dispose();
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        _themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
      });

  String getRoute([RouteMatch? routeMatch]) {
    final RouteMatch lastMatch =
        routeMatch ?? _router.routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : _router.routerDelegate.currentConfiguration;
    return matchList.uri.toString();
  }

  List<String> getRouteStack() =>
      _router.routerDelegate.currentConfiguration.matches
          .map((e) => getRoute(e as RouteMatch))
          .toList();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Lectra',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', '')],
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: false,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: false,
      ),
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }
}
