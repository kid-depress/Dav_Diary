import 'dart:convert';
import 'dart:io';

class DailyQuoteService {
  const DailyQuoteService();

  static final Uri _endpoint = Uri.parse('https://v1.hitokoto.cn/');

  Future<String> fetchQuote() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(_endpoint);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Unexpected status code: ${response.statusCode}',
          uri: _endpoint,
        );
      }
      final body = await utf8.decodeStream(response);
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Invalid quote response payload');
      }
      final quote = (json['hitokoto'] as String? ?? '').trim();
      if (quote.isEmpty) {
        throw const FormatException('Quote is missing');
      }
      return quote;
    } finally {
      client.close(force: true);
    }
  }
}
