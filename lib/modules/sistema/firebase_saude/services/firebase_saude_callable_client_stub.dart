import 'package:cloud_functions/cloud_functions.dart';

Future<Map<String, dynamic>> callFirebaseSaudeCallable({
  required FirebaseFunctions functions,
  required String functionName,
  Map<String, dynamic> data = const <String, dynamic>{},
  String region = 'us-central1',
}) async {
  final callable = functions.httpsCallable(functionName);
  final result = await callable.call<Map<String, dynamic>>(data);
  return Map<String, dynamic>.from(result.data);
}
