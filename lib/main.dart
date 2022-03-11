import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'notification_service.dart';
import 'package:rflutter_alert/rflutter_alert.dart';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:device_info_plus/device_info_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  late MqttServerClient _mqtt;
  final mqttClientId = DateTime.now().millisecondsSinceEpoch.toString();
  final mqttHost = 'broker.hivemq.com';
  final mqttUser = '';
  final mqttPassword = '';
  final mqttTopicHeroes = '/pinloc/heroes';
  final mqttTopicTasks = '/pinloc/tasks';

  late Timer _heroTimer;
  late Timer _taskTimer;
  final _jf = DateFormat("yyMMddHHmmss");
  final _df = DateFormat("yyyy-MM-dd HH:mm:ss");

  var deviceId = '-';
  var gps;
  var _heroMap = {};
  var _taskList = [];

  @override
  void initState() {
    _tabController = TabController(
      length: 2,
      initialIndex: 0,
      vsync: this,
    );

    NotificationService().init(onSelect: _answerTask);

    _getDeviceId().then((value) {
      setState(() {
        deviceId = value;
      });
    });
    _getLocationData().then((value) {
      setState(() {
        gps = value;
      });
    });

    super.initState();

    _setupMqtt();

    _heroTimer = Timer.periodic(const Duration(seconds: 10), (t) {
      _registerHero();
    });

    _taskTimer = Timer.periodic(const Duration(seconds: 15), (t) {
      for (var e in _taskList) {
        final array = e.split(',');

        if (array[5] == '0' &&
            DateTime.now().difference(_df.parse(array[1])).inSeconds > 15) {
          _acceptTask(false, array[0], array[4]);
        }
      }
    });
  }

  @override
  void dispose() {
    _heroTimer.cancel();
    _taskTimer.cancel();
    super.dispose();
  }

  late TabController _tabController;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(icon: Icon(Icons.person)),
              Tab(icon: Icon(Icons.list_alt)),
            ],
          ),
          title: Text('Hero: $deviceId'),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  final builder = MqttClientPayloadBuilder();
                  builder.addString('');

                  _mqtt.publishMessage(
                    mqttTopicHeroes,
                    MqttQos.atLeastOnce,
                    builder.payload!,
                    retain: true,
                  );
                  _mqtt.publishMessage(
                    mqttTopicTasks,
                    MqttQos.atLeastOnce,
                    builder.payload!,
                    retain: true,
                  );
                })
          ],
        ),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.pin_drop),
          onPressed: () => _registerHero(),
        ),
        body: TabBarView(
          children: [
            _heroListTab(),
            _taskListTab(),
          ],
          controller: _tabController,
        ),
      ),
    );
  }

  _heroListTab() {
    return ListView.separated(
      itemCount: _heroMap.length,
      separatorBuilder: (_, index) => const Divider(color: Colors.black26),
      itemBuilder: (context, i) {
        final heroId = _heroMap.keys.elementAt(i);
        final array = _heroMap[heroId]!.split(',');
        final isMe = heroId == deviceId;

        return ListTile(
          leading: Icon(
            isMe ? Icons.person_pin : Icons.person,
            color: isMe ? Colors.blue : Colors.black54,
          ),
          trailing: Text(array[0]),
          title: Text(heroId,
              style: TextStyle(
                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
              )),
          subtitle: Text('${array[1]}:${array[2]}'),
          onTap: () => _sendTask(heroId),
        );
      },
    );
  }

  _taskListTab() {
    return ListView.separated(
      itemCount: _taskList.length,
      separatorBuilder: (_, index) => const Divider(color: Colors.black26),
      itemBuilder: (context, i) {
        final array = _taskList[i].split(',');
        final myTask = array[0] == deviceId;
        var taskStatus = array[5];

        Color taskColor = Colors.green;
        var taskIcon = Icons.check_circle;
        if (taskStatus == '1') {
          taskIcon = Icons.remove_circle;
          taskColor = Colors.redAccent;
        } else if (taskStatus == '0') {
          taskIcon = Icons.circle_notifications_rounded;
          taskColor = myTask ? Colors.blue : Colors.grey;
        }

        return ListTile(
          leading: Icon(taskIcon, color: taskColor),
          trailing: Text(array[1]),
          title: Text(
            array[0],
            style: TextStyle(
              color: myTask ? Colors.black : Colors.grey,
              fontWeight: myTask ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text('${array[4]}'),
          onTap: () => _answerTask(array),
        );
      },
    );
  }

  _sendTask(heroId) async {
    if (heroId == deviceId) return false;

    final taskId = 'J${_jf.format(DateTime.now())}';
    final now = _df.format(DateTime.now());

    _taskList.add('$heroId,$now,${gps.latitude},${gps.longitude},$taskId,0');

    final builder = MqttClientPayloadBuilder();
    builder.addString(json.encode(_taskList));

    _mqtt.publishMessage(
      mqttTopicTasks,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: true,
    );

    print('>>>> SEND TASK: $heroId, $taskId');

    Alert(
      context: context,
      type: AlertType.success,
      title: "Task Assigned: $taskId",
      desc: 'To Hero: $heroId',
      buttons: [
        DialogButton(
          child: const Text("Ok"),
          onPressed: () => Navigator.pop(context),
          width: 120,
        )
      ],
    ).show();
  }

  _answerTask(array) async {
    final heroId = array[0];
    final taskId = array[4];
    final taskStatus = array[5];

    if (taskStatus != '0') return;

    if (heroId != deviceId) {
      Alert(
        context: context,
        type: AlertType.warning,
        title: "This task is not for you",
        buttons: [
          DialogButton(
            child: const Text("Ok"),
            onPressed: () => Navigator.pop(context),
            width: 120,
          )
        ],
      ).show();

      return false;
    }

    Alert(
      context: context,
      type: AlertType.warning,
      title: "Shall you accept the task?",
      desc: 'Task: $taskId',
      buttons: [
        DialogButton(
          child: const Text(
            "Accept",
            style: TextStyle(color: Colors.white),
          ),
          width: 120,
          onPressed: () {
            _acceptTask(true, heroId, taskId);
            Navigator.pop(context);
          },
        ),
        DialogButton(
          child: const Text(
            "Reject",
            style: TextStyle(color: Colors.white),
          ),
          color: Colors.red,
          width: 120,
          onPressed: () {
            _acceptTask(false, heroId, taskId);
            Navigator.pop(context);
          },
        )
      ],
    ).show();
  }

  _acceptTask(accept, heroId, taskId) {
    final idx = _taskList.indexWhere((e) {
      final array = e.split(',');
      return array[0] == heroId && array[4] == taskId;
    });

    var task = _taskList[idx].split(',');
    task[5] = accept ? _df.format(DateTime.now()) : '1';

    _taskList[idx] = task.join(',');

    final builder = MqttClientPayloadBuilder();
    builder.addString(json.encode(_taskList));

    _mqtt.publishMessage(
      mqttTopicTasks,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: true,
    );

    print('>>>> ${accept ? "Accept" : "Reject"} Task: $heroId, $taskId');

    _tabController.animateTo(1);
  }

  _registerHero() async {
    gps = await _getLocationData();
    final now = _df.format(DateTime.now());

    _heroMap[deviceId] = '$now,${gps.latitude},${gps.longitude}';

    final data = json.encode(_heroMap);

    final builder = MqttClientPayloadBuilder();
    builder.addString(data);

    _mqtt.publishMessage(
      mqttTopicHeroes,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: true,
    );
  }

  Future<LocationData> _getLocationData() async {
    final Location location = Location();
    if (!await location.serviceEnabled()) {
      if (!await location.requestService()) throw 'GPS service is disabled';
    }
    if (await location.hasPermission() == PermissionStatus.denied) {
      if (await location.requestPermission() != PermissionStatus.granted)
        throw 'No GPS permissions';
    }
    final LocationData data = await location.getLocation();

    return data;
  }

  Future<String> _getDeviceId() async {
    String deviceId = '';
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      var info = await deviceInfo.androidInfo;
      deviceId = info.androidId!;
    } else if (Platform.isIOS) {
      var info = await deviceInfo.iosInfo;
      deviceId = info.identifierForVendor!;
    }

    return deviceId;
  }

  _setupMqtt() {
    _mqtt = MqttServerClient.withPort(
      mqttHost,
      mqttClientId,
      1883,
    );
    _mqtt.logging(on: false);

    _mqtt.onConnected = () {
      print('>>> MQTT connected');

      _mqtt.subscribe(mqttTopicHeroes, MqttQos.atMostOnce);
      _mqtt.subscribe(mqttTopicTasks, MqttQos.atMostOnce);

      _mqtt.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final msg = c[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          msg.payload.message,
        );
        _onMessage(c[0].topic, payload);
      });
    };

    _mqtt.onSubscribed = (topic) => print('<<< MQTT SUB $topic');
    _mqtt.onSubscribeFail = (topic) => print('<<< MQTT SUB failed $topic');

    final connMessage = MqttConnectMessage()
        .authenticateAs(mqttUser, mqttPassword)
        .withWillTopic('willtopic')
        .withWillMessage('Will message')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    connMessage.withClientIdentifier(mqttClientId);
    _mqtt.connectionMessage = connMessage;
    _mqtt.keepAlivePeriod = 60;

    _mqtt.connect();
  }

  _onMessage(String topic, String payload) {
    // print('<<<< RECEIVED: $topic = $payload');
    if (topic == mqttTopicHeroes) {
      try {
        _heroMap = json.decode(payload);
      } catch (ex) {
        print('===> $ex');
        _heroMap = {};
      }

      setState(() {});
    } else if (topic == mqttTopicTasks) {
      try {
        _taskList = json.decode(payload);
        _taskList.sort((a, b) {
          return _df.parse(b.split(',')[1]).microsecondsSinceEpoch -
              _df.parse(a.split(',')[1]).microsecondsSinceEpoch;
        });

        for (var e in _taskList) {
          final array = e.split(',');

          if (array[0] == deviceId && array[5] == '0') {
            NotificationService().show(
              12345,
              'Task Available',
              '${array[4]} at ${array[1]}',
              e,
            );
          }
        }
      } catch (ex) {
        print('===> $ex');
        _taskList = [];
      }
      setState(() {});
    }
  }
}
