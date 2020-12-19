#/bin/sh

NAME="$( basename "${0}"; printf a )"; NAME="${NAME%?a}"

show_help() {
  <<EOF cat - >&2
SYNOPSIS
  ${NAME} <subcommand1> [<subcommand> ...]

SUBCOMMANDS
  download      Downloads info and subs, not
  update        Incrementally update the output json
  force-update  Rebuild entire output json
  mark-done     Move the files from '\'
  help          Display this menu
EOF
}

NL='
'

ytdl() {
  youtube-dlc -4 "$@"
}

main() {
  MAKE_DIR="$( dirname "${0}"; printf a )"; MAKE_DIR="${MAKE_DIR%?a}"
  cd "${MAKE_DIR}" || exit "$?"
  MAKE_DIR="$( pwd -P; printf a )"; MAKE_DIR="${MAKE_DIR%?a}"


  OLD_DIR="./json"
  NEW_DIR="./new"
  SUB_DIR="./transcripts"
  OUT_DIR="./compiled"

  INTERIM="./output.json"
  FINAL="${OUT_DIR}/video.json"
  ARCHIVE="./archive.txt"
  ARCHIVE2="./archive2.txt"

  #'https://www.youtube.com/user/HeiJinZhengZhi'
  #'https://www.youtube.com/watch?v=wu-_H0O5zfM&list=UUWPKJM4CT6ES2BrUz9wbELw'
  #'https://www.youtube.com/watch?v=c7M-_hKL0Yw'

  #run: sh % download2
  mkdir -p "${NEW_DIR}" "${OLD_DIR}" "${SUB_DIR}" "${OUT_DIR}"
  _make "$@"
}

_make() {
  for arg in "$@"; do
    case "${arg}"
      in download)
        mkdir -p "${NEW_DIR}" "${SUB_DIR}"
        channel_url='https://www.youtube.com/user/HeiJinZhengZhi'
        download_by_channel "${channel_url}" "${NEW_DIR}" "${SUB_DIR}"
        download_playlists "${channel_url}"
      ;; download2)
        mkdir -p "${NEW_DIR}" "${SUB_DIR}"
        download_by_rss

      ;; update)            compile false
      ;; force-update)      compile true
      ;; mark-done)         for_each "${NEW_DIR}" move_to_old
      ;; help)              show_help
      ;; verify-have-subs)  verify_have_subs
      ;; supplement-subs)   supplement_subs
      ;; make-sample)
        jq '[limit(123; .[])]' "${FINAL}" >"../a-bas-le-ciel/video.json"
        cp "${PLAYLIST}" "../a-bas-le-ciel/playlist.json"

      ;; remotes)
        git remote remove origin     2>/dev/null
        git remote remove origin-ssh 2>/dev/null
        git remote add origin     'https://github.com/Aryailia/a-bas-le-ciel-data.git'
        git remote add origin-ssh 'git@github.com:Aryailia/a-bas-le-ciel-data.git'
        git remote --verbose

      ;; publish)
        publish="./publish"
        [ -n "$( git status --short )" ] && die FATAL 1 \
          "Please commit changes before updating"
        [ -d "${publish}" ] && die FATAL 1 \
          "The directory '${publish}' exists but was reserved"

        #_make compile mark-done
        cp -r "${OUT_DIR}" "${publish}"
        cp -r "${SUB_DIR}" "${publish}/"
        git branch --delete 'compiled' --force
        git add .
        git commit -m 'publishing compiled'
        git subtree split --prefix "publish" --branch='compiled'
        git reset HEAD^
        rm -r "${publish}"
        GIT_SSH_COMMAND="ssh -i ~/.ssh/a-bas-le-ciel-data -o StrictHostKeyChecking=no " \
          git push -f origin-ssh compiled

      ;; *)  die FATAL 1 "Inavlid command \`${NAME} ${arg}\`"
    esac
  done
  [ "$#" = 0 ] && { show_help; exit 1; }
}

move_to_old() {
  mv "${NEW_DIR}/${1}" "${OLD_DIR}/${1}" || exit "$?"
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
      gsub("^.*href=\"https://www.youtube.com/watch\?v=", "");
      gsub(/".*/, "");
      print $0;
    }'
  ); do
    if [ ! -e "${OLD_DIR}/${id}.info.json" ]; then
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
  # $1: channel url

  errors="errors.log"

  printf %s '' >"${errors}"
  ytdl --write-info-json --skip-download --ignore-errors \
    --write-auto-sub --sub-lang en
    --download-archive "${ARCHIVE}" \
    --output "${2}/%(id)s" \
    "${1}" \
    2>>"${errors}"
  move_subs_from_to "${NEW_DIR}" "${SUB_DIR}"
}


_playlists_to_json() {
  printf %s '['
  <&0 sed 's/$/,/' | sed '$s/,$//'
  printf %s ']'
}
download_playlists() {
  #$1: channel url
  ytdl --ignore-errors --dump-json --flat-playlist \
    "${1}/playlists" \
    | _playlists_to_json \
    | jq 'sort_by(.title)' >"${OUT_DIR}/playlist.json"

}

################################################################################
compile() {
  # $1: true/false, true to remake from scratch (parse all of ${OLD_DIR})
  #VIDEO_DIR="json"
  #####
  # Update ${FINAL}
  if "${1}" || [ ! -e "${INTERIM}" ]
    then _is_recompile='true'
    else _is_recompile='false'
  fi
  if "${_is_recompile}"; then
    errln "Extracting video json '${OLD_DIR}' -> '${INTERIM}'"
    extract "${OLD_DIR}" >"${INTERIM}" || exit "$?"
  elif [ -e "${FINAL}" ]; then
    errln "Updating old video json '${FINAL}' -> '${INTERIM}'"
    cp "${FINAL}" "${INTERIM}" || exit "$?"
  fi
  errln "Outputting to '${OUT_DIR}/video.json'"
  mkdir -p "${OUT_DIR}" "${NEW_DIR}"
  join "${INTERIM}" "${NEW_DIR}" >"${OUT_DIR}/video.json"

  #####
  # Update ${ARCHIVE}
  # Walk dir instead of using jq on ${FINAL} to skip videos also
  # archive vidoes not uploaded by uploader
  errln "Archive before: $( <"${ARCHIVE}" wc -l ) entries"
  format_to_archive() { printf %s\\n "youtube ${1%.info.json}"; }
  {
    if "${_is_recompile}" || [ ! -e "${ARCHIVE}" ]
      then for_each "${OLD_DIR}" format_to_archive
      else cat "${ARCHIVE}"
    fi
    for_each "${NEW_DIR}" format_to_archive
  } | sort | uniq >"${ARCHIVE2}"
  mv "${ARCHIVE2}" "${ARCHIVE}"
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
format_json() {
  jq '.
    | select(.uploader_id == "HeiJinZhengZhi" )
    | {
      id: .id,
      url: .webpage_url,
      upload_date: .upload_date,
      title: .title,
      description: .description,
      # There are two relevant fields ".thumbnail" and ".thumbnails"
      thumbnail: .thumbnails | map(select(.width == 336))[0].url,
    }
  ' "${1}"
}

extract() {
  delim=''  # Because we are doing a join, avoid initial comma
  count='0'

  printf %s "["
  for filename in "${1}"/* "${1}"/.[!.]* "${1}"/..?*; do
    [ ! -f "${filename}" ] && continue
    count="$(( count + 1 ))"
    printf %s\\n "Processing ${count}: ${filename##*/}" >&2

    extracted="$( format_json "${filename}"  )"

    if [ -n "${extracted}" ]; then
      printf %s "${delim}"
      delim=','
      printf %s "${extracted}"
    fi
  done
  printf %s "]"
}

join() {
  # $1: old output.json
  # $2: directory for newely download
  [ -d "${2}" ] || die FATAL 1 "Invalid directory '${2}' for newly downloaded"
  {
    printf '['
    cat "${1}"
    printf %s ','
    extract "${2}"
    printf %s ']'
  } | jq '.[0] + .[1] | sort_by(.upload_date) | reverse'
}

################################################################################
verify_have_subs() {
  [ -r "${FINAL}" ] || die FATAL 1 "Missing '${FINAL}'" \
    ". Run \`${NAME} download update\`"

  count='0'
  for sub in "${SUB_DIR}"/* "${SUB_DIR}"/.[!.]* "${SUB_DIR}"/..?*; do
    [ -e "${sub}" ] || continue
    id="${sub##*/}"
    id="${id%.en.vtt}"
    if [ ! -e "${OLD_DIR}/${id}.info.json" ]; then
      count="$(( count + 1 ))"
      errln "${count}: '${sub}' has no corresponding info in '${OLD_DIR}'"
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
