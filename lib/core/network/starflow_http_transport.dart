import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_transport_stub.dart'
    if (dart.library.io) 'package:starflow/core/network/starflow_http_transport_io.dart'
    as impl;

http.Client createStarflowTransportClient() {
  return impl.createStarflowTransportClient();
}
