import 'dart:async';
import 'dart:collection';
import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  var btUuid = Uuid.parse('B82AB3FC-1595-4F6A-80F0-FE094CC218F9');
  var tokenUuid = Uuid.parse('FFFF');
  HashMap<String, StreamSubscription<ConnectionStateUpdate>> activeConnections = HashMap<String, StreamSubscription<ConnectionStateUpdate>>();
  HashSet<String> connectionSet = new HashSet();
  final flutterReactiveBle = FlutterReactiveBle();


  void findDevicesByServices(){
    flutterReactiveBle.scanForDevices(withServices: [tokenUuid], scanMode: ScanMode.lowLatency).listen((device) {
      connectToDevice(device);
    }, onError: (Object error, StackTrace stackTrace) {
      print(error);
    });

  }

  void connectToDevice(DiscoveredDevice device){
    if(connectionSet.contains(device.id)){
      return;
    }
    connectionSet.add(device.id);
    print(device.id);
    var connectionStream = flutterReactiveBle.connectToDevice(id: device.id,
        connectionTimeout: Duration(seconds: 20))
        .listen((connectionState) {
          print(connectionState.connectionState);
          if(connectionState.connectionState == DeviceConnectionState.connected){
            print('Connected!');
            getCharacteristic(device);

          }
    }, onError: (dynamic error){
          print(error);
          connectionSet.remove(device.id);
          return;
    });

    activeConnections[device.id] = connectionStream;
  }

  void getCharacteristic(DiscoveredDevice device) {
    flutterReactiveBle.discoverServices(device.id).asStream().listen((event) async {
      for (DiscoveredService s in event){
        if(s.serviceId != btUuid){
          continue;
        }
        var charUUID = Uuid.parse('0544082d-4676-4d5e-8ee0-34bd1907d94f');
        var characteristic = QualifiedCharacteristic(characteristicId: charUUID, serviceId: s.serviceId, deviceId: device.id);

        print('Service: ${s.serviceId}');
        for (Uuid charId in s.characteristicIds){
          print(charId);
          await readCharacteristic(characteristic);
        }

      }
      activeConnections[device.id]!.cancel();
      activeConnections.remove(device.id);
      connectionSet.remove(device.id);

    }, onError: (dynamic error){
      print(error);
    });
  }

  Future<void> readCharacteristic(QualifiedCharacteristic characteristic) async {
    final response = await flutterReactiveBle.readCharacteristic(characteristic);
    print(response);
  }

  void _incrementCounter() {
    findDevicesByServices();

    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
