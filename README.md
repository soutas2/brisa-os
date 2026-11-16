# Brisa OS

Sistema operativo leve e pensado para touch, feito para o **Surface Go 2 com 4 GB de RAM**.
Serve para três coisas: **Claude Code**, **navegar na web** e **instalar apps**.

Por baixo é Linux (Fedora Silverblue + GNOME). A aparência, as otimizações e as
ferramentas são do Brisa OS. O sistema é **atómico**: cada atualização é uma
imagem completa e testada. Se alguma correr mal, escolhes a versão anterior no
arranque e voltas a ter tudo como estava.

## O que tem

| | |
|---|---|
| **Visual tipo macOS** | Dock em baixo, botões das janelas à esquerda, fonte Inter, desfoque leve, wallpapers próprios, modo escuro |
| **Touch** | Gestos de 3 dedos, teclado no ecrã automático, rotação automática, ícones grandes |
| **4 GB de RAM** | Memória comprimida zram (cerca de 6 GB efetivos), indexação de ficheiros desligada, loja de apps que não fica aberta em fundo, Firefox que liberta separadores quando a memória está a acabar |
| **Disco** | Escalonador BFQ no eMMC, menos escritas de registos |
| **Claude Code** | Instalado sozinho no primeiro login, terminal com JetBrains Mono |
| **Apps** | Loja GNOME Software com Flathub (milhares de apps) |
| **Comando `brisa`** | `brisa update`, `brisa rollback`, `brisa claude`, `brisa ram`... |

## Estrutura

```
Containerfile                 receita do sistema (parte da base Fedora)
build_files/build.sh          instala pacotes e aplica a configuração
system_files/                 ficheiros copiados para dentro do sistema
  etc/dconf/db/local.d/       aparência, dock, touch, energia
  etc/systemd/zram-generator.conf   memória comprimida
  etc/firefox/policies/       Firefox afinado para pouca RAM
  usr/bin/brisa               comando de gestão
  usr/lib/sysctl.d/           afinação da memória
  usr/share/backgrounds/brisa wallpapers
disk_config/iso.toml          configuração do instalador
.github/workflows/            o GitHub constrói o sistema por ti
```

---

## Instalação passo a passo

### 1. Pôr o projeto no GitHub (≈5 min)

1. Cria uma conta em github.com, se ainda não tiveres.
2. Cria um repositório **público** chamado `brisa-os`. Tem de ser público para o
   GitHub construir e guardar a imagem de graça.
3. Envia esta pasta para lá:
   ```bash
   cd brisa-os
   git init -b main
   git add .
   git commit -m "Brisa OS"
   git remote add origin https://github.com/O-TEU-UTILIZADOR/brisa-os.git
   git push -u origin main
   ```
4. No separador **Actions**, o build "Construir Brisa OS" começa sozinho
   (cerca de 10 a 20 min). Tem de ficar com o visto verde.
5. Torna a imagem pública: no teu perfil do GitHub abre **Packages** → `brisa-os`
   → **Package settings** → **Change visibility** → **Public**.

### 2. Criar a pen de instalação

> **Nota (nov. 2026):** o `bootc-image-builder` ainda não suporta Fedora 45, por isso
> o workflow "Criar ISO" falha de momento. Usa a **Opção B**.

**Opção A — ISO do Brisa OS (tudo de uma vez)**

1. **Actions** → **Criar ISO** → **Run workflow**. Demora cerca de 20 a 30 min.
2. No fim, descarrega o artefacto `brisa-os-iso` (um .zip com o `install.iso`).
3. Grava o ISO numa pen USB de 8 GB ou mais com o
   [Fedora Media Writer](https://fedoraproject.org/workstation/download)
   ou o balenaEtcher.

**Opção B — a mais garantida, se a A falhar**

1. Grava o ISO oficial do **Fedora Silverblue** numa pen.
2. Instala-o no Surface (passo 3).
3. Depois do primeiro arranque, abre o Terminal e corre:
   ```bash
   sudo bootc switch ghcr.io/O-TEU-UTILIZADOR/brisa-os:latest
   ```
4. Reinicia. A partir daqui já estás no Brisa OS.

### 3. Instalar no Surface Go 2

> ⚠️ **O Windows vai ser apagado.** Antes de começar, copia para outro sítio os
> ficheiros que queres guardar.

1. Liga o Surface ao carregador e a pen. Se o Surface só tiver USB-C, usa um
   adaptador ou hub.
2. Desliga o Surface. Mantém carregado o botão **Volume −** e carrega uma vez no
   **botão de ligar**. Larga o Volume − quando aparecer o logótipo.
   Se não arrancar da pen: liga com **Volume +** carregado, para entrar na UEFI,
   e em **Boot configuration** põe o **USB Storage** em primeiro.
3. No instalador, escolhe o disco interno e **Apagar tudo / Recuperar espaço**.
   Deixa o particionamento automático.
4. Reinicia e tira a pen. O ecrã de boas-vindas pede o idioma, o Wi-Fi e cria o
   teu utilizador, tudo por toque.

**Secure Boot:** o Brisa OS usa o kernel oficial do Fedora, que é assinado.
Normalmente o Secure Boot pode ficar ligado. Se a pen não arrancar, entra na
UEFI (Volume + e ligar) → **Security** → **Change configuration** → escolhe
**Microsoft & 3rd party CA**.

### 4. Primeiros passos

- **Escala do ecrã:** em Definições → Ecrãs, põe **150%**. É o tamanho ideal
  para o ecrã de 10,5" do Surface.
- **Claude Code:** instala-se sozinho no primeiro login, quando houver internet.
  Abre o Terminal e escreve `claude`. Se não tiver instalado, escreve
  `brisa claude`.
- **Apps:** abre a **Loja** na dock. Para pouca RAM, prefere apps nativas GNOME
  a apps Electron, que são pesadas.

---

## Uso diário

```bash
brisa update     # atualiza o sistema (aplica ao reiniciar)
brisa rollback   # volta à versão anterior
brisa claude     # instala/atualiza o Claude Code
brisa apps       # atualiza as apps
brisa ram        # vê o uso de memória
```

## Como mudar o teu sistema

Edita os ficheiros e faz `git push`. O GitHub constrói uma nova versão e no
Surface corres `brisa update`.

- **Instalar pacotes de sistema:** acrescenta-os em `build_files/build.sh`.
- **Mudar a aparência e as definições:** `system_files/etc/dconf/db/local.d/01-brisa`.
- **Mudar o nome do sistema:** a variável `OS_NAME` em `build_files/build.sh`.

## Dicas para 4 GB de RAM

- Usa o Firefox com, no máximo, 8 a 10 separadores ativos. Os outros são
  libertados sozinhos.
- O Claude Code é leve, porque o modelo corre na cloud. O que pesa é o browser.
- `brisa ram` mostra quanto estás a usar. Uso de zram é normal e é rápido.

## Limitações conhecidas

- As **câmaras** do Surface Go 2 não funcionam bem em Linux.
- A versão com **eMMC de 64 GB** é mais lenta a instalar e a atualizar do que a de SSD.
