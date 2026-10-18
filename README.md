# Gestão de Horários

Aplicação Flutter de registos de trabalho, férias e banco de horas.

## Cópias de segurança

No menu **Cópias no Google Drive**, ligar a conta e escolher **Enviar cópia para o Drive**. A ligação à conta não cria uma cópia automaticamente. O envio só fica confirmado pela mensagem de sucesso e pela presença de `gestao_horarios_backup_v3.db` no Drive.

A exportação local guarda um ficheiro `.db` através do seletor do dispositivo. No Android/iOS o seletor já escreve o conteúdo; não se deve tentar escrever novamente no URI devolvido. O restauro de ficheiros é feito explicitamente pelo menu **Restaurar Base de Dados**. A abertura da aplicação recupera apenas a sessão Google e não substitui os dados locais.

## Publicação Android

A versão do APK vem de `version` no `pubspec.yaml`. Aumentar a versão e o número de compilação em cada Release.

Executar `flutter test --no-pub` e `flutter build apk --release`. Antes de publicar `build/app/outputs/flutter-apk/app-release.apk`, verificar a versão e o certificado com `aapt dump badging` e `apksigner verify --print-certs`.

A configuração atual assina com a chave local Android. Preservar essa chave fora do repositório. O certificado usado pelo APK deste computador tem SHA-1 `92:32:9E:77:F7:0A:C4:13:0F:22:D2:5C:C1:18:F1:4F:F8:40:1D:81` e está registado no Google OAuth do projeto `gestao-horarios-507920` para o pacote `com.ruibarata.gestao_horarios`.

O workflow valida testes e compilação, mas não publica o APK do runner: a chave debug temporária muda entre execuções, quebra atualizações Android e provoca o erro 10 do Google Sign-In. Publicar manualmente o APK validado e assinado com a chave preservada. Para automatizar a publicação no futuro, configurar uma chave estável em segredos do repositório.

A Release antiga v1.0.4 do GitHub tem SHA-1 `5F:BD:B4:6F:B9:3D:DB:6B:7B:5F:03:AE:F6:FA:30:99:28:F2:59:3A`. Não é possível substituí-la diretamente com outro certificado. Nunca desinstalar uma instalação antiga sem primeiro obter e verificar uma cópia dos dados.
