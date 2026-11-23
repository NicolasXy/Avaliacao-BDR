#!/bin/bash
# Recria o banco do zero (01 -> 02 -> 03). Uso: MYSQL_PWD=senha tools/reset_db.sh
cd "$(dirname "$0")/../sql" || exit 1
mysql -uroot --default-character-set=utf8mb4 -e "DROP DATABASE IF EXISTS sistema_os_altave" 2>/dev/null
for f in 01_criacao_tabelas.sql 02_insercao_dados.sql 03_programacao.sql; do
  mysql -uroot --default-character-set=utf8mb4 < "$f" 2>&1 | grep -v Warning
done
echo "banco recriado"
