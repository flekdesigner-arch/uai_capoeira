const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

exports.sendBirthdayNotifications = onSchedule('0 8 * * *', async (event) => {
    const today = new Date();
    const month = today.getMonth() + 1;
    const day = today.getDate();

    console.log(`🔔 Verificando aniversariantes para ${day}/${month}...`);

    try {
        const alunosSnapshot = await db
            .collection('alunos')
            .where('status_atividade', '==', 'ATIVO(A)')
            .get();

        const birthdayStudents = [];
        
        alunosSnapshot.forEach(doc => {
            const data = doc.data();
            if (data.data_nascimento) {
                let birthDate;
                if (data.data_nascimento.toDate) {
                    birthDate = data.data_nascimento.toDate();
                } else {
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
            return;
        }

        console.log(`🎉 ${birthdayStudents.length} aniversariante(s) hoje!`);

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
            return;
        }

        const uniqueTokens = [...new Set(tokens)];

        const title = birthdayStudents.length === 1 
            ? '🎉 Aniversariante do Dia!'
            : `🎉 ${birthdayStudents.length} Aniversariantes Hoje!`;

        const body = birthdayStudents.length === 1
            ? `${birthdayStudents[0]} está fazendo aniversário hoje! 🎂`
            : `Hoje fazem aniversário: ${birthdayStudents.join(', ')}`;

        const message = {
            notification: { title, body },
            tokens: uniqueTokens
        };

        const response = await admin.messaging().sendEachForMulticast(message);
        
        console.log(`✅ ${response.successCount} notificações enviadas`);
        console.log(`❌ ${response.failureCount} falhas`);

    } catch (error) {
        console.error('❌ Erro:', error);
    }
});