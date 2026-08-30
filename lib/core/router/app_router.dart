import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:goodloop/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:goodloop/features/friends/presentation/friends_screen.dart';
import '../../presentation/screens/welcome/welcome_screen.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../domain/providers/auth_provider.dart';

/// Wszystkie zdefiniowane ścieżki. [redirect] używa tego, by zalogowanego
/// użytkownika na nieznanej lokalizacji (`/`, `/profile`, `/feed`, literówka)
/// odesłać na `/home` zamiast pokazywać ekran błędu GoRoutera.
const _knownRoutes = {
  '/welcome',
  '/auth/login',
  '/auth/register',
  '/home',
  '/achievements',
  '/friends',
  '/settings',
};

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      // Poczekaj aż stan logowania się ustali.
      if (authState.isLoading) return null;

      final isAuthenticated = authState.valueOrNull != null;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/welcome' || loc.startsWith('/auth');

      // Niezalogowany: tylko ekrany auth, reszta → /welcome.
      if (!isAuthenticated) {
        return isAuthRoute ? null : '/welcome';
      }

      // Zalogowany na ekranie powitania/logowania → /home.
      if (isAuthRoute) return '/home';

      // Zalogowany, ale trasa nieznana → /home (zamiast GoException).
      if (!_knownRoutes.contains(loc)) return '/home';

      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/achievements',
        builder: (context, state) => const AchievementsScreen(),
      ),
      GoRoute(
        path: '/friends',
        builder: (context, state) => const FriendsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    // Siatka bezpieczeństwa — link „Home” domyślnego ekranu błędu GoRoutera
    // prowadzi do `/`, którego nie ma, i się zapętla. Tu wracamy na `/home`.
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nie znaleziono strony'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Wróć na stronę główną'),
            ),
          ],
        ),
      ),
    ),
  );
});
