# Fase 2F1 - Midias por URL em Estudos/Fundamentos

## Objetivo

Adicionar suporte visual por URL para ciclos e estudos, sem upload de arquivos e sem alterar Rules, Functions ou Storage.

## Campos usados

### Ciclos

- `capaUrl`: URL publica da capa do ciclo. O campo ja existia no `EstudoCicloModel` e continua opcional.

### Estudos

- `capaUrl`: URL publica da capa do estudo. O campo ja existia no `EstudoModel` e continua opcional.
- `imagensUrls`: lista de URLs públicas exibidas dentro do artigo do estudo.

Compatibilidade:

- estudos antigos sem `imagensUrls` carregam lista vazia;
- URLs vazias são removidas;
- duplicadas simples sao removidas;
- os textos sao salvos com `trim`;
- links comuns do Google Drive são normalizados quando o ID do arquivo é encontrado.

## Como cadastrar capas

No admin de ciclos, use o campo `Capa URL opcional` para informar uma imagem publica do ciclo.

No admin de estudos, use o campo `Capa URL opcional` para informar uma imagem publica do estudo.

## Como cadastrar multiplas imagens

No admin de estudos, a secao de midia possui o campo `Imagens do estudo`.

Informe uma URL por linha. Para remover uma imagem, remova a linha correspondente e salve o estudo.

## Como aparece para o aluno

- A capa do ciclo aparece na lista/timeline de ciclos e no topo da tela do ciclo.
- A capa do estudo aparece no card do estudo e no detalhe do artigo.
- As imagens de `imagensUrls` aparecem dentro do artigo, apos o texto principal e antes dos blocos complementares.
- Imagens inválidas mostram um aviso visual pequeno e não travam o artigo.

## Google Drive

Links no formato:

```text
https://drive.google.com/file/d/FILE_ID/view?usp=sharing
```

podem ser convertidos para:

```text
https://drive.google.com/uc?export=view&id=FILE_ID
```

O arquivo precisa estar público. A conversão automática só acontece para `drive.google.com`, `www.drive.google.com` ou subdomínios que terminem em `.drive.google.com`. Se o ID não puder ser extraído, a URL original é mantida.

## Seguranca

- O app não baixa imagens no servidor.
- Nenhum arquivo e salvo no Firebase Storage nesta fase.
- Firestore Rules não foram alteradas.
- O app salva apenas strings de URL.
- Nao ha HTML bruto nem execucao de conteudo externo.

## Limitacoes

- Upload real para Firebase Storage fica para a Fase 2F2.
- Links privados do Google Drive não carregam para alunos.
- URLs quebradas exibem fallback visual.

## Validacao

Rodar:

```bash
dart analyze lib/modules/estudos_fundamentos
```

## Confirmacao

Nenhum deploy foi executado.
Nenhum APK foi gerado.
Rules não foram alteradas.
Functions não foram alteradas.
pubspec.yaml não foi alterado.
