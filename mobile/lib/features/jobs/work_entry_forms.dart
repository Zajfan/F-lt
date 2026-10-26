import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../domain/job.dart';
import '../../domain/work_log.dart';
import '../../shared/format.dart';

class ChargeSelector extends StatelessWidget {
  const ChargeSelector({
    super.key,
    required this.value,
    required this.approved,
    required this.onChanged,
    required this.onApproval,
  });
  final ChargeType value;
  final bool approved;
  final ValueChanged<ChargeType> onChanged;
  final ValueChanged<bool> onApproval;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<ChargeType>(
        initialValue: value,
        decoration: const InputDecoration(labelText: 'Fakturering'),
        items: const [
          DropdownMenuItem(
            value: ChargeType.included,
            child: Text('Ingår / debiteras inte separat'),
          ),
          DropdownMenuItem(
            value: ChargeType.additional,
            child: Text('Debiteras separat'),
          ),
        ],
        onChanged: (v) => onChanged(v!),
      ),
      if (value == ChargeType.additional)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: approved,
          onChanged: (v) => onApproval(v!),
          title: const Text('Godkänt att fakturera'),
          subtitle: const Text(
            'Intern registrering av kundens besked. Ingen digital signering.',
          ),
        ),
    ],
  );
}

class TimeEntryForm extends StatefulWidget {
  const TimeEntryForm({super.key, required this.job});
  final Job job;
  @override
  State<TimeEntryForm> createState() => _TimeEntryFormState();
}

class _TimeEntryFormState extends State<TimeEntryForm> {
  final form = GlobalKey<FormState>();
  final note = TextEditingController();
  final rate = TextEditingController(text: '650');
  DateTime day = DateTime.now();
  late TimeOfDay end = TimeOfDay.now();
  late TimeOfDay start = TimeOfDay.fromDateTime(
    DateTime.now().subtract(const Duration(hours: 1)),
  );
  late ChargeType charge = widget.job.quoteId == null
      ? ChargeType.additional
      : ChargeType.included;
  bool approved = false;
  @override
  void dispose() {
    note.dispose();
    rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rapportera tid')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Tidrapport för ${widget.job.assignee}'),
          const SizedBox(height: 16),
          TextFormField(
            controller: note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Utfört arbete'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Beskriv arbetet' : null,
          ),
          ListTile(
            title: const Text('Datum'),
            subtitle: Text(DateFormat('yyyy-MM-dd').format(day)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final value = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (value != null && mounted) setState(() => day = value);
            },
          ),
          ListTile(
            title: const Text('Start'),
            subtitle: Text(start.format(context)),
            onTap: () async {
              final value = await showTimePicker(
                context: context,
                initialTime: start,
              );
              if (value != null && mounted) setState(() => start = value);
            },
          ),
          ListTile(
            title: const Text('Slut'),
            subtitle: Text(end.format(context)),
            onTap: () async {
              final value = await showTimePicker(
                context: context,
                initialTime: end,
              );
              if (value != null && mounted) setState(() => end = value);
            },
          ),
          TextFormField(
            controller: rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Timpris exkl. moms'),
            validator: (v) => parseFixed(v ?? '', 2) == null
                ? 'Ange ett giltigt timpris'
                : null,
          ),
          const SizedBox(height: 16),
          ChargeSelector(
            value: charge,
            approved: approved,
            onChanged: (v) => setState(() => charge = v),
            onApproval: (v) => setState(() => approved = v),
          ),
          const SizedBox(height: 20),
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
              if (!to.isAfter(from) || to.isAfter(DateTime.now())) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Ange en avslutad tidsperiod med sluttid efter starttid.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(
                context,
                TimeEntry(
                  id: const Uuid().v4(),
                  jobId: widget.job.id,
                  person: widget.job.assignee,
                  startedAt: from,
                  endedAt: to,
                  hourlyRateOre: parseFixed(rate.text, 2)!,
                  note: note.text.trim(),
                  chargeType: charge,
                  approved: approved,
                ),
              );
            },
            child: const Text('Spara tidrapport'),
          ),
        ],
      ),
    ),
  );
}

class TimerStopData {
  const TimerStopData(this.note, this.rateOre, this.chargeType, this.approved);
  final String note;
  final int rateOre;
  final ChargeType chargeType;
  final bool approved;
}

class TimerStopForm extends StatefulWidget {
  const TimerStopForm({super.key, required this.job});
  final Job job;
  @override
  State<TimerStopForm> createState() => _TimerStopFormState();
}

class _TimerStopFormState extends State<TimerStopForm> {
  final form = GlobalKey<FormState>();
  final note = TextEditingController();
  final rate = TextEditingController(text: '650');
  late ChargeType charge = widget.job.quoteId == null
      ? ChargeType.additional
      : ChargeType.included;
  bool approved = false;
  @override
  void dispose() {
    note.dispose();
    rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stoppa och spara tid')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Timern stoppas när du sparar. Om du går tillbaka fortsätter den.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Utfört arbete'),
            minLines: 2,
            maxLines: 4,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Beskriv arbetet' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Timpris exkl. moms'),
            validator: (v) =>
                parseFixed(v ?? '', 2) == null ? 'Ange giltigt timpris' : null,
          ),
          const SizedBox(height: 16),
          ChargeSelector(
            value: charge,
            approved: approved,
            onChanged: (v) => setState(() => charge = v),
            onApproval: (v) => setState(() => approved = v),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  context,
                  TimerStopData(
                    note.text.trim(),
                    parseFixed(rate.text, 2)!,
                    charge,
                    approved,
                  ),
                );
              }
            },
            child: const Text('Stoppa och spara'),
          ),
        ],
      ),
    ),
  );
}

class MaterialEntryForm extends StatefulWidget {
  const MaterialEntryForm({
    super.key,
    required this.job,
    required this.catalog,
  });
  final Job job;
  final List<Map<String, dynamic>> catalog;
  @override
  State<MaterialEntryForm> createState() => _MaterialEntryFormState();
}

class _MaterialEntryFormState extends State<MaterialEntryForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      quantity = TextEditingController(text: '1'),
      cost = TextEditingController(text: '0'),
      price = TextEditingController(),
      unit = TextEditingController(text: 'st');
  late ChargeType charge = widget.job.quoteId == null
      ? ChargeType.additional
      : ChargeType.included;
  bool approved = false;
  @override
  void dispose() {
    for (final controller in [name, quantity, cost, price, unit]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lägg till material')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.catalog.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Välj ur prisboken'),
              items: widget.catalog
                  .map(
                    (p) => DropdownMenuItem(
                      value: p['id'] as String,
                      child: Text(p['name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                final p = widget.catalog.firstWhere((p) => p['id'] == id);
                setState(() {
                  name.text = p['name'] as String;
                  cost.text = ((p['purchasePriceOre'] as int) / 100)
                      .toStringAsFixed(2);
                  price.text = ((p['sellingPriceOre'] as int) / 100)
                      .toStringAsFixed(2);
                  unit.text = p['unit'] as String;
                });
              },
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Material'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Ange material' : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Antal'),
                  validator: (v) {
                    final n = parseFixed(v ?? '', 3);
                    return n == null || n <= 0 ? 'Ange positivt antal' : null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: unit,
                  decoration: const InputDecoration(labelText: 'Enhet'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Ange enhet' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Inköpspris per enhet exkl. moms',
            ),
            validator: (v) =>
                parseFixed(v ?? '', 2) == null ? 'Ange giltigt pris' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Försäljningspris per enhet exkl. moms',
            ),
            validator: (v) =>
                parseFixed(v ?? '', 2) == null ? 'Ange giltigt pris' : null,
          ),
          const SizedBox(height: 16),
          ChargeSelector(
            value: charge,
            approved: approved,
            onChanged: (v) => setState(() => charge = v),
            onApproval: (v) => setState(() => approved = v),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(
                context,
                MaterialEntry(
                  id: const Uuid().v4(),
                  jobId: widget.job.id,
                  description: name.text.trim(),
                  quantityMilli: parseFixed(quantity.text, 3)!,
                  purchasePriceOre: parseFixed(cost.text, 2)!,
                  sellingPriceOre: parseFixed(price.text, 2)!,
                  unit: unit.text.trim(),
                  chargeType: charge,
                  approved: approved,
                ),
              );
            },
            child: const Text('Spara material'),
          ),
        ],
      ),
    ),
  );
}
