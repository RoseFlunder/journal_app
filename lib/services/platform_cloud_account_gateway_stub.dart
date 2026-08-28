import 'cloud_auth_config.dart';
import 'cloud_gateway.dart';

class PlatformCloudAccountGateway extends DisabledCloudAccountGateway {
  PlatformCloudAccountGateway({
    GoogleCloudConfig config = const GoogleCloudConfig(),
  });
}
