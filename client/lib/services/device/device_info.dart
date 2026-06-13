class DeviceInfo {
  final String platformType;
  final String osVersion;
  final String deviceModel;
  final String deviceBrand;
  final String appVersion;
  final String appBuildNumber;

  const DeviceInfo({
    this.platformType = 'unknown',
    this.osVersion = '',
    this.deviceModel = '',
    this.deviceBrand = '',
    this.appVersion = '',
    this.appBuildNumber = '',
  });
}
