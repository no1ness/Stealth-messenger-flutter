export 'device_info.dart';
export 'device_info_service_stub.dart'
    if (dart.library.io) 'device_info_service_io.dart'
    if (dart.library.js_interop) 'device_info_service_web.dart';
