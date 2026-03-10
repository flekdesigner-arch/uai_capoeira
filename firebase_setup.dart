
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
print('🚀 INICIANDO SETUP FIREBASE...');

try {
await Firebase.initializeApp();
final firestore = FirebaseFirestore.instance;

print('✅ Firebase conectado!');
print('📊 Criando academia CENTRO DE CONVIVIO...');

final academiaData = {
'nome': 'CENTRO DE CONVIVIO',
'cidade': 'BOCAIUVA-MG',
'modalidade': 'CAPOEIRA',
'professor': 'TICO-TICO',
'logo_url': 'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/JEmRdvRYw6JD14UcSnby.jpg',
'whatsapp_url': 'https://chat.whatsapp.com/DmOMLyuoBou3Ax7WQvAbTE',
'responsavel': 'TICO-TICO',
'endereco': 'Centro de Convivio - Bocaiúva-MG',
'turmas_count': 2,
'status': 'ativa',
'criado_em': FieldValue.serverTimestamp(),
'atualizado_em': FieldValue.serverTimestamp(),
};

final academiaRef = await firestore.collection('academias').add(academiaData);
print('✅ Academia criada! ID: ' + academiaRef.id);

print('🎓 Criando 2 turmas...');

final turma1 = {
'nome': '19:00 AS 20:30',
'horario': '19:00 às 20:30',
'logo_url': 'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/x7fzZFECzpbjdTplh0g7.jpg',
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
'logo_url': 'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/AqQPRSDgpWpmyD3UByd7.jpg',
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
print('   ✅ Turma 1: 19:00 AS 20:30');

await academiaRef.collection('turmas').add(turma2);
print('   ✅ Turma 2: 18:00 AS 19:00');

await academiaRef.update({'turmas_count': 2});

print('');
print('==========================================');
print('🎉 SETUP COMPLETO!');
print('==========================================');
print('📊 1 Academia criada');
print('🎓 2 Turmas criadas');
print('🔗 Tudo vinculado automaticamente');
print('📍 ID da Academia: ' + academiaRef.id);
print('==========================================');

} catch (e) {
print('❌ ERRO: ' + e.toString());
print('');
print('🔧 Tente criar manualmente:');
print('1. Acesse: https://console.firebase.google.com/');
print('2. Coleção: academias');
print('3. Subcoleção: turmas');
}
}
