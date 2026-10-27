import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../data/local_store.dart';
import '../../domain/estimate.dart';
import '../../domain/invoice.dart';
import '../../domain/job.dart';
import '../../domain/work_log.dart';
import '../../shared/format.dart';
import '../invoices/invoice_preview_page.dart';
import 'photo_service.dart';
import 'work_entry_forms.dart';

class JobWorkspace extends StatefulWidget {
  const JobWorkspace({super.key, required this.store, required this.jobId});
  final LocalStore store;
  final String jobId;
  @override
  State<JobWorkspace> createState() => _JobWorkspaceState();
}

class _JobWorkspaceState extends State<JobWorkspace>
    with WidgetsBindingObserver {
  Job? job;
  Map<String, dynamic>? customer, timer;
  List<TimeEntry> time = [];
  List<MaterialEntry> materials = [];
  List<Map<String, dynamic>> notes = [], checks = [], photos = [];
  JobBillingPreview? billing;
  Map<String, dynamic>? invoice;
  bool busy = false;
  String? loadError;
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && timer != null) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    try {
      await widget.store.ensureWorkspace(widget.jobId);
      final j = Job.fromJson((await widget.store.get('job', widget.jobId))!);
      final c = await widget.store.get('customer', j.customerId);
      final t = await widget.store.get('timer', 'active');
      final times =
          (await widget.store.forJob(
              'time',
              j.id,
            )).map(TimeEntry.fromJson).toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      final m = (await widget.store.forJob(
        'material',
        j.id,
      )).map(MaterialEntry.fromJson).toList();
      final n = await widget.store.forJob('note', j.id),
          ck = await widget.store.forJob('check', j.id),
          p = await widget.store.forJob('photo', j.id);
      final b = await widget.store.billingPreview(j.id);
      final i = await widget.store.get(
        'invoice',
        j.quoteId == null ? 'invoice-job-${j.id}' : 'invoice-${j.quoteId}',
      );
      if (mounted) {
        setState(() {
          job = j;
          customer = c;
          timer = t;
          time = times;
          materials = m;
          notes = n;
          checks = ck;
          photos = p;
          billing = b;
          invoice = i;
          loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    }
  }

  Future<void> perform(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool get locked => job?.status == JobStatus.completed;
  Widget page(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
    children: children,
  );
  Widget section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  String elapsed() {
    if (timer?['jobId'] != job?.id) return '';
    final duration = DateTime.now().toUtc().difference(
      DateTime.parse(timer!['startedAt'] as String),
    );
    final seconds = duration.inSeconds.clamp(0, 999999999);
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (job == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Arbetsorder')),
        body: Center(
          child: loadError == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(loadError!),
                    TextButton(
                      onPressed: load,
                      child: const Text('Försök igen'),
                    ),
                  ],
                ),
        ),
      );
    }
    final j = job!;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(title: const Text('Arbetsorder')),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      j.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text('${customer?['name'] ?? ''} · ${j.assignee}'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Chip(
                          avatar: Icon(
                            locked ? Icons.task_alt : Icons.work_outline,
                            size: 16,
                          ),
                          label: Text(switch (j.status) {
                            JobStatus.scheduled => 'Planerat',
                            JobStatus.inProgress => 'Pågående',
                            JobStatus.completed => 'Avslutat',
                          }),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Sparat på enheten',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    if (timer?['jobId'] == j.id)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xff154c3e),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              color: Color(0xffbcec8d),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                elapsed(),
                                style: const TextStyle(
                                  fontSize: 22,
                                  color: Colors.white,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            FilledButton(
                              onPressed: busy ? null : stopTimer,
                              child: const Text('Stoppa'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Översikt'),
                  Tab(text: 'Tid'),
                  Tab(text: 'Material'),
                  Tab(text: 'Underlag'),
                  Tab(text: 'Fakturering'),
                ],
              ),
              if (busy) const LinearProgressIndicator(),
              if (loadError != null)
                MaterialBanner(
                  content: Text(loadError!),
                  actions: [
                    TextButton(
                      onPressed: load,
                      child: const Text('Försök igen'),
                    ),
                  ],
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    overview(),
                    timePage(),
                    materialPage(),
                    documents(),
                    billingPage(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget overview() {
    final j = job!;
    return page([
      section('Kund och plats', [
        Text(customer?['name'] as String? ?? ''),
        const SizedBox(height: 5),
        Text(j.address),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => openUri(
                Uri(scheme: 'tel', path: customer?['phone'] as String? ?? ''),
              ),
              icon: const Icon(Icons.call_outlined),
              label: const Text('Ring'),
            ),
            OutlinedButton.icon(
              onPressed: () => openUri(
                Uri.https('www.google.com', '/maps/search/', {
                  'api': '1',
                  'query': j.address,
                }),
              ),
              icon: const Icon(Icons.near_me_outlined),
              label: const Text('Hitta hit'),
            ),
            OutlinedButton.icon(
              onPressed: () => openUri(
                Uri(
                  scheme: 'mailto',
                  path: customer?['email'] as String? ?? '',
                ),
              ),
              icon: const Icon(Icons.mail_outline),
              label: const Text('Mejla'),
            ),
          ],
        ),
        Text(
          '${DateFormat('d MMM HH:mm', 'sv').format(j.startsAt)}–${DateFormat('HH:mm').format(j.endsAt)}',
        ),
      ]),
      section('Instruktioner', [
        Text(
          j.instructions.isEmpty
              ? 'Inga instruktioner ännu. Lägg till omfattning, åtkomst och sådant kollegan behöver veta.'
              : j.instructions,
        ),
        if (!locked)
          TextButton.icon(
            onPressed: busy ? null : editInstructions,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Ändra instruktioner'),
          ),
      ]),
      section(
        'Checklista · ${checks.where((c) => c['checked'] == true).length}/${checks.length}',
        [
          const Text(
            'Intern arbetschecklista. Anpassa punkterna efter uppdragets krav och företagets rutiner.',
            style: TextStyle(fontSize: 12),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: checks.isEmpty
                  ? 0
                  : checks.where((c) => c['checked'] == true).length /
                        checks.length,
              minHeight: 5,
              backgroundColor: const Color(0xffe0e4d5),
              color: const Color(0xff99cd73),
            ),
          ),
          const SizedBox(height: 8),
          ...checks.map(
            (c) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(c['label'] as String),
              subtitle: c['required'] == true
                  ? const Text('Krävs för att avsluta')
                  : null,
              value: c['checked'] as bool,
              onChanged: locked || busy
                  ? null
                  : (v) => perform(
                      () => widget.store.addJobRecord('check', {
                        ...c,
                        'checked': v,
                        'checkedAt': DateTime.now().toUtc().toIso8601String(),
                      }),
                    ),
            ),
          ),
          if (!locked)
            TextButton.icon(
              onPressed: busy ? null : addCheck,
              icon: const Icon(Icons.add),
              label: const Text('Lägg till kontrollpunkt'),
            ),
        ],
      ),
      if (j.status == JobStatus.scheduled)
        FilledButton.icon(
          onPressed: busy
              ? null
              : () => perform(
                  () =>
                      widget.store.saveJob(j.withStatus(JobStatus.inProgress)),
                ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Starta jobbet'),
        ),
      if (j.status == JobStatus.inProgress) ...[
        if (timer == null)
          FilledButton.icon(
            onPressed: busy
                ? null
                : () => perform(() => widget.store.startTimer(j.id)),
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Starta tidtagning'),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : finish,
          icon: const Icon(Icons.task_alt),
          label: const Text('Avsluta jobbet'),
        ),
      ],
      if (locked)
        const Text(
          'Jobbet är avslutat och arbetsunderlaget är låst. Granska faktureringsfliken för att skapa underlaget.',
        ),
    ]);
  }

  Widget timePage() => page([
    section('Rapporterad tid', [
      Text(
        '${time.fold<int>(0, (sum, t) => sum + t.minutes)} minuter totalt',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Påbörjade minuter avrundas uppåt per rapport. Timern fortsätter även om appen stängs.',
        style: TextStyle(fontSize: 12),
      ),
      if (!locked)
        Wrap(
          spacing: 8,
          children: [
            if (timer == null && job!.status == JobStatus.inProgress)
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => perform(() => widget.store.startTimer(job!.id)),
                icon: const Icon(Icons.timer),
                label: const Text('Starta timer'),
              ),
            OutlinedButton.icon(
              onPressed: busy ? null : addTime,
              icon: const Icon(Icons.add),
              label: const Text('Rapportera tid'),
            ),
          ],
        ),
      if (timer != null && timer!['jobId'] != job!.id)
        const Text(
          'En timer kör på ett annat jobb. Stoppa den där innan du startar en ny.',
        ),
    ]),
    ...time.map(
      (t) => section('${t.minutes} min · ${t.person}', [
        Text(t.note),
        Text(
          '${DateFormat('d MMM HH:mm', 'sv').format(t.startedAt.toLocal())}–${DateFormat('HH:mm').format(t.endedAt.toLocal())}',
        ),
        Text('${money(t.hourlyRateOre)}/tim · ${money(t.netOre)} exkl. moms'),
        chargeStatus('time', t.id, t.chargeType, t.approved, t.invoiceId),
      ]),
    ),
    if (time.isEmpty) const Text('Ingen tid rapporterad ännu.'),
  ]);
  Widget materialPage() => page([
    section('Material på jobbet', [
      Text(
        'Inköpskostnad ${money(materials.fold(0, (sum, m) => sum + m.costOre))} exkl. moms',
      ),
      const SizedBox(height: 8),
      const Text(
        'Spara vad som faktiskt använts. Markera om det ingår i offerten eller ska faktureras separat.',
      ),
      if (!locked)
        FilledButton.icon(
          onPressed: busy ? null : addMaterial,
          icon: const Icon(Icons.add),
          label: const Text('Lägg till material'),
        ),
    ]),
    ...materials.map(
      (m) => section(m.description, [
        Text(
          '${m.quantityMilli / 1000} ${m.unit} · ${money(m.sellingPriceOre)}/${m.unit}',
        ),
        Text('Försäljning ${money(m.netOre)} · inköp ${money(m.costOre)}'),
        chargeStatus('material', m.id, m.chargeType, m.approved, m.invoiceId),
      ]),
    ),
    if (materials.isEmpty) const Text('Inget material registrerat ännu.'),
  ]);
  Widget chargeStatus(
    String kind,
    String id,
    ChargeType type,
    bool approved,
    String? invoiceId,
  ) {
    if (invoiceId != null) {
      return const Chip(label: Text('Med på fakturautkast'));
    }
    if (type == ChargeType.included) {
      return const Chip(label: Text('Ingår i offert / debiteras inte separat'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chip(
          label: Text(
            approved
                ? 'Godkänt för fakturering'
                : 'Tillägg · väntar på godkännande',
          ),
        ),
        if (!approved)
          TextButton(
            onPressed: busy ? null : () => approve(kind, id),
            child: const Text('Registrera godkännande'),
          ),
      ],
    );
  }

  Widget documents() => page([
    if (!locked)
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : addNote,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Anteckning'),
          ),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => perform(
                    () => PhotoService(
                      widget.store,
                    ).pick(job!.id, ImageSource.camera),
                  ),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Kamera'),
          ),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => perform(
                    () => PhotoService(
                      widget.store,
                    ).pick(job!.id, ImageSource.gallery),
                  ),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Bild från galleri'),
          ),
        ],
      ),
    const SizedBox(height: 16),
    ...notes.map(
      (n) => section(
        DateFormat(
          'd MMM HH:mm',
          'sv',
        ).format(DateTime.parse(n['createdAt'] as String).toLocal()),
        [Text(n['text'] as String)],
      ),
    ),
    ...photos.map(
      (p) => section('Bilddokumentation', [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(p['path'] as String),
            height: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) => const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Bildfilen saknas på denna enhet.'),
            ),
          ),
        ),
        if ((p['caption'] as String? ?? '').isNotEmpty)
          Text(p['caption'] as String),
        if (!locked)
          TextButton(
            onPressed: busy ? null : () => caption(p),
            child: const Text('Ändra bildtext'),
          ),
      ]),
    ),
    if (notes.isEmpty && photos.isEmpty)
      const Text(
        'Lägg till bilder och anteckningar så att nästa person kan följa arbetet.',
      ),
    const SizedBox(height: 16),
    const Text(
      'Bilder sparas på denna enhet. Molnlagring och delning är ännu inte anslutna.',
      style: TextStyle(fontSize: 12),
    ),
  ]);
  Widget billingPage() {
    final b = billing!;
    return page([
      section('Granska fakturaunderlag', [
        Text(
          job!.quoteId == null
              ? 'Löpande räkning: godkända debiterbara rader.'
              : 'Fast offert: offertrader plus godkända tillägg.',
        ),
        const SizedBox(height: 10),
        const Text(
          'Tid och material som ingår i offerten läggs inte på en gång till.',
          style: TextStyle(fontSize: 12),
        ),
        ...b.lines.map(
          (l) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.description),
            trailing: Text(money(l.netOre)),
          ),
        ),
        if (b.totals != null) ...[
          const Divider(),
          Text('Exkl. moms ${money(b.totals!.netOre)}'),
          Text('Moms ${money(b.totals!.vatOre)}'),
          Text('Preliminärt avdrag −${money(b.totals!.deductionOre)}'),
          const SizedBox(height: 10),
          Text(
            'Att betala ${money(b.totals!.customerPaysOre)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
        if (b.pendingApproval > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${b.pendingApproval} tillägg väntar på godkännande. Registrera svaret under Tid eller Material före fakturering.',
            ),
          ),
        if (invoice != null) ...[
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Fakturautkast finns redan.'),
          ),
          OutlinedButton.icon(
            onPressed: previewInvoice,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Förhandsvisa faktura'),
          ),
        ]
        else if (!locked)
          ...[
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Avsluta jobbet för att skapa fakturautkastet.'),
            ),
            if (b.lines.isNotEmpty)
              OutlinedButton.icon(
                onPressed: previewInvoice,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Förhandsvisa faktura'),
              ),
          ]
        else
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: FilledButton.icon(
              onPressed: busy || b.pendingApproval > 0 || b.lines.isEmpty
                  ? null
                  : createInvoice,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Skapa fakturautkast'),
            ),
          ),
      ]),
      const Text(
        'Detta är ett lokalt utkast. Granska avdrag och moms före användning. Ingen faktura skickas eller bokförs här.',
        style: TextStyle(fontSize: 12),
      ),
    ]);
  }

  Future<void> openUri(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Ingen app kunde öppna länken.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<String?> textInput(
    String heading, {
    String initial = '',
    String hint = '',
    bool allowEmpty = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(heading),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (allowEmpty || value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Spara'),
          ),
        ],
      ),
    );
    // Route transitions may still reference the controller during dismissal.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    return result;
  }

  Future<void> editInstructions() async {
    final v = await textInput(
      'Instruktioner',
      initial: job!.instructions,
      allowEmpty: true,
    );
    if (v != null) {
      await perform(() => widget.store.saveJob(job!.copyWith(instructions: v)));
    }
  }

  Future<void> addCheck() async {
    final v = await textInput('Ny kontrollpunkt');
    if (v != null) {
      await perform(
        () => widget.store.addJobRecord('check', {
          'id': const Uuid().v4(),
          'jobId': job!.id,
          'label': v,
          'required': true,
          'checked': false,
        }),
      );
    }
  }

  Future<void> addNote() async {
    final v = await textInput(
      'Intern anteckning',
      hint: 'Vad behöver kollegan eller kontoret veta?',
    );
    if (v != null) {
      await perform(
        () => widget.store.addJobRecord('note', {
          'id': const Uuid().v4(),
          'jobId': job!.id,
          'text': v,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    }
  }

  Future<void> caption(Map<String, dynamic> p) async {
    final v = await textInput(
      'Bildtext',
      initial: p['caption'] as String? ?? '',
      allowEmpty: true,
    );
    if (v != null) {
      await perform(
        () => widget.store.addJobRecord('photo', {...p, 'caption': v}),
      );
    }
  }

  Future<void> addTime() async {
    final entry = await Navigator.push<TimeEntry>(
      context,
      MaterialPageRoute(builder: (_) => TimeEntryForm(job: job!)),
    );
    if (entry != null) await perform(() => widget.store.saveTime(entry));
  }

  Future<void> addMaterial() async {
    final catalog = await widget.store.list('price');
    if (!mounted) return;
    final entry = await Navigator.push<MaterialEntry>(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialEntryForm(job: job!, catalog: catalog),
      ),
    );
    if (entry != null) await perform(() => widget.store.saveMaterial(entry));
  }

  Future<void> stopTimer() async {
    final data = await Navigator.push<TimerStopData>(
      context,
      MaterialPageRoute(builder: (_) => TimerStopForm(job: job!)),
    );
    if (data != null) {
      await perform(
        () => widget.store.stopTimer(
          expectedJobId: job!.id,
          note: data.note,
          hourlyRateOre: data.rateOre,
          chargeType: data.chargeType,
          approved: data.approved,
        ),
      );
    }
  }

  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bekräfta'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> approve(String kind, String id) async {
    if (await confirm(
      'Registrera kundens godkännande',
      'Har kunden godkänt tillägget utanför appen? Detta är en intern notering, inte en identitetskontroll eller digital signering.',
    )) {
      await perform(() => widget.store.approveCharge(kind, id));
    }
  }

  Future<void> finish() async {
    if (await confirm(
      'Avsluta jobbet?',
      'Kontrollera att tid, material och dokumentation är registrerade. Arbetsunderlaget låses när jobbet avslutas.',
    )) {
      await perform(
        () => widget.store.saveJob(job!.withStatus(JobStatus.completed)),
      );
    }
  }

  Future<void> createInvoice() async {
    if (await confirm(
      'Skapa fakturautkast?',
      'Raderna sparas som en låst ögonblicksbild. Detta skickar ingen faktura.',
    )) {
      await perform(() async {
        await widget.store.createJobInvoice(job!.id);
      });
    }
  }

  Future<void> previewInvoice() async {
    try {
      final company = await widget.store.get('company', 'local');
      final selected = invoice;
      final document = selected == null
          ? InvoiceDocument.draft(
              invoiceId: 'invoice-job-${job!.id}',
              title: job!.title,
              quote: Quote(
                id: 'job-${job!.id}',
                customerId: job!.customerId,
                title: job!.title,
                lines: billing!.lines,
                deduction: billing!.deduction,
              ),
              customer: customer,
              company: company,
            )
          : InvoiceDocument.fromRecord(
              selected,
              customerFallback: customer,
              companyFallback: company,
            );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InvoicePreviewPage(document: document),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fakturan kunde inte förhandsvisas.')),
        );
      }
    }
  }
}
