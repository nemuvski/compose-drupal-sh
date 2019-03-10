#!/bin/bash
set -e

### 前処理 ###
# 引数の有無確認
if [ $# -ne 1 ]; then
  echo 'Usage: bash compose-drupal.sh {DRUPAL_PROJECT_NAME}'
  exit 1
fi

### 変数定義 ###
DRUPAL_PROJECT_NAME=$1
PATH_DOT_ENV=.env
PATH_COMPOSER_JSON=composer.json
PATH_SETTINGS_PHP=app/sites/default/settings.php
SCRIPT_DIR=$(cd $(dirname $0); pwd)

# 環境設定ファイルの存在確認
if [ ! -e "$SCRIPT_DIR/.env" ]; then
  echo 'You have to make .env file on this script directory first. Please look README.md.'
  exit 1
fi

# .env ファイルから環境依存の各種設定を読み込む
eval "$(cat $SCRIPT_DIR/.env <(echo) <(declare -x))"

MYSQL_DATABASE=$1

### Drupalサイト構築準備 ###
# Drupalプロジェクトを生成
composer create-project drupal-composer/drupal-project:8.x-dev ${DRUPAL_PROJECT_NAME} --stability dev --no-interaction

# カレントディレクトリを移す
cd ${DRUPAL_PROJECT_NAME}

# composer.jsonを編集
sed -i '' -e "s/web\//app\//g" ${PATH_COMPOSER_JSON}

jq '.extra |= .+ {"drupal-paranoia": {"app-dir": "app", "web-dir": "web"}}' ${PATH_COMPOSER_JSON} | sponge ${PATH_COMPOSER_JSON}

# webディレクトリの移動
mv web app

# Drupal Paranoiaのインストール
composer require drupal-composer/drupal-paranoia:~1

# .envファイルを作成（.envに接続先のDBサーバーの情報を記述）
echo "MYSQL_DATABASE=${MYSQL_DATABASE}" > ${PATH_DOT_ENV}
echo "MYSQL_HOSTNAME=${MYSQL_HOSTNAME}" >> ${PATH_DOT_ENV}
echo "MYSQL_PORT=${MYSQL_PORT}" >> ${PATH_DOT_ENV}
echo "MYSQL_USER=${MYSQL_USER}" >> ${PATH_DOT_ENV}
echo "MYSQL_PASSWORD=${MYSQL_PASSWORD}" >> ${PATH_DOT_ENV}

# settings.phpの編集
START_LINE=$(awk "/^#.*?'\/settings\.local\.php'\)\) \{$/ {print NR}" ${PATH_SETTINGS_PHP})
END_LINE=$((START_LINE+2))
sed -i '' -e "${START_LINE},${END_LINE}s:^# ::" ${PATH_SETTINGS_PHP}

DATABASE_SETTINGS="
\$databases['default']['default'] = [
  'database' => getenv('MYSQL_DATABASE'),
  'driver' => 'mysql',
  'host' => getenv('MYSQL_HOSTNAME'),
  'password' => getenv('MYSQL_PASSWORD'),
  'port' => getenv('MYSQL_PORT'),
  'prefix' => '',
  'username' => getenv('MYSQL_USER'),
];
"
echo "${DATABASE_SETTINGS}" >> ${PATH_SETTINGS_PHP}


### データベース作成 ###
echo ''
echo "データベース ${MYSQL_DATABASE} を作成しました. => [${MYSQL_HOSTNAME}:${MYSQL_PORT}]"
mysql --host=${MYSQL_HOSTNAME} \
  --port=${MYSQL_PORT} \
  --user=${MYSQL_USER} \
  --password=${MYSQL_PASSWORD} \
  --execute="create database \`${MYSQL_DATABASE}\`;"


### Drupalサイトをインストール ###
drush si --yes \
  --account-name=${DRUPAL_ADMIN_USER} \
  --account-pass=${DRUPAL_ADMIN_PASSWORD} \
  --site-name=${DRUPAL_PROJECT_NAME} \
  --locale=ja

# デフォルトタイムゾーンをAsia/Tokyoに設定
drush vset --yes date_default_timezone 'Asia/Tokyo'


### ハッシュ値を.envから読み込むように変更 ###
chmod 755 app/sites/default/
HASH_SALT_VALUE=`cat ${PATH_SETTINGS_PHP} | grep '^$settings\['\''hash_salt'\''\]' | sed -E "s/.+= *'(.+)';/\1/"`
echo "DRUPAL_HASH_SALT=${HASH_SALT_VALUE}" >> ${PATH_DOT_ENV}
sed -i '' -E "s/'${HASH_SALT_VALUE}'/getenv('DRUPAL_HASH_SALT')/" ${PATH_SETTINGS_PHP}


### 後処理 ###
echo "Drupalサイト ${DRUPAL_PROJECT_NAME} の構築が完了しました."
