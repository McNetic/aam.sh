#!/system/xbin/bash
#
# aam.sh -android app management
#
# script to manage (backup/restore) android apps
#
# (C) 2015 Nicolai Ehemann (en@enlightened.de)
#
# This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

VERSION="0.1"
DEBUG=0

usage() {
  echo "Usage: $(basename $0) [options] <app> [<app>,...]"
  echo "options:"
  echo "  -h | --help         - print this help"
  echo "  -b | --backup       - backup app"
  echo "  -d | --debug <lvl>  - set debug level (default 0, max 2)"
  echo "  -p | --path <path>  - backup/restore path (default /storage/sdcard1/aam_backup)"
  echo "  -r | --restore      - restore app"
  echo "  -V | --version      - show version information"

  exit $1
}

version() {
  echo "aam.sh v$VERSION. (C) 2015 Nicolai Ehemann (en@enlightened.de)"

  exit 0
}

error() {
  echo "$(basename $0): $*" 1>&2
}

function debug() {
  if [ "$DEBUG" -ge "$1" ]; then
    shift
    echo "$(basename $0): DEBUG: $*"
  fi
}

function app_get_apk() {
  pm list packages -f $1 | sed -e "s/package:\([^=]*\)=$1/\1/"
}

function app_backup() {
  app=$1
  debug 2 "app_backup($app)"
  pushd $BACKUPPATH > /dev/null
  
  apk=$(app_get_apk "$app")

  echo "Backing up $app"
  debug 1 "  apk=$apk"
  [ -n "$apk" ] || { error "app $app not found"; exit -1; }
  cp $apk $app.apk

  debug 2 "tar --exclude=data/data/$app/lib --exclude=data/data/$app/cache --exclude=data/data/$app/app_webview -cvf $app.tar $app.apk /data/data/$app"
  tar --exclude=data/data/$app/lib --exclude=data/data/$app/cache --exclude=data/data/$app/app_webview -cvf $app.tar $app.apk /data/data/$app

  popd > /dev/null
}

function app_restore() {
  app=$1
  debug 2 "app_restore($app)"

  echo "Restoring $app"
  pushd $BACKUPPATH > /dev/null
  tar -xf $app.tar $app.apk || { error "failed to unpack apk"; exit -1; }
  pm install $BACKUPPATH/$app.apk || { error "failed to install apk"; rm $app.apk; exit -1; }
  rm $app.apk
  popd > /dev/null

  [ -d /data/data/$app ] || { error "no data directory found"; exit -1; }
  uid=$(ls -lnd /data/data/$app | awk '{print $2}')
  gid=$(ls -lnd /data/data/$app | awk '{print $3}')

  pushd / > /dev/null
  tar -xf $BACKUPPATH/$app.tar data/data/$app
  find /data/data/$app/ -exec chown $uid.$gid {} \;
  chown $uid.$gid /data/data/$app
  popd > /dev/null
}
#restore_app() {
#  echo $1
#  echo $2
#  path=$1
#  if [ "" != "$2" ]; then
#    restore_apk=$2
#  else
#    restore_apk=false
#  fi
#  apk=$(echo $path | cut -d/ -f4)
#  appurl=$(echo $apk | cut -d- -f1)
#  echo "Restoring app: $apk (url: $appurl, restore_apk: $restore_apk)"
#  [ $restore_apk ] && pm install $path
#  uid=$(ls -lnd /data/data/$appurl | awk '{print $2}')
#  gid=$(ls -lnd /data/data/$appurl | awk '{print $3}')
#  for content in $(ls -a /storage/sdcard1/restore/$appurl/); do
#    [ "lib" != "$content" ] && cp -r /storage/sdcard1/restore/$appurl/$content /data/data/$appurl/
#  done
#  find /data/data/$appurl/ -exec chown $uid.$gid {} \;
#  chown $uid.$gid /data/data/$appurl
#}

### run shell function multiple times #######################################
function foreach() {
  cmd=$1
  shift
  for arg in $*; do
    $cmd $arg
  done
}

TEMP=$(getopt -o bd::hp:rV --long backup,debug::,help,path:,restore,version -n "$(basename $0)" -- "$@")

[ $? == 0 ] || usage 1
eval set -- "$TEMP"

ACTION="none"
BACKUPPATH=/storage/sdcard1/aam_backup
while true ; do
  case "$1" in
    -b|--backup)     ACTION="backup"; shift ;;
    -d|--debug)
      case "$2" in
        "")          DEBUG=2 ;;
        *)           DEBUG=$2 ;;
      esac
      shift 2 ;;
    -h|--help)     usage 0; shift ;;
    -p|--path)     BACKUPPATH=$2; shift 2 ;;
    -r|--restore)  ACTION="restore"; shift ;;
    -V|--version)  version; shift ;;
    --)            shift ; break ;;
    *)             error "Internal error!" ; exit 1 ;;
  esac
done

if [ -z "$1" ]; then
  usage 1;
fi

APPS=""
while [ -n "$1" ]; do
  APPS="$APPS $1"
  shift
done

if [ ! -d "$BACKUPPATH" ]; then
  mkdir "$BACKUPPATH"
fi

case "$ACTION" in
  backup)
    foreach app_backup $APPS
    am broadcast -a android.intent.action.MEDIA_MOUNTED -d file://$BACKUPPATH
    ;;
  restore)
    foreach app_restore $APPS
    ;;
  *)
    usage 1
    ;;
esac

exit 0
