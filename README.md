# Gestão de Horários

Aplicação Flutter de registos de trabalho, férias e banco de horas.

## Cópias de segurança

Ao ligar uma conta, a aplicação pergunta se deve **manter os dados atuais** ou **procurar uma cópia no Google Drive**. Os envios permanecem pausados até concluir essa escolha. A pesquisa lista os ficheiros de cópia criados por esta aplicação; depois de selecionar um, apresenta a quantidade de registos e as datas antes de pedir confirmação para o carregar. Cancelar não altera os dados.

No menu **Cópias no Google Drive** existem as opções **Enviar cópia agora** e **Cópia automática a cada 24 horas**. O agendamento começa desligado. Ao ativá-lo, envia imediatamente se ainda não houver uma cópia bem-sucedida nas últimas 24 horas. O intervalo e a data do último sucesso ficam guardados entre reinícios, associados à conta. O envio só fica confirmado pela mensagem de sucesso/data do último envio e pelo ficheiro `gestao_horarios_backup_v3.db` no Drive.

No Android, WorkManager verifica periodicamente os envios vencidos com ligação à rede. A verificação ocorre aproximadamente a cada hora e só envia após 24 horas desde o último sucesso; erros não avançam essa data e podem ser repetidos. A abertura/retoma da aplicação também recupera envios em atraso. O sistema pode adiar a execução por poupança de bateria, falta de rede ou encerramento forçado. Não se trata de um alarme com hora exata. Outras plataformas mantêm o envio manual.

Desligar a opção automática ou terminar a sessão cancela o agendamento. Os envios e restauros são serializados entre a aplicação e as tarefas em segundo plano; uma conta diferente não pode receber os dados de uma conta anteriormente configurada. Preferências e estado ficam numa base de controlo separada, que não é substituída por um restauro.

O restauro verifica a integridade e a estrutura da cópia antes de aplicar migrações. A substituição dos registos é uma transação SQLite atómica e é preservada uma cópia local anterior, com sufixo `.before-restore-...`. Falhar ou cancelar não substitui os dados existentes. A abertura da aplicação nunca carrega uma cópia da nuvem sem confirmação.

A exportação local guarda um ficheiro `.db` através do seletor do dispositivo. No Android/iOS o seletor já escreve o conteúdo; não se deve tentar escrever novamente no caminho devolvido. O restauro de um ficheiro escolhido no dispositivo é feito explicitamente pelo menu **Restaurar Base de Dados**.
## Publicação Android

A versão do APK vem de `version` no `pubspec.yaml`. Aumentar a versão e o número de compilação em cada Release.

Executar `flutter test --no-pub` e `flutter build apk --release`. Antes de publicar `build/app/outputs/flutter-apk/app-release.apk`, verificar a versão e o certificado com `aapt dump badging` e `apksigner verify --print-certs`.

A configuração atual assina com a chave local Android. Preservar essa chave fora do repositório. O certificado usado pelo APK deste computador tem SHA-1 `92:32:9E:77:F7:0A:C4:13:0F:22:D2:5C:C1:18:F1:4F:F8:40:1D:81` e está registado no Google OAuth do projeto `gestao-horarios-507920` para o pacote `com.ruibarata.gestao_horarios`.

O workflow valida testes e compilação, mas não publica o APK do runner: a chave debug temporária muda entre execuções, quebra atualizações Android e provoca o erro 10 do Google Sign-In. Publicar manualmente o APK validado e assinado com a chave preservada. Para automatizar a publicação no futuro, configurar uma chave estável em segredos do repositório.

A Release antiga v1.0.4 do GitHub tem SHA-1 `5F:BD:B4:6F:B9:3D:DB:6B:7B:5F:03:AE:F6:FA:30:99:28:F2:59:3A`. Não é possível substituí-la diretamente com outro certificado. Nunca desinstalar uma instalação antiga sem primeiro obter e verificar uma cópia dos dados.
