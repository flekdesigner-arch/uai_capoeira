const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

const {
  doc,
  setDoc,
  getDoc,
  collection,
  query,
  where,
  getDocs,
} = require("firebase/firestore");

const PROJECT_ID = "demo-uai-capoeira-rules";
const RULES_PATH = path.resolve(__dirname, "../firestore.rules");

async function main() {
  console.log("Iniciando testes funcionais das Firestore Rules...");
  console.log("Rules:", RULES_PATH);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8085,
    },
  });

  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // Config do módulo Estudos.
    await setDoc(doc(db, "estudos_config/global"), {
      ativo: true,
      mostrarCardAreaAluno: true,
      mostrarEmBreve: true,
    });

    // Usuário admin amplo.
    await setDoc(doc(db, "usuarios/admin_uid"), {
      tipo: "admin",
      peso_permissao: 100,
      status_conta: "ativa",
    });

    // Usuário aluno comum.
    await setDoc(doc(db, "usuarios/aluno_uid"), {
      tipo: "aluno",
      peso_permissao: 0,
      status_conta: "ativa",
    });

    // Aluno vinculado ao Google aluno_uid.
    await setDoc(doc(db, "alunos/aluno_001"), {
      nome: "Aluno Teste",
      areaAlunoGoogleVinculado: true,
      areaAlunoGoogleUid: "aluno_uid",
    });

    // Outro aluno que NÃO pertence ao aluno_uid.
    await setDoc(doc(db, "alunos/aluno_002"), {
      nome: "Outro Aluno",
      areaAlunoGoogleVinculado: true,
      areaAlunoGoogleUid: "outro_uid",
    });

    // Ciclo publicado.
    await setDoc(doc(db, "estudos_ciclos/ciclo_001"), {
      titulo: "Ciclo Publicado",
      status: "publicado",
      mostrarNaLinhaDoTempo: true,
    });

    // Estudo publicado.
    await setDoc(doc(db, "estudos/estudo_publicado"), {
      titulo: "Estudo Publicado",
      cicloId: "ciclo_001",
      status: "publicado",
      mostrarNaLinhaDoTempo: true,
    });

    // Estudo rascunho.
    await setDoc(doc(db, "estudos/estudo_rascunho"), {
      titulo: "Estudo Rascunho",
      cicloId: "ciclo_001",
      status: "rascunho",
      mostrarNaLinhaDoTempo: true,
    });

    // Pergunta publica segura para aluno responder.
    await setDoc(doc(db, "estudos_perguntas/pergunta_001"), {
      cicloId: "ciclo_001",
      estudoId: "estudo_publicado",
      enunciado: "Pergunta de teste",
      tipo: "multipla_escolha",
      status: "ativa",
      alternativasPublicas: [
        { id: "a", texto: "A", ordem: 1 },
        { id: "b", texto: "B", ordem: 2 },
      ],
    });

    await setDoc(doc(db, "estudos_perguntas/pergunta_sensivel"), {
      cicloId: "ciclo_001",
      estudoId: "estudo_publicado",
      enunciado: "Pergunta sensivel",
      tipo: "multipla_escolha",
      status: "ativa",
      alternativasPublicas: [
        { id: "a", texto: "A", ordem: 1 },
        { id: "b", texto: "B", ordem: 2 },
      ],
      alternativaCorretaId: "a",
    });

    await setDoc(doc(db, "alunos_estudos_resultados/aluno_001/estudos/estudo_publicado"), {
      alunoId: "aluno_001",
      googleUid: "aluno_uid",
      estudoId: "estudo_publicado",
      cicloId: "ciclo_001",
      melhorPercentual: 80,
      ultimoPercentual: 80,
      ultimaTentativaId: "tentativa_001",
      tentativasCount: 1,
      aprovado: true,
      status: "finalizada",
      origem: "cloud_function",
    });

    await setDoc(doc(db, "estudos_tentativas/tentativa_001"), {
      tentativaId: "tentativa_001",
      alunoId: "aluno_001",
      googleUid: "aluno_uid",
      estudoId: "estudo_publicado",
      cicloId: "ciclo_001",
      percentual: 80,
      aprovado: true,
      status: "finalizada",
      origem: "cloud_function",
    });
    // Gabarito futuro/sensível.
    await setDoc(doc(db, "estudos_gabaritos/pergunta_001"), {
      perguntaId: "pergunta_001",
      estudoId: "estudo_publicado",
      alternativaCorretaId: "a",
      justificativaCorreta: "Resposta correta de teste.",
    });
  });

  const adminDb = testEnv.authenticatedContext("admin_uid").firestore();
  const alunoDb = testEnv.authenticatedContext("aluno_uid").firestore();
  const outroDb = testEnv.authenticatedContext("outro_uid").firestore();
  const anonDb = testEnv.unauthenticatedContext().firestore();

  console.log("Teste 1: admin consegue ler gabarito...");
  await assertSucceeds(getDoc(doc(adminDb, "estudos_gabaritos/pergunta_001")));

  console.log("Teste 2: aluno NÃO consegue ler gabarito...");
  await assertFails(getDoc(doc(alunoDb, "estudos_gabaritos/pergunta_001")));

  console.log('Teste 3: aluno NAO consegue ler estudos_perguntas diretamente...');
  await assertFails(getDoc(doc(alunoDb, 'estudos_perguntas/pergunta_001')));

  console.log("Teste 3b: aluno NAO consegue listar estudos_perguntas mesmo com estudoId/status...");
  await assertFails(
    getDocs(
      query(
        collection(alunoDb, "estudos_perguntas"),
        where("estudoId", "==", "estudo_publicado"),
        where("status", "==", "ativa")
      )
    )
  );

  console.log("Teste 3c: aluno NAO consegue listar perguntas sem filtro de status...");
  await assertFails(
    getDocs(
      query(
        collection(alunoDb, "estudos_perguntas"),
        where("estudoId", "==", "estudo_publicado")
      )
    )
  );
  console.log("Teste 3d: admin consegue ler estudos_perguntas...");
  await assertSucceeds(getDoc(doc(adminDb, "estudos_perguntas/pergunta_001")));
  console.log("Teste 4: aluno consegue ler estudo publicado...");
  await assertSucceeds(getDoc(doc(alunoDb, "estudos/estudo_publicado")));

  console.log("Teste 5: aluno NÃO consegue ler estudo rascunho...");
  await assertFails(getDoc(doc(alunoDb, "estudos/estudo_rascunho")));

  console.log("Teste 6: anônimo NÃO consegue ler estudo publicado...");
  await assertFails(getDoc(doc(anonDb, "estudos/estudo_publicado")));

  console.log("Teste 7: aluno consegue gravar progresso dele...");
  await assertSucceeds(
    setDoc(doc(alunoDb, "alunos_estudos_progresso/aluno_001/estudos/estudo_publicado"), {
      alunoId: "aluno_001",
      googleUid: "aluno_uid",
      estudoId: "estudo_publicado",
      cicloId: "ciclo_001",
      status: "concluido",
      iniciadoEm: new Date(),
      concluidoEm: new Date(),
      atualizadoEm: new Date(),
      ultimaVisualizacaoEm: new Date(),
      percentualLeitura: 100,
      origem: "teste_rules",
    })
  );

  console.log("Teste 8: aluno NÃO consegue gravar progresso de outro aluno...");
  await assertFails(
    setDoc(doc(alunoDb, "alunos_estudos_progresso/aluno_002/estudos/estudo_publicado"), {
      alunoId: "aluno_002",
      googleUid: "aluno_uid",
      estudoId: "estudo_publicado",
      cicloId: "ciclo_001",
      status: "concluido",
      iniciadoEm: new Date(),
      concluidoEm: new Date(),
      atualizadoEm: new Date(),
      ultimaVisualizacaoEm: new Date(),
      percentualLeitura: 100,
      origem: "teste_rules",
    })
  );

  console.log("Teste 9: aluno NÃO consegue gravar campo proibido nota...");
  await assertFails(
    setDoc(doc(alunoDb, "alunos_estudos_progresso/aluno_001/estudos/estudo_publicado_com_nota"), {
      alunoId: "aluno_001",
      googleUid: "aluno_uid",
      estudoId: "estudo_publicado_com_nota",
      cicloId: "ciclo_001",
      status: "concluido",
      iniciadoEm: new Date(),
      concluidoEm: new Date(),
      atualizadoEm: new Date(),
      ultimaVisualizacaoEm: new Date(),
      percentualLeitura: 100,
      origem: "teste_rules",
      nota: 10,
    })
  );

  console.log("Teste 10: outro usuário NÃO consegue acessar progresso do aluno_001...");
  await assertFails(getDoc(doc(outroDb, "alunos_estudos_progresso/aluno_001/estudos/estudo_publicado")));


  console.log("Teste 11: aluno NAO consegue ler pergunta com campo sensivel alternativaCorretaId...");
  await assertFails(getDoc(doc(alunoDb, "estudos_perguntas/pergunta_sensivel")));

  console.log("Teste 12: aluno consegue ler proprio resultado resumido...");
  await assertSucceeds(getDoc(doc(alunoDb, "alunos_estudos_resultados/aluno_001/estudos/estudo_publicado")));

  console.log("Teste 13: aluno NAO consegue escrever proprio resultado oficial...");
  await assertFails(
    setDoc(doc(alunoDb, "alunos_estudos_resultados/aluno_001/estudos/estudo_publicado"), {
      alunoId: "aluno_001",
      googleUid: "aluno_uid",
      estudoId: "estudo_publicado",
      cicloId: "ciclo_001",
      melhorPercentual: 100,
      ultimoPercentual: 100,
      ultimaTentativaId: "tentativa_cliente",
      tentativasCount: 99,
      aprovado: true,
      status: "finalizada",
      origem: "cliente",
    })
  );

  console.log("Teste 14: outro aluno NAO consegue ler resultado de aluno diferente...");
  await assertFails(getDoc(doc(outroDb, "alunos_estudos_resultados/aluno_001/estudos/estudo_publicado")));


  console.log("Teste 15: admin consegue ler tentativa oficial...");
  await assertSucceeds(getDoc(doc(adminDb, "estudos_tentativas/tentativa_001")));

  console.log("Teste 16: aluno NAO consegue ler historico completo de tentativas nesta fase...");
  await assertFails(getDoc(doc(alunoDb, "estudos_tentativas/tentativa_001")));

  console.log("Teste 17: aluno NAO consegue escrever tentativa oficial...");
  await assertFails(
    setDoc(doc(alunoDb, "estudos_tentativas/tentativa_cliente"), {
      tentativaId: "tentativa_cliente",
      alunoId: "aluno_001",
      googleUid: "aluno_uid",
      estudoId: "estudo_publicado",
      percentual: 100,
      aprovado: true,
      origem: "cliente",
    })
  );

  await testEnv.cleanup();

  console.log("");
  console.log("TODOS OS TESTES FUNCIONAIS DAS RULES PASSARAM ✅");
  console.log("Nenhum deploy foi feito.");
  console.log("Gabarito continua sem acesso para aluno.");
}

main().catch((error) => {
  console.error("");
  console.error("TESTE FALHOU ❌");
  console.error(error);
  process.exit(1);
});