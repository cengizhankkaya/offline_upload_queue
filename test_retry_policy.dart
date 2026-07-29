import 'lib/src/queue/retry_policy.dart';
void main() {
  final p = RetryPolicy(maxAttempts: 3, backoff: BackoffStrategy.fixed(Duration.zero));
  print(p.shouldPermanentlyFail(0));
  print(p.shouldPermanentlyFail(1));
  print(p.shouldPermanentlyFail(2));
}
