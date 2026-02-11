import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

@pragma('vm:entry-point')
void recordingForegroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(_RecordingTaskHandler());
}

class _RecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('RecordingTaskHandler started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // El foreground service mantiene el proceso vivo.
    // El GPS se actualiza mediante el stream en la UI.
    // Este evento se ejecuta periódicamente para mantener el servicio activo.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('RecordingTaskHandler destroyed');
  }
}
