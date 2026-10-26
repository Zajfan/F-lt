import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'data/local_store.dart';
import 'domain/estimate.dart';
import 'domain/job.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FaltApp());
}

class FaltApp extends StatelessWidget {
  const FaltApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fält', debugShowCheckedModeBanner: false,
    locale: const Locale('sv'), supportedLocales: const [Locale('sv')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff244e3e)),
      scaffoldBackgroundColor: const Color(0xfff5f6f0),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff5f6f0))),
    home: const Workspace(),
  );
}
String sek(int ore) => NumberFormat.currency(locale:'sv_SE',symbol:'kr').format(ore/100);
String quoteLabel(QuoteStatus status) => switch(status) {
  QuoteStatus.draft => 'Utkast', QuoteStatus.sent => 'Skickad',
  QuoteStatus.accepted => 'Godkänd', QuoteStatus.declined => 'Avböjd',
};

class Workspace extends StatefulWidget {
  const Workspace({super.key});
  @override
  State<Workspace> createState() => _WorkspaceState();
}
class _WorkspaceState extends State<Workspace> {
  LocalStore? store;
  String? error;
  int tab = 0;
  bool busy = false;
  List<Job> jobs = [];
  List<Quote> quotes = [];
  List<Map<String,dynamic>> customers = [], invoices = [];
  @override
  void initState() { super.initState(); initialize(); }
  Future<void> initialize() async {
    try {
      store = await LocalStore.open();
      await store!.seedDemo();
      await refresh();
    } catch (e) { if(mounted) setState(() => error = 'Det gick inte att öppna den lokala databasen. $e'); }
  }
  Future<void> refresh() async {
    final j = await store!.list('job');
    final q = await store!.list('quote');
    final c = await store!.list('customer');
    final i = await store!.list('invoice');
    if (!mounted) return;
    setState(() {
      jobs = j.map(Job.fromJson).toList()..sort((a,b)=>a.startsAt.compareTo(b.startsAt));
      quotes = q.map(Quote.fromJson).toList(); customers = c; invoices = i;
    });
  }
  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    setState(()=>busy=true);
    try { await operation(); await refresh(); }
    catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
    finally { if(mounted) setState(()=>busy=false); }
  }
  String customerName(String id) => customers.where((c)=>c['id']==id).firstOrNull?['name'] as String? ?? 'Okänd kund';
  @override
  Widget build(BuildContext context) {
    if(error != null) return Scaffold(body:SafeArea(child:Center(child:Padding(
      padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(error!),const SizedBox(height:16),FilledButton(onPressed:(){setState(()=>error=null);initialize();},child:const Text('Försök igen'))])))));
    if(store == null || customers.isEmpty) return const Scaffold(body:Center(child:CircularProgressIndicator()));
    return Scaffold(
      appBar:AppBar(title:const Text('fält.',style:TextStyle(fontWeight:FontWeight.w800,fontSize:30)),
        actions:[IconButton(tooltip:'Om denna version',onPressed:about,icon:const Icon(Icons.info_outline))]),
      body:SafeArea(child:Column(children:[
        Container(width:double.infinity,color:const Color(0xffe5eddb),padding:const EdgeInsets.symmetric(horizontal:20,vertical:10),
          child:const Text('UTVÄRDERINGSVERSION · Lokal data · Ingen serversynk',style:TextStyle(fontSize:11))),
        if(busy) const LinearProgressIndicator(),
        Expanded(child:RefreshIndicator(onRefresh:refresh,child:buildPage())),
      ])),
      floatingActionButton: tab==1 ? FloatingActionButton.extended(onPressed:busy?null:newQuote,icon:const Icon(Icons.add),label:const Text('Ny offert'))
        : tab==2 ? FloatingActionButton.extended(onPressed:busy?null:newJob,icon:const Icon(Icons.add),label:const Text('Boka jobb'))
        : tab==4 ? FloatingActionButton.extended(onPressed:busy?null:()=>editCustomer(),icon:const Icon(Icons.add),label:const Text('Ny kund')) : null,
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(value)=>setState(()=>tab=value),destinations:const[
        NavigationDestination(icon:Icon(Icons.today_outlined),label:'Idag'),
        NavigationDestination(icon:Icon(Icons.description_outlined),label:'Offerter'),
        NavigationDestination(icon:Icon(Icons.calendar_month_outlined),label:'Schema'),
        NavigationDestination(icon:Icon(Icons.receipt_long_outlined),label:'Fakturor'),
        NavigationDestination(icon:Icon(Icons.people_outline),label:'Kunder'),
      ]),
    );
  }
  Widget title(String heading,String description) => Padding(padding:const EdgeInsets.only(bottom:24),child:Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[Text(heading,style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.w700)),
      const SizedBox(height:8),Text(description,style:Theme.of(context).textTheme.bodyMedium)]));
  Widget list(List<Widget> children) => ListView(padding:const EdgeInsets.fromLTRB(20,24,20,100),physics:const AlwaysScrollableScrollPhysics(),children:children);
  Widget buildPage() {
    final now=DateTime.now();
    final todays=jobs.where((j)=>DateUtils.isSameDay(j.startsAt,now)).toList();
    return switch(tab) {
      0=>list([title('Din arbetsdag','Lindqvist El · ${DateFormat('d MMMM','sv').format(now)}'),
        Card(child:Padding(padding:const EdgeInsets.all(20),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          const Text('Dagens jobb klara'),Text('${todays.where((j)=>j.status==JobStatus.completed).length} / ${todays.length}',style:Theme.of(context).textTheme.headlineSmall)]))),
        const SizedBox(height:20),...todays.map(jobCard),if(todays.isEmpty) const Text('Inga jobb bokade idag.'),
        const SizedBox(height:24),title('Att följa upp','Skickade offerter som väntar på svar'),
        ...quotes.where((q)=>q.status==QuoteStatus.sent).map(quoteCard)]),
      1=>list([title('Offerter','Från första kontakt till nästa uppdrag.'),...quotes.map(quoteCard),if(quotes.isEmpty) const Text('Skapa din första offert.')]),
      2=>list([title('Schema','Bokningar i datumordning · Erik och Nora'),...jobs.map(jobCard)]),
      3=>list([title('Fakturor','Lokala fakturautkast. Inga fakturor har skickats.'),
        if(invoices.isEmpty) const Text('Öppna en skickad eller godkänd offert för att skapa ett fakturautkast.'),
        ...invoices.map((i) { final q=Quote.fromJson(Map<String,dynamic>.from(i['quoteSnapshot'] as Map)); return Card(child:Padding(
          padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(i['title'] as String,style:Theme.of(context).textTheme.titleMedium),Text(customerName(i['customerId'] as String)),
            const SizedBox(height:12),Text(sek(q.totals.customerPaysOre),style:Theme.of(context).textTheme.headlineSmall),
            Text('Förfaller ${DateFormat('yyyy-MM-dd').format(DateTime.parse(i['dueAt'] as String))}'),
            if(i['status']=='paid') const Chip(label:Text('Betald')) else TextButton.icon(onPressed:busy?null:()=>run(() async {
              final confirm=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('Registrera betalning?'),
                content:const Text('Bekräfta att betalningen faktiskt har mottagits. Detta initierar ingen betalning.'),actions:[
                  TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Avbryt')),
                  FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Registrera'))]));
              if(confirm==true) await store!.put('invoice',{...i,'status':'paid','paidAt':DateTime.now().toUtc().toIso8601String()});
            }),icon:const Icon(Icons.check),label:const Text('Registrera betalning')),
          ])));
        })]),
      _=>list([title('Kunder','Kontaktuppgifter som följer med uppdraget.'),...customers.map((c)=>Card(child:ListTile(
        leading:const CircleAvatar(child:Icon(Icons.person_outline)),title:Text(c['name'] as String),subtitle:Text(c['address'] as String),
        trailing:const Icon(Icons.chevron_right),onTap:()=>editCustomer(c))))]),
    };
  }
  Widget jobCard(Job job) => Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('${DateFormat('EEE d MMM · HH:mm','sv').format(job.startsAt)}–${DateFormat('HH:mm').format(job.endsAt)}',style:Theme.of(context).textTheme.labelLarge),
    const SizedBox(height:12),Text(job.title,style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:5),Text('${customerName(job.customerId)}\n${job.address}'),
    const SizedBox(height:12),Row(children:[const Icon(Icons.person_outline,size:18),const SizedBox(width:6),Text(job.assignee),const Spacer(),
      if(job.status==JobStatus.completed) const Chip(label:Text('Klart'))
      else FilledButton.tonal(onPressed:busy?null:()=>run(()=>store!.saveJob(job.withStatus(job.status==JobStatus.scheduled?JobStatus.inProgress:JobStatus.completed))),
        child:Text(job.status==JobStatus.scheduled?'Starta jobb':'Markera klart')),
    ])])));
  Widget quoteCard(Quote q) => Card(child:ListTile(contentPadding:const EdgeInsets.all(18),
    title:Text(q.title,style:Theme.of(context).textTheme.titleMedium),
    subtitle:Text('${customerName(q.customerId)}\n${quoteLabel(q.status)} · ${sek(q.totals.customerPaysOre)}'),
    isThreeLine:true,trailing:const Icon(Icons.chevron_right),onTap:()=>openQuote(q)));
  Future<void> openQuote(Quote quote) async {
    final action=await showModalBottomSheet<String>(context:context,isScrollControlled:true,useSafeArea:true,
      builder:(context)=>SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(24),child:Column(
        crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
          Text(quote.title,style:Theme.of(context).textTheme.headlineSmall),Text(customerName(quote.customerId)),
          const SizedBox(height:16),Text('${quoteLabel(quote.status)} · Revision ${quote.revision}'),
          ...quote.lines.map((line)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(line.description),
            subtitle:Text('${line.quantityMilli/1000} × ${sek(line.unitPriceOre)} exkl. moms'),trailing:Text(sek(line.netOre)))),
          const Divider(),Text('Exkl. moms: ${sek(quote.totals.netOre)}'),Text('Moms: ${sek(quote.totals.vatOre)}'),
          Text('Preliminärt avdrag: ${sek(quote.totals.deductionOre)}'),const SizedBox(height:12),
          Text('Att betala: ${sek(quote.totals.customerPaysOre)}',style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:12),const Text('ROT/RUT är en förenklad kalkyl, inte en kontroll av kundens avdragsrätt. Avdragssatsen måste granskas före verklig användning.',style:TextStyle(fontSize:12)),
          const SizedBox(height:24),
          if(quote.status==QuoteStatus.draft) FilledButton(onPressed:()=>Navigator.pop(context,'send'),child:const Text('Markera som skickad lokalt')),
          if(quote.status==QuoteStatus.sent) ...[
            OutlinedButton(onPressed:()=>Navigator.pop(context,'accept'),child:const Text('Registrera kundens godkännande')),
            TextButton(onPressed:()=>Navigator.pop(context,'decline'),child:const Text('Registrera avböjande')),
          ],
          if(quote.status==QuoteStatus.sent || quote.status==QuoteStatus.accepted)
            FilledButton(onPressed:()=>Navigator.pop(context,'invoice'),child:const Text('Skapa fakturautkast')),
          const SizedBox(height:16),const Text('Ingen e-post eller extern kundsignering är ansluten i denna version.',style:TextStyle(fontSize:12)),
        ]))));
    if(action==null || !mounted) return;
    if(action=='accept') {
      final confirm=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('Registrera godkännande'),
        content:const Text('Detta är en manuell intern registrering. Den verifierar inte kundens identitet och är ingen digital signering. Har kunden godkänt offerten utanför appen?'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Avbryt')),
          FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Ja, registrera'))]));
      if(confirm!=true) return;
    }
    await run(() async {
      if(action=='invoice') { await store!.createInvoice(quote); if(mounted)setState(()=>tab=3); }
      else { await store!.transitionQuote(quote,switch(action){'send'=>QuoteStatus.sent,'accept'=>QuoteStatus.accepted,_=>QuoteStatus.declined}); }
    });
  }
  Future<void> newQuote() async {
    final result=await Navigator.of(context).push<Quote>(MaterialPageRoute(builder:(_)=>QuoteEditor(customers:customers)));
    if(result!=null) await run(()=>store!.put('quote',result.toJson()));
  }
  Future<void> editCustomer([Map<String,dynamic>? customer]) async {
    final values=await Navigator.of(context).push<Map<String,dynamic>>(MaterialPageRoute(builder:(_)=>CustomerEditor(customer:customer)));
    if(values!=null) await run(()=>store!.put('customer',values));
  }
  Future<void> newJob() async {
    final result=await Navigator.of(context).push<Job>(MaterialPageRoute(builder:(_)=>JobEditor(customers:customers)));
    if(result!=null) await run(()=>store!.saveJob(result));
  }
  void about() => showDialog<void>(context:context,builder:(context)=>AlertDialog(
    title:const Text('Fält · Teknisk förhandsversion'),content:const Text('Flutter för Android och senare iOS.\n\nData lagras på denna enhet i SQLite. Outboxen sparar ändringar men ingen synkarbetare är ansluten.\n\nAnvänd bara exempeldata tills företagsinloggning, skyddad lagring, synk och säkerhetskopiering har levererats.'),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Stäng'))]));
}

class QuoteEditor extends StatefulWidget {
  const QuoteEditor({super.key,required this.customers});
  final List<Map<String,dynamic>> customers;
  @override State<QuoteEditor> createState()=>_QuoteEditorState();
}
class _QuoteEditorState extends State<QuoteEditor> {
  final form=GlobalKey<FormState>();
  final title=TextEditingController();
  final description=TextEditingController();
  final price=TextEditingController();
  final quantity=TextEditingController(text:'1');
  late String customerId=widget.customers.first['id'] as String;
  Deduction deduction=Deduction.rot;
  LineKind kind=LineKind.labour;
  final List<EstimateLine> lines=[];
  String? lineError;
  @override void dispose(){title.dispose();description.dispose();price.dispose();quantity.dispose();super.dispose();}
  int? decimal(String value,int places) {
    final text=value.trim().replaceAll(',','.');
    if(!RegExp('^\\d+(?:\\.\\d{1,$places})?\$').hasMatch(text)) return null;
    final parts=text.split('.');final scale=places==2?100:1000;
    return int.parse(parts[0])*scale+(parts.length==2?int.parse(parts[1].padRight(places,'0')):0);
  }
  void addLine(){
    final p=decimal(price.text,2),q=decimal(quantity.text,3);
    if(description.text.trim().isEmpty || p==null || q==null || q<=0){setState(()=>lineError='Ange beskrivning, positivt antal och pris med högst två decimaler.');return;}
    setState((){lines.add(EstimateLine(description:description.text.trim(),unitPriceOre:p,quantityMilli:q,kind:kind));lineError=null;description.clear();price.clear();quantity.text='1';});
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Ny offert')),body:Form(key:form,child:ListView(
    padding:const EdgeInsets.all(20),children:[
      TextFormField(controller:title,decoration:const InputDecoration(labelText:'Uppdrag'),validator:(v)=>(v??'').trim().isEmpty?'Ange uppdrag':null),const SizedBox(height:16),
      DropdownButtonFormField<String>(initialValue:customerId,decoration:const InputDecoration(labelText:'Kund'),items:widget.customers.map((c)=>DropdownMenuItem(value:c['id'] as String,child:Text(c['name'] as String))).toList(),onChanged:(v)=>setState(()=>customerId=v!)),
      const SizedBox(height:16),OutlinedButton.icon(onPressed:()=>setState((){title.text='Spotlights kök';lines.clear();lines.addAll([
        EstimateLine(description:'Elektriker, arbete',unitPriceOre:65000,quantityMilli:6000,kind:LineKind.labour),
        EstimateLine(description:'LED-spotlight',unitPriceOre:39500,quantityMilli:6000,kind:LineKind.material)]);}),icon:const Icon(Icons.auto_awesome_outlined),label:const Text('Använd mallen Spotlights kök')),
      const SizedBox(height:16),...lines.indexed.map((entry)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(entry.$2.description),subtitle:Text('${entry.$2.quantityMilli/1000} × ${sek(entry.$2.unitPriceOre)}'),
        trailing:IconButton(tooltip:'Ta bort rad',icon:const Icon(Icons.delete_outline),onPressed:()=>setState(()=>lines.removeAt(entry.$1))))),
      const Divider(),const SizedBox(height:16),TextField(controller:description,decoration:const InputDecoration(labelText:'Beskrivning för ny rad')),const SizedBox(height:12),
      Row(children:[Expanded(child:TextField(controller:quantity,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Antal'))),const SizedBox(width:12),Expanded(child:TextField(controller:price,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'À-pris exkl. moms')))]),
      const SizedBox(height:12),DropdownButtonFormField<LineKind>(initialValue:kind,decoration:const InputDecoration(labelText:'Typ'),items:const[
        DropdownMenuItem(value:LineKind.labour,child:Text('Arbete')),DropdownMenuItem(value:LineKind.material,child:Text('Material')),DropdownMenuItem(value:LineKind.other,child:Text('Övrigt'))],onChanged:(v)=>setState(()=>kind=v!)),
      if(lineError!=null) Padding(padding:const EdgeInsets.all(8),child:Text(lineError!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      TextButton.icon(onPressed:addLine,icon:const Icon(Icons.add),label:const Text('Lägg till rad')),const SizedBox(height:16),
      DropdownButtonFormField<Deduction>(initialValue:deduction,decoration:const InputDecoration(labelText:'Preliminärt avdrag'),items:const[
        DropdownMenuItem(value:Deduction.none,child:Text('Inget avdrag')),DropdownMenuItem(value:Deduction.rot,child:Text('ROT 30 % (demoregel)')),DropdownMenuItem(value:Deduction.rut,child:Text('RUT 50 % (demoregel)'))],onChanged:(v)=>setState(()=>deduction=v!)),
      const SizedBox(height:20),if(lines.isNotEmpty) Text('Att betala: ${sek(EstimateTotals(lines,deduction).customerPaysOre)}',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:24),FilledButton(onPressed:(){if(!form.currentState!.validate())return;if(lines.isEmpty){setState(()=>lineError='Lägg till minst en rad.');return;}
        Navigator.pop(context,Quote(id:const Uuid().v4(),customerId:customerId,title:title.text.trim(),lines:List.unmodifiable(lines),deduction:deduction));},child:const Text('Spara offertutkast')),
    ])));
}
class CustomerEditor extends StatefulWidget {
  const CustomerEditor({super.key,this.customer}); final Map<String,dynamic>? customer;
  @override State<CustomerEditor> createState()=>_CustomerEditorState();
}
class _CustomerEditorState extends State<CustomerEditor> {
  final form=GlobalKey<FormState>();
  late final fields={for(final k in ['name','address','phone','email']) k:TextEditingController(text:widget.customer?[k] as String? ?? '')};
  @override void dispose(){for(final c in fields.values){c.dispose();}super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Kunduppgifter')),body:Form(key:form,child:ListView(padding:const EdgeInsets.all(20),children:[
    for(final entry in {'name':'Namn','address':'Adress','phone':'Telefon','email':'E-post'}.entries) Padding(padding:const EdgeInsets.only(bottom:16),child:TextFormField(
      controller:fields[entry.key],decoration:InputDecoration(labelText:entry.value),keyboardType:entry.key=='email'?TextInputType.emailAddress:entry.key=='phone'?TextInputType.phone:TextInputType.text,
      validator:(value){if(entry.key=='name'&&(value??'').trim().isEmpty)return 'Ange namn';if(entry.key=='email'&&(value??'').isNotEmpty&&!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!))return 'Ange en giltig e-postadress';return null;})),
    FilledButton(onPressed:(){if(form.currentState!.validate()) Navigator.pop(context,<String,dynamic>{'id':widget.customer?['id']??const Uuid().v4(),for(final e in fields.entries)e.key:e.value.text.trim()});},child:const Text('Spara kund')),
  ])));
}
class JobEditor extends StatefulWidget {
  const JobEditor({super.key,required this.customers});final List<Map<String,dynamic>> customers;
  @override State<JobEditor> createState()=>_JobEditorState();
}
class _JobEditorState extends State<JobEditor> {
  final form=GlobalKey<FormState>();final title=TextEditingController();
  late String customerId=widget.customers.first['id'] as String;
  String person='Erik';DateTime day=DateTime.now();TimeOfDay start=const TimeOfDay(hour:8,minute:0),end=const TimeOfDay(hour:10,minute:0);
  @override void dispose(){title.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Boka jobb')),body:Form(key:form,child:ListView(padding:const EdgeInsets.all(20),children:[
    TextFormField(controller:title,decoration:const InputDecoration(labelText:'Uppdrag'),validator:(v)=>(v??'').trim().isEmpty?'Ange uppdrag':null),const SizedBox(height:16),
    DropdownButtonFormField<String>(initialValue:customerId,decoration:const InputDecoration(labelText:'Kund'),items:widget.customers.map((c)=>DropdownMenuItem(value:c['id'] as String,child:Text(c['name'] as String))).toList(),onChanged:(v)=>setState(()=>customerId=v!)),const SizedBox(height:16),
    DropdownButtonFormField<String>(initialValue:person,decoration:const InputDecoration(labelText:'Ansvarig'),items:['Erik','Nora'].map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(),onChanged:(v)=>setState(()=>person=v!)),
    ListTile(title:const Text('Dag'),subtitle:Text(DateFormat('yyyy-MM-dd').format(day)),trailing:const Icon(Icons.calendar_month),onTap:()async{final v=await showDatePicker(context:context,initialDate:day,firstDate:DateTime(2020),lastDate:DateTime(2100));if(v!=null)setState(()=>day=v);}),
    ListTile(title:const Text('Starttid'),subtitle:Text(start.format(context)),onTap:()async{final v=await showTimePicker(context:context,initialTime:start);if(v!=null)setState(()=>start=v);}),
    ListTile(title:const Text('Sluttid'),subtitle:Text(end.format(context)),onTap:()async{final v=await showTimePicker(context:context,initialTime:end);if(v!=null)setState(()=>end=v);}),
    FilledButton(onPressed:(){if(!form.currentState!.validate())return;
      final from=DateTime(day.year,day.month,day.day,start.hour,start.minute),to=DateTime(day.year,day.month,day.day,end.hour,end.minute);
      if(!to.isAfter(from)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Sluttiden måste vara efter starttiden.')));return;}
      final c=widget.customers.firstWhere((c)=>c['id']==customerId);
      Navigator.pop(context,Job(id:const Uuid().v4(),title:title.text.trim(),customerId:customerId,address:c['address'] as String,assignee:person,startsAt:from,endsAt:to));
    },child:const Text('Spara bokning')),
  ])));
}
