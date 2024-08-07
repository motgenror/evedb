export def format-table [] {
  each {
    transpose key value
    | update value {
        let type = ($in | describe)
        if $type =~ '(int|float)' {
          format-num
        } else if $type =~ '^table' {
          format-table
        } else if $type == 'list<any>' {
          # todo
        } else {
          $in
        }
      }
    | transpose -rdi
  }
}

export def format-num [] {
  let num = $in
  def format-int [] {
    split chars
    | reverse
    | chunks 3
    | each { str join }
    | str join ","
    | str reverse
  }
  match ($num | describe) {
    "int" => { $num | into string | format-int }
    "float" => {
      $num
      | into string
      | do {
          let parts = $in | split row "."
          let intpart = $parts | first
          let floatpart = $parts | last
          $'($intpart | format-int).($floatpart)'
      }
    }
  }
}

export def load-cache [cachefile: path, varname: string, loader: closure] {
  print -en $'- Loading ($varname)'
  if ($cachefile | path exists) {
    print -e ' (cached)'
    open $cachefile
  } else {
    print -e ''
    do $loader | tee { save $cachefile }
  }
}

export def convert-value [unitID: int] {
  let input = $in
  let expiry_anchor = ('1970-01-01' | into datetime)
  $input | match $unitID {
    115 => { into int } # groupID
    116 => { into int } # typeID
    119 => { into int } # attributeID
    129 => { $'($in)hr' | into duration } # hours
    136 => { into int } # slot
    137 => { into bool } # boolean
    139 => { into bool } # plus sign
    141 => { into int } # hardpoints
    142 => { into int } # 1=Male 2=Unisex 3=Female
    143 => { $expiry_anchor + ($'($in)day' | into duration) } # days since UNIX epoch
    _ => { $in }
  }
}

export def xray [
  comment
  --length (-l) # output input's length
] {
  let input = $in

  print -en $'- ($comment): '

  if $length {
    print -e ($input | length | into string)
    return $input
  }

  let inputtype = $input | describe
  if $inputtype =~ '^(list|table|record)' {
    print -e $"\n($input | table)"
  } else {
    print -e $"($input)"
  }
  $input
}

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
