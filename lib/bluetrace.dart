import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:semaphore/semaphore.dart';

class BlueTrace {
  FlutterBlue flutterBlue;

  var btUuid = Guid('b82ab3fc-1595-4f6a-80f0-fe094cc218f9');
  var btlUuid = Guid('0000ffff-0000-1000-8000-00805f9b34fb');
  var iOSUuid = Guid('0544082d-4676-4d5e-8ee0-34bd1907d94f');
  var androidUuid = Guid('117bdd58-57ce-4e7a-8e87-7cccdda2a804');
  var deviceInfoUuid = Guid('0000180a-0000-1000-8000-00805f9b34fb');
  var modelNameUuid = Guid('00002a24-0000-1000-8000-00805f9b34fb');
  Map<String, dynamic> iosMapping = Map();
  Map<String, dynamic> androidMapping = Map();
  HashSet<String> connectionSet;

  BlueTrace()
      : flutterBlue = FlutterBlue.instance,
        connectionSet = HashSet() {}
  StreamController<BlueTraceDevice> btDeviceStream = StreamController();
  final connectSemaphore = LocalSemaphore(2);
  final characteristicSemaphore = LocalSemaphore(1);

  StreamController<BlueTraceDevice> startScan() {
    startBleScan();
    // flutterBlue.startScan();
    // var subscription = flutterBlue.scanResults.listen((event) {
    //   for (ScanResult r in event) {
    //     processScanResults(r);
    //   }
    // });

    return this.btDeviceStream;
  }


  Future<void> startBleScan() async {
    List<ScanResult> results = List.empty(growable: true);
    flutterBlue.startScan(timeout: Duration(seconds: 5),
        withServices: [btUuid, btlUuid])
        .whenComplete(() => processScanResults(results));

    flutterBlue.scanResults.listen((event) {
      for(ScanResult r in event){
        results.add(r);
      }
    });
    flutterBlue.stopScan();

  }


  Future<String> getJson(String fileName) {
    return rootBundle.loadString(fileName);
  }

  void processScanResults(List<ScanResult> results) {
    for(ScanResult result in results){
      if (this.connectionSet.contains(result.device.id.id)) {
        continue;
      } else {
        this.connectionSet.add(result.device.id.id);
        removeEntry(result.device.id.id);
      }
      if (result.advertisementData.serviceUuids.contains(btUuid.toString())) {
        print(result.advertisementData.serviceUuids);
        connectToBlueTracePhone(result);
      } else if (result.advertisementData.serviceUuids
          .contains(btlUuid.toString())) {
        processBlueTraceLite(result);
      }
    }

    startBleScan();

  }

  Future<void> removeEntry(String deviceId) {
    return new Future.delayed(
        Duration(seconds: 15), () => this.connectionSet.remove(deviceId));
  }

  void processBlueTraceLite(ScanResult result) {
    if (!result.advertisementData.connectable) {
      var data = result.advertisementData.serviceData[btlUuid.toString()];
      if (data == null) {
        return;
      }
      BlueTraceLite blueTraceLite = BlueTraceLite('TraceTogether Token',
          result.device.id.id, result.rssi, Uint8List.fromList(data));
      print(blueTraceLite.deviceName);
      this.btDeviceStream.sink.add(blueTraceLite);
    }
  }

  Future<void> connectToBlueTracePhone(ScanResult result) async {
    if (!result.advertisementData.connectable) {
      return;
    }
    var connectionStatus = await _connectToDevice(result.device, 10);
    if(connectionStatus){
      if(result.device.name.isEmpty){
        await processBlueTraceAndroid(result);
      }else{
        await processBlueTraceApple(result);
      }
    }else{
      print('Could not connect to ${result.device.id.id}');
    }
  }

  Future<bool> _connectToDevice(BluetoothDevice device, int timeout) async {
    int state = -1;
    connectSemaphore.acquire();
    await device.connect(autoConnect: false).timeout(Duration(seconds: timeout),
        onTimeout: () {
      state = 0;
      device.disconnect();
    }).then((data) {
      if (state == -1) {
        state = 1;
      }
    });
    connectSemaphore.release();
    if (state == 1) {
      return Future.value(true);
    } else {
      return Future.value(false);
    }
  }

  Future<void> processBlueTraceAndroid(ScanResult result) async {
    BluetoothDevice device = result.device;
    var data = await readCharacteristic(device, btUuid, androidUuid);
    BlueTraceOG blueTraceOG =
        BlueTraceOG(String.fromCharCodes(data), device.id.id, result.rssi);
    if (androidMapping.length == 0) {
      androidMapping = json.decode(await getJson('android-device.json'));
    }

    var buffer = androidMapping[blueTraceOG.deviceName];
    if (buffer != null) {
      blueTraceOG.deviceName = buffer;
    }

    print(blueTraceOG.deviceName);
    this.btDeviceStream.sink.add(blueTraceOG);
    device.disconnect();
  }

  Future<void> processBlueTraceApple(ScanResult result) async {
    BluetoothDevice device = result.device;
    var modelName =
        await readCharacteristic(device, deviceInfoUuid, modelNameUuid);
    if (iosMapping.length == 0) {
      iosMapping = json.decode(await getJson('ios-device-identifiers.json'));
    }
    String modelNameStr = String.fromCharCodes(modelName);

    var buffer = iosMapping[modelNameStr];
    if (buffer != null) {
      modelNameStr = buffer;
    }

    modelNameStr = 'Apple $modelNameStr';

    var data = await readCharacteristic(device, btUuid, iOSUuid);
    BlueTraceLite blueTraceLite = BlueTraceLite(
        modelNameStr, device.id.id, result.rssi, Uint8List.fromList(data));
    print(blueTraceLite.deviceName);
    this.btDeviceStream.sink.add(blueTraceLite);
    device.disconnect();
  }

  Future<List<int>> readCharacteristic(
      BluetoothDevice device, Guid serviceUuid, Guid characteristicUuid) async {
    characteristicSemaphore.acquire();
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid == serviceUuid) {
        var characteristics = service.characteristics;
        for (BluetoothCharacteristic characteristic in characteristics) {
          if (characteristic.uuid == characteristicUuid) {
            var data = await characteristic.read();
            characteristicSemaphore.release();
            return data;
          }
        }
      }
    }
    characteristicSemaphore.release();
    return List.empty();
  }
}

abstract class BlueTraceDevice {
  String deviceName;
  String macAddress;
  int rssi;
  String uniqueId;

  BlueTraceDevice()
      : deviceName = '',
        macAddress = '',
        rssi = -1000,
        uniqueId = '';
}

class BlueTraceOG extends BlueTraceDevice {
  Uint8List encryptedData = Uint8List(0);
  Uint8List iv = Uint8List(0);
  Uint8List authTag = Uint8List(0);
  String orgCode = '';
  int version = -1;

  BlueTraceOG(String message, String macAddress, int rssi) {
    this.macAddress = macAddress;
    this.rssi = rssi;
    var jsonMessage = jsonDecode(message);
    var packet = base64.decode(jsonMessage['id']);
    this.encryptedData = packet.sublist(0, 29);
    this.iv = packet.sublist(29, 45);
    this.authTag = packet.sublist(45, 61);
    this.deviceName = jsonMessage['mp'];
    this.orgCode = jsonMessage['o'];
    this.version = jsonMessage['v'];
    this.uniqueId = hex.encode(encryptedData);
  }
}

class BlueTraceLite extends BlueTraceDevice {
  Uint8List mac;
  Uint8List uuid;
  Uint8List reservedValue;
  Uint8List type;

  BlueTraceLite(
      String deviceName, String macAddress, int rssi, Uint8List packet)
      : mac = packet.sublist(0, 6),
        this.uuid = packet.sublist(6, 16),
        this.reservedValue = packet.sublist(16, 18),
        this.type = packet.sublist(18, 20) {
    this.deviceName = deviceName;
    this.macAddress = macAddress;
    this.rssi = rssi;
    this.uniqueId = hex.encode(uuid);
  }
}
