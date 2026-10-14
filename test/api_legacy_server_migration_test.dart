import 'package:flutter_test/flutter_test.dart';

import '../lib/core/api.dart';

void main() {
  group('legacy FlavorFlow API URL migration', () {
    const official = 'https://app.flavorflow.co.in/api';

    test('rewrites the saved factory DuckDNS URL to the official HTTPS API', () {
      expect(
        ApiClient.migrateLegacyServerBase('https://flavorflow.duckdns.org/api'),
        official,
      );
      expect(
        ApiClient.migrateLegacyServerBase('http://flavorflow.duckdns.org'),
        official,
      );
      expect(
        ApiClient.migrateLegacyServerBase('http://flavorflow.duckdns.org:80/api/'),
        official,
      );
    });

    test('leaves unrelated hosts, tenant paths, and custom ports untouched', () {
      expect(ApiClient.migrateLegacyServerBase('https://example.com/api'), isNull);
      expect(ApiClient.migrateLegacyServerBase('https://gdfoods.duckdns.org/api'), isNull);
      expect(
        ApiClient.migrateLegacyServerBase('https://flavorflow.duckdns.org/t/acme/api'),
        isNull,
      );
      expect(
        ApiClient.migrateLegacyServerBase('http://flavorflow.duckdns.org:4000/api'),
        isNull,
      );
    });
  });
}
