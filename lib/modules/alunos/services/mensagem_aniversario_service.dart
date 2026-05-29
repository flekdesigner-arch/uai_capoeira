import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/mensagem_aniversario_model.dart';

class MensagemAniversarioService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionPath = 'mensagens_aniversario';

  // Buscar mensagens ativas
  Future<List<MensagemAniversario>> getMensagensAtivas() async {
    try {
      final snapshot = await _firestore
          .collection(_collectionPath)
          .where('ativa', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => MensagemAniversario.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Erro ao buscar mensagens: $e');
      return [];
    }
  }

  // Buscar uma mensagem aleatória
  Future<MensagemAniversario?> getMensagemAleatoria() async {
    try {
      final snapshot = await _firestore
          .collection(_collectionPath)
          .where('ativa', isEqualTo: true)
          .get();

      if (snapshot.docs.isEmpty) {
        // Se não houver mensagens, retorna null (vamos tratar depois)
        return null;
      }

      // Escolhe um índice aleatório
      final randomIndex = DateTime.now().millisecondsSinceEpoch % snapshot.docs.length;
      return MensagemAniversario.fromFirestore(snapshot.docs[randomIndex]);
    } catch (e) {
      print('❌ Erro ao buscar mensagem aleatória: $e');
      return null;
    }
  }

  // Buscar mensagens por categoria
  Future<List<MensagemAniversario>> getMensagensPorCategoria(String categoria) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionPath)
          .where('ativa', isEqualTo: true)
          .where('categoria', isEqualTo: categoria)
          .get();

      return snapshot.docs
          .map((doc) => MensagemAniversario.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Erro ao buscar mensagens por categoria: $e');
      return [];
    }
  }

  // Inicializar com mensagens padrão (chamar uma vez)
  Future<void> inicializarMensagensPadrao() async {
    final snapshot = await _firestore.collection(_collectionPath).get();
    if (snapshot.docs.isNotEmpty) {
      print('✅ Mensagens já existem no banco!');
      return;
    }

    final mensagensPadrao = [
      // Mensagens NEUTRAS (sem menção específica a capoeira)
      {
        'texto': 'Feliz aniversário, {nome}! Que Deus abençoe sua vida com saúde, paz e muitas alegrias. 🎂',
        'categoria': 'neutra',
      },
      {
        'texto': 'Parabéns, {nome}! Que seu dia seja especial e seu ano repleto de realizações. 🎉',
        'categoria': 'neutra',
      },
      {
        'texto': '{nome}, hoje é seu dia! Que venham muitos anos de vida pela frente. Feliz aniversário! 🎈',
        'categoria': 'neutra',
      },
      {
        'texto': 'Feliz aniversário, {nome}! Que você continue sendo essa pessoa iluminada. Sucesso sempre! ✨',
        'categoria': 'neutra',
      },
      {
        'texto': 'Parabéns, {nome}! Que seu caminho seja sempre de luz e muitas conquistas. 🎊',
        'categoria': 'neutra',
      },
      {
        'texto': 'Hoje é dia de festa! Feliz aniversário, {nome}! Que Deus realize todos os seus sonhos. 🎂',
        'categoria': 'neutra',
      },
      {
        'texto': '{nome}, que seu aniversário seja o início de um ano incrível! Muitas felicidades. 🎁',
        'categoria': 'neutra',
      },
      {
        'texto': 'Feliz aniversário, {nome}! Que a alegria e o amor estejam sempre presentes em sua vida. ❤️',
        'categoria': 'neutra',
      },
      {
        'texto': 'Parabéns, {nome}! Mais um ano de vida, mais um ano de bênçãos. Aproveite seu dia! 🎉',
        'categoria': 'neutra',
      },
      {
        'texto': '{nome}, hoje é seu dia especial! Que você seja muito feliz e realizado. Parabéns! 🎈',
        'categoria': 'neutra',
      },
      {
        'texto': 'Feliz aniversário, {nome}! Que Deus continue te abençoando e guiando seus passos. 🙏',
        'categoria': 'neutra',
      },
      {
        'texto': 'Parabéns, {nome}! Que seu ano seja cheio de saúde, paz e prosperidade. 🎂',
        'categoria': 'neutra',
      },
      {
        'texto': '{nome}, hoje celebramos sua vida! Que venham muitos anos pela frente. Feliz aniversário! 🎊',
        'categoria': 'neutra',
      },
      {
        'texto': 'Feliz aniversário, {nome}! Que você continue sendo essa pessoa incrível. Abraço grande! 🎁',
        'categoria': 'neutra',
      },
      {
        'texto': 'Parabéns, {nome}! Que seu dia seja lindo como você merece. Muita saúde e sucesso! 🎉',
        'categoria': 'neutra',
      },
      {
        'texto': '{nome}, hoje é seu grande dia! Que Deus abençoe e ilumine sempre seu caminho. 🎈',
        'categoria': 'neutra',
      },
      {
        'texto': 'Feliz aniversário, {nome}! Que a felicidade more no seu coração todos os dias. ❤️',
        'categoria': 'neutra',
      },
      {
        'texto': 'Parabéns, {nome}! Mais um ano de histórias e conquistas. Viva essa data especial! 🎂',
        'categoria': 'neutra',
      },
      {
        'texto': '{nome}, desejo um aniversário maravilhoso e um ano cheio de coisas boas! 🎉',
        'categoria': 'neutra',
      },
      {
        'texto': 'Feliz aniversário, {nome}! Que todos os seus sonhos se realizem. Axé (paz e energia positiva)! 🕊️',
        'categoria': 'neutra',
      },
    ];

    for (var msg in mensagensPadrao) {
      await _firestore.collection(_collectionPath).add({
        ...msg,
        'ativa': true,
        'criada_em': FieldValue.serverTimestamp(),
      });
    }

    print('✅ ${mensagensPadrao.length} mensagens padrão inicializadas!');
  }
}