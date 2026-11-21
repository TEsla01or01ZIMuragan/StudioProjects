import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nanny_crows_guide/core/auth_flow.dart';
import 'package:nanny_crows_guide/features/auth/presentation/auth_screens.dart';
import 'package:nanny_crows_guide/features/home/presentation/home_screen.dart';

final _authRefresh = _AuthRefreshListenable();

final _router = GoRouter(
  refreshListenable: _authRefresh,
  initialLocation: '/home',
  redirect: (context, state) {
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final isLogin = state.matchedLocation == '/login';
    if (isLogin && AuthFlow.registrationPending) return null;
    if (!signedIn && !isLogin) return '/login';
    if (signedIn && isLogin) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
  ],
);

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable() {
    _subscription = FirebaseAuth.instance.authStateChanges().listen(
      (_) => notifyListeners(),
    );
  }

  late final StreamSubscription<User?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF4768D8);
    return MaterialApp.router(
      title: 'Nanny Crows',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      routerConfig: _router,
    );
  }
}
