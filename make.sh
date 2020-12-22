#/bin/sh

NAME="$( basename "${0}"; printf a )"; NAME="${NAME%?a}"

show_help() {
  <<EOF cat - >&2
SYNOPSIS
  ${NAME} <subcommand1> [<subcommand> ...]

SUBCOMMANDS
  help              Display this menu
  download-channel  ownloads info and subs, not
  download-rss      Downloads info and subs, not
  compile           Incrementally update the output json
  force-compile     Rebuild entire output json
  mark-done         Move the files from '\'
  clean-publish
  compile
  force-compile
  verify-have-subs
  supplement-subs
  cron
  sample
  prepare-publish
  publish           For manual publishing
EOF
}

NL='
'

# --write-auto-sub not working in newest youtube-dl (15 Dec 2020)
# BUG: 'youtube-dlc' does not provide title or id for playlists download
# TODO: fix when youtube-dl fixes itself
ytdl() {
  youtube-dlc -4 "$@" || exit "$?"
}

main() {
  MAKE_DIR="$( dirname "${0}"; printf a )"; MAKE_DIR="${MAKE_DIR%?a}"
  cd "${MAKE_DIR}" || exit "$?"
  MAKE_DIR="$( pwd -P; printf a )"; MAKE_DIR="${MAKE_DIR%?a}"

  INFO_DIR="./json"
  NEW_DIR="./new"
  SUB_DIR="./subtitles"
  PUBLISH="./publish"

  INTERIM="./output.json"
  FINAL="${PUBLISH}/video.json"
  PLAYLIST="${PUBLISH}/playlist.json"
  ARCHIVE="./archive.txt"

  CHANNEL_URL='https://www.youtube.com/user/HeiJinZhengZhi'

  #'https://www.youtube.com/user/HeiJinZhengZhi'
  #'https://www.youtube.com/watch?v=wu-_H0O5zfM&list=UUWPKJM4CT6ES2BrUz9wbELw'
  #'https://www.youtube.com/watch?v=c7M-_hKL0Yw'

  # implement flags (force flag)

  #run: sh % cron
  mkdir -p "${NEW_DIR}" "${INFO_DIR}" "${SUB_DIR}" "${PUBLISH}"
  _make "$@"
}

_make() {
  for arg in "$@"; do
    errln "Running \`${NAME} ${arg}\`"
    case "${arg}"
      in help)                    show_help

      ;; download-channel)        download_by_channel
      ;; download-rss)            download_by_rss
      ;; download-playlist-list)  download_playlist_list
      ;; compile)                 node parse-info.mjs "${INFO_DIR}" "${FINAL}"
      ;; mark-done)               mark_done
      ;; verify-have-subs)        verify_have_subs
      ;; supplement-subs)         supplement_subs
      ;; publish)                 _make prepare-publish; push_subtree 'compiled'
      ;; clean-publish)           rm -r "${PUBLISH}"; git checkout "${PUBLISH}"

      ;; cron)
        # 'mark-done' will skip the 'publish' step if no new files
        _make download-rss download-playlist-list mark-done || exit "$?"
        git add "${INFO_DIR}" "${SUB_DIR}" "${PUBLISH}"
        git commit -m "update $( date "+%Y-%m-%d" )"
        git push origin master

      ;; sample)
        _make compile
        jq '[limit(123; .[])]' "${FINAL}" >"../a-bas-le-ciel/video.json"
        cp "${PLAYLIST}" "../a-bas-le-ciel/playlist.json"

      ;; prepare-publish)
        rm -r "${PUBLISH}/transcripts" 2>/dev/null
        node './parse-subs.mjs' "${SUB_DIR}" "${PUBLISH}/transcripts.json"
        _make compile



      ;; *)  die FATAL 1 "Inavlid command \`${NAME} ${arg}\`"
    esac

    [ "$#" = 0 ] || errln ''
  done
  # need 'if' to exit with 0 on no error
  if [ "$#" = 0 ]; then show_help; exit 1; fi
}

## Github uses the actions on the branch that is being pushed
## Thus '.github/workflows' exists within ${PUBLISHED}
## See: https://stackoverflow.com/questions/64565482
# old example:
#ssh_push_subtree compiled "./compiled" 'a-bas-le-ciel-data' \
#  'git@github.com:Aryailia/a-bas-le-ciel-data.git' \
#  parse_subs_to_transcripts \
## end
push_subtree() {
  # $1: branch name

  # Not using these anymore
  # 1: the directory
  # 2: the branch name
  # 3: private key name
  # 4: remote ssh url tag

  [ -n "$( git status --short )" ] && die FATAL 1 \
    "Please commit changes before updating"

  rm .gitignore  # Allow all of ${PUBLISH} to be pushed
  git branch --force --delete "${1}" 2>/dev/null
  git add "${PUBLISH}"
  git commit -m "publishing $( date "+%Y-%m-%d" )" || exit "$?"  # no changes
  git subtree split --prefix "${PUBLISH#./}" --branch="${1}"
  git reset HEAD^
  git push --force origin "${1}"

  # Clean up
  rm -r "${PUBLISH}"
  git checkout .gitignore "${PUBLISH}"

  #settings="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  #GIT_SSH_COMMAND="ssh -i '${HOME}/.ssh/${3}' ${settings}" \
  #  git push -f "${4}" "${2}"
}


################################################################################
move_subs_from_to() {
  for path in "${1}"/* "${1}"/.[!.]* "${1}"/..?*; do
    [ -e "${path}" ] || continue
    if [ "${path}" != "${path%.vtt}" ]; then
      mv "${path}" "${2}/"
    fi
  done
}

# Clears error log everytime this runs
download_by_rss() {
  errors="errors.log"
  printf %s '' >"${errors}"

  for id in $(
    # so this fits on one line
    rss='https://www.youtube.com/feeds/videos.xml?channel_id='
    errln "Curling channel rss feed..."

    curl -L "${rss}UCWPKJM4CT6ES2BrUz9wbELw" \
      | awk '$0 ~ "<link.*href=\"https://www.youtube.com/watch" {
        gsub(".*href=\"https://www\\.youtube\\.com/watch\\?v=", "");
        gsub("\"/>$", "");
        print $0;
      }'
  ); do
    [ "${#id}" != '11' ] && die FATAL 1 "Parse error of RSS feed: '${id}'"
    if [ ! -e "${INFO_DIR}/${id}.info.json" ]; then
      ytdl --write-info-json --skip-download --ignore-errors \
        --sub-lang en --write-auto-sub \
        --output "${NEW_DIR}/%(id)s" \
        "https://www.youtube.com/watch?v=${id}" \
      2>>"${errors}"
    fi
  done
  move_subs_from_to "${NEW_DIR}" "${SUB_DIR}"
}

# Clears error log everytime this runs
download_by_channel() {
  errors="errors.log"

  printf %s '' >"${errors}"
  ytdl --write-info-json --skip-download --ignore-errors \
    --write-auto-sub --sub-lang en \
    --download-archive "${ARCHIVE}" \
    --output "${NEW_DIR}/%(id)s" \
    "${CHANNEL_URL}" \
    2>>"${errors}"
  move_subs_from_to "${NEW_DIR}" "${SUB_DIR}"
}

download_playlist_list() {
  # BUG: 'youtube-dlc' does not provide title or id
  # See: https://github.com/blackjack4494/yt-dlc/issues/288
  # TODO: Fix when this issue is resolved (should be resolved soon)
  dump="$( youtube-dl -4 --ignore-errors --dump-json --flat-playlist \
    "${CHANNEL_URL}/playlists" )" || exit "$?"
  printf %s\\n "${dump}" | jq --slurp 'sort_by(.title)' >"${PLAYLIST}"
}

################################################################################
mark_done() {
  #####
  count='0'
  for file in "${NEW_DIR}"/* "${NEW_DIR}"/.[!.]* "${NEW_DIR}"/..?*; do
    [ -e "${file}" ] || continue
    count="$(( count + 1 ))"
  done
  [ "${count}" = '0' ] && die "No files in '${NEW}' processed" 1

  errln "Archive before: $( <"${ARCHIVE}" wc -l ) entries"
  move_to_old() { mv "${NEW_DIR}/${1}" "${INFO_DIR}/${1}" || exit "$?"; }
  for_each "${NEW_DIR}" move_to_old
  format_to_archive() { printf %s\\n "youtube ${1%.info.json}"; }
  for_each "${INFO_DIR}" format_to_archive | sort | uniq >"${ARCHIVE}"
  errln "Archive after:  $( <"${ARCHIVE}" wc -l ) entries"
}

for_each() {
  _dir="${1}"
  shift 1
  for f in "${_dir}"/* "${_dir}"/.[!.]* "${_dir}"/..?*; do
    [ ! -f "${f}" ] && continue
    _name="${f##*/}"
    "$@" "${_name}"
  done
}
# replaced this with a node application
# $ compile true
# $ compile false
#compile() {
#  # $1: true/false, true to remake from scratch (parse all of ${INFO_DIR})
#  #VIDEO_DIR="json"
#  #####
#  # Update ${FINAL}
#  if "${1}" || [ ! -e "${INTERIM}" ]
#    then _is_recompile='true'
#    else _is_recompile='false'
#  fi
#  if "${_is_recompile}"; then
#    errln "Extracting video json '${INFO_DIR}' -> '${INTERIM}'"
#    extract "${INFO_DIR}" >"${INTERIM}" || exit "$?"
#  elif [ -e "${FINAL}" ]; then
#    errln "Updating old video json '${FINAL}' -> '${INTERIM}'"
#    #cp "${FINAL}" "${INTERIM}" || exit "$?"
#  fi
#  errln "Outputting to '${OUT_DIR}/video.json'"
#  join "${INTERIM}" "${NEW_DIR}" >"${OUT_DIR}/video.json"
#
#  #####
#  # Update ${ARCHIVE}
#  # Walk dir instead of using jq on ${FINAL} to skip videos also
#  # archive vidoes not uploaded by uploader
#  errln "Archive before: $( <"${ARCHIVE}" wc -l ) entries"
#  format_to_archive() { printf %s\\n "youtube ${1%.info.json}"; }
#  {
#    if "${_is_recompile}" || [ ! -e "${ARCHIVE}" ]
#      then for_each "${INFO_DIR}" format_to_archive
#      else cat "${ARCHIVE}"
#    fi
#    for_each "${NEW_DIR}" format_to_archive
#  } | sort | uniq >"${ARCHIVE2}"
#  mv "${ARCHIVE2}" "${ARCHIVE}"
#  errln "Archive after:  $( <"${ARCHIVE}" wc -l ) entries"
#}
#
#format_json() {
#  jq '.
#    | select(.uploader_id == "HeiJinZhengZhi" )
#    | {
#      id: .id,
#      url: .webpage_url,
#      upload_date: .upload_date,
#      title: .title,
#      description: .description,
#      # There are two relevant fields ".thumbnail" and ".thumbnails"
#      thumbnail: .thumbnails | map(select(.width == 336))[0].url,
#    }
#  ' "${1}"
#}
#
#extract() {
#  delim=''  # Because we are doing a join, avoid initial comma
#  count='0'
#
#  printf %s "["
#  for filename in "${1}"/* "${1}"/.[!.]* "${1}"/..?*; do
#    [ ! -f "${filename}" ] && continue
#    count="$(( count + 1 ))"
#    printf %s\\n "Processing ${count}: ${filename##*/}" >&2
#
#    extracted="$( format_json "${filename}"  )"
#
#    if [ -n "${extracted}" ]; then
#      printf %s "${delim}"
#      delim=','
#      printf %s "${extracted}"
#    fi
#  done
#  printf %s "]"
#}
#
#join() {
#  # $1: old output.json
#  # $2: directory for newely download
#  [ -d "${2}" ] || die FATAL 1 "Invalid directory '${2}' for newly downloaded"
#  extract "${2}" | jq \
#    '.[0] + .[1] | sort_by(.upload_date) | reverse' \
#    --slurp  "${1}" - \
#  # end
#}

################################################################################
verify_have_subs() {
  [ -r "${FINAL}" ] || die FATAL 1 "Missing '${FINAL}'" \
    ". Run \`${NAME} download update\`"

  count='0'
  for sub in "${SUB_DIR}"/* "${SUB_DIR}"/.[!.]* "${SUB_DIR}"/..?*; do
    [ -e "${sub}" ] || continue
    id="${sub##*/}"
    id="${id%.en.vtt}"
    if [ ! -e "${INFO_DIR}/${id}.info.json" ]; then
      count="$(( count + 1 ))"
      errln "${count}: '${sub}' has no corresponding info in '${INFO_DIR}'"
    fi
  done
  [ "${count}" != '0' ] && die FATAL 1 "${count} extra transcript files" \
    "Perhaps you forgot run \`${NAME} mark-done\`"

  list=''
  for id in $( jq --raw-output '.[].id' "${FINAL}" ); do
    [ -e "${SUB_DIR}/${id}.en.vtt" ] || list="${list}${id}${NL}"
  done

  if [ -n "${list}" ]; then
    count='0'
    for id in ${list}; do
      count="$(( count + 1 ))"
      [ -e "${SUB_DIR}/${id}.en.vtt" ] || errln "${count}: ${id} has no en sub"
    done
    die FATAL 1 "Missing ${count} transcripts" \
      "Download missing ones with \`${NAME} supplement-subs\`"
  else
    errln "Seem to have adequate number of transcripts"
  fi
}

supplement_subs() {
  [ -r "${FINAL}" ] || die FATAL 1 "Missing '${FINAL}'" \
    ". Run \`${NAME} download update\`"

  list=''
  for id in $( jq --raw-output '.[].id' "${FINAL}" ); do
    [ -e "${SUB_DIR}/${id}.en.vtt" ] || list="${list}${id}${NL}"
  done

  if [ -n "${list}" ]; then
    count='0'
    for id in ${list}; do
      count="$(( count + 1 ))"
      [ -e "${SUB_DIR}/${id}.en.vtt" ] || ytdl \
        --write-auto-sub --skip-download --ignore-errors \
        --output "${SUB_DIR}/%(id)s" \
        "https://www.youtube.com/watch?v=${id}" \
      # end
    done
    verify_have_subs
  fi
}


errln() { printf %s\\n "$@" >&2; }
die() { printf %s "${1}: " >&2; shift 1; printf %s\\n "$@" >&2; exit "${1}"; }

main "$@"
