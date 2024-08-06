export def wrap-bin [] {
  wrap text | insert bin { |row| $row.text | into binary }
}

export def str-wrap [
  --wrap-at: number = 20
] {
  str replace -a "\r\n" "\n"
    | str replace -a "\n" " SINGLENEWLINE "
    | str trim
    | split row -r "\\s+"
    | reduce -f { joined: '' count: 0 } { |word, state|
        if ($word == "\n") {
          {
            joined: ($state.joined + "\n")
            count: 0
          }
        } else if ($state.count < $wrap_at) {
          if ($state.joined | is-empty) {
            {
              joined: $word
              count: ($word | str length)
            }
          } else {
            {
              joined: ($state.joined + ' ' + $word)
              count: ($state.count + 1 + ($word | str length))
            }
          }
        } else {
          {
            joined: ($state.joined + "\n" + $word)
            count: 0
          }
        }
      }
    | get joined
    | str replace -ar "\\s*SINGLENEWLINE\\s*" "\n"
}

# To be used inside of an `each`, only update a column (key) if it exists.
export def smart-update [key: string, op: closure] {
  if ($key in $in) {
    update $key { if ($in != null) { do $op } else { null } }
  } else {}
}

# Gets the first available column (key).
export def smart-get [
  --empty-as-missing (-e) # treat empty values as missing columns
  ...keys
] {
  let input = $in
  if ($input | is-empty) {
    return ''
  }
  let result = $keys | reduce -f null { |key, acc|
    if ($acc == null) {
      if $key in ($input | columns) {
        let value = try { $input | get $key } catch { |err|
          error make { msg: $'($key) not found in ($input | to json)' }
        }
        if ($empty_as_missing and ($value | is-empty)) {
          $acc
        } else {
          $value
        }
      } else {
        $acc
      }
    } else {
      $acc
    }
  }
  if $result == null {
    error make { msg: $'no values found for keys ($keys)' }
  }
  $result
}

export def load-units [] {
  let filename = '.dogmaunits.json'
  $filename | path exists | if not $in {
    http get 'https://sde.hoboleaks.space/tq/dogmaunits.json' | save $filename
  }
  open --raw $filename | from json | transpose unitID data | flatten | update unitID { into int }
}

export def left-join [
  other: list<any>
  join_on: string
] {
  upsert $join_on { default null } # workaround for the `join -l` bug that removes rows
    | join -l $other $join_on
}
