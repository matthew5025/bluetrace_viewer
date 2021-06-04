import 'dart:collection';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';

import 'bluetrace.dart';

class BlueTraceView {
  HashMap<String, BlueTraceDevice> deviceList = HashMap();
  HashMap<String, int> lastSeenTime = HashMap();

  void updateList(BlueTraceDevice blueTraceDevice) {
    deviceList[blueTraceDevice.uniqueId] = blueTraceDevice;
    lastSeenTime[blueTraceDevice.uniqueId] =
        DateTime.now().millisecondsSinceEpoch;
  }

  List<BlueTraceDevice> getResultList() {
    var result = deviceList.values.toList();
    result.sort((a, b) => b.rssi.compareTo(a.rssi));
    return result;
  }

  ListView getView() {
    List<ExpansionTile> childItems = List.empty(growable: true);
    var currentTime = DateTime.now().millisecondsSinceEpoch;
    for (var device in getResultList()) {
      var deviceInfo = buildDeviceInfo(device);
      int lastSeenMs = lastSeenTime[device.uniqueId] ?? 0;
      String lastSeen = 'Last seen '
          '${_printDuration(Duration(milliseconds: currentTime - lastSeenMs))}'
          ' ago';
      var deviceUi = ExpansionTile(
        title: Text(device.deviceName),
        subtitle: Text(lastSeen),
        children: deviceInfo,
      );
      childItems.add(deviceUi);
    }

    return ListView(
      children: childItems,
    );
  }

  List<ListTile> buildDeviceInfo(BlueTraceDevice device) {
    List<ListTile> deviceValues = List.empty(growable: true);
    var btAddress = ListTile(
        title: Text('Bluetooth Address'), subtitle: Text(device.macAddress));
    deviceValues.add(btAddress);

    var rssi = ListTile(
        title: Text('RSSI'), subtitle: Text(device.rssi.toString() + 'dBm'));
    deviceValues.add(rssi);

    if (device is BlueTraceOG) {
      var encryptedData = ListTile(
          title: Text('AES-256-GCM Encrypted Data'),
          subtitle: Text(hex.encode(device.encryptedData)));
      deviceValues.add(encryptedData);

      var iv = ListTile(
          title: Text('Encryption IV'), subtitle: Text(hex.encode(device.iv)));
      deviceValues.add(iv);

      var authTag = ListTile(
          title: Text('Authentication Tag'),
          subtitle: Text(hex.encode(device.authTag)));
      deviceValues.add(authTag);

      var orgCode = ListTile(
          title: Text('Organisation Code'), subtitle: Text(device.orgCode));
      deviceValues.add(orgCode);

      var version = ListTile(
          title: Text('Protocol Version'),
          subtitle: Text(device.version.toString()));
      deviceValues.add(version);
    } else if (device is BlueTraceLite) {
      var mac = ListTile(
          title: Text('Packet Authentication'),
          subtitle: Text(hex.encode(device.mac)));
      deviceValues.add(mac);

      var uuid = ListTile(
          title: Text('Random Universally unique identifier'),
          subtitle: Text(hex.encode(device.uuid)));
      deviceValues.add(uuid);

      var reservedValue = ListTile(
          title: Text('Device Variant'),
          subtitle: Text(hex.encode(device.reservedValue)));
      deviceValues.add(reservedValue);

      var type = ListTile(
          title: Text('Issuer Code'),
          subtitle: Text(hex.encode(device.type)));
      deviceValues.add(type);
    }
    return deviceValues;
  }

  String _printDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
