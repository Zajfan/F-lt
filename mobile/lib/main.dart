import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'auth/auth_gateway.dart';
import 'auth/auth_gate.dart';
import 'auth/company_gateway.dart';
import 'auth/device_identity.dart';
import 'config/app_config.dart';
import 'data/local_store.dart';
import 'domain/estimate.dart';
import 'domain/job.dart';
import 'features/jobs/job_workspace.dart';
import 'features/jobs/photo_service.dart';
import 'features/pricebook/pricebook_page.dart';
import 'features/settings/company_page.dart';
import 'sync/sync_context.dart';
import 'sync/background_sync.dart';
import 'sync/supabase_sync_transport.dart';
import 'sync/sync_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  SupabaseClient? client;
  BackgroundSyncScheduler? backgroundSyncScheduler;
  if (config.isLive) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.publishableKey,
    );
    client = Supabase.instance.client;
    backgroundSyncScheduler = BackgroundSyncScheduler();
    try {
      await backgroundSyncScheduler.initialize();
    } catch (_) {
      // Foreground auth and sync must remain usable if the platform scheduler
      // is unavailable on a particular device or build configuration.
      backgroundSyncScheduler = null;
    }
  }
  runApp(FaltApp(
    config: config,
    client: client,
    backgroundSyncScheduler: backgroundSyncScheduler,
  ));
}

class FaltApp extends StatelessWidget {
  const FaltApp({
    super.key,
    this.store,
    this.clock,
    this.config,
    this.client,
    this.authGateway,
    this.companyGateway,
    this.deviceIdentity,
    this.backgroundSyncScheduler,
  });

  final DateTime Function()? clock;
  final LocalStore? store;
  final AppConfig? config;
  final SupabaseClient? client;
  final AuthGateway? authGateway;
  final CompanyGateway? companyGateway;
  final DeviceIdentity? deviceIdentity;
  final BackgroundSyncScheduler? backgroundSyncScheduler;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fält',
    debugShowCheckedModeBanner: false,
    locale: const Locale('sv'),
    supportedLocales: const [Locale('sv')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: Color(0xff154c3e),
        onPrimary: Colors.white,
        secondary: Color(0xffbcec8d),
        onSecondary: Color(0xff153f34),
        surface: Color(0xfffaf9ee),
        onSurface: Color(0xff173f34),
        primaryContainer: Color(0xffe8efda),
        onPrimaryContainer: Color(0xff173f34),
        secondaryContainer: Color(0xffe4f2ce),
        onSecondaryContainer: Color(0xff173f34),
        outline: Color(0xffc8d4bd),
        outlineVariant: Color(0xffdde3d2),
      ),
      scaffoldBackgroundColor: const Color(0xfffaf9ee),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xfffaf9ee),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffd9dfce)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xffbcec8d),
          foregroundColor: const Color(0xff153f34),
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xfff5f5e8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfffaf9ee),
        foregroundColor: Color(0xff154c3e),
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xfffaf9ee),
        indicatorColor: Color(0xffddefc8),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Color(0xff154c3e),
        unselectedLabelColor: Color(0xff607b65),
        indicatorColor: Color(0xff1e8b4b),
      ),
    ),
    home: store != null
        ? Workspace(providedStore: store, clock: clock)
        : _buildGate(),
  );

  Widget _buildGate() {
    final selectedConfig = config ?? AppConfig.fromEnvironment();
    final selectedAuth = authGateway ??
        (client == null
            ? DemoAuthGateway()
            : SupabaseAuthGateway(client: client!));
    return AuthGate(
      config: selectedConfig,
      authGateway: selectedAuth,
      companyGateway: selectedConfig.isLive
          ? companyGateway ?? CompanyGateway(client: client!)
          : null,
      deviceIdentity: deviceIdentity ?? DeviceIdentity.production(),
      backgroundSyncScheduler: backgroundSyncScheduler,
      demoWorkspace: () => Workspace(clock: clock),
      liveWorkspace: (user, company, deviceId) => Workspace.live(
        client: client!,
        syncContext: SyncContext(
          accountId: user.id,
          companyId: company.id,
          deviceId: deviceId,
        ),
        clock: clock,
        onSignOut: selectedAuth.signOut,
      ),
    );
  }
}

String sek(int ore) =>
    NumberFormat.currency(locale: 'sv_SE', symbol: 'kr').format(ore / 100);
String quoteLabel(QuoteStatus status) => switch (status) {
  QuoteStatus.draft => 'Utkast',
  QuoteStatus.sent => 'Skickad',
  QuoteStatus.accepted => 'Godkänd',
  QuoteStatus.declined => 'Avböjd',
};

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    this.providedStore,
    this.clock,
    this.syncContext,
    this.client,
    this.onSignOut,
  });

  factory Workspace.live({
    required SupabaseClient client,
    required SyncContext syncContext,
    DateTime Function()? clock,
    Future<void> Function()? onSignOut,
  }) => Workspace(
        client: client,
        syncContext: syncContext,
        clock: clock,
        onSignOut: onSignOut,
      );

  final DateTime Function()? clock;
  final LocalStore? providedStore;
  final SyncContext? syncContext;
  final SupabaseClient? client;
  final Future<void> Function()? onSignOut;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  LocalStore? store;
  String? error;
  int tab = 0;
  bool busy = false;
  List<Job> jobs = [];
  List<Quote> quotes = [];
  List<Map<String, dynamic>> customers = [], invoices = [];
  SyncEngine? _syncEngine;
  Timer? _syncTimer;
  Future<void>? _syncInFlight;
  bool _disposed = false;
  bool _storeClosed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  bool get isLive => widget.syncContext != null;

  Future<void> _closeOwnedStore(LocalStore candidate) async {
    if (widget.providedStore != null || _storeClosed) return;
    _storeClosed = true;
    if (identical(store, candidate)) store = null;
    await candidate.close();
  }

  Future<void> initialize() async {
    LocalStore? openedStore;
    try {
      openedStore = widget.providedStore ??
          await LocalStore.open(syncContext: widget.syncContext);
      if (!mounted) {
        await _closeOwnedStore(openedStore);
        return;
      }
      store = openedStore;
      if (widget.providedStore == null) _storeClosed = false;
      if (!isLive) {
        await store!.seedDemo(at: widget.clock?.call());
        await store!.ensureCatalog();
      }
      if (!mounted) return;
      try {
        await PhotoService(store!).recover();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      if (!mounted) return;
      if (isLive) {
        _syncEngine = SyncEngine(
          store: store!,
          transport: SupabaseSyncTransport(
            client: widget.client!,
            companyId: widget.syncContext!.companyId,
          ),
        );
        await runSync();
        if (!mounted) return;
        _startSyncTimer();
      }
      if (!mounted) return;
      await refresh();
    } catch (e) {
      if (openedStore != null) await _closeOwnedStore(openedStore);
      if (mounted) {
        setState(
          () => error = 'Det gick inte att öppna den lokala databasen. $e',
        );
      }
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    if (!isLive || !mounted || _disposed) return;
    _syncTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(runSync()),
    );
  }

  Future<void> runSync() {
    final inFlight = _syncInFlight;
    if (inFlight != null) return inFlight;
    final future = _runSync();
    _syncInFlight = future;
    return future.whenComplete(() {
      if (identical(_syncInFlight, future)) _syncInFlight = null;
    });
  }

  Future<void> _runSync() async {
    final engine = _syncEngine;
    if (engine == null || !mounted || _disposed) return;
    try {
      final result = await engine.runOnce();
      if (mounted && result.errors.isNotEmpty && result.pushed == 0 && result.pulled == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synkningen försöker igen senare.')),
        );
      }
      if (mounted && !_disposed) await refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synkningen försöker igen senare.')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isLive) return;
    if (state == AppLifecycleState.resumed) {
      _startSyncTimer();
      unawaited(runSync());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _syncTimer?.cancel();
      _syncTimer = null;
    }
  }

  Future<void> refresh() async {
    final j = await store!.list('job');
    final q = await store!.list('quote');
    final c = await store!.list('customer');
    final i = await store!.list('invoice');
    if (!mounted) {
      return;
    }
    setState(() {
      jobs = j.map(Job.fromJson).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      quotes = q.map(Quote.fromJson).toList();
      customers = c;
      invoices = i;
    });
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      await refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  String customerName(String id) =>
      customers.where((c) => c['id'] == id).firstOrNull?['name'] as String? ??
      'Okänd kund';
  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() => error = null);
                      initialize();
                    },
                    child: const Text('Försök igen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'fält.',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 30),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Fler funktioner',
            onSelected: (value) async {
              if (value == 'about') {
                about();
                return;
              }
              if (value == 'sync') {
                await syncStatus();
                return;
              }
              if (value == 'signOut') {
                await widget.onSignOut?.call();
                return;
              }
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => value == 'prices'
                      ? PricebookPage(store: store!)
                      : CompanyPage(store: store!),
                ),
              );
              await refresh();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'prices', child: Text('Prisbok')),
              const PopupMenuItem(value: 'company', child: Text('Företagsuppgifter')),
              const PopupMenuItem(
                value: 'sync',
                child: Text('Lagring och synkstatus'),
              ),
              const PopupMenuItem(value: 'about', child: Text('Om denna version')),
              if (isLive)
                const PopupMenuItem(value: 'signOut', child: Text('Logga ut')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xffe5eddb),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                isLive
                    ? 'INLOGGAD ARBETSYTA · Lokal cache · Synkas till molnet'
                    : 'UTVÄRDERINGSVERSION · Lokal data · Ingen serversynk',
                style: TextStyle(fontSize: 11),
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: RefreshIndicator(onRefresh: refresh, child: buildPage()),
            ),
          ],
        ),
      ),
      floatingActionButton: tab == 1
          ? FloatingActionButton.extended(
              onPressed: busy ? null : newQuote,
              icon: const Icon(Icons.add),
              label: const Text('Ny offert'),
            )
          : tab == 2
          ? FloatingActionButton.extended(
              onPressed: busy ? null : newJob,
              icon: const Icon(Icons.add),
              label: const Text('Boka jobb'),
            )
          : tab == 4
          ? FloatingActionButton.extended(
              onPressed: busy ? null : () => editCustomer(),
              icon: const Icon(Icons.add),
              label: const Text('Ny kund'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            label: 'Idag',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            label: 'Offerter',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Schema',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Fakturor',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Kunder',
          ),
        ],
      ),
    );
  }

  Widget title(String heading, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
  Widget list(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
    physics: const AlwaysScrollableScrollPhysics(),
    children: children,
  );
  Widget buildPage() {
    if (customers.isEmpty) {
      return list([
        title(
          'Välkommen till din arbetsyta',
          'Lägg till din första kund för att komma igång.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.people_outline, size: 36),
                const SizedBox(height: 14),
                Text(
                  'Din arbetsyta är redo.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('Kunder, offerter och jobb samlas här när du lägger till dem.'),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: busy ? null : () => editCustomer(),
                  icon: const Icon(Icons.add),
                  label: const Text('Lägg till första kund'),
                ),
              ],
            ),
          ),
        ),
      ]);
    }
    final now = widget.clock?.call()??DateTime.now();
    final todays = jobs
        .where((j) => DateUtils.isSameDay(j.startsAt, now))
        .toList();
    return switch (tab) {
      0 => list([
        title(
          'Din arbetsdag',
          'Din arbetsyta · ${DateFormat('d MMMM', 'sv').format(now)}',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing:16,
              runSpacing:8,
              children: [
                const Text('Dagens jobb klara'),
                Text(
                  '${todays.where((j) => j.status == JobStatus.completed).length} / ${todays.length}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...todays.map(jobCard),
        if (todays.isEmpty) const Text('Inga jobb bokade idag.'),
        const SizedBox(height: 24),
        title('Att följa upp', 'Skickade offerter som väntar på svar'),
        ...quotes.where((q) => q.status == QuoteStatus.sent).map(quoteCard),
      ]),
      1 => list([
        title('Offerter', 'Från första kontakt till nästa uppdrag.'),
        ...quotes.map(quoteCard),
        if (quotes.isEmpty) const Text('Skapa din första offert.'),
      ]),
      2 => list([
        title('Schema', 'Bokningar i datumordning'),
        ...jobs.map(jobCard),
      ]),
      3 => list([
        title('Fakturor', 'Lokala fakturautkast. Inga fakturor har skickats.'),
        if (invoices.isEmpty)
          const Text(
            'Öppna en skickad eller godkänd offert för att skapa ett fakturautkast.',
          ),
        ...invoices.map((i) {
          final q = Quote.fromJson(
            Map<String, dynamic>.from(i['quoteSnapshot'] as Map),
          );
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i['title'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(customerName(i['customerId'] as String)),
                  const SizedBox(height: 12),
                  Text(
                    sek(q.totals.customerPaysOre),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Förfaller ${DateFormat('yyyy-MM-dd').format(DateTime.parse(i['dueAt'] as String))}',
                  ),
                  if (i['status'] == 'paid')
                    const Chip(label: Text('Betald'))
                  else
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Registrera betalning?'),
                                  content: const Text(
                                    'Bekräfta att betalningen faktiskt har mottagits. Detta initierar ingen betalning.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Avbryt'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Registrera'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await store!.put('invoice', {
                                  ...i,
                                  'status': 'paid',
                                  'paidAt': DateTime.now()
                                      .toUtc()
                                      .toIso8601String(),
                                });
                              }
                            }),
                      icon: const Icon(Icons.check),
                      label: const Text('Registrera betalning'),
                    ),
                ],
              ),
            ),
          );
        }),
      ]),
      _ => list([
        title('Kunder', 'Kontaktuppgifter som följer med uppdraget.'),
        ...customers.map(
          (c) => Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(c['name'] as String),
              subtitle: Text(c['address'] as String),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => editCustomer(c),
            ),
          ),
        ),
      ]),
    };
  }

  Widget jobCard(Job job) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('EEE d MMM · HH:mm', 'sv').format(job.startsAt)}–${DateFormat('HH:mm').format(job.endsAt)}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          Text(job.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text('${customerName(job.customerId)}\n${job.address}'),
          const SizedBox(height: 12),
          Wrap(alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,spacing:12,runSpacing:8,
            children: [
              Text(job.assignee),
              if (job.status == JobStatus.completed)
                const Chip(label: Text('Klart'))
              else
                FilledButton.tonal(
                  onPressed: busy ? null : () => openJob(job),
                  child: const Text('Öppna jobb'),
                ),
              if (job.status == JobStatus.completed)
                TextButton(
                  onPressed: () => openJob(job),
                  child: const Text('Visa'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget quoteCard(Quote q) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(18),
      title: Text(q.title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(
        '${customerName(q.customerId)}\n${quoteLabel(q.status)} · ${sek(q.totals.customerPaysOre)}',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openQuote(q),
    ),
  );
  Future<void> openQuote(Quote quote) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                quote.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(customerName(quote.customerId)),
              const SizedBox(height: 16),
              Text('${quoteLabel(quote.status)} · Revision ${quote.revision}'),
              ...quote.lines.map(
                (line) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(line.description),
                  subtitle: Text(
                    '${line.quantityMilli / 1000} × ${sek(line.unitPriceOre)} exkl. moms',
                  ),
                  trailing: Text(sek(line.netOre)),
                ),
              ),
              const Divider(),
              Text('Exkl. moms: ${sek(quote.totals.netOre)}'),
              Text('Moms: ${sek(quote.totals.vatOre)}'),
              Text('Preliminärt avdrag: ${sek(quote.totals.deductionOre)}'),
              const SizedBox(height: 12),
              Text(
                'Att betala: ${sek(quote.totals.customerPaysOre)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'ROT/RUT är en förenklad kalkyl, inte en kontroll av kundens avdragsrätt. Avdragssatsen måste granskas före verklig användning.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 24),
              if (quote.status == QuoteStatus.draft)
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'send'),
                  child: const Text('Markera som skickad lokalt'),
                ),
              if (quote.status == QuoteStatus.sent) ...[
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'accept'),
                  child: const Text('Registrera kundens godkännande'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'decline'),
                  child: const Text('Registrera avböjande'),
                ),
              ],
              if (quote.status == QuoteStatus.sent ||
                  quote.status == QuoteStatus.accepted)
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'schedule'),
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Boka jobb från offerten'),
                ),
              if (quote.status == QuoteStatus.sent ||
                  quote.status == QuoteStatus.accepted)
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'invoice'),
                  child: const Text('Skapa fakturautkast'),
                ),
              const SizedBox(height: 16),
              const Text(
                'Ingen e-post eller extern kundsignering är ansluten i denna version.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'schedule') {
      await newJob(quote: quote);
      return;
    }
    if (action == 'accept') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Registrera godkännande'),
          content: const Text(
            'Detta är en manuell intern registrering. Den verifierar inte kundens identitet och är ingen digital signering. Har kunden godkänt offerten utanför appen?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ja, registrera'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    await run(() async {
      if (action == 'invoice') {
        await store!.createInvoice(quote);
        if (mounted) setState(() => tab = 3);
      } else {
        await store!.transitionQuote(quote, switch (action) {
          'send' => QuoteStatus.sent,
          'accept' => QuoteStatus.accepted,
          _ => QuoteStatus.declined,
        });
      }
    });
  }

  Future<void> newQuote() async {
    final result = await Navigator.of(context).push<Quote>(
      MaterialPageRoute(
        builder: (_) => QuoteEditor(
          customers: customers,
        ),
      ),
    );
    if (result != null) await run(() => store!.put('quote', result.toJson()));
  }

  Future<void> editCustomer([Map<String, dynamic>? customer]) async {
    final values = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => CustomerEditor(customer: customer)),
    );
    if (values != null) await run(() => store!.put('customer', values));
  }

  Future<void> newJob({Quote? quote}) async {
    final result = await Navigator.of(context).push<Job>(
      MaterialPageRoute(
        builder: (_) => JobEditor(
          customers: customers,
          quote: quote,
        ),
      ),
    );
    if (result != null) await run(() => store!.saveJob(result));
  }

  Future<void> openJob(Job job) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => JobWorkspace(store: store!, jobId: job.id),
      ),
    );
    await refresh();
  }

  Future<void> syncStatus() async {
    final count = await store!.pendingCount;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lagring och synkstatus'),
        content: Text(
          isLive
              ? '$count lokala ändringsposter väntar på synkning. Data cachelagras på enheten och bekräftas av molnet när anslutningen fungerar.'
              : '$count lokala ändringsposter.\n\nÄndringarna finns i SQLite på denna enhet. Ingen server är ansluten och inga poster har bekräftats av molnet. Bilder lagras också lokalt. Radera inte appdata om du vill behålla underlaget.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stäng'),
          ),
        ],
      ),
    );
  }

  void about() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Fält · Teknisk förhandsversion'),
      content: Text(
        isLive
          ? 'Flutter för Android och senare iOS.\n\nDen här arbetsytan cachelagras lokalt och synkas med företagets Supabase-projekt när du är inloggad.'
          : 'Flutter för Android och senare iOS.\n\nData lagras på denna enhet i SQLite. Outboxen sparar ändringar men ingen synkarbetare är ansluten.\n\nAnvänd bara exempeldata tills företagsinloggning, skyddad lagring, synk och säkerhetskopiering har levererats.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Stäng'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    final currentStore = store;
    if (currentStore != null) unawaited(_closeOwnedStore(currentStore));
    super.dispose();
  }
}

class QuoteEditor extends StatefulWidget {
  const QuoteEditor({super.key, required this.customers});
  final List<Map<String, dynamic>> customers;
  @override
  State<QuoteEditor> createState() => _QuoteEditorState();
}

class _QuoteEditorState extends State<QuoteEditor> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  final quantity = TextEditingController(text: '1');
  late String customerId = widget.customers.first['id'] as String;
  Deduction deduction = Deduction.rot;
  LineKind kind = LineKind.labour;
  final List<EstimateLine> lines = [];
  String? lineError;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    price.dispose();
    quantity.dispose();
    super.dispose();
  }

  int? decimal(String value, int places) {
    final text = value.trim().replaceAll(',', '.');
    if (!RegExp('^\\d+(?:\\.\\d{1,$places})?\$').hasMatch(text)) return null;
    final parts = text.split('.');
    final scale = places == 2 ? 100 : 1000;
    return int.parse(parts[0]) * scale +
        (parts.length == 2 ? int.parse(parts[1].padRight(places, '0')) : 0);
  }

  void addLine() {
    final p = decimal(price.text, 2), q = decimal(quantity.text, 3);
    if (description.text.trim().isEmpty || p == null || q == null || q <= 0) {
      setState(
        () => lineError =
            'Ange beskrivning, positivt antal och pris med högst två decimaler.',
      );
      return;
    }
    setState(() {
      lines.add(
        EstimateLine(
          description: description.text.trim(),
          unitPriceOre: p,
          quantityMilli: q,
          kind: kind,
        ),
      );
      lineError = null;
      description.clear();
      price.clear();
      quantity.text = '1';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ny offert')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Uppdrag'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Ange uppdrag' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: customerId,
            decoration: const InputDecoration(labelText: 'Kund'),
            items: widget.customers
                .map(
                  (c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(c['name'] as String),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => customerId = v!),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              title.text = 'Standarduppdrag';
              lines.clear();
              lines.addAll([
                EstimateLine(
                  description: 'Arbete',
                  unitPriceOre: 65000,
                  quantityMilli: 6000,
                  kind: LineKind.labour,
                ),
                EstimateLine(
                  description: 'Material',
                  unitPriceOre: 39500,
                  quantityMilli: 6000,
                  kind: LineKind.material,
                ),
              ]);
            }),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Använd standardmall'),
          ),
          const SizedBox(height: 16),
          ...lines.indexed.map(
            (entry) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.$2.description),
              subtitle: Text(
                '${entry.$2.quantityMilli / 1000} × ${sek(entry.$2.unitPriceOre)}',
              ),
              trailing: IconButton(
                tooltip: 'Ta bort rad',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => lines.removeAt(entry.$1)),
              ),
            ),
          ),
          const Divider(),
          const SizedBox(height: 16),
          TextField(
            controller: description,
            decoration: const InputDecoration(
              labelText: 'Beskrivning för ny rad',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Antal'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'À-pris exkl. moms',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LineKind>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: 'Typ'),
            items: const [
              DropdownMenuItem(value: LineKind.labour, child: Text('Arbete')),
              DropdownMenuItem(
                value: LineKind.material,
                child: Text('Material'),
              ),
              DropdownMenuItem(value: LineKind.other, child: Text('Övrigt')),
            ],
            onChanged: (v) => setState(() => kind = v!),
          ),
          if (lineError != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                lineError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextButton.icon(
            onPressed: addLine,
            icon: const Icon(Icons.add),
            label: const Text('Lägg till rad'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Deduction>(
            initialValue: deduction,
            decoration: const InputDecoration(labelText: 'Preliminärt avdrag'),
            items: const [
              DropdownMenuItem(
                value: Deduction.none,
                child: Text('Inget avdrag'),
              ),
              DropdownMenuItem(
                value: Deduction.rot,
                child: Text('ROT 30 % (demoregel)'),
              ),
              DropdownMenuItem(
                value: Deduction.rut,
                child: Text('RUT 50 % (demoregel)'),
              ),
            ],
            onChanged: (v) => setState(() => deduction = v!),
          ),
          const SizedBox(height: 20),
          if (lines.isNotEmpty)
            Text(
              'Att betala: ${sek(EstimateTotals(lines, deduction).customerPaysOre)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              if (lines.isEmpty) {
                setState(() => lineError = 'Lägg till minst en rad.');
                return;
              }
              Navigator.pop(
                context,
                Quote(
                  id: const Uuid().v4(),
                  customerId: customerId,
                  title: title.text.trim(),
                  lines: List.unmodifiable(lines),
                  deduction: deduction,
                ),
              );
            },
            child: const Text('Spara offertutkast'),
          ),
        ],
      ),
    ),
  );
}

class CustomerEditor extends StatefulWidget {
  const CustomerEditor({super.key, this.customer});
  final Map<String, dynamic>? customer;
  @override
  State<CustomerEditor> createState() => _CustomerEditorState();
}

class _CustomerEditorState extends State<CustomerEditor> {
  final form = GlobalKey<FormState>();
  late final fields = {
    for (final k in ['name', 'address', 'phone', 'email'])
      k: TextEditingController(text: widget.customer?[k] as String? ?? ''),
  };
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kunduppgifter')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final entry in {
            'name': 'Namn',
            'address': 'Adress',
            'phone': 'Telefon',
            'email': 'E-post',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                controller: fields[entry.key],
                decoration: InputDecoration(labelText: entry.value),
                keyboardType: entry.key == 'email'
                    ? TextInputType.emailAddress
                    : entry.key == 'phone'
                    ? TextInputType.phone
                    : TextInputType.text,
                validator: (value) {
                  if (entry.key == 'name' && (value ?? '').trim().isEmpty) {
                    return 'Ange namn';
                  }
                  if (entry.key == 'email' &&
                      (value ?? '').isNotEmpty &&
                      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!)) {
                    return 'Ange en giltig e-postadress';
                  }
                  return null;
                },
              ),
            ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, <String, dynamic>{
                  'id': widget.customer?['id'] ?? const Uuid().v4(),
                  for (final e in fields.entries) e.key: e.value.text.trim(),
                });
              }
            },
            child: const Text('Spara kund'),
          ),
        ],
      ),
    ),
  );
}

class JobEditor extends StatefulWidget {
  const JobEditor({super.key, required this.customers, this.quote});
  final List<Map<String, dynamic>> customers;
  final Quote? quote;
  @override
  State<JobEditor> createState() => _JobEditorState();
}

class _JobEditorState extends State<JobEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.quote?.title ?? '');
  late String customerId =
      widget.quote?.customerId ?? widget.customers.first['id'] as String;
  String person = 'Ansvarig';
  DateTime day = DateTime.now();
  TimeOfDay start = const TimeOfDay(hour: 8, minute: 0),
      end = const TimeOfDay(hour: 10, minute: 0);
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Boka jobb')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Uppdrag'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Ange uppdrag' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: customerId,
            decoration: const InputDecoration(labelText: 'Kund'),
            items: widget.customers
                .map(
                  (c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(c['name'] as String),
                  ),
                )
                .toList(),
            onChanged: widget.quote != null
                ? null
                : (v) => setState(() => customerId = v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: person,
            decoration: const InputDecoration(labelText: 'Ansvarig'),
            items: const [
              DropdownMenuItem(value: 'Ansvarig', child: Text('Ansvarig')),
            ],
            onChanged: (v) => setState(() => person = v!),
          ),
          ListTile(
            title: const Text('Dag'),
            subtitle: Text(DateFormat('yyyy-MM-dd').format(day)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final v = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (v != null) setState(() => day = v);
            },
          ),
          ListTile(
            title: const Text('Starttid'),
            subtitle: Text(start.format(context)),
            onTap: () async {
              final v = await showTimePicker(
                context: context,
                initialTime: start,
              );
              if (v != null) setState(() => start = v);
            },
          ),
          ListTile(
            title: const Text('Sluttid'),
            subtitle: Text(end.format(context)),
            onTap: () async {
              final v = await showTimePicker(
                context: context,
                initialTime: end,
              );
              if (v != null) setState(() => end = v);
            },
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              final from = DateTime(
                    day.year,
                    day.month,
                    day.day,
                    start.hour,
                    start.minute,
                  ),
                  to = DateTime(
                    day.year,
                    day.month,
                    day.day,
                    end.hour,
                    end.minute,
                  );
              if (!to.isAfter(from)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sluttiden måste vara efter starttiden.'),
                  ),
                );
                return;
              }
              final c = widget.customers.firstWhere(
                (c) => c['id'] == customerId,
              );
              Navigator.pop(
                context,
                Job(
                  id: const Uuid().v4(),
                  title: title.text.trim(),
                  customerId: customerId,
                  address: c['address'] as String,
                  assignee: person,
                  startsAt: from,
                  endsAt: to,
                  quoteId: widget.quote?.id,
                ),
              );
            },
            child: const Text('Spara bokning'),
          ),
        ],
      ),
    ),
  );
}
