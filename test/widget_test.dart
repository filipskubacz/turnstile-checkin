import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turnstile_checkin/models/app_settings.dart';
import 'package:turnstile_checkin/providers/scanner_provider.dart';
import 'package:turnstile_checkin/services/graphql_service.dart';
import 'package:turnstile_checkin/services/queue_service.dart';
import 'package:turnstile_checkin/services/storage_service.dart';

void main() {
  test('App Services initialization smoke test', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    expect(storage.loadSettings().isSafeMode, isTrue);

    final gql = GraphQLService(storage);
    final queue = QueueService(
      storageService: storage,
      graphQLService: gql,
      getSettings: () => const AppSettings(),
    );
    await queue.init();

    final scanner = ScannerProvider(
      graphQLService: gql,
      queueService: queue,
      getSettings: () => const AppSettings(),
    );

    expect(scanner.state, ScanState.ready);
  });
}
