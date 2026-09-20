import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

typedef OnSharedFileCallback = void Function(String filePath);

class ShareIntentService {
  StreamSubscription? _intentDataStreamSubscription;
  OnSharedFileCallback? _onSharedFile;

  void init({required OnSharedFileCallback onSharedFile}) {
    _onSharedFile = onSharedFile;

    // 1. 监听运行中的分享 Intent (热启动)
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final filePath = value.first.path;
        if (filePath.isNotEmpty) {
          _onSharedFile?.call(filePath);
        }
      }
    }, onError: (err) {
      // Ignored
    });

    // 2. 获取冷启动时的分享 Intent (冷启动)
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final filePath = value.first.path;
        if (filePath.isNotEmpty) {
          _onSharedFile?.call(filePath);
        }
        ReceiveSharingIntent.instance.reset();
      }
    }).catchError((err) {
      // Ignored
    });
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
