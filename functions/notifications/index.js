const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

// FUNÇÃO QUE RODA TODO DIA ÀS 8:00
exports.sendBirthdayNotifications = functions.pubsub
    .schedule('0 8 * * *')
    .timeZone('America/Sao_Paulo')
    .onRun(async (context) => {
        const today = new Date();
        const month = today.getMonth() + 1;
        const day = today.getDate();

        console.log(`🔔 Verificando aniversariantes para ${day}/${month}...`);

        try {
            // Buscar alunos ATIVOS
            const alunosSnapshot = await db
                .collection('alunos')
                .where('status_atividade', '==', 'ATIVO(A)')
                .get();

            const birthdayStudents = [];
            
            alunosSnapshot.forEach(doc => {
                const data = doc.data();
                if (data.data_nascimento) {
                    let birthDate;
                    
                    // Verifica se é Timestamp do Firestore ou String
                    if (data.data_nascimento.toDate) {
                        birthDate = data.data_nascimento.toDate();
                    } else {
                        // Formato: DD/MM/AAAA
                        const [d, m, a] = data.data_nascimento.split('/');
                        birthDate = new Date(parseInt(a), parseInt(m) - 1, parseInt(d));
                    }
                    
                    if (birthDate.getDate() === day && 
                        birthDate.getMonth() + 1 === month) {
                        birthdayStudents.push(data.nome || data.apelido || 'Aluno');
                    }
                }
            });

            if (birthdayStudents.length === 0) {
                console.log('😴 Nenhum aniversariante hoje');
                return null;
            }

            console.log(`🎉 ${birthdayStudents.length} aniversariante(s) hoje!`);
            console.log('📋 Lista:', birthdayStudents.join(', '));

            // Buscar tokens FCM de TODOS os usuários ativos
            const usuariosSnapshot = await db
                .collection('usuarios')
                .where('status_conta', '==', 'ativa')
                .get();

            const tokens = [];
            usuariosSnapshot.forEach(doc => {
                const data = doc.data();
                if (data.fcm_tokens && Array.isArray(data.fcm_tokens)) {
                    tokens.push(...data.fcm_tokens);
                }
            });

            if (tokens.length === 0) {
                console.log('😴 Nenhum token FCM encontrado');
                return null;
            }

            // Remover tokens duplicados
            const uniqueTokens = [...new Set(tokens)];
            console.log(`📱 Enviando para ${uniqueTokens.length} dispositivos`);

            // Criar mensagem personalizada
            let title = '';
            let body = '';

            if (birthdayStudents.length === 1) {
                title = '🎉 Aniversariante do Dia!';
                body = `${birthdayStudents[0]} está fazendo aniversário hoje! 🎂`;
            } else {
                title = `🎉 ${birthdayStudents.length} Aniversariantes Hoje!`;
                body = `Hoje fazem aniversário: ${birthdayStudents.join(', ')}`;
            }

            // Configurar mensagem
            const message = {
                notification: {
                    title: title,
                    body: body
                },
                tokens: uniqueTokens
            };

            // Enviar notificações
            const response = await admin.messaging().sendEachForMulticast(message);
            
            console.log('✅ ===== RELATÓRIO =====');
            console.log(`✅ Sucessos: ${response.successCount}`);
            console.log(`❌ Falhas: ${response.failureCount}`);
            console.log('✅ ===== FIM =====');

            return null;

        } catch (error) {
            console.error('❌ ERRO:', error);
            return null;
        }
    });