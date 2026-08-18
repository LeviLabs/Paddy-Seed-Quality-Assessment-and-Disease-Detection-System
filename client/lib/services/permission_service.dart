import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Request camera permission
  static Future<bool> requestCamera() async {
    final status = await Permission.camera.request();

    return status.isGranted;
  }

  /// Request gallery/photo permission
  static Future<bool> requestGallery() async {
    final status = await Permission.photos.request();

    return status.isGranted;
  }

  /// Request location permission
  static Future<bool> requestLocation() async {
    final status = await Permission.location.request();

    return status.isGranted;
  }

  /// Request all required permissions
  static Future<bool> requestAll() async {
    final statuses = await [
      Permission.camera,
      Permission.photos,
      Permission.location,
    ].request();

    return statuses[Permission.camera]?.isGranted == true &&
        statuses[Permission.photos]?.isGranted == true &&
        statuses[Permission.location]?.isGranted == true;
  }
}