#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
exec "${0:A:h}/Scripts/install-background-service.sh"
