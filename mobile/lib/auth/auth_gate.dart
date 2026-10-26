import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../sync/background_sync.dart';
import 'auth_gateway.dart';
import 'company_gateway.dart';
import 'device_identity.dart';

typedef DemoWorkspaceBuilder = Widget Function();
typedef LiveWorkspaceBuilder = Widget Function(
  AuthUser user,
  CompanySummary company,
  String deviceId,
);

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.config,
    required this.authGateway,
    required this.deviceIdentity,
    required this.demoWorkspace,
    required this.liveWorkspace,
    this.companyGateway,
    this.backgroundSyncScheduler,
  });

  final AppConfig config;
  final AuthGateway authGateway;
  final CompanyGateway? companyGateway;
  final DeviceIdentity deviceIdentity;
  final DemoWorkspaceBuilder demoWorkspace;
  final LiveWorkspaceBuilder liveWorkspace;
  final BackgroundSyncScheduler? backgroundSyncScheduler;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthUser? _user;
  List<CompanySummary>? _companies;
  Widget? _workspace;
  StreamSubscription<AuthUser?>? _authSubscription;
  bool _loading = false;
  String? _error;
  int _requestGeneration = 0;
  String? _scheduledCompanyId;

  @override
  void initState() {
    super.initState();
    _user = widget.authGateway.currentUser;
    _authSubscription = widget.authGateway.authStateChanges.listen(
      _onUser,
      onError: _onAuthError,
    );
    if (_user != null) unawaited(_onUser(_user));
  }

  @override
  void dispose() {
    _requestGeneration++;
    final subscription = _authSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    unawaited(_cancelScheduledSync());
    super.dispose();
  }

  Future<void> _onUser(AuthUser? user) async {
    if (!mounted) return;
    if (user != null && user.id == _user?.id && _workspace != null) {
      return;
    }
    if (user?.id != _user?.id) {
      unawaited(_cancelScheduledSync());
    }
    final generation = ++_requestGeneration;
    setState(() {
      _user = user;
      _workspace = null;
      _companies = null;
      _error = null;
    });
    if (user == null) return;
    if (!widget.config.isLive) {
      setState(() => _workspace = widget.demoWorkspace());
      return;
    }
    await _loadCompanies(userId: user.id, generation: generation);
  }

  void _onAuthError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    _requestGeneration++;
    setState(() {
      _error = 'Anslutningen till inloggningen bröts. Försök igen.';
      _loading = false;
    });
  }

  bool _requestIsCurrent({required String userId, required int generation}) =>
      mounted &&
      generation == _requestGeneration &&
      _user?.id == userId;

  Future<void> _loadCompanies({
    required String userId,
    required int generation,
  }) async {
    final gateway = widget.companyGateway;
    if (gateway == null) {
      if (_requestIsCurrent(userId: userId, generation: generation)) {
        setState(() => _error = 'Företagsanslutningen saknas.');
      }
      return;
    }
    if (!_requestIsCurrent(userId: userId, generation: generation)) return;
    setState(() => _loading = true);
    try {
      final companies = await gateway.listMyCompanies();
      if (!_requestIsCurrent(userId: userId, generation: generation)) return;
      setState(() => _companies = companies);
    } catch (error) {
      if (_requestIsCurrent(userId: userId, generation: generation)) {
        setState(() => _error = _companyError(error));
      }
    } finally {
      if (_requestIsCurrent(userId: userId, generation: generation)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectCompany(
    CompanySummary company, {
    int? generation,
    String? userId,
  }) async {
    final user = _user;
    if (user == null) return;
    final requestGeneration = generation ?? _requestGeneration;
    final requestUserId = userId ?? user.id;
    if (!_requestIsCurrent(
      userId: requestUserId,
      generation: requestGeneration,
    )) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final deviceId = await widget.deviceIdentity.load();
      if (_requestIsCurrent(
        userId: requestUserId,
        generation: requestGeneration,
      )) {
        setState(() {
          _workspace = widget.liveWorkspace(user, company, deviceId);
          _loading = false;
        });
        _scheduledCompanyId = company.id;
        final scheduler = widget.backgroundSyncScheduler;
        if (scheduler != null) {
          unawaited(
            scheduler
                .schedule(
                  accountId: user.id,
                  companyId: company.id,
                  deviceId: deviceId,
                )
                .catchError((_) {}),
          );
        }
      }
    } catch (error) {
      if (_requestIsCurrent(
        userId: requestUserId,
        generation: requestGeneration,
      )) {
        setState(() {
          _loading = false;
          _error = 'Kunde inte förbereda den här enheten. Försök igen.';
        });
      }
    }
  }

  Future<void> _cancelScheduledSync() async {
    final companyId = _scheduledCompanyId;
    _scheduledCompanyId = null;
    final scheduler = widget.backgroundSyncScheduler;
    if (companyId == null || scheduler == null) return;
    try {
      await scheduler.cancel(companyId);
    } catch (_) {
      // A failed cancellation must not block logout or account switching.
    }
  }

  Future<void> _signOut() async {
    await _cancelScheduledSync();
    await widget.authGateway.signOut();
  }

  Future<void> _createCompany(String name, String tradeProfile) async {
    final gateway = widget.companyGateway;
    if (gateway == null) return;
    if (name.trim().length < 2) {
      setState(() => _error = 'Ange företagets namn.');
      return;
    }
    final user = _user;
    if (user == null) return;
    final generation = _requestGeneration;
    final userId = user.id;
    if (!_requestIsCurrent(userId: userId, generation: generation)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final company = await gateway.createCompany(
        name: name,
        tradeProfile: tradeProfile,
      );
      if (!_requestIsCurrent(userId: userId, generation: generation)) return;
      await _selectCompany(
        company,
        generation: generation,
        userId: userId,
      );
    } catch (error) {
      if (_requestIsCurrent(userId: userId, generation: generation)) {
        setState(() {
          _loading = false;
          _error = _companyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_workspace != null) {
      if (_error == null) return _workspace!;
      return Stack(
        children: [
          _workspace!,
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ),
        ],
      );
    }
    final user = _user;
    if (user == null) {
      return _AuthForm(
        allowDemo: !widget.config.isLive,
        gateway: widget.authGateway,
        gateError: _error,
        onDemo: () async {
          final gateway = widget.authGateway;
          if (gateway is! DemoAuthGateway) {
            throw StateError('Demo mode is unavailable.');
          }
          await gateway.continueDemo();
        },
      );
    }
    if (!widget.config.isLive) return const _LoadingScreen();
    final companies = _companies;
    if (_loading && companies == null) return const _LoadingScreen();
    return _CompanyOnboarding(
      companies: companies ?? const [],
      busy: _loading,
      error: _error,
      onSelect: _selectCompany,
      onCreate: _createCompany,
      onSignOut: _signOut,
    );
  }

  String _companyError(Object error) =>
      error is FormatException
          ? 'Företagsinformationen kunde inte läsas.'
          : 'Företaget kunde inte sparas. Kontrollera anslutningen och försök igen.';
}

class _AuthForm extends StatefulWidget {
  const _AuthForm({
    required this.allowDemo,
    required this.gateway,
    required this.onDemo,
    this.gateError,
  });

  final bool allowDemo;
  final AuthGateway gateway;
  final Future<void> Function() onDemo;
  final String? gateError;

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@')) {
      setState(() => _error = 'Ange en giltig e-postadress.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Lösenordet måste vara minst 6 tecken.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = _signUp
          ? await widget.gateway.signUp(email: email, password: password)
          : await widget.gateway.signIn(email: email, password: password);
      if (mounted && _signUp && user == null) {
        setState(() => _error = 'Kontot skapades. Bekräfta din e-post innan du loggar in.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = sanitizeAuthError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayError = _error ?? widget.gateError;
    return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
            children: [
              Text(
                'fält.',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _signUp ? 'Skapa ditt konto' : 'Logga in till din arbetsyta',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-post'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Lösenord'),
              ),
              if (displayError != null) ...[
                const SizedBox(height: 14),
                Text(displayError, style: TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_signUp ? 'Skapa konto' : 'Logga in'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _signUp = !_signUp;
                          _error = null;
                        }),
                child: Text(
                  _signUp ? 'Jag har redan ett konto' : 'Skapa ett nytt konto',
                ),
              ),
              if (widget.allowDemo) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await widget.onDemo();
                          } catch (error) {
                            if (mounted) setState(() => _error = sanitizeAuthError(error));
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: const Text('Fortsätt med demo på enheten'),
                ),
              ],
            ],
          ),
        ),
      );
  }
}

class _CompanyOnboarding extends StatefulWidget {
  const _CompanyOnboarding({
    required this.companies,
    required this.busy,
    required this.error,
    required this.onSelect,
    required this.onCreate,
    required this.onSignOut,
  });

  final List<CompanySummary> companies;
  final bool busy;
  final String? error;
  final Future<void> Function(CompanySummary company) onSelect;
  final Future<void> Function(String name, String tradeProfile) onCreate;
  final Future<void> Function() onSignOut;

  @override
  State<_CompanyOnboarding> createState() => _CompanyOnboardingState();
}

class _CompanyOnboardingState extends State<_CompanyOnboarding> {
  final _name = TextEditingController();
  String _profile = 'Annat';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Välj arbetsyta'),
          actions: [
            IconButton(
              tooltip: 'Logga ut',
              onPressed: widget.busy
                  ? null
                  : () => unawaited(widget.onSignOut()),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.companies.isEmpty
                  ? 'Skapa företagets arbetsyta'
                  : 'Dina företag',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              widget.companies.isEmpty
                  ? 'Börja med namn och profil. Du kan lägga till kunder när arbetsytan är klar.'
                  : 'Välj en arbetsyta eller skapa en ny.',
            ),
            const SizedBox(height: 20),
            ...widget.companies.map(
              (company) => Card(
                child: ListTile(
                  title: Text(company.name),
                  subtitle: Text('${company.tradeProfile} · ${company.role}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.busy ? null : () => widget.onSelect(company),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Skapa ny arbetsyta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Företagsnamn'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _profile,
              decoration: const InputDecoration(labelText: 'Profil'),
              items: const [
                DropdownMenuItem(value: 'Tak', child: Text('Tak')),
                DropdownMenuItem(value: 'Måleri', child: Text('Måleri')),
                DropdownMenuItem(value: 'El', child: Text('El')),
                DropdownMenuItem(value: 'Annat', child: Text('Annat')),
              ],
              onChanged: widget.busy ? null : (value) => setState(() => _profile = value!),
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 14),
              Text(widget.error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: widget.busy
                  ? null
                  : () => widget.onCreate(_name.text, _profile),
              child: const Text('Skapa arbetsyta'),
            ),
          ],
        ),
      );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
