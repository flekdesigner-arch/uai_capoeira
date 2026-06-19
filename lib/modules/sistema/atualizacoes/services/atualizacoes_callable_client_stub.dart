import 'package:cloud_functions/cloud_functions.dart';

class AtualizacoesCallableException implements Exception {
  const AtualizacoesCallableException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callNotifyNewAppVersion(
  Map<String, dynamic> data,
) async {
  final callable = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  ).httpsCallable('notifyNewAppVersion');
  final result = await callable.call<Map<String, dynamic>>(data);
  return Map<String, dynamic>.from(result.data);
}
