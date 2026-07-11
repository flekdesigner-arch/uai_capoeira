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

    // Pergunta pública sem gabarito, mas ainda admin-only nesta fase.
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

  console.log("Teste 3: aluno NÃO consegue ler perguntas nesta fase...");
  await assertFails(getDoc(doc(alunoDb, "estudos_perguntas/pergunta_001")));

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