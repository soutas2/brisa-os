# Brisa OS — sistema leve, touch-first, para o Surface Go 2 (4 GB RAM)
#
# Base: Fedora Silverblue (GNOME) da Universal Blue, já com codecs e drivers Intel.
# O sistema é "atómico": cada atualização é uma imagem completa, e se algo
# correr mal escolhes a versão anterior no arranque.

ARG BASE_IMAGE=ghcr.io/ublue-os/silverblue-main:latest

# Contexto de build (não fica na imagem final)
FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /system_files

FROM ${BASE_IMAGE}

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/build.sh

# Verifica se a imagem é um sistema bootc válido
RUN bootc container lint
