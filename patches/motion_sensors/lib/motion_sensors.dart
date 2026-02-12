// No-op shim for package:motion_sensors to satisfy panorama 0.4.1.
// Provides the types and members panorama references, but does nothing at runtime.

library motion_sensors;

import 'dart:async';

// Panorama sometimes listens to `motionSensors.orientation`
class OrientationEvent {
  final double yaw; // radians
  final double pitch; // radians
  final double roll; // radians
  const OrientationEvent(this.yaw, this.pitch, this.roll);
}

// Panorama sometimes listens to `motionSensors.absoluteOrientation`
class AbsoluteOrientationEvent {
  final double yaw; // radians
  final double pitch; // radians
  final double roll; // radians
  const AbsoluteOrientationEvent(this.yaw, this.pitch, this.roll);
}

// Panorama reads `event.angle` and runs radians(event.angle!)
class ScreenOrientationEvent {
  /// degrees (0, 90, 180, 270) typically; nullable because panorama treats it so
  final double? angle;

  /// Optional numeric orientation if someone wants it
  final int orientation;
  const ScreenOrientationEvent({this.angle, this.orientation = 0});
}

class MotionSensors {
  MotionSensors._internal();
  static final MotionSensors _instance = MotionSensors._internal();
  factory MotionSensors() => _instance;

  // Streams panorama may subscribe to
  final _orientationCtrl = StreamController<OrientationEvent>.broadcast();
  final _absoluteOrientationCtrl =
      StreamController<AbsoluteOrientationEvent>.broadcast();
  final _screenOrientationCtrl =
      StreamController<ScreenOrientationEvent>.broadcast();

  // Expose as getters like the real package
  Stream<OrientationEvent> get orientation => _orientationCtrl.stream;
  Stream<AbsoluteOrientationEvent> get absoluteOrientation =>
      _absoluteOrientationCtrl.stream;
  Stream<ScreenOrientationEvent> get screenOrientation =>
      _screenOrientationCtrl.stream;

  // Panorama sets these; we accept and ignore.
  set orientationUpdateInterval(int micros) {}
  set absoluteOrientationUpdateInterval(int micros) {}

  void dispose() {
    _orientationCtrl.close();
    _absoluteOrientationCtrl.close();
    _screenOrientationCtrl.close();
  }
}

// Top-level singleton the real package exports.
final MotionSensors motionSensors = MotionSensors();
