#!/usr/bin/env bash
# aicrew: nama lama (alias usang) dari scheduled-workflow.sh; jalankan nama Inggris.
exec bash "$(dirname "$0")/scheduled-workflow.sh" "$@"
