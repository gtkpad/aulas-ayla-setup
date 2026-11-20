#!/bin/bash
# Aulas Ayla, semana 1: prepara a máquina Linux onde você programa em C.
# É uma máquina Linux arm64 de verdade, rodando direto no processador do Mac (o mesmo
# tipo de processador, sem imitar outro), criada pelo OrbStack.
#
# Este script roda no Mac (no Terminal do macOS), não dentro do Linux.
# Para instalar: curl -fsSL https://raw.githubusercontent.com/gtkpad/aulas-ayla-setup/main/semana-01.sh | bash
# Pode rodar quantas vezes quiser: o que já está pronto é deixado como está.
# Ele nunca mexe na sua pasta ~/aulas/: quem cria e cuida dela é você, no Dia 1.
# No seu home, ele só escreve na pasta ~/material/ e numa linha do ~/.bashrc.
#
# O que ele faz, em ordem:
#   1. confere se o Mac tem o OrbStack e o git;
#   2. cria (ou liga) a máquina Linux "aulas-ayla-vm";
#   3. instala os programas da semana dentro dela (gcc, gdb, man, ...);
#   4. deixa o terminal do Linux com LC_ALL=C.UTF-8 e cria ~/material;
#   5. desliga a IA do VS Code do Mac;
#   6. copia o material da semana para ~/material/semana-01/ no Linux;
#   7. confere se tudo ficou certo e imprime OK ou FAILED para cada item.
set -euo pipefail

SEMANA=semana-01
MAQUINA=aulas-ayla-vm
USUARIO=ayla
REPO_URL=https://github.com/gtkpad/aulas-ayla.git
CACHE="$HOME/.cache/aulas-ayla/repo"
# O caminho padrão do settings.json do VS Code no macOS. Dá para trocar por outro arquivo
# (por exemplo, num teste) com: VSCODE_SETTINGS=/caminho/settings.json bash semana-01.sh
VSCODE_SETTINGS=${VSCODE_SETTINGS:-"$HOME/Library/Application Support/Code/User/settings.json"}

# Pacotes do bloco 1. É a mesma lista da seção "base" do template/captura/vm-pacotes.sh
# do workspace do Gabriel (é ela que monta o ambiente onde as saídas do PDF foram
# capturadas). A lista vem copiada aqui para o script funcionar sozinho, baixado pelo curl;
# quem gera este arquivo a partir do workspace mantém as duas listas iguais.
PACOTES="build-essential gdb curl ca-certificates traceroute bind9-dnsutils \
netcat-openbsd python3 python3-venv sqlite3 iproute2 iputils-ping \
git man-db manpages-dev xxd"

passo() { printf '\n== %s\n' "$1"; }
pare()  { printf '\nPAREI: %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------------------
passo "1/7 Conferindo o Mac"
# `command -v` diz se um programa existe. Sem o OrbStack não há máquina Linux; sem o git
# não dá para baixar o material.
command -v orb >/dev/null 2>&1 ||
  pare "falta o OrbStack. Instale pelo site orbstack.dev, abra o aplicativo uma vez e rode este script de novo."
command -v git >/dev/null 2>&1 ||
  pare "falta o git. No Terminal, rode 'xcode-select --install', espere terminar e rode este script de novo."
echo "OrbStack e git encontrados."

# ---------------------------------------------------------------------------------------
passo "2/7 Máquina Linux $MAQUINA"
# `orb start` liga o OrbStack, se ele estiver fechado. `orb info` responde com erro quando
# a máquina não existe; nesse caso ela é criada: Ubuntu 24.04 (noble), arquitetura arm64
# (a do processador do Mac, a mesma do PDF), com o usuário ayla.
# Se já existe uma máquina com esse nome, mas de outra arquitetura, o script para: trocar
# exige apagar a máquina, e isso apaga tudo o que está dentro dela. Ele nunca apaga sozinho.
orb start >/dev/null 2>&1 || true
if ! info=$(orb info "$MAQUINA" 2>/dev/null); then
  echo "A máquina não existe. Criando (leva alguns minutos na primeira vez)..."
  orb create -a arm64 -u "$USUARIO" ubuntu:noble "$MAQUINA"
elif ! printf '%s\n' "$info" | grep -q '^Architecture: arm64$'; then
  arq=$(printf '%s\n' "$info" | sed -n 's/^Architecture: //p')
  pare "já existe uma máquina $MAQUINA, mas ela é ${arq:-de arquitetura desconhecida}, não arm64.
O curso usa a máquina arm64. Para trocar, a máquina antiga precisa ser apagada, e isso
apaga tudo o que está dentro dela, inclusive a sua pasta ~/aulas/. Não apaguei nada.
Chame o Gabriel: ele guarda o que precisar (pelo Mac, em ~/OrbStack/$MAQUINA/home/$USUARIO/),
apaga a máquina com 'orb delete $MAQUINA' e roda este script de novo."
elif ! printf '%s\n' "$info" | grep -q '^State: running'; then
  echo "A máquina existe, mas está desligada. Ligando..."
  orb start "$MAQUINA"
else
  echo "A máquina já existe e está ligada."
fi

# Atalhos: `como_root` e `como_ayla` rodam, dentro do Linux, o script que vier pela
# entrada padrão (o texto entre <<'EOF' e EOF logo abaixo de cada uso).
como_root() { orb -m "$MAQUINA" -u root bash -s -- "$@"; }
como_ayla() { orb -m "$MAQUINA" -u "$USUARIO" bash -s -- "$@"; }

# ---------------------------------------------------------------------------------------
passo "3/7 Programas da semana (dentro do Linux)"
# O apt é o instalador de pacotes do Ubuntu e precisa do usuário root. Se todos os pacotes
# já estão instalados, nada é baixado.
# shellcheck disable=SC2086  # a lista é separada em palavras de propósito
como_root $PACOTES <<'EOF'
set -euo pipefail
faltam=""
for p in "$@"; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || faltam="$faltam $p"
done
if [ -z "$faltam" ]; then
  echo "Todos os pacotes já estão instalados."
  exit 0
fi
echo "Instalando:$faltam"
echo "(pode levar alguns minutos; o detalhe fica em /var/log/aulas-ayla-apt.log)"
export DEBIAN_FRONTEND=noninteractive
log=/var/log/aulas-ayla-apt.log
# shellcheck disable=SC2086
if ! { apt-get update -q && apt-get install -y -q --no-install-recommends $faltam; } > "$log" 2>&1; then
  tail -n 20 "$log"
  echo "A instalação falhou. As últimas linhas do registro estão acima."
  exit 1
fi
echo "Pacotes instalados."
EOF

# ---------------------------------------------------------------------------------------
passo "4/7 Ambiente do Linux"
# LC_ALL=C.UTF-8 deixa as mensagens dos programas em inglês e iguais às do PDF. A linha
# vai para o ~/.bashrc, que o bash lê toda vez que abre um terminal; só entra se ainda
# não estiver lá. `mkdir -p` cria a pasta só se ela não existir e não apaga nada.
# A ~/aulas/ não é criada aqui: você mesma a cria no Dia 1.
como_ayla <<'EOF'
set -euo pipefail
linha='export LC_ALL=C.UTF-8'
if grep -qxF "$linha" ~/.bashrc 2>/dev/null; then
  echo "O ~/.bashrc já tem $linha"
else
  printf '\n# Aulas Ayla: mensagens dos programas iguais às do PDF\n%s\n' "$linha" >> ~/.bashrc
  echo "Coloquei $linha no ~/.bashrc"
fi
mkdir -p ~/material
echo "Pasta ~/material pronta."
EOF

# ---------------------------------------------------------------------------------------
passo "5/7 VS Code sem IA"
# Até a semana 11 o VS Code fica sem IA (sem chat, sem sugestões de código). As chaves
# abaixo vão para o settings.json do VS Code do Mac:
#   chat.disableAIFeatures  desliga e esconde os recursos de IA do VS Code;
#   github.copilot.enable   desliga o Copilot em todas as linguagens, se ele existir;
#   chat.commandCenter.enabled  tira o botão do chat da barra de cima.
CHAVES='{
    "chat.disableAIFeatures": true,
    "github.copilot.enable": { "*": false },
    "chat.commandCenter.enabled": false
}'
mostre_chaves() {
  echo "Abra o VS Code, rode o comando 'Preferences: Open User Settings (JSON)' e cole"
  echo "estas linhas dentro das chaves { } que já estão lá:"
  printf '%s\n' "$CHAVES" | sed '1d;$d'
}
mkdir -p "$(dirname "$VSCODE_SETTINGS")"
if [ ! -s "$VSCODE_SETTINGS" ]; then
  # Arquivo novo (ou vazio): escrevemos só as nossas chaves.
  printf '%s\n' "$CHAVES" > "$VSCODE_SETTINGS"
  echo "Criei $VSCODE_SETTINGS com a IA desligada."
elif xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/python3 ]; then
  # O arquivo já existe. O python3 que vem com as ferramentas do Xcode só acrescenta as
  # chaves que faltam e não muda as que você já tem. Se o arquivo tiver comentários ou
  # não for JSON puro, ele não mexe em nada (código 3) e mostramos o que colar.
  # Antes de gravar, uma cópia do original fica em settings.json.antes-das-aulas.
  set +e
  /usr/bin/python3 -I - "$VSCODE_SETTINGS" "$CHAVES" <<'EOF'
import json, os, shutil, sys
path, wanted = sys.argv[1], json.loads(sys.argv[2])
try:
    with open(path) as f:
        cur = json.load(f)
except ValueError:
    sys.exit(3)
if not isinstance(cur, dict):
    sys.exit(3)
missing = {k: v for k, v in wanted.items() if k not in cur}
for k, v in wanted.items():
    if k in cur and cur[k] != v:
        print("Atenção: a chave %s já existe com outro valor (%s). Deixei como está." % (k, json.dumps(cur[k])))
if not missing:
    print("O settings.json já tem as chaves da IA desligada.")
    sys.exit(0)
backup = path + ".antes-das-aulas"
if not os.path.exists(backup):
    shutil.copy2(path, backup)
cur.update(missing)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(cur, f, indent=4)
    f.write("\n")
os.replace(tmp, path)
print("Acrescentei ao settings.json: " + ", ".join(missing))
EOF
  r=$?
  set -e
  if [ "$r" -eq 3 ]; then
    echo "O $VSCODE_SETTINGS tem comentários ou não é JSON puro; não mexi nele."
    mostre_chaves
  elif [ "$r" -ne 0 ]; then
    pare "não consegui atualizar o $VSCODE_SETTINGS (erro $r)."
  fi
else
  echo "O $VSCODE_SETTINGS já existe e este Mac não tem o python3 do Xcode; não mexi nele."
  mostre_chaves
fi

# ---------------------------------------------------------------------------------------
passo "6/7 Material da $SEMANA"
# O repositório do material é privado. O git usa a senha ou o token que já estão guardados
# neste Mac; o script não pede nem guarda nenhum token. GIT_TERMINAL_PROMPT=0 faz o git
# falhar em vez de ficar esperando uma senha. A cópia em ~/.cache é só do script: ela é
# sempre igualada ao repositório (por isso o reset --hard), e nada seu fica lá.
export GIT_TERMINAL_PROMPT=0
erro_git() {
  pare "não consegui baixar o material ($REPO_URL).
Isso quase sempre é falta de acesso: o repositório é privado. Confira se a sua conta do
GitHub tem acesso a ele e se o git deste Mac está com o seu token guardado (o Gabriel
mostra como). Depois rode este script de novo."
}
if [ -d "$CACHE/.git" ]; then
  git -C "$CACHE" fetch -q origin main || erro_git
  git -C "$CACHE" reset -q --hard origin/main
  echo "Material atualizado em $CACHE"
else
  mkdir -p "$(dirname "$CACHE")"
  git clone -q --branch main --single-branch "$REPO_URL" "$CACHE" || erro_git
  echo "Material baixado em $CACHE"
fi
[ -d "$CACHE/$SEMANA" ] || pare "o repositório ainda não tem a pasta $SEMANA/. Avise o Gabriel."

# A cópia para o Linux é feita lá dentro: o Linux enxerga o disco do Mac em /mnt/mac.
# ~/material/ é só para ler. Para não perder nada que você tenha mudado lá por engano:
#   - arquivo novo no repositório: é copiado;
#   - arquivo igual ao do repositório: fica como está;
#   - arquivo que mudou no repositório e que você não tocou: é atualizado;
#   - arquivo que você mudou: a sua versão é guardada ao lado, com o final .local
#     (por exemplo README.md.local), e o arquivo volta a ser o do repositório.
# Para saber se foi você que mudou, o script guarda a "impressão digital" (sha256) de cada
# arquivo que entregou, em ~/material/semana-01/.entregue.sha256.
#   - arquivo que o script entregou antes e que saiu do repositório: é apagado, se você
#     não mexeu nele; se mexeu, ele fica, renomeado com o final .local;
#   - pastas que ficarem vazias por isso saem também.
# Nada que o script não entregou é apagado, e nada fora de ~/material/semana-01/ é tocado.
como_ayla "/mnt/mac$CACHE/$SEMANA" "$SEMANA" <<'EOF'
set -euo pipefail
src=$1
dst=~/material/$2
reg=$dst/.entregue.sha256
mkdir -p "$dst"
touch "$reg"
novo_reg=$(mktemp)
novos=0; atualizados=0; guardados=0; removidos=0
sha() { sha256sum < "$1" | cut -d' ' -f1; }
cd "$src"
while IFS= read -r f; do
  f=${f#./}
  h=$(sha "$f")
  printf '%s\t%s\n' "$h" "$f" >> "$novo_reg"
  if [ ! -e "$dst/$f" ]; then
    mkdir -p "$dst/$(dirname "$f")"
    cp "$f" "$dst/$f"; novos=$((novos + 1)); continue
  fi
  atual=$(sha "$dst/$f")
  [ "$atual" = "$h" ] && continue
  entregue=$(awk -F'\t' -v f="$f" '$2 == f { print $1 }' "$reg")
  if [ "$atual" != "$entregue" ]; then
    copia="$dst/$f.local"
    [ -e "$copia" ] && copia="$dst/$f.local.$(date +%Y%m%d-%H%M%S)"
    cp "$dst/$f" "$copia"
    echo "Você tinha mudado $f; a sua versão ficou em ${copia#"$dst"/}"
    guardados=$((guardados + 1))
  fi
  cp "$f" "$dst/$f"; atualizados=$((atualizados + 1))
done < <(find . -type f | sort)

# Arquivos do registro antigo que não estão no novo saíram do repositório.
while IFS=$'\t' read -r entregue f; do
  [ -f "$dst/$f" ] || continue
  if [ "$(sha "$dst/$f")" = "$entregue" ]; then
    rm "$dst/$f"; removidos=$((removidos + 1))
  else
    copia="$dst/$f.local"
    [ -e "$copia" ] && copia="$dst/$f.local.$(date +%Y%m%d-%H%M%S)"
    mv "$dst/$f" "$copia"
    echo "$f saiu do material, mas você tinha mudado; a sua versão ficou em ${copia#"$dst"/}"
    guardados=$((guardados + 1))
  fi
  # Sobe pelas pastas do arquivo apagando as que ficaram vazias (rmdir só apaga pasta vazia).
  d=$(dirname "$f")
  while [ "$d" != . ] && rmdir "$dst/$d" 2>/dev/null; do d=$(dirname "$d"); done
done < <(awk -F'\t' 'NR == FNR { novo[$2] = 1; next } !($2 in novo)' "$novo_reg" "$reg")

mv "$novo_reg" "$reg"
echo "Em ~/material/$2: $novos novo(s), $atualizados atualizado(s), $removidos apagado(s) porque saíram do repositório, $guardados versão(ões) sua(s) guardada(s) com .local."
EOF

# ---------------------------------------------------------------------------------------
passo "7/7 Conferência final"
# Cada item imprime OK ou FAILED. O script só termina com sucesso (código 0) se todos
# derem OK. Rodamos como ayla, com LC_ALL=C.UTF-8, como no terminal dela.
set +e
como_ayla "$SEMANA" <<'EOF'
export LC_ALL=C.UTF-8
falhas=0
item() {  # item <nome> <comando...>: OK se o comando der certo
  nome=$1; shift
  if "$@" >/dev/null 2>&1; then echo "OK $nome"; else echo "FAILED $nome"; falhas=$((falhas + 1)); fi
}
item "uname -m = aarch64" test "$(uname -m)" = aarch64
item "Ubuntu 24.04" grep -q '^VERSION_ID="24.04"' /etc/os-release
item "~/.bashrc com LC_ALL=C.UTF-8" test "$(bash -ic 'echo "$LC_ALL"' 2>/dev/null | tail -1)" = C.UTF-8
item "locale C.UTF-8" sh -c 'locale 2>&1 | grep -qx "LC_ALL=C.UTF-8" && ! locale 2>&1 >/dev/null | grep -q .'
item "gcc 13" test "$(gcc -dumpversion 2>/dev/null | cut -d. -f1)" = 13
t=$(mktemp -d)
printf '#include <stdio.h>\n\nint main(void) {\n    printf("Hello, world!\\n");\n    return 0;\n}\n' > "$t/hello.c"
item "hello compila (gcc -std=c17 -Wall -Wextra -Werror)" gcc -std=c17 -Wall -Wextra -Werror "$t/hello.c" -o "$t/hello"
item "hello roda" test "$("$t/hello" 2>&1)" = "Hello, world!"
item "~/material/$1" test -d ~/material/"$1"
rm -rf "$t"
exit "$falhas"
EOF
falhas=$?
set -e
echo
if [ "$falhas" -eq 0 ]; then
  echo "Tudo pronto. Para entrar no Linux: orb -m $MAQUINA"
  exit 0
fi
echo "$falhas item(ns) com FAILED. Copie as linhas acima e mande para o Gabriel."
exit 1
