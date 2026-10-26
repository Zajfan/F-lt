import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:falt/auth/auth_gateway.dart';
import 'package:falt/auth/auth_gate.dart';
import 'package:falt/auth/company_gateway.dart';
import 'package:falt/auth/device_identity.dart';
import 'package:falt/config/app_config.dart';

class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway({this.initialUser});

  AuthUser? initialUser;
  final _states = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => initialUser;

  @override
  Stream<AuthUser?> get authStateChanges => _states.stream;

  void emit(AuthUser? user) {
    initialUser = user;
    _states.add(user);
  }
  void emitError(Object error) => _states.addError(error);
  Future<void> close() => _states.close();

  @override
  Future<AuthUser?> signIn({required String email, required String password}) async => initialUser;

  @override
  Future<AuthUser?> signUp({required String email, required String password}) async => initialUser;

  @override
  Future<void> signOut() async {}
}

void main() {
  test('live configuration requires both Supabase values and demo mode off', () {
    expect(
      const AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        publishableKey: 'publishable-key',
        demoMode: false,
      ).isLive,
      isTrue,
    );
    expect(
      const AppConfig(
        supabaseUrl: '',
        publishableKey: 'publishable-key',
        demoMode: false,
      ).isLive,
      isFalse,
    );
    expect(
      const AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        publishableKey: 'publishable-key',
        demoMode: true,
      ).isLive,
      isFalse,
    );
  });

  test('demo gateway emits signed-in and signed-out state transitions', () async {
    final gateway = DemoAuthGateway();
    final states = <AuthUser?>[];
    final subscription = gateway.authStateChanges.listen(states.add);
    addTearDown(subscription.cancel);

    final user = await gateway.signIn(
      email: 'demo@example.test',
      password: 'demo-password',
    );
    await gateway.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(user.id, DemoAuthGateway.demoUserId);
    expect(states.map((state) => state?.id), [DemoAuthGateway.demoUserId, null]);
  });

  test('device identity reuses the stored UUID across loads', () async {
    final storage = MemoryDeviceIdentityStorage();
    final first = await DeviceIdentity(storage: storage).load();
    final second = await DeviceIdentity(storage: storage).load();

    expect(first, second);
    expect(storage.value, first);
  });

  test('auth error messages do not expose provider details', () {
    expect(
      sanitizeAuthError(Exception('secret provider response with token')),
      'Inloggningen kunde inte genomföras. Kontrollera uppgifterna och försök igen.',
    );
  });

  testWidgets('same-user auth events preserve the active workspace', (tester) async {
    final user = const AuthUser(id: '11111111-1111-4111-8111-111111111111');
    final gateway = _FakeAuthGateway(initialUser: user);
    var workspaceBuilds = 0;
    final company = const CompanySummary(
      id: '22222222-2222-4222-8222-222222222222',
      name: 'Workspace',
      tradeProfile: 'Annat',
      role: 'owner',
    );
    final companies = CompanyGateway.forTesting(
      rpc: (name, {rpcParams}) async => [
        {
          'id': company.id,
          'name': company.name,
          'trade_profile': company.tradeProfile,
          'role': company.role,
        },
      ],
    );
    addTearDown(gateway.close);

    await tester.pumpWidget(MaterialApp(
      home: AuthGate(
        config: const AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          publishableKey: 'publishable-key',
          demoMode: false,
        ),
        authGateway: gateway,
        companyGateway: companies,
        deviceIdentity: DeviceIdentity(storage: MemoryDeviceIdentityStorage()),
        demoWorkspace: () => const Text('demo'),
        liveWorkspace: (user, company, deviceId) {
          workspaceBuilds++;
          return const Text('active workspace');
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('active workspace'), findsOneWidget);
    expect(workspaceBuilds, 1);

    gateway.emit(user);
    await tester.pump();
    expect(find.text('active workspace'), findsOneWidget);
    expect(workspaceBuilds, 1);
  });

  testWidgets('auth stream errors show a sanitized connection message', (tester) async {
    final gateway = _FakeAuthGateway();
    addTearDown(gateway.close);
    await tester.pumpWidget(MaterialApp(
      home: AuthGate(
        config: const AppConfig(
          supabaseUrl: '',
          publishableKey: '',
          demoMode: true,
        ),
        authGateway: gateway,
        deviceIdentity: DeviceIdentity(storage: MemoryDeviceIdentityStorage()),
        demoWorkspace: () => const Text('demo'),
        liveWorkspace: (user, company, deviceId) => const Text('live'),
      ),
    ));

    gateway.emitError(Exception('provider token leaked'));
    await tester.pump();
    expect(find.text('Anslutningen till inloggningen bröts. Försök igen.'), findsOneWidget);
    expect(find.textContaining('provider token'), findsNothing);
  });

  testWidgets('a stale company selection cannot reopen a signed-out workspace', (tester) async {
    final user = const AuthUser(id: '11111111-1111-4111-8111-111111111111');
    final gateway = _FakeAuthGateway(initialUser: user);
    final identityRead = Completer<String?>();
    final company = const CompanySummary(
      id: '22222222-2222-4222-8222-222222222222',
      name: 'Workspace',
      tradeProfile: 'Annat',
      role: 'owner',
    );
    final companies = CompanyGateway.forTesting(
      rpc: (name, {rpcParams}) async => [
        {
          'id': company.id,
          'name': company.name,
          'trade_profile': company.tradeProfile,
          'role': company.role,
        },
      ],
    );
    final identity = DeviceIdentity(
      storage: _BlockingDeviceIdentityStorage(identityRead),
    );
    addTearDown(gateway.close);

    await tester.pumpWidget(MaterialApp(
      home: AuthGate(
        config: const AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          publishableKey: 'publishable-key',
          demoMode: false,
        ),
        authGateway: gateway,
        companyGateway: companies,
        deviceIdentity: identity,
        demoWorkspace: () => const Text('demo'),
        liveWorkspace: (user, company, deviceId) => const Text('active workspace'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace'));
    await tester.pump();
    gateway.emit(null);
    await tester.pump();
    identityRead.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('Logga in till din arbetsyta'), findsOneWidget);
    expect(find.text('active workspace'), findsNothing);
  });
}

class _BlockingDeviceIdentityStorage implements DeviceIdentityStorage {
  _BlockingDeviceIdentityStorage(this.readResult);

  final Completer<String?> readResult;

  @override
  Future<String?> read() => readResult.future;

  @override
  Future<void> write(String value) async {}
}
