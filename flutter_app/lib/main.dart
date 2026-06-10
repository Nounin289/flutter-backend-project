import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// ⚠️ ضع رابط الـ Backend بعد نشره على Cloud Run
const String BASE_URL = "https://YOUR-BACKEND-URL.run.app";

void main() {
  runApp(const VideoDownloaderApp());
}

class VideoDownloaderApp extends StatelessWidget {
  const VideoDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ======= الصفحة الرئيسية =======
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _videoInfo;
  String _selectedQuality = "best";
  String _status = "";

  Future<void> _getVideoInfo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _videoInfo = null;
      _status = "جاري جلب معلومات الفيديو...";
    });

    try {
      final response = await http.post(
        Uri.parse("$BASE_URL/info"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"url": url}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        setState(() {
          _videoInfo = jsonDecode(response.body);
          _status = "";
        });
      } else {
        final err = jsonDecode(response.body);
        setState(() => _status = "❌ ${err['detail']}");
      }
    } catch (e) {
      setState(() => _status = "❌ خطأ في الاتصال: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadVideo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _status = "جاري تحضير الفيديو للتحميل...";
    });

    try {
      final response = await http.post(
        Uri.parse("$BASE_URL/download"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"url": url, "quality": _selectedQuality}),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final downloadUrl = "$BASE_URL${data['download_url']}";
        
        // فتح رابط التحميل في المتصفح
        if (await canLaunchUrl(Uri.parse(downloadUrl))) {
          await launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
          setState(() => _status = "✅ بدأ التحميل!");
        }
      } else {
        final err = jsonDecode(response.body);
        setState(() => _status = "❌ ${err['detail']}");
      }
    } catch (e) {
      setState(() => _status = "❌ خطأ: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
      _getVideoInfo();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text(
          "📥 Video Downloader",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // المنصات المدعومة
            _buildPlatformIcons(),
            const SizedBox(height: 24),

            // حقل الرابط
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "الصق رابط الفيديو هنا...",
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onSubmitted: (_) => _getVideoInfo(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste, color: Color(0xFF6C63FF)),
                    onPressed: _pasteFromClipboard,
                    tooltip: "لصق",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // زر البحث
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _getVideoInfo,
              icon: const Icon(Icons.search),
              label: const Text("جلب معلومات الفيديو"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            // حالة التحميل
            if (_isLoading) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
            ],

            // رسالة الحالة
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _status,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            // معلومات الفيديو
            if (_videoInfo != null) ...[
              const SizedBox(height: 24),
              _buildVideoCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformIcons() {
    final platforms = [
      {"name": "YouTube", "emoji": "▶️"},
      {"name": "TikTok", "emoji": "🎵"},
      {"name": "Instagram", "emoji": "📸"},
      {"name": "Facebook", "emoji": "📘"},
      {"name": "Threads", "emoji": "🧵"},
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: platforms.map((p) => Chip(
        label: Text("${p['emoji']} ${p['name']}"),
        backgroundColor: const Color(0xFF1E1E2E),
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
        side: BorderSide.none,
      )).toList(),
    );
  }

  Widget _buildVideoCard() {
    final info = _videoInfo!;
    final formats = (info['formats'] as List?) ?? [];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الصورة المصغرة
          if (info['thumbnail'] != null && info['thumbnail'].toString().isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.network(
                info['thumbnail'],
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 180,
                  color: const Color(0xFF2A2A3E),
                  child: const Icon(Icons.video_library, size: 60, color: Colors.white30),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // العنوان
                Text(
                  info['title'] ?? "فيديو",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "${info['platform'] ?? ''} • ${_formatDuration(info['duration'] ?? 0)}",
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),

                // اختيار الجودة
                if (formats.isNotEmpty) ...[
                  const Text("الجودة:", style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _qualityChip("best", "أفضل جودة"),
                      ...formats.take(4).map((f) => _qualityChip(
                        f['quality'].toString().replaceAll('p', ''),
                        f['quality'].toString(),
                      )),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // زر التحميل
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _downloadVideo,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text("تحميل الفيديو"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qualityChip(String value, String label) {
    final isSelected = _selectedQuality == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedQuality = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF) : const Color(0xFF2A2A3E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }
}
