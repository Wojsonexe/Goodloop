import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/features/auth/providers/auth_provider.dart';

import '../data/chat_models.dart';
import '../data/chat_socket.dart';

final chatSocketProvider = Provider<ChatSocket>((ref) {
  final s = ChatSocket();
  ref.onDispose(s.dispose);
  return s;
});

/// Utrzymuje połączenie socketu wg stanu logowania + odświeża token co 50 min.
/// `ref.watch` w widgecie hostującym bottom-nav (żeby wiadomości/nieprzeczytane
/// leciały nawet poza ekranem czatu).
final chatConnectionProvider = StreamProvider<bool>((ref) {
  final socket = ref.watch(chatSocketProvider);

  ref.listen(authStateProvider, (_, next) {
    next.whenData((user) async {
      if (user == null) {
        socket.disconnect();
      } else {
        final t = await user.getIdToken();
        if (t != null) socket.connect(t);
      }
    });
  }, fireImmediately: true);

  final timer = Timer.periodic(const Duration(minutes: 50), (_) async {
    final t = await fb.FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (t != null) socket.refreshToken(t);
  });
  ref.onDispose(timer.cancel);

  return socket.connectionState;
});

/// Kto pisze w danej rozmowie (auto-czyszczone po 5 s).
final typingProvider =
    StateNotifierProvider.family<TypingNotifier, bool, String>(
  (ref, conversationId) => TypingNotifier(ref, conversationId),
);

class TypingNotifier extends StateNotifier<bool> {
  TypingNotifier(this.ref, this.conversationId) : super(false) {
    _sub = ref.read(chatSocketProvider).onTyping.listen((e) {
      if (e.conversationId != conversationId) return;
      state = e.typing;
      _clear?.cancel();
      if (e.typing) {
        _clear = Timer(const Duration(seconds: 5), () => state = false);
      }
    });
  }
  final Ref ref;
  final String conversationId;
  StreamSubscription<TypingEvent>? _sub;
  Timer? _clear;

  @override
  void dispose() {
    _sub?.cancel();
    _clear?.cancel();
    super.dispose();
  }
}
