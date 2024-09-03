import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:full_chat_application/core/storage/shared_preferences.dart';
import 'package:full_chat_application/core/utils/app_utils.dart';
import 'package:full_chat_application/features/home_screen/view/home_screen.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/storage/firebase_helper/fireBaseHelper.dart';
import '../chat_screen/manager/chat_cubit.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({Key? key}) : super(key: key);

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  bool _joined = false;
  int _remoteUid = 0;
  bool _switch = false;
  bool _isMuted = false;
  late RtcEngine _engine;
  late Timer _timer;
  late FToast fToast;

  @override
  void initState() {
    super.initState();
    _initAgoraEngine();
    _startMissedCallTimer();
    _listenToCallStatus();
  }

  Future<void> _initAgoraEngine() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await [Permission.microphone, Permission.camera].request();
    }

    FireBaseHelper().updateCallStatus(context, "true");

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(appId: APP_ID));

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        setState(() {
          _joined = true;
        });
      },
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        setState(() {
          _remoteUid = remoteUid;
        });
        _timer.cancel();
      },
      onUserOffline: (RtcConnection connection, int remoteUid,
          UserOfflineReasonType reason) {
        setState(() {
          _remoteUid = 0;
        });
      },
    ));

    await _engine.enableVideo();
    await _engine.joinChannel(
      token: Token,
      channelId: 'bego',
      options: ChannelMediaOptions(),
      uid: 0,
    );
  }

  void _startMissedCallTimer() {
    _timer = Timer(const Duration(milliseconds: 40000), () {
      _missedCall("user didn't answer");
    });
  }

  void _listenToCallStatus() {
    final chatCubit = context.read<ChatCubit>();
    final userId = chatCubit.peerUserData["userId"] ?? getId();

    FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .snapshots()
        .listen((event) {
      if (event["chatWith"].toString() == "false") {
        Get.off(const HomeScreen());
        buildShowSnackBar(context, "user ended the call");
      }
    });
  }

  void _missedCall(String msg) {
    _sendNotification();
    _endCallWithMessage(msg);
  }

  void _endCallWithMessage(String msg) {
    Get.off(const HomeScreen());
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.CENTER,
      timeInSecForIosWeb: 1,
      fontSize: 16.0,
    );
    FireBaseHelper().updateCallStatus(context, "");
  }

  void _sendNotification() {
    final chatCubit = context.read<ChatCubit>();
    final peerEmail = chatCubit.peerUserData["email"];
    final currentUserEmail = chatCubit.getCurrentUser()!.email;
    final currentUserName = chatCubit.getCurrentUser()!.displayName;

    chatCubit.notifyUser(
      currentUserName!,
      "$currentUserName called you",
      peerEmail ?? getEmail(),
      currentUserEmail,
    );
  }

  @override
  void dispose() {
    _engine.leaveChannel();
    _engine.release();
    _timer.cancel();
    super.dispose();
  }

  Widget _renderLocalPreview() {
    if (_joined) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: _engine,
          canvas: const VideoCanvas(uid: 0),
        ),
      );
    } else {
      return const Center(child: Text('Please join channel first'));
    }
  }

  Widget _renderRemoteVideo() {
    if (_remoteUid != 0) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: const RtcConnection(channelId: "bego"),
        ),
      );
    } else {
      return const Center(child: Text('Please wait for remote user to join'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            Center(
                child: _switch ? _renderRemoteVideo() : _renderLocalPreview()),
            Align(
              alignment: Alignment.topLeft,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _switch = !_switch;
                  });
                },
                child: Container(
                  width: 150,
                  height: 300,
                  color: Colors.blue,
                  child: Center(
                    child:
                        _switch ? _renderLocalPreview() : _renderRemoteVideo(),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height * .2,
                color: Colors.transparent,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      iconSize: 50,
                      onPressed: () {
                        FireBaseHelper().updateCallStatus(context, "false");
                        _endCallWithMessage("You ended the call");
                      },
                      icon: const CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.red,
                        child:
                            Icon(Icons.call_end, color: Colors.white, size: 40),
                      ),
                    ),
                    IconButton(
                      iconSize: 50,
                      onPressed: () {
                        setState(() {
                          _isMuted = !_isMuted;
                        });
                        buildShowSnackBar(
                            context, _isMuted ? "Call Muted" : "Call Unmuted");
                        _engine.muteLocalAudioStream(_isMuted);
                      },
                      icon: CircleAvatar(
                        radius: 40,
                        child: Icon(
                          _isMuted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 50,
                      onPressed: () {
                        _engine.switchCamera();
                      },
                      icon: const CircleAvatar(
                        radius: 40,
                        child: Icon(Icons.switch_camera,
                            color: Colors.white, size: 40),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
