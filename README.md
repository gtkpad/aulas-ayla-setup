# aulas-ayla-setup

Um script por semana que prepara, no Mac, a máquina Linux onde se programa em C nas Aulas Ayla.

Cada `semana-NN.sh` cria (ou liga) a máquina `aulas-ayla-vm` no OrbStack (Ubuntu 24.04 arm64, o mesmo processador do Mac), instala os pacotes da semana, fixa o ambiente (`LC_ALL=C.UTF-8`, IA do VS Code desligada), põe o material da semana em `~/material/semana-NN/` e confere se tudo ficou certo. Pode rodar de novo quantas vezes quiser: ele só muda o que falta e nunca mexe em `~/aulas/`.

## Como usar

No Terminal do Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/gtkpad/aulas-ayla-setup/main/semana-01.sh | bash
```

O script é público: para ver o que ele faz, abra o `semana-01.sh` neste repositório.

Precisa do OrbStack e do `git` instalados no Mac, e de acesso de leitura ao repositório do material.
