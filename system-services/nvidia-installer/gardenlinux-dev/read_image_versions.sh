#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

main() {

  if [ -z ${GARDENLINUX_VERSION+x} ]; then
    >&2 echo "GARDENLINUX_VERSION must be set"
    exit 1
  fi

  # Get the build arg names from the first line of `image_versions`
  # (`sed '/^#.*$\|^\s*$/d' image_versions` first removes any comment or empty lines)
  build_arg_names=($(\
    sed '/^#.*$\|^\s*$/d' image_versions | \
    head -n 1 | \
    cut -d '|' -f 1- --output-delimiter=' '
  ))
  # Loop from line 2 of `image_versions` onwards to find the line for this Gerden Linux version,
  # then process the build arg values in each line
  sed '/^#.*$\|^\s*$/d' image_versions | \
    tail -n +2 | \
    while IFS="" read -r p || [ -n "$p" ]; do
      line=$(printf '%s\n' "$p")
      build_arg_values=($(echo "$line" | cut -d '|' -f 1- --output-delimiter=' '))
      i=0
      declare -A build_args
      for arg_name in "${build_arg_names[@]}";
      do
        build_args[$arg_name]=${build_arg_values[$i]}
        ((i+=1))
      done
      if [ "${GARDENLINUX_VERSION}" == ${build_args[GARDENLINUX_VERSION]} ]; then
        # This is the correct version, so dump the dictionary as a list of "key=value" lines, then exit
        for key in "${!build_args[@]}"; do
          echo "$key=${build_args[$key]}"
        done
        exit 0
      fi
    done

}

log() {
  echo -e "\033[1;32m[+] $*\033[0m"
}

main "$@"