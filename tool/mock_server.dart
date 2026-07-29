import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
  print('Mock server running on localhost:${server.port}');

  await for (HttpRequest request in server) {
    if (request.uri.path == '/upload') {
      await handleUpload(request);
    } else if (request.uri.path == '/upload_error') {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Simulated Internal Server Error')
        ..close();
    } else if (request.uri.path == '/upload_timeout') {
      // Simulate timeout by delaying the response indefinitely
      Timer(const Duration(minutes: 5), () {
        request.response
          ..statusCode = HttpStatus.gatewayTimeout
          ..close();
      });
    } else if (request.uri.path == '/upload_429') {
      request.response
        ..statusCode = HttpStatus.tooManyRequests
        ..write('Too Many Requests')
        ..close();
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found')
        ..close();
    }
  }
}

Future<void> handleUpload(HttpRequest request) async {
  if (request.method != 'POST') {
    request.response
      ..statusCode = HttpStatus.methodNotAllowed
      ..write('Method Not Allowed')
      ..close();
    return;
  }

  // Consume the request body to simulate reading the file
  int byteCount = 0;
  await for (var chunk in request) {
    byteCount += chunk.length;
  }

  print('Received upload of $byteCount bytes.');

  // Add a 2-second delay to allow upload_test to observe the uploading state
  await Future.delayed(const Duration(seconds: 2));

  request.response
    ..statusCode = HttpStatus.ok
    ..write(jsonEncode({'status': 'success', 'bytesReceived': byteCount}))
    ..close();
}
