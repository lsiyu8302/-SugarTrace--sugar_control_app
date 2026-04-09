import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

const _base = 'http://10.0.2.2:8000';

class ApiService {
  static Future<Map<String, dynamic>> chat({
    required String message,
    Uint8List? imageBytes,
    List<Map<String, String>> history = const [],
    int? lastRecordId,
  }) async {
    final String? imageBase64 =
        imageBytes != null ? base64Encode(imageBytes) : null;

    final body = <String, dynamic>{
      'message': message,
      'history': history,
      'image_base64': imageBase64,
      'last_record_id': lastRecordId,
    }..removeWhere((_, v) => v == null);

    final resp = await http
        .post(
          Uri.parse('$_base/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 40));

    if (resp.statusCode != 200) {
      throw HttpException('Server error ${resp.statusCode}');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> record({
    required String foodName,
    required double sugarG,
    double? calories,
    String category = '其他',
    String? servingSize,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$_base/record'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'food_name': foodName,
            'sugar_g': sugarG,
            'calories': calories,
            'category': category,
            'serving_size': servingSize,
          }..removeWhere((_, v) => v == null)),
        )
        .timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw HttpException('Server error ${resp.statusCode}');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<void> deleteRecord(int id) async {
    final resp = await http
        .delete(Uri.parse('$_base/record/$id'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw HttpException('Server error ${resp.statusCode}');
    }
  }

  static Future<void> updateSettings(String key, String value) async {
    final resp = await http
        .put(
          Uri.parse('$_base/settings'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'key': key, 'value': value}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw HttpException('Server error ${resp.statusCode}');
  }

  static Future<void> clearTodayRecords() async {
    final resp = await http
        .delete(Uri.parse('$_base/records/today'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw HttpException('Server error ${resp.statusCode}');
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final resp = await http
        .get(Uri.parse('$_base/settings'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw HttpException('Server error ${resp.statusCode}');
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getDailySummary(String date) async {
    final resp = await http
        .get(Uri.parse('$_base/daily-summary/$date'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw HttpException('Server error ${resp.statusCode}');
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyShoppingIntent({
    String? screenshotBase64,
    String? screenText,
    List<String> foodKeywords = const [],
  }) async {
    final resp = await http
        .post(
          Uri.parse('$_base/verify-shopping-intent'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'screenshot_base64': screenshotBase64,
            'screen_text': screenText,
            'food_keywords': foodKeywords,
          }..removeWhere((_, v) => v == null)),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) throw HttpException('Server error ${resp.statusCode}');
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getRecordsRange(
      String start, String end) async {
    final uri = Uri.parse('$_base/records/range').replace(
        queryParameters: {'start': start, 'end': end});
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw HttpException('Server error ${resp.statusCode}');
    return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
        .cast<Map<String, dynamic>>();
  }
}
