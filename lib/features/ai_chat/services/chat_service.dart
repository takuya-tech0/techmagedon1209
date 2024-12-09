import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/chat_message.dart';
import '../models/chat_history.dart';

class ChatService {
  final String apiKey;
  static const String _baseUrl = 'http://localhost:8000';

  int? _currentConversationId;

  int? get currentConversationId => _currentConversationId;

  set currentConversationId(int? value) {
    _currentConversationId = value;
  }

  final Set<String> _unusedInitialRecommendations = {};

  ChatService({required this.apiKey}) {
    if (apiKey.isEmpty) {
      throw ArgumentError('API key cannot be empty');
    }
    _unusedInitialRecommendations.addAll(initialRecommendations);
  }

  final List<String> initialRecommendations = [
    "加速度の意味について",
    "加速度の数式について",
    "等加速度直線運動の意味について",
    "等加速度直線運動の数式について",
  ];

  final List<String> followUpRecommendations = [
    "もっと詳しく教えて",
    "先生に質問する",
    "理解できました！ありがとう！",
    "「みんなの教習」に追加する！",
    "今回はやめとく",
  ];

  final List<String> understandingConfirmationOptions = [
    "「みんなの教習」に追加する！",
    "今回はやめとく",
  ];

  String getUnderstandingConfirmationMessage() {
    return "お役に立てて光栄です！\n今回の学びを「みんなの叡智」に追加しますか？";
  }

  void markRecommendationAsUsed(String recommendation) {
    _unusedInitialRecommendations.remove(recommendation);
  }

  List<String> getCurrentRecommendations(bool isFirstMessage, String? selectedRecommendation) {
    if (isFirstMessage) {
      return initialRecommendations;
    } else {
      List<String> currentRecommendations = List.from(followUpRecommendations);

      if (selectedRecommendation != null) {
        markRecommendationAsUsed(selectedRecommendation);
      }

      final unusedRecommendations = _unusedInitialRecommendations.take(2).toList();
      currentRecommendations.insertAll(0, unusedRecommendations);

      return currentRecommendations;
    }
  }

  Future<int> createConversation(int userId, int unitId) async {
    try {
      developer.log('Creating new conversation for user $userId in unit $unitId');

      final response = await http.post(
        Uri.parse('$_baseUrl/chat/conversations'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json; charset=UTF-8',
        },
        body: utf8.encode(json.encode({
          'user_id': userId,
          'unit_id': unitId,
        })),
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = json.decode(responseBody);
        _currentConversationId = data['conversation_id'];
        developer.log('Created conversation with ID: $_currentConversationId');
        return _currentConversationId!;
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        throw Exception('Failed to create conversation: $errorBody');
      }
    } catch (e) {
      developer.log('Error creating conversation', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendUserMessage(
      String content, {
        int? conversationId,
        bool isFirstMessage = false,
      }) async {
    try {
      developer.log('Sending user message. ConversationId: $conversationId');

      final body = {
        'conversation_id': conversationId ?? 0,
        'content': content,
        'role': 'user',
        'is_first_message': isFirstMessage,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/chat/messages'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json; charset=UTF-8',
        },
        body: utf8.encode(json.encode(body)),
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = json.decode(responseBody);
        _currentConversationId = data['conversation_id'];
        return data;
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        throw Exception('Failed to send message: $errorBody');
      }
    } catch (e) {
      developer.log('Error sending user message', error: e);
      rethrow;
    }
  }

  Future<void> sendAssistantMessage(
      String content,
      int conversationId,
      ) async {
    try {
      developer.log('Sending assistant message for conversation $conversationId');

      final response = await http.post(
        Uri.parse('$_baseUrl/chat/messages'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json; charset=UTF-8',
        },
        body: utf8.encode(json.encode({
          'conversation_id': conversationId,
          'content': content,
          'role': 'assistant',
          'is_first_message': false,
        })),
      );

      if (response.statusCode != 200) {
        final errorBody = utf8.decode(response.bodyBytes);
        throw Exception('Failed to send assistant message: $errorBody');
      }
    } catch (e) {
      developer.log('Error sending assistant message', error: e);
      rethrow;
    }
  }

  Future<String> generateTitle(int conversationId) async {
    try {
      developer.log('Generating title for conversation $conversationId');

      final response = await http.post(
        Uri.parse('$_baseUrl/chat/conversations/$conversationId/title'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json; charset=UTF-8',
        },
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = json.decode(responseBody);
        final title = data['title'] as String;
        developer.log('Generated title: $title');
        return title;
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        throw Exception('Failed to generate title: $errorBody');
      }
    } catch (e) {
      developer.log('Error generating title', error: e);
      rethrow;
    }
  }

  Future<List<ChatHistory>> getChatHistory() async {
    try {
      developer.log('Fetching chat history');

      final response = await http.get(
        Uri.parse('$_baseUrl/chat/history'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json; charset=UTF-8',
        },
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final List<dynamic> data = json.decode(responseBody);
        final history = data.map((json) => ChatHistory.fromJson(json)).toList();
        developer.log('Successfully fetched ${history.length} chat histories');
        return history;
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        throw Exception('Failed to load chat history: $errorBody');
      }
    } catch (e) {
      developer.log('Error fetching chat history', error: e);
      rethrow;
    }
  }

  Future<ChatHistoryDetail> getConversationDetail(int conversationId) async {
    try {
      developer.log('Fetching conversation detail for ID: $conversationId');

      final response = await http.get(
        Uri.parse('$_baseUrl/chat/$conversationId'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json; charset=UTF-8',
        },
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = json.decode(responseBody);
        final detail = ChatHistoryDetail.fromJson(data);
        developer.log('Successfully fetched conversation detail');
        return detail;
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        throw Exception('Failed to load conversation: $errorBody');
      }
    } catch (e) {
      developer.log('Error fetching conversation detail', error: e);
      rethrow;
    }
  }
}