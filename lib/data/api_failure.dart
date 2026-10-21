/// HTTP-level failure from the Cursor web API.
///
/// Ported from Kotlin 0.1.5 `ApiFailure`. Only the status, a short error code
/// and the `Retry-After` header are kept, so [toString] never carries cookie
/// or other secret material.
class ApiFailure implements Exception {
  const ApiFailure(this.status, this.code, [this.retryAfter]);

  final int status;
  final String code;
  final String? retryAfter;

  @override
  String toString() => 'HTTP $status · $code';
}
