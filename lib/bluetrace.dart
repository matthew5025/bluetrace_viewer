import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:convert/convert.dart';

class BlueTrace {
  var btUuid = Uuid.parse('B82AB3FC-1595-4F6A-80F0-FE094CC218F9');
  var btlUuid = Uuid.parse('0000ffff-0000-1000-8000-00805f9b34fb');
  FlutterReactiveBle flutterReactiveBle;
  HashMap<String, StreamSubscription<ConnectionStateUpdate>> activeConnections;
  HashSet<String> connectionSet;
  StreamController<BlueTraceDevice> btDeviceStream = StreamController();

  BlueTrace()
      : flutterReactiveBle = FlutterReactiveBle(),
        activeConnections = HashMap(),
        connectionSet = HashSet();

  StreamController<BlueTraceDevice> startScan() {
    var scanResults = flutterReactiveBle.scanForDevices(
        withServices: [btUuid, btlUuid], scanMode: ScanMode.lowLatency);
    scanResults.listen((device) {
      processScanResults(device);
    }, onError: (dynamic error) {
      print(error);
    });
    return btDeviceStream;
  }


  Future<bool> removeEntry(String deviceId){
    return new Future.delayed(Duration(seconds: 5),
            () => connectionSet.remove(deviceId));
  }

  void processScanResults(DiscoveredDevice device) {
    if(connectionSet.contains(device.id)){
      return;
    }
    connectionSet.add(device.id);
    removeEntry(device.id);
    print('Processing ${device.id}');

    if (device.serviceUuids.length == 1) {
      if (device.serviceUuids[0] == btlUuid) {
        processBlueTraceToken(device);
        return;
      }
    }

    for (Uuid uuid in device.serviceUuids) {
      if (uuid == btUuid) {
        connectToDevice(device);
        return;
      }
    }

    connectionSet.remove(device.id);
  }

  void processBlueTraceToken(DiscoveredDevice device) {
    var btlPacket = device.serviceData[btlUuid];
    if (btlPacket!.length != 20) {
      return;
    }

    BlueTraceLite blueTraceLite =
    BlueTraceLite('TraceTogether Token', device.id, device.rssi, btlPacket);
    btDeviceStream.sink.add(blueTraceLite);
  }

  void connectToDevice(DiscoveredDevice device) {
    // ignore: cancel_subscriptions
    var connectionStream = flutterReactiveBle.connectToDevice
      (id: device.id, connectionTimeout: Duration(seconds: 5)).listen((event) {
        if(event.connectionState == DeviceConnectionState.connected){
          getBlueTraceMessage(device);
        }
    });

    activeConnections[device.id] = connectionStream;
  }

  void getBlueTraceMessage(DiscoveredDevice device){
    var iOSUuid = Uuid.parse('0544082d-4676-4d5e-8ee0-34bd1907d94f');
    var androidUuid = Uuid.parse('117BDD58-57CE-4E7A-8E87-7CCCDDA2A804');
    var deviceInfoServiceUuid = Uuid.parse('0000180a-0000-1000-8000-00805f9b34fb');
    var iOSModelNumberUuid = Uuid.parse('00002a24-0000-1000-8000-00805f9b34fb');
    flutterReactiveBle.discoverServices(device.id).asStream().listen((event) async {
      for(DiscoveredService s in event){
        if(s.serviceId != btUuid){
          continue;
        }

        if(s.characteristicIds.contains(iOSUuid)){
          var deviceNameCharacteristic = QualifiedCharacteristic(
              characteristicId: iOSModelNumberUuid,
              serviceId: deviceInfoServiceUuid, deviceId: device.id);

          var result = await readCharacteristic(deviceNameCharacteristic);
          String phoneModel = new String.fromCharCodes(result);

          var btPacketCharacteristic = QualifiedCharacteristic(characteristicId: iOSUuid, serviceId: btUuid, deviceId: device.id);
          var packet = await readCharacteristic(btPacketCharacteristic);
          BlueTraceLite blueTraceLite = BlueTraceLite(phoneModel, device.id, device.rssi, Uint8List.fromList(packet));
          btDeviceStream.sink.add(blueTraceLite);
        }
        else if(s.characteristicIds.contains(androidUuid)){
          var btPacketCharacteristic = QualifiedCharacteristic(characteristicId: androidUuid, serviceId: btUuid, deviceId: device.id);
          var packet = await readCharacteristic(btPacketCharacteristic);
          String base64Data = new String.fromCharCodes(packet);
          BlueTraceOG blueTraceOG = BlueTraceOG(base64Data, device.id, device.rssi);
          btDeviceStream.sink.add(blueTraceOG);
        }

      }

      if(activeConnections[device.id] != null){
        activeConnections[device.id]!.cancel();
      }
      activeConnections.remove(device.id);
      connectionSet.remove(device.id);

    });
  }

  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic) async {
    final response = await flutterReactiveBle.readCharacteristic(characteristic);
    return response;
  }



}


abstract class BlueTraceDevice {
  String deviceName;
  String macAddress;
  int rssi;

  BlueTraceDevice()
      : deviceName = '',
        macAddress = '',
        rssi = -1000;
}

class BlueTraceOG extends BlueTraceDevice {
  Uint8List encryptedData = Uint8List(0);
  Uint8List iv = Uint8List(0);
  Uint8List authTag = Uint8List(0);
  String orgCode = '';
  int version = -1;

  BlueTraceOG(String message, String macAddress, int rssi){
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
  }

}

class BlueTraceLite extends BlueTraceDevice {
  Uint8List mac;
  Uint8List uuid;
  Uint8List reservedValue;
  Uint8List type;

  BlueTraceLite(String deviceName, String macAddress, int rssi, Uint8List packet):
        mac = packet.sublist(0, 6),
        this.uuid = packet.sublist(6, 16),
        this.reservedValue = packet.sublist(16, 18),
        this.type = packet.sublist(18, 20) {
    this.deviceName = deviceName;
    this.macAddress = macAddress;
    this.rssi = rssi;
  }
}
