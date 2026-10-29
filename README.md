# HollowDrivers

## Instalar no Windows

Execute `dist/HollowDrivers-Setup.exe` e clique em **Instalar**. A instalação é por usuário, em `%LOCALAPPDATA%\Programs\HollowDrivers`, com atalhos na Área de Trabalho e no Menu Iniciar. A remoção fica disponível em Configurações → Apps. Instalar o aplicativo não instala drivers automaticamente.

## Gerar o instalador

No Windows, execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

O build usa o compilador do .NET Framework do Windows e gera o instalador independente, o aplicativo e um arquivo SHA-256 em `dist`. Para distribuir, basta enviar `HollowDrivers-Setup.exe`. Os arquivos `DriverGuard-Setup.*` são cópias de compatibilidade com versões antigas.

O instalador suporta instalação, reinstalação, atualização e `/silent` para o atualizador existente. Os backups e as configurações ficam separados da pasta do aplicativo.

## Clone inicializável (1.5.0)

Em **Proteção → Preparar clone do Windows**, o fluxo principal tem três etapas: escolher o destino, preparar um pendrive e clonar/testar. A interface mostra o espaço ocupado em C: e distingue capacidade disponível de compatibilidade das partições. Discos menores com espaço suficiente recebem um roteiro de migração pelo DiskGenius, ajustando somente o destino. A ferramenta externa ainda precisa validar todas as partições. O roteiro de disco inteiro continua usando Rescuezilla.

O fluxo simples usa a interface gráfica do Rescuezilla, com links oficiais para baixar a ISO e o Rufus. O botão de abrir o Rufus verifica a assinatura digital da Akeo Consulting. A seleção e a gravação do pendrive são feitas no Rufus, com a confirmação dele. O HollowDrivers não baixa/grava a mídia automaticamente. O roteiro HTML personalizado pode ser impresso ou fotografado e não exige scripts, comandos ou uma segunda mídia auxiliar.

O destino preferido pode ser identificado por serial no arquivo local `%LOCALAPPDATA%\HollowDrivers\clone-preferences.json`; essa preferência não é distribuída a outros usuários e não ignora bloqueios de compatibilidade. Se o disco desaparecer, a lista é atualizada sem autorizar uma clonagem automaticamente.

Na cópia de disco inteiro, o usuário inicia pelo pendrive e escolhe Clone no Rescuezilla e confere os discos; o assistente não transmite a seleção automaticamente à ferramenta externa. O destino será apagado. Depois da cópia, teste a inicialização com a origem desconectada. Não há redução automática de partições, sincronização contínua nem certificação automática de boot. Dados de outros discos não entram.

O kit anterior de Clonezilla permanece disponível no código para manutenção avançada, mas não faz parte do fluxo simples. Testes: `tests/clone-assistant.ps1` e `tests/simple-clone.ps1`, executados com Windows PowerShell em STA. Verificam bloqueios, navegação real, confirmação de preparo, escape do HTML, exportação e recursos do instalador. Não executam clonagem física.

Referências: [Rescuezilla](https://rescuezilla.com/download), [restrições de discos menores](https://rescuezilla.com/help), [Rufus](https://rufus.ie/pt_BR/).
## Identidade visual

O emblema original está em `assets/HollowDrivers-logo.png`. O build converte esse PNG em um ícone com sete tamanhos e incorpora os recursos ao instalador. O logo também aparece na interface do aplicativo.

Criado com a ferramenta integrada de geração de imagens. Prompt utilizado:

> Use case: logo-brand. Create a NEW highly legible Windows app icon for HollowDrivers, inspired by dark fantasy and the ember mood of Dark Souls but wholly original. This MUST work at 16 and 32 pixels: one extremely simple bold silhouette, a broad ivory silver sword vertically centered inside a thick amber orange broken circular flame ring. Flat graphic design, solid filled shapes, generous negative space, only ivory and vivid amber orange. No shield, no gears, no engraving, no texture, no tiny sparks, no thin strokes, no gradients, no text, no mockup. Square canvas with genuine transparent background. Symbol fills 90 percent of canvas width and height. Broad sword blade and short bold crossguard, thick simplified flame ring with just one flame tip. Clean iconic geometry, strong contrast on charcoal Windows taskbar. This is a finished production app icon, not concept art.

O emblema anterior foi preservado em `assets/HollowDrivers-logo-original.png`.
Arte própria inspirada em fantasia medieval sombria; sem vínculo com Dark Souls.

## Confiabilidade e manutenção (1.5.0)

- O backup de vídeo mantém as versões anteriores e backups de outros dispositivos. O espaço cresce conforme novas versões são guardadas.
- Operações administrativas têm contexto e log próprios. A interface aguarda sua conclusão; instalador e desinstalador recusam alterações enquanto houver sessões em uso, sem encerrar processos à força. Feche também o vigia na bandeja antes de atualizar.
- A instalação prepara todos os arquivos em uma pasta separada e troca a pasta completa. Uma falha na troca recupera a instalação anterior; interrupções são recuperadas ao executar novamente o instalador. Pastas `.previous-*` preservam versões anteriores, e `.failed-*` preservam tentativas incompletas para diagnóstico.
- Proteção oferece histórico persistente e exportação de logs. O diagnóstico pode conter caminhos e nomes de dispositivos; revise antes de compartilhar.
- O assistente registra roteiro preparado, cópia concluída e boot testado, com data e identificação dos discos. Cópia e teste são declarados pelo usuário; não são certificados pelo aplicativo. Salvar outro roteiro não apaga um teste já registrado. Uma nova cópia volta ao estado de boot pendente.
- Código separado em lógica de drivers (`DriverLogic.ps1`), telas (`Views.ps1`), operações (`Operations.ps1`), histórico (`History.ps1`) e clonagem. Distribua o instalador completo, não somente o script principal.

Testes adicionais: `tests/reliability.ps1` simula falha de atualização, interrupção na troca de pastas, bloqueio de manutenção, respostas simultâneas, erros de tarefas, preservação de backups e transições do clone. Usa somente pastas de teste em `dist`, sem alterar drivers ou discos. `tests/single-instance.ps1` valida abertura simultânea e reabertura.
## Componentes para jogos (1.6.0)

Em **Proteção → Componentes para jogos**, selecione Visual C++ v14 x86, Visual C++ v14 x64 ou DirectX legado (junho de 2010). O aplicativo consulta as versões registradas do Visual C++ e algumas bibliotecas de referência do DirectX; essa consulta não certifica a integridade de todos os componentes nem identifica automaticamente as exigências de cada jogo.

Após confirmação e autorização do Windows, o aplicativo baixa o instalador oficial para uma pasta temporária protegida em Program Files, valida a assinatura da Microsoft e instala ou repara o componente selecionado. Para Visual C++, uma versão mais nova é mantida, uma versão igual é reparada e uma versão antiga é atualizada. Pacotes Visual C++ anteriores à família v14 permanecem intactos. O pacote x86 pode ser necessário mesmo em Windows x64. Em ARM64, o pacote x64 oficial também contém binários ARM64; o fluxo DirectX legado não é oferecido.

O DirectX legado acrescenta bibliotecas usadas por jogos antigos e não troca a versão do DirectX do Windows. Seus componentes não oferecem desinstalação individual; instale conforme a necessidade do jogo. Há confirmação específica antes do download de aproximadamente 96 MB.

Falhas e resultados entram no histórico existente. O retorno de reinício necessário é mostrado sem reiniciar o computador automaticamente. Nada é instalado ao abrir a tela ou ao verificar os componentes. .NET, PhysX, OpenAL e famílias antigas de Visual C++ não estão incluídos nesta primeira versão.

Fontes oficiais: [Visual C++](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist), [DirectX legado](https://www.microsoft.com/en-us/download/details.aspx?id=8109).

Teste: `tests/game-components.ps1`, com Windows PowerShell em STA. Verifica catálogo, detecção, rejeição de assinaturas não confiáveis, decisões conforme versão, códigos de saída, tamanho do comando administrativo e navegação da janela. Não instala componentes no sistema.

## Tela inicial e navegação (próxima versão)

- A tela inicial mostra o veredito, quatro blocos de status (Drivers, Vídeo, Proteção e Sistema), um botão principal e no máximo três problemas. Cada bloco abre a seção correspondente.
- **Corrigir tudo** reúne só o que é seguro fazer em sequência, depois de uma única confirmação: backup do driver de vídeo, ligar a proteção automática e abrir a lista de atualizações oficiais para escolher. Restaurar driver, reiniciar e remover programas continuam com o próprio botão. Sem correção segura, o botão principal resolve o primeiro problema grave.
- Sugestões e explicações ficam em **Ver detalhes**. Uma sugestão pode ser ignorada no ✕ e volta em Configurações → Tela inicial, ou sozinha quando a situação muda (por exemplo, novas atualizações).
- O app analisa o PC ao abrir (desligável em Configurações) e mostra a etapa da análise. O resultado anterior aparece enquanto a nova análise roda.
- Menu lateral único: Início, Drivers (abas Todos os drivers, Backups e Windows Update), Proteção, Ferramentas (abas Sistema, Limpeza e Jogos e clone) e Configurações.
- Configurações, referências e estado são gravados em arquivo temporário e trocados de uma vez, para não corromper em caso de queda de energia.
- Código: tela inicial e navegação em `Home.ps1`, atualizações em `Updates.ps1` e limpeza em `Cleanup.ps1`.

Teste: `tests/home.ps1`, com Windows PowerShell em STA. Usa um PC simulado e verifica resumo, blocos, Corrigir tudo, avisos ignorados, detalhes, última análise, navegação e gravação das configurações.
