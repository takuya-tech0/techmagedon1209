// lib/features/ai_chat/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_history_drawer.dart';
import '../widgets/teacher_question_dialog.dart';
import '../models/chat_message.dart';
import '../models/chat_history.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  late final ChatService _chatService;
  bool _isLoading = false;
  bool _isFirstMessage = true;
  String _activeFilter = 'すべての履歴';
  List<ChatHistory> _conversations = [];
  ChatHistory? _currentConversation;
  bool _isLoadingHistory = false;
  String _conversationTitle = '無題の会話';
  int? _currentConversationId;

  @override
  void initState() {
    super.initState();
    _chatService = ChatService(apiKey: dotenv.env['OPENAI_API_KEY'] ?? '');
    _loadInitialMessage();
    _loadChatHistory();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialMessage() async {
    if (mounted) {
      setState(() {
        _messages.add(
          ChatMessage(
            content: '物理の学習をサポートします。\n分からないことがあれば、気軽に質問してください！',
            isUser: false,
            recommendations: _chatService.initialRecommendations,
            isFirstMessage: true,
          ),
        );
      });
    }
  }

  Future<void> _loadChatHistory() async {
    if (!mounted) return;

    setState(() {
      _isLoadingHistory = true;
    });

    try {
      final history = await _chatService.getChatHistory();
      if (!mounted) return;

      setState(() {
        _conversations = history;
        _isLoadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingHistory = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('履歴の読み込みに失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleFilterChange(String filter) {
    if (!mounted) return;
    setState(() {
      _activeFilter = filter;
    });
  }

  Future<void> _handleConversationSelect(ChatHistory conversation) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _currentConversation = conversation;
      _currentConversationId = conversation.conversationId;
      _conversationTitle = conversation.title ?? '無題の会話';
    });

    try {
      final conversationDetail = await _chatService.getConversationDetail(
        conversation.conversationId,
      );

      if (!mounted) return;

      setState(() {
        _messages.clear();
        _messages.addAll(conversationDetail.messages);
        _isFirstMessage = false;
        _isLoading = false;
        _conversationTitle = conversationDetail.conversation.title ?? '無題の会話';
      });

      await _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _messages.clear();
        _conversationTitle = '無題の会話';
      });
      await _loadInitialMessage();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('会話の読み込みに失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleTeacherQuestion() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return TeacherQuestionDialog(
          onSubmit: (question, isChat) {
            setState(() {
              _messages.add(ChatMessage(
                content: "質問を送信しました。先生からの回答をお待ちください。",
                isUser: false,
                recommendations: const [],
              ));
            });
            _scrollToBottom();
          },
        );
      },
    );
  }

  void _handleRecommendationTap(String recommendation) async {
    if (recommendation == "先生に質問する") {
      _handleTeacherQuestion();
      return;
    }

    if (recommendation == "理解できました！ありがとう！") {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          content: _chatService.getUnderstandingConfirmationMessage(),
          isUser: false,
          recommendations: _chatService.understandingConfirmationOptions,
        ));
      });
      _scrollToBottom();
      return;
    }

    if (recommendation == "「みんなの教習」に追加する！") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('「みんなの教習」に追加しました！'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (recommendation == "今回はやめとく") {
      return;
    }

    _messageController.text = recommendation;
    _sendMessage();
  }

  Future<void> _scrollToBottom() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty) return;

    final userMessage = _messageController.text;
    _messageController.clear();

    setState(() {
      _messages.add(ChatMessage(
        content: userMessage,
        isUser: true,
      ));
      _isLoading = true;
    });

    await _scrollToBottom();

    try {
      // バックエンドにメッセージを送信
      final response = await _chatService.sendUserMessage(
        userMessage,
        conversationId: _currentConversationId,
        isFirstMessage: _isFirstMessage,
      );

      if (!mounted) return;

      // 会話IDの更新
      _currentConversationId = response['conversation_id'];

      // バックエンドから返された最新の応答を表示
      setState(() {
        _messages.add(ChatMessage(
          content: response['assistant_message'],
          isUser: false,
          recommendations: _chatService.getCurrentRecommendations(
            _isFirstMessage,
            userMessage,
          ),
          isFirstMessage: _isFirstMessage,
        ));
        _isLoading = false;
      });

      // 履歴を更新
      await _loadChatHistory();
      await _scrollToBottom();

      // 初回メッセージの場合はタイトルを生成
      if (_isFirstMessage && _currentConversationId != null) {
        final title = await _chatService.generateTitle(_currentConversationId!);
        if (mounted) {
          setState(() {
            _conversationTitle = title;
            _isFirstMessage = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラーが発生しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      height: kToolbarHeight,
      color: Colors.white,
      child: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
          const Spacer(),
          Expanded(
            child: Text(
              _conversationTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChatHistory,
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty && !_isLoading) {
      return const Expanded(
        child: Center(
          child: Text('メッセージがありません'),
        ),
      );
    }

    return Expanded(
      child: Container(
        color: Colors.white,
        child: ListView.builder(
          key: const PageStorageKey('chat_list'),
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.all(16.0),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final message = _messages[_messages.length - 1 - index];
            return ChatBubble(
              key: ValueKey('message_${index}'),
              message: message,
              onRecommendationTap: _handleRecommendationTap,
            );
          },
        ),
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE4E8),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'メッセージ',
                    hintStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_upward),
                onPressed: _sendMessage,
                color: Colors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_currentConversation != null) {
          setState(() {
            _currentConversation = null;
            _messages.clear();
            _currentConversationId = null;
            _conversationTitle = '無題の会話';
            _isFirstMessage = true;
          });
          _loadInitialMessage();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        drawer: ChatHistoryDrawerContent(
          conversations: _conversations,
          onSelectConversation: _handleConversationSelect,
          onFilterChange: _handleFilterChange,
          activeFilter: _activeFilter,
          isLoading: _isLoadingHistory,
          currentConversation: _currentConversation,
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildChatList(),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
                  ),
                ),
              _buildChatInput(),
            ],
          ),
        ),
      ),
    );
  }
}