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
      expect(message, contains('--dart-define-from-file=.env'));
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

    test('tests run without .env, so the compiled value is empty and rejected', () {
      // `fvm flutter test` passes no --dart-define-from-file, which is the
      // same situation as a build without frontend/.env.
      expect(ApiConfig.baseUrl, isEmpty);
      expect(ApiConfig.validateBaseUrl(ApiConfig.baseUrl), isNotNull);
    });
  });

  testWidgets('the configuration error screen shows the message', (tester) async {
    final message = ApiConfig.validateBaseUrl('')!;

    await tester.pumpWidget(ConfigurationErrorApp(message: message));

    expect(find.text('App configuration error'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
  });
}
