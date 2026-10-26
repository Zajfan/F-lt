import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:falt/data/local_store.dart';
import 'package:falt/main.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();sqfliteFfiInit();
  late LocalStore store;
  setUp(()async{store=await LocalStore.open(factory:databaseFactoryFfi,databasePath:inMemoryDatabasePath);await store.seedDemo(at:DateTime(2026,10,26));await store.ensureCatalog();});
  tearDown(()async{await store.close();});
  Future<void> waitFor(WidgetTester tester,Finder finder)async{
    for(var i=0;i<100;i++){
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));
      await tester.pump(const Duration(milliseconds:50));
      if(finder.evaluate().isNotEmpty){await tester.pumpAndSettle();return;}
    }
    expect(finder,findsWidgets);
  }
  Future<void> open(WidgetTester tester,{double scale=1})async{
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    tester.platformDispatcher.textScaleFactorTestValue=scale;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown((){tester.platformDispatcher.textScaleFactorTestValue=1.0;});
    await tester.pumpWidget(FaltApp(store:store,clock:()=>DateTime(2026,10,26)));await waitFor(tester,find.text('Idag'));
  }
  testWidgets('job workspace opens and all five tabs are reachable on a phone',(tester)async{
    await open(tester);final openJob=find.text('Öppna jobb').first;await tester.ensureVisible(openJob);await tester.tap(openJob);await waitFor(tester,find.text('Kund och plats'));
    expect(find.text('Byte av elcentral'),findsOneWidget);
    for(final tab in ['Tid','Material','Underlag','Fakturering','Översikt']){
      final target=find.text(tab).first;await tester.ensureVisible(target);await tester.tap(target);await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('today and job detail remain usable at 200 percent text',(tester)async{
    await open(tester,scale:2);expect(tester.takeException(),isNull);
    final openJob = find.text('Öppna jobb').first;await tester.ensureVisible(openJob);await tester.tap(openJob);
    await waitFor(tester,find.text('Kund och plats'));
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('native Flutter job overview reference',(tester)async{
    await open(tester);final openJob=find.text('Öppna jobb').first;await tester.ensureVisible(openJob);await tester.tap(openJob);await waitFor(tester,find.text('Kund och plats'));
    for(final entry in {'Tid':'time','Material':'materials','Underlag':'documents','Fakturering':'billing'}.entries){
      final target=find.text(entry.key).first;await tester.ensureVisible(target);await tester.tap(target);await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
