import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:full_chat_application/core/storage/shared_preferences.dart';
import 'package:full_chat_application/core/utils/app_utils.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/storage/firebase_helper/fireBaseHelper.dart';
import '../chat_screen/manager/chat_cubit.dart';
import '../home_screen/view/home_screen.dart';

class AudioCallScreen extends StatefulWidget {
  const AudioCallScreen({Key? key}) : super(key: key);

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  bool _joined = false;
  int _remoteUid = 0;
  bool _isMuted = false;
  late RtcEngine engine;
  late Timer timer;
  late FToast fToast;

  Future<void> initPlatformState() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await [Permission.microphone].request();
    }

    // Create and initialize the RtcEngine
    engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(appId: APP_ID));

    // Define event handling logic
    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        debugPrint(
            'joinChannelSuccess ${connection.channelId} ${connection.localUid}');
        setState(() {
          _joined = true;
        });
      },
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        debugPrint('userJoined $remoteUid');
        setState(() {
          _remoteUid = remoteUid;
        });
        timer.cancel();
      },
      onUserOffline: (RtcConnection connection, int remoteUid,
          UserOfflineReasonType reason) {
        debugPrint('userOffline $remoteUid');
        setState(() {
          _remoteUid = 0;
        });
      },
    ));

    // Join channel with channel name as 'bego'
    await engine.joinChannel(
        token: Token,
        channelId: 'bego',
        uid: 0,
        options: const ChannelMediaOptions());

    // Initialize a timer to detect missed calls
    timer = Timer(const Duration(seconds: 40), () {
      missedCall("User didn't answer");
    });
  }

  void missedCall(String msg) {
    if (context.read<ChatCubit>().peerUserData["email"] == null) {
      context.read<ChatCubit>().notifyUser(
          "${context.read<ChatCubit>().getCurrentUser()!.displayName}",
          "${context.read<ChatCubit>().getCurrentUser()!.displayName} called you",
          getEmail(),
          context.read<ChatCubit>().getCurrentUser()!.email);
    } else {
      context.read<ChatCubit>().notifyUser(
          "${context.read<ChatCubit>().getCurrentUser()!.displayName}",
          "${context.read<ChatCubit>().getCurrentUser()!.displayName} called you",
          context.read<ChatCubit>().peerUserData["email"],
          context.read<ChatCubit>().getCurrentUser()!.email);
    }
    Navigator.pop(context);
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.CENTER,
      timeInSecForIosWeb: 1,
      fontSize: 16.0,
    );
  }

  void endCall(String msg) {
    if (context.read<ChatCubit>().peerUserData["email"] == null) {
      context.read<ChatCubit>().notifyUser(
          "${context.read<ChatCubit>().getCurrentUser()!.displayName}",
          "${context.read<ChatCubit>().getCurrentUser()!.displayName} called you",
          getEmail(),
          context.read<ChatCubit>().getCurrentUser()!.email);
    } else {
      context.read<ChatCubit>().notifyUser(
          "${context.read<ChatCubit>().getCurrentUser()!.displayName}",
          "${context.read<ChatCubit>().getCurrentUser()!.displayName} called you",
          context.read<ChatCubit>().peerUserData["email"],
          context.read<ChatCubit>().getCurrentUser()!.email);
    }
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

  @override
  void initState() {
    super.initState();
    initPlatformState();
    timer = Timer(const Duration(milliseconds: 40000), () {
      missedCall("User didn't answer");
    });

    if (context.read<ChatCubit>().peerUserData["userId"] == null) {
      FirebaseFirestore.instance
          .collection("users")
          .doc(getId())
          .snapshots()
          .listen((event) {
        if (event["chatWith"].toString() == "false") {
          // Mean that user ended the call
          Get.off(const HomeScreen());
          buildShowSnackBar(context, "User ended the call");
        }
      });
    } else {
      FirebaseFirestore.instance
          .collection("users")
          .doc(context.read<ChatCubit>().peerUserData["userId"])
          .snapshots()
          .listen((event) {
        if (event["chatWith"].toString() == "false") {
          // Mean that user ended the call
          Get.off(const HomeScreen());
          buildShowSnackBar(context, "User ended the call");
        }
      });
    }
  }

  @override
  void dispose() {
    engine.leaveChannel();
    engine.release();
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            Center(
              child: Text(
                  "Calling with ${context.read<ChatCubit>().peerUserData["name"] ?? getName()}"),
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
                        endCall("You ended the call");
                      },
                      icon: const CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.red,
                        child: Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 40,
                        ),
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
                        engine.muteLocalAudioStream(_isMuted);
                      },
                      icon: CircleAvatar(
                        radius: 40,
                        child: _isMuted
                            ? const Icon(
                                Icons.volume_off,
                                color: Colors.white,
                                size: 40,
                              )
                            : const Icon(
                                Icons.volume_up,
                                color: Colors.white,
                                size: 40,
                              ),
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
