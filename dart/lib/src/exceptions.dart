class LocalInferException implements Exception {
  LocalInferException(this.message);

  final String message;

  @override
  String toString() => message;
}
