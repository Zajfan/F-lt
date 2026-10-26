import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../data/local_store.dart';
import '../../shared/format.dart';

class PricebookPage extends StatefulWidget {
  const PricebookPage({super.key, required this.store});
  final LocalStore store;
  @override
  State<PricebookPage> createState() => _PricebookPageState();
}

class _PricebookPageState extends State<PricebookPage> {
  List<Map<String, dynamic>> prices = [];
  String search = '';
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final list = await widget.store.list('price');
      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      if (mounted) {
        setState(() {
          prices = list;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> edit([Map<String, dynamic>? price]) async {
    final value = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => PriceEditor(price: price)),
    );
    if (value != null) {
      await widget.store.put('price', value);
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Prisbok')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => edit(),
      icon: const Icon(Icons.add),
      label: const Text('Ny artikel'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Sök material eller artikel',
            ),
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        if (error != null) Text(error!),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              const Text(
                'Priser exklusive moms. Ändringar påverkar nya rader, inte sparade offerter eller materialrapporter.',
              ),
              const SizedBox(height: 12),
              ...prices
                  .where(
                    (p) => (p['name'] as String).toLowerCase().contains(
                      search.toLowerCase(),
                    ),
                  )
                  .map(
                    (p) => Card(
                      child: ListTile(
                        title: Text(p['name'] as String),
                        subtitle: Text(
                          'Inköp ${money(p['purchasePriceOre'] as int)} · ${p['unit']}',
                        ),
                        trailing: Text(money(p['sellingPriceOre'] as int)),
                        onTap: () => edit(p),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PriceEditor extends StatefulWidget {
  const PriceEditor({super.key, this.price});
  final Map<String, dynamic>? price;
  @override
  State<PriceEditor> createState() => _PriceEditorState();
}

class _PriceEditorState extends State<PriceEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.price?['name'] as String? ?? '',
  );
  late final unit = TextEditingController(
    text: widget.price?['unit'] as String? ?? 'st',
  );
  late final cost = TextEditingController(
    text: ((widget.price?['purchasePriceOre'] as int? ?? 0) / 100)
        .toStringAsFixed(2),
  );
  late final price = TextEditingController(
    text: ((widget.price?['sellingPriceOre'] as int? ?? 0) / 100)
        .toStringAsFixed(2),
  );
  @override
  void dispose() {
    for (final c in [name, unit, cost, price]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.price == null ? 'Ny artikel' : 'Ändra artikel'),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Artikel'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Ange namn' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: unit,
            decoration: const InputDecoration(labelText: 'Enhet'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Ange enhet' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Inköpspris exkl. moms',
            ),
            validator: (v) =>
                parseFixed(v ?? '', 2) == null ? 'Ange giltigt pris' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Försäljningspris exkl. moms',
            ),
            validator: (v) =>
                parseFixed(v ?? '', 2) == null ? 'Ange giltigt pris' : null,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, <String, dynamic>{
                  'id': widget.price?['id'] ?? const Uuid().v4(),
                  'name': name.text.trim(),
                  'unit': unit.text.trim(),
                  'purchasePriceOre': parseFixed(cost.text, 2)!,
                  'sellingPriceOre': parseFixed(price.text, 2)!,
                });
              }
            },
            child: const Text('Spara artikel'),
          ),
        ],
      ),
    ),
  );
}
