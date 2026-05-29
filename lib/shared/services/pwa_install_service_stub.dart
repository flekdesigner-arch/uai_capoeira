class PwaInstallService {
  PwaInstallService._internal();

  static final PwaInstallService instance = PwaInstallService._internal();

  Stream<bool> get installAvailableStream => const Stream<bool>.empty();

  bool get isInstallPromptAvailable => false;

  Future<bool> promptInstall() async => false;
}
