import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:goodloop/core/network/api_config.dart';
import 'package:goodloop/core/utils/logger.dart';

import 'chat_models.dart';

class AckException implements Exception {
  final String code;
  final String message;
  AckException(this.code, this.message);
  @override
  String toString() => message;
}

class ChatSocket {
  io.Socket? _socket;

  final _conn = StreamController<bool>.broadcast();
  final _msgNew = StreamController<ChatMessage>.broadcast();
  final _convUpd = StreamController<Conversation>.broadcast();
  final _typing = StreamController<TypingEvent>.broadcast();
  final _read = StreamController<ReadEvent>.broadcast();

  Stream<bool> get connectionState => _conn.stream;
  Stream<ChatMessage> get onMessageNew => _msgNew.stream;
  Stream<Conversation> get onConversationUpdated => _convUpd.stream;
  Stream<TypingEvent> get onTyping => _typing.stream;
  Stream<ReadEvent> get onMessageRead => _read.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String token) {
    if (_socket != null) {
      _socket!.auth = {'token': token};
      if (!_socket!.connected) _socket!.connect();
      return;
    }
    final s = io.io(
      ApiConfig.webSocketUrl, // wss://host/chat
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setAuth({'token': token})
          .build(),
    );
    _socket = s;

    s.onConnect((_) => _conn.add(true));
    s.onDisconnect((_) => _conn.add(false));
    s.onConnectError((e) {
      logger.w('chat connect error: $e');
      _conn.add(false);
    });
    s.on('connection:rejected', (d) {
      logger.w('chat rejected: $d');
      _conn.add(false);
    });

    s.on('message:new',
        (d) => _safe(_msgNew, () => ChatMessage.fromJson(_m(d))));
    s.on('conversation:updated',
        (d) => _safe(_convUpd, () => Conversation.fromJson(_m(d))));
    s.on('typing', (d) {
      final m = _m(d);
      _typing.add(TypingEvent(m['conversationId'] as String,
          m['userId'] as String, m['typing'] as bool? ?? false));
    });
    s.on('message:read', (d) {
      final m = _m(d);
      _read
          .add(ReadEvent(m['conversationId'] as String, m['userId'] as String));
    });
    s.on('error', (d) => logger.w('chat error: $d'));

    s.connect();
  }

  void refreshToken(String token) {
    _socket?.auth = {'token': token};
    _socket?.emit('auth:refresh', {'token': token});
  }

  Future<T> _ack<T>(String event, Map<String, dynamic> payload,
      T Function(dynamic) parse) async {
    await _ensureConnected();
    final s = _socket!;
    final c = Completer<T>();
    s.emitWithAck(event, payload, ack: (res) {
      if (c.isCompleted) return;
      try {
        final m = _m(res);
        if (m['ok'] == true) {
          c.complete(parse(m['data']));
        } else {
          c.completeError(AckException(m['code'] as String? ?? 'ERROR',
              m['message'] as String? ?? 'Błąd'));
        }
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future.timeout(const Duration(seconds: 15),
        onTimeout: () =>
            throw AckException('TIMEOUT', 'Serwer nie odpowiedział'));
  }

  Future<Conversation> openConversation(String recipientId) => _ack(
      'conversation:open',
      {'recipientId': recipientId},
      (d) => Conversation.fromJson(_m(d)));

  Future<List<Conversation>> listConversations() => _ack('conversation:list',
      {}, (d) => (d as List).map((e) => Conversation.fromJson(_m(e))).toList());

  Future<ChatMessage> sendMessage(
          String conversationId, String text, String clientId) =>
      _ack(
          'message:send',
          {
            'conversationId': conversationId,
            'text': text,
            'clientId': clientId
          },
          (d) => ChatMessage.fromJson(_m(d)));

  Future<void> _ensureConnected() async {
    if (_socket?.connected ?? false) return;
    if (_socket == null) {
      throw AckException('NO_CONNECTION', 'Czat nie został zainicjalizowany');
    }
    await connectionState.firstWhere((c) => c).timeout(
          const Duration(seconds: 8),
          onTimeout: () =>
              throw AckException('NO_CONNECTION', 'Brak połączenia z czatem'),
        );
  }

  Future<List<ChatMessage>> listMessages(String conversationId,
          {int limit = 50}) =>
      _ack('message:list', {'conversationId': conversationId, 'limit': limit},
          (d) => (d as List).map((e) => ChatMessage.fromJson(_m(e))).toList());

  Future<void> markRead(String conversationId) =>
      _ack('message:read', {'conversationId': conversationId}, (_) {});

  void setTyping(String conversationId, bool typing) => _socket?.emit(
      'typing:set', {'conversationId': conversationId, 'typing': typing});

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _conn.add(false);
  }

  void dispose() {
    disconnect();
    _conn.close();
    _msgNew.close();
    _convUpd.close();
    _typing.close();
    _read.close();
  }

  static Map<String, dynamic> _m(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  void _safe<T>(StreamController<T> c, T Function() build) {
    try {
      c.add(build());
    } catch (e) {
      logger.w('chat parse: $e');
    }
  }
}
