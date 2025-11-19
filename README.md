# NFC Token Registry (Hive) — README

Resumo
---
Este é um MVP em Flutter para registrar tokens NFC (ID), salvar um nome e uma foto associada e armazenar tudo localmente usando Hive. As imagens são salvas em disco (pasta `images` dentro do diretório de documentos do app) e os dados do Hive são criptografados com `HiveAesCipher`. O app também oferece exportação (backup) e importação (restore) via ZIP para facilitar migração/backup offline.

O que já foi implementado
---
- Leitura de tags NFC via `nfc_manager` e extração de ID.
- Modelo `Token` com `TypeAdapter` manual para Hive.
- Armazenamento de tokens em um `Box<Token>('tokens')`. Cada token é salvo com chave = id do token (evita duplicatas).
- Imagens capturadas com `image_picker` e gravadas em disco em: `<appDocuments>/images/<id>.<ext>`.
- Criptografia local do box usando `HiveAesCipher`. A chave (32 bytes, base64) é gerada/armazenada em `flutter_secure_storage`.
- Export (backup): gera ZIP contendo arquivos do Hive relacionados ao box `tokens`, a pasta `images/` e, se existir, `hive_key.txt` (base64) — o ZIP é salvo em `<appDocuments>/nfc_backup_<timestamp>.zip` e é aberto via share sheet.
- Import (restore): permite selecionar um ZIP, extrai seu conteúdo (substitui arquivos do app) e reabre o Hive com a chave restaurada (se houver `hive_key.txt`).

Dependências principais
---
- flutter
- hive
- hive_flutter
- path_provider
- image_picker
- nfc_manager
- flutter_secure_storage
- archive (para zip/unzip)
- file_picker (para escolher zip na importação)
- share_plus (para compartilhar o ZIP de backup)

Instalação rápida
---
1. Garanta que o Flutter está instalado e configurado.
2. No diretório do projeto:
```bash
flutter pub get
```
3. Execute no dispositivo físico (NFC não funciona em emuladores padrão):
```bash
flutter run
```

Arquivos principais modificados
---
- `lib/main.dart` — inicialização do Hive (com encriptação), lógica NFC, UI, backup/export/import.
- `lib/models/token.dart` — modelo `Token` + `TokenAdapter` manual.
- `pubspec.yaml` — dependências conforme a lista acima.

Permissões e configurações nativas
---
Android (AndroidManifest.xml):
- `<uses-permission android:name="android.permission.NFC" />`
- `<uses-permission android:name="android.permission.CAMERA" />` (para tirar fotos)
- `<uses-feature android:name="android.hardware.nfc" android:required="false" />`

iOS (Info.plist):
- `NSCameraUsageDescription` (descrição do uso da câmera)
- `NSNFCReaderUsageDescription` (descrição do uso do NFC)

Fluxos importantes do app
---
Registrar token
1. Toque em "Registrar (encoste token)".
2. Encoste o token no aparelho.
3. O app extrai o ID do token e abre um diálogo para inserir um nome e (opcionalmente) tirar foto.
4. Ao salvar: o `Token` é persistido no box `tokens` e a imagem (se houver) é salva em disco em `images/`.

Exportar backup
1. Toque no ícone de backup (AppBar).
2. O app cria um ZIP contendo:
   - Arquivos do Hive relativos ao box `tokens` (por exemplo `tokens.hive`, `tokens.lock`, etc) encontrados no diretório de documentos do app.
   - A pasta `images/` e seus arquivos.
   - Se existir, um arquivo `hive_key.txt` com a chave base64 usada para encriptar o box.
3. O ZIP é salvo em `<appDocuments>/nfc_backup_<timestamp>.zip` e aberto no share sheet para você salvar/enviar (e.g., enviar por e-mail, copiar para Google Drive, etc).

Importar backup
1. Toque no ícone de restore (AppBar).
2. Selecione o arquivo ZIP gerado anteriormente.
3. O app fecha o Hive, extrai os arquivos para o diretório de documentos do app (sobrescrevendo) e, se houver `hive_key.txt`, salva a chave em `flutter_secure_storage`.
4. O app reabre o Hive usando a chave restaurada (se presente) e mostra os dados restaurados.

Onde os dados e chaves ficam
---
- Dados Hive: `<appDocuments>/tokens.*` (arquivos do Hive, dentro do diretório de documentos do app).
- Imagens: `<appDocuments>/images/<id>.<ext>`.
- Chave de criptografia Hive: armazenada em `flutter_secure_storage` sob a chave `_secureKeyName` (no código: `'hive_key'`). O backup ZIP inclui `hive_key.txt` (base64) para facilitar a restauração — veja advertências abaixo.

Avisos de segurança (leia com atenção)
---
- O backup ZIP pode incluir `hive_key.txt` (a chave base64) se a chave existir no `flutter_secure_storage`. Isso significa que quem tiver o ZIP poderá abrir a DB criptografada. Trate o ZIP como informação sensível.
- Recomendações:
  - Armazene o ZIP em local seguro (criptografado, pasta privada, unidade externa segura).
  - Apague o ZIP quando não for mais necessário.
  - Se desejar maior segurança, solicite que eu implemente cifragem da chave com senha antes de colocar no ZIP (recomendado).
- Importar o ZIP sobrescreve os arquivos locais (faça backup antes de testar a importação).

Migração a partir do SharedPreferences (se aplicável)
---
Se você estava usando a versão anterior com `SharedPreferences` (JSON + base64 para imagens), eu posso fornecer um script para migrar:
- Ler o JSON dos `SharedPreferences`
- Decodificar imagens base64 para arquivos em `images/`
- Inserir `Token` no box Hive com `id` como chave
Peça a migração e eu entrego um snippet para executar uma única vez no app.

Boas práticas e melhorias futuras sugeridas
---
- (Opcional) Criptografar `hive_key` com senha no momento do export; pedir senha na importação para desfazer a cifragem.
- Implementar verificação de integridade do backup (hash).
- Implementar backup automático para armazenamento em nuvem quando o aparelho estiver online (opcional).
- UI: permitir edição de tokens, re-captura de imagem, marcação como "perdido" com mensagem de contato limitada.
- Exportar somente dados (JSON) sem chave, e exigir que a chave seja armazenada separadamente (mais seguro).

Soluções para problemas comuns
---
- NFC não é detectado:
  - Teste em aparelho físico com NFC. Emuladores normalmente não suportam NFC.
  - Android: verifique se NFC está ativado nas configurações do aparelho.
  - iOS: CoreNFC disponível a partir do iPhone 7 e com limitações (ver docs Apple).
- Erro ao abrir box Hive após import:
  - Pode ser por chave ausente/errada. Confira se o ZIP continha `hive_key.txt`. Se não contiver, a importação abrirá o box sem criptografia (se aplicável).
  - Se ocorrer erro, o app tenta reabrir o Hive; verifique logs no console para diagnosticar.
- Permissões de câmera/arquivo:
  - Android 13+ e mudanças de storage: `FilePicker`/`share_plus` e gravação em `getApplicationDocumentsDirectory()` devem funcionar sem permissões extras, mas em algumas versões você pode precisar adaptar o comportamento. Se der erro, me avise com a mensagem do log.

Comandos úteis
---
- Obter dependências:
```bash
flutter pub get
```
- Rodar no aparelho conectado:
```bash
flutter run
```
- Build APK/IPA:
```bash
flutter build apk --release
# ou
flutter build ios --release
```

Observações finais
---
Eu já implementei o fluxo completo (criação de chave segura, encriptação do box, armazenamento das imagens em disco, export/import do ZIP). Você está agora com um app offline-friendly, capaz de guardar seus tokens NFC de forma local e portável via backup ZIP. Lembre-se apenas de proteger os ZIPs de backup que contêm a chave.

Se quiser que eu faça a próxima melhoria recomendada (cifrar a chave do Hive com senha no momento do `export` e pedir senha para `import`), eu implemento isso na próxima etapa — é uma boa prática para proteger o backup em trânsito/na nuvem. Também posso gerar o script de migração caso venha de SharedPreferences.

Obrigado — se quiser, gero também um guia passo-a-passo com capturas de tela ou implemento a proteção por senha agora.