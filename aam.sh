#!/system/xbin/bash
#
# aam.sh -android app management
#
# script to manage (backup/restore) android apps
#
# (C) 2015 Nicolai Ehemann (en@enlightened.de)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

VERSION="0.1"
DEBUG=0

usage() {
  echo "Usage: $(basename $0) [options] <app> [<app>,...]"
  echo "actions:"
  echo "  -b | --backup       - backup app"
  echo "  -h | --help         - print this help"
  echo "  -r | --restore      - restore app"
  echo "  -V | --version      - show version information"
  echo "options:"
  echo "  -d | --debug <lvl>  - set debug level (default 0, max 2)"
  echo "  -D | --data-only    - backup/restore only data"
  echo "  -p | --path <path>  - backup/restore path (default /storage/sdcard1/aam_backup)"
  echo "       --nolink       - do not relink app to sdcard"

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
  result=$(pm list packages -f $1 | grep "=$1$" | sed -e "s/package:\([^=]*\)=$1/\1/")
  echo $result
  return $([ -n "$result" ] && echo 0 || echo -1)
}

function apps_get_list() {
  pm list packages | sed -e "s/package:\(.*\)/\1/"
}

function app_backup() {
  app=$1

  pushd $BACKUPPATH > /dev/null
  apk=$(app_get_apk "$app")

  [ -n "$apk" ] || { error "app $app not found"; exit -1; }

  echo "Backing up $app"
  link=""
  debug 1 "(apk=$apk)"
  if ! $DATAONLY; then
    debug 1 "copying apk to backup target"
    cp $apk $app.apk
    tarapk=" $app.apk"
  fi
  if [ -h $apk ]; then
    debug 1 "creating symbolic link marker"
    touch $app.link
    tarlink=" $app.link"
  fi

  debug 1 "packing data$( $DATAONLY || echo ' and apk')"
  debug 2 "tar --exclude=data/data/$app/lib --exclude=data/data/$app/cache --exclude=data/data/$app/app_webview -czf $app.tgz$tarapk$tarlink /data/data/$app"
  tar --exclude=data/data/$app/lib --exclude=data/data/$app/cache --exclude=data/data/$app/app_webview -czf $app.tgz$tarapk$tarlink /data/data/$app > /dev/null 2>&1
  
  debug 1 "cleaning up leftovers"
  if [ ! $DATAONLY ]; then
    rm $app.apk
  fi
  if [ -n "$tarlink" ]; then
    rm $app.link
  fi

  popd > /dev/null
}

function app_restore() {
  app=$1

  echo "Restoring $app"

  if ! $DATAONLY; then
    pushd $BACKUPPATH > /dev/null
    debug 1 "unpacking apk"
    tar -xzf $app.tgz $app.apk || { error "failed to unpack apk"; exit -1; }
    debug 1 "installing apk"
    pm install $BACKUPPATH/$app.apk 2> /dev/null | grep "Success" || { error "failed to install apk"; rm $app.apk; exit -1; }
    rm $app.apk
    if $RELINK; then
      tar -xzf $app.tgz $app.link > /dev/null 2>&1 && {
        debug 1 "moving apk to sdcard and relinking"
        rm $app.link
        apk=$(app_get_apk "$app")
        apkbase=$(basename $apk)
        mv $apk /data/sdext2/$apkbase
        ln -s /data/sdext2/$apkbase $apk
      }
    fi
    popd > /dev/null
  fi

  app_get_apk $app > /dev/null || { error "app $app not found (failed to install?)"; exit -1; }
  [ -d /data/data/$app ] || { error "no data directory found"; exit -1; }
  uid=$(ls -lnd /data/data/$app | awk '{print $2}')
  gid=$(ls -lnd /data/data/$app | awk '{print $3}')

  pushd / > /dev/null
  debug 1 "unpacking data"
  tar -xzf $BACKUPPATH/$app.tgz data/data/$app
  debug 1 "fixing data permissions"
  find /data/data/$app/ -exec chown $uid.$gid {} \;
  chown $uid.$gid /data/data/$app
  popd > /dev/null

  if [ -d /storage/sdcard1/Android/data/$app ]; then
    debug 1 "fixing sdcard data permissions"
    chown  -R $uid /storage/sdcard1/Android/data/$app
  fi
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

TEMP=$(getopt -o bd::Dhp:rV --long backup,debug::,data-only,help,nolink,path:,restore,version -n "$(basename $0)" -- "$@")

[ $? == 0 ] || usage 1
eval set -- "$TEMP"

ACTION="none"
BACKUPPATH=/storage/sdcard1/aam_backup
DATAONLY=false
RELINK=true
while true ; do
  case "$1" in
    -b|--backup)    ACTION="backup" ;;
    -d|--debug)
      case "$2" in
        "")           DEBUG=2 ;;
        *)            DEBUG=$2 ;;
      esac
      shift ;;
    -D|--data-only) DATAONLY=true ;;
    -h|--help)      usage 0 ;;
    --nolink)       RELINK=false ;;
    -p|--path)      BACKUPPATH=$2; shift ;;
    -r|--restore)   ACTION="restore" ;;
    -V|--version)   version ;;
    --)             shift ; break ;;
    *)              error "Internal error!" ; exit 1 ;;
  esac
  shift
done

if [ -z "$1" ]; then
  usage 1;
fi

APPS=""
while [ -n "$1" ]; do
  if [ -z "$APPS" ]; then
    APPS=$1
  else
    APPS="$APPS $1"
  fi
  shift
done

if [ ! -d "$BACKUPPATH" ]; then
  mkdir "$BACKUPPATH"
fi

case "$ACTION" in
  backup)
    if [ "all" = "$APPS" ]; then
      APPS=$(apps_get_list)
    fi
    foreach app_backup $APPS
    am broadcast -a android.intent.action.MEDIA_MOUNTED -d file://$BACKUPPATH
    ;;
  restore)
    if [ "all" = "$APPS" ]; then
      APPS=$(ls $BACKUPPATH | sed -e "s/\(.*\).tgz/\1/")
    fi
    foreach app_restore $APPS
    ;;
  *)
    usage 1
    ;;
esac

exit 0
