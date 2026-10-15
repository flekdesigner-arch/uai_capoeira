import 'dart:io' show stdout;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  stdout.writeln('🚀 INICIANDO SETUP FIREBASE...');

  try {
    await Firebase.initializeApp();
    final firestore = FirebaseFirestore.instance;

    stdout.writeln('✅ Firebase conectado!');
    stdout.writeln('📊 Criando academia CENTRO DE CONVIVIO...');

    final academiaData = {
      'nome': 'CENTRO DE CONVIVIO',
      'cidade': 'BOCAIUVA-MG',
      'modalidade': 'CAPOEIRA',
      'professor': 'TICO-TICO',
      'logo_url':
          'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/JEmRdvRYw6JD14UcSnby.jpg',
      'whatsapp_url': 'https://chat.whatsapp.com/DmOMLyuoBou3Ax7WQvAbTE',
      'responsavel': 'TICO-TICO',
      'endereco': 'Centro de Convivio - Bocaiúva-MG',
      'turmas_count': 2,
      'status': 'ativa',
      'criado_em': FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
    };

    final academiaRef = await firestore
        .collection('academias')
        .add(academiaData);
    stdout.writeln('✅ Academia criada! ID: ${academiaRef.id}');

    stdout.writeln('🎓 Criando 2 turmas...');

    final turma1 = {
      'nome': '19:00 AS 20:30',
      'horario': '19:00 às 20:30',
      'logo_url':
          'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/x7fzZFECzpbjdTplh0g7.jpg',
      'cidade': 'BOCAIUVA-MG',
      'nucleo': 'CENTRO DE CONVIVIO',
      'modalidade': 'CAPOEIRA',
      'whatsapp_url': 'https://chat.whatsapp.com/DmOMLyuoBou3Ax7WQvAbTE',
      'academia_id': academiaRef.id,
      'professor': 'TICO-TICO',
      'capacidade_maxima': 30,
      'alunos_count': 0,
      'status': 'ativa',
      'dias_semana': ['Segunda', 'Quarta', 'Sexta'],
      'faixa_etaria': 'Livre',
      'criado_em': FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
    };

    final turma2 = {
      'nome': '18:00 AS 19:00',
      'horario': '18:00 às 19:00',
      'logo_url':
          'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/AqQPRSDgpWpmyD3UByd7.jpg',
      'cidade': 'BOCAIUVA-MG',
      'nucleo': 'CENTRO DE CONVIVIO',
      'modalidade': 'CAPOEIRA',
      'whatsapp_url': 'https://chat.whatsapp.com/DmOMLyuoBou3Ax7WQvAbTE',
      'academia_id': academiaRef.id,
      'professor': 'TICO-TICO',
      'capacidade_maxima': 25,
      'alunos_count': 0,
      'status': 'ativa',
      'dias_semana': ['Terça', 'Quinta'],
      'faixa_etaria': 'Infantil (6-12 anos)',
      'criado_em': FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
    };

    await academiaRef.collection('turmas').add(turma1);
    stdout.writeln('   ✅ Turma 1: 19:00 AS 20:30');

    await academiaRef.collection('turmas').add(turma2);
    stdout.writeln('   ✅ Turma 2: 18:00 AS 19:00');

    await academiaRef.update({'turmas_count': 2});

    stdout.writeln('');
    stdout.writeln('==========================================');
    stdout.writeln('🎉 SETUP COMPLETO!');
    stdout.writeln('==========================================');
    stdout.writeln('📊 1 Academia criada');
    stdout.writeln('🎓 2 Turmas criadas');
    stdout.writeln('🔗 Tudo vinculado automaticamente');
    stdout.writeln('📍 ID da Academia: ${academiaRef.id}');
    stdout.writeln('==========================================');
  } catch (e) {
    stdout.writeln('❌ ERRO: ${e.toString()}');
    stdout.writeln('');
    stdout.writeln('🔧 Tente criar manualmente:');
    stdout.writeln('1. Acesse: https://console.firebase.google.com/');
    stdout.writeln('2. Coleção: academias');
    stdout.writeln('3. Subcoleção: turmas');
  }
}
