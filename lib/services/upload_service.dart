import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

class UploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Upload de imagem para o Firebase Storage
  Future<String?> uploadImagem(File imagem, {String? pasta}) async {
    try {
      String fileName = DateTime.now().millisecondsSinceEpoch.toString() + path.extension(imagem.path);
      String caminho = 'eventos/${pasta ?? 'banners'}/$fileName';

      Reference ref = _storage.ref().child(caminho);
      UploadTask uploadTask = ref.putFile(imagem);

      TaskSnapshot snapshot = await uploadTask;
      String urlDownload = await snapshot.ref.getDownloadURL();

      return urlDownload;
    } catch (e) {
      print('❌ Erro ao fazer upload: $e');
      return null;
    }
  }

  // Deletar imagem
  Future<void> deletarImagem(String url) async {
    try {
      Reference ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (e) {
      print('❌ Erro ao deletar imagem: $e');
    }
  }
}