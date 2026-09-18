#!/bin/bash

# Description:
#   This script backs up a part of a Grav installation. If its contents differ
#   from the previous run a new .tar.gz is saved; earlier ones are kept, so the
#   timestamps in the filenames form a history.
#   A site is normally split into two parts: the variable part ('user/', which
#   holds content, configuration and whatever visitors submit) and the fixed part
#   (the Grav core, archived with -d . and the variable directories excluded).
#   Optionally, tar and tar.gz files can be saved in different locations.
# ./grav_user_backup.sh -g /home/joppe/digitect.nl/grav -b /private/backup/grav/prod25.digitect.nl/daily -t /mnt/backups/grav/tar -s mysite

# Version, bumped on every change (see README.md). Deployments compare it with this
# repository, so a changed script without a new number shows up as a difference.
#   1.0  first numbered version
VERSION="1.0"

usage() {
  echo "Usage: $0 -g /path/to/grav -b /path/to/gz-backups [-t /path/to/tar-backups] [-s sitename] [-d subdir] [-n name] [-x \"excludes\"] [-r partname]"
  echo
  echo "  -g GRAV_PATH"
  echo "    Path to the Grav installation (must contain a 'user/' folder)."
  echo "  -b BACKUP_PATH"
  echo "    Path to the directory where .tar.gz backups should be stored."
  echo "  -t TAR_PATH (optional)"
  echo "    Optional path to store the .tar file separately (default: same as BACKUP_PATH)."
  echo "  -d SUBDIR"
  echo "    Directory inside the Grav path to archive (default: user). Use '.' to archive"
  echo "    the whole Grav root, which is how the fixed part is captured."
  echo "  -n NAME"
  echo "    Name of this part in the filename (default: the subdir, or 'core' for '.')."
  echo "    Two parts of the same site must have different names or they overwrite"
  echo "    each other's reference tar."
  echo "  -x \"NAME NAME ...\""
  echo "    Space-separated names to leave out. Only useful with -d '.', to keep the"
  echo "    variable and the regenerable directories out of the fixed part."
  echo "  -r PARTNAME (optional)"
  echo "    Also record, in this part's .recent file, the newest stored backup of"
  echo "    that other part. Use '-r core' on the variable part to note which fixed"
  echo "    part it belongs with, so a restore does not have to guess."
  echo "  -s SITENAME (optional)"
  echo "    Optional name to include in the backup filename (default: derived from GRAV_PATH)."
  exit 1
}

readargs() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -g) grav_path="$2"; shift 2 ;;
      -b) backup_path="$2"; shift 2 ;;
      -t) tar_path="$2"; shift 2 ;;
      -d) subdir="$2"; shift 2 ;;
      -n) partname="$2"; shift 2 ;;
      -x) excludes="$2"; shift 2 ;;
      -r) refpart="$2"; shift 2 ;;
      -s) sitename="$2"; shift 2 ;;
      *) echo "Unknown option or argument $1."; usage ;;
    esac
  done
}

checkargs() {
  if [ -z "$grav_path" ] || [ -z "$backup_path" ]; then
    echo "Missing required arguments."
    usage
  fi
}

setargs() {
  timestamp=$(date +"%Y%m%d-%H%M%S")
  tmp_dir=$(mktemp -d)
  # Standaard user/, want dat is bij Grav de map met inhoud, configuratie en
  # accounts. Met -d kun je een andere map archiveren.
  if [ -z "${subdir:-}" ]; then subdir="user"; fi
  user_dir="$grav_path/$subdir"
  # De naam in het bestand mag geen '.' zijn; die staat voor de hele wortel.
  if [ -z "${partname:-}" ]; then
    if [ "$subdir" = "." ]; then partname="core"; else partname="$subdir"; fi
  fi
  # Uitsluitingen omzetten naar --exclude-opties voor tar.
  tar_excludes=""
  for e in ${excludes:-}; do tar_excludes="$tar_excludes --exclude=./$e"; done

  if [ -z "$sitename" ]; then
    sitename=$(basename "$grav_path")
  fi

  if [ -z "$tar_path" ]; then
    tar_path="/private/backup/daily/${sitename}"
  fi

  mkdir -p "$backup_path" "$tar_path"

  base_filename="${timestamp}-${sitename}-${partname}"
  new_tar="$tmp_dir/${base_filename}.tar"
  new_tar_gz="$tmp_dir/${base_filename}.tar.gz"
  recent_file="$tar_path/${sitename}-${partname}.recent"
}

# Naam van de nieuwste opgeslagen .tar.gz van een deel van deze site. Leeg als
# dat deel nog nooit is weggeschreven.
newest_backup_of() {
  local part="$1" newest
  newest=$(find "$backup_path" -maxdepth 1 -name "*-${sitename}-${part}.tar.gz" | sort | tail -n 1)
  [ -n "$newest" ] && basename "$newest"
}

# Het .recent-bestand beschrijft de stand van zaken van dit deel: wanneer er
# voor het laatst is gekeken, welke backup de nieuwste is, en - als -r is
# meegegeven - bij welke backup van het andere deel die hoort. Zonder die
# verwijzing moet je bij een herstel zelf uitzoeken welk vast deel bij welk
# variabel deel past.
write_recent() {
  local newest ref
  newest=$(newest_backup_of "$partname")
  {
    echo "# ${sitename}, part '${partname}' - written by $(basename "$0")"
    echo "checked=$(date +"%Y-%m-%d %H:%M:%S")"
    echo "backup=${newest:-none}"
    if [ -n "${refpart:-}" ]; then
      ref=$(newest_backup_of "$refpart")
      echo "${refpart}=${ref:-none}"
    fi
  } > "$recent_file"
}

checkvalues() {
  if [ ! -d "$grav_path" ]; then
    echo "Grav path '$grav_path' does not exist."
    exit 2
  fi

  if [ ! -d "$user_dir" ]; then
    echo "Directory '$subdir' not found in Grav path '$grav_path'."
    exit 2
  fi
}

main() {
  echo "Creating tar of '$user_dir'..."
  tar -cf "$new_tar" -C "$grav_path" $tar_excludes "$subdir"

  latest_tar=$(find "$tar_path" -name "*${sitename}-${partname}.tar" | sort | tail -n 1)

  if [[ -z "$latest_tar" ]]; then
    echo "No previous backup found. Saving new backup."
    cp "$new_tar" "$tar_path/"
    gzip -c "$new_tar" > "$backup_path/$(basename "$new_tar_gz")"
  else
    echo "Diffing against latest backup: $latest_tar"
    tar -tvf "$new_tar" > "$tmp_dir/new_list.txt"
    tar -tvf "$latest_tar" > "$tmp_dir/old_list.txt"

    if ! diff -q "$tmp_dir/old_list.txt" "$tmp_dir/new_list.txt" > /dev/null; then
      echo "Changes detected. Saving new backup, keeping the previous one."
      # De oude .tar.gz blijft staan: de naam bevat een tijdstempel, dus je houdt
      # vanzelf een reeks. Alleen de referentie-tar wordt vervangen, want daar is er
      # per definitie maar een van nodig - die dient om te zien of er iets wijzigde.
      rm -f "$latest_tar"

      cp "$new_tar" "$tar_path/"
      gzip -c "$new_tar" > "$backup_path/$(basename "$new_tar_gz")"
    else
      echo "No changes detected. Backup skipped."
    fi
  fi

  # Ook bijwerken als er niets veranderde: dan blijft zichtbaar dat er is
  # gekeken, en verschuift de verwijzing mee als het andere deel wel wijzigde.
  write_recent
  echo "State written to $recent_file"

  rm -rf "$tmp_dir"
}

readargs "$@"
checkargs
setargs
checkvalues
main
