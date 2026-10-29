

import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  ApiConfig._();

  // From frontend/.env, which main() loads with dotenv.load() before the API
  // client is created. Read once, on first use.
  static final String baseUrl = readBaseUrl(dotenv);

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);

  // API_BASE_URL from [env], or '' when the key is missing or [env] was never
  // loaded (as in unit tests), so validateBaseUrl reports it. Using toString()
  // here would turn a missing value into the string "null".
  static String readBaseUrl(DotEnv env) {
    if (!env.isInitialized) return '';
    return env.env['API_BASE_URL'] ?? '';
  }

  static String? validateBaseUrl(String url) {
    if (url.trim().isEmpty) {
      return 'API_BASE_URL is not set. Create frontend/.env from frontend/.env.example, '
          'set API_BASE_URL, and rebuild the app.';
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
