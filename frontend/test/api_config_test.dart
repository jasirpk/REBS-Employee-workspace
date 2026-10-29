import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/config/api_config.dart';
import 'package:frontend/core/config/configuration_error_app.dart';

void main() {
  group('ApiConfig.validateBaseUrl', () {
    test('accepts http and https URLs that end with a slash', () {
      expect(ApiConfig.validateBaseUrl('http://192.168.1.2:3000/api/'), isNull);
      expect(ApiConfig.validateBaseUrl('http://localhost:3000/api/'), isNull);
      expect(ApiConfig.validateBaseUrl('https://example.com/api/'), isNull);
    });

    test('reports a missing value and how to set it', () {
      final message = ApiConfig.validateBaseUrl('');

      expect(message, contains('API_BASE_URL is not set'));
      expect(message, contains('frontend/.env'));
      expect(message, contains('frontend/.env.example'));
      expect(ApiConfig.validateBaseUrl('   '), message);
    });

    test('rejects values that are not http(s) URLs', () {
      expect(ApiConfig.validateBaseUrl('192.168.1.2:3000/api/'), contains('not a valid'));
      expect(ApiConfig.validateBaseUrl('ftp://192.168.1.2/api/'), contains('not a valid'));
      expect(ApiConfig.validateBaseUrl('http://<MAC_LAN_IP>:3000/api/'), contains('not a valid'));
    });

    test('requires the trailing slash so the /api path is kept', () {
      expect(ApiConfig.validateBaseUrl('http://192.168.1.2:3000/api'), contains('must end with "/"'));
    });

  });

  group('ApiConfig.readBaseUrl', () {
    test('returns API_BASE_URL from the loaded .env', () {
      final env = DotEnv()..testLoad(fileInput: 'API_BASE_URL=http://192.168.1.2:3000/api/\n# API_BASE_URL=http://localhost:3000/api/');

      expect(ApiConfig.readBaseUrl(env), 'http://192.168.1.2:3000/api/');
    });

    test('returns an empty value, not "null", when the key is missing', () {
      final env = DotEnv()..testLoad(fileInput: 'OTHER_SETTING=1');

      expect(ApiConfig.readBaseUrl(env), isEmpty);
      expect(ApiConfig.validateBaseUrl(ApiConfig.readBaseUrl(env)), contains('API_BASE_URL is not set'));
    });

    test('returns an empty value when .env was never loaded', () {
      expect(ApiConfig.readBaseUrl(DotEnv()), isEmpty);
    });

    test('is empty in unit tests, which never load .env', () {
      // Tests construct ApiClient without loading .env; this must not throw.
      expect(ApiConfig.baseUrl, isEmpty);
    });
  });

  testWidgets('the configuration error screen shows the message', (tester) async {
    final message = ApiConfig.validateBaseUrl('')!;

    await tester.pumpWidget(ConfigurationErrorApp(message: message));

    expect(find.text('App configuration error'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
  });
}
