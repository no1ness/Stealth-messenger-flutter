import 'dart:convert';
import 'dart:io';

Future<Map<String, Object?>> loadUpdateManifest(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
          'manifest request failed with HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return decoded.cast<String, Object?>();
    throw const FormatException('manifest root must be a JSON object');
  } finally {
    client.close(force: true);
  }
}
