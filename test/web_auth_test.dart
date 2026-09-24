import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turnstile_checkin/providers/settings_provider.dart';
import 'package:turnstile_checkin/services/storage_service.dart';
import 'package:turnstile_checkin/utils/jwt_utils.dart';

void main() {
  test('JWT validator parses valid unexpired JWT', () {
    // Generate an unexpired test JWT payload (exp: year 2030)
    // Header: {"alg":"none","typ":"JWT"} -> eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0
    // Payload: {"sub":"user123","name":"Test User","exp":1893456000} -> eyJzdWIiOiJ1c2VyMTIzIiwibmFtZSI6IlRlc3QgVXNlciIsImV4cCI6MTg5MzQ1NjAwMH0
    const validJwt =
        'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJ1c2VyMTIzIiwibmFtZSI6IlRlc3QgVXNlciIsImV4cCI6MTg5MzQ1NjAwMH0.';

    expect(validJwt.startsWith('eyJ'), isTrue);
    expect(JwtUtils.isExpired(validJwt), isFalse);
    expect(JwtUtils.getUserIdentifier(validJwt), 'Test User');
  });

  test('SettingsProvider updates bearer token properly', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final settingsProvider = SettingsProvider(storage);

    const testToken =
        'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJ1c2VyMTIzIiwibmFtZSI6IlRlc3QgVXNlciIsImV4cCI6MTg5MzQ1NjAwMH0.';

    await settingsProvider.setBearerToken(testToken);
    expect(settingsProvider.settings.bearerToken, testToken);
  });
}
