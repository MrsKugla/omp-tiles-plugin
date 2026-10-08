#!/bin/sh
# Installa omp Tiles in Tern: copia questa cartella nella cartella dei plugin di Tern.
# Rilancialo per aggiornare il plugin.
set -eu

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if ! command -v tern >/dev/null 2>&1; then
	echo "tern non trovato nel PATH: installa Tern (https://stencil.so/tern) e riprova." >&2
	exit 1
fi

tern plugin install "$dir" --force
