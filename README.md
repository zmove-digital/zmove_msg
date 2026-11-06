# ZMove Msg

App Android offline para enviar mensagens personalizadas pelo WhatsApp para uma lista de clientes, de forma **assistida**: o app monta a mensagem e abre a conversa no WhatsApp; o envio é confirmado com um toque.

Feito em Flutter, em português (pt-BR), Material 3, sem backend e sem API oficial.

## Recursos

- **Contatos** com nome, telefone, grupo e controle de opt-in (autorizado / não autorizado / desconhecido).
- **Importação da agenda do celular** com seleção manual, um a um (inclui os contatos sincronizados pelo WhatsApp).
- **Importação de CSV** e exportação dos contatos.
- **Modelos de mensagem** com variáveis: `{{nome}}`, `{{primeiro_nome}}`, `{{saudacao}}`, `{{telefone}}`, `{{grupo}}`, `{{empresa}}`, `{{remetente}}`, `{{data}}`.
- **Envios** em 3 passos: escolher modelo → escolher contatos e mídia (opcional) → revisar e iniciar.
- **Fila assistida**: abre o WhatsApp com o texto pronto, volta ao app e confirma o status (enviado / pulado / pendente).
- **Envio de mídia** (imagem/PDF) via compartilhamento do Android: o texto é copiado para a área de transferência e o arquivo é compartilhado; escolha o contato no WhatsApp.
- **Agendamento** de lembretes locais que abrem a fila no horário marcado.
- **Relatórios** por campanha e histórico de envios.
- 100% local: dados em SQLite no aparelho, sem conta e sem servidor.

## Limitações importantes

- A importação pelo celular lê a **agenda do aparelho** (o Android pede a permissão de contatos). Contatos que existem somente dentro do WhatsApp, sem estarem salvos na agenda, não aparecem na lista.
- O app **não envia sozinho**. Ele abre o WhatsApp com a mensagem preenchida; o disparo final é feito por você. Isso evita automações não oficiais e o risco de bloqueio do número.
- Em links `wa.me` o texto chega ao WhatsApp, mas **anexos não podem ser incluídos pelo link**. Por isso, mídia usa o compartilhamento do sistema.
- No Android 12+, o agendamento exato depende da permissão “Alarmes e lembretes”. Se ela não for concedida, o lembrete usa o agendamento inexato do sistema.
- O ícone de notificação é local; notificações exigem permissão no Android 13+.
- A build de release deste projeto usa a **assinatura de debug**. Troque a chave antes de publicar.

## Como rodar

Pré-requisitos: Flutter 3.47+ e Android SDK 36.

```bash
flutter pub get
flutter run
```

Gerar o APK:

```bash
flutter build apk --release
# saída: build/app/outputs/flutter-apk/app-release.apk
```

Instalar no aparelho conectado:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Formato do CSV

Cabeçalho opcional. Separador `;` ou `,`. Exemplo:

```csv
nome;telefone;grupo;autorizado
Maria Silva;11987654321;Clientes;sim
João Souza;+55 11 91234-5678;VIP;nao
```

- `nome`: obrigatório.
- `telefone`: obrigatório. Sem DDI, o prefixo configurado em Ajustes (padrão `55`) é adicionado.
- `grupo`: opcional.
- `autorizado`: `sim`/`nao`/`desconhecido` (também aceita `true`/`false`). Se vazio, fica como desconhecido.

## Estrutura

```
lib/
  data/        modelos e SQLite
  services/    WhatsApp, notificações, CSV, mídia
  state/       regras de negócio (Provider)
  ui/          telas (Início, Contatos, Modelos, Envios, Ajustes)
  utils/       telefone, templates, datas, tema
```

## Privacidade e consentimento

Use apenas contatos que autorizaram o recebimento das mensagens. O app permite marcar quem pediu descadastro como “não autorizado”, e a fila de envio ignora esses contatos.
