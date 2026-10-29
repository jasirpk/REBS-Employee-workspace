
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);


  static String? validateBaseUrl(String url) {
    if (url.trim().isEmpty) {
      return 'API_BASE_URL is not set. Create frontend/.env from frontend/.env.example '
          'and run or build the app with --dart-define-from-file=.env.';
    }

    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty || uri.host.contains('%')) {
      return 'API_BASE_URL "$url" is not a valid http:// or https:// URL.';
    }

    if (!url.endsWith('/')) {
      return 'API_BASE_URL "$url" must end with "/", for example http://192.000.0.0:3000/api/.';
    }

    return null;
  }
}
