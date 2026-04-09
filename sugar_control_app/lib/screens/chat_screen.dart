import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'camera_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _scrollCtrl = ScrollController();
  final _textCtrl = TextEditingController();
  bool _hasText = false;

  // pending image attachment
  Uint8List? _pendingImageBytes;

  // track last auto-recorded id for correction support
  int? _lastRecordId;

  // ids of messages whose record prompt has been dismissed
  final _dismissedRecordIds = <String>{};

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() {
      final has = _textCtrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _messages.add(ChatMessage(
      id: 'welcome',
      role: MessageRole.assistant,
      text: '👋你好呀!\n'
          '我是你的控糖小助手Cici😊\n'
          '奶茶、甜品、糖果别想"偷袭"你~\n'
          '拍照识糖、自动记录、超标提醒，守护你的健康每一天!\n\n'
          '说「记录+食物名」可以记录摄入哦！输入准确的食物名和规格，结果更精准~',
      state: MessageState.done,
    ));
  }

  // ── image helpers ─────────────────────────────────────────────────

  /// Compress raw bytes to 720p and store as pending attachment.
  Future<void> _setCompressedImage(Uint8List raw) async {
    final compressed = await FlutterImageCompress.compressWithList(
      raw,
      minWidth: 720,
      minHeight: 720,
      quality: 85,
    );
    if (!mounted) return;
    setState(() {
      _pendingImageBytes = compressed;
    });
  }

  Future<void> _openCamera() async {
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraScreen(),
        fullscreenDialog: true,
      ),
    );
    if (bytes == null || !mounted) return;
    setState(() {
      _pendingImageBytes = bytes; // already compressed in PhotoPreviewScreen
    });
  }

  Future<void> _pickGalleryImage() async {
    final xfile =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    final raw = await File(xfile.path).readAsBytes();
    await _setCompressedImage(raw);
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('拍照识别'),
              onTap: () {
                Navigator.pop(context);
                _openCamera();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                _pickGalleryImage();
              },
            ),
            ListTile(
              title: const Text('取消',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  // ── send ──────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _pendingImageBytes == null) return;

    final userMsg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.user,
      text: text,
      imageBytes: _pendingImageBytes,
    );

    final loadingId = '${userMsg.id}_loading';
    final loadingMsg = ChatMessage(
      id: loadingId,
      role: MessageRole.assistant,
      text: '思考中...',
      state: MessageState.loading,
    );

    final imageBytes = _pendingImageBytes;

    setState(() {
      _messages.add(userMsg);
      _messages.add(loadingMsg);
      _textCtrl.clear();
      _pendingImageBytes = null;
    });
    _scrollToBottom();

    // build history: last 10 completed messages (5 rounds) excluding the new one
    const maxHistory = 10;
    final history = _messages
        .where((m) => m.state == MessageState.done && m.text.isNotEmpty)
        .map((m) => {
              'role': m.role == MessageRole.user ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList()
        .reversed
        .take(maxHistory)
        .toList()
        .reversed
        .toList();

    try {
      final result = await ApiService.chat(
        message: text.isEmpty ? '请识别图中食物' : text,
        imageBytes: imageBytes,
        history: history,
        lastRecordId: _lastRecordId,
      );

      final reply = result['reply'] as String? ?? '（无回复）';
      final foodInfo = result['food_info'] as Map<String, dynamic>?;
      final newRecordId = result['record_id'] as int?;
      if (newRecordId != null) _lastRecordId = newRecordId;

      setState(() {
        final idx = _messages.indexWhere((m) => m.id == loadingId);
        if (idx != -1) {
          _messages[idx] = ChatMessage(
            id: loadingId,
            role: MessageRole.assistant,
            text: reply,
            state: MessageState.done,
            foodInfo: foodInfo,
          );
        }
      });

      // Show over-limit alert if agent auto-recorded and exceeded daily limit
      if ((result['is_over_limit'] as bool?) == true && mounted) {
        _showOverLimitDialog(result);
      }

      // Guard: detect hallucinated recording — model said "已记录" but didn't call the tool
      final bool actuallyRecorded = result['recorded'] == true;
      final bool claimsRecorded = reply.contains('已记录') || reply.contains('✅');
      if (claimsRecorded && !actuallyRecorded && mounted) {
        _showSnack('⚠️ 记录可能未写入，请在摄入统计中确认，或重新发送"记录"');
      }
    } catch (e) {
      final String errMsg;
      if (e is TimeoutException) {
        errMsg = '⏱ 网络不佳，请稍后重试';
      } else if (e is SocketException) {
        errMsg = '🔌 无法连接到服务器，请确保后端已启动';
      } else {
        errMsg = '请求失败，请检查网络或后端服务';
      }
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == loadingId);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(
            text: errMsg,
            state: MessageState.done,
          );
        }
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── record action ─────────────────────────────────────────────────

  Future<void> _handleRecord(ChatMessage msg) async {
    final info = msg.foodInfo;
    if (info == null) {
      _showSnack('没有食物数据可记录');
      return;
    }
    try {
      final result = await ApiService.record(
        foodName: info['name'] as String? ?? '未知食物',
        sugarG: (info['sugar_g'] as num?)?.toDouble() ?? 0,
        calories: (info['calories'] as num?)?.toDouble(),
        category: info['category'] as String? ?? '其他',
        servingSize: info['serving_size'] as String?,
      );
      _showSnack('✅ 已记录摄入');
      if ((result['is_over_limit'] as bool?) == true && mounted) {
        _showOverLimitDialog(result);
      }
    } catch (e) {
      _showSnack('记录失败：$e');
    }
  }

  void _showOverLimitDialog(Map<String, dynamic> result) {
    final double total = (result['daily_total'] as num?)?.toDouble() ?? 0;
    final double limit = (result['limit'] as num?)?.toDouble() ?? 50;
    final double over = (result['over_amount'] as num?)?.toDouble() ?? 0;
    final String level = result['warning_level'] as String? ?? '轻度';

    final Color bgColor;
    final String advice;
    final bool bold;
    switch (level) {
      case '重度':
        bgColor = const Color(0xFFFFEBEE);
        advice = '立即停止高糖摄入，注意血糖风险！';
        bold = true;
      case '中度':
        bgColor = const Color(0xFFFFF3E0);
        advice = '继续食用将严重影响控糖目标';
        bold = false;
      default:
        bgColor = const Color(0xFFFFFDE7);
        advice = '建议减少高糖食物摄入';
        bold = false;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bgColor,
        title: const Text('⚠️ 糖分超标提醒',
            style: TextStyle(fontWeight: FontWeight.bold)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Text(
          '您今日糖分摄入已达${total.toStringAsFixed(1)}g，'
          '超过建议阈值${limit.toStringAsFixed(0)}g（超标${over.toStringAsFixed(1)}g）。'
          '$advice',
          style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  void _handleDismiss(String msgId) {
    setState(() => _dismissedRecordIds.add(msgId));
    _showSnack('好的，不记录啦 😊');
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  // ── build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cici',
            style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFEDEDED),
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFFEDEDED),
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/chat_bg.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyHint()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _MessageBubble(
                        message: _messages[i],
                        onRecord: () => _handleRecord(_messages[i]),
                        onDismiss: () => _handleDismiss(_messages[i].id),
                        recordDismissed: _dismissedRecordIds.contains(_messages[i].id),
                      ),
                    ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 64, color: AppColors.primary.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          const Text('向控糖小助手提问吧 🍵',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          const Text('例如："一杯珍珠奶茶含多少糖？"',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // image preview strip
          if (_pendingImageBytes != null)
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_pendingImageBytes!,
                        height: 72, width: 72, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  const Text('图片已选择，可附加文字发送',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _pendingImageBytes = null;
                    }),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.92),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_camera_outlined),
                  color: AppColors.primary,
                  onPressed: _showImageSourceSheet,
                  tooltip: '拍照/相册',
                ),
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    decoration: InputDecoration(
                      hintText: '输入食物名称或描述...',
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: IconButton(
                    icon: const Icon(Icons.send),
                    color: (_hasText || _pendingImageBytes != null)
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    onPressed: (_hasText || _pendingImageBytes != null) ? _send : null,
                    tooltip: '发送',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}

// ── Message Bubble ────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onRecord;
  final VoidCallback onDismiss;
  final bool recordDismissed;

  const _MessageBubble({
    required this.message,
    required this.onRecord,
    required this.onDismiss,
    this.recordDismissed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: isUser
            ? [_userBubble()]
            : [_avatarIcon(), const SizedBox(width: 8), _aiBubble()],
      ),
    );
  }

  Widget _avatarIcon() {
    return CircleAvatar(
      radius: 16,
      backgroundImage: const AssetImage('assets/images/agent_avatar.png'),
    );
  }

  Widget _userBubble() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (message.imageBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(message.imageBytes!,
                width: 180, fit: BoxFit.cover),
          ),
        if (message.text.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxWidth: 260),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.82),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Text(message.text,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
      ],
    );
  }

  Widget _aiBubble() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.90),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: message.state == MessageState.loading
              ? _LoadingDots()
              : MarkdownBody(
                  data: message.text,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.5),
                    strong: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                    em: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontStyle: FontStyle.italic),
                    h1: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                    h2: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    h3: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                    listBullet: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    blockquote: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    blockquoteDecoration: BoxDecoration(
                      border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
                      color: Colors.transparent,
                    ),
                  ),
                  softLineBreak: true,
                ),
        ),
        if (message.needsRecordPrompt && !recordDismissed) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              _ActionChip(
                label: '✅ 记录',
                color: AppColors.primary,
                onTap: onRecord,
              ),
              const SizedBox(width: 8),
              _ActionChip(
                label: '❌ 不用',
                color: AppColors.textSecondary,
                onTap: onDismiss,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(16),
          color: color.withValues(alpha: 0.08),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final step = (_ctrl.value * 3).floor(); // 0,1,2
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == step
                    ? AppColors.primary
                    : AppColors.textSecondary.withValues(alpha: 0.4),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}
