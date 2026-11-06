algorithm=$1
gap=$2
shortcuts=$3
dir="${XDG_CONFIG_HOME:-$HOME/.config}/plasmazones"
mkdir -p "$dir"

# merge <file> <base-json> <jq args...>: never fails the service, so the daemon still starts.
merge() {
  local file=$1 input=$2
  shift 2
  if [[ -s $file ]]; then
    if ! jq empty "$file" 2>/dev/null; then
      echo "icedos-plasmazones-merge: $file is not valid JSON, leaving it alone" >&2
      return 0
    fi
    [[ -e $file.icedos-pre-tiling ]] || cp -- "$file" "$file.icedos-pre-tiling"
    input=$(cat "$file")
  fi

  local tmp
  tmp=$(mktemp "$file.tmp.XXXXXX")
  if jq "$@" <<<"$input" >"$tmp"; then
    mv -- "$tmp" "$file"
  else
    rm -f -- "$tmp"
    echo "icedos-plasmazones-merge: could not update $file" >&2
  fi
}

merge "$dir/config.json" '{}' \
  --arg algorithm "$algorithm" \
  --argjson gap "$gap" \
  --slurpfile shortcuts "$shortcuts" \
  '. * {
    Tiling: {
      Enabled: true,
      Algorithm: {
        Default: $algorithm,
        SplitRatio: 0.5,
        PerAlgorithmSettings: {($algorithm): {splitRatio: 0.5}}
      },
      Behavior: {OverflowBehavior: 1, DragBehavior: 1}
    },
    Gaps: {Inner: $gap, Outer: $gap},
    Shortcuts: $shortcuts[0]
  }'

merge "$dir/rules.json" '{"_version":4,"rules":[]}' \
  --arg algorithm "$algorithm" \
  '._version = 4
  | .rules = (((.rules // []) | map(select(any(.actions[]?; .type == "setEngineMode") | not))) + [{
      id: "{5b1f0c52-3a7e-4d19-9c7e-1c0de7a11e55}",
      name: "IceDOS: tile every window",
      enabled: true,
      priority: 0,
      match: {all: []},
      actions: [
        {type: "setEngineMode", mode: "autotile"},
        {type: "setTilingAlgorithm", algorithm: $algorithm}
      ]
    }])'

exit 0
