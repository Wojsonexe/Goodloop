import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:goodloop/features/achievements/presentation/achievements_screen.dart';
import 'package:goodloop/features/chat/presentation/chat_screen.dart';
import 'package:goodloop/features/chat/presentation/conversations_screen.dart';
import 'package:goodloop/features/friends/presentation/friends_screen.dart';
import 'package:goodloop/features/auth/presentation/welcome_screen.dart';
import 'package:goodloop/features/auth/presentation/login_screen.dart';
import 'package:goodloop/features/auth/presentation/register_screen.dart';
import 'package:goodloop/features/home/presentation/home_screen.dart';
import 'package:goodloop/features/profile/presentation/screens/profile_screen.dart';
import 'package:goodloop/features/settings/presentation/settings_screen.dart';
import 'package:goodloop/features/auth/providers/auth_provider.dart';

/// Wszystkie zdefiniowane ścieżki. [redirect] używa tego, by zalogowanego
/// użytkownika na nieznanej lokalizacji (`/`, `/feed`, literówka) odesłać
/// na `/home` zamiast pokazywać ekran błędu GoRoutera.
const _knownRoutes = {
  '/welcome',
  '/auth/login',
  '/auth/register',
  '/home',
  '/achievements',
  '/friends',
  '/profile',
  '/settings',
  '/chat',
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
      // w redirect, zamiast samego contains:
      if (!_knownRoutes.contains(loc) && !loc.startsWith('/chat/')) {
        return '/home';
      }

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
          path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(path: '/chat', builder: (c, s) => const ConversationsScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (c, s) => ChatScreen(conversationId: s.pathParameters['id']!),
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
