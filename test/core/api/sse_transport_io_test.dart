import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/sse_transport_io.dart';

void main() {
  group('withoutCancellation', () {
    test('a cancel we asked for ends the stream quietly', () async {
      final source = StreamController<List<int>>();
      final received = <List<int>>[];
      final done = Completer<void>();
      withoutCancellation(source.stream).listen(
        received.add,
        onError: (Object error) => fail('unexpected error: $error'),
        onDone: done.complete,
      );

      source.add([1, 2]);
      source.addError(
        DioException.requestCancelled(
          requestOptions: RequestOptions(path: '/sse'),
          reason: 'stopped',
        ),
      );
      await source.close();
      await done.future;

      expect(received, [
        [1, 2],
      ]);
    });

    test('any other error still reaches the listener', () async {
      final source = StreamController<List<int>>();
      final errors = <Object>[];
      withoutCancellation(source.stream).listen(null, onError: errors.add);

      source.addError(
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/sse'),
          reason: 'offline',
        ),
      );
      await source.close();
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
    });
  });
}
