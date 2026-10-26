import 'package:flutter/material.dart';
import '../../data/local_store.dart';

class CompanyPage extends StatefulWidget {
  const CompanyPage({super.key, required this.store});
  final LocalStore store;
  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends State<CompanyPage> {
  final form = GlobalKey<FormState>();
  final labels = {
    'name': 'Företagsnamn',
    'organisation': 'Organisationsnummer',
    'address': 'Adress',
    'email': 'E-post',
    'phone': 'Telefon',
  };
  late final fields = {for (final k in labels.keys) k: TextEditingController()};
  bool loaded = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data =
          await widget.store.get('company', 'local') ??
          {
            'name': 'Ditt företag',
            'organisation': '',
            'address': '',
            'email': '',
            'phone': '',
          };
      for (final e in fields.entries) {
        e.value.text = data[e.key] as String? ?? '';
      }
      if (mounted) setState(() => loaded = true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Företagsuppgifter')),
    body: !loaded
        ? Center(
            child: error != null
                ? Text(error!)
                : const CircularProgressIndicator(),
          )
        : Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Uppgifterna sparas på den här enheten och används i företagets arbetsyta.',
                ),
                const SizedBox(height: 20),
                for (final entry in labels.entries)
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
                      validator: (v) {
                        if (entry.key == 'name' && (v ?? '').trim().isEmpty) {
                          return 'Ange företagsnamn';
                        }
                        if (entry.key == 'email' &&
                            (v ?? '').isNotEmpty &&
                            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v!)) {
                          return 'Ange giltig e-post';
                        }
                        return null;
                      },
                    ),
                  ),
                if (error != null) Text(error!),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) return;
                          setState(() => busy = true);
                          try {
                            await widget.store.put('company', {
                              'id': 'local',
                              for (final e in fields.entries)
                                e.key: e.value.text.trim(),
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Företagsuppgifterna sparades.',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) setState(() => error = '$e');
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: const Text('Spara uppgifter'),
                ),
              ],
            ),
          ),
  );
}
