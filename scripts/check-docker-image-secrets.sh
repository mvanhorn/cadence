#!/usr/bin/env bash

set -euo pipefail

readonly PRIVATE_KEY_PATTERN='-----BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'
readonly CREDENTIALS_PATH='etc/cadence/credentials'

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <image>" >&2
  exit 2
fi

readonly image="$1"
archive_dir="$(mktemp -d)"
trap 'rm -rf "${archive_dir}"' EXIT

docker image inspect "${image}" >/dev/null
docker image save --output "${archive_dir}/image.tar" "${image}"
tar -xf "${archive_dir}/image.tar" -C "${archive_dir}"
rm "${archive_dir}/image.tar"

mapfile -d '' layer_archives < <(
  find "${archive_dir}" -type f -name layer.tar -print0
)
if [[ ${#layer_archives[@]} -eq 0 ]]; then
  echo "No image layers found while checking ${image}" >&2
  exit 1
fi

for layer_archive in "${layer_archives[@]}"; do
  if grep -aEq -- "${PRIVATE_KEY_PATTERN}" "${layer_archive}"; then
    echo "Private key material found in an image layer of ${image}" >&2
    exit 1
  fi

  tar -tf "${layer_archive}" >"${archive_dir}/layer-contents.txt"
  if grep -Eq "^\.?/?${CREDENTIALS_PATH}(/|$)" "${archive_dir}/layer-contents.txt"; then
    echo "/${CREDENTIALS_PATH} found in an image layer of ${image}" >&2
    exit 1
  fi
done

echo "No private key material found in image layers of ${image}"
