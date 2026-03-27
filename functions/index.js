const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { Storage } = require('@google-cloud/storage');

admin.initializeApp();

const db = admin.firestore();
const storage = new Storage();
const bucketName = 'uai-capoeira-52753.firebasestorage.app';

// ============================================
// FUNÇÃO 1: NOTIFICAÇÕES DE ANIVERSARIANTES
// Executa todo dia às 8h
// ============================================
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

// ============================================
// FUNÇÃO 2: PROCESSAR CHAMADA EM LOTE
// Chamada pelo app Flutter
// ============================================
exports.processarChamada = onCall(async (request) => {
    // Verificar autenticação
    if (!request.auth) {
        throw new Error('Usuário não autenticado');
    }

    const data = request.data;
    
    const {
        turmaId,
        turmaNome,
        academiaId,
        academiaNome,
        dataChamada,
        alunos,
        tipoAula,
        professorId,
        professorNome
    } = data;

    const batch = db.batch();
    const chamadaRef = db.collection('chamadas').doc();
    
    // Formatar data
    const dataObj = new Date(dataChamada);
    const dataFormatada = dataObj.toISOString().split('T')[0];
    
    // Contar presentes
    const presentes = alunos.filter(a => a.presente).length;
    const ausentes = alunos.length - presentes;
    const porcentagem = alunos.length > 0 ? Math.round((presentes / alunos.length) * 100) : 0;
    
    // Dados da chamada principal
    const chamadaData = {
        turma_id: turmaId,
        turma_nome: turmaNome,
        academia_id: academiaId,
        academia_nome: academiaNome,
        data_chamada: admin.firestore.Timestamp.fromDate(dataObj),
        data_formatada: dataFormatada,
        tipo_aula: tipoAula,
        total_alunos: alunos.length,
        presentes: presentes,
        ausentes: ausentes,
        porcentagem_frequencia: porcentagem,
        professor_id: professorId,
        professor_nome: professorNome,
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
        alunos: alunos.map(aluno => ({
            aluno_id: aluno.id,
            aluno_nome: aluno.nome,
            presente: aluno.presente,
            observacao: aluno.observacao || ''
        }))
    };
    
    batch.set(chamadaRef, chamadaData);
    
    // Processar cada aluno
    const logs = [];
    const updates = [];
    
    for (const aluno of alunos) {
        const alunoId = aluno.id;
        const presente = aluno.presente;
        const mesAno = dataFormatada.substring(0, 7); // YYYY-MM
        
        // 1. Atualizar contador de presença mensal
        updates.push(
            db.collection('alunos').doc(alunoId).update({
                [`contadores.${mesAno}`]: admin.firestore.FieldValue.increment(presente ? 1 : 0)
            }).catch(err => console.error(`Erro ao atualizar contador ${alunoId}:`, err))
        );
        
        // 2. Atualizar última presença (se presente)
        if (presente) {
            updates.push(
                db.collection('alunos').doc(alunoId).update({
                    ultima_presenca: admin.firestore.Timestamp.fromDate(dataObj),
                    ultimo_dia_presente: dataFormatada
                }).catch(err => console.error(`Erro ao atualizar ultima_presenca ${alunoId}:`, err))
            );
        }
        
        // 3. Criar log de presença
        logs.push({
            log_id: `log_${alunoId}_${dataFormatada}`,
            aluno_id: alunoId,
            aluno_nome: aluno.nome,
            turma_id: turmaId,
            turma_nome: turmaNome,
            academia_id: academiaId,
            academia_nome: academiaNome,
            data_aula: admin.firestore.Timestamp.fromDate(dataObj),
            data_formatada: dataFormatada,
            presente: presente,
            observacao: aluno.observacao || '',
            professor_id: professorId,
            professor_nome: professorNome,
            registrado_em: admin.firestore.FieldValue.serverTimestamp(),
            tipo_registro: 'chamada_turma'
        });
        
        // 4. Atualizar última chamada
        updates.push(
            db.collection('alunos').doc(alunoId).update({
                ultima_chamada: admin.firestore.FieldValue.serverTimestamp(),
                ultima_chamada_por: professorNome,
                ultima_chamada_por_id: professorId
            }).catch(err => console.error(`Erro ao atualizar ultima_chamada ${alunoId}:`, err))
        );
    }
    
    // Executar tudo em paralelo
    await Promise.all([
        batch.commit(),
        ...updates,
        ...logs.map(log => db.collection('log_presenca_alunos').add(log))
    ]);
    
    // Limpar lock da chamada
    await db.collection('locks_chamada').doc(turmaId).delete().catch(() => {});
    
    return {
        success: true,
        chamadaId: chamadaRef.id,
        processados: alunos.length,
        presentes: presentes,
        ausentes: ausentes
    };
});

// ============================================
// FUNÇÃO 3: EXCLUIR CHAMADA (COM REVERSÃO COMPLETA)
// ============================================
exports.excluirChamada = onCall(async (request) => {
    // Verificar autenticação
    if (!request.auth) {
        throw new Error('Usuário não autenticado');
    }

    const { chamadaId, turmaId } = request.data;

    if (!chamadaId || !turmaId) {
        throw new Error('Parâmetros obrigatórios: chamadaId e turmaId');
    }

    const batch = db.batch();

    // 1️⃣ BUSCAR DADOS DA CHAMADA
    const chamadaDoc = await db.collection('chamadas').doc(chamadaId).get();

    if (!chamadaDoc.exists) {
        throw new Error('Chamada não encontrada');
    }

    const chamadaData = chamadaDoc.data();
    const alunos = chamadaData.alunos || [];
    const dataFormatada = chamadaData.data_formatada;
    const dataChamada = chamadaData.data_chamada.toDate();

    // 2️⃣ BUSCAR TODOS OS LOGS DESTA CHAMADA
    const logsQuery = await db
        .collection('log_presenca_alunos')
        .where('data_formatada', '==', dataFormatada)
        .where('turma_id', '==', turmaId)
        .get();

    // 3️⃣ PROCESSAR CADA ALUNO
    const updates = [];

    for (const aluno of alunos) {
        const alunoId = aluno.aluno_id;
        const estavaPresente = aluno.presente;
        const mesAno = dataFormatada.substring(0, 7);

        // 🔥 DECREMENTAR CONTADOR (se estava presente)
        if (estavaPresente) {
            updates.push(
                db.collection('alunos').doc(alunoId).update({
                    [`contadores.${mesAno}`]: admin.firestore.FieldValue.increment(-1)
                }).catch(err => console.error(`Erro ao decrementar contador ${alunoId}:`, err))
            );
        }

        // 🔥 RECALCULAR ÚLTIMA PRESENÇA
        const ultimaPresencaQuery = await db
            .collection('log_presenca_alunos')
            .where('aluno_id', '==', alunoId)
            .where('presente', '==', true)
            .where('data_aula', '<', dataChamada)
            .orderBy('data_aula', 'desc')
            .limit(1)
            .get();

        const alunoRef = db.collection('alunos').doc(alunoId);

        if (ultimaPresencaQuery.docs.isNotEmpty) {
            const ultimaPresenca = ultimaPresencaQuery.docs.first.data().data_aula;
            updates.push(
                alunoRef.update({
                    ultimo_dia_presente: ultimaPresenca
                }).catch(err => console.error(`Erro ao atualizar ultima_presenca ${alunoId}:`, err))
            );
        } else {
            updates.push(
                alunoRef.update({
                    ultimo_dia_presente: null
                }).catch(err => console.error(`Erro ao remover ultima_presenca ${alunoId}:`, err))
            );
        }

        // 🔥 RECALCULAR ÚLTIMA CHAMADA
        const ultimaChamadaQuery = await db
            .collection('log_presenca_alunos')
            .where('aluno_id', '==', alunoId)
            .orderBy('data_aula', 'desc')
            .limit(1)
            .get();

        if (ultimaChamadaQuery.docs.isNotEmpty) {
            const ultimaChamada = ultimaChamadaQuery.docs.first.data();
            updates.push(
                alunoRef.update({
                    ultima_chamada: ultimaChamada.data_aula,
                    ultima_chamada_por: ultimaChamada.professor_nome || null,
                    ultima_chamada_por_id: ultimaChamada.professor_id || null
                }).catch(err => console.error(`Erro ao atualizar ultima_chamada ${alunoId}:`, err))
            );
        } else {
            updates.push(
                alunoRef.update({
                    ultima_chamada: null,
                    ultima_chamada_por: null,
                    ultima_chamada_por_id: null
                }).catch(err => console.error(`Erro ao remover ultima_chamada ${alunoId}:`, err))
            );
        }
    }

    // 4️⃣ DELETAR CHAMADA E LOGS
    batch.delete(chamadaDoc.ref);
    for (const logDoc of logsQuery.docs) {
        batch.delete(logDoc.ref);
    }

    // 5️⃣ EXECUTAR TUDO
    await Promise.all([
        batch.commit(),
        ...updates
    ]);

    return {
        success: true,
        logsExcluidos: logsQuery.docs.length,
        alunosProcessados: alunos.length
    };
});

// ============================================
// FUNÇÃO 4: RESTAURAR FOTOS DO BACKUP (COM TIMEOUT AUMENTADO)
// ============================================
exports.restaurarFotosDoBackup = onRequest(
    {
        timeoutSeconds: 540, // 9 minutos (máximo permitido)
        memory: '1GiB'       // 1GB de memória para processar mais rápido
    },
    async (req, res) => {
        // Permitir CORS
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'GET, POST');
        res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

        if (req.method === 'OPTIONS') {
            res.status(204).send('');
            return;
        }

        const bucket = storage.bucket(bucketName);
        const pastaBackup = 'backup_fotos_alunos/';

        try {
            console.log('🚀 Iniciando restauração de fotos...');

            // 1️⃣ LISTAR TODAS AS FOTOS DO BACKUP
            const [files] = await bucket.getFiles({ prefix: pastaBackup });
            
            if (files.length === 0) {
                res.status(200).json({ 
                    success: false, 
                    message: 'Nenhuma foto encontrada no backup',
                    totalFotos: 0
                });
                return;
            }

            console.log(`📸 Encontradas ${files.length} fotos no backup`);

            // 2️⃣ BUSCAR TODOS OS ALUNOS DO FIRESTORE
            const alunosSnapshot = await db.collection('alunos').get();
            
            // Criar mapa: nome do aluno (normalizado) -> dados do aluno
            const mapaAlunos = new Map();
            alunosSnapshot.docs.forEach(doc => {
                const data = doc.data();
                const nome = data.nome?.trim();
                if (nome) {
                    const nomeNormalizado = nome
                        .toLowerCase()
                        .normalize('NFD')
                        .replace(/[\u0300-\u036f]/g, '');
                    mapaAlunos.set(nomeNormalizado, {
                        id: doc.id,
                        nome: data.nome,
                        fotoAtual: data.foto_perfil_aluno
                    });
                }
            });

            console.log(`👥 ${mapaAlunos.size} alunos encontrados no Firestore`);

            // 3️⃣ PROCESSAR CADA FOTO
            const resultados = {
                totalFotos: files.length,
                atualizadas: 0,
                naoEncontrados: [],
                erros: []
            };

            for (const file of files) {
                const nomeArquivo = file.name.replace(pastaBackup, '');
                const nomeAlunoBackup = nomeArquivo
                    .replace(/\.(jpg|jpeg|png|gif)$/i, '')
                    .trim()
                    .toLowerCase()
                    .normalize('NFD')
                    .replace(/[\u0300-\u036f]/g, '');

                console.log(`🔍 Processando: ${nomeArquivo}`);

                if (!mapaAlunos.has(nomeAlunoBackup)) {
                    resultados.naoEncontrados.push(nomeArquivo);
                    console.log(`   ❌ Aluno não encontrado: ${nomeArquivo}`);
                    continue;
                }

                const aluno = mapaAlunos.get(nomeAlunoBackup);
                
                try {
                    const extensao = nomeArquivo.includes('.') ? nomeArquivo.split('.').pop() : 'jpg';
                    const nomeDestino = `fotos_perfil_alunos/${aluno.id}_${Date.now()}.${extensao}`;
                    const arquivoDestino = bucket.file(nomeDestino);
                    
                    await file.copy(arquivoDestino);
                    await arquivoDestino.makePublic();
                    
                    const publicUrl = `https://storage.googleapis.com/${bucketName}/${nomeDestino}`;
                    
                    await db.collection('alunos').doc(aluno.id).update({
                        foto_perfil_aluno: publicUrl,
                        foto_restaurada_em: admin.firestore.FieldValue.serverTimestamp(),
                        foto_backup_original: file.name
                    });
                    
                    resultados.atualizadas++;
                    console.log(`   ✅ Foto atualizada: ${aluno.nome}`);
                    
                } catch (erro) {
                    resultados.erros.push({
                        aluno: aluno.nome,
                        erro: erro.message
                    });
                    console.log(`   ❌ Erro ao processar ${aluno.nome}: ${erro.message}`);
                }
            }

            console.log(`✅ Restauração concluída! ${resultados.atualizadas} fotos atualizadas`);

            res.status(200).json({
                success: true,
                totalFotos: resultados.totalFotos,
                atualizadas: resultados.atualizadas,
                naoEncontrados: resultados.naoEncontrados,
                erros: resultados.erros,
                mensagem: `${resultados.atualizadas} fotos atualizadas com sucesso!`
            });

        } catch (erro) {
            console.error('❌ Erro na restauração:', erro);
            res.status(500).json({
                success: false,
                error: erro.message
            });
        }
    }
);